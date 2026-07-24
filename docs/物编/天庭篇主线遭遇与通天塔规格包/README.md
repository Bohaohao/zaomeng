# 天庭篇主线、遭遇与通天塔规格包

## 状态

offline-design-spec / content-expanded / authority-contract-specified / authority-vertical-slice-offline-tested / seven-star-session-reference-offline-tested / mansion-session-reference-offline-tested / mansion-encounter-choreography-specified / mainline-narrative-presentation-specified / combat-readability-specified / combat-numeric-unit-baseline-specified / cross-profession-calibration-protocol-specified / enemy-ecology-specified / mainline-boss-deepened / map-scale-aligned / terrain-layout-dry-run-specified / ui-information-specified / object-art-vfx-blueprint-specified / y3-construction-preflight-specified / surface-construction-discovery-specified / tower-economy-full-run-candidate-pending-global-adoption / economy-v2-input-handoff-specified / production-gate-closed

本包已从“边界已冻结、内容待定”扩展为可复审的纯离线内容规格：

- 天庭主线：临时天庭 → 南天门 → 天宫道 → 天王殿外缘 → 周天观台 → 凌霄外庭常规收束。
- 单人本：固定七星系列，天枢至瑶光各有机制、残片、星君称号和展示方向。
- 团队本：二十八星宿按十二时辰四象轮换；普通教学七宿，噩梦由四圣兽与七宿双向加成构成版本终局。
- 长期复用：七星与二十八星宿进入唯一全局通天塔的小 Boss 内容池；四十层、八段五拍、每五层 Boss 槽与每十层大 Boss 是待上位全局塔合同采纳的天庭侧离线候选。
- 权威边界：入章、三段逻辑进度、主线终局、七星/星宿会话、时辰快照和噩梦逐人资格均已有纯离线合同语义。
- 战斗可读性：主线、七星、四方七宿与四圣噩梦已补齐“预警 → 决策 → 反制 → 可复盘失败”的施工前机制规格，且所有机制都保留 1–4 人可完成路径。
- 星宿遭遇编排：普通四象的 `双宿 → 双宿 → 双宿 → 单宿`、28 张星官的读线/提交/反制/恢复卡，以及四圣噩梦固定 `2+2+2+1` 七链、净宿援护与核心回正均已细化；它们只消费会话权威事实，不能改写 `phase_id`、`revision` 或 `cleanup_token`。
- 战斗数值与单位基线：四职业 Lv41/45/50/55/60 裸装属性形成可核查参照；小怪、精英、主线 Boss、七星、二十八星官与四圣统一冻结为无量纲耐久、压力、节拍、P0/反制和 1–4 人缩放，原始对象字段与秒数仍等待实机标定。
- 跨职业绝对标定（P0）：`implementation/combat-calibration` 已冻结 12 个 Lv41/55/60 裸装锚点、固定构筑声明账本、D90/B10、动作/移速、场地碰撞和 1–4 人回放的证据接口；新增 [实证采集与采纳包](../../../implementation/combat-calibration/evidence-adoption/README.md) 固定“真实只读采集 → 摘要/哈希 → 独立复核 → 外部采纳 → 另行投影复审”链路。当前无可信采集方、真实工程、账本或采纳决定，七道绝对投影门禁仍为 `0/7`。
- 敌人生态：受控天兵、四门守备机关、失控云兽、泛称监星使及命令/阵眼/星历/共鸣回响均已有非塔职责、双通道预警、反制与首领身份护栏。
- 主线首领：南天门、断虹阵、四门失衡、周天观台与凌霄外庭五组首领级遭遇已细化阶段语法、失败复盘、小怪/精英接口和 1–4 人适配。
- 主线叙事与表现：五组主线 Boss 均已补齐入场引导、三段叙事锚点、双通道预警、失败复盘和 L0–L4 表现职责；它只消费未来已确认的权威事实，不裁决成功、进度或结算。
- 地图口径与白盒：`640×416` 只保留为章节关系图解；两张 `96×64` 候选公共白盒和独立会话包络共同受 `224×80` 天界带状容量约束，均不是已创建的 Y3 地图。
- UI 与无障碍：双通道预警、轮换快照、队伍状态、失败复盘及七曜/四圣称号展示已成为可验收的信息架构；UI 仍只展示权威结果。
- 物编／美术／特效：主线、七星、二十八星官与四圣的轮廓、前摇、特效层级和场地交互已形成无 ID、无数值的资产需求蓝图。
- 主线纵切：`入章 → 周天观台 → 凌霄外庭` 已有独立 Node/Fengari 离线测试基座；它不是 Y3 地图脚本、真实存档或线上权威服务。
- 七星与星宿会话参考：七星 owner/观台准入、七路线、失败清理与重放，以及星宿逐人准入、上海时辰冻结、噩梦三方位、`left` 与清理边界，均已由进程内离线模型回归；它们不创建真实会话、时间、资格、进度、奖励或 economy-v2 输入。
- 施工预检与表面发现：`implementation/tianting-y3-construction-preflight` 只验证未来地图根的最小结构，当前离线仓库按预期失败关闭；地图白盒、最小 HUD 和五组主线 Boss 资产已进入无写入的发现清单，全部实际绑定仍为 `null`。
- 经济交接：天庭完成/会话事实可作为 economy-v2 的未来权威收据**输入候选**；当前只冻结字段映射、资格快照、重放、断线和清理边界，所有 profile、slot、资格 ID 与奖励值均为 `null/deferred`。
- 塔与赛季：四门校律使、九曜司衡官、镇塔监律使、玲珑塔灵是天庭侧第 10/20/30/40 层候选的无数值创意身份，须由上位全局塔合同采纳；赛季只定义权威快照语义，来源事件、掉落、资格、收据和全部值仍为 `null/deferred`。

