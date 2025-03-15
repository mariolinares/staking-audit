// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract RottolabsStaking is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for uint128;
    using Address for address;

    uint128 public stakerCount;
    uint128 private planCount;

    address private rottoAdminAddress = 0x37eF5480A6F43795fC5F1fCA5Dc78252a0c3507a;

    bool public contractActive;

    // Constants de porcentaje mínimo y máximo
    uint256 private constant MIN_PLAN_PERCENT = 0;
    uint256 private constant MAX_PLAN_PERCENT = 100;

    // Número máximo de stakers
    uint256 public maxStakers = 150;

    // Tarifas de servicio
    uint256 private services = 14000000000000000;

    // Listado de clientes
    address[] private customerList;
    mapping(address => uint256) public customerActivePlans;

    // Flag de aprobación de Rotto
    bool private rottoApprove;

    // Flags para manejo de incrementos en planes
    bool private activePlanForIncrementPercentage = true;
    bool public incrementPercentageUnblockPlans = true;
    bool private generateInitialPercentages = true;

    // Número total de planes y monedas máximas disponibles
    uint256 public totalPlans = 6;
    uint256 public maximunCoin = 400000000 * 10**9; // 400 millones

    // Incrementos en porcentaje por plan completado
    uint256[] public rewardsPercentIncrement = [0, 1, 1, 2];
    uint256 private numberIncrements = 4;

    address public treasuryWallet;

    struct Staker {
        uint256 id;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        uint256 percentage;
        uint256 rewards;
        uint256 selectedPlan;
        bool earlyWithdrawal;
    }

    struct Plan {
        uint128 id;
        uint128 percentage;
        uint256 position;
        uint256 duration;
        uint256 minAmount;
        uint256 maxAmount;
        bool earlyWithdrawal;
    }

    // Mapeos y estructuras de datos
    mapping(address => uint256) public staker_replays;
    mapping(address => Staker[]) private stakers;
    mapping(address => Plan[]) private plans;
    mapping(address => uint256[]) private userStakingComplete;
    mapping(address => mapping(uint256 => uint256)) public userPlansComplete;
    mapping(uint256 => mapping(uint256 => uint256)) public plansPercent;
    mapping(address => uint256) public stakingBalance;
    mapping(address => bool) public isStaking;
    mapping(address => uint256) public totalStakingBalance;
    mapping(address => uint256) public totalRewards;
    mapping(address => bool) public blacklist;

    event Staked(address indexed from, uint256 amount);
    event Claimed(address indexed from, uint256 amount);
    event SendMarketing(uint256 bnbSend);
    event ChangeServices(uint256 services);

    IERC20 private externalContract;

    constructor(IERC20 _exteralContractAddress) {
        require(address(_exteralContractAddress) != address(0));
        externalContract = _exteralContractAddress;

        Plan memory zero = Plan({
            id: 0,
            position: 0,
            percentage: 1,
            duration: 45 seconds,
            minAmount: 1000 * 10**9,
            maxAmount: 5000000 * 10**9,
            earlyWithdrawal: false
        });

        Plan memory one = Plan({
            id: 1,
            position: 1,
            percentage: 4,
            duration: 90 seconds,
            minAmount: 1000 * 10**9,
            maxAmount: 10000000 * 10**9,
            earlyWithdrawal: false
        });

        Plan memory two = Plan({
            id: 2,
            position: 2,
            percentage: 2,
            duration: 60 seconds,
            minAmount: 1000 * 10**9,
            maxAmount: 7000000 * 10**9,
            earlyWithdrawal: false
        });

        Plan memory three = Plan({
            id: 3,
            position: 0,
            percentage: 1,
            duration: 45 seconds,
            minAmount: 1000 * 10**9,
            maxAmount: 5000000 * 10**9,
            earlyWithdrawal: true
        });

        Plan memory four = Plan({
            id: 4,
            position: 1,
            percentage: 4,
            duration: 90 seconds,
            minAmount: 1000 * 10**9,
            maxAmount: 10000000 * 10**9,
            earlyWithdrawal: true
        });

        Plan memory five = Plan({
            id: 5,
            position: 2,
            percentage: 2,
            duration: 60 seconds,
            minAmount: 1000 * 10**9,
            maxAmount: 7000000 * 10**9,
            earlyWithdrawal: true
        });

        // Se crean los planes iniciales
        plans[address(this)].push(zero);
        plans[address(this)].push(one);
        plans[address(this)].push(two);
        plans[address(this)].push(three);
        plans[address(this)].push(four);
        plans[address(this)].push(five);

        treasuryWallet = 0xb3cf72697b796A86FD0D52F73e1D8C7Ef3f4875D;
        rottoApprove = true;
        contractActive = true;
        stakerCount = 0;
        planCount = 6;

        if (generateInitialPercentages) {
            generateInitialPlansPercent();
        }
    }

    // Modificadores
    modifier notBlacklisted() {
        require(!blacklist[_msgSender()], "You are not allowed to stake");
        _;
    }

    // Se usa cuando el contrato está activo
    modifier onlyWhenContractActive() {
        require(contractActive, "Contract is inactive");
        _;
    }

    // Se usa cuando el contrato está inactivo
    modifier onlyWhenContractInactive() {
        require(!contractActive, "Contract is active");
        _;
    }

    modifier onlyWhenRottoApprove() {
        require(rottoApprove, "Contact with Rotto");
        _;
    }

    modifier onlyWhenIsRottoAdmin() {
        require(rottoAdminAddress == _msgSender(), "Contact with Rotto");
        _;
    }

    modifier onlyWhenNoStakers() {
        require(stakerCount == 0, "Contract can only be stopped when there are no stakers");
        _;
    }

    // CORRECCIÓN 1: Se utiliza onlyWhenContractActive para detener el contrato
    function stopContract()
        external
        onlyWhenContractActive
        onlyWhenNoStakers
    {
        contractActive = false;
    }

    function startContract() external onlyWhenContractInactive {
        contractActive = true;
    }

    function generateInitialPlansPercent() private {
        for (uint256 n = 0; n < plans[address(this)].length; n++) {
            for (uint256 i = 0; i < numberIncrements; i++) {
                plansPercent[n][i] =
                    plans[address(this)][n].percentage +
                    (plans[address(this)][n].earlyWithdrawal ? 0 : rewardsPercentIncrement[i]);
            }
        }
    }

    // NUEVA: Función interna para obtener el índice del stake y evitar loops redundantes
    function findStakerIndex(uint256 _id) internal view returns (uint256) {
        for (uint256 i = 0; i < stakers[_msgSender()].length; i++) {
            if (stakers[_msgSender()][i].id == _id) {
                return i;
            }
        }
        revert("Staking product not found");
    }

    function stake(uint256 _amount, uint256 _selectedPlan)
        external
        payable
        nonReentrant
        notBlacklisted
        onlyWhenContractActive
        onlyWhenRottoApprove
    {
        uint256 newTotalBalance = totalStakingBalance[address(this)] + _amount;
        require(newTotalBalance < maximunCoin, "No more coins are allowed within the staking");
        require(_msgSender() != address(0), "Invalid token address");
        require(address(_msgSender()).isContract() == false, "Contracts are not allowed to stake");

        Plan memory stakePlan = getSelectedPlan(_selectedPlan);
        require(stakePlan.percentage > 0, "The plan does not exist");
        require(_amount >= stakePlan.minAmount && _amount <= stakePlan.maxAmount, "Amount added is not valid");
        // CORRECCIÓN 3: Se verifica que el número de stakers sea menor al máximo permitido
        require(stakerCount < maxStakers, "No more users allowed");
        require(externalContract.balanceOf(_msgSender()) >= _amount, "Insufficient balance");
        require(hasAllowance(_amount), "Insufficient allowance");

        require(msg.value == services, "Incorrect fees");
        sendServices(payable(treasuryWallet), services);

        bool transferSuccess = externalContract.transferFrom(_msgSender(), address(this), _amount);
        require(transferSuccess, "Transfer failed");
        
        uint256 calculatedPercentage = activePlanForIncrementPercentage
            ? calculatePercentage(stakePlan.id)
            : stakePlan.percentage;
        uint256 id = staker_replays[_msgSender()];

        stakers[_msgSender()].push(
            Staker({
                id: id,
                amount: _amount,
                selectedPlan: stakePlan.id,
                startTime: block.timestamp,
                endTime: block.timestamp.add(stakePlan.duration),
                percentage: calculatedPercentage,
                rewards: calculateRewards(_amount, calculatedPercentage),
                earlyWithdrawal: stakePlan.earlyWithdrawal
            })
        );

        totalRewards[owner()] = totalRewards[owner()].add(calculateRewards(_amount, calculatedPercentage));
        userPlansComplete[_msgSender()][stakePlan.id] = userPlansComplete[_msgSender()][stakePlan.id].add(1);
        _generatePlanCompleteInfo(_msgSender());

        stakingBalance[_msgSender()] = stakingBalance[_msgSender()].add(_amount);
        totalStakingBalance[address(this)] = totalStakingBalance[address(this)].add(_amount);

        isStaking[_msgSender()] = true;
        stakerCount++;
        if (customerActivePlans[_msgSender()] == 0) {
            customerList.push(_msgSender());
        }
        customerActivePlans[_msgSender()] = customerActivePlans[_msgSender()].add(1);
        staker_replays[_msgSender()] = staker_replays[_msgSender()].add(1);

        emit Staked(_msgSender(), _amount);
    }

    function getSelectedPlan(uint256 _id) internal view returns (Plan memory stakePlan) {
        for (uint256 i = 0; i < plans[address(this)].length; i++) {
            if (plans[address(this)][i].id == _id) {
                return plans[address(this)][i];
            }
        }
        revert("Plan not found");
    }

    function getSelectedProduct(uint256 _id) internal view returns (Staker memory selectedProduct) {
        for (uint256 i = 0; i < stakers[_msgSender()].length; i++) {
            if (stakers[_msgSender()][i].id == _id) {
                return stakers[_msgSender()][i];
            }
        }
        revert("Staking product not found");
    }

    function unstakeTokens(uint256 _id)
        external
        payable
        nonReentrant
        onlyWhenContractActive
        onlyWhenRottoApprove
    {
        require(isStaking[_msgSender()], "The user is not staking");
        require(address(_msgSender()).isContract() == false, "Contracts are not allowed to stake");

        // CORRECCIÓN 4: Se obtiene el índice del stake sin loops redundantes
        uint256 index = findStakerIndex(_id);
        Staker storage selectedProduct = stakers[_msgSender()][index];

        uint256 amount = selectedProduct.amount;
        uint256 rewards = selectedProduct.rewards;
        uint256 amountToTransfer = amount.add(rewards);

        bool earlyWithdrawal = selectedProduct.earlyWithdrawal;
        bool hasStakeFinished = block.timestamp >= selectedProduct.endTime;
        uint256 totalAmount;

        if (earlyWithdrawal) {
            totalAmount = hasStakeFinished ? amountToTransfer : amount;
        } else {
            require(hasStakeFinished, "Staking period not ended");
            totalAmount = amountToTransfer;
        }

        require(externalContract.balanceOf(address(this)) >= totalAmount, "Insufficient balance in contract");
        require(msg.value == services, "Incorrect fees");
        sendServices(payable(treasuryWallet), services);

        bool transferSuccess = externalContract.transfer(_msgSender(), totalAmount);
        require(transferSuccess, "Transfer failed");

        totalRewards[owner()] = totalRewards[owner()].sub(rewards);

        // CORRECCIÓN 2: Actualización correcta del saldo del usuario
        stakingBalance[_msgSender()] = stakingBalance[_msgSender()].sub(amount);
        totalStakingBalance[address(this)] = totalStakingBalance[address(this)].sub(amount);

        // Eliminamos el stake usando el índice obtenido
        removeStakeByIndex(_msgSender(), index);

        stakerCount--;
        customerActivePlans[_msgSender()] = customerActivePlans[_msgSender()].sub(1);
        if (customerActivePlans[_msgSender()] == 0) {
            for (uint256 i = 0; i < customerList.length; i++) {
                if (customerList[i] == _msgSender()) {
                    customerList[i] = customerList[customerList.length - 1];
                    customerList.pop();
                    break;
                }
            }
        }

        emit Claimed(_msgSender(), totalAmount);
    }

    // NUEVA: Función para eliminar un stake dado el índice
    function removeStakeByIndex(address _staker, uint256 index) internal {
        uint256 totalUserStakes = stakers[_staker].length;
        if (totalUserStakes == 1) {
            stakers[_staker].pop();
            isStaking[_staker] = false;
            return;
        }
        stakers[_staker][index] = stakers[_staker][totalUserStakes - 1];
        stakers[_staker].pop();
    }

    function hasAllowance(uint256 _amount) public view returns (bool) {
        require(_amount > 0, "Invalid amount");
        return externalContract.allowance(_msgSender(), address(this)) >= _amount;
    }

    function getStaker(address _account) public view returns (Staker[] memory) {
        return stakers[_account];
    }

    function getPlans() public view returns (Plan[] memory) {
        return plans[address(this)];
    }

    function getPlansComplete(address _account) public view returns (uint256[] memory) {
        return userStakingComplete[_account];
    }

    function _generatePlanCompleteInfo(address _account) private {
        delete userStakingComplete[_account];
        for (uint256 i = 0; i < planCount; i++) {
            userStakingComplete[_account].push(userPlansComplete[_account][i]);
        }
    }

    function getLength(address _sender) public view returns (uint256) {
        return stakers[_sender].length;
    }

    function getPlanLength() internal view returns (uint128) {
        return uint128(planCount);
    }

    function getTotalBalance() public view returns (uint256) {
        return totalStakingBalance[address(this)];
    }

    function calculatePercentage(uint256 _id) private view returns (uint256) {
        uint256 stakerRepeatPlan = userPlansComplete[_msgSender()][_id];
        uint256 positionIncrement = stakerRepeatPlan < numberIncrements ? stakerRepeatPlan : (numberIncrements - 1);
        return plansPercent[_id][positionIncrement];
    }

    function calculateRewards(uint256 amount, uint256 percentage)
        public
        pure
        returns (uint256)
    {
        require(percentage >= MIN_PLAN_PERCENT && percentage <= MAX_PLAN_PERCENT, "data error");
        uint256 rewardAmount = amount.mul(percentage).div(100);
        return rewardAmount;
    }

    function createPlan(
        uint256 _position,
        uint128 _percentage,
        uint256 _duration,
        uint256 _minAmount,
        uint256 _maxAmount,
        bool _earlyWithdrawal
    ) external onlyOwner onlyWhenRottoApprove {
        require(_percentage >= MIN_PLAN_PERCENT && _percentage <= MAX_PLAN_PERCENT, "Percentage cannot be accepted");
        require(_minAmount > 0, "Minimum must be greater than zero");
        require(_minAmount < _maxAmount, "Minimum quantity cannot be equal to or greater than the maximum quantity");
        require(_duration >= 1 minutes && _duration <= 365 days, "Duration cannot be less than 1 minute and more than 365 days");

        uint128 _id = getPlanLength();

        Plan memory newPlan = Plan({
            id: _id,
            position: _position,
            percentage: _percentage,
            duration: _duration,
            minAmount: _minAmount,
            maxAmount: _maxAmount,
            earlyWithdrawal: _earlyWithdrawal
        });

        plans[address(this)].push(newPlan);
        _generatePlanCompleteInfo(_msgSender());

        for (uint256 i = 0; i < rewardsPercentIncrement.length; i++) {
            plansPercent[_id][i] = !_earlyWithdrawal ? newPlan.percentage + rewardsPercentIncrement[i] : 0;
        }

        totalPlans++;
        planCount++;
    }

    function deletePlan(uint256 _plan) external onlyOwner onlyWhenRottoApprove {
        bool planExist;
        for (uint256 i = 0; i < plans[address(this)].length; i++) {
            if (plans[address(this)][i].id == _plan) {
                plans[address(this)][i] = plans[address(this)][plans[address(this)].length - 1];
                plans[address(this)].pop();
                totalPlans--;
                planExist = true;
                break;
            } else {
                planExist = false;
            }
        }
        require(planExist, "You cannot delete. The plan does not exist");
    }

    function editServices(uint256 _newServices) external onlyOwner onlyWhenRottoApprove {
        require(_newServices > 0 && _newServices <= 700000000000000000, "Fees should be more than zero and less than 0.7");
        services = _newServices;
        emit ChangeServices(services);
    }

    function updaterContractAddress(IERC20 _contractAddress) external onlyOwner onlyWhenRottoApprove {
        require(address(_contractAddress) != address(0), "Invalid token address");
        externalContract = _contractAddress;
    }

    function addToBlacklist(address account) external onlyOwner onlyWhenRottoApprove {
        require(address(account) != address(0), "Invalid token address");
        blacklist[account] = true;
    }

    function removeFromBlacklist(address account) external onlyOwner onlyWhenRottoApprove {
        delete blacklist[account];
    }

    function sendServices(address payable recipient, uint256 amount) private {
        require(address(recipient).isContract() == false, "Contracts are not allowed to stake");
        require(address(_msgSender()).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
        emit SendMarketing(amount);
    }

    function changeMaxStakers(uint256 _maxStakers) external onlyOwner onlyWhenRottoApprove {
        require(_maxStakers > 0, "Stakers must be greater than 0");
        maxStakers = _maxStakers;
    }

    function editTreasuryWallet(address _treasuryWallet) external onlyOwner onlyWhenRottoApprove {
        require(address(_treasuryWallet) != address(0), "Invalid token address");
        treasuryWallet = _treasuryWallet;
    }

    function editRottoApprove(bool _rottoApprove) external onlyWhenIsRottoAdmin {
        rottoApprove = _rottoApprove;
    }

    function withdrawalBalance()
        external
        onlyOwner
        onlyWhenRottoApprove
        onlyWhenNoStakers
    {
        bool sendSupply = externalContract.transfer(owner(), externalContract.balanceOf(address(this)));
        require(sendSupply, "Could not withdraw balance");
    }

    function totalRewardsPending() public view returns (uint256) {
        return totalRewards[owner()];
    } 

    function customersList() public view returns (address[] memory) {
        return customerList;
    }

    function changeMaxAvailableCoins(uint256 _maxCoins) external onlyOwner onlyWhenRottoApprove {
        require(_maxCoins > 0, "Must be greater than zero");
        maximunCoin = _maxCoins;
    }
}
