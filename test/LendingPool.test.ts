import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, BigNumber } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("LendingPool", function () {
  let lendingPool: Contract;
  let mockToken: Contract;
  let sToken: Contract;
  let owner: SignerWithAddress;
  let user1: SignerWithAddress;
  let user2: SignerWithAddress;

  const INITIAL_SUPPLY = ethers.utils.parseEther("1000000");
  const INITIAL_INTEREST_RATE = ethers.utils.parseEther("0.1"); // 10% 年化利率
  
  beforeEach(async function () {
    // 获取测试账户
    [owner, user1, user2] = await ethers.getSigners();

    // 部署模拟代币
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("Mock Token", "MTK", INITIAL_SUPPLY);
    await mockToken.deployed();

    // 部署 LendingPool
    const LendingPool = await ethers.getContractFactory("LendingPool");
    lendingPool = await LendingPool.deploy();
    await lendingPool.deployed();

    // 初始化市场
    await lendingPool.initializeMarket(
      mockToken.address,
      "Savings Token",
      "sMTK",
      INITIAL_INTEREST_RATE
    );

    // 获取 sToken 地址
    const sTokenAddress = await lendingPool.sTokens(mockToken.address);
    sToken = await ethers.getContractAt("SToken", sTokenAddress);

    // 给测试用户转一些代币
    await mockToken.transfer(user1.address, ethers.utils.parseEther("1000"));
    await mockToken.transfer(user2.address, ethers.utils.parseEther("1000"));
  });

  describe("Market Initialization", function () {
    it("Should initialize market correctly", async function () {
      expect(await lendingPool.sTokens(mockToken.address)).to.not.equal(ethers.constants.AddressZero);
    });

    it("Should not allow initializing same market twice", async function () {
      await expect(
        lendingPool.initializeMarket(
          mockToken.address,
          "Savings Token",
          "sMTK",
          INITIAL_INTEREST_RATE
        )
      ).to.be.revertedWith("Market already exists");
    });
  });

  describe("Deposits", function () {
    const depositAmount = ethers.utils.parseEther("100");

    beforeEach(async function () {
      // 授权 LendingPool 使用代币
      await mockToken.connect(user1).approve(lendingPool.address, depositAmount);
    });

    it("Should allow deposits and mint correct amount of sTokens", async function () {
      await lendingPool.connect(user1).deposit(mockToken.address, depositAmount);
      
      const balance = await sToken.balanceOf(user1.address);
      expect(balance).to.equal(depositAmount);
      expect(await mockToken.balanceOf(lendingPool.address)).to.equal(depositAmount);
    });

    it("Should not allow zero deposits", async function () {
      await expect(
        lendingPool.connect(user1).deposit(mockToken.address, 0)
      ).to.be.revertedWith("Amount must be greater than 0");
    });
  });

  describe("Withdrawals", function () {
    const depositAmount = ethers.utils.parseEther("100");

    beforeEach(async function () {
      await mockToken.connect(user1).approve(lendingPool.address, depositAmount);
      await lendingPool.connect(user1).deposit(mockToken.address, depositAmount);
    });

    it("Should allow withdrawals", async function () {
      const initialBalance = await mockToken.balanceOf(user1.address);
      const withdrawAmount = depositAmount;
      
      // 获取用户的 sToken 余额（包含利息）
      const userBalance = await sToken.balanceOfWithInterest(user1.address);
      
      await lendingPool.connect(user1).withdraw(mockToken.address, withdrawAmount);
      
      // 验证基础代币余额
      const finalBalance = await mockToken.balanceOf(user1.address);
      expect(finalBalance).to.equal(initialBalance.add(withdrawAmount));
      
      // 获取剩余的 sToken 余额
      const remainingSTokens = await sToken.balanceOf(user1.address);
      const remainingSTokensWithInterest = await sToken.balanceOfWithInterest(user1.address);
      
      // 验证剩余的 sToken 数量很小（接近于0）
      expect(remainingSTokensWithInterest).to.be.lt(ethers.utils.parseEther("0.01"));
    });

    it("Should not allow withdrawing more than balance", async function () {
      const tooMuch = depositAmount.mul(2);
      await expect(
        lendingPool.connect(user1).withdraw(mockToken.address, tooMuch)
      ).to.be.revertedWith("Insufficient balance");
    });
  });

  describe("Interest Accrual", function () {
    const depositAmount = ethers.utils.parseEther("100");

    beforeEach(async function () {
      await mockToken.connect(user1).approve(lendingPool.address, depositAmount);
      await lendingPool.connect(user1).deposit(mockToken.address, depositAmount);
    });

    it("Should accrue interest over time", async function () {
      // 模拟时间经过
      await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]); // 1年
      await ethers.provider.send("evm_mine", []);

      const balanceWithInterest = await sToken.balanceOfWithInterest(user1.address);
      
      // 检查余额是否增加了大约10%（考虑一些舍入误差）
      expect(balanceWithInterest).to.be.gt(depositAmount);
      
      const expectedBalance = depositAmount.mul(110).div(100); // 预期余额应该约为本金的110%
      const difference = balanceWithInterest.sub(expectedBalance).abs();
      const tolerance = depositAmount.div(100); // 1% 的误差容忍度
      
      expect(difference).to.be.lt(tolerance);
    });
  });
}); 