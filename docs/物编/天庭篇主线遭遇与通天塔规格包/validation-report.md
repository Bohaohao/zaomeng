# 天庭篇离线规格验证记录

## 结论

验证日期：2026-07-21。三项离线校验均已运行；没有结构错误。此结果只证明规格包的边界、自洽性和交接字段可验证，不能代表地图、对象、Lua、UI、多人、存档或经济已实现。

| 校验 | 命令结果 | 结论 |
|---|---|---|
| 包内边界校验 | `VALIDATION PASSED: 508 checks` | 原有等级、跨篇、经济与键边界通过；资源表 canonical 状态与设计引用角色已分离校验。首轮五节拍顺序、第五节拍休整、结算/失败/退出/交接终局、幂等语义包络、角色归属、塔资格快照、`tower_award_class`、周额度前后值、无运行时键、`economy-v2` 外部设计引用和 `implementation/growth/` 候选隔离均通过。 |
| 设计规格结构校验 | `ok: true`，`errors: []` | 所有必填设计字段、会话流程、内容桶、MVP、交接和验收字段均有效。 |
| 设计完整度校验 | `100/100`，`grade: ready` | 仅证明离线交接信息完整；不会把任何 deferred 内容提升为可生产资产。 |

## 保留提示

设计规格结构校验报告了 1 条预期提示：`targetDurationMinutes = 0`。单次时长在当前批准来源中未定，为避免臆造数值而明确保留为未裁定；这不是校验错误。

设计规格还报告 6 项 unresolved。这些是生产门禁，而不是待自动填充的空值：独立进度合同、公共/副本职责、单人选择、团队关系、全局塔运行合同，以及天庭 XP source_profile 与 `economy-v2` 的权威运行时接入。五节拍合同只补齐首轮子循环的状态边界，不替代全局记录、持久化、后续循环、资源与实机合同。

## 可复现命令

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\天庭篇主线遭遇与通天塔规格包\validate-tianting-tower-spec.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\validate-design-spec.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\design-spec.json
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\score-spec-completeness.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\design-spec.json
~~~

## 验收口径

- 包内校验器验证等级、塔、跨篇键、局部 `TT_SPEC_` 标识和运行时键为空，并验证首轮五节拍、第五节拍休整、终局互斥、pending 收束与幂等语义包络；塔首轮奖励只能外部引用 runtime-closed `economy-v2`，并要求 owner、资格快照、塔 run/cycle/week/mode、周额度前后值、收据哈希和证明字段。
- 设计规格校验必须无 errors；时长提示只反映未批准的时长缺口。
- 完整度评分用于检查交接字段齐备性，不能将 deferred 内容提升为已实施内容。
