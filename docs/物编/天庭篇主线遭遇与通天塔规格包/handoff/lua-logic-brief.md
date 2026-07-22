# Lua 逻辑交接简报

本包不生成 Lua。[进度与副本会话权威合同](../authority/tianting-progression-and-instance-authority-contract.json) 只冻结未来权威玩法逻辑必须接手的语义边界，不能由 UI、本地时间或临时脚本绕过。

## 必须先有的权威合同

| 域 | 未来逻辑必须保证 | 本包未提供 |
|---|---|---|
| 天庭章节 | 权威端逐人确认达到 Lv41 与同角色 `TT_SPEC_CHAPTER_ENTRY_HANDOFF_PROOF`（源自 `DF_E_YANLUO_HALL` 成功），依序写入 `TT_SPEC_PROGRESS_CHAPTER_ENTERED`、`TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN`、`TT_SPEC_PROGRESS_MAINLINE_CLEARED`；不消费或写入 `DF_PROGRESS_YANLUO_HALL_CLEARED`。 | 真实键、证明签发/验签、存储、写入者服务和网络事件。 |
| 主线终局 | `TT_SPEC_SESSION_LINGXIAO_MAINLINE` 私有 1–4 人会话逐人校验入章；仅有效权威参与者可获得常规完成，队长/旁观者不能代领。 | Lua 状态机、地图、队列、进度写入与实例服务。 |
| 七星单人本 | `TT_SPEC_SESSION_SEVEN_STAR` 仅由周天观台开启者创建；使用 owner、生命周期、实例、epoch、revision、cleanup token，并在死亡、超时、断线或生命周期失效后进入清理、清理前禁止重入。 | Lua 状态机、单位、技能、复活、掉落与实际锁。 |
| 星宿轮换 | `TT_SPEC_TIME_BASIS_ASIA_SHANGHAI_SHICHEN` 在首次成功创建会话时，从服务器 `Asia/Shanghai` 权威时间冻结 rotation_snapshot；整个实例都锁定方位和难度。 | 时间服务、快照存储、恢复和异常回退。 |
| 星宿普通 | 冻结 1–4 人权威成员快照，并逐人校验常规主线完成；共享七宿的双宿/双宿/双宿/单宿阶段状态。 | 波次、AI、检查点、收益和实际成员锁。 |
| 星宿噩梦 | 每位成员各自持有并由权威端解析 `TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL` 同方位资格；七宿向四圣施加宿曜贡辉，四圣向七宿施加圣兽庇护；每条共鸣链只能由权威逻辑转为净宿一次。 | 凭证物品/消耗、Buff ID、数值、持续时间、效果实现。 |
| 死亡与断线 | 团队成员死亡后回当前篇章初始出生点并锁至清理确认；断线成员为 `left`，不得重连或领奖，其他 `active` 成员可以继续。 | 出生点、复活流程、断线检测、锁和奖励实现。 |
| economy-v2 输入交接 | `TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 必须从同一完成 receipt/proof 和冻结会话快照原子导出 actor/生命周期/成功事件、route/实例/epoch/revision、成员状态与轮换；成功事实可保留但不能调用 materializer。 | source_profile、slot、owner、资格 ID、roll、保底、经济实例 ID、收据和一切奖励数值。 |
| 奖励 | 资格、所有者、实例、事件、幂等收据和资源表版本。 | 实际材料、钥匙、称号、法宝、数值和发奖。 |
| 通天塔 | 未来只可把七星/星宿作为内容池；不可把它们塞入现有五节拍状态键。 | 全局 run、楼层、抽取、掉落和赛季。 |

## 时辰快照最低语义

~~~text
authority_time(Asia/Shanghai) -> rotation_snapshot
rotation_snapshot = {
  rotation_snapshot_id, schedule_version, authoritative_time_slot, quadrant,
  difficulty, instance_scope, authority_time_basis_id,
  captured_authoritative_instant, schema_version
}
first successful session creation -> snapshot immutable
client clock / client quadrant / retry recomputation -> prohibited
reconnect is not allowed after leave; a surviving session reads its existing snapshot
~~~

上面是合同语义，不是实际字段、Lua 类型或网络协议。

## 幂等重点

1. 同一角色事件对 `(actor_id, event_id)` 的三段逻辑进度重放，只返回既有结果，不能重复写入；收据语义必须包含 actor、生命周期、生产者、会话、completed tick、authority proof 与 schema 版本。
2. 同一入场请求只能返回同一个权威方位快照，不能跨时辰重掷；普通完成方位、角色资格凭证方位和噩梦快照方位必须逐人一致。
3. 同一星链的净宿请求重复到达时，只返回既有状态，不能重复削弱 Boss 或重复产生奖励资格。
4. 失败、退出或生命周期失效必须转为 `cleanup_pending`；只有匹配实例身份、`session_epoch`、`revision` 与 cleanup token 的权威确认可关闭会话。已确认的正常完成不因后续清理确认失败而回滚。

## 明确不做

- 不在本交接件写 Lua、Y3 API、对象 ID、技能 ID、Buff ID、伤害、冷却、概率、掉落、地图路径或持久化键。
- 不以客户端本地时间、UI 缓存或队长单方面状态决定轮换。
- 不把 `session_instance_id`、`raid_instance_id`、噩梦入场凭证或 cleanup 成功直接转换为 economy-v2 的经济实例、奖励资格或结算请求；未获批 source profile 时所有经济字段必须保持 `null/deferred`。
- 不创建真实进度键、跨章证明、资格凭证、收据、会话锁、时间服务或奖励；合同中的 `TT_SPEC_*` 与 `null/deferred` 不能被当作可运行资产。
- 不新增 tower_mode、通天塔奖励模式或第二套爬塔记录。
