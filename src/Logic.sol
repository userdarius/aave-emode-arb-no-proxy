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
    address public shortTokenAddress;
    address public longTokenAddress;

    address public immutable swapRouterAddr;
    address public immutable quoterRouterAddr;

    modifier ifOwner() {
        console.log("Entering ifOwner");
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    constructor(
        address _aaveAddressProvider,
        address _swapRouterAddr,
        address _quoterRouterAddr,
        address _owner,
        address _shortTokenAddress,
        address _longTokenAddress
    )
        FlashLoanSimpleReceiverBase(
            IPoolAddressesProvider(_aaveAddressProvider)
        )
    {
        swapRouterAddr = _swapRouterAddr;
        quoterRouterAddr = _quoterRouterAddr;
        owner = _owner;
        shortTokenAddress = _shortTokenAddress;
        longTokenAddress = _longTokenAddress;
    }

    function getAmountIn(uint256 amount, address _tokenIn, address _tokenOut) public returns (uint256) {
        (uint256 amountIn, , , ) = IQuoterV2(quoterRouterAddr)
            .quoteExactOutputSingle(
                IQuoterV2.QuoteExactOutputSingleParams({
                    tokenIn: _tokenIn,
                    tokenOut: _tokenOut,
                    amount: amount,
                    fee: 100,
                    sqrtPriceLimitX96: 0
                })
            );
        return amountIn;
    }

    // function craftPosition(
    //     bool depositIsLong,
    //     uint256 _amountDeposited,
    //     uint256 _leverageRatio
    // ) public override ifOwner returns (bool success) {
    //     if (depositIsLong) {
    //         longDepositedCraft(_amountDeposited, _leverageRatio);
    //     } else {
    //         shortDepositedCraft(_amountDeposited, _leverageRatio);
    //     }
    //     success = true;
    //     return success;
    // }

    function longDepositedCraft(
        uint256 _amountDeposited,
        uint256 _leverageRatio,
        uint256 _shortToLongRate,
        uint256 _slippagePercent
    ) external ifOwner {
        //pulling the tokens from the user into the contract
        AaveTransferHelper.safeTransferFrom(
            longTokenAddress,
            owner,
            address(this),
            _amountDeposited
        );

        uint256 amount = _amountDeposited * (_leverageRatio - 1);

        requestFlashLoan(longTokenAddress, amount, true, _shortToLongRate, _slippagePercent);
    }
    
    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _repayAmount the amount of longToken needed to repay the flashloan
    function prepareRepayementCraft(uint256 _repayAmount, uint256 shortToLongRate, uint256 slippagePercent) internal {
        uint256 amountIn = _repayAmount*shortToLongRate*(100+slippagePercent)/100;

        uint256 longTokenBalance = IERC20(longTokenAddress).balanceOf(address(this));
        AaveTransferHelper.safeApprove(
            longTokenAddress,
            address(POOL),
            longTokenBalance
        );
        // check balanceOf long_token for this contract to check flashloan has been correctly executed
        console.log(IERC20(longTokenAddress).balanceOf(address(this)));
        // deposit flashloaned longed asset on Aave
        console.log("Supplying the entire balance of longToken to Aave");
        uint16 referralCode = 0;//TODO: make referralCode a global variable and add a setter so we can change it later
        //supplying max amount of longToken
        POOL.supply(longTokenAddress, longTokenBalance, address(this), referralCode);
        console.log(
            "AMOUNT AFTER: supply",
            IERC20(longTokenAddress).balanceOf(address(this))
        );

        // borrow phase on aave (this next part is tricky)
        // fetch the pool configuration from the reserve data
        uint256 configuration = POOL
            .getReserveData(longTokenAddress)
            .configuration
            .data;
        // fetch the category id from the configuration (bits 168-175 from the configuration uin256)
        uint8 categoryId = fetchBits(configuration);
        // activate emode for this contract
        POOL.setUserEMode(categoryId);

        console.log(POOL.getUserEMode(address(this)));
        // borrow short_token
        console.log("trying to borrow shortToken");
        console.log("amount to borrow in shortToken ", amountIn);
        POOL.borrow(
            shortTokenAddress,
            amountIn,
            2,
            referralCode,
            address(this)
        );
        console.log("The borrow went through and the balance of shortToken");
        uint256 shortTokenBalance = IERC20(shortTokenAddress).balanceOf(
            address(this)
        );
        console.log("shortToken balance is ", shortTokenBalance);
        console.log("CraftSwap is going to be called");
        //swaping shortToken to longToken to repay the flashloan
        craftSwap(amountIn, shortTokenBalance, shortTokenAddress, longTokenAddress);
    }

    function unwindPosition(uint256  _shortToLongRate,uint256 _slippagePercentage)
        external
        ifOwner
    {   
        // retrieving the debt in shortToken
        address variableDebtTokenAddress = POOL.getReserveData(shortTokenAddress).variableDebtTokenAddress;
        uint256 variableDebtBalance = IERC20(variableDebtTokenAddress).balanceOf(address(this));
        //there might be some shortToken leftover from position crafting
        uint256 shortTokenBalance = IERC20(shortTokenAddress).balanceOf(address(this));
        requestFlashLoan(shortTokenAddress, variableDebtBalance - shortTokenBalance, false, _shortToLongRate, _slippagePercentage);
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _repayAmount the amount of shortToken needed to repay the flashloan
    function prepareRepayementUnwind(uint256 _repayAmount, uint256 _shortToLongRate, uint256 _slippagePercent) internal {
        AaveTransferHelper.safeApprove(
            shortTokenAddress,
            address(POOL),
            type(uint).max
        );
        // //retreiving the total shortToken balance
        //uint256 shortTokenBalance = IERC20(shortTokenAddress).balanceOf(address(this));
        //repay Aave debt in shortToken
        POOL.repay(shortTokenAddress, type(uint).max, 2, address(this));
        //withdraw all longToken from Aave
        POOL.withdraw(longTokenAddress, type(uint).max, address(this));
        //sell enough longToken for shortToken to repay the flashloan
        uint256 amountIn = _repayAmount/_shortToLongRate*(100+_slippagePercent)/100;//TODO: (use the twap + 1% to account for slippage) * _repayAmount
        //swaping shortToken to longToken to repay the flashloan
        craftSwap(amountIn, _repayAmount, longTokenAddress, shortTokenAddress);
    }

    // function shortDepositedCraft(
    //     uint256 _amountDeposited,
    //     uint256 _leverageRatio
    // ) internal returns (uint256) {
    //     uint256 amountIn = getAmountIn(
    //         shortTokenAddress,
    //         longTokenAddress,
    //         _amountDeposited,
    //         100
    //     );

    //     uint256 amount = amountIn * _amountDeposited * _leverageRatio;

    //     AaveTransferHelper.safeTransferFrom(
    //         longTokenAddress,
    //         msg.sender,
    //         address(this),
    //         amountIn * _amountDeposited
    //     );

    //     requestFlashLoan(longTokenAddress, amount);

    //     uint16 referralCode = 0;
    //     AaveTransferHelper.safeTransferFrom(
    //         longTokenAddress,
    //         owner,
    //         address(this),
    //         amount
    //     );
    //     AaveTransferHelper.safeApprove(longTokenAddress, address(POOL), amount);
    //     POOL.supply(longTokenAddress, amount, msg.sender, referralCode);

    //     uint256 configuration = POOL
    //         .getReserveData(longTokenAddress)
    //         .configuration
    //         .data;

    //     uint8 categoryId = fetchBits(configuration);

    //     POOL.setUserEMode(categoryId);

    //     // borrow short_token
    //     POOL.borrow(
    //         shortTokenAddress,
    //         amount - _amountDeposited,
    //         2,
    //         referralCode,
    //         address(this)
    //     );

    //     return amount - _amountDeposited;
    // }

    // SWAP CRAFTER
    function craftSwap(
        uint256 amountOut,
        uint256 amountInMaximum,
        address tokenBeforeSwap,
        address tokenAfterSwap
    ) internal returns (uint256 amountIn) {
        //We use the lowest fee tier for the pool
        console.log("Entering craftSwap");
        uint24 poolFee = 100; //UniswapV3Pool(address_pool).fee();

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: tokenBeforeSwap,
                tokenOut: tokenAfterSwap,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });

        console.log("Swap params have been generated");
        console.log("Swap is going to be executed");
        amountIn = ISwapRouter(swapRouterAddr).exactOutputSingle(params);
        console.log("swap has been executed");
        return amountIn;
    }

    function requestFlashLoan(address _token, uint256 _amount, bool _crafting,  uint256 _shortToLongRate, uint256 _slippagePercent) internal {
        address receiverAddress = address(this);
        address asset = _token;
        uint256 amount = _amount;
        bytes memory params = abi.encode(_crafting, _shortToLongRate, _slippagePercent);
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
        (bool crafting, uint256 shortToLongRate, uint256 slippagePercent) = abi.decode(params, (bool, uint256, uint256));
        uint256 repayAmount = amount + premium;
        if (crafting){
            prepareRepayementCraft(repayAmount, shortToLongRate, slippagePercent);
        }
        else
        {
            prepareRepayementUnwind(repayAmount, shortToLongRate, slippagePercent);
        }

        // require(msg.sender == address(POOL), "Unauthorized");
        // require(initiator == address(this), "Unauthorized");

        // Approve the Pool contract allowance to *pull* the owed amount
        IERC20(asset).approve(address(POOL), repayAmount);

        return true;
    }

    function fetchBits(uint256 x) public pure returns (uint8) {
        uint8 bits = uint8((x >> 168) & 0xFF);
        return bits;
    }
}
