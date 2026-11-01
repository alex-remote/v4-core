// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {CustomRevert} from "../libraries/CustomRevert.sol";

type Currency is address;

using {greaterThan as >, lessThan as <, greaterThanOrEqualTo as >=, equals as ==} for Currency global;
using CurrencyLibrary for Currency global;

function equals(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) == Currency.unwrap(other);
}

function greaterThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) > Currency.unwrap(other);
}

function lessThan(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) < Currency.unwrap(other);
}

function greaterThanOrEqualTo(Currency currency, Currency other) pure returns (bool) {
    return Currency.unwrap(currency) >= Currency.unwrap(other);
}

/// @title CurrencyLibrary
/// @dev 该库支持转账和持有原生代币及 ERC20 代币
library CurrencyLibrary {
    /// @notice 原生代币转账失败时，作为 ERC-7751 包装错误的附加上下文
    error NativeTransferFailed();

    /// @notice ERC20 转账失败时，作为 ERC-7751 包装错误的附加上下文
    error ERC20TransferFailed();

    /// @notice 表示原生代币的常量
    Currency public constant ADDRESS_ZERO = Currency.wrap(address(0));

    function transfer(Currency currency, address to, uint256 amount) internal {
        // 改编自 https://github.com/transmissions11/solmate/blob/44a9963d4c78111f77caa0e65d677b8b46d6f2e6/src/utils/SafeTransferLib.sol
        // 修改了自定义错误的选择器

        bool success;
        if (currency.isAddressZero()) {
            assembly ("memory-safe") {
                // 转出 ETH，失败则回滚（revert）。
                success := call(gas(), to, amount, 0, 0, 0, 0)
            }
            // 以 NativeTransferFailed 回滚（revert），并将向上冒泡的错误作为参数携带
            if (!success) {
                CustomRevert.bubbleUpAndRevertWith(to, bytes4(0), NativeTransferFailed.selector);
            }
        } else {
            assembly ("memory-safe") {
                // 获取指向一段空闲内存的指针。
                let fmp := mload(0x40)

                // 将 ABI 编码的 calldata 写入内存，以函数选择器开头。
                mstore(fmp, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
                mstore(add(fmp, 4), and(to, 0xffffffffffffffffffffffffffffffffffffffff)) // 追加 "to" 参数并对其应用掩码。
                mstore(add(fmp, 36), amount) // 追加 "amount" 参数。它是完整的 32 字节类型，无需掩码。

                success :=
                    and(
                        // 将 success 设为调用是否未回滚（revert）；若未回滚，再检查其要么
                        // 恰好返回 1（不能仅仅是非零数据），要么没有返回数据。
                        or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                        // 使用 68 是因为 calldata 的总长度为：4 + 32 * 2。
                        // 使用 0 和 32 是为了把最多 32 字节的返回数据复制到 scratch space（暂存空间）中。
                        // 反直觉的是，在外层的 and() 调用中，该 call 必须排在 or() 调用之后，
                        // 否则在计算 or() 时 returndatasize() 将为零。
                        call(gas(), currency, 0, fmp, 68, 0, 32)
                    )

                // 现在清理我们用过的内存
                mstore(fmp, 0) // 此处存放了 4 字节的 `selector` 和 `to` 的 28 字节
                mstore(add(fmp, 0x20), 0) // 此处存放了 `to` 的 4 字节和 `amount` 的 28 字节
                mstore(add(fmp, 0x40), 0) // 此处存放了 `amount` 的 4 字节
            }
            // 以 ERC20TransferFailed 回滚（revert），并将向上冒泡的错误作为参数携带
            if (!success) {
                CustomRevert.bubbleUpAndRevertWith(
                    Currency.unwrap(currency), IERC20Minimal.transfer.selector, ERC20TransferFailed.selector
                );
            }
        }
    }

    function balanceOfSelf(Currency currency) internal view returns (uint256) {
        if (currency.isAddressZero()) {
            return address(this).balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(address(this));
        }
    }

    function balanceOf(Currency currency, address owner) internal view returns (uint256) {
        if (currency.isAddressZero()) {
            return owner.balance;
        } else {
            return IERC20Minimal(Currency.unwrap(currency)).balanceOf(owner);
        }
    }

    function isAddressZero(Currency currency) internal pure returns (bool) {
        return Currency.unwrap(currency) == Currency.unwrap(ADDRESS_ZERO);
    }

    function toId(Currency currency) internal pure returns (uint256) {
        return uint160(Currency.unwrap(currency));
    }

    // 若高 12 字节非零，它们会被清零
    // 因此，fromId() 与 toId() 并非互逆操作
    function fromId(uint256 id) internal pure returns (Currency) {
        return Currency.wrap(address(uint160(id)));
    }
}
