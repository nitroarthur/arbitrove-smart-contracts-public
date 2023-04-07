pragma solidity 0.8.17;

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "@vault/NonTransferrableVault.sol";
import "@/AddressRegistry.sol";
import "@/TProxy.sol";

contract FactoryArbitroveVaultOnly is Ownable {
    address public vaultAddress;

    constructor() {
        Vault v = new NonTransferrableVault();
        TProxy vProxy = new TProxy(address(v), address(this), "");
        vaultAddress = address(vProxy);
    }

    function upgradeImplementation(
        TProxy proxy,
        address newImplementation
    ) external onlyOwner {
        proxy.upgradeTo(newImplementation);
    }
}
