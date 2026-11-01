// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExtsload} from "./interfaces/IExtsload.sol";

/// @notice 开放公共的存储访问，便于外部合约高效地读取状态。
/// https://eips.ethereum.org/EIPS/eip-2330#rationale
abstract contract Extsload is IExtsload {
    /// @inheritdoc IExtsload
    function extsload(bytes32 slot) external view returns (bytes32) {
        assembly ("memory-safe") {
            mstore(0, sload(slot))
            return(0, 0x20)
        }
    }

    /// @inheritdoc IExtsload
    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory) {
        assembly ("memory-safe") {
            let memptr := mload(0x40)
            let start := memptr
            // 左移 5 位等价于乘以 32，但消耗的 gas 更少。
            let length := shl(5, nSlots)
            // 返回数据（returndata）中动态数组的 abi 偏移量为 32。
            mstore(memptr, 0x20)
            // 存储返回数组的长度
            mstore(add(memptr, 0x20), nSlots)
            // 将 memptr 更新为存放第一个结果的位置
            memptr := add(memptr, 0x40)
            let end := add(memptr, length)
            for {} 1 {} {
                mstore(memptr, sload(startSlot))
                memptr := add(memptr, 0x20)
                startSlot := add(startSlot, 1)
                if iszero(lt(memptr, end)) { break }
            }
            return(start, sub(end, start))
        }
    }

    /// @inheritdoc IExtsload
    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory) {
        assembly ("memory-safe") {
            let memptr := mload(0x40)
            let start := memptr
            // 用于对返回值做 abi 编码——数组位于偏移 0x20 处
            mstore(memptr, 0x20)
            // 接着存储返回数组的长度
            mstore(add(memptr, 0x20), slots.length)
            // 将 memptr 更新为存放第一个数组元素的位置
            memptr := add(memptr, 0x40)
            // 左移 5 位等价于乘以 32，但消耗的 gas 更少。
            let end := add(memptr, shl(5, slots.length))
            let calldataptr := slots.offset
            for {} 1 {} {
                mstore(memptr, sload(calldataload(calldataptr)))
                memptr := add(memptr, 0x20)
                calldataptr := add(calldataptr, 0x20)
                if iszero(lt(memptr, end)) { break }
            }
            return(start, sub(end, start))
        }
    }
}
