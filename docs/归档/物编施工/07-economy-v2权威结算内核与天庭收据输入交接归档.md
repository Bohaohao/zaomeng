# economy-v2 权威结算内核与天庭收据输入交接归档

## 归档状态

```text
offline-acceptance-reference-only / independently-reviewed / archived / runtime-handoff-false / production-gate-closed
```

- 归档日期：`2026-07-22`。
- 范围：`economy-v2` 冻结资源表的纯离线编译/结算参考、Tide Trace 外部 fixture 可信闭包、终态收据/回放/恢复边界，以及天庭完成与会话到未来 economy-v2 权威收据输入的零价值交接。
- 当前详细来源以 [economy-v2 验收包](../../../implementation/economy-v2-authoritative-settlement/README.md)、[机器可读总合同](../../../implementation/economy-v2-authoritative-settlement/package-contract.json)、[天庭输入交接合同](../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json)、[天庭权威合同](../../物编/天庭篇主线遭遇与通天塔规格包/authority/tianting-progression-and-instance-authority-contract.json) 与各自验证记录为准；本页只保留本轮复审闭环、验收证据和未关闭门禁。

## 已归档的结论

- `economy-v2` 仍是运行时关闭的冻结设计基线。参考模型只验证七类既有结算事件的表驱动计划、终态收据、幂等、冲突、HMAC 保护离线恢复与零副作用拒绝；它不是生产账本、证明服务、Y3 Lua 或多人服务。
- Tide Trace 的真实外部 Lua/fixture 执行链现在由[闭包清单](../../../implementation/economy-v2-authoritative-settlement/contract/tide-trace-fixture-closure.json)固定路径、realpath 与 SHA-256，并在 Fengari 执行前后复验；隔离检查在受控 scratch root 对实际闭包执行。归档还固定已签名 Node `v20.19.5` 字节哈希与 Fengari 闭包。
- 结算参考拒绝 `__proto__`、`constructor`、`prototype` 等保留 map key，拒绝畸形塔周计数器、不安全 owner 与越界 XP 等级；这类输入不能创建收据或经济状态变化。
- Tide Trace resolver 必须对完整 canonical evidence 产生 attestation digest。相同 evidence 的 `tide_trace_attestation_ref` 必须稳定且不随 `authority_proof_ref` 轮换；稳定 ref 的有效 proof 轮换可回放，evidence 或 attestation ref 漂移则冲突且零副作用。
- 天庭到 economy-v2 的交接不是结算请求。`source_profile`、`reward_slot_key`、owner、经济 `encounter_instance_id`、资格 ID、roll、保底、XP、货币、材料、物品与所有奖励值均保持 `null/deferred`。
- `TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 是天庭来源事实的唯一封套：它由未来权威 resolver 从**同一**完成 receipt/proof 与冻结会话快照原子绑定 actor、生命周期、事件、route、规范化实例、epoch、revision、成员快照/状态；星宿还绑定 rotation snapshot、quadrant、difficulty。调用方不能拼接或替换其中字段。
- 同一 `(actor_id, event_id)` 的来源重放只能返回同一封套；route、实例、epoch、revision、成员快照/状态或星宿轮换任何漂移均被拒绝。成功完成不会因后续 cleanup 失败回滚为来源事实，但 cleanup 不能自动创造资格、经济收据或奖励；`left`、失败、旁观、未冻结、伪造与旧生命周期成员不能形成候选。
- 未来经济实例只能由 `source_session_spec_id + source_session_instance_id + source_session_epoch` 三个冻结字段共同派生；裸 `session_instance_id`、`raid_instance_id`、revision 或 cleanup token 不得成为经济语义身份。

## 复审与验证证据

| 验证 | 结果 |
|---|---|
| economy-v2 全量离线验收 | `tests/run-all.ps1` 通过：`225` 条 settlement、`395` 条天庭交接、`83` 条 Tide Trace Lua adapter 断言；包外 Tide fixture 闭包校验另计 `186` 条断言。 |
| TianTing 权威合同校验 | `validate-tianting-tower-spec.ps1` 通过：`VALIDATION PASSED: 1887 checks`。 |
| 设计规格结构与完整度 | `validate-design-spec.ps1` 为 `ok: true`、无 errors；`score-spec-completeness.ps1` 为 `100/100 ready`。预期保留 `targetDurationMinutes` 未裁定提示与 6 项生产 unresolved。 |
| 文本/差异质量 | JSON 严格解析与 `git diff --check` 通过。 |
| 独立安全复审 | 首轮 P1（外部 fixture 闭包、原型键/塔周桶）与 P2（XP、Tide attestation、标识符/Node pin）均已修复；复审结论 `APPROVE`，P0/P1 为 `0`。 |
| 独立交接复审 | 首轮 P1（来源 receipt/proof 与 revision/成员/轮换快照未原子闭合）和 P2（schema/路由集合不封闭、裸实例措辞）均已修复；最终 `APPROVE`，P0/P1/P2 为 `0`。 |

## 未关闭门禁

- 未创建真实 authority proof、来源 evidence resolver、资格快照、source-profile、slot、owner/origin、roll、保底、经济实例、持久化经济收据或任何奖励分配。
- 未建设生产持久化账本、跨进程锁、密钥管理、迁移/保留期、断线重连对账、审计与可观测性；Node 内存模型、Fengari 与 HMAC 夹具不能代替它们。
- 未创建 Y3 地图、对象、Lua 运行时、UI、网络协议、时间服务、存档、物编资源或多人实机场景。
- 七星、二十八星宿、四圣、天庭称号与材料仍只是离线内容/资格候选；本归档没有授权它们继承花果山 profile 或创建新的经济数值。

## 后续方向

下一阶段应先单独裁决地府与天庭的 source-profile、事件类型、slot、资格与数值分配，再将已冻结边界移交为独立受审计的生产架构：证明/快照/roll 服务、持久化账本、跨进程锁、重连对账和 Y3 会话接入都需各自施工与复审。在获得这些明确授权前，本归档只能作为离线合同和验收依据。
