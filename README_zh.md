# Uniswap v4 Core

[![Lint](https://github.com/Uniswap/v4-core/actions/workflows/lint.yml/badge.svg)](https://github.com/Uniswap/v4-core/actions/workflows/lint.yml)
[![Tests](https://github.com/Uniswap/v4-core/actions/workflows/tests-merge.yml/badge.svg)](https://github.com/Uniswap/v4-core/actions/workflows/tests-merge.yml)

Uniswap v4 是一个全新的自动做市商（AMM）协议，提供可扩展、可定制的池子。`v4-core` 包含核心的池子逻辑，用于创建池子以及执行兑换（swap）、提供流动性等池子操作。

本仓库中的合约尚处于早期阶段——我们现在就发布草案代码，是为了让 v4 能够公开构建，获得开放的反馈和有意义的社区贡献。我们预计这将是一个历时数月的过程，并感谢任何形式的贡献，无论大小。

## 贡献

如果你有兴趣参与贡献，请参阅我们的[贡献指南](./CONTRIBUTING_zh.md)！

## 白皮书

关于 Uniswap v4 Core 更详细的描述，请参阅 [Uniswap v4 Core 白皮书](./docs/whitepaper/whitepaper-v4.pdf)草案。

## 架构

`v4-core` 采用单例（singleton）风格的架构，所有池子状态都在 `PoolManager.sol` 合约中管理。在首次调用 `unlock` 之后即可执行池子操作。集成方需实现 `unlockCallback`，并在其中对池子执行以下任意操作：

- `swap`
- `modifyLiquidity`
- `donate`
- `take`
- `settle`
- `mint`
- `burn`

注意，池子的初始化可以在解锁 PoolManager 的上下文之外进行。

在一次解锁的整个持续期间，只跟踪欠用户的净余额（正值）或欠池子的净余额（负值），这就是解锁状态中保存的 `delta` 字段。只要解锁期间累积的 delta 在解锁结束释放时归零，就可以在池子上执行任意数量的操作。这种“解锁并调用”式的架构为调用者与核心代码的集成提供了最大的灵活性。

此外，池子在初始化时可以绑定一个 hook 合约，该合约可以在池子操作的生命周期中实现以下任意回调：

- {before,after}Initialize
- {before,after}AddLiquidity
- {before,after}RemoveLiquidity
- {before,after}Swap
- {before,after}Donate

回调逻辑可以由 hook 根据其自身实现进行更新。但池子初始化之后，该池子上会执行 _哪些_ 回调就不能再更改。

## 仓库结构

所有合约都位于 `v4-core/src` 文件夹中。

注意，测试所用的辅助合约位于 `src` 文件夹下的 `v4-core/src/test` 子文件夹中。任何新的测试辅助合约都应添加到这里，而所有 foundry 测试都位于 `v4-core/test` 文件夹中。

```markdown
src/
----interfaces/
    | IPoolManager.sol
    | ...
----libraries/
    | Position.sol
    | Pool.sol
    | ...
----test
----PoolManager.sol
...
test/
----libraries/
    | Position.t.sol
    | Pool.t.sol
```

## 本地部署与使用

如需使用这些合约并部署到本地测试网，可以通过 forge 将代码安装到你的仓库中：

```markdown
forge install https://github.com/Uniswap/v4-core
```

如需与这些合约集成，可以使用以下接口：

```solidity

import {IPoolManager} from 'v4-core/contracts/interfaces/IPoolManager.sol';
import {IUnlockCallback} from 'v4-core/contracts/interfaces/callback/IUnlockCallback.sol';

contract MyContract is IUnlockCallback {
    IPoolManager poolManager;

    function doSomethingWithPools() {
        // 该函数将调用下方的 `unlockCallback`
        poolManager.unlock(...);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        // 禁止任意调用者
        if (msg.sender != address(poolManager) revert Unauthorized();
        // 执行池子操作
        poolManager.swap(...)
    }
}

error Unauthorized();
```

## 许可证

Uniswap V4 Core 依据 Business Source License 1.1（`BUSL-1.1`）授权，参见 [BUSL_LICENSE](https://github.com/Uniswap/v4-core/blob/main/licenses/BUSL_LICENSE)；同时依据 MIT 许可证（`MIT`）授权，参见 [MIT_LICENSE](https://github.com/Uniswap/v4-core/blob/main/licenses/MIT_LICENSE)。Uniswap V4 Core 中的每个文件都在文件头部注明了适用的许可证类型。
