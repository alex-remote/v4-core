// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title 用于高效地以自定义错误回滚（revert）的库
/// @notice 包含以带不同类型参数的自定义错误高效回滚的函数
/// @dev 使用本库时，声明 `using CustomRevert for bytes4;`，并将 `revert CustomError()` 替换为
/// `CustomError.selector.revertWith()`
/// @dev 这些函数可能会改动空闲内存指针，但这没有问题，因为调用上下文会立即退出
library CustomRevert {
    /// @dev 用于包装向上冒泡的回滚（revert）的 ERC-7751 错误
    error WrappedError(address target, bytes4 selector, bytes reason, bytes details);

    /// @dev 在 scratch space（暂存空间）中写入自定义错误的选择器并回滚
    function revertWith(bytes4 selector) internal pure {
        assembly ("memory-safe") {
            mstore(0, selector)
            revert(0, 0x04)
        }
    }

    /// @dev 在 scratch space 中以带一个 address 参数的自定义错误回滚
    function revertWith(bytes4 selector, address addr) internal pure {
        assembly ("memory-safe") {
            mstore(0, selector)
            mstore(0x04, and(addr, 0xffffffffffffffffffffffffffffffffffffffff))
            revert(0, 0x24)
        }
    }

    /// @dev 在 scratch space 中以带一个 int24 参数的自定义错误回滚
    function revertWith(bytes4 selector, int24 value) internal pure {
        assembly ("memory-safe") {
            mstore(0, selector)
            mstore(0x04, signextend(2, value))
            revert(0, 0x24)
        }
    }

    /// @dev 在 scratch space 中以带一个 uint160 参数的自定义错误回滚
    function revertWith(bytes4 selector, uint160 value) internal pure {
        assembly ("memory-safe") {
            mstore(0, selector)
            mstore(0x04, and(value, 0xffffffffffffffffffffffffffffffffffffffff))
            revert(0, 0x24)
        }
    }

    /// @dev 以带两个 int24 参数的自定义错误回滚
    function revertWith(bytes4 selector, int24 value1, int24 value2) internal pure {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, selector)
            mstore(add(fmp, 0x04), signextend(2, value1))
            mstore(add(fmp, 0x24), signextend(2, value2))
            revert(fmp, 0x44)
        }
    }

    /// @dev 以带两个 uint160 参数的自定义错误回滚
    function revertWith(bytes4 selector, uint160 value1, uint160 value2) internal pure {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, selector)
            mstore(add(fmp, 0x04), and(value1, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(fmp, 0x24), and(value2, 0xffffffffffffffffffffffffffffffffffffffff))
            revert(fmp, 0x44)
        }
    }

    /// @dev 以带两个 address 参数的自定义错误回滚
    function revertWith(bytes4 selector, address value1, address value2) internal pure {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, selector)
            mstore(add(fmp, 0x04), and(value1, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(fmp, 0x24), and(value2, 0xffffffffffffffffffffffffffffffffffffffff))
            revert(fmp, 0x44)
        }
    }

    /// @notice 将调用返回的回滚信息向上冒泡，并以包装后的 ERC-7751 错误回滚
    /// @dev 此方法可能易受回滚数据炸弹（revert data bomb）攻击
    function bubbleUpAndRevertWith(
        address revertingContract,
        bytes4 revertingFunctionSelector,
        bytes4 additionalContext
    ) internal pure {
        bytes4 wrappedErrorSelector = WrappedError.selector;
        assembly ("memory-safe") {
            // 确保回滚数据的大小为 32 字节的整数倍
            let encodedDataSize := mul(div(add(returndatasize(), 31), 32), 32)

            let fmp := mload(0x40)

            // 编码包装错误选择器、地址、函数选择器、偏移量、附加上下文、大小、回滚原因（revert reason）
            mstore(fmp, wrappedErrorSelector)
            mstore(add(fmp, 0x04), and(revertingContract, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(
                add(fmp, 0x24),
                and(revertingFunctionSelector, 0xffffffff00000000000000000000000000000000000000000000000000000000)
            )
            // 回滚原因的偏移量
            mstore(add(fmp, 0x44), 0x80)
            // 附加上下文的偏移量
            mstore(add(fmp, 0x64), add(0xa0, encodedDataSize))
            // 回滚原因的大小
            mstore(add(fmp, 0x84), returndatasize())
            // 回滚原因
            returndatacopy(add(fmp, 0xa4), 0, returndatasize())
            // 附加上下文的大小
            mstore(add(fmp, add(0xa4, encodedDataSize)), 0x04)
            // 附加上下文
            mstore(
                add(fmp, add(0xc4, encodedDataSize)),
                and(additionalContext, 0xffffffff00000000000000000000000000000000000000000000000000000000)
            )
            revert(fmp, add(0xe4, encodedDataSize))
        }
    }
}
