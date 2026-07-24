# 二十八星宿与四圣机制编排离线包

## 状态

- `package_status`: `offline-encounter-choreography-spec`
- `production_gate`: `closed`
- `runtime_handoff`: `false`

本包把已完成的二十八星官签名机制、四象普通团本结构与四圣噩梦共鸣，细化为可施工拆解的**遭遇语义编排**。它描述读线、提交、反制、可见结果、恢复、跨段保留与一至四人降级，不产生 Lua、Y3 对象或真实运行时状态机。

## 权威边界

现有会话合同继续唯一拥有准入、冻结成员、上海时辰快照、`left`、死亡、完成、清理、重入、幂等与经济隔离。本包只能在已确认的 `active` 会话内消费这些只读事实。

- `phase_id`、`revision`、`cleanup_token` 不是战斗阶段字段；其中 `cleanup_token` 不得进入任何机制动作输入。
- 新增的 `TT_SPEC_MANSION_ENCOUNTER_*` 只是离线语义身份，不是运行时 ID、事件名、计时器或存档键。
- 一次遭遇转场未来必须绑定冻结的 raid/boss/epoch/phase/revision、轮换快照、方位、难度，以及每名参与者的 `actor_id` / `actor_lifecycle_id` / `membership_snapshot_id` / `member_status` 权威元组；客户端、UI、本地时钟、伤害飘字和本地计时不能推进它。
- 普通与噩梦都只可形成“遭遇终局事实候选”：普通严格走完四段 `2+2+2+1`，噩梦严格走完同方位四链、净宿和核心回正；语义恢复不能跳段、倒退或重建候选。实际会话完成、资格、奖励、收据和 economy-v2 输入仍由既有权威合同决定，当前保持 `null/deferred`。

## 主要工件

| 工件 | 用途 |
|---|---|
| [机制编排规格](天庭二十八星官与四圣机制编排规格.md) | 人类可读的普通四段、二十八张星官编排卡、四圣七链与恢复规则。 |
| [机器合同](tianting-mansion-encounter-orchestration-contract.json) | 来源映射、状态语法、并发预算、成员变化、四象链序和验收的唯一机器事实源。 |
| [包内校验](tests/run-all.ps1) | 校验 28 星官覆盖、四段结构、四圣七链、身份绑定、重放、恢复及全空运行时边界。 |

## 明确不做

- 不改写既有团本会话参考模型，也不把它的离线 `recordCompletion` 入口误当作真实施工接口。
- 不定义计时、伤害、HP、冷却、仇恨、波次、对象/技能/Buff/投射物、地图碰撞、UI 节点或资源。
- 不写入进度、资格、夜巡钥、称号、材料、奖励、收据或任何经济字段。

## 验证

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\天庭篇主线遭遇与通天塔规格包\mansion-orchestration\tests\run-all.ps1
```

通过只表示离线编排能拒绝越权或缺失映射；不表示二十八星宿或四圣已在 Y3 中可玩。
