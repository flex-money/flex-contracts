// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";

import "./owner/Operator.sol";

contract FlexToken is ERC20Burnable, Operator {
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 2400000 ether;
    uint256 public constant PREMINT_REWARD_ALLOCATION = 5000 ether;
    uint256 public constant ECOSYSTEM_FUND_POOL_ALLOCATION = 590000 ether;

    bool public rewardPoolDistributed = false;

    constructor() public ERC20("Flex Token", "FLEX") {
        _mint(msg.sender, 5000 ether); // mint Flex for initial pools deployment
    }

    /**
     * @notice distribute to reward pools (only once)
     */
    function distributeReward(
        address _farmingIncentiveFund,
        address _premint,
        address _ecosystemFund
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        require(_premint != address(0), "!_premint");
        require(_ecosystemFund != address(0), "!_ecosystemFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
        _mint(_premint, PREMINT_REWARD_ALLOCATION);
        _mint(_ecosystemFund, ECOSYSTEM_FUND_POOL_ALLOCATION);
    }

    function burn(uint256 amount) public override onlyOperator {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }
}
