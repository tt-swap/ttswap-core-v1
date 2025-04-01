// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.26;

abstract contract IWithdrawContract {
    //需要确认与修改
    event Withdrawn(address indexed recipient, uint256 amount);

    function withdraw(address recipient, uint256 amount) external virtual;

    function withdrawableBalanceOf(
        address account
    ) external view virtual returns (uint256);
}
