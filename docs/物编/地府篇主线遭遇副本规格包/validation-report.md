# 地府篇主线、遭遇与副本规格包验证报告

## 结果

验证日期：`2026-07-20`

| 检查 | 结果 | 证据 |
|---|---|---|
| JSON 解析 | 通过 | 领域合同、规格视图与两个 JSON 交接简报均可由 PowerShell 解析。 |
| 严格主线规格校验 | 通过 | `validate-difu-mainline-spec.ps1` 返回 `ok=true`、`0` errors，并通过 `14/14` 负例。 |
| 十节点、白骨秘境与双轨路径 | 通过 | 校验器要求恰好十个路线 `spec_id`、一个白骨秘境 spec-local 单人副本角色；参考顺序、阎罗常规完成路径、固定转轮团队终点及其 deferred 入口/路线分别受约束。 |
| 阎罗/转轮跨篇同步 | 通过 | 校验器逐项比对地府前置接口：阎罗殿是唯一完成键写入者，转轮殿为团队本且非写入者。 |
| 负例：阎罗类型漂移 | 通过 | 将阎罗殿改为 `team_instance`，被 `fixed_value_mismatch` 拒绝。 |
| 负例：转轮写入完成键 | 通过 | 将转轮的非写入布尔改为 `true`，被 `strict_boolean_mismatch` 拒绝。 |
| 负例：泛化旧键 | 通过 | 将逆潮完成键替换为 `underworld_late`，被固定值与旧键门禁拒绝。 |
| 负例：新增运行时键或内部消费者 | 通过 | 注入新 `DF_E_*` 或把忘川河加入完成键消费者，分别被 `new_runtime_key_forbidden`、`internal_progression_consumer_forbidden` 拒绝。 |
| 负例：Y3/奖励字段 | 通过 | 注入 `y3_id` 或 `reward_amount`，被 `forbidden_production_field` 拒绝。 |
| 负例：工作区外来源 | 通过 | 注入绝对来源， 被 `non_relative_source_ref` 拒绝。 |
| 负例：固定终点、来源与局部标识 | 通过 | 降级转轮团队终点、断开任一节点来源、让白骨秘境写入完成键/数值或移除章节 spec-local 标记，均被拒绝。 |
| 负例：终审状态降级 | 通过 | 将领域合同从 `review-ready` 改回 `draft`，被 `fixed_value_mismatch` 拒绝。 |
| 地府—花果山镜像校验 | 通过 | `validate-difu-huaguoshan-contract.ps1` 返回 `ok=true`、`0` errors，并通过 `20/20` manifest、binding、Lua 文本与固定跨篇合同负例。 |
| 既有地府接口回归 | 通过 | `validate-underworld-preflight.ps1` 返回 `ok=true`、`0` errors，并通过 `7/7` 接口负例（含完整非写入者集合漂移）。 |
| 花果山行为回归 | 通过 | `preflight.ps1`、`test-config-binding-parity.ps1` 与 `test-y3-api-baseline.ps1` 通过；后者独立拒绝 `30` 条 Node/Fengari 离线执行边界逃逸路径。 |
| Normalizer 结构校验 | 通过 | `0` errors；保留 `missing_duration`，因为地府单次会话时长尚未裁决。 |
| Normalizer 完整度 | `90/100 ready` | 空的英雄、技能、物品、经济和波次桶是本包不创建对象/数值的有意边界，不是实现完成声明。 |

## 已验证边界

- 常规篇章止于 `DF_E_YANLUO_HALL`；它唯一写入角色级 `DF_PROGRESS_YANLUO_HALL_CLEARED`。
- `DF_E_ZHUANLUN_HALL` 是固定团队副本终点，引用 `TEAM_INSTANCE_RETURN_TO_CHAPTER_INITIAL_SPAWN_V1`；死亡、全灭、超时与离场的实际行为仍由既有花果山 Lua 回归证明，静态镜像校验不冒充运行时测试。
- 忘川河、奈何桥与望乡台以及通向转轮殿的入口/物理拓扑保持 deferred；没有被擅自转化为物理地图连接、阎罗完成键消费者或新的 runtime key。
- 白骨秘境固定为 `DF_SIDE_BAIGU_SECRET_REALM` 的 spec-local 单人副本角色；它不写入/消费阎罗完成键，也不定义生产奖励或数值。
- 所有十个路线节点、白骨秘境角色和成长经济决策来源均逐条解析到工作区内的有效文件与行号。
- 本包没有 `implementation/difu/`、`implementation/growth/`、Y3 ID、地图资源、坐标、对象记录、奖励表、经验、货币、概率或保底字段。

## 未验证且不得误报

- 地府真实地图根、`chapter_initial_spawn` 资源、入口出口、坐标、地形与对象 ID。
- 白骨秘境、阎罗殿和转轮殿的对象、Boss 阶段、波次、战斗状态机、传送、持久化和同步实现。
- 奖励、掉落、经验、货币、物品、保底、资格、资源吞吐、地府内部入口条件与会话时长。
- Y3 编辑器回读、四人实机、UI、多人同步和真实完成事件验证。
