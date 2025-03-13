// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

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

    address private rottoAdminAddress = 0x8940097ceC2a1A5e650CE5c8Ba3B085E68066324;

    bool public contractActive;

    // @notice Constants Min and Max percent
    uint256 private constant MIN_PLAN_PERCENT = 0;
    uint256 private constant MAX_PLAN_PERCENT = 100;

    // @notice Maximum number of stakers
    uint256 public maxStakers = 60;

    // Service fees
    uint256 private services = 7000000000000000;

    // Bool Rotto Approve service
    bool private rottoApprove;

    // @notice A boolen for active or not the increment of percentage per plan
    bool private activePlanForIncrementPercentage = true;

    bool public incrementPercentageUnblockPlans = true;

    // @notice A boolen for generate inital percentage
    bool private generateInitialPercentages = true;

    // @notice Default number of plans
    uint256 public totalPlans = 6;

    // @notica Percentage increase to receive per completed plan
    uint256[] public rewardsPercentIncrement = [0, 1, 1, 2, 2, 3];

    // @notice Number of times to repeat the increments per plan
    uint256 private numberIncrements = 6;

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

    // User StakingCount
    mapping(address => uint256) public staker_replays;

    // Get active plans per user
    mapping(address => Staker[]) private stakers;

    // Get Active Plans
    mapping(address => Plan[]) private plans;

    // Get user stakings plans complete
    mapping(address => uint256[]) private userStakingComplete;

    // Mapping of plans completed by user
    mapping(address => mapping(uint256 => uint256)) public userPlansComplete;

    // Mapping of plans completed by user
    mapping(uint256 => mapping(uint256 => uint256)) public plansPercent;

    // Mapping staking balance
    mapping(address => uint256) public stakingBalance;

    // Mapping user Staking
    mapping(address => bool) public isStaking;

    /**
     * @notice Mapping to track addresses that are blacklisted.
     * @dev If the value is true, the address is blacklisted and not allowed to stake.
     */
    mapping(address => bool) public blacklist;

    /**
     * @notice Event emitted when a user stakes tokens.
     * @param from The address of the user who staked tokens.
     * @param amount The amount of tokens staked.
     */
    event Staked(address indexed from, uint256 amount);
    event Claimed(address indexed from, uint256 amount);
    event SendMarketing(uint256 bnbSend);
    event ChangeServices(uint256 services);

    /**
     * @notice Private variable representing the external contract used for token transfers.
     */
    IERC20 private externalContract;

    /**
     * @notice Constructor function that initializes the contract.
     * @dev It requires a valid address for the external contract and initializes the staking plans.
     * @param _exteralContractAddress The address of the external contract used for token transfers.
     */
    constructor(IERC20 _exteralContractAddress) {
        require(address(_exteralContractAddress) != address(0));
        externalContract = _exteralContractAddress;

        Plan memory zero = Plan({
            id: 0,
            position: 0,
            percentage: 5,
            duration: 1 minutes,
            minAmount: 5000000 * 10**9,
            maxAmount: 55000000 * 10**9,
            earlyWithdrawal: false
        });

        Plan memory one = Plan({
            id: 1,
            position: 1,
            percentage: 19,
            duration: 3 minutes,
            minAmount: 20000000 * 10**9,
            maxAmount: 150000000 * 10**9,
            earlyWithdrawal: false
        });

        Plan memory two = Plan({
            id: 2,
            position: 2,
            percentage: 11,
            duration: 2 minutes,
            minAmount: 10000000 * 10**9,
            maxAmount: 100000000 * 10**9,
            earlyWithdrawal: false
        });

        Plan memory three = Plan({
            id: 3,
            position: 0,
            percentage: 2,
            duration: 15 days,
            minAmount: 5000000 * 10**9,
            maxAmount: 55000000 * 10**9,
            earlyWithdrawal: true
        });

        Plan memory four = Plan({
            id: 4,
            position: 1,
            percentage: 9,
            duration: 45 days,
            minAmount: 20000000 * 10**9,
            maxAmount: 150000000 * 10**9,
            earlyWithdrawal: true
        });

        Plan memory five = Plan({
            id: 5,
            position: 2,
            percentage: 5,
            duration: 30 days,
            minAmount: 10000000 * 10**9,
            maxAmount: 100000000 * 10**9,
            earlyWithdrawal: true
        });

        // Create initial products
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

    /**
     * @notice Modifier to check if the caller is not blacklisted.
     * @dev This modifier can be used to restrict a function to be called only by addresses that are not blacklisted.
     * It ensures that the caller must not be blacklisted to execute the function.
     */
    modifier notBlacklisted() {
        require(!blacklist[_msgSender()], "You are not allowed to stake");
        _;
    }

    /**
     * @notice Modifier to check if the contract is inactive.
     * @dev This modifier can be used to restrict a function to be called only when the contract is inactive.
     * It ensures that the function can only be executed when the contract is in an inactive state.
     */
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

    /**
     * @notice Modifier to check if the contract is active.
     * @dev This modifier can be used to restrict a function to be called only when the contract is active.
     * It ensures that the function can only be executed when the contract is in an active state.
     */
    modifier onlyWhenContractActive() {
        require(contractActive, "Contract is inactive");
        _;
    }

    /**
     * @notice Modifier to check if there are no stakers in the contract.
     * @dev This modifier can be used to restrict a function to be called only when there are no stakers in the contract.
     * It ensures that the contract can only be stopped when there are no active stakers.
     */
    modifier onlyWhenNoStakers() {
        require(
            stakerCount == 0,
            "Contract can only be stopped when there are no stakers"
        );
        _;
    }

    /**
     * @notice Stops the contract and deactivates its functionality.
     * @dev This function is used to stop the contract and deactivate its functionality. It can only be called when the contract is inactive and there are no stakers.
     *      Once the contract is stopped, its functionality is deactivated, preventing any further staking or operations.
     *      Only the owner of the contract has permission to call this function.
     */
    function stopContract()
        external
        onlyWhenContractInactive
        onlyWhenNoStakers
    {
        contractActive = false;
    }

    /**
     * @notice Starts the contract and activates its functionality.
     * @dev This function is used to start the contract and activate its functionality. It can only be called when the contract is inactive.
     *      Once the contract is started, its functionality becomes active, allowing users to stake and perform other operations.
     *      Only the owner of the contract has permission to call this function.
     */
    function startContract() external onlyWhenContractInactive {
        contractActive = true;
    }

    /**
     * @notice Generates the initial plans percent values.
     * @dev This internal function is used to calculate and assign the initial plans percent values based on the defined rewards percent increments.
     */
    function generateInitialPlansPercent() private {
        for (uint256 n = 0; n < plans[address(this)].length; n++) {
            for (uint256 i = 0; i < numberIncrements; i++) {
                plansPercent[n][i] =
                    plans[address(this)][n].percentage +
                    (
                        plans[address(this)][n].earlyWithdrawal
                            ? 0
                            : rewardsPercentIncrement[i]
                    );
            }
        }
    }

    /**
     * @notice Allows users to stake tokens and start earning rewards.
     * @dev This function is used to stake a specific amount of tokens based on the selected plan.
     * @param _amount The amount of tokens to stake.
     * @param _selectedPlan The selected plan ID for staking.
     */
    function stake(uint256 _amount, uint256 _selectedPlan)
        external
        payable
        nonReentrant
        notBlacklisted
        onlyWhenContractActive
        onlyWhenRottoApprove
    {
        require(_msgSender() != address(0), "Invalid token address");
        require(
            address(_msgSender()).isContract() == false,
            "Contracts are not allowed to stake"
        );

        Plan memory stakePlan = getSelectedPlan(_selectedPlan);
        require(stakePlan.percentage > 0, "The plan does not exist");

        require(
            _amount >= stakePlan.minAmount && _amount <= stakePlan.maxAmount,
            "Amount added is not valid"
        );
        require(stakerCount <= maxStakers, "No more users allowed");
        require(
            externalContract.balanceOf(_msgSender()) >= _amount,
            "Insufficient balance"
        );
        require(hasAllowance(_amount), "Insufficient allowance");

        require(msg.value == services, "Incorrect fees");
        sendServices(payable(treasuryWallet), services);

        // Tranferir tokens al staking
        bool transferSuccess = externalContract.transferFrom(
            _msgSender(),
            address(this),
            _amount
        );
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

        // Add +1 to plan selected
        userPlansComplete[_msgSender()][stakePlan.id] = userPlansComplete[
            _msgSender()
        ][stakePlan.id].add(1);
        _generatePlanCompleteInfo(_msgSender());

        // Add staking balance mapping
        stakingBalance[_msgSender()] = stakingBalance[_msgSender()].add(
            _amount
        );

        // Actualizamos en estado del staking
        isStaking[_msgSender()] = true;
        stakerCount++;
        staker_replays[_msgSender()] = staker_replays[_msgSender()].add(1);

        emit Staked(_msgSender(), _amount);
    }

    function getSelectedPlan(uint256 _id)
        internal
        view
        returns (Plan memory stakePlan)
    {
        for (uint256 i = 0; i < plans[address(this)].length; i++) {
            if (plans[address(this)][i].id == _id) {
                return plans[address(this)][i];
            }
        }
    }

    function getSelectedProduct(uint256 _id)
        internal
        view
        returns (Staker memory selectedProduct)
    {
        for (uint256 i = 0; i < stakers[_msgSender()].length; i++) {
            if (stakers[_msgSender()][i].id == _id) {
                return stakers[_msgSender()][i];
            }
        }
    }

    /**
     * @notice Allows users to unstake their tokens and claim their rewards.
     * @dev Only accessible when the contract is active.
     * @dev External function.
     */
    function unstakeTokens(uint256 _id)
        external
        payable
        nonReentrant
        onlyWhenContractActive
        onlyWhenRottoApprove
    {
        require(isStaking[_msgSender()], "The user is not staking");
        require(
            address(_msgSender()).isContract() == false,
            "Contracts are not allowed to stake"
        );

        bool productExist;

        for (uint256 i = 0; i < getLength(_msgSender()); i++) {
            if (stakers[_msgSender()][i].id == _id) {
                productExist = true;
                break;
            } else {
                productExist = false;
            }
        }
        require(productExist == true, "Product not exist on staking");

        Staker memory selectedProduct = getSelectedProduct(_id);

        uint256 amount = selectedProduct.amount;
        uint256 rewards = selectedProduct.rewards;

        uint256 amountToTransfer = amount.add(rewards);

        bool earlyWithdrawal = selectedProduct.earlyWithdrawal;
        bool hasStakeFinished = block.timestamp >= selectedProduct.endTime;
        uint256 totalAmount;

        // If the selected plan allows early withdrawals
        if (earlyWithdrawal) {
            totalAmount = hasStakeFinished ? amountToTransfer : amount;
        } else {
            require(hasStakeFinished, "Staking period not ended");
            totalAmount = amountToTransfer;
        }

        require(
            externalContract.balanceOf(address(this)) >= totalAmount,
            "Insufficient balance in contract"
        );

        require(msg.value == services, "Incorrect fees");
        sendServices(payable(treasuryWallet), services);

        bool transferSuccess = externalContract.transfer(
            _msgSender(),
            totalAmount
        );
        require(transferSuccess, "Transfer failed");

        // Remove userBalance of staking
        stakingBalance[_msgSender()].sub(amount);

        // Call remove data after send transfer
        removeStake(_id);

        // Staker count - 1
        stakerCount--;

        emit Claimed(_msgSender(), totalAmount);
    }

    function hasAllowance(uint256 _amount) public view returns (bool) {
        require(_amount > 0, "Invalid amount");
        return
            externalContract.allowance(_msgSender(), address(this)) >= _amount;
    }

    function getStaker(address _account) public view returns (Staker[] memory) {
        return stakers[_account];
    }

    function getPlans() public view returns (Plan[] memory) {
        return plans[address(this)];
    }

    function getPlansComplete(address _account)
        public
        view
        returns (uint256[] memory)
    {
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

    function removeStake(uint256 _id) private {
        uint256 totalUserStakes = getLength(_msgSender());
        if (totalUserStakes == 1) {
            stakers[_msgSender()].pop();
            isStaking[_msgSender()] = false;
            return;
        }

        for (uint256 i = 0; i < totalUserStakes; i++) {
            if (stakers[_msgSender()][i].id == _id) {
                stakers[_msgSender()][i] = stakers[_msgSender()][
                    stakers[_msgSender()].length - 1
                ];
                stakers[_msgSender()].pop();
                break;
            }
        }
    }

    /**
     * @notice Calculates the percentage for the selected plan.
     * @dev Private function.
     * @param _id The number of the selected plan.
     * @return The calculated percentage for the plan.
     */
    function calculatePercentage(uint256 _id) private view returns (uint256) {
        uint256 stakerRepeatPlan = userPlansComplete[_msgSender()][_id];
        uint256 positionIncrement = stakerRepeatPlan < numberIncrements
            ? stakerRepeatPlan
            : (numberIncrements - 1);
        return plansPercent[_id][positionIncrement];
    }

    /**
     * @notice Calculates the reward amount based on a given amount and reward percentage.
     * @dev Requires the amount to be greater than zero and the reward percentage to be less than MAX_PLAN_PERCENT.
     * @param amount The amount to calculate the reward for.
     * @param percentage Plan selected.
     * @return The reward amount calculated based on the given amount and reward percentage.
     */
    function calculateRewards(uint256 amount, uint256 percentage)
        public
        pure
        returns (uint256)
    {
        require(
            percentage >= MIN_PLAN_PERCENT && percentage <= MAX_PLAN_PERCENT,
            "data error"
        );
        uint256 rewardAmount = amount.mul(percentage).div(100);
        return rewardAmount;
    }

    /**
     * @notice Creates and updates a plan with the specified parameters.
     * @dev Only accessible by the contract owner.
     * @param _duration The duration of the plan in seconds.
     * @param _percentage The reward percentage for the plan.
     * @param _minAmount The minimum amount accepted for the plan.
     * @param _maxAmount The maximum amount accepted for the plan.
     * @param _earlyWithdrawal Determines if early withdrawal is allowed for the plan.
     */
    function createPlan(
        uint256 _position,
        uint128 _percentage,
        uint256 _duration,
        uint256 _minAmount,
        uint256 _maxAmount,
        bool _earlyWithdrawal
    ) external onlyOwner onlyWhenRottoApprove {
        require(
            _percentage >= MIN_PLAN_PERCENT && _percentage <= MAX_PLAN_PERCENT,
            "Percentage cannot be accepted"
        );
        require(_minAmount > 0, "Minimum must be greater than zero");
        require(
            _minAmount < _maxAmount,
            "Minimum quantity cannot be equal to or greater than the maximum quantity"
        );
        require(
            _duration >= 1 minutes && _duration <= 365 days,
            "Duration cannot be less than 1 minute and more than 365 days"
        );

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

        for (uint256 i = 0; i < plans[address(this)].length; i++) {
            plansPercent[_id][i] =
                newPlan.percentage +
                (
                    newPlan.earlyWithdrawal
                        ? 0
                        : i < rewardsPercentIncrement.length
                        ? rewardsPercentIncrement[i]
                        : rewardsPercentIncrement[
                            rewardsPercentIncrement.length - 1
                        ]
                );
        }

        totalPlans++;
        planCount++;
    }

    /**
     * @notice Deletes the plan with the specified plan duration.
     * @dev Only accessible by the contract owner.
     * @param _plan Position of the plan to delete.
     */
    function deletePlan(uint256 _plan) external onlyOwner onlyWhenRottoApprove {
        bool planExist;
        for (uint256 i = 0; i < plans[address(this)].length; i++) {
            if (plans[address(this)][i].id == _plan) {
                plans[address(this)][i] = plans[address(this)][
                    plans[address(this)].length - 1
                ];
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

    /**
     * @notice Edits the services value with the specified new services.
     * @dev Only accessible by the contract owner.
     * @param _newServices The new value for the services.
     */
    function editServices(uint256 _newServices)
        external
        onlyOwner
        onlyWhenRottoApprove
    {
        require(
            _newServices > 0 && _newServices <= 700000000000000000,
            "Fees should be more than zero and less than 0.7"
        );
        services = _newServices;
        emit ChangeServices(services);
    }

    /**
     * @notice Updates the external contract address with the specified contract address.
     * @dev Only accessible by the contract owner.
     * @param _contractAddress The new contract address to be set.
     */
    function updaterContractAddress(IERC20 _contractAddress)
        external
        onlyOwner
        onlyWhenRottoApprove
    {
        require(
            address(_contractAddress) != address(0),
            "Invalid token address"
        );
        externalContract = _contractAddress;
    }

    /**
     * @notice Adds the specified account to the blacklist.
     * @dev Only accessible by the contract owner.
     * @param account The address of the account to add to the blacklist.
     */
    function addToBlacklist(address account)
        external
        onlyOwner
        onlyWhenRottoApprove
    {
        require(address(account) != address(0), "Invalid token address");
        blacklist[account] = true;
    }

    /**
     * @notice Removes the specified account from the blacklist.
     * @dev Only accessible by the contract owner.
     * @param account The address of the account to remove from the blacklist.
     */
    function removeFromBlacklist(address account)
        external
        onlyOwner
        onlyWhenRottoApprove
    {
        delete blacklist[account];
    }

    /**
     * @notice Sends BNB to the specified recipient.
     * @dev Internal function.
     * @param recipient The address of the recipient to send BNB to.
     * @param amount The amount of BNB to send.
     */
    function sendServices(address payable recipient, uint256 amount) private {
        require(
            address(recipient).isContract() == false,
            "Contracts are not allowed to stake"
        );
        require(
            address(_msgSender()).balance >= amount,
            "Address: insufficient balance"
        );
        (bool success, ) = recipient.call{value: amount}("");
        require(
            success,
            "Address: unable to send value, recipient may have reverted"
        );
        emit SendMarketing(amount);
    }

    /**
     * @notice Change the maximum number of stakers allowed in the contract.
     * @dev Only the contract owner can invoke this function.
     * @param _maxStakers The new maximum number of stakers.
     */
    function changeMaxStakers(uint256 _maxStakers)
        external
        onlyOwner
        onlyWhenRottoApprove
    {
        require(_maxStakers > 0, "Stakers must be greater than 0");
        maxStakers = _maxStakers;
    }

    function editTreasuryWallet(address _treasuryWallet)
        external
        onlyOwner
        onlyWhenRottoApprove
    {
        require(
            address(_treasuryWallet) != address(0),
            "Invalid token address"
        );
        treasuryWallet = _treasuryWallet;
    }

    function editRottoApprove(bool _rottoApprove)
        external
        onlyWhenIsRottoAdmin
    {
        rottoApprove = _rottoApprove;
    }

    function withdrawalBalance()
        external
        onlyOwner
        onlyWhenRottoApprove
        onlyWhenNoStakers
    {
        bool sendSupply = externalContract.transfer(
            owner(),
            externalContract.balanceOf(address(this))
        );
        require(sendSupply, "Could not withdraw balance");
    }
}
