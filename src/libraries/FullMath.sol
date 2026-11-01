// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title 包含 512 位数学运算函数
/// @notice 支持中间值可能溢出的乘法与除法运算，且不损失任何精度
/// @dev 处理“幻影溢出”（phantom overflow），即允许中间值超出 256 位的乘除运算
library FullMath {
    /// @notice 以全精度计算 floor(a×b÷denominator)。若结果溢出 uint256 或 denominator == 0 则抛出异常
    /// @param a 被乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result 256 位的结果
    /// @dev 致谢 Remco Bloemen（MIT 许可证）：https://xn--2-umb.com/21/muldiv
    function mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512 位乘法 [prod1 prod0] = a * b
            // 分别计算乘积对 2**256 和对 2**256 - 1 取模的结果
            // 然后利用中国剩余定理重建出
            // 512 位的结果。结果存放在两个 256 位
            // 变量中，满足 product = prod1 * 2**256 + prod0
            uint256 prod0 = a * b; // 乘积的低 256 位
            uint256 prod1; // 乘积的高 256 位
            assembly ("memory-safe") {
                let mm := mulmod(a, b, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // 确保结果小于 2**256。
            // 同时也防止 denominator == 0
            require(denominator > prod1);

            // 处理未溢出的情况：256 位除以 256 位
            if (prod1 == 0) {
                assembly ("memory-safe") {
                    result := div(prod0, denominator)
                }
                return result;
            }

            ///////////////////////////////////////////////
            // 512 位除以 256 位。
            ///////////////////////////////////////////////

            // 从 [prod1 prod0] 中减去余数，使除法能够整除
            // 使用 mulmod 计算余数
            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(a, b, denominator)
            }
            // 从 512 位数中减去 256 位数
            assembly ("memory-safe") {
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // 从 denominator 中提取出 2 的幂因子
            // 计算 denominator 的最大 2 的幂约数。
            // 恒 >= 1。
            uint256 twos = (0 - denominator) & denominator;
            // 用该 2 的幂去除 denominator
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
            }

            // 用 2 的幂因子去除 [prod1 prod0]
            assembly ("memory-safe") {
                prod0 := div(prod0, twos)
            }
            // 将 prod1 中的位移入 prod0。为此我们需要
            // 翻转 `twos`，使其变为 2**256 / twos。
            // 若 twos 为零，则它变为一
            assembly ("memory-safe") {
                twos := add(div(sub(0, twos), twos), 1)
            }
            prod0 |= prod1 * twos;

            // 求 denominator 模 2**256 的逆元
            // 由于此时 denominator 是奇数，它存在一个
            // 模 2**256 的逆元，满足 denominator * inv = 1 mod 2**256。
            // 计算逆元时，先取一个种子值作为起点，该种子
            // 在低四位上是正确的。即 denominator * inv = 1 mod 2**4
            uint256 inv = (3 * denominator) ^ 2;
            // 接下来使用 Newton-Raphson 迭代来提高精度。
            // 得益于 Hensel 引理（Hensel's lifting lemma），该方法在模
            // 运算中同样适用，每一步都使正确的位数翻倍。
            inv *= 2 - denominator * inv; // 模 2**8 的逆元
            inv *= 2 - denominator * inv; // 模 2**16 的逆元
            inv *= 2 - denominator * inv; // 模 2**32 的逆元
            inv *= 2 - denominator * inv; // 模 2**64 的逆元
            inv *= 2 - denominator * inv; // 模 2**128 的逆元
            inv *= 2 - denominator * inv; // 模 2**256 的逆元

            // 由于现在除法是整除的，我们可以通过乘以
            // denominator 的模逆元来完成除法。这将得到
            // 模 2**256 意义下的正确结果。由于前置条件保证了
            // 结果小于 2**256，因此这就是最终结果。
            // 我们无需计算结果的高位，并且 prod1
            // 也不再需要了。
            result = prod0 * inv;
            return result;
        }
    }

    /// @notice 以全精度计算 ceil(a×b÷denominator)。若结果溢出 uint256 或 denominator == 0 则抛出异常
    /// @param a 被乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result 256 位的结果
    function mulDivRoundingUp(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            result = mulDiv(a, b, denominator);
            if (mulmod(a, b, denominator) != 0) {
                require(++result > 0);
            }
        }
    }
}
