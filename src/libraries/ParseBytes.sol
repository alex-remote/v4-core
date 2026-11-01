// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @notice 解析 hook 返回的字节数据，以及用于检查 hook 返回选择器的字节选择器。
/// @dev parseSelector 也用于解析预期的选择器
/// 解析 hook 返回值时请注意，所有 hook 的返回值要么是 bytes4，要么是 (bytes4, 32-byte-delta)，要么是 (bytes4, 32-byte-delta, uint24)。
library ParseBytes {
    function parseSelector(bytes memory result) internal pure returns (bytes4 selector) {
        // 等价于：(selector,) = abi.decode(result, (bytes4, int256));
        assembly ("memory-safe") {
            selector := mload(add(result, 0x20))
        }
    }

    function parseFee(bytes memory result) internal pure returns (uint24 lpFee) {
        // 等价于：(,, lpFee) = abi.decode(result, (bytes4, int256, uint24));
        assembly ("memory-safe") {
            lpFee := mload(add(result, 0x60))
        }
    }

    function parseReturnDelta(bytes memory result) internal pure returns (int256 hookReturn) {
        // 等价于：(, hookReturnDelta) = abi.decode(result, (bytes4, int256));
        assembly ("memory-safe") {
            hookReturn := mload(add(result, 0x40))
        }
    }
}
