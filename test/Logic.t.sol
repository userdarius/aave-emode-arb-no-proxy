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

    // function testConstructor() public {
    //     assertEq(logic.aaveAddressProvider(), AAVE_ADDRESS_PROVIDER);
    //     assertEq(logic.uniswapRouter(), UNISWAP_ROUTER);
    //     assertEq(logic.wETH(), Mainnet_wETH);
    //     assertEq(logic.wstETH(), Mainnet_wstETH);
    // }

    function testGetAmountIn() public {
        uint256 amountIn = logic.getAmountIn();
        console.log("amountIn: ", amountIn);
    }
}
