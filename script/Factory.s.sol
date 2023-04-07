pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "@/FactoryTokens.sol";

contract DeployFactory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address troveAddress = vm.envAddress("TROVE_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        FactoryTokens factory = new FactoryTokens();
        esTROVE(factory.esTroveAddress()).init(
            troveAddress,
            360,
            factory.farmAddress()
        );
        Farm(factory.farmAddress()).init(
            IERC20(factory.esTroveAddress()),
            30e18,
            3575,
            0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
        );

        console.log("esTROVE contract: ");
        console.log(factory.esTroveAddress());
        console.log("Farm contract: ");
        console.log(factory.farmAddress());

        Farm(factory.farmAddress()).add(
            1,
            IERC20(troveAddress),
            false,
            factory.esTroveAddress()
        );
        Farm(factory.farmAddress()).pause();
        esTROVE(factory.esTroveAddress()).pause();
        vm.stopBroadcast();
    }
}
