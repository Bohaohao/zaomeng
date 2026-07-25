# Lua 逻辑交接简报

本包不生成 Y3 地图根 Lua。[进度与副本会话权威合同](../authority/tianting-progression-and-instance-authority-contract.json) 冻结未来权威玩法逻辑必须接手的语义边界，不能由 UI、本地时间或临时脚本绕过。[战斗可读性合同](../combat/tianting-combat-readability-contract.json) 只补充预警、决策、反制和可见结果的设计输入，不能产生新的状态写入或经济路由。

[敌人生态合同](../enemy-ecology/tianting-enemy-ecology-contract.json)与[主线 Boss 深化合同](../mainline-boss/tianting-mainline-boss-contract.json)只允许未来表现层消费既有权威已确认的阶段、关系、路线和成员状态：它们不能创建单位、波次、会话、进度、资格、成功事件、奖励、收据或 economy-v2 输入，也不能把附属压力变成清场或首领替代条件。

[战斗数值与单位基线裁决](../combat-baseline/tianting-combat-numeric-unit-baseline-contract.json)只提供四职业裸装参照和无量纲 `H0/A0/M0/I0/R0/B0/O0/S0` 系数。未来战斗逻辑可以在权威已确认的成员规模下选择相对缩放档，但不得把它解释为原始对象属性、秒数、会话规则或经济输入；没有完整标定证据与稳定对象键时，不得写 `hp_max`、攻击、双防、移速、攻速、伤害、冷却或 AI 参数。

[P0 实证采集与采纳包](../../../../implementation/combat-calibration/evidence-adoption/README.md)是后续实机标定的唯一离线入口：它只接受受信任外部系统的只读、不变工件引用与哈希，并要求采集者、复核者和采纳者分离。当前没有真实采集方或账本，因此 Lua/Y3 施工不得把此包、离线 Node/Fengari 测试、结构预检或施工发现记录解释为已采纳公式、稳定对象键或对象字段。

独立的[天庭权威运行时基座与主线纵切](../../../../implementation/tianting-authority-vertical-slice/README.md) 只作为 Node/Fengari 受信任边界内的纯离线回归：它实现入章、周天观台和凌霄外庭的可验证模型，不提供 Y3 API、地图、存档、网络或真实证明服务。`NODE_PATH` 不是依赖来源，必须被拒绝。未来转接 Y3 前，必须先通过[天庭 Y3 施工预检](../../../../implementation/tianting-y3-construction-preflight/README.md)并读取真实地图根、Y3 API 基线和 UI 根；预检的合成 fixture 或当前仓库的 fail-closed 不能代替这些事实。

[天庭毕业法宝定位与谱系合同](../artifact-graduation/tianting-endgame-artifact-positioning-and-lineage-contract.json)与[周天校律盘完整设计合同](../artifact-graduation/complete-design/tianting-graduation-artifact-complete-design-contract.json)共同为未来逻辑提供单一活动法宝槽、构筑预设原子切换、挑战锁、定序／辨序／开序互斥响应，以及“不自动读题、反制、复活、回滚或绕过清理”的边界。完整设计把回应限定为当前角色已经取得的权威反制窗口的只读、一次性可读提示：定序只接受 `stabilize`、辨序只接受 `discern`、开序只接受 `open`；错配必须转为 `invalidated` 且不出回应卡。未来实现必须以 `(actor_id,response_window_id)` 幂等，死亡、断线、`left`、旧生命周期与 `cleanup_pending` 先使未结算回应失效。它们不是入章、主线、七星、星宿、夜巡资格或经济写入的替代品；在 P0 外部实证和独立 source-profile／收据合同采纳前，Lua/Y3 不得创建法宝、技能、材料、配方、属性、掉落、资格、收据或 economy-v2 调用。

[七星会话离线参考包](../../../../implementation/tianting-seven-star-session-reference/README.md)与[星宿会话离线参考包](../../../../implementation/tianting-mansion-session-reference/README.md)只把既有权威合同的准入、快照、失败、清理和幂等边界固定为进程内回归；它们不能代替真实进度、时间、凭证、成员、会话或断线服务。未来 Lua/Y3 接入必须把这些事实交由可信提供方解析，不得从调用字段、系统时钟、客户端方位或参考模型记录推断。

[二十八星官与四圣机制编排合同](../mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json)是未来团本战斗状态机的唯一离线语义输入：普通本按严格四段 `2+2+2+1` 和逐星官的读线/提交/反制/恢复推进，噩梦按同方位固定 `2+2+2+1` 链序与净宿集合推进。未来逻辑只能在既有会话确认 `active` 且完整绑定 raid/boss/epoch/`phase_id`/revision、轮换快照、方位、难度和每名成员的 actor/lifecycle/membership/status 权威元组后消费这些语义；`transition_index` 只能沿声明边前进，恢复不能跳段或倒退。`phase_id`、`revision` 与 `cleanup_token` 不可被用作或改写为战斗阶段，`cleanup_token` 更不得进入玩家机制输入。该合同不生成 Lua、权威事件、计时器、实际状态机或会话完成写入。

## 必须先有的权威合同

