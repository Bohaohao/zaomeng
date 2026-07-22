# 天庭篇主线、遭遇与通天塔规格包

## 状态

offline-design-spec / content-expanded / authority-contract-specified / economy-v2-input-handoff-specified / independent-review-approved / archived / production-gate-closed

本包已从“边界已冻结、内容待定”扩展为可复审的纯离线内容规格：

- 天庭主线：临时天庭 → 南天门 → 天宫道 → 天王殿外缘 → 周天观台 → 凌霄外庭常规收束。
- 单人本：固定七星系列，天枢至瑶光各有机制、残片、星君称号和展示方向。
- 团队本：二十八星宿按十二时辰四象轮换；普通教学七宿，噩梦由四圣兽与七宿双向加成构成版本终局。
- 长期复用：七星与二十八星宿仅登记为唯一全局通天塔的未来小 Boss 内容池。
- 权威边界：入章、三段逻辑进度、主线终局、七星/星宿会话、时辰快照和噩梦逐人资格均已有纯离线合同语义。
- 经济交接：天庭完成/会话事实可作为 economy-v2 的未来权威收据**输入候选**；当前只冻结字段映射、资格快照、重放、断线和清理边界，所有 profile、slot、资格 ID 与奖励值均为 `null/deferred`。

它不创建真实地图、Y3 对象、Lua、UI、物品、奖励、账本、实际进度键、时间服务或多人运行时。合同中的 `TT_SPEC_*` 仅是逻辑身份；所有运行时键、服务、存储和发奖仍为空或延期。

本阶段的归档结论、复审与验收证据见[天庭篇主线、遭遇、副本与权威合同归档](../../归档/物编施工/06-天庭篇主线遭遇副本与权威合同归档.md)。

后续 economy-v2 零价值收据输入交接的复审与归档见[economy-v2 权威结算内核与天庭收据输入交接归档](../../归档/物编施工/07-economy-v2权威结算内核与天庭收据输入交接归档.md)；它不改变本包的生产门禁。

## 本轮用户定向规则

| 范围 | 已明确内容 | 仍不在本包冻结 |
|---|---|---|
| 入章与三段进度 | 权威端确认达到 Lv41，并验证同角色、源自 `DF_E_YANLUO_HALL` 成功事件的 `TT_SPEC_CHAPTER_ENTRY_HANDOFF_PROOF`；依次形成 `TT_SPEC_PROGRESS_CHAPTER_ENTERED`、`TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN`、`TT_SPEC_PROGRESS_MAINLINE_CLEARED` 三段逻辑进度。 | 实际进度键、证明签发/验签服务、存储、网络协议与运行时写入。 |
| 主线终局 | 凌霄外庭·裂律观台使用私有 1–4 人会话；入场成员逐人校验已入章，只有权威确认的有效参与者获得常规完成。 | 真实实例、队列、地图、脚本与任何进度发放。 |
| 七星单人本 | 天枢、天璇、天玑、天权、玉衡、开阳、瑶光；每星对应残片、星君称号和独立机制。 | 实际副本、掉落、Boss 数值、对象与技能。 |
| 七星称号 | 同一种残片累计十枚合成对应星君称号；集齐七称号自动解锁名称待定的集合称号。 | 数值、属性作用域、持久化与真实 title ID。 |
| 毕业法宝 | 七种残片均齐备，加上珍贵材料候选，合成名称待定的天庭毕业法宝。 | 最终名称、配方数量、属性、是否强制团本材料。 |
| 七星与团队会话 | `TT_SPEC_SESSION_SEVEN_STAR`、`TT_SPEC_SESSION_MANSION_NORMAL` 与 `TT_SPEC_SESSION_MANSION_NIGHTMARE` 固定身份、版本、成员快照、失败、清理与幂等语义；死亡、超时、断线或生命周期失效进入清理，确认前不可重入。 | 真实会话服务、锁、复活、断线恢复或状态机实现。 |
| 二十八星宿 | 四象各七宿；`TT_SPEC_TIME_BASIS_ASIA_SHANGHAI_SHICHEN` 按服务器 `Asia/Shanghai` 时辰四槽循环三次，首次成功创建会话时冻结不可变轮换快照。 | 权威时间服务、时辰边界计算、快照存储与实例实现。 |
| 团本普通/噩梦 | 普通和噩梦均逐人要求天庭常规主线完成；噩梦还逐人验证 `TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL` 的同方位不透明资格，且普通完成、凭证和本次噩梦快照三方位必须相同。 | 钥匙形态、消耗、奖励、Buff 数值和收据。 |
| economy-v2 收据输入交接 | `TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 将同一完成收据/proof 与会话 route、instance、epoch、revision、成员快照/状态和星宿轮换原子绑定；这些事实才可进入零价值输入候选，且原始 session/raid ID 不可直接成为经济实例身份。 | `source_profile`、`reward_slot_key`、owner、资格/roll/保底、经济收据、材料、货币、XP 与全部实际奖励。 |
| 通天塔 | 七星/星宿未来可作小 Boss；每三或五层待选，每十层大 Boss 只登记接口。 | 总层数、层位、抽取、掉落、词缀、赛季、记录。 |

## 不可突破的约束

- 天庭精确覆盖 Lv41–60，首发上限 Lv60。
- 通天塔 Lv55 逐人准入，每五层休整；玲珑只属于唯一全局通天塔。
- 天庭不得读取、写入或注册为 `DF_PROGRESS_YANLUO_HALL_CLEARED` 的消费者；入章只验证同角色的 `DF_E_YANLUO_HALL` 成功交接证明。
- 三段角色逻辑进度以 `(actor_id, event_id)` 幂等；其语义收据包含 actor、生命周期、事件、唯一生产者、会话身份、完成时刻、权威证明与 schema 版本，但不创建真实账本。
- 首发最多四人；主线终局、七星和星宿会话的离线权威语义均已冻结，实际运行时由未来权威逻辑接入。会话状态只能从 `active` 经 `cleanup_pending` 到 `closed`，只有匹配实例身份、`session_epoch`、`revision` 与清理令牌的权威确认才可释放锁。
- 星宿快照固定使用服务器 `Asia/Shanghai` 自然时辰；客户端时钟、客户端方位和重试重新抽宿均不得参与决定。死亡成员回当前篇章初始出生点并锁至清理确认；断线成员标记为 `left`，不得重连或领奖。
- economy-v2 只能作为运行时关闭的设计引用；本包不新增 MAT_、CUR_、tower_mode 或任何现有资源表值。
- [天庭完成/会话 → economy-v2 权威收据输入合同](../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json) 不可调用结算内核：`TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 必须把同一完成 receipt/proof、冻结会话 route/instance/epoch/revision、成员快照/状态和星宿轮换原子绑定。主线成功在 cleanup 后仍可保留来源事实，但不能因此产生经济收据；失败、`left`、旁观、伪造成员、旧生命周期、字段漂移和错误 cleanup 确认均不得形成资格或结算输入。
- “十枚同星残片合成称号”是用户明确的离线配方倍率，不是掉落数量或已接入的资源配方。

