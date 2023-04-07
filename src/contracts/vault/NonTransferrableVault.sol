// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@vault/Vault.sol";
import "@strategy/IStrategy.sol";
import "@/AddressRegistry.sol";
import "@structs/structs.sol";

contract NonTransferrableVault is Vault {
    constructor() Vault() {}

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(msg.sender == owner(), "Only owner can transfer");
        super._beforeTokenTransfer(from, to, amount);
    }

    function bulkTransferALP(
        address[] calldata recipients,
        uint256[] calldata amounts
    ) external onlyOwner {
        require(recipients.length == amounts.length, "Length mismatch");
        for (uint i; i < recipients.length; ) {
            _transfer(msg.sender, recipients[i], amounts[i]);
            unchecked {
                i++;
            }
        }
    }
}