| 域 | 未来逻辑必须保证 | 本包未提供 |
|---|---|---|
| 天庭章节 | 权威端逐人确认达到 Lv41 与同角色 `TT_SPEC_CHAPTER_ENTRY_HANDOFF_PROOF`（源自 `DF_E_YANLUO_HALL` 成功），依序写入 `TT_SPEC_PROGRESS_CHAPTER_ENTERED`、`TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN`、`TT_SPEC_PROGRESS_MAINLINE_CLEARED`；不消费或写入 `DF_PROGRESS_YANLUO_HALL_CLEARED`。 | 真实键、证明签发/验签、存储、写入者服务和网络事件。 |
| 主线终局 | `TT_SPEC_SESSION_LINGXIAO_MAINLINE` 私有 1–4 人会话逐人校验入章；仅有效权威参与者可获得常规完成，队长/旁观者不能代领。 | Lua 状态机、地图、队列、进度写入与实例服务。 |
| 七星单人本 | `TT_SPEC_SESSION_SEVEN_STAR` 仅由周天观台开启者创建；使用 owner、生命周期、实例、epoch、revision、cleanup token，并在死亡、超时、断线或生命周期失效后进入清理、清理前禁止重入。 | Lua 状态机、单位、技能、复活、掉落与实际锁。 |
| 星宿轮换 | `TT_SPEC_TIME_BASIS_ASIA_SHANGHAI_SHICHEN` 在首次成功创建会话时，从服务器 `Asia/Shanghai` 权威时间冻结 rotation_snapshot；整个实例都锁定方位和难度。 | 时间服务、快照存储、恢复和异常回退。 |
| 星宿普通 | 冻结 1–4 人权威成员快照，并逐人校验常规主线完成；共享七宿的双宿/双宿/双宿/单宿阶段状态。 | 波次、AI、检查点、收益和实际成员锁。 |
| 星宿噩梦 | 每位成员各自持有并由权威端解析 `TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL` 同方位资格；七宿向四圣施加宿曜贡辉，四圣向七宿施加圣兽庇护；每条共鸣链只能由权威逻辑转为净宿一次。 | 凭证物品/消耗、Buff ID、数值、持续时间、效果实现。 |
| 星宿遭遇编排 | 逐星官读线、提交、反制、恢复与成员流失降级；普通严格四段 `2+2+2+1`、噩梦固定同方位 `2+2+2+1` 链序，净宿集合只增不减。普通与噩梦只形成终局候选；未来转场绑定既有会话身份和权威成员元组，`transition_index` 只能沿声明边前进。 | Lua/Y3 状态机、计时器、实际战斗事件、终局证明验证器、会话完成写入、资格、奖励和收据。 |
| 战斗可读性 | 将权威已接受的阶段、连线、净宿和成员状态映射为预警、决策和可见反制反馈；不得让战斗表现反向决定资格、进度、方位或会话状态。 | Lua 代码、事件注册、同步、计时器、伤害、仇恨和阶段数值。 |
| 相对战斗数值 | 只消费 `H0/A0/M0/I0/R0/B0/O0/S0`、既有身份映射与权威确认的 1–4 人规模；P0 与反制窗口不因人数缩短。 | 原始对象字段、秒数、伤害公式、技能循环、装备/法宝/宠物/收集加成、波次与 AI。 |
| P0 绝对标定 | 仅在 `CAL_SPEC_CROSS_PROFESSION_ABSOLUTE_COMBAT_V1` 的七道投影门禁通过 `CAL_SPEC_P0_EVIDENCE_COLLECTION_AND_ADOPTION_V1` 逐项外部采纳、且单独投影复审通过后，才可将相对标尺提出为对象字段候选。 | 把离线锚点、窄域旧夹具、Node/Fengari 测试、结构预检、发现清单或设计空间移速写成 Y3 HP、攻击、双防、攻速、移速、技能秒数或碰撞参数。 |
| 敌人生态与主线 Boss | 只把既有阶段、来源、关系、反制窗口与失败原因渲染为受控天兵/机关/回响及五组主线首领级遭遇的表现职责；首领身份不可降格，小怪不得遮挡 P0。 | 单位、对象、技能、Buff、AI、波次、刷新、地图、会话、进度、奖励、资格、成功事件和经济输入。 |
| 死亡与断线 | 团队成员死亡后回当前篇章初始出生点并锁至清理确认；断线成员为 `left`，不得重连或领奖，其他 `active` 成员可以继续。 | 出生点、复活流程、断线检测、锁和奖励实现。 |
| economy-v2 输入交接 | `TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 必须从同一完成 receipt/proof 和冻结会话快照原子导出 actor/生命周期/成功事件、route/实例/epoch/revision、成员状态与轮换；当前只有凌霄主线成功可进入既有零价值来源事实候选，且仍不能调用 materializer。 | 七星/普通星宿/噩梦星宿的 success event、source profile、slot、owner、资格 ID、roll、保底、经济实例 ID、收据和一切奖励数值。 |
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
- 不把相对系数、跨职业白盒夹具或玩家裸装属性直接复制为天庭单位的 HP、攻击、双防、秒数或 Buff；绝对值必须走独立标定门禁。
- 不以客户端本地时间、UI 缓存或队长单方面状态决定轮换。
- 不把七星、普通星宿或噩梦星宿的战斗阶段/完成事实转为 handoff candidate、资格或结算输入；该路由需要未来独立授权，当前 success event 仍为空。
- 不让敌人生态或主线 Boss 表现层创建新成功事件、进度写入、资格、奖励、收据或 economy-v2 输入；附属压力只能消费既有权威事实。
- 不把 `session_instance_id`、`raid_instance_id`、噩梦入场凭证或 cleanup 成功直接转换为 economy-v2 的经济实例、奖励资格或结算请求；未获批 source profile 时所有经济字段必须保持 `null/deferred`。
- 不创建真实进度键、跨章证明、资格凭证、收据、会话锁、时间服务或奖励；合同中的 `TT_SPEC_*` 与 `null/deferred` 不能被当作可运行资产。
- 不新增 tower_mode、通天塔奖励模式或第二套爬塔记录。
