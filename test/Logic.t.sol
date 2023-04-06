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
            paraswapRouter,
            USER,
            Mainnet_wstETH,
            Mainnet_wETH
        );
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


    function testLongDepositedCraft() public {
        //uint256 amountIn = logic.getAmountIn();
        //console.log("amountIn: ", amountIn);

        console.log(
            "BALANCE TOKEN1 CONTRACT BEFORE:",
            IERC20(Mainnet_wETH).balanceOf(address(logic))
        );
        console.log(
            "BALANCE TOKEN2 CONTRACT BEFORE:",
            IERC20(Mainnet_wstETH).balanceOf(address(logic))
        );
        console.log(
            "BALANCE TOKEN1 USER BEFORE:",
            IERC20(Mainnet_wETH).balanceOf(USER)
        );
        console.log(
            "BALANCE TOKEN2 USER BEFORE:",
            IERC20(Mainnet_wstETH).balanceOf(USER)
        );

        vm.startPrank(USER);
        AaveTransferHelper.safeApprove(Mainnet_wETH, address(logic), 2 ether);
        uint256 shortTokenAmountToBorrow = 0; //TODO: read from a file
        logic.longDepositedCraft(2 ether, 2, 0, shortTokenAmountToBorrow, "");
        vm.stopPrank();
        console.log(
            "BALANCE TOKEN1 LOGIC BETWEEN:",
            IERC20(Mainnet_wETH).balanceOf(address(logic))
        );
        console.log(
            "BALANCE TOKEN2 LOGIC BETWEEN:",
            IERC20(Mainnet_wstETH).balanceOf(address(logic))
        );
        console.log(
            "BALANCE TOKEN1 USER BETWEEN:",
            IERC20(Mainnet_wETH).balanceOf(USER)
        );
        console.log(
            "BALANCE TOKEN2 USER BETWEEN:",
            IERC20(Mainnet_wstETH).balanceOf(USER)
        );

        //vm.warp(block.timestamp + 100 days);

        //logic.unwindPosition(1, 2);

        //console.log(
            //"BALANCE TOKEN1 LOGIC AFTER:",
            //IERC20(Mainnet_wETH).balanceOf(address(logic))
        //);
        //console.log(
            //"BALANCE TOKEN2 LOGIC AFTER:",
            //IERC20(Mainnet_wstETH).balanceOf(address(logic))
        //);
        //console.log(
            //"BALANCE TOKEN1 USER AFTER:",
            //IERC20(Mainnet_wETH).balanceOf(USER)
        //);
        //console.log(
            //"BALANCE TOKEN2 USER AFTER:",
            //IERC20(Mainnet_wstETH).balanceOf(USER)
        //);
    }
    //TODO: test shortDepositedCraft
    //TODO: test unwind
}
