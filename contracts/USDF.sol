// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

import "./owner/Operator.sol";

contract USDF is ERC20Burnable, Operator {
    /**
     * @notice Constructs the USDF ERC-20 contract.
     */
    constructor() public ERC20("USD Flex", "USDF") {
        // Mints dollar to contract creator for initial pool setup
        _mint(msg.sender, 100000 ether);
    }

    /**
     * @notice Operator mints dollar to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of dollar to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override onlyOperator {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }
}
