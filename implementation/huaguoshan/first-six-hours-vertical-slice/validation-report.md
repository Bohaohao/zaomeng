# 花果山首 6 小时垂直切片：验证报告

验证日期：2026-07-21

## 结果

```text
PASS: Huaguoshan first-six-hours offline vertical-slice contract passed 284 checks.
PASS: 81 tide trace growth bridge assertions
PASS: Huaguoshan offline API isolation check passed.
PASS: Huaguoshan first-six-hours vertical slice offline bridge.
```

总回归还确认：

```text
PASS: first-six-hours offline package validation (51 checks)
PASS: 155 growth runtime assertions
PASS: first-six-hours growth offline environment.
```

## 已覆盖的链路

1. 既有地图绑定合同解析潮痕的三个资源，并启动受信任的公共潮痕状态机。
2. 权威提供者证明读取完成，状态机直接发出包含事件、角色、生命周期、动作令牌、完成时刻、证明引用和来源指纹的 canonical `trace_action_completed`。
3. 桥接层消费该 canonical 证据，并在调用注入的成长结算运行时前校验其仍是“未采纳离线候选、运行时交接关闭、生产门关闭”的成长包；随后校验证据、请求/证据版本、`owner_id == evidence.actor_id`、实例身份、资格快照和资源表版本。
4. 首次结算返回不含奖励明细的账本收据；同一幂等请求返回 `duplicate_replayed`。
5. 换用新幂等键重放同一潮痕、跨角色结算、内联奖励字段、未知资源表版本、非候选成长运行时和伪造动作令牌都会被拒绝，且不会改写成长账本。
6. 结算后，既有潮痕仍完成 30 秒余波清理和生命周期关闭；关闭不会影响已存在的结算收据。

## 仍不代表生产完成

该结果只证明受信任 Node/Fengari 离线边界内的合同与状态机可以协作。它不证明真实 Y3 地图、对象、持久化收据、在线交易、多端同步、断线恢复或生产经济已经实现。`f6h-v1` 仍是未采纳的离线候选模拟，生产门保持关闭。
