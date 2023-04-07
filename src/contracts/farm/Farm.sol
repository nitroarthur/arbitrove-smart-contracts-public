// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "@tokens/esTROVE.sol";

// Farm distributes the ERC20 rewards based on staked LP to each user.
//
// Cloned from https://github.com/SashimiProject/sashimiswap/blob/master/contracts/MasterChef.sol
// Modified by LTO Network to work for non-mintable ERC20.
contract Farm is
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of ERC20s
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accERC20PerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's accERC20PerShare (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's amount gets updated.
        //   4. User's rewardDebt gets updated.
        uint256 mirrorAmount;
        uint256 realAmount;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ERC20s to distribute per block.
        uint256 lastRewardBlock; // Last block number that ERC20s distribution occurs.
        uint256 accERC20PerShare; // Accumulated ERC20s per share, times 1e36.
    }

    // Address of the ERC20 Token contract.
    IERC20 public erc20;
    // The total amount of ERC20 that's paid out as reward.
    uint256 public paidOut;
    // ERC20 tokens rewarded per block.
    uint256 public rewardPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => address) troveToEsTrove;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    // The block number when farming starts.
    uint256 public startBlock;
    // The block number when farming ends.
    uint256 public endBlock;

    function init(
        IERC20 _erc20,
        uint256 _rewardPerBlock,
        uint256 _startBlockDelay,
        uint256 _endBlock
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        erc20 = _erc20;
        rewardPerBlock = _rewardPerBlock;
        startBlock = block.number + _startBlockDelay;
        endBlock = _endBlock;
        totalAllocPoint = 0;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // Number of LP pools
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate,
        address mirror
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock
            ? block.number
            : startBlock;
        troveToEsTrove[address(_lpToken)] = mirror;
        totalAllocPoint = totalAllocPoint + (_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accERC20PerShare: 0
            })
        );
    }

    // Update the given pool's ERC20 allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint =
            totalAllocPoint -
            (poolInfo[_pid].allocPoint) +
            (_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function setRewardPerBlock(
        uint256 _rewardPerBlock,
        bool _withUpdate
    ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        rewardPerBlock = _rewardPerBlock;
    }

    // View function to see deposited LP for a user.
    function deposited(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.amount;
    }

    function depositedReal(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.realAmount;
    }

    function depositedRealMirror(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        UserInfo storage user = userInfo[_pid][_user];
        return user.mirrorAmount;
    }

    // View function to see pending ERC20s for a user.
    function pending(
        uint256 _pid,
        address _user
    ) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accERC20PerShare = pool.accERC20PerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this)) +
            IERC20(troveToEsTrove[address(pool.lpToken)]).balanceOf(
                address(this)
            );
        uint256 lastBlock = block.number < endBlock ? block.number : endBlock;

        if (
            lastBlock > pool.lastRewardBlock &&
            block.number > pool.lastRewardBlock &&
            lpSupply != 0
        ) {
            uint256 nrOfBlocks = lastBlock - (pool.lastRewardBlock);
            uint256 erc20Reward = (nrOfBlocks *
                (rewardPerBlock) *
                (pool.allocPoint)) / (totalAllocPoint);
            accERC20PerShare =
                accERC20PerShare +
                ((erc20Reward * (1e36)) / (lpSupply));
        }

        return (user.amount * (accERC20PerShare)) / (1e36) - (user.rewardDebt);
    }

    // View function for total reward the farm has yet to pay out.
    function totalPending() external view returns (uint256) {
        if (block.number <= startBlock) {
            return 0;
        }

        uint256 lastBlock = block.number < endBlock ? block.number : endBlock;
        return rewardPerBlock * (lastBlock - startBlock) - (paidOut);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public nonReentrant {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 lastBlock = block.number < endBlock ? block.number : endBlock;

        if (lastBlock <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this)) +
            IERC20(troveToEsTrove[address(pool.lpToken)]).balanceOf(
                address(this)
            );
        if (lpSupply == 0) {
            pool.lastRewardBlock = lastBlock;
            return;
        }

        uint256 nrOfBlocks = lastBlock - (pool.lastRewardBlock);
        uint256 erc20Reward = (nrOfBlocks *
            (rewardPerBlock) *
            (pool.allocPoint)) / (totalAllocPoint);

        pool.accERC20PerShare =
            pool.accERC20PerShare +
            ((erc20Reward * (1e36)) / (lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to Farm for ERC20 allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool mirror
    ) public nonReentrant whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pendingAmount = (user.amount * (pool.accERC20PerShare)) /
                (1e36) -
                (user.rewardDebt);
            erc20Transfer(msg.sender, pendingAmount);
        }
        if (!mirror) {
            pool.lpToken.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.realAmount += _amount;
        } else {
            IERC20(troveToEsTrove[address(pool.lpToken)]).safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            user.mirrorAmount += _amount;
        }

        user.amount = user.amount + (_amount);
        user.rewardDebt = (user.amount * (pool.accERC20PerShare)) / (1e36);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from Farm.
    function withdraw(
        uint256 _pid,
        uint256 _amount,
        bool mirror
    ) public nonReentrant whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(
            user.amount >= _amount,
            "withdraw: can't withdraw more than deposit"
        );
        updatePool(_pid);
        uint256 pendingAmount = (user.amount * (pool.accERC20PerShare)) /
            (1e36) -
            (user.rewardDebt);
        erc20Transfer(msg.sender, pendingAmount);
        user.amount = user.amount - (_amount);
        user.rewardDebt = (user.amount * (pool.accERC20PerShare)) / (1e36);
        if (!mirror) {
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            user.realAmount -= _amount;
        } else {
            IERC20(troveToEsTrove[address(pool.lpToken)]).safeTransfer(
                address(msg.sender),
                _amount
            );
            user.mirrorAmount -= _amount;
        }
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Transfer ERC20 and update the required ERC20 to payout all rewards
    function erc20Transfer(address _to, uint256 _amount) internal {
        esTROVE(address(erc20)).mintEsTrove(_to, _amount);
        paidOut += _amount;
    }
}
