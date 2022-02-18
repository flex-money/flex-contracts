// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./utils/ContractGuard.sol";
import "./lib/Stake.sol";

contract EcosystemFund is ContractGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Pool for Pool.Data;
    using Stake for Stake.Data;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant TOTAL_REWARD = 590000 ether;
    uint256 public constant VESTING_DURATION = 730 days; // 2 years

    /* ========== STATE VARIABLES ========== */

    address public admin;

    // flags
    bool public initialized;

    uint256 startTime;

    Pool.Data private _pool;
    mapping(address => Stake.Data) private _partners;

    IERC20 public share;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event PartnerAdded(address indexed user, uint256 point);
    event PartnerRemoved(address indexed user, uint256 point);
    event TokensClaimed(address indexed user, uint256 amount);

    /* =================== Modifier =================== */

    modifier onlyAdmin() {
        require(msg.sender == admin, "EcosystemFund: caller is not the admin");
        _;
    }

    modifier checkCondition() {
        require(now >= startTime, "EcosystemFund: not started yet");
        require(now < _pool.rewardEndTime, "EcosystemFund: ended");

        _;
    }

    modifier notInitialized() {
        require(!initialized, "EcosystemFund: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(IERC20 _share, uint256 _startTime) public notInitialized {
        share = _share;
        startTime = _startTime;

        _pool.rewardRate = TOTAL_REWARD.div(VESTING_DURATION);
        _pool.rewardEndTime = _startTime.add(VESTING_DURATION);

        initialized = true;
        admin = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function addPartner(address _account, uint256 _point) external checkCondition onlyAdmin {
        _pool.update();

        Stake.Data storage _partner = _partners[_account];
        _partner.update(_pool);

        _addPartner(_account, _point);
    }

    function removePartner(address _account, uint256 _point) external checkCondition onlyAdmin {
        _pool.update();

        Stake.Data storage _partner = _partners[_account];
        _partner.update(_pool);

        _removePartner(_account, _point);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function claim() external onlyOneBlock {
        _pool.update();

        Stake.Data storage _partner = _partners[msg.sender];
        _partner.update(_pool);

        _claim();
    }

    function rewardRate() external view returns (uint256) {
        return _pool.rewardRate;
    }

    function getTotalPoint() external view returns (uint256) {
        return _pool.totalDeposited;
    }

    function getPoint(address _account) external view returns (uint256) {
        Stake.Data storage _partner = _partners[_account];
        return _partner.totalDeposited;
    }

    function getUnclaimed(address _account) external view returns (uint256) {
        Stake.Data storage _partner = _partners[_account];
        return _partner.getUpdatedTotalUnclaimed(_pool);
    }

    // The fund MUST be updated before calling this function.
    function _addPartner(address _address, uint256 _point) internal {
        Stake.Data storage _partner = _partners[_address];

        _pool.totalDeposited = _pool.totalDeposited.add(_point);
        _partner.totalDeposited = _partner.totalDeposited.add(_point);

        emit PartnerAdded(_address, _point);
    }

    // The fund MUST be updated before calling this function.
    function _removePartner(address _address, uint256 _point) internal {
        Stake.Data storage _partner = _partners[_address];

        _pool.totalDeposited = _pool.totalDeposited.sub(_point);
        _partner.totalDeposited = _partner.totalDeposited.sub(_point);

        emit PartnerRemoved(_address, _point);
    }

    // The fund MUST be updated before calling this function.
    function _claim() internal {
        Stake.Data storage _partner = _partners[msg.sender];

        uint256 _claimAmount = _partner.totalUnclaimed;
        _partner.totalUnclaimed = 0;

        share.safeTransfer(msg.sender, _claimAmount);

        emit TokensClaimed(msg.sender, _claimAmount);
    }
}
