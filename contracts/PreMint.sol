// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./utils/ContractGuard.sol";
import "./owner/Operator.sol";
import "./lib/Stake.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IDecimals.sol";

contract PreMint is ContractGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Pool for Pool.Data;
    using Stake for Stake.Data;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant TOTAL_REWARD = 5000 ether;
    uint256 public constant VESTING_DURATION = 7 days;

    /* ========== STATE VARIABLES ========== */

    // flags
    bool public initialized;

    uint256 public startTime;

    Pool.Data private _pool;
    mapping(address => Stake.Data) private _stakes;

    address public dollar;
    address public share;
    address public usdt;

    address public treasury;
    address public daoFund;

    uint256 public usdtDecimals;
    uint256 public exchageRate;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event TokensMinted(address indexed user, uint256 amount);
    event TokensClaimed(address indexed user, uint256 amount);

    /* =================== Modifier =================== */

    modifier checkCondition() {
        require(now >= startTime, "PreMint: not started yet");
        require(now < _pool.rewardEndTime, "PreMint: ended");

        _;
    }

    modifier notInitialized() {
        require(!initialized, "PreMint: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _dollar,
        address _share,
        address _usdt,
        address _treasury,
        address _daoFund,
        uint256 _startTime
    ) public notInitialized {
        dollar = _dollar;
        share = _share;
        usdt = _usdt;

        treasury = _treasury;
        daoFund = _daoFund;
        startTime = _startTime;

        exchageRate = 9900;
        usdtDecimals = IDecimals(usdt).decimals();

        _pool.rewardRate = TOTAL_REWARD.div(VESTING_DURATION);
        _pool.rewardEndTime = _startTime.add(VESTING_DURATION);

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function mint(uint256 _amount) external onlyOneBlock checkCondition {
        _pool.update();

        Stake.Data storage _stake = _stakes[msg.sender];
        _stake.update(_pool);

        _mint(_amount);
    }

    function claim() external onlyOneBlock {
        _pool.update();

        Stake.Data storage _stake = _stakes[msg.sender];
        _stake.update(_pool);

        _claim();
    }

    function rewardRate() external view returns (uint256) {
        return _pool.rewardRate;
    }

    function getTotalMinted() external view returns (uint256) {
        return _pool.totalDeposited;
    }

    function getMinted(address _account) external view returns (uint256) {
        Stake.Data storage _stake = _stakes[_account];
        return _stake.totalDeposited;
    }

    function getUnclaimed(address _account) external view returns (uint256) {
        Stake.Data storage _stake = _stakes[_account];
        return _stake.getUpdatedTotalUnclaimed(_pool);
    }

    // The fund MUST be updated before calling this function.
    function _mint(uint256 _amount) internal {
        Stake.Data storage _stake = _stakes[msg.sender];

        uint256 _mintAmount = _amount.mul(10**(18 - usdtDecimals)).mul(exchageRate).div(10000);

        _pool.totalDeposited = _pool.totalDeposited.add(_mintAmount);
        _stake.totalDeposited = _stake.totalDeposited.add(_mintAmount);

        IERC20(usdt).safeTransferFrom(msg.sender, daoFund, _amount);
        IBasisAsset(dollar).mint(msg.sender, _mintAmount);

        emit TokensMinted(msg.sender, _mintAmount);
    }

    // The fund MUST be updated before calling this function.
    function _claim() internal {
        Stake.Data storage _stake = _stakes[msg.sender];

        uint256 _claimAmount = _stake.totalUnclaimed;
        _stake.totalUnclaimed = 0;

        IERC20(share).safeTransfer(msg.sender, _claimAmount);

        emit TokensClaimed(msg.sender, _claimAmount);
    }

    function transferDollarOwnershipToTreasury() external {
        require(now >= _pool.rewardEndTime, "PreMint: not ended");
        Operator(dollar).transferOperator(treasury);
        Operator(dollar).transferOwnership(treasury);
    }
}
