// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/libraries/FullMath.sol";
import "../../src/libraries/FixedPoint96.sol";

/// @title 流动性数量计算函数
/// @notice 提供根据代币数量和价格计算流动性数量的函数
library LiquidityAmounts {
    /// @notice 将 uint256 向下转换为 uint128
    /// @param x 待向下转换的 uint258
    /// @return y 传入的值，已向下转换为 uint128
    function toUint128(uint256 x) private pure returns (uint128 y) {
        require((y = uint128(x)) == x, "liquidity overflow");
    }

    /// @notice 根据给定的 token0 数量和价格区间，计算可获得的流动性数量
    /// @dev 计算 amount0 * (sqrt(upper) * sqrt(lower)) / (sqrt(upper) - sqrt(lower))
    /// @param sqrtPriceAX96 表示第一个 tick 边界的平方根价格
    /// @param sqrtPriceBX96 表示第二个 tick 边界的平方根价格
    /// @param amount0 转入的 amount0
    /// @return liquidity 返回的流动性数量
    function getLiquidityForAmount0(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        uint256 intermediate = FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
        return toUint128(FullMath.mulDiv(amount0, intermediate, sqrtPriceBX96 - sqrtPriceAX96));
    }

    /// @notice 根据给定的 token1 数量和价格区间，计算可获得的流动性数量
    /// @dev 计算 amount1 / (sqrt(upper) - sqrt(lower))。
    /// @param sqrtPriceAX96 表示第一个 tick 边界的平方根价格
    /// @param sqrtPriceBX96 表示第二个 tick 边界的平方根价格
    /// @param amount1 转入的 amount1
    /// @return liquidity 返回的流动性数量
    function getLiquidityForAmount1(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        return toUint128(FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtPriceBX96 - sqrtPriceAX96));
    }

    /// @notice 根据给定的 token0 数量、token1 数量、当前
    /// 池子价格以及各 tick 边界处的价格，计算可获得的最大流动性数量
    /// @param sqrtPriceX96 表示当前池子价格的平方根价格
    /// @param sqrtPriceAX96 表示第一个 tick 边界的平方根价格
    /// @param sqrtPriceBX96 表示第二个 tick 边界的平方根价格
    /// @param amount0 转入的 token0 数量
    /// @param amount1 转入的 token1 数量
    /// @return liquidity 可获得的最大流动性数量
    function getLiquidityForAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            liquidity = getLiquidityForAmount0(sqrtPriceAX96, sqrtPriceBX96, amount0);
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtPriceX96, sqrtPriceBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceX96, amount1);

            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceBX96, amount1);
        }
    }

    /// @notice 根据给定的流动性数量和价格区间，计算 token0 的数量
    /// @param sqrtPriceAX96 表示第一个 tick 边界的平方根价格
    /// @param sqrtPriceBX96 表示第二个 tick 边界的平方根价格
    /// @param liquidity 待估值的流动性
    /// @return amount0 token0 的数量
    function getAmount0ForLiquidity(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);

        return FullMath.mulDiv(
            uint256(liquidity) << FixedPoint96.RESOLUTION, sqrtPriceBX96 - sqrtPriceAX96, sqrtPriceBX96
        ) / sqrtPriceAX96;
    }

    /// @notice 根据给定的流动性数量和价格区间，计算 token1 的数量
    /// @param sqrtPriceAX96 表示第一个 tick 边界的平方根价格
    /// @param sqrtPriceBX96 表示第二个 tick 边界的平方根价格
    /// @param liquidity 待估值的流动性
    /// @return amount1 token1 的数量
    function getAmount1ForLiquidity(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);

        return FullMath.mulDiv(liquidity, sqrtPriceBX96 - sqrtPriceAX96, FixedPoint96.Q96);
    }

    /// @notice 根据给定的流动性数量、当前
    /// 池子价格以及各 tick 边界处的价格，计算 token0 和 token1 的价值
    /// @param sqrtPriceX96 表示当前池子价格的平方根价格
    /// @param sqrtPriceAX96 表示第一个 tick 边界的平方根价格
    /// @param sqrtPriceBX96 表示第二个 tick 边界的平方根价格
    /// @param liquidity 待估值的流动性
    /// @return amount0 token0 的数量
    /// @return amount1 token1 的数量
    function getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            amount0 = getAmount0ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity);
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            amount0 = getAmount0ForLiquidity(sqrtPriceX96, sqrtPriceBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity);
        }
    }
}
