# economy-v2 权威结算内核：纯离线验收包

## 状态与边界

- `package_status`: `offline-acceptance-reference-only`
- `runtime_handoff`: `false`
- `production_gate`: `closed`
- 冻结输入：`docs/物编/成长数值与经济裁决包/tables/economy-v2-resource-table.json` 的不可变文件字节，以及由 `implementation/huaguoshan/lua/huaguoshan_public_trace.lua` 产生、受 [外部 fixture 闭包清单](contract/tide-trace-fixture-closure.json) 精确哈希约束的 canonical Tide Trace 完成证据。
- 归档：本轮复审、交接和未解除门禁见 [economy-v2 权威结算内核与天庭收据输入交接归档](../../docs/归档/物编施工/07-economy-v2权威结算内核与天庭收据输入交接归档.md)。

本目录是一个**纯离线验收参考包**。它用于证明以后实现的编译、权威证明适配、结算计划、终态收据、重放与状态恢复是否遵守 `economy-v2` 的冻结合同；它不把冻结表升级为运行时实现。

它不是：

- Y3 运行时、地图脚本根、物编或地图内容；
- 服务端持久化账本、真实权威证明服务、在线迁移或断线恢复服务；
- `implementation/growth/` 的 f6h-v1 历史离线夹具的替代品或晋升路径；
- 地府、天庭的新增经验来源、遭遇、掉落或数值内容。

除冻结的 `economy-v2` 原表和 canonical Tide Trace evidence 外，验收包不接受客户端、UI、地图对象或手填奖励作为结算依据。离线测试中可以使用确定性的假权威提供者，但它只模拟证明解析接口，不能充当新的证据来源或生产证明。

## 冻结的收据合同

每个可持久化结算的语义去重身份固定为以下六元组：

```text
(owner_scope, owner_id, encounter_instance_id, event_id, source_profile, reward_slot_key)
```

`owner_id` 只能由 `(actor_id, lifecycle_id, authority_proof_ref)` 经权威提供者解析得到；客户端传入的 owner、原始 actor 或 lifecycle 均不能替代它。

`resource_table_version` **不属于**六元语义身份，但必须进入不可变 fingerprint。相同六元身份在不同表版本、资格快照、奖励计划、掉落证明、保底、XP 或塔计数器输入下重放，必须产生 `receipt_identity_conflict`，绝不能重新计算或改写旧收据。

`authority_proof_ref` 是每次尝试必须验证的权威证据，但**不进入 fingerprint**。重放时，当前 proof 仍须验证为同一 `owner_id`、`event_id` 与 `encounter_instance_id`；验证成功则返回原有终态收据，不再结算。验证失败不能借由更换 proof 创建新收据或状态变更。

Tide Trace 的 resolver 还必须为完整 canonical evidence（除可轮换、逐次复验的 `authority_proof_ref`）返回 `tide_trace_attestation_ref` 与 SHA-256 canonical digest。`tide_trace_attestation_ref` 必须对同一 canonical evidence 稳定，且不得编码或随 proof 轮换；该 attestation 被绑定到离线请求与奖励计划指纹：修改 target、action、tick、来源指纹或 attestation ref 都会产生 `receipt_identity_conflict`，而独立复验通过且保持同一 attestation ref 的 proof 轮换可回放既有终态。它是离线 resolver-result 合同，不是生产证明格式。

proof resolver 还必须在其自身的可信、可持久化状态中先绑定 evidence origin：

```text
(actor_id, lifecycle_id, encounter_instance_id, event_id, source_profile, reward_slot_key)
```

它不是 object，也不允许由各实现自行排序：将上述六个已脱离并校验的值依次写成一个**无空白 UTF-8 JSON array**，再取 SHA-256 小写十六进制并加前缀 `economy-v2-origin:`。除 `lifecycle_id` 可为非负安全整数外，字段均为 `[A-Za-z0-9_.:-]+` ASCII 标识符；字符串按 JSON 转义，数字按最短十进制 JSON 数字表示；脱离阶段会把 `-0` 规范化为 `0`。固定互通向量为：

```text
["trace-actor-a",7,"economy-v2-trace-instance-1","economy-v2-trace-event-1","HG_DROP_WATERFALL_ELITE","base_bundle"]
=> economy-v2-origin:17bb857c14e4893d7076819afee3a150496a26b4d8e0b6f2840bbcea0041e463
```

