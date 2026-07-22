# 成长数值与经济裁决包验证记录

验证日期：2026-07-21。

> 2026-07-22 追加了独立的 `economy-v2` 权威结算内核纯离线验收；本页保留 7 月 21 日设计表验证记录，新增验收的详细证据见 [implementation/economy-v2-authoritative-settlement/validation-report.md](../../../implementation/economy-v2-authoritative-settlement/validation-report.md)。

> 同日复审修订已补齐外部 Tide Trace fixture 可信闭包、保留原型 map key/塔周桶/XP fail-closed、Tide evidence attestation，并建立[天庭零价值权威收据输入交接](../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json)。它没有分配任何天庭奖励值。

## 结果

| 检查 | 结果 | 说明 |
|---|---|---|
| 包内 JSON 解析 | 通过 | `economy-v1` 历史表、`economy-v2` 当前表、标定候选与生成交接简报的核心 JSON 均可解析。 |
| Node 严格 JSON 消费 | 通过 | 经济、地府与天庭六份生成 handoff JSON 已统一为 UTF-8 无 BOM，并通过 `JSON.parse(fs.readFileSync(path, 'utf8'))`。 |
| 自定义语义校验 | 通过 | 24 个决策、`economy-v1` 历史 6 项与 `economy-v2` 当前 6 项 accepted-baseline、3 种角色货币、3 种材料、21 个 HG_DROP profile、2 条保底池和 4 个历史标定场景均通过；候选仍未进入 runtime_handoff。 |
| 已采纳表完整性 | 通过 | 校验器复算 Lv1-Lv60 经验锚点、花果山 9,485 XP、10,000bp 来源预算、奖励包、P1/团队资格绑定、塔首轮奖励/资格快照/周桶封顶、XP 来源投影、保底 roll 状态机、proof-to-owner 与终态收据矩阵，并锁定 v1/v2 SHA-256 链。 |
| 标定候选负例 | 通过 | 临时写入非空 effective_value 与伪造的白盒来源 SHA-256，校验器分别拒绝并报告 calibration_effective_value_forbidden、calibration_source_hash_mismatch。 |
| 标定候选安全负例 | 通过 | 临时注入改名经济字段、未知嵌套载荷、字符串/空值布尔门禁、空来源引用、无关快照和未绑定白盒来源；校验器分别拒绝候选输出、封闭字段结构、布尔类型、来源哈希链和场景快照绑定绕过。 |
| Y3 规格结构校验 | 通过 | 仅保留预期的 targetDurationMinutes 缺失警告。 |
| 规格完整性评分 | 100/100 ready | 表示规格结构完整；`economy-v2` 是当前已采纳设计基线，`economy-v1` 为历史冻结表，生产运行时仍未获批。 |
| 交接包生成 | 通过 | 已生成 object-config、terrain-layout、Lua、UI 与 review 五类简报。 |

## 已验证的安全边界

- 非 accepted-baseline 决策和全部标定候选的 effective_value 均为 null，runtime_handoff 均为 false。
- `P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION` 是唯一公共参与箱规则，也是三条公共 profile 的唯一基础包结算路径；公共首通与稀有必须绑定同事件已提交参与箱收据，团队稀有明确不继承该前置。
- 21 个花果山 HG_DROP profile、两条角色保底池与重复转化由 `economy-v2` 冻结；旧 manifest 和 `implementation/growth/` 仍为 deferred/candidate。
- 表中没有 Y3 object ID；白盒输入和候选货币/掉率不被伪装为生产数据。余额/堆叠封顶、塔周桶和跨版本来源冲突都有零奖励或终态冲突边界；零奖励不会推进保底或消耗首通。
- 角色归属、资源表、XP 来源/倍率/实发投影、奖励计划、收据、保底 roll、塔资格快照、周额度和前进迁移已冻结为设计契约；收据只能由权威 `(actor_id, lifecycle_id, authority_proof_ref)` 解析稳定 owner，且仅持久化终态。未来事务必须先锁定身份/额度再结算；持久化载体、证明解析和运行时事务仍未实现。
- 标定候选的来源、快照、假设和场景引用均可解析；每个来源文件和白盒 manifest 的 SHA-256 已锁定，漂移会阻断校验。
- 四个标定场景均声明 JSON Boolean 的 non_production=true、effective_value=null、runtime_handoff=false；其 candidate_value 的全部字段、经验、货币、材料、概率和保底输出仍为空。
- 使用白盒输入的场景必须绑定同一 source_id 的来源快照；空、失效、重复或未绑定的来源/快照引用均会失败。
- 候选根、来源、快照、假设、场景、范围、模型选项、观测摘要和候选输出均采用封闭字段结构；任何未声明字段都会失败。
- `implementation/growth/` 被显式登记为 `offline_candidate_simulation_not_adopted`：只能在受信任 Node/Fengari 离线测试边界执行，`runtime_handoff=false`，且被禁止作为 Y3、生产账本、生产经济基线或天庭资源表的消费者输入。

## 未解除的门禁

本包没有解除生产门禁。尤其不能据此启用 `implementation/growth/` 中的候选模拟作为 `economy-v2` 运行时结算、生产账本、物编、UI、真实掉落表或商业字段。精确编译/哈希绑定与 proof-to-owner/origin binding 已在纯离线参考中验收；下一门禁是将其移交到真实权威持久化账本、proof/snapshot/roll 服务、跨进程锁、迁移与重连对账，并补地府/天庭 `source_profile` 分配及 30/60/90 分钟实测；标定候选仍只能用于采样与审阅。

## 2026-07-22：权威结算内核纯离线验收

| 检查 | 结果 | 说明 |
|---|---|---|
| 独立编译门 | 通过 | 只接受 `economy-v2` 原表的精确 UTF-8 字节、冻结 SHA、关闭门禁；篡改 baseline 不可进入结算。 |
| 七类结算事件 | 通过 | XP、普通/团队掉落、P1、首通、公共/团队稀有保底与塔奖励都由冻结表派生。 |
| 权威与幂等 | 通过 | proof-to-owner、profile/event 绑定、同 origin 换主拒绝、终态重放、跨重启恢复与冲突路径均有离线回归。 |
| 收据和快照 | 通过 | 终态收据条件字段、P1/团队/塔快照、roll 的 pity/分支、首通已消耗及恢复状态注入负例均被覆盖。 |
| 受信任执行边界 | 通过 | Node/Fengari、环境变量、PATH、固定闭包、`-E` 与 Lua/Y3 API 隔离回归通过。 |
| 复审修订 | 通过 | 外部 fixture 闭包、保留 map key、塔周桶、无效 XP、Tide attestation 与 Lua/Node 标识符边界回归通过。 |
| 天庭零价值输入交接 | 通过 | `TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 原子绑定完成 receipt/proof、会话 revision、成员/轮换快照；资格快照、重放、断线与 cleanup 边界通过，所有经济字段保持 `null/deferred`。 |

这项结果仅将状态推进为 `offline-acceptance-passed`，不改变 `runtime_handoff=false` 与 `production_gate=closed`。生产账本、真实证明服务、跨进程并发/重连、Y3 接入和地府/天庭新来源分配仍必须另行施工和复审。
