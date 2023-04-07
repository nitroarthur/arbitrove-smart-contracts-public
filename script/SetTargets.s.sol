pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@/vault/FeeOracle.sol";
import "@/FactoryArbitrove.sol";
import "@/FactoryTokens.sol";

contract SetTargets is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        FactoryArbitrove factory = FactoryArbitrove(
            0xBD7B746213C1Ed7C7c35636d9C23f03a06410899
        );
        CoinWeight[] memory weights = new CoinWeight[](2);
        weights[0] = CoinWeight(address(0), 0);
        weights[1] = CoinWeight(
            0xf531B8F309Be94191af87605CfBf600D71C2cFe0,
            100
        );
        FeeOracle(factory.feeOracleAddress()).setTargets(weights);

        FeeOracle(factory.feeOracleAddress()).setMaxFee(50);
        Vault(payable(0xbF9093C5E09DbbeCF8F3C72162Da383e0A6397eB))
            .setCoinCapUSD(0xf531B8F309Be94191af87605CfBf600D71C2cFe0, 1e18);
        Vault(payable(0xbF9093C5E09DbbeCF8F3C72162Da383e0A6397eB))
            .setCoinCapUSD(address(0), 1e18);

        vm.stopBroadcast();
    }
}
