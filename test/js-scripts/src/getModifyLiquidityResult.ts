import { BigNumber, ethers } from "ethers";
import JSBI from "jsbi";
import Decimal from "decimal.js";

import { getSqrtPriceAtTick, getAmount0Delta, getAmount1Delta, JSBI_ZERO } from "./utils/shared";

const params = process.argv[2].split(",");

const tickLower = params[0];
const tickUpper = params[1];
const liquidity = params[2];
const slot0Tick = params[3];
const slot0Price = params[4];

const result = modifyLiquidity(tickLower, tickUpper, liquidity, slot0Tick, slot0Price);
process.stdout.write(ethers.utils.defaultAbiCoder.encode(["int128[]"], [result]));

function modifyLiquidity(
  _tickLower: string,
  _tickUpper: string,
  _liquidity: string,
  slot0Tick: string,
  slot0Price: string,
): string[] {
  // TODO: 实现手续费 delta 的计算。

  const liquidity = JSBI.BigInt(_liquidity);

  if (JSBI.EQ(liquidity, 0)) {
    return [JSBI_ZERO.toString(), JSBI_ZERO.toString()];
  }

  // slot0 中的状态值。
  const tick = JSBI.BigInt(slot0Tick);
  const sqrtPriceX96 = JSBI.BigInt(slot0Price);

  // 头寸的下限 tick 和上限 tick。
  const tickLower = JSBI.BigInt(_tickLower);
  const tickUpper = JSBI.BigInt(_tickUpper);

  let delta: string[] = [];

  if (JSBI.LT(tick, tickLower)) {
    // 当前 tick 小于头寸的最低 tick，因此头寸完全由 token0 构成。
    let priceLower = JSBI.BigInt(getSqrtPriceAtTick(_tickLower));
    let priceUpper = JSBI.BigInt(getSqrtPriceAtTick(_tickUpper));
    let amount0 = getAmount0Delta(priceLower, priceUpper, liquidity);
    delta.push(amount0.toString());
    delta.push(JSBI_ZERO.toString());
  } else if (JSBI.LT(tick, tickUpper)) {
    // 区间内流动性。由于我们只是在计算 delta 的值，
    // 所以不会更新 state.liquidity 这一全局状态变量，但注意在这种情况下协议会增加 state 的流动性。

    let priceUpper = JSBI.BigInt(getSqrtPriceAtTick(_tickUpper));
    let priceLower = JSBI.BigInt(getSqrtPriceAtTick(_tickLower));

    // 当 tickLower == 当前 tick 时，JS 中 getSqrtPriceATick 返回的价格存在轻微误差。
    // 而在 solidity 中，由于 getSqrtRatioAtTick(tickLower) 的计算结果 == currentSqrtPriceX96，
    // 分子变为 0，金额也随之为 0。
    // 因此我们不使用 getSqrtRatioAtTick 得到的价格，而是将 priceLower 设为当前价格。
    if (JSBI.EQ(tickLower, tick)) {
      priceLower = sqrtPriceX96;
    }

    let amount0 = getAmount0Delta(sqrtPriceX96, priceUpper, liquidity);
    let amount1 = getAmount1Delta(priceLower, sqrtPriceX96, liquidity);

    delta.push(amount0.toString());
    delta.push(amount1.toString());
  } else {
    // 当前 tick 大于头寸的最高 tick，意味着头寸完全由 token1 构成。
    let priceLower = JSBI.BigInt(getSqrtPriceAtTick(_tickLower));
    let priceUpper = JSBI.BigInt(getSqrtPriceAtTick(_tickUpper));

    let amount1 = getAmount1Delta(priceLower, priceUpper, liquidity);
    delta.push(JSBI_ZERO.toString());
    delta.push(amount1.toString());
  }

  return delta;
}
