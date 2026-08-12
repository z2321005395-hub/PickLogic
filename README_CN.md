# PickLogic / 拾理

**小而精、本地优先、即装即用。**

不用记文件在哪里，只需要知道它是什么。

拾理是一个本地优先的文件理解与整理项目。同一个 Flutter/Dart monorepo 生成 PickLogic Desktop、PickLogic Pro 和 PickLogic Mobile。**知件 · Insight** 根据证据和置信度解释选中的文件、截图、文献与存储，不把聊天机器人放在首页。

> 当前状态：正在进行 Private v0.1.0-alpha 集成，尚无公开发行版。

## 产品目标

- **PickLogic Desktop**：Windows 普通版，提供本地扫描、虚拟分类、搜索、预览、完全重复检测、整理计划与知件。
- **PickLogic Pro**：与普通版共享同一桌面代码，增加轻量文献管理、研究工作区和只读系统洞察。
- **PickLogic Mobile**：Android 文件、截图、照片、存储洞察、快速审阅与知件。

## 安全与隐私

- 无强制账号、广告、默认遥测或云端后端。
- Debug 构建强制显示并执行 Developer Safe Mode。
- 虚拟分类不移动原文件。
- 任何变更必须先形成计划、预览、确认，并提供撤销或回收机制。
- 未知或受保护内容绝不标记为“可放心删除”。

## 文档

请阅读 [架构](ARCHITECTURE.md)、[产品原则](PRODUCT_PRINCIPLES.md)、[安全与隐私](SECURITY_AND_PRIVACY.md)、[安装说明](docs/INSTALLATION.md)、[已知问题](docs/KNOWN_ISSUES.md)、[路线图](ROADMAP.md) 和 [贡献指南](CONTRIBUTING.md)。

开发基线为 Flutter stable、Dart、本地 SQLite，以及范围明确的 Windows/Android 原生桥接。参考机使用 `tools\picklogic.cmd env` 和 `tools\picklogic.cmd quick`；该入口优先复用 TTDT Android 工具链，也不要求修改 PowerShell 执行策略。

最终开源许可证和版权人尚待维护者确认。在完成这些决定和公开发布门禁前，仓库必须保持 Private。
