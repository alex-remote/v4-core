// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CustomRevert} from "./libraries/CustomRevert.sol";

/// @title 防止对合约进行 delegatecall
/// @notice 基础合约，提供一个修饰符，用于防止对子合约中的方法进行 delegatecall
abstract contract NoDelegateCall {
    using CustomRevert for bytes4;

    error DelegateCallNotAllowed();

    /// @dev 本合约的原始地址
    address private immutable original;

    constructor() {
        // immutable 变量在合约的初始化代码（init code）中计算，然后内联到部署后的字节码中。
        // 换言之，在运行时检查该变量时，它的值不会改变。
        original = address(this);
    }

    /// @dev 这里使用私有方法而非内联到修饰符中，因为修饰符会被复制到每个使用它的方法里，
    ///     而使用 immutable 意味着地址字节会被复制到每一处使用该修饰符的地方。
    function checkNotDelegateCall() private view {
        if (address(this) != original) DelegateCallNotAllowed.selector.revertWith();
    }

    /// @notice 防止对被修饰的方法进行 delegatecall
    modifier noDelegateCall() {
        checkNotDelegateCall();
        _;
    }
}