它不创建真实地图、Y3 对象、地图根 Lua、UI、物品、奖励、账本、实际进度键、时间服务或多人运行时。`terrain-layout/layout.json` 与 `terrain-layout/scale-alignment/layout.json` 中的坐标、尺寸、区域、路径和逻辑资源候选只服务于 dry-run 布局预览，不能被当作现有地图、入口、传送、出生点、编辑器资源或运行时键。合同中的 `TT_SPEC_*` 仅是逻辑身份；独立离线 Lua 测试不改变生产门禁，所有实际运行时键、服务、存储和发奖仍为空或延期。

本轮离线施工收口、P0 外部实证接入边界、复审与验收证据见[天庭离线施工收口与 P0 外部实证接入归档](../../归档/物编施工/08-天庭离线施工收口与P0外部实证接入归档.md)；早期主线、遭遇、副本与权威合同冻结记录仍见[第 06 号归档](../../归档/物编施工/06-天庭篇主线遭遇副本与权威合同归档.md)。

二十八星官普通四段、二十八张机制卡、四圣噩梦七链、成员权威元组与只读终局候选的细化及终审证据见[天庭星宿机制编排与状态图归档](../../归档/物编施工/09-天庭星宿机制编排与状态图归档.md)；该归档不使离线语义图成为运行时状态机。

后续 economy-v2 零价值收据输入交接的复审与归档见[economy-v2 权威结算内核与天庭收据输入交接归档](../../归档/物编施工/07-economy-v2权威结算内核与天庭收据输入交接归档.md)；它不改变本包的生产门禁。

## 本轮用户定向规则

