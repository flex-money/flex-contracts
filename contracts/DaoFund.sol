// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/IDecimals.sol";
import "./interfaces/IKlayswapFactory.sol";
import "./interfaces/IKlayswapPool.sol";
import "./interfaces/IKlayExchange.sol";
import "./interfaces/IKlayswapSinglePool.sol";

contract DaoFund {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    /* ========== STATE VARIABLES ========== */

    // flags
    bool public initialized;

    address public operator;
    address public strategist;

    address[] public kspToDollarPath;
    mapping(address => uint256) public maxAmountToTrade;
    uint256 public usdtDecimals;

    // core components
    address public dollar;
    address public share;
    address public usdt;

    address public klayswapFactory;
    address public treasury;

    address public devFund;

    // protocol parameters
    uint256 public rewardDistributeRate;
    uint256 public shareBuyBackRate;
    uint256 public platformFee;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event SwapToken(address inputToken, address outputToken, uint256 amount);
    event FundHarvested(address pool, uint256 rewardAmount, uint256 distributedAmount, uint256 burnedAmount);
    event DollarBuyBacked(uint256 amount);
    event ShareBurned(uint256 amount);

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "DaoFund: caller is not the operator");
        _;
    }

    modifier onlyStrategist() {
        require(msg.sender == strategist || msg.sender == operator, "DaoFund: only strategist or operator can");
        _;
    }

    modifier notInitialized() {
        require(!initialized, "DaoFund: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _dollar,
        address _share,
        address _usdt,
        address _klayswapFactory,
        address _treasury,
        address[] memory _kspToDollarPath
    ) public notInitialized {
        dollar = _dollar;
        share = _share;
        usdt = _usdt;

        klayswapFactory = _klayswapFactory;
        treasury = _treasury;

        kspToDollarPath = _kspToDollarPath;
        usdtDecimals = IDecimals(usdt).decimals();

        rewardDistributeRate = 4000; // 40%
        shareBuyBackRate = 1000; // 10%
        platformFee = 1000; // 10%

        operator = _treasury;
        strategist = msg.sender;
        devFund = msg.sender;

        maxAmountToTrade[dollar] = 10000 ether;
        maxAmountToTrade[usdt] = 10000 * 10**usdtDecimals;
        maxAmountToTrade[address(0)] = 10000 ether;
        maxAmountToTrade[klayswapFactory] = 10000 ether;

        initialized = true;
        emit Initialized(msg.sender, block.number);
    }

    function setStrategist(address _strategist) external onlyStrategist {
        strategist = _strategist;
    }

    function setDevFund(address _devFund) external onlyStrategist {
        devFund = _devFund;
    }

    function setMaxAmountToTrade(address _token, uint256 _maxAmount) external onlyStrategist {
        require(_maxAmount > 0 ether && _maxAmount < 100000 ether, "out of range");
        maxAmountToTrade[_token] = _maxAmount;
    }

    function setTreasuryAllowance(uint256 _amount) external onlyStrategist {
        IERC20(dollar).safeIncreaseAllowance(address(treasury), _amount);
    }

    function setKspToDollarPath(address[] memory _kspToDollarPath) external onlyStrategist {
        kspToDollarPath = _kspToDollarPath;
    }

    function setRewardDistributeRate(uint256 _rewardDistributeRate) external onlyStrategist {
        require(_rewardDistributeRate.add(shareBuyBackRate).add(platformFee) <= 10000, "out of range");
        rewardDistributeRate = _rewardDistributeRate;
    }

    function setShareBuyBackRate(uint256 _shareBuyBackRate) external onlyStrategist {
        require(_shareBuyBackRate.add(rewardDistributeRate).add(platformFee) <= 10000, "out of range");
        shareBuyBackRate = _shareBuyBackRate;
    }

    function setPlatformFee(uint256 _platformFee) external onlyStrategist {
        require(_platformFee.add(rewardDistributeRate).add(shareBuyBackRate) <= 10000, "out of range");
        platformFee = _platformFee;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function buyBackDollar(uint256 _amount) external onlyOperator {
        address[] memory _path;
        _swapToken(usdt, dollar, _amount.div(10**(18 - usdtDecimals)), _path);
        emit DollarBuyBacked(_amount);
    }

    function burnShare(uint256 _amount) external onlyStrategist {
        IERC20(share).safeTransfer(BURN_ADDRESS, _amount);
        emit ShareBurned(_amount);
    }

    /* ========== TOKEN SWAP FUNCTIONS ========== */

    function _swapToken(
        address _inputToken,
        address _outputToken,
        uint256 _amount,
        address[] memory _path
    ) internal {
        uint256 _balance = IERC20(_inputToken).balanceOf(address(this));
        if (_amount > _balance) {
            _amount = _balance;
        }

        if (_amount == 0) return;
        uint256 _maxAmount = maxAmountToTrade[_inputToken];

        if (_maxAmount > 0 && _maxAmount < _amount) {
            _amount = _maxAmount;
        }

        IERC20(_inputToken).safeIncreaseAllowance(address(klayswapFactory), _amount);
        IKlayswapFactory(klayswapFactory).exchangeKctPos(_inputToken, _amount, _outputToken, 1, _path);
        emit SwapToken(_inputToken, _outputToken, _amount);
    }

    function swapToken(
        address _inputToken,
        address _outputToken,
        uint256 _amount,
        address[] memory _path
    ) external onlyStrategist {
        _swapToken(_inputToken, _outputToken, _amount, _path);
    }

    function swapKlay(
        address _outputToken,
        uint256 _amount,
        address[] memory _path
    ) external onlyStrategist {
        uint256 _balance = address(this).balance;
        if (_amount > _balance) {
            _amount = _balance;
        }

        if (_amount == 0) return;
        uint256 _maxAmount = maxAmountToTrade[address(0)];

        if (_maxAmount > 0 && _maxAmount < _amount) {
            _amount = _maxAmount;
        }

        IKlayswapFactory(klayswapFactory).exchangeKlayPos{value: _amount}(_outputToken, 1, _path);
        emit SwapToken(address(0), _outputToken, _amount);
    }

    /* ========== FUND FARMING FUNCTIONS ========== */

    function addKlayLiquidity(
        IKlayExchange klayExchange,
        uint256 amountA,
        uint256 amountB
    ) external onlyStrategist {
        address tokenB = klayExchange.tokenB();
        IERC20(tokenB).safeApprove(address(klayExchange), amountB);
        klayExchange.addKlayLiquidity{value: amountA}(amountB);
        IERC20(tokenB).safeApprove(address(klayExchange), 0);
    }

    function addKctLiquidity(
        IKlayExchange klayExchange,
        uint256 amountA,
        uint256 amountB
    ) external onlyStrategist {
        address tokenA = klayExchange.tokenA();
        address tokenB = klayExchange.tokenB();
        IERC20(tokenA).safeApprove(address(klayExchange), amountA);
        IERC20(tokenB).safeApprove(address(klayExchange), amountB);
        klayExchange.addKctLiquidity(amountA, amountB);
        IERC20(tokenA).safeApprove(address(klayExchange), 0);
        IERC20(tokenB).safeApprove(address(klayExchange), 0);
    }

    function removeLiquidity(IKlayExchange klayExchange, uint256 amount) external onlyStrategist {
        klayExchange.removeLiquidity(amount);
    }

    function depositKct(IKlayswapSinglePool klayswapSinglePool, uint256 amount) external onlyStrategist {
        address token = klayswapSinglePool.token();
        IERC20(token).safeIncreaseAllowance(address(klayswapSinglePool), amount);
        klayswapSinglePool.depositKct(amount);
    }

    function withdraw(IKlayswapSinglePool klayswapSinglePool, uint256 amount) external onlyStrategist {
        klayswapSinglePool.withdraw(amount);
    }

    function harvest(IKlayswapPool klayswapPool) external onlyStrategist {
        uint256 kspBefore = IERC20(klayswapFactory).balanceOf(address(this));
        klayswapPool.claimReward();
        uint256 kspAfter = IERC20(klayswapFactory).balanceOf(address(this));
        uint256 kspAmount = kspAfter.sub(kspBefore);
        if (kspAmount > 0) {
            // transfer to devFund
            IERC20(klayswapFactory).safeTransfer(devFund, kspAmount.mul(platformFee).div(10000));

            uint256 dollarBefore = IERC20(dollar).balanceOf(address(this));
            uint256 _percentage = rewardDistributeRate.add(shareBuyBackRate);
            _swapToken(klayswapFactory, dollar, kspAmount.mul(_percentage).div(10000), kspToDollarPath);
            uint256 dollarAfter = IERC20(dollar).balanceOf(address(this));
            uint256 dollarAmount = dollarAfter.sub(dollarBefore);

            // harvested dollar will be distributed to boardroom on the next epoch
            uint256 _distributeAmount = dollarAmount.mul(rewardDistributeRate).div(_percentage);
            IERC20(dollar).safeTransfer(treasury, _distributeAmount);

            // buyback burn share
            uint256 shareBefore = IERC20(share).balanceOf(address(this));
            address[] memory _path;
            _swapToken(dollar, share, dollarAmount.sub(_distributeAmount), _path);
            uint256 shareAfter = IERC20(share).balanceOf(address(this));
            uint256 shareAmount = shareAfter.sub(shareBefore);
            IERC20(share).safeTransfer(BURN_ADDRESS, shareAmount);

            emit FundHarvested(address(klayswapPool), kspAmount, _distributeAmount, shareAmount);
        }
    }

    receive() external payable {}
}
