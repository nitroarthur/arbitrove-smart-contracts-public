// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "ds-test/test.sol";
import "@mocks/MockERC20.sol";
import "@farm/Farm.sol";
import "@tokens/esTROVE.sol";

contract FarmTest is DSTest {
    Farm farm;
    MockERC20 public testTroveToken;
    MockERC20 public testEsTroveToken;

    function setUp() public {
        uint256 rewardPerBlock = 10;
        uint256 startBlock = 100;
        uint256 endBlock = 1000;

        // Give user testing tokens

        testTroveToken = new MockERC20("Trove", "TROVE");
        testEsTroveToken = new MockERC20("esTrove", "esTROVE");
        testTroveToken.mint(address(this), 1000);
        testEsTroveToken.mint(address(this), 1000);

        farm = new Farm();
        farm.init(testTroveToken, rewardPerBlock, startBlock, endBlock);
        farm.add(100, testTroveToken, true, address(testEsTroveToken));

        testTroveToken.approve(address(farm), type(uint256).max);
        testEsTroveToken.approve(address(farm), type(uint256).max);
    }

    // function test_setup() public {
    //     assertTrue(true);
    //     assertEq(address(farm.erc20()), address(testTroveToken));
    //     assertEq(farm.rewardPerBlock(), 10);
    //     assertEq(farm.startBlock(), 100);
    //     assertEq(farm.endBlock(), 1000);
    //     assertEq(farm.poolLength(), 1);
    //     assertEq(farm.totalAllocPoint(), 100);

    //     assertEq((testTroveToken.balanceOf(address(this))), 1000);
    //     assertEq((testEsTroveToken.balanceOf(address(this))), 1000);
    // }

    // function testDeposit() public {
    //     setUp();
    //     assertEq(farm.deposited(0, address(this)), 0);
    //     farm.deposit(0, 100, false);
    //     //farm.withdraw(0, 0, false);

    //     //     assertEq(farm.deposited(0, address(this)), 100);
    //     //     assertEq(farm.userInfo(0, address(this)).amount, 100);
    //     //     assertEq(farm.userInfo(0, address(this)).realAmount, 100);
    // }
}
