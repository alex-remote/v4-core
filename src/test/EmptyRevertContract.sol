// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

contract EmptyRevertContract {
    // 用于模拟不带 returndata 回滚（revert）的合约，以测试我们的错误捕获逻辑是否正常工作
    fallback() external {
        revert();
    }
}
