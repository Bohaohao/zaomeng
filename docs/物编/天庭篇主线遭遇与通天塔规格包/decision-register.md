# 天庭篇与通天塔首轮决策登记

## 已冻结基础边界

| ID | 决策 | 状态 | 影响 |
|---|---|---|---|
| TT-FIX-001 | 天庭等级段为 Lv41–60，首发等级上限为 Lv60。 | fixed | 只定义章节定位，不推导经验表或时长。 |
| TT-FIX-002 | 通天塔入口要求单人或每一名团队成员均达到 Lv55。 | fixed | 不使用队伍平均等级或成员替代。 |
| TT-FIX-003 | 通天塔每五层设置构筑休整节点。 | fixed | 基线本身不定义总层数或 Boss；后续离线完整 run 必须保持该休整硬约束。 |
| TT-FIX-004 | 玲珑塔主题并入唯一全局通天塔。 | fixed | 天庭只提供内容池接口，不能创建独立塔记录、赛季或账本。 |
| TT-FIX-005 | 首发公共地图、单人本与团队本最多四人；共享状态走权威玩法逻辑。 | fixed | 副本未来必须复用会话、成员锁、失败和清理边界。 |
| TT-FIX-006 | `DF_PROGRESS_YANLUO_HALL_CLEARED` 不是天庭门槛、写入目标或消费者。 | fixed | 天庭只可验证同角色、源自 `DF_E_YANLUO_HALL` 成功事件的跨章交接证明；不得直接消费受保护键。 |
| TT-FIX-007 | 成长、货币、掉落、保底和塔奖励由版本化资源表和幂等收据结算。 | fixed | economy-v2 仅是运行时关闭的设计引用；implementation/growth 仍禁止消费。 |

## 本轮内容设计结论

