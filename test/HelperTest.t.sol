// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

contract HelperTest is Test {
    address DEPLOYER = makeAddr("DEPLOYER");
    address USER = makeAddr("USER");
    address REGISTRY = makeAddr("REGISTRY");
    address AAVE_ADDRESS_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address Mainnet_wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address Mainnet_wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address Mainnet_stETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address quoteRouter = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    function setUp() public virtual {
        deal(DEPLOYER, 100 ether);
        deal(USER, 100 ether);
        deal(Mainnet_wETH, USER, 10 ether);
        deal(Mainnet_wstETH, USER, 10 ether);
        //vm.startPrank(USER);
        //address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0).call(abi.encodeWithSignature("unwrap(uint256)", 4 ether));
        //vm.stopPrank();
        console.log("dealt the money to deployer and user");
    }
}
