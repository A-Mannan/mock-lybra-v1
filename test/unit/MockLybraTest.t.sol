// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {MockLybra} from "../../src/MockLybra.sol";
import {MockStETH} from "../../src/MockStETH.sol";
import {MockV3Aggregator} from "../../src/MockV3Aggregator.sol";
import {DeployMockLybra} from "../../script/DeployMockLybra.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract MockLybraTest is StdCheats, Test {
    MockLybra lybra;
    MockStETH stEth;
    MockV3Aggregator ethUsdPriceFeed;

    address public user = makeAddr("user");
    address public redeemer = makeAddr("redeemer");
    address public liquidator = makeAddr("liquidator");
    address public keepers = makeAddr("keepers");

    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant USER_SUBMIT_AMOUNT = 2 ether;
    uint256 public constant USER_MINT_AMOUNT = 1000e18;
    uint256 public constant REDEEM_AMOUNT = 1e18;
    uint256 public constant LIQUIDATION_AMOUNT = 1 ether;

    function setUp() public {
        DeployMockLybra deployer = new DeployMockLybra();
        (lybra, stEth, ethUsdPriceFeed) = deployer.run();
        if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
            vm.deal(redeemer, STARTING_USER_BALANCE);
            vm.deal(keepers, STARTING_USER_BALANCE);
            vm.deal(liquidator, STARTING_USER_BALANCE);
        }
    }

    function test_MintEUSDWithETH() public {
        // Initial values
        uint256 initialEUSDSupply = lybra.totalSupply();
        uint256 initialETHBalance = user.balance;

        vm.prank(user);
        lybra.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            user,
            USER_MINT_AMOUNT
        );

        // Assertions
        assertGt(lybra.totalSupply(), initialEUSDSupply);
        assertEq(user.balance, initialETHBalance - USER_SUBMIT_AMOUNT);

        assertGt(lybra.balanceOf(user), 0);
        assertEq(USER_MINT_AMOUNT, lybra.balanceOf(user));
    }

    function testMintEUSDWithstETH() public {
        uint256 initialETHBalance = user.balance;
        uint256 initialEUSDSupply = lybra.totalSupply();
        uint256 stETHAmountToDeposit = 1 ether;

        // Provide some stETH:
        vm.startPrank(user);
        stEth.submit{value: USER_SUBMIT_AMOUNT}(user);

        stEth.approve(address(lybra), stETHAmountToDeposit);

        lybra.depositStETHToMint(user, stETHAmountToDeposit, USER_MINT_AMOUNT);

        vm.stopPrank();

        // Assertions
        assertGt(lybra.totalSupply(), initialEUSDSupply);
        assertEq(user.balance, initialETHBalance - USER_SUBMIT_AMOUNT);

        assertGt(lybra.balanceOf(user), 0); // Ensure user received minted EUSD
        assertEq(USER_MINT_AMOUNT, lybra.balanceOf(user));
    }

    function testRevert_WhenMintInsufficientETH() public {
        vm.expectRevert("Deposit should not be less than 1 ETH.");
        vm.prank(user);
        lybra.depositEtherToMint{value: 0.99 ether}(user, USER_MINT_AMOUNT);
    }

    modifier WhenUserDepositedCollateralAndMintedEUSD() {
        vm.prank(user);
        lybra.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            user,
            USER_MINT_AMOUNT
        );
        _;
    }

    function test_UserCanBuyStEthIncomeAndTriggerRebaseRedemption()
        public
        WhenUserDepositedCollateralAndMintedEUSD
    {
        // Arrange
        uint256 otherDepositersMintAmount = 1e18;
        for (
            uint160 depositerIndex = 1;
            depositerIndex < 10;
            depositerIndex++
        ) {
            hoax(address(depositerIndex), STARTING_USER_BALANCE);
            lybra.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
                address(depositerIndex),
                otherDepositersMintAmount
            );
        }

        uint256 initialUserStEthEBalance = stEth.balanceOf(user);

        // Act

        vm.warp(10 days);

        vm.prank(user);
        lybra.excessIncomeDistribution(REDEEM_AMOUNT); // Trigger rebase

        // Assert

        assertGt(stEth.balanceOf(user), initialUserStEthEBalance);
        for (
            uint160 depositerIndex = 1;
            depositerIndex < 10;
            depositerIndex++
        ) {
            assertGt(
                lybra.balanceOf(address(depositerIndex)),
                otherDepositersMintAmount
            );
        }
    }

    function test_UserCanRigidRedeemCollateralForEUSD()
        public
        WhenUserDepositedCollateralAndMintedEUSD
    {
        // Arrange
        uint256 initialUserBorrowedAmount = lybra.getBorrowedOf(user);
        vm.prank(user);
        lybra.becomeRedemptionProvider(true);

        vm.startPrank(redeemer);
        lybra.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            redeemer,
            USER_MINT_AMOUNT
        );

        uint256 intialRedeemerStEthBalance = stEth.balanceOf(redeemer);

        // Act
        lybra.rigidRedemption(user, REDEEM_AMOUNT);

        vm.stopPrank();

        // Assert
        uint256 endingUserBorrowedAmount = lybra.getBorrowedOf(user);
        uint256 endingRedeemerStEthBalance = stEth.balanceOf(redeemer);
        assertGt(endingRedeemerStEthBalance, intialRedeemerStEthBalance);
        assertLt(endingUserBorrowedAmount, initialUserBorrowedAmount);
    }

    modifier WhenUserCollateralRateFallsBelowBadCollateralRate() {
        ethUsdPriceFeed.updateAnswer(180);
        _;
    }
    modifier WhenLiquidatorHasProvidedLiquidation() {
        vm.startPrank(liquidator);
        lybra.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            liquidator,
            USER_MINT_AMOUNT
        );
        lybra.approve(address(lybra), LIQUIDATION_AMOUNT);
        vm.stopPrank();
        _;
    }

    function test_UserCanBeLiquidated()
        public
        WhenUserDepositedCollateralAndMintedEUSD
        WhenLiquidatorHasProvidedLiquidation
        WhenUserCollateralRateFallsBelowBadCollateralRate
    {
        //Arrange
        uint256 initialUserBorrowedAmount = lybra.getBorrowedOf(user);
        uint256 initialLiquidatorStEthBalance = stEth.balanceOf(liquidator);

        // Act
        vm.prank(keepers);
        lybra.liquidation(liquidator, user, LIQUIDATION_AMOUNT);

        // Assert
        uint256 endingUserBorrowedAmount = lybra.getBorrowedOf(user);
        uint256 endingLiquidatorStEthBalance = stEth.balanceOf(liquidator);

        assertGt(endingLiquidatorStEthBalance, initialLiquidatorStEthBalance);
        assertLt(endingUserBorrowedAmount, initialUserBorrowedAmount);
    }

    function test_UserCanBeSuperLiquidated()
        public
        WhenUserDepositedCollateralAndMintedEUSD
        WhenLiquidatorHasProvidedLiquidation
        WhenUserCollateralRateFallsBelowBadCollateralRate
    {
        //Arrange
        uint256 initialUserBorrowedAmount = lybra.getBorrowedOf(user);
        uint256 initialLiquidatorStEthBalance = stEth.balanceOf(liquidator);

        // Act
        vm.prank(keepers);
        lybra.superLiquidation(liquidator, user, LIQUIDATION_AMOUNT);

        // Assert
        uint256 endingUserBorrowedAmount = lybra.getBorrowedOf(user);
        uint256 endingLiquidatorStEthBalance = stEth.balanceOf(liquidator);
        
        assertGt(endingLiquidatorStEthBalance, initialLiquidatorStEthBalance);
        assertLt(endingUserBorrowedAmount, initialUserBorrowedAmount);
    }
}
