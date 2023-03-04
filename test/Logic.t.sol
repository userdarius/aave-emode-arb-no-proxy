// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./HelperTest.t.sol";
import "../src/Logic.sol";

contract LogicTest is HelperTest {
    Logic logic;

    function setUp() public override {
        super.setUp();
        logic = new Logic(
            AAVE_ADDRESS_PROVIDER,
            swapRouter,
            quoteRouter,
            USER,
            Mainnet_wETH,
            Mainnet_wstETH
        );
    }

    function testGetAmountIn() public {
        uint256 amountIn = logic.getAmountIn(10000);
        console.log("amountIn: ", amountIn);
    }

    function testLongDepositedCraft() public {
        uint256 amountIn = logic.getAmountIn(1 ether);
        console.log("amountIn: ", amountIn);
        vm.startPrank(USER);
        AaveTransferHelper.safeApprove(
            Mainnet_wstETH,
            address(logic),
            amountIn
        );
        logic.longDepositedCraft(amountIn, 1 ether);
        vm.stopPrank();
    }
}