## 主要工件

| 工件 | 用途 |
|---|---|
| [tianting-mainline-tower-contract.json](tianting-mainline-tower-contract.json) | 原有冻结边界与天庭内容选择的领域事实源。 |
| [tianting-content-expansion-contract.json](tianting-content-expansion-contract.json) | 七星、星宿轮换、噩梦四圣、奖励候选与塔复用的机器可读内容合同。 |
| [authority/tianting-progression-and-instance-authority-contract.json](authority/tianting-progression-and-instance-authority-contract.json) | 入章、三段逻辑进度、主线终局、会话生命周期、时辰快照与噩梦资格的权威合同；纯离线、不可直接投产。 |
| [economy-v2 天庭权威收据输入合同](../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json) | 天庭完成/会话事实到未来 economy-v2 收据输入候选的唯一交接件；字段映射和资格边界已冻结，所有经济值仍为 `null/deferred`。 |
| [mainline-route.md](mainline-route.md) | 主线因果弧、公共遭遇和副本职责关系。 |
| [instances/七星单人本规格.md](instances/七星单人本规格.md) | 七个单人试炼、称号、毕业法宝和学习闭环。 |
| [instances/二十八星宿团队本规格.md](instances/二十八星宿团队本规格.md) | 十二时辰轮换、二十八星官签名动作、普通/噩梦与四圣称号。 |
| [encounters/天庭公共遭遇规格.md](encounters/天庭公共遭遇规格.md) | 公共路线遭遇骨架、可读性与施工前验收。 |
| [economy-candidates/天庭奖励候选登记.md](economy-candidates/天庭奖励候选登记.md) | 仅奖励类别、称号防叠加与经济接入前置。 |
| [tower/天庭Boss复用接口.md](tower/天庭Boss复用接口.md) | 全局通天塔的未来内容池接口，不定义塔运行或掉落。 |
| [references/西游记与造梦参考.md](references/西游记与造梦参考.md) | 文学/视觉灵感的使用边界与来源。 |
| [acceptance-matrix.md](acceptance-matrix.md) | 规格、生产门禁和下游施工的验收矩阵。 |
| [validate-tianting-tower-spec.ps1](validate-tianting-tower-spec.ps1) | 校验既有硬边界、新内容合同、轮换完整性、双向噩梦关系与负例。 |

## 内容关系

~~~mermaid
flowchart LR
  H["DF_E_YANLUO_HALL 成功交接证明"] --> I["天门入章：角色级逻辑进度"]
  I --> A["朝会殿·周天观台开启"]
  A --> B["七星：单人长期收集"]
  A --> C["常规主线：凌霄外庭收束"]
  C --> D["二十八星宿普通"]
  D --> E["逐人同方位资格凭证候选"]
  E --> F["噩梦四圣兽：三方位匹配"]
  B -. "未来小 Boss 池" .-> G["唯一全局通天塔"]
  D -. "未来小 Boss 池" .-> G
~~~

## 运行校验

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\天庭篇主线遭遇与通天塔规格包\validate-tianting-tower-spec.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\validate-design-spec.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\design-spec.json
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\score-spec-completeness.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\design-spec.json
~~~

通过仅表示离线设计可被后续专项接手；不代表任何副本、Boss、材料、称号、地图、同步或结算已经实现。
