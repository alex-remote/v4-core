# 贡献指南

感谢你有兴趣为 Uniswap 协议 v4 做出贡献！本仓库中的合约尚处于早期阶段——我们现在就发布草案代码，是为了让 v4 能够公开构建，接受公开反馈并获得有意义的社区贡献。我们预计这将是一个持续数月的过程，任何形式的贡献，无论大小，我们都非常感谢。

如果你需要联系仓库维护者，请通过我们的 [Discord](https://discord.com/invite/FCfyBSbCU5) 与我们联系。

## 贡献方式

贡献的方式有很多，如果你想找个起点，可以参考以下几种：

1. **提交 issue。** 在提交 issue 之前，请先确认是否已有相同的 issue 处于打开状态。如果已有，欢迎在该 issue 中补充更多细节、解释或示例，而不是重复创建。对开放开发流程提出修改建议也属于提交 issue 的范畴。我们始终乐于接受反馈和建议！
2. **解决 issue。** 你可以通过证明某个 issue 其实并不是问题，或者通过代码修改、补充测试等方式修复该 issue 来解决它。任何修复 issue 的 pull request 都应引用该 issue。
3. **评审开放中的 PR。** 你可以在任何开放中的 pull request 上提供评论、规范指导、命名建议、gas 优化或替代设计思路。

## 提交 Issue

提交 [issue](https://github.com/Uniswap/v4-core/issues/new/choose) 时，请选择一个模板作为起点：Bug Report（缺陷报告）或 Feature Improvement（功能改进）。对于缺陷报告，你应当能够通过测试或概念验证（proof of concept）实现来复现该缺陷。对于功能改进，请用简洁的问题陈述作为标题，并确认尚无类似的请求处于打开或进行中状态。并非所有 issue 都会被认为值得解决，因此请持续跟进，回复其他人可能就该 issue 提出的任何问题或评论。

对于任何与清理相关的 issue 或范围较小的改动，欢迎将其标记为 “good first issue”，以鼓励首次贡献者提交 pull request！

## 提交 Pull Request

所有 pull request 都应以 `main` 分支为目标分支。请在 pull request 中引用你所修复的 issue。

社区成员可以评审 pull request，但要合并则需要获得仓库维护者的批准。请理解收到回复需要一些时间，不过维护者会力求尽快回复和评论。

**对于规模较大、较为实质性的代码改动，最好先提交一个 issue 并与维护者展开讨论，在投入开发时间之前就改动达成一致。**

最后，在提交 pull request 之前，请完成以下事项：

- 检查代码风格是否符合[规范](#standards)。
- 运行测试和快照。相关命令见[测试](#tests)一节。
- 按照 NatSpec 规范为所有新增的函数、结构体或接口编写文档。
- 添加测试！对于较小的贡献，应编写单元测试，并尽可能编写模糊测试。对于较大的贡献，应尽可能编写集成测试和不变量测试。
- 确保所有提交都已[签名](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)

## 规范

所有贡献都必须遵循以下规范。维护者会关闭不符合这些规范的 PR。

1. 所有合约都应使用默认的 forge fmt 配置进行格式化。请运行 `forge fmt`。
2. 这些合约遵循 [Solidity 风格指南](https://docs.soliditylang.org/en/v0.8.17/style-guide.html)，仅有一个小例外：对于合约的 internal 函数、internal 顶层参数以及存在命名冲突的函数参数，使用 \_prependUnderscore 风格命名（即加下划线前缀）。
3. 所有对外暴露的合约都应继承自接口，由接口声明其函数并用 NatSpec 编写文档。
4. 接手其他作者已停滞的 issue 是可以的！只是请事先与他们沟通，最佳实践是在相关提交中将他们列为共同作者（co-author）。
5. 尽可能压缩（squash）提交，使评审清晰高效。合并到 main 的 PR 会被压缩为 1 个提交。

## 环境配置

`forge build`：获取合约构建产物（artifacts）以及 forge 所需的依赖

`forge test --isolate`：运行 forge 测试并更新快照

## 行为准则

最重要的是，请尊重代码背后的人。任何具有攻击性或不尊重他人的评论、issue 和言论都将被删除。

明显属于垃圾信息、对开发过程无益或与核心代码无关的 issue 和 PR 也会被关闭。
