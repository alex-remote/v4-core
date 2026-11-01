// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {BitMath} from "./BitMath.sol";

/// @title 打包的 tick 初始化状态库
/// @notice 存储从 tick 索引到其初始化状态的打包映射
/// @dev 该映射使用 int16 作为键，因为 tick 以 int24 表示，且每个字（word）包含 256 (2^8) 个值。
library TickBitmap {
    /// @notice 当 tick 未按 tick 间距对齐时抛出
    /// @param tick 无效的 tick
    /// @param tickSpacing 池子的 tick 间距
    error TickMisaligned(int24 tick, int24 tickSpacing);

    /// @dev 向负无穷方向取整
    function compress(int24 tick, int24 tickSpacing) internal pure returns (int24 compressed) {
        // compressed = tick / tickSpacing;
        // if (tick < 0 && tick % tickSpacing != 0) compressed--;
        assembly ("memory-safe") {
            tick := signextend(2, tick)
            tickSpacing := signextend(2, tickSpacing)
            compressed :=
                sub(
                    sdiv(tick, tickSpacing),
                    // 若 (tick < 0 && tick % tickSpacing != 0)，则 tick % tickSpacing < 0，反之亦然
                    slt(smod(tick, tickSpacing), 0)
                )
        }
    }

    /// @notice 计算某个 tick 的初始化位在映射中所处的位置
    /// @param tick 要计算位置的 tick
    /// @return wordPos 映射中的键，对应存储该位的那个字（word）
    /// @return bitPos 标志位在该字中的位位置
    function position(int24 tick) internal pure returns (int16 wordPos, uint8 bitPos) {
        assembly ("memory-safe") {
            // 有符号算术右移
            wordPos := sar(8, signextend(2, tick))
            bitPos := and(tick, 0xff)
        }
    }

    /// @notice 将给定 tick 的初始化状态从 false 翻转为 true，或反之
    /// @param self 要在其中翻转 tick 的映射
    /// @param tick 要翻转的 tick
    /// @param tickSpacing 可用 tick 之间的间距
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        // 等价于以下 Solidity 代码：
        //     if (tick % tickSpacing != 0) revert TickMisaligned(tick, tickSpacing);
        //     (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        //     uint256 mask = 1 << bitPos;
        //     self[wordPos] ^= mask;
        assembly ("memory-safe") {
            tick := signextend(2, tick)
            tickSpacing := signextend(2, tickSpacing)
            // 确保 tick 按间距对齐
            if smod(tick, tickSpacing) {
                let fmp := mload(0x40)
                mstore(fmp, 0xd4d8f3e6) // TickMisaligned(int24,int24) 的选择器
                mstore(add(fmp, 0x20), tick)
                mstore(add(fmp, 0x40), tickSpacing)
                revert(add(fmp, 0x1c), 0x44)
            }
            tick := sdiv(tick, tickSpacing)
            // 计算该 tick 对应的存储槽
            // wordPos = tick >> 8
            mstore(0, sar(8, tick))
            mstore(0x20, self.slot)
            // self[wordPos] 的存储槽为 keccak256(abi.encode(wordPos, self.slot))
            let slot := keccak256(0, 0x40)
            // mask = 1 << bitPos = 1 << (tick % 256)
            // self[wordPos] ^= mask
            sstore(slot, xor(sload(slot), shl(and(tick, 0xff), 1)))
        }
    }

    /// @notice 返回与该 tick 处于同一个字（word）（或相邻字）中的下一个已初始化 tick，该 tick 要么位于给定 tick 的
    /// 左侧（小于或等于），要么位于其右侧（大于）
    /// @param self 用于计算下一个已初始化 tick 的映射
    /// @param tick 起始 tick
    /// @param tickSpacing 可用 tick 之间的间距
    /// @param lte 是否向左搜索下一个已初始化 tick（小于或等于起始 tick）
    /// @return next 距当前 tick 最多 256 个 tick 以内的下一个已初始化或未初始化 tick
    /// @return initialized 下一个 tick 是否已初始化，因为该函数最多只在 256 个 tick 范围内搜索
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        unchecked {
            int24 compressed = compress(tick, tickSpacing);

            if (lte) {
                (int16 wordPos, uint8 bitPos) = position(compressed);
                // 当前 bitPos 及其右侧的所有 1
                uint256 mask = type(uint256).max >> (uint256(type(uint8).max) - bitPos);
                uint256 masked = self[wordPos] & mask;

                // 若当前 tick 及其右侧没有已初始化的 tick，则返回该字中最右侧的 tick
                initialized = masked != 0;
                // 可能发生溢出/下溢，但已通过在外部限制 tickSpacing 和 tick 加以防止
                next = initialized
                    ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * tickSpacing
                    : (compressed - int24(uint24(bitPos))) * tickSpacing;
            } else {
                // 从下一个 tick 所在的字开始，因为当前 tick 的状态无关紧要
                (int16 wordPos, uint8 bitPos) = position(++compressed);
                // bitPos 及其左侧的所有 1
                uint256 mask = ~((1 << bitPos) - 1);
                uint256 masked = self[wordPos] & mask;

                // 若当前 tick 左侧没有已初始化的 tick，则返回该字中最左侧的 tick
                initialized = masked != 0;
                // 可能发生溢出/下溢，但已通过在外部限制 tickSpacing 和 tick 加以防止
                next = initialized
                    ? (compressed + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * tickSpacing
                    : (compressed + int24(uint24(type(uint8).max - bitPos))) * tickSpacing;
            }
        }
    }
}