| 范围 | 已明确内容 | 仍不在本包冻结 |
|---|---|---|
| 入章与三段进度 | 权威端确认达到 Lv41，并验证同角色、源自 `DF_E_YANLUO_HALL` 成功事件的 `TT_SPEC_CHAPTER_ENTRY_HANDOFF_PROOF`；依次形成 `TT_SPEC_PROGRESS_CHAPTER_ENTERED`、`TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN`、`TT_SPEC_PROGRESS_MAINLINE_CLEARED` 三段逻辑进度。 | 实际进度键、证明签发/验签服务、存储、网络协议与运行时写入。 |
| 主线终局 | 凌霄外庭·裂律观台使用私有 1–4 人会话；入场成员逐人校验已入章，只有权威确认的有效参与者获得常规完成。 | 真实实例、队列、地图、脚本与任何进度发放。 |
| 七星单人本 | 天枢、天璇、天玑、天权、玉衡、开阳、瑶光；每星对应残片、星君称号和独立机制，并已纳入相对战斗基线。 | 实际副本、掉落、Boss 原始属性、对象与技能。 |
| 七星称号 | 同一种残片累计十枚合成对应星君称号；集齐七称号自动解锁名称待定的集合称号。 | 数值、属性作用域、持久化与真实 title ID。 |
| 毕业法宝 | 七种残片均齐备，加上珍贵材料候选，合成名称待定的天庭毕业法宝。 | 最终名称、配方数量、属性、是否强制团本材料。 |
| 七星与团队会话 | `TT_SPEC_SESSION_SEVEN_STAR`、`TT_SPEC_SESSION_MANSION_NORMAL` 与 `TT_SPEC_SESSION_MANSION_NIGHTMARE` 固定身份、版本、成员快照、失败、清理与幂等语义；死亡、超时、断线或生命周期失效进入清理，确认前不可重入。 | 真实会话服务、锁、复活、断线恢复或状态机实现。 |
| 二十八星宿 | 四象各七宿；`TT_SPEC_TIME_BASIS_ASIA_SHANGHAI_SHICHEN` 按服务器 `Asia/Shanghai` 时辰四槽循环三次，首次成功创建会话时冻结不可变轮换快照。 | 权威时间服务、时辰边界计算、快照存储与实例实现。 |
| 团本普通/噩梦 | 普通和噩梦均逐人要求天庭常规主线完成；噩梦还逐人验证 `TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL` 的同方位不透明资格，且普通完成、凭证和本次噩梦快照三方位必须相同。 | 钥匙形态、消耗、奖励、Buff 数值和收据。 |
| 星宿机制编排 | 普通本固定四段和二十八张星官编排卡；噩梦四圣固定同方位 `2+2+2+1` 链序，单读线仅一个主 P0，净宿集合只增不减。所有遭遇转场未来只绑定既有会话身份与成员/轮换快照。 | 真实遭遇状态机、权威机制事件、Y3/Lua、计时、对象、地图、同步、会话完成证明与任何结算。 |
| 战斗可读性 | 主线、七星、普通星宿与四圣噩梦均冻结预警、决策、反制、失败复盘、场地职责和 1–4 人适配；颜色不是唯一关键信息载体。 | 技能、单位、原始数值/计时、AI、实际 UI、同步和战斗运行时。 |
| 战斗数值与单位基线 | 四职业 Lv41/45/50/55/60 裸装包络、`H0/A0/M0/I0/R0/B0/O0/S0` 相对标尺、既有单位全覆盖、相对共鸣与 1–4 人缩放已冻结。 | `hp_max`、攻击/双防、移速字段、攻击间隔秒数、技能伤害、冷却、仇恨、AI、波次、对象/资源键与实机战斗运行时。 |
| 跨职业绝对标定（P0） | 12 个裸装锚点、12 份固定构筑声明、D90/B10、60Hz 设计夹具、动作/移速、碰撞与 1–4 人回放证据接口，以及独立实证采集/采纳链和 `TT_CAL_ABSOLUTE_OBJECT_FIELDS_V1` 的 fail-closed 投影已冻结。 | 受信任采集提供方、真实工程、逐门证据账本与采纳决定；泛用伤害/双防穿透、命中/暴击/控制公式，实机帧/碰撞/回放、稳定对象键；全部天庭绝对字段仍为 `null`。 |
| 敌人生态与精英 | 受控天兵、四门守备机关、失控云兽、泛称监星使和非人格机制回响已有职责、反制、失败含义与 1–4 人表达；相对数值由独立基线统一供给，首领身份不可降格复用。 | 单位/对象/技能/Buff/AI、波次/刷新、原始数值、掉落、地图、资格、进度、收据与结算。 |
| 主线 Boss 深化 | 南天门、断虹阵、四门失衡、周天观台和凌霄外庭均已有阶段预警、决策、可见反制、失败复盘与附属压力接口；相对阶段暴露与压力由独立基线供给。 | 实际 Boss 单位、技能/AI、原始数值、波次、地图、会话/进度写入、奖励、收据与结算。 |
| 地形与副本分布 | `640×416` 是图解画布，不是地形格或地图尺寸；公共内容改映射为两张 `96×64` 候选白盒，凌霄、七星、星宿普通/噩梦继续为独立会话包络。 | 实际地图键、入口/传送、地形/装饰写入、出生点、碰撞、逻辑资源 ID、资源绑定和性能验收。 |
| UI 与无障碍 | 双通道预警、轮换快照、队伍状态、失败/清理复盘和七曜/四圣称号展示均有权威来源、禁止本地裁决项和无障碍替代。 | UI 节点、资产、音效、特效、模板、事件、存档与本地状态机。 |
| 物编／美术／特效 | 主线、七星、二十八星官与四圣的 Boss 轮廓、前摇、P0–P2、L0–L4 与场地交互均已登记。 | 对象/资源 ID、单位、技能、Buff、数值、模型、动画和实际特效。 |
| 主线运行基座 | 独立纯 Lua 模型已覆盖入章、观台、凌霄成员快照、完成、幂等、清理与受信任 Node/Fengari 离线执行边界。 | 真实 Y3 API、地图脚本、存档、网络、权威证明服务或 economy-v2 调用。 |
| Y3 施工预检与表面发现 | 未来地图根 `script/y3/{meta,game}`、UI 根、对象接口标签和实时清单均有 fail-closed 预检；五组主线白盒、最小 HUD、失败复盘与 P0 资产批次已有发现项。 | 真实 Y3 工程、地图/UI/对象写入、资源 ID、Y3 API 读回、实时权威适配与绝对属性。 |
| economy-v2 收据输入交接 | `TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 将同一完成收据/proof 与会话 route、instance、epoch、revision、成员快照/状态和星宿轮换原子绑定；这些事实才可进入零价值输入候选，且原始 session/raid ID 不可直接成为经济实例身份。 | `source_profile`、`reward_slot_key`、owner、资格/roll/保底、经济收据、材料、货币、XP 与全部实际奖励。 |
| 通天塔 | 天庭侧候选为四十层、八段五拍、每五层 Boss 槽；第 10/20/30/40 层候选以大 Boss 取代小 Boss，七星/星宿按槽位交替进入内容池。 | 上位全局塔采纳、实际楼层、地图/实例、抽取、词缀、失败恢复、掉落来源、资格、收据、赛季值、记录和奖励。 |

## 不可突破的约束

- 天庭精确覆盖 Lv41–60，首发上限 Lv60。
- 通天塔 Lv55 逐人准入，每五层休整；玲珑只属于唯一全局通天塔。
- 天庭不得读取、写入或注册为 `DF_PROGRESS_YANLUO_HALL_CLEARED` 的消费者；入章只验证同角色的 `DF_E_YANLUO_HALL` 成功交接证明。
- 三段角色逻辑进度以 `(actor_id, event_id)` 幂等；其语义收据包含 actor、生命周期、事件、唯一生产者、会话身份、完成时刻、权威证明与 schema 版本，但不创建真实账本。
- 首发最多四人；主线终局、七星和星宿会话的离线权威语义均已冻结，实际运行时由未来权威逻辑接入。会话状态只能从 `active` 经 `cleanup_pending` 到 `closed`，只有匹配实例身份、`session_epoch`、`revision` 与清理令牌的权威确认才可释放锁。
- 星宿快照固定使用服务器 `Asia/Shanghai` 自然时辰；客户端时钟、客户端方位和重试重新抽宿均不得参与决定。死亡成员回当前篇章初始出生点并锁至清理确认；断线成员标记为 `left`，不得重连或领奖。
- economy-v2 只能作为运行时关闭的设计引用；本包不新增 MAT_、CUR_、tower_mode 或任何现有资源表值。
- 当前 economy-v2 的零价值来源事实候选只覆盖既有 `TT_SPEC_EVENT_LINGXIAO_OUTER_COURT_SUCCESS`；七星、普通星宿和噩梦星宿的战斗成功仍不得形成 handoff candidate、资格或结算输入。
- [天庭完成/会话 → economy-v2 权威收据输入合同](../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json) 不可调用结算内核：`TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 必须把同一完成 receipt/proof、冻结会话 route/instance/epoch/revision、成员快照/状态和星宿轮换原子绑定。主线成功在 cleanup 后仍可保留来源事实，但不能因此产生经济收据；失败、`left`、旁观、伪造成员、旧生命周期、字段漂移和错误 cleanup 确认均不得形成资格或结算输入。
- “十枚同星残片合成称号”是用户明确的离线配方倍率，不是掉落数量或已接入的资源配方。
- 四十层、八段五拍、五层 Boss 槽与四个大 Boss 只是待上位全局塔合同采纳的天庭侧离线逻辑候选；它们不创建地图、实例、记录、赛季、掉落、资格或结算。