| ID | 结论 | 状态 | 约束 |
|---|---|---|---|
| TT-DESIGN-001 | 以天门倾覆、临时天庭、错误天律、四方轮值失衡和星历污染组织主线。 | offline_design | 保留“净化秩序而非只消灭守卫”的核心冲突。 |
| TT-DESIGN-002 | 常规路径为临时天庭主城 → 南天门 → 天宫道 → 天王殿外缘 → 周天观台 → 凌霄外庭。 | offline_design | 是内容路径，不是地图坐标、传送或进度实现。 |
| TT-DESIGN-003 | 凌霄外庭·裂律观台承担天庭常规主线收束。 | offline_design | 常规完成的唯一语义生产者已由权威合同指定；真实进度键、服务与实例仍为空。 |
| TT-DESIGN-004 | 旧“蟠桃园 / 御马监二选一单人本”被七星固定单人系列取代。 | fixed-user-requirement | 蟠桃园/御马监可保留为场景或支线，不再抢占单人本名额。 |
| TT-DESIGN-005 | 七星固定为天枢、天璇、天玑、天权、玉衡、开阳、瑶光；各有残片、星君称号、独立机制和展示方向。 | fixed-user-requirement | 残片运行时键、掉落、数值和称号实现均为空。 |
| TT-DESIGN-006 | 同种七星残片十枚可合成对应星君称号；七称号齐备自动解锁名称待定的集合称号。 | fixed-user-requirement | 十枚是用户固定的离线配方倍率，不是掉落量；集合称号不与单称号重复叠加。 |
| TT-DESIGN-007 | 二十八星宿是天庭常规主线后开放的最高端团队本；凌霄/杨戬方向降为主线高潮或后续故事素材。 | fixed-user-requirement | 不把团队本写成常规完成者。 |
| TT-DESIGN-008 | 十二时辰按四槽循环三次：子/辰/申青龙，丑/巳/酉朱雀，寅/午/戌白虎，卯/未/亥玄武。 | fixed-user-requirement | 以服务器 `Asia/Shanghai` 自然时辰生成并冻结 rotation_snapshot；实例中禁止换宿、客户端改时或重试重掷。 |
| TT-DESIGN-009 | 普通七宿完成产出方位夜巡钥候选；噩梦同方位四圣兽与七宿保持双向加成。 | fixed-user-requirement | 钥匙形态、消耗、归属、掉落和收据 deferred。 |
| TT-DESIGN-010 | 四圣称号经普通完成、噩梦完成与七链净宿取得；四象齐备自动取得四象镇天。 | offline_design | 无数值、无 title/cosmetic ID；集合效果不与单称号翻倍。 |
| TT-DESIGN-011 | 七星和二十八星宿成为唯一全局通天塔的小 Boss 内容池；天庭侧候选为每五层 Boss 槽，第十层节点升级为大 Boss 并取代该槽的小 Boss。 | fixed-user-requirement / global-adoption-pending | 槽位编排只通过 `NEXT_CYCLE_HANDOFF` 外层组织，不修改或给既有五拍绑定内容；不宣告为上位全局塔已采纳。 |
| TT-DESIGN-012 | 天庭战斗统一使用“预警 → 决策 → 反制 → 可复盘失败”语法；主线、七星、四方七宿与四圣均保留 1–4 人可完成路径，颜色不是唯一关键信息载体。 | offline_design | 只冻结可读性和场地职责；不创建技能、数值、AI、实际 UI 或会话状态机。 |
| TT-DESIGN-013 | 公共路线、周天观台会话门廊、凌霄前庭和独立副本会话图采用候选分布与尺寸族；公共图不承载实际副本。 | offline_design_candidate | `terrain-layout/layout.json` 的坐标、尺寸、区域与路径仅为 dry-run，不能视为地图键、传送、出生点、地形写入或编辑器资源。 |
| TT-DESIGN-014 | `640×416` 归为章节关系图解；公共可玩白盒改为两张 `96×64` 候选场景并受 `224×80` 天界带状容量预算约束，独立副本继续使用会话包络。 | offline_preconstruction_decision | 不把图解单位缩放成地形格、地图大小或运行时坐标；实际地图/资源仍不存在。 |
| TT-DESIGN-015 | UI 以权威事实为唯一来源，冻结双通道预警、轮换快照、队伍状态、失败复盘及七曜/四圣称号展示的无障碍信息架构。 | offline_design | 不生成 UI 节点、资产、音效、特效、事件、存档或本地裁决。 |
| TT-DESIGN-016 | 主线、七星、二十八星官与四圣的物编／美术／特效需求统一按轮廓、前摇、P0–P2、L0–L4 与场地交互登记。 | offline_design_requirements_only | 当前物编蓝图只覆盖天庭主线/副本；不分配对象/资源 ID、模型、技能、Buff、数值或实际特效。全局塔四大 Boss 须在上位采纳后另起独立蓝图。 |
| TT-DESIGN-017 | 天庭侧完整 run 候选为四十层、八个五层段和四个十层篇章；第 10/20/30/40 层候选依次为四门校律使、九曜司衡官、镇塔监律使、玲珑塔灵的无数值创意身份。 | offline_design_candidate_pending_global_tower_adoption | 仅等待 `docs/物编/成长系统规格包/design-spec.json` 所属全局塔显式采纳；不创建真实楼层、地图、实例、记录、Boss 对象、资源 ID、数值、经济或掉落。 |
| TT-DESIGN-018 | 通天塔赛季只提出未来权威快照语义；星宿、塔小 Boss、大 Boss 与 run 关闭当前都不是经济来源。 | offline_design_candidate_pending_global_tower_adoption | season ID、日期、词缀、榜单、周桶、重置、来源事件、profile、slot、资格、收据和任何奖励值均为 `null/deferred`。 |
| TT-DESIGN-019 | 非通天塔敌人生态固定为受控天兵、四门守备机关、失控云兽、泛称监星使及巡天/阵眼/星历/裂律/校星/方位/共鸣回响；它们是可读性与反制职责，不是现成单位或奖励容器。 | offline_design_requirements_only | 不得降格复用千里眼、顺风耳、巨灵神、监律天将、七星首领、二十八星官或四圣兽；对象、技能、AI、数值、波次、刷新、掉落和经济均继续为空。 |
| TT-DESIGN-020 | 南天门、断虹阵、四门失衡、周天观台、凌霄外庭五组主线首领级遭遇固定以“来源/关系预警 → 读图决策 → 可见反制 → 可复盘失败”深化；附属压力只能放大 P0 信息。 | offline_design_requirements_only | 每组保留串行单人解法与 1–4 人并行适配；不创建 Boss 对象、技能、AI、数值、波次、地图、会话写入、奖励或经济输入。 |
| TT-DESIGN-021 | 建立独立的天庭战斗数值与单位基线：以四职业 Lv41/45/50/55/60 裸装包络为参照，冻结 `H0/A0/M0/I0/R0/B0/O0/S0`、既有单位覆盖、主线/七星/星宿/四圣相对压力与 1–4 人缩放。 | accepted_relative_balance_baseline_offline_only | 系数是无量纲离线设计值；不得推导或填写 `hp_max`、攻击、双防、秒数、对象键、波次、会话/资格、经济或塔值。 |
| TT-DESIGN-022 | 建立跨职业绝对标定协议：冻结 C01–C04 Lv41/55/60 锚点、12 份固定构筑声明账本、D90/B10、60Hz 动作/移速、碰撞和 1–4 人回放的证据接口，并以 `TT_CAL_ABSOLUTE_OBJECT_FIELDS_V1` 承接未来天庭字段投影。 | offline_calibration_protocol_accepted_projection_blocked | 现有窄域旧物理夹具不能外推为泛用伤害/双防/命中控制公式；七道投影门禁均未采纳，目标对象、HP、攻击、双防、攻速、移速和技能秒数必须保持 `null`。 |
| TT-DESIGN-023 | 将五组主线白盒、最小 HUD、失败复盘与 P0 资产批次收束为实时发现清单；候选图解只提供未来读项目后的施工核对项。 | offline_preconstruction_discovery_only | 不创建或写入地图、地形、UI、对象、资源、Y3 API 绑定、权威状态或经济字段；每个真实绑定均等待现场读取与对应门禁。 |
| TT-DESIGN-024 | 七星星君称号来自单人本；每个效果方向必须对单人完整可用，组队最多增加展示或可选协同。 | offline_design_consistency_fixed | 不把天权等称号落成“团队共同打断”才有价值的硬依赖；具体数值、持久化和效果实现继续延期。 |
| TT-DESIGN-025 | 将五组既有主线 Boss 深化为叙事与表现规格：入场引导、三段锚点、双通道预警、失败复盘、非经济确认与 L0–L4 表现职责。 | offline_narrative_presentation_spec | 只消费未来已确认的权威事实；不引入原作正文、实际镜头/音频/VFX 资源、对象、地图、数值、会话/进度写入或经济。 |
| TT-DESIGN-026 | 建立天庭物编字段预占包：将 11 类敌人生态、5 组主线、7 星、28 星官和 4 圣收束为 55 张逻辑卡，并固定声音／投射物／表现状态→技能壳→单位／机制体→遭遇组装的依赖顺序。 | offline_field_reservation_only | 不产生 y3-object-config `assets`／`mode`、插件、对象键、`copyFrom`、模板、资源、字段映射或绝对数值；所有实际绑定等待 P0 七道门、真实对象／资源盘点、稳定键／模板审定与写入授权。 |
| TT-DESIGN-027 | 建立 P0 实证采集与采纳包：以父 P0 合同的 SHA-256 与完整七门 ID 序列为唯一真源，冻结“真实 Y3 只读采集 → 不可变外部工件摘要 → 独立复核 → 外部授权采纳 → 单独绝对字段投影复审”的链路。 | offline_evidence_collection_and_adoption_plan_only | 当前没有可信采集方、真实工程引用、证据账本、采纳决定或投影负载；测试/预检/发现清单/客户端声明/自由文本摘要/重复 run/混版本和对象键或绝对字段注入都不能打开门禁。 |
| TT-DESIGN-028 | 建立 P0 受信任外部实机采集方接入前置：结构预检仅是必要条件，须由外部来源证明精确绑定预检合同/runner/报告、只读授权、权威时间及无路径泄露的工程—地图指纹；四角色两两隔离，manifest 仅单向流向独立审阅。 | offline_external_capture_onboarding_only | 当前没有真实 Y3 工程、采集方、资格绑定、来源—预检证明、环境证明、工件、审阅交接、证据账本、采纳决定或投影；本地模板、预检、发现清单和 Node/Fengari 夹具都不能登记提供方、采纳 P0 或填写天庭绝对字段。 |

