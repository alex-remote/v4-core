// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {FullMath} from "./FullMath.sol";
import {FixedPoint128} from "./FixedPoint128.sol";
import {LiquidityMath} from "./LiquidityMath.sol";
import {CustomRevert} from "./CustomRevert.sol";

/// @title Position
/// @notice 头寸表示某个所有者地址在下界 tick 与上界 tick 之间提供的流动性
/// @dev 头寸还存储额外的状态，用于追踪应付给该头寸的手续费
library Position {
    using CustomRevert for bytes4;

    /// @notice 不能更新没有流动性的头寸
    error CannotUpdateEmptyPosition();

    // 为每个用户头寸存储的信息
    struct State {
        // 该头寸拥有的流动性数量
        uint128 liquidity;
        // 截至上次更新流动性或应付手续费时，每单位流动性的手续费增长量
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
    }

    /// @notice 给定所有者和头寸边界，返回该头寸的 State 结构体
    /// @param self 包含所有用户头寸的 mapping
    /// @param owner 头寸所有者的地址
    /// @param tickLower 头寸的下界 tick
    /// @param tickUpper 头寸的上界 tick
    /// @param salt 用于区分同一区间内多个头寸的唯一值
    /// @return position 给定所有者头寸的头寸信息结构体
    function get(mapping(bytes32 => State) storage self, address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
        internal
        view
        returns (State storage position)
    {
        bytes32 positionKey = calculatePositionKey(owner, tickLower, tickUpper, salt);
        position = self[positionKey];
    }

    /// @notice 计算头寸 key 的辅助函数
    /// @param owner 头寸所有者的地址
    /// @param tickLower 头寸的下界 tick
    /// @param tickUpper 头寸的上界 tick
    /// @param salt 用于区分同一所有者在同一区间内多个头寸的唯一值，由调用者传入。
    function calculatePositionKey(address owner, int24 tickLower, int24 tickUpper, bytes32 salt)
        internal
        pure
        returns (bytes32 positionKey)
    {
        // positionKey = keccak256(abi.encodePacked(owner, tickLower, tickUpper, salt))
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(add(fmp, 0x26), salt) // [0x26, 0x46)
            mstore(add(fmp, 0x06), tickUpper) // [0x23, 0x26)
            mstore(add(fmp, 0x03), tickLower) // [0x20, 0x23)
            mstore(fmp, owner) // [0x0c, 0x20)
            positionKey := keccak256(add(fmp, 0x0c), 0x3a) // 长度为 58 字节

            // 现在清理我们用过的内存
            mstore(add(fmp, 0x40), 0) // fmp+0x40 处存放过 salt
            mstore(add(fmp, 0x20), 0) // fmp+0x20 处存放过 tickLower、tickUpper、salt
            mstore(fmp, 0) // fmp 处存放过 owner
        }
    }

    /// @notice 将累积的手续费记入用户的头寸
    /// @param self 要更新的单个头寸
    /// @param liquidityDelta 本次头寸更新导致的池子流动性变化量
    /// @param feeGrowthInside0X128 头寸 tick 边界内 currency0 的历史累计手续费增长量（按每单位流动性计）
    /// @param feeGrowthInside1X128 头寸 tick 边界内 currency1 的历史累计手续费增长量（按每单位流动性计）
    /// @return feesOwed0 应付给头寸所有者的 currency0 数量
    /// @return feesOwed1 应付给头寸所有者的 currency1 数量
    function update(
        State storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal returns (uint256 feesOwed0, uint256 feesOwed1) {
        uint128 liquidity = self.liquidity;

        if (liquidityDelta == 0) {
            // 不允许对流动性为 0 的头寸进行 poke（即 liquidityDelta 为 0 的更新）
            if (liquidity == 0) CannotUpdateEmptyPosition.selector.revertWith();
        } else {
            self.liquidity = LiquidityMath.addDelta(liquidity, liquidityDelta);
        }

        // 计算累积的手续费。手续费增长量相减时发生溢出是预期行为
        unchecked {
            feesOwed0 =
                FullMath.mulDiv(feeGrowthInside0X128 - self.feeGrowthInside0LastX128, liquidity, FixedPoint128.Q128);
            feesOwed1 =
                FullMath.mulDiv(feeGrowthInside1X128 - self.feeGrowthInside1LastX128, liquidity, FixedPoint128.Q128);
        }

        // 更新头寸
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
    }
}
