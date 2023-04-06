//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlashLoanSimpleReceiverBase} from "aave-v3-core/contracts/flashloan/base/FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";
import {IERC20} from "aave-v3-core/contracts/dependencies/openzeppelin/contracts/IERC20.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "./AaveTransferHelper.sol";
import "./interfaces/IFlashLoan.sol";
import "forge-std/Test.sol";

contract Logic is FlashLoanSimpleReceiverBase {
    address public owner;
    address public shortTokenAddress;
    address public longTokenAddress;
    uint16 public referralCode;//TODO: in the proxy version, only the owner of the implementation should be able to change the ref code

    address public immutable paraswapRouterAddr;

    modifier ifOwner() {
        console.log("Entering ifOwner");
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    constructor(
        address _aaveAddressProvider,
        address _paraswapRouterAddr,
        address _owner,
        address _shortTokenAddress,
        address _longTokenAddress
    )
        FlashLoanSimpleReceiverBase(
            IPoolAddressesProvider(_aaveAddressProvider)
        )
    {
        paraswapRouterAddr = _paraswapRouterAddr;
        owner = _owner;
        shortTokenAddress = _shortTokenAddress;
        longTokenAddress = _longTokenAddress;
    }

    function requestFlashLoan(
        address _token,
        uint256 _amount,
        bool _crafting,
        uint256 _slippagePercent,
        uint256 _amountToSwap,
        bytes memory paraswapData
    ) internal {
        console.log("Entering requestFlashLoan");
        address receiverAddress = address(this);
        address asset = _token;
        uint256 amount = _amount;
        bytes memory params = abi.encode(
            _crafting,
            _slippagePercent,
            _amountToSwap,
            paraswapData
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
        require(msg.sender == address(POOL));//TODO: might break tests
        console.log("Entering executeOperation");
        (bool crafting, uint256 slippagePercent, uint256 amountToSwap, bytes memory paraswapData) = abi
            .decode(params, (bool, uint256, uint256, bytes));
        uint256 repayAmount = amount + premium;
        if (crafting) {
            prepareRepayementCraft(
                repayAmount,
                slippagePercent,
                amountToSwap,
                paraswapData
            );
        } else {
            prepareRepayementUnwind(
                repayAmount,
                slippagePercent,
                amountToSwap,
                paraswapData
            );
        }

        // require(msg.sender == address(POOL), "Unauthorized");
        // require(initiator == address(this), "Unauthorized");

        // Approve the Pool contract allowance to *pull* the owed amount
        IERC20(asset).approve(address(POOL), repayAmount);

        return true;
    }

    function longDepositedCraft(
        uint256 _amountDeposited,
        uint256 _leverageRatio,
        uint256 _slippagePercent,//TODO: is it still needed?
        uint256 _shortTokenAmountToBorrow, //TODO: in shortDepositedCraft, the same amount will be passed and the _amountDeposited will be substracted
        bytes memory paraswapData
    ) external ifOwner {
        //pulling the tokens from the user into the contract
        AaveTransferHelper.safeTransferFrom(
            longTokenAddress,
            owner,
            address(this),
            _amountDeposited
        );

        uint256 amountToFlashloan = _amountDeposited * (_leverageRatio - 1);

        requestFlashLoan(
            longTokenAddress,
            amountToFlashloan,
            true,
            _slippagePercent,
            _shortTokenAmountToBorrow,
            paraswapData
        );
    }

    function shortDepositedCraft(//TODO: do it with using the longDepositedCraft structure
        uint256 _amountDeposited,
        uint256 _amountToFlash,//It is the amount of long token to borrow with the flashloan
        uint256 _slippagePercent,
        uint256 _shortTokenAmountToBorrow,
        bytes memory paraswapData
    ) external ifOwner {
        //pulling the tokens from the user into the contract
        AaveTransferHelper.safeTransferFrom(
            shortTokenAddress,
            owner,
            address(this),
            _amountDeposited
        );
        requestFlashLoan(
            longTokenAddress,
            _amountToFlash,
            true,
            _slippagePercent,
            _shortTokenAmountToBorrow,
            paraswapData
        );
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _repayAmount the amount of longToken needed to repay the flashloan
    function prepareRepayementCraft(
        uint256 _repayAmount,
        uint256 _slippagePercent,
        uint256 shortTokenAmountToBorrow,
        bytes memory paraswapData
    ) internal {
        console.log("repayAmount is ", _repayAmount);
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
        //supplying max amount of longToken to be able to borrow shortToken to repay the flashloan
        POOL.supply(
            longTokenAddress,
            longTokenBalance,
            address(this),
            referralCode
        );
        console.log(
            "AMOUNT AFTER SUPPLYING TO AAVE (should be 0): ",
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
        uint256 shortTokenBalance = IERC20(shortTokenAddress).balanceOf(address(this));
        POOL.borrow(
            shortTokenAddress,
            shortTokenAmountToBorrow - shortTokenBalance,
            2,
            referralCode,
            address(this)
        );
        console.log("The borrow went through");
        uint256 finalShortTokenBalance = IERC20(shortTokenAddress).balanceOf(
            address(this)
        );
        console.log("shortToken balance is ", finalShortTokenBalance);
        //swaping shortToken to longToken to repay the flashloan
        console.log("CraftSwap is going to be called");
        craftSwap(
            _repayAmount,
            shortTokenAmountToBorrow,
            shortTokenAddress,
            longTokenAddress,
            paraswapData
        );
    }

    function unwindPosition(
        uint256 _slippagePercentage,
        uint256 _longTokenAmountToSwap,
        bytes memory paraswapData
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
            _slippagePercentage,
            _longTokenAmountToSwap,
            paraswapData
        );
    }

    /// @notice Explain to an end user what this does
    /// @dev Explain to a developer any extra details
    /// @param _repayAmount the amount of shortToken needed to repay the flashloan
    function prepareRepayementUnwind(
        uint256 _repayAmount,
        uint256 _slippagePercent,
        uint256 _longTokenAmountToSwap,
        bytes memory paraswapData
    ) internal {
        AaveTransferHelper.safeApprove(
            shortTokenAddress,
            address(POOL),
            type(uint).max
        );
        //repay maximum Aave debt in shortToken
        POOL.repay(shortTokenAddress, type(uint).max, 2, address(this));
        AaveTransferHelper.safeApprove(
            shortTokenAddress,
            address(POOL),
            0
        );
        //withdraw all longToken from Aave
        POOL.withdraw(longTokenAddress, type(uint).max, address(this));
        //sell enough longToken for shortToken to repay the flashloan
        console.log("_repayAmount is ", _repayAmount);
        //swaping longToken to shortToken to repay the flashloan
        craftSwap(_longTokenAmountToSwap, _repayAmount, longTokenAddress, shortTokenAddress, paraswapData);
    }

    // SWAP CRAFTER
    function craftSwap(
        uint256 _amountOut,
        uint256 _amountInMaximum,
        address _tokenBeforeSwap,
        address _tokenAfterSwap,
        bytes memory paraswapData
    ) internal returns (uint256 amountIn) {
        //We use the lowest fee tier for the pool
        console.log("Entering craftSwap");
        //TODO: might be useful for security reasons:
        //     require(AUGUSTUS_REGISTRY.isValidAugustus(address(augustus)), 'INVALID_AUGUSTUS');
        IERC20(_tokenBeforeSwap).approve(paraswapRouterAddr, _amountInMaximum);
        console.log("AmountInMaximum is ", _amountInMaximum);
        console.log("Swap is going to be executed");
        //callWithData on the paraswap router
        (bool success, ) = address(paraswapRouterAddr).call(paraswapData);
        if (!success) {
        // Copy revert reason from call
        assembly {
            returndatacopy(0, 0, returndatasize())
            revert(0, returndatasize())
            }
        }
        require(IERC20(_tokenAfterSwap).balanceOf(address(this)) >= _amountOut);
        console.log("swap has been executed successfully");
        AaveTransferHelper.safeApprove(_tokenBeforeSwap, paraswapRouterAddr, 0);
        return amountIn;
    }


    function fetchBits(uint256 x) public pure returns (uint8) {
        uint8 bits = uint8((x >> 168) & 0xFF);
        return bits;
    }
}