## 主要工件

| 工件 | 用途 |
|---|---|
| [tianting-mainline-tower-contract.json](tianting-mainline-tower-contract.json) | 原有冻结边界与天庭内容选择的领域事实源。 |
| [tianting-content-expansion-contract.json](tianting-content-expansion-contract.json) | 七星、星宿轮换、噩梦四圣、奖励候选与塔复用的机器可读内容合同。 |
| [authority/tianting-progression-and-instance-authority-contract.json](authority/tianting-progression-and-instance-authority-contract.json) | 入章、三段逻辑进度、主线终局、会话生命周期、时辰快照与噩梦资格的权威合同；纯离线、不可直接投产。 |
| [七星单人会话离线参考包](../../../implementation/tianting-seven-star-session-reference/README.md) | 对 owner、观台进度、七路线、失败清理、完成保留与幂等的进程内可执行夹具；不产生掉落、称号、资格、收据或经济输入。 |
| [二十八星宿会话离线参考包](../../../implementation/tianting-mansion-session-reference/README.md) | 对注入上海时辰、逐人普通/噩梦资格、三方位、断线 `left`、清理和重放的进程内可执行夹具；不读取真实时钟或创建团本。 |
| [economy-v2 天庭权威收据输入合同](../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json) | 天庭完成/会话事实到未来 economy-v2 收据输入候选的唯一交接件；字段映射和资格边界已冻结，所有经济值仍为 `null/deferred`。 |
| [mainline-route.md](mainline-route.md) | 主线因果弧、公共遭遇和副本职责关系。 |
| [instances/七星单人本规格.md](instances/七星单人本规格.md) | 七个单人试炼、称号、毕业法宝和学习闭环。 |
| [instances/二十八星宿团队本规格.md](instances/二十八星宿团队本规格.md) | 十二时辰轮换、二十八星官签名动作、普通/噩梦与四圣称号。 |
| [mansion-orchestration/二十八星官与四圣机制编排](mansion-orchestration/README.md) | 普通严格四段 `2+2+2+1`、28 星官读线/提交/反制/恢复、权威成员元组降级、普通/噩梦只读终局候选、四圣固定七链与不可跳段/倒退的离线语义编排；不生成状态机。 |
| [combat/天庭战斗机制与可读性规格.md](combat/天庭战斗机制与可读性规格.md) | 主线、七星、普通星宿与四圣噩梦的预警、决策、反制、复盘、1–4 人适配和下游施工信息需求。 |
| [combat/tianting-combat-readability-contract.json](combat/tianting-combat-readability-contract.json) | 战斗可读性验收、经济隔离和权威边界的机器可读合同。 |
| [combat-baseline/天庭战斗数值与单位基线裁决.md](combat-baseline/天庭战斗数值与单位基线裁决.md) | 四职业裸装包络、相对单位/首领标尺、四圣共鸣与 1–4 人缩放的唯一数值裁决；不含原始物编字段。 |
| [combat-baseline/tianting-combat-numeric-unit-baseline-contract.json](combat-baseline/tianting-combat-numeric-unit-baseline-contract.json) | 数值裁决的机器合同、身份覆盖、标定门禁和验收编号。 |
| [跨职业战斗绝对标定包](../../../implementation/combat-calibration/README.md) | P0 的跨职业锚点、构筑声明、D90/B10、实机证据接口与绝对字段 fail-closed 投影；不填写天庭原始对象字段。 |
| [P0 实证采集与采纳包](../../../implementation/combat-calibration/evidence-adoption/README.md) | P0 七门的外部只读采集、哈希/不可变工件、独立复核和外部采纳模板；当前没有采集方、真实证据或采纳账本，不能自行打开门禁。 |
| [P0 受信任外部实机采集方接入前置包](../../../implementation/combat-calibration/external-capture-onboarding/README.md) | 真实采集方进入既有采纳控制面前的纯离线前置：结构预检只是必要条件，还须绑定 runner/报告/授权/时钟与工程—地图指纹的外部来源证明；四角色两两分离、环境冻结、规范化 manifest 单向交审阅。当前无真实 Y3 工程、采集方或证据，P0 仍 `0/7`，不能采纳或投影。 |
| [enemy-ecology/天庭敌人生态与精英单位规格.md](enemy-ecology/天庭敌人生态与精英单位规格.md) | 非通天塔的小怪、精英、机制与噩梦支援状态的职责、预警、反制、首领护栏与施工前验收。 |
| [enemy-ecology/tianting-enemy-ecology-contract.json](enemy-ecology/tianting-enemy-ecology-contract.json) | 敌人生态的机器可读边界；所有对象、单位、数值、波次、掉落、资格与经济字段为 `null/deferred`。 |
| [mainline-boss/天庭主线Boss深化规格.md](mainline-boss/天庭主线Boss深化规格.md) | 五组非通天塔主线首领级遭遇的阶段语法、附属压力接口、可读性与复盘规格。 |
| [mainline-boss/tianting-mainline-boss-contract.json](mainline-boss/tianting-mainline-boss-contract.json) | 主线首领深化的机器可读合同；不创建对象、技能、地图、会话、进度、奖励或经济输入。 |
| [mainline-presentation/天庭主线Boss叙事与表现深化规格.md](mainline-presentation/天庭主线Boss叙事与表现深化规格.md) | 五组主线 Boss 的叙事、预警、复盘、无障碍替代与表现层级；不写权威状态、资产或经济。 |
| [terrain-layout/layout.json](terrain-layout/layout.json) | 纯离线地形 dry-run：公共路线候选分区、独立会话图尺寸族、场地职责与后续施工层。 |
| [terrain-layout/layout-report.md](terrain-layout/layout-report.md) | 带可复现预览的候选布局报告；不代表 Y3 地图已创建。 |
| [terrain-layout/天庭地图口径对齐与白盒前置裁决.md](terrain-layout/天庭地图口径对齐与白盒前置裁决.md) | 图解坐标、白盒场景和会话包络之间的唯一映射裁决。 |
| [terrain-layout/scale-alignment/layout-report.md](terrain-layout/scale-alignment/layout-report.md) | `224×80` 容量内的两张公共白盒候选布局报告。 |
| [ui/天庭UI与无障碍信息架构规格.md](ui/天庭UI与无障碍信息架构规格.md) | 双通道预警、快照、队伍状态、复盘与称号的可验收交互信息规格。 |
| [object-blueprint/天庭物编美术与特效需求蓝图.md](object-blueprint/天庭物编美术与特效需求蓝图.md) | Boss 轮廓、前摇、特效层级和场地交互的无资源 ID 蓝图。 |
| [object-preallocation/天庭物编字段预占规格.md](object-preallocation/天庭物编字段预占规格.md) | 十一类生态、五组主线、七星、二十八星官与四圣的五十五张逻辑物编卡；稳定对象键、`copyFrom`、资源、绝对字段与插件保持 `null/deferred`。 |
| [天庭权威运行时基座与主线纵切](../../../implementation/tianting-authority-vertical-slice/README.md) | 受信任 Node/Fengari 边界内的纯离线 Lua 主线纵切回归包。 |
| [天庭 Y3 施工预检](../../../implementation/tianting-y3-construction-preflight/README.md) | 未来 Y3 地图根的结构性 fail-closed 预检；当前仓库不是可施工地图工程。 |
| [天庭地图、UI 与资产施工发现清单](../../../implementation/tianting-surface-construction-manifest/README.md) | 主线白盒、最小 HUD、失败复盘和资产批次的无写入发现清单；实际绑定均为空。 |
| [施工顺序与就绪门禁台账](construction-readiness-ledger.md) | P0 到通天塔的顺序、已完成离线工件、准入条件与阻塞原因。 |
| [tower-economy/星宿经济来源、全局通天塔运行与赛季裁决.md](tower-economy/星宿经济来源、全局通天塔运行与赛季裁决.md) | 四十层完整 run、Boss 槽和大 Boss 的天庭侧候选、赛季快照与零值经济来源边界；总层数仍待上位全局塔合同采纳。 |
| [encounters/天庭公共遭遇规格.md](encounters/天庭公共遭遇规格.md) | 公共路线遭遇骨架、可读性与施工前验收。 |
| [economy-candidates/天庭奖励候选登记.md](economy-candidates/天庭奖励候选登记.md) | 仅奖励类别、称号防叠加与经济接入前置。 |
| [tower/天庭Boss复用接口.md](tower/天庭Boss复用接口.md) | 全局通天塔的内容池接口；具体 run 编排以 `tower-economy/` 裁决为准。 |
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
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-terrain-layout\scripts\validate-layout-plan.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\terrain-layout\layout.json -AllowWarnings
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-terrain-layout\scripts\validate-layout-plan.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\terrain-layout\scale-alignment\layout.json -AllowWarnings
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-authority-vertical-slice\tests\test-execution-boundary.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-authority-vertical-slice\tests\run-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\combat-calibration\tests\run-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-y3-construction-preflight\tests\test-preflight.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-surface-construction-manifest\tests\run-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-seven-star-session-reference\tests\run-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-mansion-session-reference\tests\run-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\天庭篇主线遭遇与通天塔规格包\mainline-presentation\tests\run-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\天庭篇主线遭遇与通天塔规格包\object-preallocation\tests\run-all.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\run-all-tianting-construction-readiness.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\economy-v2-authoritative-settlement\tests\run-all.ps1
~~~

通过仅表示离线设计可被后续专项接手；不代表任何副本、Boss、材料、称号、地图、同步或结算已经实现。