resolver 必须返回同一个 `authority_origin_key` 与 `origin_owner_binding_verified=true`，并拒绝任何 owner 漂移——包括第一次结算已被拒绝的来源。Node 内存账本只能对**已提交** origin 再做一道本地后备检查；它不能替代真实 proof resolver 的跨进程持久化绑定。

持久收据只有两种终态：`committed` 和 `rejected`；`prepared` 状态、prepared 收据和 prepared 经济状态一律禁止。`rejected` 必须是零经济副作用：不得写入余额、材料、唯一物品、首通、保底、重复 XP 配额、塔周配额或 origin 状态。终态重放也不得再次改变任何经济状态。

## 已覆盖的离线事件类型

验收内核应从原表的 `award_plan_derivation_contract` 只派生下列事件类型：

1. `experience`
2. `drop_bundle`
3. `participation_chest`
4. `first_clear_grant`
5. `public_rare_drop`
6. `team_raid_rare_drop`
7. `tower_reward`

上述七类处理器已经在本包的 Node 内存参考模型中实现并由离线回归覆盖；它们仍**没有**接入 Y3、地图脚本、物编、存档或服务端。`OfflineTransactionStore` 只验证单进程内的终态、索引和 origin 一致性，绝不能被当作生产持久化账本。

提交收据前，参考模型还会同时验证：

- 编译基线的精确冻结表 SHA 与 canonical table digest；
- authority result 对 `owner_id`、actor/lifecycle、事件、实例、`source_profile` 与 `event_type` 的逐项绑定；
- actor/lifecycle/实例/事件/profile/slot 形成的 evidence origin。已提交 origin 不得因更换 proof 映射到第二个角色；
- 冻结收据合同的 required/null/条件字段与零奖励状态矩阵。无法形成合规终态收据的前置拒绝不落盘。

## 受信任恢复边界

`exportState()` 只是诊断用深拷贝，**不能**作为恢复输入。跨重启的离线参考必须使用：

```text
{ snapshot_schema_version: 1, state, state_hmac_sha256 }
```

并在包外保存至少 16 字节的 `integrity_key`；HMAC key 不得写进 snapshot、收据、环境变量或本包文件。恢复时，模型先把输入一次性脱离为普通 JSON，再校验 HMAC、双索引、计划哈希和终态状态。缺 key、裸状态、篡改内容或试图通过 getter/Proxy 在校验后换状态都会被拒绝。

这只是离线夹具的完整性边界，不提供生产密钥管理、真实迁移、跨进程锁、断线重连或灾难恢复。`migration_isolation_queue` 仅为未来迁移接口预留容器，迁移本身不在本包验收范围。

## 受信任执行文件系统边界

编译器会在检查时对每个输出父路径组件执行 `lstat/realpath`：非目录、符号链接，以及解析到包外的路径都会被拒绝，且最终输出名绝不覆盖；`run-all.ps1` 还会复核 Node 签名/版本/哈希、固定 Fengari 闭包和环境变量。但纯 Node/PowerShell 的路径 API 不能把 Windows 目录/可执行文件句柄固定到后续每次路径操作：若另一个本地主体能在检查与写入/启动之间删除、改名、替换路径或加入 reparse point，就可能绕过这种检查。

因此，本离线参考包只在下列前提下成立：单次运行期间，离线包根目录、编译输出父目录、选中的 `node.exe` 与固定 Fengari 闭包均由受信任执行主体独占；不授予其他主体 Delete/Write/rename/reparse 权限。它覆盖静态路径和环境注入负例，**不**声称对抗并发的本地 ACL 级路径替换。生产环境若需要对抗该威胁，必须另行采用经审计的原生句柄相对写入/启动器或隔离的签名服务。

归档复现还精确固定已签名 Node `v20.19.5` 的 SHA-256 与 `fengari-node-cli@0.1.0` 闭包；runner 会在每次 Fengari 执行前后复核完整外部 Tide Trace fixture 闭包，并对该闭包单独执行 API 隔离扫描。

## 天庭完成/会话输入交接

