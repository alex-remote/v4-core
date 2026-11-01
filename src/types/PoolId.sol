// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "./PoolKey.sol";

type PoolId is bytes32;

/// @notice 用于计算池子 ID 的库
library PoolIdLibrary {
    /// @notice 返回值等于 keccak256(abi.encode(poolKey))
    function toId(PoolKey memory poolKey) internal pure returns (PoolId poolId) {
        assembly ("memory-safe") {
            // 0xa0 表示 poolKey 结构体的总大小（5 个 32 字节的槽位）
            poolId := keccak256(poolKey, 0xa0)
        }
    }
}
