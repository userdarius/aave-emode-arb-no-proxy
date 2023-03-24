//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlashLoanSimpleReceiverBase} from "aave-v3-core/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../lib/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./AaveTransferHelper.sol";
import "./interfaces/IFlashLoan.sol";
import "forge-std/Test.sol";

contract Logic is FlashLoanSimpleReceiverBase, Test {
    address public owner;
    address public shortTokenAddress;
    address public longTokenAddress;
    uint16 public referralCode;//TODO: in the proxy version, only the owner of the implementation should be able to change the ref code

    address public immutable swapRouterAddr;

    modifier ifOwner() {
        console.log("Entering ifOwner");
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    constructor(
        address _aaveAddressProvider,
        address _swapRouterAddr,
        address _owner,
        address _shortTokenAddress,
        address _longTokenAddress
    )
        FlashLoanSimpleReceiverBase(
            IPoolAddressesProvider(_aaveAddressProvider)
        )
    {
        swapRouterAddr = _swapRouterAddr;
        owner = _owner;
        shortTokenAddress = _shortTokenAddress;
        longTokenAddress = _longTokenAddress;
    }

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

        requestFlashLoan(
            longTokenAddress,
            amount,
            true,
            _shortToLongRate,
            _slippagePercent
        );
    }

    function shortDepositedCraft(
        uint256 _amountDeposited,
        uint256 _leverageRatio,
        uint256 _shortToLongRate,
        uint256 _slippagePercent
    ) external ifOwner {
        //pulling the tokens from the user into the contract
        AaveTransferHelper.safeTransferFrom(
            shortTokenAddress,
            owner,
            address(this),
            _amountDeposited
        );
        uint256 value = _amountDeposited * _shortToLongRate/(10^18);
        uint256 amountToFlash = value * _leverageRatio;
        requestFlashLoan(
            shortTokenAddress,
            amountToFlash,
            true,
            _shortToLongRate,
            _slippagePercent
        );
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _repayAmount the amount of longToken needed to repay the flashloan
    function prepareRepayementCraft(
        uint256 _repayAmount,
        uint256 _shortToLongRate,
        uint256 _slippagePercent
    ) internal {
        console.log("repayAmount is ", _repayAmount);
        console.log("shortToLongRate is ", _shortToLongRate);
        console.log("slippagePercent is ", _slippagePercent);

        uint256 longTokenBalance = IERC20(longTokenAddress).balanceOf(
            address(this)
        );
        AaveTransferHelper.safeApprove(
            longTokenAddress,
            address(POOL),
            longTokenBalance
        );
        // check balanceOf long_token for this contract to check flashloan has been correctly executed
        console.log(IERC20(longTokenAddress).balanceOf(address(this)));
        // deposit flashloaned longed asset on Aave
        console.log("Supplying the entire balance of longToken to Aave");
        //supplying max amount of longToken
        POOL.supply(
            longTokenAddress,
            longTokenBalance,
            address(this),
            referralCode
        );
        console.log(
            "AMOUNT AFTER SUPPLYING TO AAVE (should be 0)",
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

        console.log("user emode config : ", POOL.getUserEMode(address(this)));
        // borrow short_token
        console.log("_repayAmount is ", _repayAmount);
        console.log("_shortToLongRate is ", _shortToLongRate);
        console.log("(_repayAmount * (10^18) / _shortToLongRate) is ", (_repayAmount * _shortToLongRate/ 1000000));
        uint256 amountIn = (_repayAmount *
            _shortToLongRate / 1000000) * (100 + _slippagePercent) / 100;
        console.log("AmountIn is ", amountIn);
        uint256 initialShortTokenBalance = IERC20(shortTokenAddress).balanceOf(address(this));
        POOL.borrow(
            shortTokenAddress,
            amountIn - initialShortTokenBalance,
            2,
            referralCode,
            address(this)
        );
        console.log("The borrow went through");
        uint256 shortTokenBalance = IERC20(shortTokenAddress).balanceOf(
            address(this)
        );
        console.log("shortToken balance is ", shortTokenBalance);
        //swaping shortToken to longToken to repay the flashloan
        console.log("CraftSwap is going to be called");
        craftSwap(
            _repayAmount,
            shortTokenBalance,
            shortTokenAddress,
            longTokenAddress
        );
    }

    function unwindPosition(
        uint256 _shortToLongRate,
        uint256 _slippagePercentage
    ) external ifOwner {
        // retrieving the debt in shortToken
        address variableDebtTokenAddress = POOL
            .getReserveData(shortTokenAddress)
            .variableDebtTokenAddress;
        uint256 variableDebtBalance = IERC20(variableDebtTokenAddress)
            .balanceOf(address(this));
        //there might be some shortToken leftover from position crafting
        uint256 shortTokenBalance = IERC20(shortTokenAddress).balanceOf(
            address(this)
        );
        requestFlashLoan(
            shortTokenAddress,
            variableDebtBalance - shortTokenBalance,
            false,
            _shortToLongRate,
            _slippagePercentage
        );
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _repayAmount the amount of shortToken needed to repay the flashloan
    function prepareRepayementUnwind(
        uint256 _repayAmount,
        uint256 _shortToLongRate,
        uint256 _slippagePercent
    ) internal {
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
        console.log("_repayAmount is ", _repayAmount);
        console.log("_shortToLongRate is ", _shortToLongRate);
        console.log("(_repayAmount * (10^18) / _shortToLongRate) is ", (_repayAmount * (10^18) / _shortToLongRate));
        uint256 amountIn = ((_repayAmount * (10^18) / _shortToLongRate) *
            (100 + _slippagePercent)) / 100;
        //swaping shortToken to longToken to repay the flashloan
        craftSwap(amountIn, _repayAmount, longTokenAddress, shortTokenAddress);
    }

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
        IERC20(tokenBeforeSwap).approve(swapRouterAddr, amountInMaximum);
        console.log("AmountInMaximum is ", amountInMaximum);
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

    function requestFlashLoan(
        address _token,
        uint256 _amount,
        bool _crafting,
        uint256 _shortToLongRate,
        uint256 _slippagePercent
    ) internal {
        console.log("Entering requestFlashLoan");
        address receiverAddress = address(this);
        address asset = _token;
        uint256 amount = _amount;
        bytes memory params = abi.encode(
            _crafting,
            _shortToLongRate,
            _slippagePercent
        );

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
        require(initiator == address(this));
        console.log("Entering executeOperation");
        (bool crafting, uint256 shortToLongRate, uint256 slippagePercent) = abi
            .decode(params, (bool, uint256, uint256));
        uint256 repayAmount = amount + premium;
        if (crafting) {
            prepareRepayementCraft(
                repayAmount,
                shortToLongRate,
                slippagePercent
            );
        } else {
            prepareRepayementUnwind(
                repayAmount,
                shortToLongRate,
                slippagePercent
            );
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
