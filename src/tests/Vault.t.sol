// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;
import "forge-std/Test.sol";
import "@mocks/MockERC20.sol";
import "@mocks/MockStrategy.sol";
import "@/FactoryArbitrove.sol";
import "../../script/FactoryArbitrove.s.sol";

contract VaultTest is Test, VyperDeployer {
    Vault public vault;
    MockERC20 public jonesToken;
    Router public router;
    AddressRegistry public ar;
    FeeOracle public feeOracle;

    address public whale = vm.addr(1);
    address public user1 = vm.addr(2);
    address public user2 = vm.addr(3);
    uint256 public mockCoin1Balance = 1e18;
    uint256 public mockUser1Balance = 1e18;
    uint256 public mockUser2Balance = 10e18;
    uint256 public mockVaultBalance = 1e19;

    function setUp() public {
        vm.startPrank(whale);
        vm.deal(whale, 1 ether);

        /// pre required contracts deployments
        FactoryArbitrove factory = new FactoryArbitrove();
        factory.upgradeImplementation(
            TProxy(payable(factory.vaultAddress())),
            address(new Vault())
        );

        router = Router(deployContract("src/contracts/Router.vy"));
        router.initialize(
            factory.vaultAddress(),
            factory.addressRegistryAddress(),
            whale
        );

        ar = AddressRegistry(factory.addressRegistryAddress());
        ar.init(FeeOracle(factory.feeOracleAddress()), address(router));
        Vault(payable(factory.vaultAddress())).init829{value: 1e18}(
            AddressRegistry(factory.addressRegistryAddress())
        );
        FeeOracle(factory.feeOracleAddress()).init(70, 0);

        /// setting up initial data
        CoinWeight[] memory cw = new CoinWeight[](2);

        feeOracle = FeeOracle(factory.feeOracleAddress());
        vault = Vault(payable(factory.vaultAddress()));
        /// set vault pool ratio denominator
        vault.setPoolRatioDenominator(1e18);
        jonesToken = new MockERC20("Jones Token", "JONES");
        jonesToken.mint(whale, mockCoin1Balance);
        jonesToken.mint(user1, mockUser1Balance);
        jonesToken.mint(user2, mockUser2Balance);
        jonesToken.mint(address(vault), mockVaultBalance);
        cw[0] = CoinWeight(address(0), 50);
        cw[1] = CoinWeight(address(jonesToken), 50);
        FeeOracle(factory.feeOracleAddress()).setTargets(cw);
        vault.setCoinCapUSD(address(jonesToken), 1000e18);
        vault.setBlockCap(100000e18);
        ExampleStrategy st = new ExampleStrategy();
        address[] memory x = new address[](1);
        x[0] = address(jonesToken);
        AddressRegistry(factory.addressRegistryAddress()).addStrategy(st, x);
        vm.stopPrank();
    }

    function testSetup() public {
        CoinWeight[] memory cw = new CoinWeight[](2);
        cw[0] = CoinWeight(address(0), 50);
        cw[1] = CoinWeight(address(jonesToken), 50);

        assertEq(
            vault.balanceOf(whale),
            mockCoin1Balance,
            "!whale's vault balance"
        );
        assertEq(feeOracle.getTargets()[0].coin, cw[0].coin, "!coin1 address");
        assertEq(feeOracle.getTargets()[1].coin, cw[1].coin, "!coin2 address");
        assertEq(router.owner(), whale, "!router owner");
        assertEq(
            ar.getCoinToStrategy(address(jonesToken)).length,
            0,
            "!strategy length for jonesToken"
        );
    }

    function testDepositAndWithdraw() public {
        vm.startPrank(whale);
        uint256 initialBalance = jonesToken.balanceOf(address(whale));
        uint256 expectedJTWhaleBalance = initialBalance - mockCoin1Balance;
        assertEq(
            initialBalance,
            mockCoin1Balance,
            "!whale's jonesToken initial balance"
        );
        jonesToken.approve(address(router), mockCoin1Balance);

        /// submit mint request to the router
        router.submitMintRequest(
            MintRequest(
                mockCoin1Balance,
                1000000000000,
                jonesToken,
                whale,
                block.timestamp + 1 days
            )
        );

        assertEq(
            jonesToken.balanceOf(whale),
            expectedJTWhaleBalance,
            "!expected whale's jonesToken balance after submit mint"
        );
        assertEq(
            jonesToken.balanceOf(address(router)),
            mockCoin1Balance,
            "!expected router jonesToken balance after submit mint"
        );
        assertEq(
            jonesToken.balanceOf(address(vault)),
            mockVaultBalance,
            "!expected vault jonesToken balance after submit mint"
        );

        CoinPriceUSD[] memory x = new CoinPriceUSD[](2);
        x[0] = CoinPriceUSD(address(0), 1600e4);
        x[1] = CoinPriceUSD(address(jonesToken), 20e4);
        assertEq(feeOracle.getTargets()[0].coin, x[0].coin);

        /// process mint request in the queue
        router.acquireLock();
        router.processMintRequest(OracleParams(x, block.timestamp + 1 days));
        router.releaseLock();

        uint256 routerVaultBalance = vault.balanceOf(address(router));
        uint256 whaleVaultBalance = vault.balanceOf(whale);
        assertEq(
            jonesToken.balanceOf(address(router)),
            0,
            "!expected router jonesToken balance after process mint"
        );
        assertEq(
            routerVaultBalance,
            0,
            "!expected router vault balance after process mint"
        );
        assertGt(
            whaleVaultBalance,
            0,
            "!expected whale vault balance after process mint"
        );

        /// Withdraw flow
        initialBalance = jonesToken.balanceOf(address(whale));
        assertEq(
            initialBalance,
            expectedJTWhaleBalance,
            "!whale's jonesToken initial balance"
        );
        vault.approve(address(router), whaleVaultBalance);

        /// submit burn request to the router
        router.submitBurnRequest(
            BurnRequest(
                mockCoin1Balance,
                mockCoin1Balance,
                jonesToken,
                whale,
                block.timestamp + 1 days
            )
        );

        router.acquireLock();
        router.processBurnRequest(OracleParams(x, block.timestamp + 1 days));
        router.releaseLock();

        assertEq(
            jonesToken.balanceOf(address(router)),
            0,
            "!expected router jonesToken balance after process burn"
        );
        assertEq(
            jonesToken.balanceOf(address(vault)),
            mockVaultBalance,
            "!expected vault's jonesToken balance after process burn"
        );
        assertEq(
            jonesToken.balanceOf(whale),
            mockCoin1Balance,
            "!expected whale's jonesToken balance"
        );
        assertLt(
            vault.balanceOf(whale),
            whaleVaultBalance,
            "!expected whale's vault balance"
        );
        vm.stopPrank();
    }

    function testMultiDepositAndWithdraw() public {
        multipleDeposit();
        multipleWithdraw();
    }

    function multipleDeposit() internal {
        CoinPriceUSD[] memory x = new CoinPriceUSD[](2);

        /// submit user2 mint request
        vm.startPrank(user2);
        jonesToken.approve(address(router), mockUser2Balance);
        router.submitMintRequest(
            MintRequest(
                mockUser2Balance,
                1000000000000,
                jonesToken,
                user2,
                block.timestamp + 1 days
            )
        );
        vm.stopPrank();

        /// submit user1 mint request
        vm.startPrank(user1);
        jonesToken.approve(address(router), mockUser1Balance);
        router.submitMintRequest(
            MintRequest(
                mockUser1Balance,
                1000000000000,
                jonesToken,
                user1,
                block.timestamp + 1 days
            )
        );
        vm.stopPrank();

        vm.startPrank(whale);

        /// coin price usd for user1 deposit
        x[0] = CoinPriceUSD(address(0), 1600e4);
        x[1] = CoinPriceUSD(address(jonesToken), 20e4);

        /// depsosit fee params for user1 deposit
        DepositFeeParams memory depositFeeParams = DepositFeeParams({
            cpu: x,
            vault: vault,
            expireTimestamp: block.timestamp + 1 days,
            position: 1,
            amount: mockUser1Balance
        });

        /// expected user1 vault balance after deposit
        uint256 expectedUser1VaultBalance = getExpectedDepositAmount(
            depositFeeParams
        );

        /// process mint request in the queue for user1
        router.acquireLock();
        router.processMintRequest(OracleParams(x, block.timestamp + 1 days));
        router.releaseLock();

        /// coin price usd for user2 deposit
        x[0] = CoinPriceUSD(address(0), 1600e4);
        x[1] = CoinPriceUSD(address(jonesToken), 200e4);

        /// deposit fee params for user2 deposit
        depositFeeParams = DepositFeeParams({
            cpu: x,
            vault: vault,
            expireTimestamp: block.timestamp + 1 days,
            position: 1,
            amount: mockUser2Balance
        });

        /// expected user2 vault balance after deposit
        uint256 expectedUser2VaultBalance = getExpectedDepositAmount(
            depositFeeParams
        );

        /// process mint request in the queue for user2
        router.acquireLock();
        router.processMintRequest(OracleParams(x, block.timestamp + 1 days));
        router.releaseLock();

        uint256 routerVaultBalance = vault.balanceOf(address(router));
        uint256 user1VaultBalance = vault.balanceOf(user1);
        uint256 user2VaultBalance = vault.balanceOf(user2);
        uint256 jonesTokenUser1Balance = jonesToken.balanceOf(user1);
        uint256 jonesTokenUser2Balance = jonesToken.balanceOf(user2);

        assertEq(
            user1VaultBalance,
            expectedUser1VaultBalance,
            "!user1 vault balance after deposit"
        );
        assertEq(
            user2VaultBalance,
            expectedUser2VaultBalance,
            "!user2 vault balance after deposit"
        );
        assertEq(routerVaultBalance, 0, "!router vault balance after deposit");
        assertEq(
            jonesTokenUser1Balance,
            0,
            "!user1 jonesToken balance after deposit"
        );
        assertEq(
            jonesTokenUser2Balance,
            0,
            "!user2 jonesToken balance after deposit"
        );
        vm.stopPrank();
    }

    function multipleWithdraw() internal {
        CoinPriceUSD[] memory x = new CoinPriceUSD[](2);
        uint256 initialUser1VaultBalance = vault.balanceOf(user1);
        uint256 initialUser2VaultBalance = vault.balanceOf(user2);

        /// submit user2 burn request
        vm.startPrank(user2);
        vault.approve(address(router), initialUser2VaultBalance);
        router.submitBurnRequest(
            BurnRequest(
                initialUser2VaultBalance,
                mockUser2Balance / 2,
                jonesToken,
                user2,
                block.timestamp + 1 days
            )
        );
        vm.stopPrank();

        /// submit user1 burn request
        vm.startPrank(user1);
        vault.approve(address(router), initialUser1VaultBalance);
        router.submitBurnRequest(
            BurnRequest(
                initialUser1VaultBalance,
                mockUser1Balance / 2,
                jonesToken,
                user1,
                block.timestamp + 1 days
            )
        );
        vm.stopPrank();

        vm.startPrank(whale);

        /// coin price usd for user1 withdraw
        x[0] = CoinPriceUSD(address(0), 1600e4);
        x[1] = CoinPriceUSD(address(jonesToken), 30e4);

        /// depsosit fee params for user1 withdraw
        WithdrawalFeeParams memory withdrawalFeeParams = WithdrawalFeeParams({
            cpu: x,
            vault: vault,
            expireTimestamp: block.timestamp + 1 days,
            position: 1,
            amount: mockUser1Balance / 2
        });

        /// expected user1 vault balance after withdraw
        uint256 expectedUser1VaultBalance = getExpectedWithdrawalAmount(
            withdrawalFeeParams
        );

        /// process burn request in the queue for user1
        router.acquireLock();
        router.processBurnRequest(OracleParams(x, block.timestamp + 1 days));
        router.releaseLock();

        /// coin price usd for user2 withdraw
        x[0] = CoinPriceUSD(address(0), 1600e4);
        x[1] = CoinPriceUSD(address(jonesToken), 200e4);

        /// withdraw fee params for user2 withdraw
        withdrawalFeeParams = WithdrawalFeeParams({
            cpu: x,
            vault: vault,
            expireTimestamp: block.timestamp + 1 days,
            position: 1,
            amount: mockUser2Balance / 2
        });

        /// expected user2 vault balance after withdraw
        uint256 expectedUser2VaultBalance = getExpectedWithdrawalAmount(
            withdrawalFeeParams
        );

        /// process burn request in the queue for user2
        router.acquireLock();
        router.processBurnRequest(OracleParams(x, block.timestamp + 1 days));
        router.releaseLock();

        uint256 routerVaultBalance = vault.balanceOf(address(router));
        uint256 user1VaultBalance = vault.balanceOf(user1);
        uint256 user2VaultBalance = vault.balanceOf(user2);
        uint256 jonesTokenUser1Balance = jonesToken.balanceOf(user1);
        uint256 jonesTokenUser2Balance = jonesToken.balanceOf(user2);

        assertEq(
            user1VaultBalance,
            initialUser1VaultBalance - expectedUser1VaultBalance,
            "!user1 vault balance after withdraw"
        );
        assertEq(
            user2VaultBalance,
            initialUser2VaultBalance - expectedUser2VaultBalance,
            "!user2 vault balance after withdraw"
        );
        assertEq(routerVaultBalance, 0, "!router vault balance after withdraw");
        assertEq(
            jonesTokenUser1Balance,
            mockUser1Balance / 2,
            "!user1 jonesToken balance after withdraw"
        );
        assertEq(
            jonesTokenUser2Balance,
            mockUser2Balance / 2,
            "!user2 jonesToken balance after withdraw"
        );
        vm.stopPrank();
    }

    function getExpectedDepositAmount(
        DepositFeeParams memory depositFeeParams
    ) internal view returns (uint256) {
        address coin = depositFeeParams.cpu[depositFeeParams.position].coin;
        uint256 __decimals = coin == address(0)
            ? 18
            : IERC20Metadata(coin).decimals();
        (int256 fee, , uint256 tvlUSD1e18X) = ar.feeOracle().getDepositFee(
            depositFeeParams
        );
        uint256 expectedDepositValue = (depositFeeParams.amount *
            depositFeeParams.cpu[depositFeeParams.position].price) /
            10 ** __decimals;
        uint256 expectedPoolRatio = (expectedDepositValue * 1e18) / tvlUSD1e18X;

        uint256 expectedVaultBalance = (((expectedPoolRatio *
            vault.totalSupply()) / 1e18) * uint256(100 - fee)) / 100;
        return expectedVaultBalance;
    }

    function getExpectedWithdrawalAmount(
        WithdrawalFeeParams memory withdrawalFeeParams
    ) internal view returns (uint256) {
        address coin = withdrawalFeeParams
            .cpu[withdrawalFeeParams.position]
            .coin;
        uint256 __decimals = coin == address(0)
            ? 18
            : IERC20Metadata(coin).decimals();
        (int256 fee, , uint256 tvlUSD1e18X) = ar.feeOracle().getWithdrawalFee(
            withdrawalFeeParams
        );
        uint256 expectedWithdrawalValue = (withdrawalFeeParams.amount *
            withdrawalFeeParams.cpu[withdrawalFeeParams.position].price) /
            10 ** __decimals;
        uint256 expectedPoolRatio = (expectedWithdrawalValue * 1e18) /
            tvlUSD1e18X;

        uint256 expectedVaultBalance = (((expectedPoolRatio *
            vault.totalSupply()) / 1e18) * uint256(100 - fee)) / 100;
        return expectedVaultBalance;
    }
}
