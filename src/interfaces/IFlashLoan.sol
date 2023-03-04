//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFlashLoan {
    //TODO: mod craft based on arch
    function craftPosition(
        bool depositIsLong,
        uint256 _amountDeposited,
        uint256 _leverageRatio
    ) external returns (bool);

    //TODO: mod unwind based on arch
    function unwindPosition(uint256 shortDebt) external returns (bool);
}
