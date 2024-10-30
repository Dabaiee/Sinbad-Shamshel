// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./sToken.sol";

contract LendingPool is ReentrancyGuard, Ownable {
    // 映射：基础资产地址 => sToken 地址
    mapping(address => address) public sTokens;
    
    // 存款事件
    event Deposit(address indexed user, address indexed token, uint256 amount);
    // 取款事件
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    
    constructor() {}
    
    // 初始化新的资产市场
    function initializeMarket(
        address underlyingAsset,
        string memory name,
        string memory symbol,
        uint256 initialInterestRate
    ) external onlyOwner {
        require(sTokens[underlyingAsset] == address(0), "Market already exists");
        
        SToken sToken = new SToken(
            name,
            symbol,
            underlyingAsset,
            initialInterestRate
        );
        
        sTokens[underlyingAsset] = address(sToken);
    }
    
    // 存款功能
    function deposit(address asset, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(sTokens[asset] != address(0), "Market does not exist");
        
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
        
        SToken sToken = SToken(sTokens[asset]);
        sToken.mint(msg.sender, amount);
        
        emit Deposit(msg.sender, asset, amount);
    }
    
    // 取款功能
    function withdraw(address asset, uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be greater than 0");
        require(sTokens[asset] != address(0), "Market does not exist");
        
        SToken sToken = SToken(sTokens[asset]);
        uint256 userBalance = sToken.balanceOfWithInterest(msg.sender);
        require(userBalance >= amount, "Insufficient balance");
        
        // 修改这部分计算逻辑
        uint256 currentIndex = sToken.interestIndex();
        uint256 sTokenAmount = (amount * 1e18) / currentIndex;
        
        // 确保有足够的 sToken 余额
        require(sToken.balanceOf(msg.sender) >= sTokenAmount, "Insufficient sToken balance");
        
        sToken.burn(msg.sender, sTokenAmount);
        IERC20(asset).transfer(msg.sender, amount);
        
        emit Withdraw(msg.sender, asset, amount);
    }
    
    // 查询用户在特定市场的余额（包含利息）
    function getUserBalance(address asset, address user) external view returns (uint256) {
        require(sTokens[asset] != address(0), "Market does not exist");
        return SToken(sTokens[asset]).balanceOfWithInterest(user);
    }
} 