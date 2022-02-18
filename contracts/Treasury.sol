// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./lib/Babylonian.sol";
import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IBoardroom.sol";
import "./interfaces/IDaoFund.sol";

/**
 * @title Flex Treasury contract
 * @notice Monetary policy logic to adjust supplies of dollar
 */
contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 6 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized;

    // epoch
    uint256 public startTime;
    uint256 public epoch;

    // core components
    address public dollar;
    address public share;

    address public boardroom;
    address public daoFund;
    address public dollarOracle;

    // price
    uint256 public dollarPriceOne;
    uint256 public dollarPriceCeiling;
    uint256 public dollarPriceFloor;
    uint256 public previousEpochDollarPrice;

    // protocol parameters
    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public seigniorageExpansionRate;
    uint256 public daoFundSharedPercent;
    uint256 public daoFundBuyBackPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFunded(uint256 timestamp, uint256 seigniorage);
    event DollarBurned(uint256 timestamp, uint256 dollarAmount);

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition() {
        require(now >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch() {
        require(now >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
    }

    modifier checkOperator() {
        require(
            IBasisAsset(dollar).operator() == address(this) &&
                IBasisAsset(share).operator() == address(this) &&
                Operator(boardroom).operator() == address(this) &&
                Operator(daoFund).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized() {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // flags
    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    // oracle
    function getDollarPrice() public view returns (uint256 dollarPrice) {
        try IOracle(dollarOracle).consult(dollar, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert("Treasury: failed to consult dollar price from the oracle");
        }
    }

    function getDollarUpdatedPrice() public view returns (uint256 dollarPrice) {
        try IOracle(dollarOracle).twap(dollar, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert("Treasury: failed to consult dollar price from the oracle");
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _dollar,
        address _share,
        uint256 _startTime
    ) public notInitialized {
        dollar = _dollar;
        share = _share;
        startTime = _startTime;

        dollarPriceOne = 10**18;
        dollarPriceCeiling = dollarPriceOne.mul(1003).div(1000);
        dollarPriceFloor = dollarPriceOne.mul(997).div(1000);

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 500000 ether, 1000000 ether, 1500000 ether, 2000000 ether, 5000000 ether, 10000000 ether, 20000000 ether, 50000000 ether];
        maxExpansionTiers = [450, 400, 350, 300, 250, 200, 150, 125, 100];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion
        seigniorageExpansionRate = 3000; // (TWAP - 1) * 100% * 30%
        daoFundSharedPercent = 5000; // (TWAP - 1) * 100% * 30% * 50%
        daoFundBuyBackPercent = 1000; // (1 - TWAP) * 100% * 10%

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function setDaoFund(address _daoFund) external onlyOperator {
        daoFund = _daoFund;
    }

    function setDollarOracle(address _dollarOracle) external onlyOperator {
        dollarOracle = _dollarOracle;
    }

    function setDollarPriceCeiling(uint256 _dollarPriceCeiling) external onlyOperator {
        require(_dollarPriceCeiling >= dollarPriceOne && _dollarPriceCeiling <= dollarPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        dollarPriceCeiling = _dollarPriceCeiling;
    }

    function setDollarPriceFloor(uint256 _dollarPriceFloor) external onlyOperator {
        require(_dollarPriceFloor <= dollarPriceOne && _dollarPriceFloor >= dollarPriceOne.mul(80).div(100), "out of range"); // [$0.8, $1.0]
        dollarPriceFloor = _dollarPriceFloor;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < 8) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }

    function setDaoFundSharedPercent(uint256 _daoFundSharedPercent) external onlyOperator {
        require(_daoFundSharedPercent <= 10000 && _daoFundSharedPercent >= 0, "out of range"); // under 100%
        daoFundSharedPercent = _daoFundSharedPercent;
    }

    function setDaoFundBuyBackPercent(uint256 _daoFundBuyBackPercent) external onlyOperator {
        require(_daoFundBuyBackPercent <= 10000 && _daoFundBuyBackPercent >= 0, "out of range"); // under 100%
        daoFundBuyBackPercent = _daoFundBuyBackPercent;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateDollarPrice() internal {
        try IOracle(dollarOracle).update() {} catch {}
    }

    function _sendToBoardRoom() internal {
        uint256 _amount = IERC20(dollar).balanceOf(address(this));
        if (_amount > 0) {
            IERC20(dollar).safeIncreaseAllowance(boardroom, _amount);
            IBoardroom(boardroom).allocateSeigniorage(_amount);
            emit BoardroomFunded(now, _amount);
        }
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _dollarSupply) internal returns (uint256) {
        for (uint8 tierId = 8; tierId >= 0; --tierId) {
            if (_dollarSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateDollarPrice();
        previousEpochDollarPrice = getDollarPrice();
        uint256 dollarSupply = IERC20(dollar).totalSupply();

        if (previousEpochDollarPrice > dollarPriceCeiling) {
            // Expansion ($dollar Price > 1$): there is some seigniorage to be allocated
            uint256 _percentage = previousEpochDollarPrice.sub(dollarPriceOne).mul(seigniorageExpansionRate).div(10000);
            uint256 _mse = _calculateMaxSupplyExpansionPercent(dollarSupply).mul(1e14);
            if (_percentage > _mse) {
                _percentage = _mse;
            }
            uint256 _mintAmount = dollarSupply.mul(_percentage).div(1e18);
            IBasisAsset(dollar).mint(address(this), _mintAmount);
            if (daoFundSharedPercent > 0) {
                uint256 _savedForDaoFund = _mintAmount.mul(daoFundSharedPercent).div(10000);
                IERC20(dollar).safeTransfer(daoFund, _savedForDaoFund);
                emit DaoFunded(now, _savedForDaoFund);
            }
        } else if (previousEpochDollarPrice < dollarPriceFloor) {
            // Contraction ($dollar Price < 1$): buyback and burn dollar
            if (daoFundBuyBackPercent > 0) {
                uint256 _percentage = dollarPriceOne.sub(previousEpochDollarPrice).mul(daoFundBuyBackPercent).div(10000);

                uint256 balanceBefore = IERC20(dollar).balanceOf(daoFund);
                IDaoFund(daoFund).buyBackDollar(dollarSupply.mul(_percentage).div(1e18));
                uint256 balanceAfter = IERC20(dollar).balanceOf(daoFund);

                uint256 _burnAmount = balanceAfter.sub(balanceBefore);
                IBasisAsset(dollar).burnFrom(daoFund, _burnAmount);
                emit DollarBurned(now, _burnAmount);
            }
        }
        _sendToBoardRoom();
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(dollar), "dollar");
        require(address(_token) != address(share), "share");
        _token.safeTransfer(_to, _amount);
    }

    /* ========== BOARDROOM CONTROLLING FUNCTIONS ========== */

    function boardroomSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IBoardroom(boardroom).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function boardroomGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }

    /* ========== DAOFUND CONTROLLING FUNCTIONS ========== */

    function burnDollarFromDaoFund(uint256 _amount) external onlyOperator {
        require(_amount > 0, "Treasury: cannot burn dollar with zero amount");
        IBasisAsset(dollar).burnFrom(address(daoFund), _amount);
        emit DollarBurned(now, _amount);
    }
}
