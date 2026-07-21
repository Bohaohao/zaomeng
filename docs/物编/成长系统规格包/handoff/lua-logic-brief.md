# Lua 逻辑交接简报

## 目标

以 `economy-v2` 为冻结设计输入，实现成长相关的同步权威事务；本简报不包含 Lua 代码，且不授权直接接入 Y3 或生产账本。

## 必须实现的职责

1. 仅按 `economy-v2` 的 XP 来源行、倍率、首次/重复结算类型和终态收据授予经验，再处理等级上限、升级事件与 `Lv1` 自动技能 / `Lv2-Lv60` 59 点的精确守恒。
2. 四职业基础属性的全量幂等重算，以及装备、强化、进阶、法宝、宠物、收集和临时状态的确定顺序叠加；完整定点计算后统一四舍五入写入整数，禁止截断。
3. 存档载入、版本迁移、重连、构筑原子切换、挑战锁与临时战斗态清理；预设必须一起校验并切换 5 主动、装备引用、法宝引用和宠物配置引用，物品实例不复制状态。
4. 龙宫旧潮/逆潮、通天塔和章节门槛的可信权威校验；完整旧潮交互还校验每个职业自己的 Lv8 核心路线完成键：C01/C02/C03 分别是 `C01_ROUTE_LV8_core`、`C02_ROUTE_LV8_core`、`C03_ROUTE_LV8_core`，C04 校验当前所选 `C04_ROUTE_LV8_hunt|wind|bind`；不得信任调用方布尔值或本地 UI。
5. 实现 Lv8 私有路线 attempt 事务：开始时创建带 `attempt_id`、`actor_id`、`profession_id`、`route_key`、`trial_lifecycle_id`、`start_tick`、`deadline_tick` 的会话态；成功仅在同 actor、同职业、同 lifecycle 且已满 60 秒时，以 `event_id` + `(actor_id, route_key)` 幂等原子写入永久完成记录。失败、超时、死亡、中止、跨层和断线只清理 attempt；已完成的重复成功返回原结果且不重复结算。队友、公共事件、发现入口和客户端状态不得代写通过键。
6. C04 的完整龙宫交互必须校验同一 `actor_id` 已写入的 `C04_ROUTE_LV8_hunt|wind|bind` 通过键；路线、一次性资格、绝技资格/永久阶级和 `recovery_next_eligible_tick` 持久化为绝对进度/时钟，不能与临时猎印或当前绝技能量混同。Lv15 一阶绝技试炼还必须校验 `C04_U01_TRIAL_ELIGIBLE`、`C04_REAL_RECOVERY_INTRO` 与 `u01_tier=0`，成功后才写入永久一阶。
7. `kill_honor_credit`、`progression_participation`、参与箱、稀有资格、保底和 roll 的独立证据链与幂等结算。花果山公共行为必须复用完整 encounter origin/window 载荷，先按 `event_id` 去重，再按 `(actor_id, boss_instance_id, phase_id, mechanic_occurrence_id, encounter_action_key)` 限制每 occurrence 一次成功；`primary/assist` 只写行为角色，不能直接发参与箱、稀有资格或保底。
8. 物品/材料/货币事务、强化/进阶/合成/孵化、掉落 profile/保底策略、重复请求保护与审计日志；货币账本与掉落 profile 是系统数据，不是物品对象。每笔 economy-v2 收据必须以权威 `(actor_id, lifecycle_id, authority_proof_ref)` 解析稳定 `owner_id`，并携带 `owner_scope`、`schema_version`、`resource_table_version`、权威 `event_id`、来源/奖励计划哈希、资格/roll 证明与终态；不得把裸 actor/lifecycle 或客户端 owner 写入账本。

## 阻塞项

- economy-v2 的权威编译、持久化收据、proof-to-owner 解析和跨重启对账。
- 装备/法宝/宠物/材料消耗、地府/天庭 source_profile 与后续塔数据。
- 真实 Y3 事件、属性映射和存档 API 的正式确认。

## 不可违反的规则

- 不得逐级累加基础成长；必须全量重算。
- 不得把 `effective_participant_ids` 直接映射为参与箱、稀有或保底。
- 不得让 UI、客户端随机或调用方自报资格改变共享状态。
- 不得绕过 economy-v2 的来源绑定、奖励投影、资格快照、参与箱/团队绑定、保底状态机或终态矩阵。
- 不得持久化战势、守势、法印、猎印、绝技能量、冷却或短时效果。
