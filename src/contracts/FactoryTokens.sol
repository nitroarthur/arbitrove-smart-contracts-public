pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "@farm/Farm.sol";
import "@/TProxy.sol";

contract FactoryTokens is Ownable {
    address public farmAddress;
    address public esTroveAddress;

    constructor() {
        Farm farm = new Farm();
        esTROVE estrove = new esTROVE();
        TProxy farmProxy = new TProxy(address(farm), address(this), "");
        TProxy estroveProxy = new TProxy(address(estrove), address(this), "");
        farmAddress = address(farmProxy);
        esTroveAddress = address(estroveProxy);
    }

    function upgradeImplementation(
        TProxy proxy,
        address newImplementation
    ) external onlyOwner {
        proxy.upgradeTo(newImplementation);
    }
}
