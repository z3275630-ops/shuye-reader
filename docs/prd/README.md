# 后续 PRD 衔接

PRD 和调研提案放在本目录，以独立文件提交并关联 Issue / PR；按 CONTRIBUTING.md 的约定核对现有代码、用户要求、实际限制与验收条件。提案不等于已实现，不自动合并或发布。

本轮从 main `5914e12` 出发，主 Agent 直接推进 main；其他 Agent 通过 PR 提交文档和改动，由主 Agent 核对衔接。范围为共用表单 / 分组名称、阅读颜色校验和 PDF 目录 / 搜索 / 页码交互；实现见 `lib/edit_dialog.dart`、`lib/pdf_controls.dart` 及相关调用。结果见 [本轮验证](../verification-usability.md)。后续提案请引用这些已有能力，避免重复组件和覆盖。

本轮开始及提交前复查远端 PR / Issue 与 main。尚未收到其他 Agent 的 PRD；不提前制定其方案。收到后按“已实现 / 可以衔接 / 需求冲突 / 需设备或账号验证”核对，主 Agent 按小范围提交直接实现，其他 Agent 的改动通过 PR 审核衔接。复杂 EPUB、增量同步、原生服务和设备回归继续按 [功能对照](../report-coverage.md) 保留边界。