[天庭权威收据输入交接合同](contract/tianting-authority-receipt-input-contract.json) 只接收已冻结的天庭完成、成员、会话、轮换、断线与清理来源事实。`TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 必须把同一完成 receipt/proof 与 route、规范化实例、epoch、revision、成员快照/状态及星宿轮换原子绑定；调用方不能自行拼接这些字段。它目前不是结算请求：`encounter_instance_id`、`source_profile`、`reward_slot_key`、owner、资格快照 ID、roll、保底和全部奖励字段都是 `null/deferred`。

主线成功在后续 cleanup 失败、延迟或重放后仍保留为天庭来源完成事实，但不会自动写经济收据；死亡、超时、断线、`left`、旁观、伪造成员、旧生命周期和错误 cleanup 确认都不能形成输入候选。未来只有在独立批准天庭 source-profile 分配后，才可从 `source_session_spec_id + source_session_instance_id + source_session_epoch` 导出不透明经济实例身份；原始 session/raid ID、会话 revision 和 cleanup token 都不能单独成为经济语义身份。

## 验收矩阵（全部必须通过）

| 编号 | 必须验证的结论 |
| --- | --- |
| AC-01 | 编译器只接受原表的精确 UTF-8 文件字节、SHA-256、`resource_table_version=economy-v2`、`runtime_handoff=false` 与 `production_gate=closed`；旧表、候选表、篡改字节或门禁漂移一律拒绝。 |
| AC-02 | Tide Trace 适配器只消费 canonical `trace_action_completed` evidence；真实离线 Trace fixture 的固定输出会与独立 canonical evidence 对照，并在写入前解析 `(actor_id, lifecycle_id, authority_proof_ref)` 到稳定角色 owner。 |
| AC-03 | 不接受客户端 owner、手填奖励、手填资格、手填保底或手填 XP 倍率；未映射来源、证明或快照不完整时只产生拒绝结果或无收据的前置拒绝，绝不发奖。 |
| AC-04 | 相同六元身份和相同 fingerprint 返回同一终态收据；跨重启仅接受外持密钥 HMAC 保护的快照，裸状态、篡改、索引/计划失配与 accessor 状态交换都必须拒绝。 |
| AC-05 | 同一六元身份而 fingerprint 不同（包括 `resource_table_version` 不同）返回 `receipt_identity_conflict`，且不改变既有收据或经济状态。 |
| AC-06 | proof ref 不进 fingerprint；每次重放仍重新验证当前 proof 指向同一 owner/event/instance，成功只回放原收据，失败零副作用。 |
| AC-07 | 所有事件类型的奖励计划严格来自冻结表；P1 参与箱、公会/团队快照、首通、稀有/保底、XP 重复配额与塔奖励均执行原表的绑定和空值规则。 |
| AC-08 | 余额/材料上限、塔周上限和任何原子性失败均只可产生表定义的零奖励终态；不允许部分奖励、邮件补偿、首通/保底/配额偷消耗。 |
| AC-09 | `rejected`、冲突、异常中止和重复请求不得留下奖励或进度副作用；持久状态中不得存在 `prepared`。 |
| AC-10 | 包内与精确固定的外部 Tide Trace fixture 闭包不引用 Y3、地图、物编、网络、系统时钟或真实服务；受信任 Node/Fengari 边界必须拒绝环境注入、路径漂移和闭包漂移。 |
| AC-11 | `__proto__`、`constructor`、`prototype` 等保留 map key、畸形塔周计数器、不安全 owner 和越界 XP 等级必须 fail-closed，且零经济副作用。 |
| AC-12 | Tide Trace resolver attestation 必须进入回放与奖励计划指纹；canonical evidence 漂移必须冲突，轮换但逐次复验通过的 proof 可回放。 |
| AC-13 | 天庭完成/会话只可形成零价值权威输入候选；未独立批准 source-profile 前，不能创建 economy-v2 结算请求或经济收据。 |

实现、运行和独立复审的当前进展见 [validation-report.md](validation-report.md)；机器可读总合同见 [package-contract.json](package-contract.json)，Tide Trace 输入的精确字段集、固定值与 fail-closed 规则见 [contract/tide-trace-adapter-contract.json](contract/tide-trace-adapter-contract.json)，外部 fixture 可信闭包见 [contract/tide-trace-fixture-closure.json](contract/tide-trace-fixture-closure.json)，天庭零价值输入边界见 [contract/tianting-authority-receipt-input-contract.json](contract/tianting-authority-receipt-input-contract.json)。
