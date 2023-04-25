//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILogic {
    function requestFlashLoan(
        address _token,
        uint256 _amount,
        bool _crafting,
        uint256 _slippagePercent,
        uint256 _amountToSwap,
        bytes memory paraswapData
    ) external;

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);

    function longDepositedCraft(
        uint256 _amountDeposited,
        uint256 _leverageRatio,
        uint256 _slippagePercent,
        uint256 _shortTokenAmountToBorrow,
        bytes memory paraswapData
    ) external;

    function shortDepositedCraft(
        uint256 _amountDeposited,
        uint256 _amountToFlash,
        uint256 _slippagePercent,
        uint256 _shortTokenAmountToBorrow,
        bytes memory paraswapData
    ) external;

    function prepareRepayementCraft(
        uint256 _repayAmount,
        uint256 _slippagePercent,
        uint256 shortTokenAmountToBorrow,
        bytes memory paraswapData
    ) external;

    function unwindPosition(
        uint256 _slippagePercentage,
        uint256 _longTokenAmountToSwap,
        bytes memory paraswapData
    ) external;

    function prepareRepayementUnwind(
        uint256 _repayAmount,
        uint256 _slippagePercent,
        uint256 _longTokenAmountToSwap,
        bytes memory paraswapData
    ) external;

    function craftSwap(
        uint256 _amountOut,
        uint256 _amountInMaximum,
        address _tokenBeforeSwap,
        address _tokenAfterSwap,
        bytes memory paraswapData
    ) external returns (uint256 amountIn);

    function fetchBits(uint256 x) external pure returns (uint8);
}