## 本轮权威合同结论

| ID | 结论 | 状态 | 约束 |
|---|---|---|---|
| TT-AUTH-001 | 建立 `TT_SPEC_PROGRESS_CHAPTER_ENTERED`、`TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN`、`TT_SPEC_PROGRESS_MAINLINE_CLEARED` 三段角色级逻辑进度；生产者分别为天门过渡、周天观台主线节点和凌霄外庭·裂律观台权威成功。 | offline-contract-fixed | 运行时键均为 `null`；每次写入遵守 `(actor_id, event_id)` 幂等与完成收据语义。 |
| TT-AUTH-002 | 入章由权威端逐人确认达到 Lv41 与同角色的 `TT_SPEC_CHAPTER_ENTRY_HANDOFF_PROOF`（源自 `DF_E_YANLUO_HALL` 成功）。 | offline-contract-fixed | 不读写、不注册或转译 `DF_PROGRESS_YANLUO_HALL_CLEARED`；证明签发、验签与存储未实现。 |
| TT-AUTH-003 | `TT_SPEC_SESSION_LINGXIAO_MAINLINE` 是私有 1–4 人终局会话；每名入场者校验已入章，只有权威确认的有效参与者写入常规完成。 | offline-contract-fixed | 队长、旁观者、伪造成员或未授权队友不能代领；无真实实例或进度发放。 |
| TT-AUTH-004 | `TT_SPEC_SESSION_SEVEN_STAR` 复用单人会话身份与清理骨架；`TT_SPEC_SESSION_MANSION_NORMAL` / `TT_SPEC_SESSION_MANSION_NIGHTMARE` 复用团队成员快照与阶段骨架，状态为 `active → cleanup_pending → closed`。 | offline-contract-fixed | 死亡、超时、断线或生命周期失效进入失败清理；只有匹配实例身份、`session_epoch`、`revision` 和 cleanup token 的权威确认才可解除重入锁。 |
| TT-AUTH-005 | `TT_SPEC_TIME_BASIS_ASIA_SHANGHAI_SHICHEN` 在星宿会话首次成功创建时，以服务器 `Asia/Shanghai` 时辰冻结权威轮换快照。 | offline-contract-fixed | 客户端时钟、客户端方位及重试重算均禁止；真实时间提供方、存储和恢复策略仍延期。 |
| TT-AUTH-006 | `TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL` 按角色逐人解析不透明凭证；每人都满足 `normal_clear.quadrant == credential.quadrant == nightmare.rotation_snapshot.quadrant`。 | offline-contract-fixed | 凭证物品形态、消耗、掉落、数量与收据仍由经济裁决包决定。 |
| TT-AUTH-007 | 建立天庭完成/会话 → economy-v2 权威收据输入交接合同；`TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 原子绑定同一完成 receipt/proof、会话 route/instance/epoch/revision、成员快照/状态与星宿轮换，才可形成零价值候选。 | offline-contract-fixed | 当前仅既有凌霄主线成功可进入该零价值来源事实候选；七星/普通星宿/噩梦星宿成功仍无 source success event，不得形成 handoff candidate、资格或结算。未分配 `source_profile`、slot、owner、qualification、roll、保底或任何奖励。 |
| TT-AUTH-008 | 建立独立纯 Lua 的“入章 → 周天观台 → 凌霄外庭”权威纵切；它经固定的受信任 Node/Fengari 离线边界执行。 | offline-tested-reference-only | 只模拟权威提供方事实和进程内逻辑记录；不接入 Y3、地图、存档、网络、真实证明或 economy-v2。`NODE_PATH` 与其他 Node/Lua 注入变量均拒绝。 |
| TT-AUTH-009 | 建立未来主线 Y3 接入的结构性 fail-closed 预检：目标必须是已存在的 map-local 根，且具备 `script/y3/{meta,game}` 与同根 `ui`；对象接口名只是未验证的标签。 | structural_preflight_only | 当前离线仓库按预期被拒绝；合成目录只能证明预检逻辑，不能声明地图、Y3 API、对象、UI、会话或权威服务已经存在。 |
| TT-AUTH-010 | 建立七星单人会话的进程内离线参考模型：只验证 owner、观台进度、七路线、失败清理、完成保留、重入锁和请求幂等。 | offline_reference_model_only | 注入夹具不能变成真实进度、会话、掉落、称号、资格、收据或 economy-v2 输入；不接入 Y3、Lua、网络或持久化。 |
| TT-AUTH-011 | 建立二十八星宿普通/噩梦的进程内离线参考模型：只验证注入上海时辰、逐人主线/资格、三方位、`left`、清理和重放。 | offline_reference_model_only | 不读取系统或客户端时间，不创建真实团本、凭证、时间服务、持久化、奖励或结算；P1/P3 真实接入仍受原门禁约束。 |

## 明确延期

| ID | 未决项 | 阻塞原因 |
|---|---|---|
| TT-DEFER-001 | **合同语义和离线主线纵切已由 TT-AUTH-001～003、008 覆盖**；仍延期真实进度键、证明签发/验签、持久化存储、网络协议、Y3 接入和运行时写入。 | 离线 Lua fixture 不能代替受信任生产运行时。 |
| TT-DEFER-002 | 候选公共路线与会话图布局已完成；仍延期真实地图、邻接、出生点、入口/出口、区域等级、对象、地形、碰撞、资源与地图键。 | dry-run 不能代替当前地图读取、Y3 地形写入或实际工程验收。 |
| TT-DEFER-003 | **会话身份、成员锁、失败、清理与幂等语义已由 TT-AUTH-004 解决**；仍延期真实创建、检查点、退出、锁、复活和恢复实现。 | 纯离线合同不能替代会话服务与 Y3 施工。 |
| TT-DEFER-004 | 七星残片、夜巡钥、星宿/四圣材料、装备、法宝和称号的资源表绑定、发放与收据。 | economy-v2 未分配天庭来源，且运行时账本尚未接入。 |
| TT-DEFER-005 | **天庭侧完整 run 候选、Boss 槽、大 Boss 创意身份和赛季快照语义已由 TT-DESIGN-017～018 提出，但仍待上位全局塔合同采纳**；仍延期真实全局塔实例、楼层地图、内容抽取、词缀、记录、失败恢复、季节服务、掉落来源、资格、收据和奖励。 | 离线塔合同不能替代上位全局塔决策、权威 run 服务、经济裁决或实际地图施工。 |
| TT-DEFER-006 | **`Asia/Shanghai`、快照字段、冻结时点和客户端禁止项已由 TT-AUTH-005 解决**；仍延期真实时间提供方、时钟容错、存储、恢复和异常回退。 | 轮换合同不能代替时间服务。 |
| TT-DEFER-007 | Y3 对象、地图根 Lua、UI、持久化、多人同步、性能和实际美术资产。 | 独立离线 Lua 回归与结构预检都不构成 Y3 接入；当前仓库必须被预检拒绝。任何 Y3Maker 地形、装饰或逻辑资源写入都必须先重新读取当前地图/资源并取得明确确认；候选布局与发现清单不可直接下发。 |
| TT-DEFER-008 | **相对战斗标尺、P0/反制拍数和 1–4 人缩放已由 TT-DESIGN-021 冻结，跨职业绝对标定协议已由 TT-DESIGN-022 建立，实证采集与采纳链已由 TT-DESIGN-027 固定，外部实机采集方接入前置已由 TT-DESIGN-028 固定**；仍延期原始 `hp_max`、攻击/双防、Y3 移速和攻击间隔、秒数、技能伤害/冷却、仇恨、AI、波次、镜头/无障碍实机表现、性能预算、称号作用域、叠加细节、毕业法宝最终名称/配方/属性及四圣材料必要性。 | 七道绝对投影门禁尚无采纳证据：缺少可信采集方、真实 Y3 工程、完整四职业构筑与三次回放、泛用物理/魔法/双防穿透、命中/暴击/控制公式、实机动作帧、真实碰撞/镜头、1–4 人权威回放、稳定对象键和外部逐门采纳账本。 |
| TT-DEFER-009 | 四个全局塔大 Boss 的对象／美术／特效资产蓝图。 | 当前物编蓝图只涵盖天庭主线、七星、二十八星官与四圣；待上位全局塔显式采纳天庭候选后，另建独立蓝图，所有 runtime key、resource ID、经济/奖励值继续为 `null/deferred`。 |
| TT-DEFER-010 | 敌人生态与主线首领已完成行为层规格，但实际单位名册、对象/资源 ID、技能/Buff、AI、数值、波次/刷新、地图/出生点、性能、会话接入与经济绑定仍延期。 | 纯离线职责、可读性与复盘不能代替 Y3 物编、战斗运行时、权威会话或经济裁决。 |

## 外部经济状态镜像

| 外部决策 | 当前状态 | 本包处理 |
|---|---|---|
| ECO-BASE-001：等级段、Lv55 塔门槛、每五层休整 | accepted-baseline | 精确继承为结构约束。 |
| ECO-BASE-002：装备/法宝/宠物/材料分类边界 | accepted-baseline | 只登记类别，不创建资产。 |
| ECO-QUAL-001：公共 Boss 资格四分与事件幂等 | accepted-baseline | 天庭公共内容未来复用其分层；星宿/塔不得默认套用未裁决奖励。 |
| 四职业 Lv41–60 裸装公式与跨职业白盒夹具 | calibration-protocol / projection-blocked | 已由 `implementation/combat-calibration` 固化为 P0 证据协议；可作为天庭相对数值的玩家包络和未来实测夹具，但不得把夹具目标属性复制为天庭单位、奖励或经济字段。 |
| `docs/物编/成长系统规格包/design-spec.json`：全局塔总层数、分段、Boss 槽与赛季编排 | upstream-authority / unselected | 天庭四十层／八段／五层 Boss／四大 Boss 仅为离线候选，等待该合同显式采纳；不得进入 runtime、经济或奖励。 |
| economy-v2：曲线、塔首轮奖励和收据语义 | accepted-baseline / runtime-not-integrated | 可作设计引用；不得把七星、夜巡钥或四圣候选伪装成已存在资源键。 |
| 历史候选与 implementation/growth | proposal / deferred / offline candidate | 只能作为历史校准，不得成为天庭实现输入。 |
