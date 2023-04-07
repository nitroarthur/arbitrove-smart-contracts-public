pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "@/FactoryTokens.sol";

contract MassUpdatePools is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address farmAddress = vm.envAddress("FARM_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        Farm(farmAddress).massUpdatePools();

        vm.stopBroadcast();
    }
}
