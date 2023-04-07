pragma solidity 0.8.17;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import "openzeppelin-contracts-upgradeable/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@tokens/esTrove.sol";
import "@mocks/MockERC20.sol";

contract esTroveTest is DSTest, Test {
    using SafeERC20Upgradeable for ERC20Upgradeable;
    MockERC20 public testTroveToken;
    esTROVE esTrove;
    address trove;
    address stakingAddress;
    uint256 maxStakes;

    function setUp() public {
        esTrove = new esTROVE();
        testTroveToken = new MockERC20("Trove", "TROVE");
        testTroveToken.mint(address(esTrove), 100000000000000);
        trove = address(testTroveToken);
        stakingAddress = address(0x3);
        maxStakes = 1000;
        vm.warp(1641000000);
        esTrove.init(trove, maxStakes, stakingAddress);
        //esTrove.unpause();
        esTrove.mintEsTrove(address(this), 100000000000000);
        //esTrove.transfer(address(1), 10);
        esTrove.vest(50000000000000);
        esTrove.transfer(address(0x3),50000000000000);
        vm.warp(1641000000 + 86400);
        esTrove.unvest(25000000000000);
        console.log(esTrove.balanceOf(address(this)));
        console.log(testTroveToken.balanceOf(address(this)));
        (uint256 a, ) = esTrove.vesting(address(this));
        console.log(a);
    }

    function init_estrove() internal {
        
    }
}
