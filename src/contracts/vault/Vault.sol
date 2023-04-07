// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@vault/IVault.sol";
import "@strategy/IStrategy.sol";
import "@/AddressRegistry.sol";
import "@structs/structs.sol";

/// The Vault contract provides a secure and flexible platform for depositing and withdrawing coins, as well as approving and depositing ETH to strategies.
contract Vault is OwnableUpgradeable, IVault, ERC20Upgradeable {
    struct DepositParams {
        /// Deposit coin position in cpu array
        uint256 coinPositionInCPU;
        /// Deposit amount
        uint256 _amount;
        /// Vault's Coin price usd array
        CoinPriceUSD[] cpu;
        /// Expire time stamp
        uint256 expireTimestamp;
    }

    struct WithdrawalParams {
        /// Withdraw coin position in cpu array
        uint256 coinPositionInCPU;
        /// Withdrawal amount
        uint256 _amount;
        /// Vault's Coin price usd array
        CoinPriceUSD[] cpu;
        /// Expire time stamp
        uint256 expireTimestamp;
    }

    AddressRegistry public addressRegistry;
    /// USD price cap for coin
    /// only process certain amount of USD per coin
    mapping(address => uint256) public coinCap;
    /// block cap USD for block number
    mapping(uint => uint256) public blockCapCounter;
    /// only process certain amount of tx in USD per block
    uint256 public blockCapUSD;
    /// claimable debt amount for routers
    mapping(address => uint256) public debt;
    /// pool ratio denominator for pool ratio calculation
    uint256 public poolRatioDenominator;

    event SET_ADDRESS_REGISTRY(AddressRegistry);

    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    modifier onlyRouter() {
        require(
            msg.sender == addressRegistry.router(),
            "only router has permitted"
        );
        _;
    }

    function init829(
        AddressRegistry _addressRegistry
    ) external payable initializer {
        require(
            address(_addressRegistry) != address(0),
            "_addressRegistry address can't be zero"
        );
        require(msg.value >= 1e15);

        __Ownable_init();
        __ERC20_init("ALP", "ALP");
        addressRegistry = _addressRegistry;
        _mint(msg.sender, msg.value);
    }

    function setPoolRatioDenominator(
        uint256 _poolRatioDenominator
    ) external onlyOwner {
        poolRatioDenominator = _poolRatioDenominator;
    }

    /// @notice Set addressRegistry
    /// @param _addressRegistry Address registry contract
    function setAddressRegistry(
        AddressRegistry _addressRegistry
    ) external onlyOwner {
        require(
            address(_addressRegistry) != address(0),
            "_addressRegistry address can't be zero"
        );

        addressRegistry = _addressRegistry;

        emit SET_ADDRESS_REGISTRY(_addressRegistry);
    }

    /// @notice Set coin cap usd
    /// @param coin Address of coin to set cap
    /// @param cap Amount of cap to set
    function setCoinCapUSD(address coin, uint256 cap) external onlyOwner {
        coinCap[coin] = cap;
    }

    /// @notice Set block cap for vault
    /// @param cap Amount of cap to set
    function setBlockCap(uint256 cap) external onlyOwner {
        blockCapUSD = cap;
    }

    /// @notice Deposit. Note that the deposit amount is transferred to the vault from the router after checking the amount of ALP minted. If the amount of ALP minted is not correct, the call will revert and the router will refund.
    /// @param params Deposit params
    function deposit(DepositParams memory params) external onlyRouter {
        DepositFeeParams memory depositFeeParams = DepositFeeParams({
            cpu: params.cpu,
            vault: this,
            expireTimestamp: params.expireTimestamp,
            position: params.coinPositionInCPU,
            amount: params._amount
        });
        address coin = params.cpu[params.coinPositionInCPU].coin;
        uint256 __decimals = coin == address(0)
            ? 18
            : IERC20Metadata(coin).decimals();
        require(
            getAmountAcrossStrategies(coin) + params._amount < coinCap[coin],
            "Coin cap reached"
        );

        /// calculate deposit value
        /// formula: depositValue = coinPriceUSD * coinDepositAmount / 10**coinDecimal
        uint256 depositValue = (params.cpu[params.coinPositionInCPU].price *
            params._amount) / 10 ** __decimals;
        require(
            depositValue + blockCapCounter[block.number] < blockCapUSD,
            "Block cap reached"
        );

        /// update blockCapCounter with depositValue
        blockCapCounter[block.number] += depositValue;

        /// Get deposit fee and tvl before deposit
        (int256 fee, , uint256 tvlUSD1e18X) = addressRegistry
            .feeOracle()
            .getDepositFee(depositFeeParams);
        uint256 poolRatio = (depositValue * poolRatioDenominator) / tvlUSD1e18X;

        /// vault token mint
        /// fomula: poolRatio * totalSupply / (poolRatio denomiator) * (100 - fee) / (fee decominator)
        _mint(
            msg.sender,
            (((poolRatio * totalSupply()) / poolRatioDenominator) *
                uint256(100 - fee)) / 100
        );
    }

    /// @notice Withdraw. Note that the amount of ALP burned is checked before the router calls `claimDebt` subsequently to claim the token. If the amount of ALP burned is not correct, the call will revert and the router will refund.
    /// @param params Withdraw params
    function withdraw(WithdrawalParams memory params) external onlyRouter {
        WithdrawalFeeParams memory withdrawalFeeParams = WithdrawalFeeParams({
            cpu: params.cpu,
            vault: this,
            expireTimestamp: params.expireTimestamp,
            position: params.coinPositionInCPU,
            amount: params._amount
        });
        address coin = params.cpu[params.coinPositionInCPU].coin;
        uint256 __decimals = coin == address(0)
            ? 18
            : IERC20Metadata(coin).decimals();

        /// calculate withdrawal value
        /// formula: withdrawalValue = coinPriceUSD * withdrawalCoinAmount / 10**coinDecimal
        uint256 withdrawalValue = (params.cpu[params.coinPositionInCPU].price *
            params._amount) / 10 ** __decimals;
        require(
            withdrawalValue + blockCapCounter[block.number] < blockCapUSD,
            "Block cap reached"
        );
        blockCapCounter[block.number] += withdrawalValue;
        // no coin cap check for withdrawal

        /// Get withdrawal fee and tvl before withdraw
        (int256 fee, , uint256 tvlUSD1e18X) = addressRegistry
            .feeOracle()
            .getWithdrawalFee(withdrawalFeeParams);
        uint256 poolRatio = (withdrawalValue * poolRatioDenominator) /
            tvlUSD1e18X;

        /// burn vault token
        /// formula: poolRatio * totalSupply * (100 - fee) / 100 (fee decominator) / 10000 (poolRatio denomiator)
        _burn(
            msg.sender,
            (((poolRatio * totalSupply()) / poolRatioDenominator) *
                uint256(100 - fee)) / 100
        );

        /// increase claimable debt amount for withdrawing amount of coin later
        debt[coin] += params._amount;
    }

    /// @notice Claim `amount` debt from vault
    /// @param coin Address of coin to claim
    /// @param amount Amount of debt to claim
    function claimDebt(address coin, uint256 amount) external onlyRouter {
        require(debt[coin] >= amount, "insufficient debt amount for coin");
        debt[coin] -= amount;
        if (coin == address(0)) payable(msg.sender).transfer(amount);
        else require(IERC20(coin).transfer(msg.sender, amount));
    }

    /// @notice Approve `amount` of coin for strategy to use
    /// @param strategy Address of Strategy
    /// @param coin Address of coin
    /// @param amount Amount of coin to approve
    function approveStrategy(
        IStrategy strategy,
        address coin,
        uint256 amount
    ) external onlyOwner {
        require(
            addressRegistry.getWhitelistedStrategies(strategy),
            "strategy is not whitelisted"
        );

        /// verify coin is part of the strategy
        IStrategy[] memory strategies = addressRegistry.getCoinToStrategy(coin);
        uint256 i;
        for (; i < strategies.length; i++) {
            if (address(strategies[i]) == address(strategy)) break;
        }
        require(
            i == strategies.length,
            "provided coin is not the part of strategy"
        );

        /// approve coin for strategy
        require(
            IERC20(coin).approve(address(strategy), amount),
            "approve failed"
        );
    }

    /// @notice Deposit `amount` of ETH to strategy because ETH can't be approved. Note that this feature will not likely to be used. Trove mostly will be WETH based.
    /// @param strategy Address of Strategy
    /// @param amount Amount of ETH to deposit
    function depositETHToStrategy(
        IStrategy strategy,
        uint256 amount
    ) external onlyOwner {
        require(addressRegistry.getWhitelistedStrategies(strategy));
        (bool depositSuccess, ) = address(strategy).call{value: amount}("");
        require(depositSuccess, "Deposit failed");
    }

    /// @notice Withdraw `amount` of coin from vault
    /// @param coin Address of coin
    /// @param amount Amount of coin to withdraw
    function rebalance(
        address destination,
        address coin,
        uint256 amount
    ) external onlyOwner {
        require(addressRegistry.getWhitelistedRebalancer(destination));
        if (coin == address(0)) payable(destination).transfer(amount);
        else require(IERC20(coin).transfer(destination, amount));
    }

    /// @notice Get aggregated amount of coin for vault and strategies
    /// @param coin Address of coin
    /// @return value Aggregated amount of coin
    function getAmountAcrossStrategies(
        address coin
    ) public view returns (uint256 value) {
        if (coin == address(0)) {
            value += address(this).balance;
        } else {
            value += IERC20(coin).balanceOf(address(this));
        }
        IStrategy[] memory strategies = addressRegistry.getCoinToStrategy(coin);
        for (uint256 i; i < strategies.length; ) {
            value += strategies[i].getComponentAmount(coin);
            unchecked {
                i++;
            }
        }
    }
}
