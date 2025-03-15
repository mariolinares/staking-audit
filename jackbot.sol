// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Import de Chainlink VRF v2
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

contract BSCJackpot is VRFConsumerBaseV2, ReentrancyGuard, Ownable, Pausable {
    using SafeERC20 for IERC20;

    // ------------------------------
    //    Chainlink VRF variables
    // ------------------------------
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;

    // ID de la suscripción en Chainlink VRF v2 (lo creas en https://vrf.chain.link/)
    uint64 private immutable i_subscriptionId;

    // Gas lane (o keyHash), determina el límite de gas que costará la llamada de retorno
    bytes32 private immutable i_gasLane;

    // Límite de gas que usará Chainlink para llamar fulfillRandomWords
    uint32 private immutable i_callbackGasLimit;

    // Cantidad de números aleatorios que solicitaremos (1 en nuestro caso)
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint16 private constant NUM_WORDS = 1;

    // requestId -> lotteryId
    mapping(uint256 => uint256) private requestIdToLotteryId;

    // ------------------------------
    //       Lotería variables
    // ------------------------------
    // Comisiones
    uint256 public managerFeePercent = 15;
    uint256 public ownerFeePercent = 15;
    uint256 public constant MAX_FEE_PERCENT = 30; // límite máximo

    // Tarifas fijas en BNB (forzadas)
    uint256 public participationFeeInBNB = 0.001 ether;
    uint256 public withdrawFeeInBNB = 0.001 ether;

    // Estado de la lotería
    enum LotteryStatus {
        ONGOING,
        COMPLETED,
        CANCELLED
    }

    struct Lottery {
        string uuid;
        string name;
        address lotteryManager;
        address[] participants;
        uint256 totalJackpot;
        uint256 ticketPrice;
        address tokenAddress;
        uint256 closingTime;
        uint256 maxParticipants;
        uint256 minParticipants;
        address winnerAddress;
        LotteryStatus status;
    }

    Lottery[] public lotteries;
    mapping(string => uint256) private uuidToIndex;

    // Para "pull refunds" en caso de cancelación
    mapping(string => mapping(address => uint256)) public refunds;

    // UUID generator
    uint256 private nonce = 0;

    // Eventos
    event LotteryCreated(
        string uuid,
        string name,
        address lotteryManager,
        uint256 ticketPrice,
        uint256 closingTime,
        uint256 maxParticipants,
        uint256 minParticipants,
        address tokenAddress
    );
    event LotteryEntered(string uuid, address participant);
    event RandomnessRequested(
        uint256 indexed lotteryId,
        uint256 indexed requestId
    );
    event WinnerPicked(
        uint256 indexed lotteryId,
        address indexed winnerAddress,
        uint256 amount
    );
    event LotteryCancelled(uint256 indexed lotteryId, uint256 refundedAmount);
    event LotteryFinalized(uint256 indexed lotteryId, uint256 totalJackpot);
    event FundsWithdrawn(
        uint256 indexed lotteryId,
        address indexed winnerAddress,
        uint256 amount
    );
    event ContractPaused();
    event ContractUnpaused();

    // Nuevos eventos para cambio de fees
    event ManagerFeePercentChanged(uint256 newManagerFeePercent);
    event OwnerFeePercentChanged(uint256 newOwnerFeePercent);

    // Modifiers
    modifier onlyManager(uint256 lotteryId) {
        require(
            msg.sender == lotteries[lotteryId].lotteryManager ||
                msg.sender == owner(),
            "Only manager or owner"
        );
        _;
    }

    modifier onlyUserWinner(uint256 lotteryId) {
        require(
            msg.sender == lotteries[lotteryId].winnerAddress,
            "Only winner can call this function"
        );
        _;
    }

    modifier lotteryExists(uint256 lotteryId) {
        require(lotteryId < lotteries.length, "Lottery does not exist");
        _;
    }

    // ------------------------------------------------------------------------------------
    // Constructor: necesitamos pasar direcciones/keyHash/subscriptionId/gasLimit a deploy
    // ------------------------------------------------------------------------------------
    constructor(
        address vrfCoordinatorV2, // Dirección del VRFCoordinator en la testnet elegida
        uint64 subscriptionId, // ID de la subscripción Chainlink
        bytes32 gasLane, // keyHash o gasLane
        uint32 callbackGasLimit // gas para fulfillRandomWords
    )
        VRFConsumerBaseV2(vrfCoordinatorV2)
        ReentrancyGuard()
        Ownable()
        Pausable()
    {
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_subscriptionId = subscriptionId;
        i_gasLane = gasLane;
        i_callbackGasLimit = callbackGasLimit;
    }

    // ------------------------------
    //  Chainlink VRF Fulfillment
    // ------------------------------
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint256 lotteryId = requestIdToLotteryId[requestId];
        Lottery storage lottery = lotteries[lotteryId];

        // Solo si aún está ONGOING (en caso de un callback tardío)
        if (lottery.status != LotteryStatus.ONGOING) {
            return;
        }

        require(
            lottery.participants.length >= lottery.minParticipants,
            "Not enough players"
        );
        require(lottery.totalJackpot > 0, "Jackpot must be greater than zero");

        // Elegimos ganador con randomWords[0]
        uint256 index = randomWords[0] % lottery.participants.length;
        address winner = lottery.participants[index];
        lottery.winnerAddress = winner;

        // Calcular comisiones
        uint256 totalJackpot = lottery.totalJackpot;
        uint256 managerFee = (totalJackpot * managerFeePercent) / 100;
        uint256 ownerFee = (totalJackpot * ownerFeePercent) / 100;
        uint256 remainingPrize = totalJackpot - managerFee - ownerFee;

        // Actualizamos la lotería
        lottery.totalJackpot = remainingPrize;
        lottery.status = LotteryStatus.COMPLETED;

        // Transferimos fees
        if (lottery.tokenAddress == address(0)) {
            // BNB
            require(
                address(this).balance >= (managerFee + ownerFee),
                "Insufficient BNB for fees"
            );

            // managerFee -> lotteryManager
            (bool successM, ) = lottery.lotteryManager.call{value: managerFee}(
                ""
            );
            require(successM, "Transfer to manager failed");

            // ownerFee -> owner
            (bool successO, ) = owner().call{value: ownerFee}("");
            require(successO, "Transfer to owner failed");
        } else {
            // Tokens
            IERC20 token = IERC20(lottery.tokenAddress);
            token.safeTransfer(lottery.lotteryManager, managerFee);
            token.safeTransfer(owner(), ownerFee);
        }

        emit LotteryFinalized(lotteryId, remainingPrize);
        emit WinnerPicked(lotteryId, winner, remainingPrize);
    }

    // ------------------------------
    //        Fees
    // ------------------------------
    function setManagerFeePercent(
        uint256 newManagerFeePercent
    ) public onlyOwner {
        require(
            newManagerFeePercent <= MAX_FEE_PERCENT,
            "Exceeds max fee limit"
        );
        managerFeePercent = newManagerFeePercent;
        emit ManagerFeePercentChanged(newManagerFeePercent);
    }

    function setOwnerFeePercent(uint256 newOwnerFeePercent) public onlyOwner {
        require(newOwnerFeePercent <= MAX_FEE_PERCENT, "Exceeds max fee limit");
        ownerFeePercent = newOwnerFeePercent;
        emit OwnerFeePercentChanged(newOwnerFeePercent);
    }

    // ------------------------------
    //         Lógica de Lotería
    // ------------------------------

    function createLottery(
        string memory name,
        uint256 ticketPrice,
        uint256 duration,
        uint256 maxParticipants,
        uint256 minParticipants,
        address tokenAddress
    ) public whenNotPaused {
        require(ticketPrice > 0, "ticketPrice > 0");
        require(duration > 0, "duration > 0");
        require(maxParticipants > 0, "maxParticipants > 0");
        require(minParticipants > 0, "minParticipants > 0");
        require(
            minParticipants <= maxParticipants,
            "minParticipants <= maxParticipants"
        );

        string memory uuid = generateUUID(msg.sender);
        address[] memory emptyParticipants;

        Lottery memory newLottery = Lottery({
            uuid: uuid,
            name: name,
            lotteryManager: msg.sender,
            participants: emptyParticipants,
            totalJackpot: 0,
            ticketPrice: ticketPrice,
            tokenAddress: tokenAddress,
            closingTime: block.timestamp + duration,
            maxParticipants: maxParticipants,
            minParticipants: minParticipants,
            winnerAddress: address(0),
            status: LotteryStatus.ONGOING
        });

        lotteries.push(newLottery);
        uuidToIndex[uuid] = lotteries.length - 1;

        emit LotteryCreated(
            uuid,
            name,
            msg.sender,
            ticketPrice,
            newLottery.closingTime,
            maxParticipants,
            minParticipants,
            tokenAddress
        );
    }

    function enterLottery(
        string memory uuid
    ) public payable nonReentrant whenNotPaused {
        uint256 lotteryIndex = uuidToIndex[uuid];
        require(lotteryIndex < lotteries.length, "Lottery does not exist");
        Lottery storage lottery = lotteries[lotteryIndex];

        require(lottery.status == LotteryStatus.ONGOING, "Lottery not ongoing");
        require(block.timestamp < lottery.closingTime, "Lottery has ended");
        require(
            lottery.participants.length < lottery.maxParticipants,
            "Max participants reached"
        );

        // Cobro de la participationFeeInBNB
        require(
            msg.value >= participationFeeInBNB,
            "Insufficient BNB for participation fee"
        );

        if (lottery.tokenAddress == address(0)) {
            // Lotería en BNB
            uint256 totalRequired = lottery.ticketPrice + participationFeeInBNB;
            require(msg.value == totalRequired, "Incorrect BNB amount sent");

            // Transferir la comisión al owner
            (bool successFee, ) = owner().call{value: participationFeeInBNB}(
                ""
            );
            require(successFee, "Transfer of participation fee failed");

            // Sumar ticket al jackpot
            lottery.totalJackpot += lottery.ticketPrice;
        } else {
            // Lotería en tokens
            IERC20 token = IERC20(lottery.tokenAddress);
            uint256 allowance = token.allowance(msg.sender, address(this));
            require(allowance >= lottery.ticketPrice, "Check token allowance");

            // Transferir tokens
            token.safeTransferFrom(
                msg.sender,
                address(this),
                lottery.ticketPrice
            );

            // Transferir la comisión en BNB al owner
            (bool successFee, ) = owner().call{value: participationFeeInBNB}(
                ""
            );
            require(successFee, "Transfer of participation fee failed");

            // Sumar ticket al jackpot
            lottery.totalJackpot += lottery.ticketPrice;
        }

        lottery.participants.push(msg.sender);
        emit LotteryEntered(uuid, msg.sender);
    }

    // Chainlink
    // ==================================================

    function pickWinner(
        string memory uuid
    )
        public
        onlyManager(uuidToIndex[uuid])
        lotteryExists(uuidToIndex[uuid])
        nonReentrant
        whenNotPaused
    {
        uint256 lotteryId = uuidToIndex[uuid];
        Lottery storage lottery = lotteries[lotteryId];

        require(lottery.status == LotteryStatus.ONGOING, "Not ongoing");
        require(
            block.timestamp >= lottery.closingTime ||
                lottery.participants.length == lottery.maxParticipants,
            "Lottery is still active"
        );

        // Iniciamos la petición de aleatoriedad a Chainlink
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // keyHash
            i_subscriptionId, // subscriptionId
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );

        // Guardamos la relación requestId -> lotteryId
        requestIdToLotteryId[requestId] = lotteryId;

        // Emitimos un evento para trackeo
        emit RandomnessRequested(lotteryId, requestId);
    }

    // Cancelar lotería -> usando "pull refunds"
    function cancelLottery(
        string memory uuid
    )
        public
        onlyManager(uuidToIndex[uuid])
        lotteryExists(uuidToIndex[uuid])
        nonReentrant
        whenNotPaused
    {
        uint256 lotteryIndex = uuidToIndex[uuid];
        Lottery storage lottery = lotteries[lotteryIndex];

        require(lottery.status == LotteryStatus.ONGOING, "Lottery not ongoing");
        require(
            block.timestamp >= lottery.closingTime,
            "Lottery not ended yet"
        );

        lottery.status = LotteryStatus.CANCELLED;

        uint256 length = lottery.participants.length;
        uint256 price = lottery.ticketPrice;
        for (uint256 i = 0; i < length; i++) {
            address participant = lottery.participants[i];
            refunds[uuid][participant] += price;
        }

        uint256 refundedAmount = lottery.totalJackpot;
        lottery.totalJackpot = 0;

        emit LotteryCancelled(lotteryIndex, refundedAmount);
    }

    // Cada participante reclama su reembolso
    function claimRefund(string memory uuid) public nonReentrant {
        uint256 amount = refunds[uuid][msg.sender];
        require(amount > 0, "No refund available");

        refunds[uuid][msg.sender] = 0;

        Lottery storage lottery = lotteries[uuidToIndex[uuid]];
        if (lottery.tokenAddress == address(0)) {
            // BNB
            payable(msg.sender).transfer(amount);
        } else {
            // Tokens
            IERC20 token = IERC20(lottery.tokenAddress);
            token.safeTransfer(msg.sender, amount);
        }
    }

    // Retirar fondos (solo ganador)
    function withdrawFunds(
        string memory uuid
    )
        public
        payable
        onlyUserWinner(uuidToIndex[uuid])
        lotteryExists(uuidToIndex[uuid])
        nonReentrant
        whenNotPaused
    {
        uint256 lotteryIndex = uuidToIndex[uuid];
        Lottery storage lottery = lotteries[lotteryIndex];
        uint256 totalJackpot = lottery.totalJackpot;

        require(
            lottery.status == LotteryStatus.COMPLETED,
            "Lottery not completed"
        );
        require(totalJackpot > 0, "No funds to withdraw");
        require(
            msg.value >= withdrawFeeInBNB,
            "Insufficient BNB to cover withdrawal fee"
        );

        lottery.totalJackpot = 0; // Evitar reentrancia

        if (lottery.tokenAddress == address(0)) {
            // BNB
            payable(lottery.winnerAddress).transfer(totalJackpot);
        } else {
            // Tokens
            IERC20 token = IERC20(lottery.tokenAddress);
            token.safeTransfer(lottery.winnerAddress, totalJackpot);
        }

        // Cobro de withdrawFeeInBNB
        (bool successFee, ) = owner().call{value: withdrawFeeInBNB}("");
        require(successFee, "Transfer of withdrawal fee failed");

        emit FundsWithdrawn(lotteryIndex, lottery.winnerAddress, totalJackpot);
    }

    // ------------------------------
    //       Funciones de vista
    // ------------------------------
    function currentContractBalance(
        address tokenAddress
    ) public view returns (uint256) {
        if (tokenAddress == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(tokenAddress).balanceOf(address(this));
        }
    }

    function getParticipants(
        string memory uuid
    ) public view returns (address[] memory) {
        uint256 lotteryIndex = uuidToIndex[uuid];
        require(lotteryIndex < lotteries.length, "Lottery does not exist");
        return lotteries[lotteryIndex].participants;
    }

    function getTotalJackpot(string memory uuid) public view returns (uint256) {
        uint256 lotteryIndex = uuidToIndex[uuid];
        require(lotteryIndex < lotteries.length, "Lottery does not exist");
        return lotteries[lotteryIndex].totalJackpot;
    }

    function getWinnerAddress(
        string memory uuid
    ) public view returns (address) {
        uint256 lotteryIndex = uuidToIndex[uuid];
        require(lotteryIndex < lotteries.length, "Lottery does not exist");
        return lotteries[lotteryIndex].winnerAddress;
    }

    function getLotteriesByManager(
        address manager
    ) public view returns (Lottery[] memory) {
        uint256 totalLotteries = lotteries.length;
        uint256 count = 0;
        for (uint256 i = 0; i < totalLotteries; i++) {
            if (lotteries[i].lotteryManager == manager) {
                count++;
            }
        }

        Lottery[] memory managerLotteries = new Lottery[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < totalLotteries; i++) {
            if (lotteries[i].lotteryManager == manager) {
                managerLotteries[index] = lotteries[i];
                index++;
            }
        }

        return managerLotteries;
    }

    function getActiveLotteries() public view returns (Lottery[] memory) {
        uint256 totalLotteries = lotteries.length;
        uint256 activeCount = 0;

        for (uint256 i = 0; i < totalLotteries; i++) {
            if (lotteries[i].status == LotteryStatus.ONGOING) {
                activeCount++;
            }
        }

        Lottery[] memory activeLotteries = new Lottery[](activeCount);
        uint256 idx = 0;

        for (uint256 i = 0; i < totalLotteries; i++) {
            if (lotteries[i].status == LotteryStatus.ONGOING) {
                activeLotteries[idx] = lotteries[i];
                idx++;
            }
        }

        return activeLotteries;
    }

    // ------------------------------
    //      Pausa y Emergencias
    // ------------------------------
    function pause() public onlyOwner whenNotPaused {
        _pause();
        emit ContractPaused();
    }

    function unpause() public onlyOwner whenPaused {
        _unpause();
        emit ContractUnpaused();
    }

    function withdrawEmergency(
        address tokenAddress
    ) public onlyOwner nonReentrant {
        if (tokenAddress == address(0)) {
            uint256 contractBalance = address(this).balance;
            require(contractBalance > 0, "No funds to withdraw");

            (bool success, ) = owner().call{value: contractBalance}("");
            require(success, "Emergency withdrawal failed");
        } else {
            IERC20 token = IERC20(tokenAddress);
            uint256 contractBalance = token.balanceOf(address(this));
            require(contractBalance > 0, "No funds to withdraw");

            token.safeTransfer(owner(), contractBalance);
        }
    }

    // -----------------------------------
    //   Utilidad: generar UUID
    // -----------------------------------
    function generateUUID(address manager) private returns (string memory) {
        nonce++;
        return
            toHexString(
                keccak256(
                    abi.encodePacked(
                        manager,
                        block.timestamp,
                        nonce,
                        blockhash(block.number - 1)
                    )
                )
            );
    }

    function toHexString(bytes32 data) private pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(64);
        for (uint256 i = 0; i < 32; i++) {
            str[i * 2] = alphabet[uint8(data[i] >> 4)];
            str[1 + i * 2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }
}
