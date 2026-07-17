# 地府篇前置接口包验证报告

## 结果

验证日期：`2026-07-17`

| 检查 | 结果 | 证据 |
|---|---|---|
| JSON 解析 | 通过 | `cross-chapter-interface.json`、`design-spec.json` 均可由 PowerShell `ConvertFrom-Json` 解析。 |
| 严格接口校验 | 通过 | `validate-underworld-preflight.ps1` 返回 `ok=true`、`0` errors。 |
| 负例：非空生产值 | 通过 | 向 `production_value` 注入 `1`，被 `non_null_nonproduction_value` 拒绝。 |
| 负例：伪造 Y3 ID | 通过 | 注入 `y3_id`，被 `forbidden_production_field` 拒绝。 |
| 负例：工作区外来源 | 通过 | 注入绝对来源， 被 `non_relative_source_ref` 拒绝。 |
| 负例：非规范进度键 | 通过 | 把逆潮完成键改为 `underworld_late`，被 `fixed_value_mismatch` 拒绝。 |
| 负例：离场复活/回传 | 通过 | 把 `left_behavior` 改为复活回传，被 `fixed_value_mismatch` 拒绝。 |
| 负例：清理确认身份顺序 | 通过 | 改写 `raid_instance_id + session_epoch + cleanup_token` 身份字段顺序，被 `fixed_array_mismatch` 拒绝。 |
| Normalizer 校验 | 通过 | `0` errors；保留 `missing_duration` 警告，因为本前置接口包不定义生产会话时长。 |
| Normalizer 完整度 | `100/100 ready` | 仅表示规划结构可交接；不表示地府内容、Y3 接入或生产门禁已开放。 |

## 已验证边界

- 固定 `DF_E_ZHUANLUN_HALL` 为 `team_instance`，`DF_E_YANLUO_HALL` 为非团队地府常规最终副本。
- 固定 `DF_PROGRESS_YANLUO_HALL_CLEARED` 为角色级、受信任、按 `(actor_id, event_id)` 幂等写入的进度键；花果山只能经受信任查询直接读取这一稳定键，不存在第二个写入键或第二套幂等收据。
- 固定 `HG_E_DRAGON_REVERSE_TIDE` 必须同时满足等级至少 `38` 与受信任查询命中该键；`underworld_late` 明确被拒绝。
- 固定团队成员死亡后的“先复活、再回章节 `initial_spawn`、保留 `dead` 与重入锁”顺序；只有同一 `raid_instance_id + session_epoch + cleanup_token` 的 `cleanup_ack` 才可解锁。`left` 不复活、不回传；全灭不重复回传死者，超时只回传 `active` 成员。
- 校验器确认 `implementation/difu/` 与 `implementation/growth/` 均不存在；本包未创建地府单位、地图、对象、Y3 ID、掉落、货币、物品、概率、保底或任何生产数值。

## 未验证且不得误报

- 阎罗殿的真实完成事件、持久化写入、地府地图、章节出生点和 Y3 地图根尚未存在。
- 花果山离线查询须直接读取 `DF_PROGRESS_YANLUO_HALL_CLEARED`；真实地图绑定、持久化查询与实机回读仍是后续接入任务。
- 所有经验、奖励、掉落、概率、货币、物品和保底仍处于非生产边界。
