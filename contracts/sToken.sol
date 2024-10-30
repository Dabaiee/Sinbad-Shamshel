// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title SToken
 * @dev 实现类似 AAVE 的存款代币，支持自动累积利息
 */
contract SToken is ERC20, Ownable, ReentrancyGuard {
    // 基础资产的地址（如 DAI、USDC 等）
    address public underlyingAsset;
    
    // 年化利率（以 1e18 为基数）
    uint256 public interestRate;
    
    // 上次利息更新时间
    uint256 public lastUpdateTimestamp;
    
    // 累积利率指数，初始值为 1e18
    uint256 public interestIndex;
    
    // 常量
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant INITIAL_INDEX = 1e18;
    uint256 private constant PRECISION = 1e18;
    
    /**
     * @dev 构造函数
     * @param name 代币名称
     * @param symbol 代币符号
     * @param _underlyingAsset 基础资产地址
     * @param _initialInterestRate 初始年化利率
     */
    constructor(
        string memory name,
        string memory symbol,
        address _underlyingAsset,
        uint256 _initialInterestRate
    ) ERC20(name, symbol) {
        underlyingAsset = _underlyingAsset;
        interestRate = _initialInterestRate;
        lastUpdateTimestamp = block.timestamp;
        interestIndex = INITIAL_INDEX;
    }
    
    /**
     * @dev 更新累积利率指数
     * 根据经过的时间计算并更新利率指数
     */
    function updateInterestIndex() public {
        uint256 timeDelta = block.timestamp - lastUpdateTimestamp;
        if (timeDelta > 0) {
            // 计算累积利率：(利率 * 时间) / 年
            uint256 accumulatedRate = (interestRate * timeDelta) / SECONDS_PER_YEAR;
            // 更新指数：当前指数 * (1 + 累积利率)
            interestIndex = (interestIndex * (PRECISION + accumulatedRate)) / PRECISION;
            lastUpdateTimestamp = block.timestamp;
        }
    }
    
    /**
     * @dev 计算用户实际余额（包含累积利息）
     * @param account 用户地址
     * @return 包含利息的余额
     */
    function balanceOfWithInterest(address account) public view returns (uint256) {
        uint256 currentIndex = interestIndex;
        uint256 timeDelta = block.timestamp - lastUpdateTimestamp;
        
        if (timeDelta > 0) {
            uint256 accumulatedRate = (interestRate * timeDelta) / SECONDS_PER_YEAR;
            currentIndex = (currentIndex * (PRECISION + accumulatedRate)) / PRECISION;
        }
        
        uint256 normalizedBalance = balanceOf(account);
        return (normalizedBalance * currentIndex) / INITIAL_INDEX;
    }
    
    /**
     * @dev 铸造代币（只能由 LendingPool 调用）
     * @param account 接收代币的地址
     * @param amount 铸造数量
     */
    function mint(address account, uint256 amount) external onlyOwner {
        updateInterestIndex();
        _mint(account, amount);
    }
    
    /**
     * @dev 销毁代币（只能由 LendingPool 调用）
     * @param account 销毁代币的地址
     * @param amount 销毁数量
     */
    function burn(address account, uint256 amount) external onlyOwner {
        updateInterestIndex();
        _burn(account, amount);
    }
    
    /**
     * @dev 设置新的利率（只能由所有者调用）
     * @param newRate 新的年化利率
     */
    function setInterestRate(uint256 newRate) external onlyOwner {
        updateInterestIndex();
        interestRate = newRate;
    }
} 