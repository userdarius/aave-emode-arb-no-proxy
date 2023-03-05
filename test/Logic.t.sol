// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./HelperTest.t.sol";
import "../src/Logic.sol";

import "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";


contract LogicTest is HelperTest {
    Logic logic;
    ISwapRouter bonjour = ISwapRouter(swapRouter);

    function setUp() public override {
        super.setUp();
        logic = new Logic(
            AAVE_ADDRESS_PROVIDER,
            swapRouter,
            quoteRouter,
            USER,
            Mainnet_wstETH,
            Mainnet_wETH        );
    }

    // function testTest() public {
    //     uint24 poolFee = 500; //UniswapV3Pool(address_pool).fee();

    //     vm.startPrank(USER);
    //     AaveTransferHelper.safeApprove(Mainnet_wETH, swapRouter, 1 ether);

    //     // Approve the router to spend DAI.

    //     ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
    //         .ExactInputSingleParams({
    //             tokenIn: Mainnet_wETH,
    //             tokenOut: Mainnet_wstETH,
    //             fee: poolFee,
    //             recipient: address(this),
    //             deadline: block.timestamp,
    //             amountIn: 1 ether,
    //             amountOutMinimum: 0,
    //             sqrtPriceLimitX96: 0
    //         });

    //     bonjour.exactInputSingle(params);

    //     vm.stopPrank();
    // }

    function testGetAmountIn() public {
        uint256 amountIn = logic.getAmountIn(1 ether, Mainnet_wstETH, Mainnet_wETH);
        console.log("amountIn: ", amountIn);
    }

    function testLongDepositedCraft() public {
        //uint256 amountIn = logic.getAmountIn();
        //console.log("amountIn: ", amountIn);

        console.log("BALANCE TOKEN1 LOGIC BEFORE:", IERC20(Mainnet_wETH).balanceOf(address(logic)));
        console.log("BALANCE TOKEN2 LOGIC BEFORE:", IERC20(Mainnet_wstETH).balanceOf(address(logic)));
        console.log("BALANCE TOKEN1 USER BEFORE:", IERC20(Mainnet_wETH).balanceOf(USER));
        console.log("BALANCE TOKEN2 USER BEFORE:", IERC20(Mainnet_wstETH).balanceOf(USER));


        vm.startPrank(USER);
        AaveTransferHelper.safeApprove(
            Mainnet_wETH,
            address(logic),
            3 ether
        );
        vm.stopPrank();
        logic.longDepositedCraft(3 ether, 10);
        console.log("BALANCE TOKEN1 LOGIC BETWEEN:", IERC20(Mainnet_wETH).balanceOf(address(logic)));
        console.log("BALANCE TOKEN2 LOGIC BETWEEN:", IERC20(Mainnet_wstETH).balanceOf(address(logic)));
        console.log("BALANCE TOKEN1 USER BETWEEN:", IERC20(Mainnet_wETH).balanceOf(USER));
        console.log("BALANCE TOKEN2 USER BETWEEN:", IERC20(Mainnet_wstETH).balanceOf(USER));

        vm.warp(block.timestamp + 100 days);

        logic.unwindPosition();

        console.log("BALANCE TOKEN1 LOGIC AFTER:", IERC20(Mainnet_wETH).balanceOf(address(logic)));
        console.log("BALANCE TOKEN2 LOGIC AFTER:", IERC20(Mainnet_wstETH).balanceOf(address(logic)));
        console.log("BALANCE TOKEN1 USER AFTER:", IERC20(Mainnet_wETH).balanceOf(USER));
        console.log("BALANCE TOKEN2 USER AFTER:", IERC20(Mainnet_wstETH).balanceOf(USER));
        console.log(logic.getAmountIn(5692433031387038829, Mainnet_wETH, Mainnet_wstETH));
    }
}
