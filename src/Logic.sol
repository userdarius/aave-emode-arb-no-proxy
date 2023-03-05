//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlashLoanSimpleReceiverBase} from "lib/aave-v3-core/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "lib/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "lib/aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./AaveTransferHelper.sol";
import "../lib/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import "./interfaces/IFlashLoan.sol";
import "forge-std/Test.sol";

contract Logic is FlashLoanSimpleReceiverBase, Test {
    address public owner;
    address public address_short;
    address public address_long;
    bool internal unwind = false;

    address public immutable swapRouterAddr;
    address public immutable quoterRouterAddr;

    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    constructor(
        address _aaveAddressProvider,
        address _swapRouterAddr,
        address _quoterRouterAddr,
        address _owner,
        address _address_short,
        address _address_long
            )
        FlashLoanSimpleReceiverBase(
            IPoolAddressesProvider(_aaveAddressProvider)
        )
    {
        swapRouterAddr = _swapRouterAddr;
        quoterRouterAddr = _quoterRouterAddr;
        owner = _owner;
        address_short = _address_short;
        address_long = _address_long;
    }

    function getAmountIn(uint256 amount, address token0, address token1) public returns (uint256) {
        (uint256 amountIn, , , ) = IQuoterV2(quoterRouterAddr)
            .quoteExactOutputSingle(
                IQuoterV2.QuoteExactOutputSingleParams({
                    tokenIn: token0,
                    tokenOut: token1,
                    amount: amount,
                    fee: 500,
                    sqrtPriceLimitX96: 0
                })
            );
        return amountIn;
    }

    function getAdddressShort() external view returns (address) {
        return address_short;
    }

    function getAddressLong() external view returns (address) {
        return address_long;
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    function craftPosition(
        bool depositIsLong,
        uint256 _amountDeposited,
        uint256 _leverageRatio
    ) public onlyOwner returns (bool success) {
        if (depositIsLong) {
            longDepositedCraft(_amountDeposited, _leverageRatio);
        } else {
            //shortDepositedCraft(_amountDeposited, _leverageRatio);
        }
        success = true;
        return success;
    }

    function longDepositedCraft(
        uint256 _amountDeposited,
        uint256 _leverageRatio
    ) public returns (uint256 amount) {
        //pulling the tokens from the user into the contract
        AaveTransferHelper.safeTransferFrom(
            address_long,
            owner,
            address(this),
            _amountDeposited
        );

        amount = _amountDeposited * (_leverageRatio - 1);

        requestFlashLoan(address_long, amount); // TODO: add the necessary arguments

        return amount;
    }

    // function shortDepositedCraft(
    //     uint256 _amountDeposited,
    //     uint256 _leverageRatio
    // ) internal returns (uint256) {
    //     uint256 amountIn = getAmountIn(
    //         address_short,
    //         address_long,
    //         _amountDeposited,
    //         100
    //     );

    //     uint256 amount = amountIn * _amountDeposited * _leverageRatio;

    //     AaveTransferHelper.safeTransferFrom(
    //         address_long,
    //         msg.sender,
    //         address(this),
    //         amountIn * _amountDeposited
    //     );

    //     requestFlashLoan(address_long, amount);

    //     uint16 referralCode = 0;
    //     AaveTransferHelper.safeTransferFrom(
    //         address_long,
    //         owner,
    //         address(this),
    //         amount
    //     );
    //     AaveTransferHelper.safeApprove(address_long, address(POOL), amount);
    //     POOL.supply(address_long, amount, msg.sender, referralCode);

    //     uint256 configuration = POOL
    //         .getReserveData(address_long)
    //         .configuration
    //         .data;

    //     uint8 categoryId = fetchBits(configuration);

    //     POOL.setUserEMode(categoryId);

    //     // borrow short_token
    //     POOL.borrow(
    //         address_short,
    //         amount - _amountDeposited,
    //         2,
    //         referralCode,
    //         address(this)
    //     );

    //     return amount - _amountDeposited;
    // }

    // //SWAP CRAFTER
    function craftSwap(
        //TODO: use this example (no need to know the pool address beforehand)
        //https://docs.uniswap.org/contracts/v3/guides/swaps/single-swaps#a-complete-single-swap-contract
        uint256 amountIn,
        address tokenBeforeSwap,
        address tokenAfterSwap
    ) internal returns (uint256 amountOut) {
        //We use the lowest fee tier for the pool
        uint24 poolFee = 500; //UniswapV3Pool(address_pool).fee();

        AaveTransferHelper.safeApprove(tokenBeforeSwap, address(swapRouterAddr), amountIn);

        // Approve the router to spend DAI.

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenBeforeSwap,
                tokenOut: tokenAfterSwap,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });


        amountOut = ISwapRouter(swapRouterAddr).exactInputSingle(params);

        return amountOut;
    }

    function prepareRepayement(uint256 _repayAmount) internal {
        //TODO: move this part

        uint256 amountIn = getAmountIn(_repayAmount, address_short, address_long);

        uint256 totalBalance = IERC20(address_long).balanceOf(address(this));

        AaveTransferHelper.safeApprove(
            address_long,
            address(POOL),
            totalBalance
        );
        // check balanceOf long_token for this contract to check flashloan has been correctly executed
        // console.log(address_long.balanceOf(address(this)));
        // deposit flashloaned longed asset on Aave

        uint16 referralCode = 0;


        POOL.supply(address_long, totalBalance, address(this), referralCode);


        // borrow phase on aave (this next part is tricky)
        // fetch the pool configuration from the reserve data
        uint256 configuration = POOL
            .getReserveData(address_long)
            .configuration
            .data;
        // fetch the category id from the configuration (bits 168-175 from the configuration uin256)
        uint8 categoryId = fetchBits(configuration);
        // activate emode for this contract
        POOL.setUserEMode(categoryId);

        // borrow short_token
        POOL.borrow(
            address_short,
            amountIn,
            2,
            referralCode,
            address(this)
        );

        uint256 shortTokenBalance = IERC20(address_short).balanceOf(
            address(this)
        );
        //swaping shortToken to longToken to repay the flashloan
        craftSwap(shortTokenBalance , address_short, address_long);
    }

    function prepareUnwind(uint256 _repayAmount) internal {

        uint256 amountIn = getAmountIn(_repayAmount, address_long, address_short);

        uint256 totalBalance = IERC20(address_short).balanceOf(address(this));

        //TODO check if this is needed to repay the flashloan
        AaveTransferHelper.safeApprove(
            address_short,
            address(POOL),
            totalBalance
        );
        console.log("totalBalance", IERC20(address_short).balanceOf(address(this)));

        POOL.repay(address_short, _repayAmount, 2, address(this)); //TODO
        console.log("totalBalance", IERC20(address_short).balanceOf(address(this)));
        console.log("totalBalance", IERC20(address_long).balanceOf(address(this)));

        POOL.withdraw(address_long, 2**256-1, address(this)); //TODO
        console.log("totalBalance", IERC20(address_long).balanceOf(address(this)));
        

        uint256 longTokenBalance = IERC20(address_long).balanceOf(
            address(this)
        );

        craftSwap(
            longTokenBalance,
            address_long,
            address_short
        );
        
        console.log("totalBalance", IERC20(address_short).balanceOf(address(this)));
        console.log("totalBalance", IERC20(address_long).balanceOf(address(this)));
    }

    function unwindPosition()
        public
        returns (bool success)
    {
        address variableDebt = POOL
            .getReserveData(address_short)
            .variableDebtTokenAddress;
        IERC20 variableDebtToken = IERC20(variableDebt);
        uint256 variableDebtBalance = variableDebtToken.balanceOf(
            address(this)
        ); //TODO

        unwind = true;
        requestFlashLoan(address_short, variableDebtBalance);

        AaveTransferHelper.safeTransfer(address_long, owner,  IERC20(address_long).balanceOf(address(this)));
        AaveTransferHelper.safeTransfer(address_short, owner,  IERC20(address_short).balanceOf(address(this)));
        return true;
    }

    function requestFlashLoan(address _token, uint256 _amount) internal {
        address receiverAddress = address(this);
        address asset = _token;
        uint256 amount = _amount;
        bytes memory params = "";
        uint16 referralCode = 0;

        POOL.flashLoanSimple(
            receiverAddress,
            asset,
            amount,
            params,
            referralCode
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (!unwind){
            //TODO: calculate how much short token should be sold (= repayAmount) to get enough longToken to repay the flashloan (= amount)
            uint256 repayAmount = amount + premium;

            prepareRepayement(repayAmount);

            // require(msg.sender == address(POOL), "Unauthorized");
            // require(initiator == address(this), "Unauthorized");

            // Approve the Pool contract allowance to *pull* the owed amount

            IERC20(asset).approve(address(POOL), repayAmount);
            return true;
        } else {
            uint256 repayAmount = amount + premium;
            prepareUnwind(repayAmount);

            IERC20(asset).approve(address(POOL), repayAmount);
            return true;
        }
    }

    function fetchBits(uint256 x) public pure returns (uint8) {
        uint8 bits = uint8((x >> 168) & 0xFF);
        return bits;
    }
}
