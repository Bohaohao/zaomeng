# Y3 设计规格报告

## 一句话项目定位

以第三劫下的临时天庭为 Lv41–60 内容锚点：常规主线修复裂律，七星提供单人长期校星目标，二十八星宿以时辰轮换和噩梦四圣兽形成高端团队终局。

## Y3 适配性判断

```json
{
    "camera":  "2.5D 俯视角",
    "sessionType":  "公共路线与副本均以单局关卡会话组织；主线纵切只在受信任 Node/Fengari 离线基座中回归，Y3 地图、对象、UI、存档和多人运行时均尚未施工",
    "targetPlayers":  "1-4 人",
    "targetDurationMinutes":  0
}
```

## 核心循环

```json
{
    "shortLoop":  "在公共路线识别错误命令，拆除阵眼或净化节点，推进至周天观台。",
    "midLoop":  "以七星单人本学习空间规则，收集残片并逐步解锁星君称号；这不是常规主线门票。",
    "longLoop":  "常规主线收束后，按冻结的时辰方位挑战二十八星宿普通与噩梦；Lv55 后可由上位全局塔采纳八段五拍、每五层 Boss 槽和每十层大 Boss 的天庭侧离线候选。",
    "rewards":  [
                    "七星残片、星君称号、方位宿印、夜巡钥、四圣铸核和圣兽遗珍均只登记为候选类别。",
                    "同种七星残片累计十枚合成对应星君称号是用户固定的离线配方倍率；掉落、数量、概率、保底与属性未定义。"
                ]
}
```

## 单局流程

- `{"phase":"裂云南天门至周天观台","duration":"未裁定","playerGoal":"确认错误命令、拆阵并取得四象轮值失衡的证据。","systemsUsed":["入章交接证明","Lv41 权威校验","角色级逻辑进度"],"successCriteria":"入章仅接受同角色阎罗殿成功交接证明与 Lv41；不消费受保护的地府进度键。"}`
- `{"phase":"七星单人试炼","duration":"未裁定","playerGoal":"逐星校正并掌握七种空间规则。","systemsUsed":["周天观台逻辑进度","固定七星单人会话","残片与称号候选"],"successCriteria":"七星只对已开启周天观台的同一角色开放，失败或断线只经匹配清理确认后重入；不定义实际掉落。"}`
- `{"phase":"凌霄外庭常规收束","duration":"未裁定","playerGoal":"阻止裂律将旧命令变成不可逆的全场压制。","systemsUsed":["私有 1–4 人主线终局会话","常规主线完成逻辑进度"],"successCriteria":"仅权威确认的有效参与者写入常规完成；二十八星宿仍为主线后高端轨道，不替代本段完成。"}`
- `{"phase":"二十八星宿普通与噩梦","duration":"轮换与单次时长未裁定","playerGoal":"处理当期方位七宿；噩梦中逐链解除四圣与七宿共鸣。","systemsUsed":["Asia/Shanghai 权威 rotation_snapshot","最多四人团队会话","角色级夜巡资格"],"successCriteria":"十二时辰映射完整，副本内方位锁定；每位成员均通过主线完成与同方位资格校验，普通到噩梦路径与双向加成关系可验证。"}`
- `{"phase":"全局通天塔天庭段（待采纳离线候选）","duration":"Lv55 后；候选四十层逻辑 run，实际时长未裁定","playerGoal":"若被上位全局塔采纳，在唯一全局塔内按七星/星宿内容槽和四个大 Boss 创意身份完成八段五拍。","systemsUsed":["全局塔五节拍边界","候选四十层外层编排","候选每五层 Boss 槽","权威赛季快照语义"],"successCriteria":"候选要求第 1–7 段只可由 NEXT_CYCLE_HANDOFF 续段；第 8 段禁止继续交接并经既有终局路径关闭；在上位采纳前不创建实际地图、掉落、记录或赛季值。"}`

## 系统拆分

- `{"name":"天庭章节进度合同","category":"progression","designIntent":"以入章、周天观台开启和常规主线完成三段角色级逻辑进度，建立不消费地府完成键的受信任章节边界。","requiredData":["DF_E_YANLUO_HALL 交接证明","Lv41 权威校验","三个唯一生产者","完成收据","(actor_id,event_id) 幂等","生命周期与清理边界"],"runtimeBehavior":"offline_design；仅定义 TT_SPEC 逻辑记录与权威接口，所有实际进度键、持久化和提供方保持未接入。","owner":"authority/tianting-progression-and-instance-authority-contract.json"}`
- `{"name":"七星单人本与称号收藏","category":"instance","designIntent":"用七种不同的空间规则形成可重复单人精通与收藏闭环。","requiredData":["周天观台逻辑进度","单人会话身份","失败与匹配清理确认","资源表绑定","称号作用域","收据与持久化"],"runtimeBehavior":"offline_design；七星仅在周天观台逻辑记录后由权威单人会话准入，十枚同星配方倍率和集合称号关系已定，数值与资产未定。","owner":"后续副本、物编、战斗、经济与权威会话合同"}`
- `{"name":"二十八星宿轮换团队本","category":"raid","designIntent":"用四象共享语法和二十八个签名动作，建立普通教学到噩梦综合考验的团队循环。","requiredData":["Asia/Shanghai 权威时间基准","冻结 rotation_snapshot","逐人主线完成校验","成员锁与清理","逐人夜巡资格","奖励收据"],"runtimeBehavior":"offline_design；轮换表、星官全名、机制方向、双向加成、时区语义与逐人资格已定，真实时间/会话/经济运行时未接入。","owner":"authority/tianting-progression-and-instance-authority-contract.json"}`
- `{"name":"四圣称号与毕业法宝候选","category":"long_term","designIntent":"让七星收藏、四象高端挑战和法宝追求互相看得见，但不强制将单人毕业锁死为团本门票。","requiredData":["称号持久化","效果叠加规则","配方绑定","属性","经济周期"],"runtimeBehavior":"offline_design；七曜集合称号名称待定，周天校律盘正式显示名已冻结；数值和资源均未创建。","owner":"后续成长、战斗、经济与物编复审"}`
- `{"name":"通天塔天庭内容复用","category":"long_term","designIntent":"提出把七星和星宿编入唯一全局塔候选的五层 Boss 槽，并用四个十层大 Boss 形成四段可读阶段总结。","requiredData":["上位全局塔采纳","候选四十层/八段逻辑编排","第 1–7 段续段与第 8 段关闭规则","候选每五层 Boss 槽","四个无数值大 Boss 身份","赛季快照语义","奖励与记录边界"],"runtimeBehavior":"offline_design_candidate_pending_global_tower_adoption；可提出继承第五拍为内容槽但不改状态或转移；不创建 tower_mode、地图、实例、记录、奖励表或经济输入。","owner":"tower-economy/mansion-economy-global-tower-run-season-contract.json"}`
- `{"name":"天庭战斗机制与可读性","category":"combat","designIntent":"把主线、七星、普通星宿与四圣噩梦统一成可读的预警、玩家决策、可见反制和可复盘失败，并确保一至四名成员都有完成路径。","requiredData":["战斗阶段权威状态","目标/路线/连线可见反馈","场地职责","双通道预警","成员快照","失败与清理边界"],"runtimeBehavior":"offline_design；只定义机制语言与验收，不创建技能、单位、伤害、计时、AI、同步、进度或结算。","owner":"combat/tianting-combat-readability-contract.json"}`
- `{"name":"天庭战斗数值与单位基线","category":"combat_balance","designIntent":"以四职业 Lv41/45/50/55/60 裸装包络和八个无量纲标尺，为已登记小怪、精英、五组主线 Boss、七星、二十八星官和四圣建立可复算的相对压力与暴露基线。","requiredData":["四职业裸装公式","H0/A0/M0/I0/R0/B0/O0/S0","既有 TT_SPEC 身份映射","权威确认的 active 成员数量","绝对值标定门禁证据"],"runtimeBehavior":"accepted_relative_balance_baseline_offline_only；不写入 hp_max、攻击、双防、秒数、对象、Lua、会话、资格、经济或塔值；绝对投影持续为 null。","owner":"combat-baseline/tianting-combat-numeric-unit-baseline-contract.json"}`
- `{"name":"候选副本分布与地形布局","category":"map","designIntent":"以公共路线候选图承接调查折返，以独立会话图承接凌霄、七星与星宿，保证 2.5D 视角下的预警、反制、退路和会话边界可读。","requiredData":["候选地图尺寸","区域/路线职责","会话图尺寸族","战斗读线","当前地图与资源读取","性能验证"],"runtimeBehavior":"offline_dry_run_candidate；布局坐标、分区、门廊和逻辑点候选不创建地图、入口、传送、出生点、资源或编辑器逻辑资源。","owner":"terrain-layout/layout.json"}`
- `{"name":"地图口径与白盒前置裁决","category":"map","designIntent":"把章节关系图解与可施工白盒容量分离，避免 640×416 图解被误写为地形格或运行时地图。","requiredData":["384×320 全局推理基线","224×80 天界容量","两张 96×64 公共白盒","独立会话包络","图解单位隔离"],"runtimeBehavior":"offline_preconstruction_decision；无地图、入口、传送、出生点、坐标、资源或编辑器写入。","owner":"terrain-layout/tianting-map-scale-alignment-contract.json"}`
- `{"name":"天庭 UI 与无障碍信息架构","category":"ui","designIntent":"把双通道预警、轮换快照、队伍状态、失败复盘和称号展示组织为只能展示权威结果的信息层。","requiredData":["权威预警事实","rotation_snapshot","成员状态","清理与失败原因","称号展示身份","非颜色唯一替代"],"runtimeBehavior":"offline_design；无 UI 节点、资产、音效、特效、事件、本地状态机或本地裁决。","owner":"ui/tianting-ui-accessibility-information-contract.json"}`
- `{"name":"天庭物编／美术／特效需求蓝图","category":"asset_requirements","designIntent":"在施工前把 Boss 轮廓、前摇、特效优先级和场地交互统一成跨战斗与地图的资产需求。","requiredData":["主线/七星/二十八星官/四圣覆盖","P0–P2","L0–L4","双通道前摇","场地交互职责"],"runtimeBehavior":"offline_design_requirements_only；无对象/资源 ID、单位、技能、Buff、模型、动画、特效或数值。","owner":"object-blueprint/tianting-object-art-vfx-blueprint-contract.json"}`
- `{"name":"天庭物编字段预占","category":"object_preallocation","designIntent":"将既有敌人生态、主线、七星、二十八星官与四圣细化为逻辑单位、技能壳、表现状态、投射物和声音卡，在稳定对象键与数值到位前冻结可读性和复用边界。","requiredData":["五十五张来源身份卡","三个语义技能槽","P0 空间信号","独立第二通道","反制结果","全空字段预占","P0 七道门与真实对象资源盘点"],"runtimeBehavior":"offline_field_reservation_only；没有 assets、mode、稳定对象键、copyFrom、模板、资源 ID、字段映射、绝对数值、对象、插件或运行时写入。","owner":"object-preallocation/tianting-object-field-reservation-contract.json"}`
- `{"name":"天庭敌人生态与精英职责","category":"enemy_ecology","designIntent":"把主线、七星、星宿与四圣周围的附属压力限定为可读的秩序错误、观察、净化、路线和共鸣职责，而非清场或奖励容器。","requiredData":["受保护首领身份","双通道预警","可见反制","1–4 人交接","场地阅读职责","权威与经济隔离"],"runtimeBehavior":"offline_design_requirements_only；只定义 11 类非通天塔生态身份，所有单位/对象、技能、AI、数值、波次、掉落、进度、资格和收据为空。","owner":"enemy-ecology/tianting-enemy-ecology-contract.json"}`
- `{"name":"天庭主线 Boss 深化","category":"boss_design","designIntent":"将南天门、断虹阵、四门失衡、周天观台与凌霄外庭深化为来源/关系预警、读图决策、可见反制和可复盘失败的五组首领级遭遇。","requiredData":["P0 来源与关系","独立第二通道","串行单人解","1–4 人适配","附属压力接口","既有权威会话边界"],"runtimeBehavior":"offline_design_requirements_only；不创建 Boss 单位、技能、Buff、AI、数值、波次、地图、会话写入、奖励或经济输入。","owner":"mainline-boss/tianting-mainline-boss-contract.json"}`
- `{"name":"二十八星官与四圣机制编排","category":"encounter_choreography","designIntent":"把既有星宿机制收束为普通四段、逐星官读线/提交/反制/恢复、成员流失降级与四圣固定七链的可施工语义节拍。","requiredData":["28 个 canonical 星官身份","四象 2+2+2+1","单主 P0 预算","1–4 人与 member-loss 分支","冻结会话/轮换/成员快照","净宿单调集合","核心回正候选"],"runtimeBehavior":"offline_encounter_choreography_spec；不创建 Y3/Lua 状态机、实际机制事件、phase_id/revision/cleanup_token 写入、会话完成、资格、奖励或经济。","owner":"mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json"}`
- `{"name":"主线权威运行时纵切（离线）","category":"authority_runtime_probe","designIntent":"用独立纯 Lua 白盒模型回归入章、观台、凌霄的当前生命周期、逐人、幂等和清理边界。","requiredData":["受信任 authority_provider fixture","完整绑定收据字段","1–4 人冻结成员快照","cleanup identity","Node/Fengari 注入拒绝"],"runtimeBehavior":"offline_tested_reference_only；无 Y3 API、地图根 Lua、持久化、网络、证明服务或 economy-v2 调用。","owner":"../../../implementation/tianting-authority-vertical-slice/package-contract.json"}`
- `{"name":"经济与奖励收据依赖","category":"economy","designIntent":"只登记奖励类别和用户固定的称号配方倍率，拒绝把候选内容写成运行时资源。","requiredData":["resource_table_version","owner_id","qualification_snapshot_id","encounter_instance_id","event_id","reward_slot_key","receipt_id","award_plan_hash"],"runtimeBehavior":"accepted_design_reference_runtime_not_integrated；economy-v2 可被设计引用，不能被本包调用、编译或扩容；当前只有凌霄主线成功可形成既有零价值来源事实候选，七星/星宿/噩梦仍不得进入 handoff 或结算。","owner":"成长数值与经济裁决的独立运行时实施"}`

## 内容清单

```json
{
    "heroes":  [
                   {
                       "specId":  "TT_SPEC_EXISTING_PLAYER_HERO",
                       "status":  "fixed_boundary",
                       "role":  "继承既有玩家角色；本包不新增英雄。",
                       "runtimeKey":  null
                   }
               ],
    "abilities":  [
                      {
                          "specId":  "TT_SPEC_SEVEN_STAR_MECHANIC_LANGUAGE",
                          "status":  "offline_design",
                          "role":  "定极、回环、洞微、裁衡、调和、启阙、追影是七星的机制语言，不是已实现技能。",
                          "runtimeKey":  null
                      },
                      {
                          "specId":  "TT_SPEC_FOUR_SYMBOL_MECHANIC_LANGUAGE",
                          "status":  "offline_design",
                          "role":  "青龙连线、朱雀火候、白虎围猎、玄武封镇是星宿团本机制语法，不是 Buff 或数值。",
                          "runtimeKey":  null
                      },
                      {
                          "specId":  "TT_SPEC_TIANTING_COMBAT_READABILITY_GRAMMAR",
                          "status":  "offline_design",
                          "role":  "预警、决策、反制、可复盘失败与双通道表达是天庭战斗的施工前行为语言，不是已实现能力。",
                          "runtimeKey":  null
                      }
                  ],
    "monsters":  [
                     {
                         "specId":  "TT_SPEC_MAINLINE_CONTROLLED_GUARDS",
                         "status":  "offline_design",
                         "role":  "受控天兵、天将、云兽和机关神像承接错误天律压力。",
                         "runtimeKey":  null
                     },
                     {
                         "specId":  "TT_SPEC_TWENTY_EIGHT_MANSIONS_ROSTER",
                         "status":  "offline_design",
                         "role":  "四象各七名星官的完整名单与签名动作见内容扩展合同。",
                         "runtimeKey":  null
                     },
                     {
                         "specId":  "TT_SPEC_TIANTING_ENEMY_ECOLOGY",
                         "status":  "offline_design_requirements_only",
                         "role":  "受控天兵、四门机关、失控云兽、泛称监星使与非人格机制回响是非通天塔生态职责；它们不降格首领且不含单位、波次、掉落或经济。",
                         "runtimeKey":  null
                     },
                     {
                         "specId":  "TT_SPEC_TIANTING_COMBAT_NUMERIC_UNIT_BASELINE",
                         "status":  "accepted_relative_balance_baseline_offline_only",
                         "role":  "十一类生态身份的相对耐久、压力、节拍与可读性窗口基线；不等于实际单位或 Y3 属性。",
                         "runtimeKey":  null
                     }
                 ],
    "bosses":  [
                   {
                       "specId":  "TT_SPEC_MAINLINE_BOSS_DIRECTION",
                       "status":  "offline_design",
                       "role":  "千里眼、顺风耳、巨灵神与监律天将承担主线可读性方向。",
                       "runtimeKey":  null
                   },
                   {
                       "specId":  "TT_SPEC_TIANTING_MAINLINE_BOSS_DEEPENING",
                       "status":  "offline_design_requirements_only",
                       "role":  "南天门、断虹阵、四门失衡、周天观台与凌霄外庭五组主线首领级遭遇已有阶段语法和附属压力接口；不含 Boss 对象、技能、AI、数值、地图、进度或奖励。",
                       "runtimeKey":  null
                   },
                   {
                       "specId":  "TT_SPEC_TIANTING_COMBAT_NUMERIC_UNIT_BASELINE",
                       "status":  "accepted_relative_balance_baseline_offline_only",
                       "role":  "五组主线、七星、二十八星官与四圣的相对暴露、压力、窗口和人数缩放；不生成 Boss 对象、血量或伤害字段。",
                       "runtimeKey":  null
                   },
                   {
                       "specId":  "TT_SPEC_SEVEN_STAR_BOSS_DIRECTION",
                       "status":  "offline_design",
                       "role":  "七名试炼首领分别服务七种空间规则。",
                       "runtimeKey":  null
                   },
                   {
                       "specId":  "TT_SPEC_FOUR_SACRED_NIGHTMARE_BOSSES",
                       "status":  "offline_design",
                       "role":  "青龙、朱雀、白虎、玄武与对应七宿形成双向加成终局。",
                       "runtimeKey":  null
                   },
                   {
                       "specId":  "TT_SPEC_GLOBAL_TOWER_MAJOR_BOSS_CREATIVE_ROSTER",
                       "status":  "offline_design_candidate_pending_global_tower_adoption",
                       "role":  "天庭侧候选第 10/20/30/40 层依次为四门校律使、九曜司衡官、镇塔监律使、玲珑塔灵的无数值创意身份；不创建单位、技能、AI、资产或掉落。",
                       "runtimeKey":  null
                   }
               ],
    "items":  [
                  {
                      "specId":  "TT_SPEC_SEVEN_STAR_FRAGMENT_CATEGORIES",
                      "status":  "fixed-user-requirement",
                      "role":  "七种残片与十同星残片合成对应星君称号的离线规则。",
                      "runtimeKey":  null
                  },
                  {
                      "specId":  "TT_SPEC_TIANTING_REWARD_CANDIDATES",
                      "status":  "offline_design",
                      "role":  "夜巡钥、方位宿印、星官遗契、四圣铸核与圣兽遗珍仅是候选类别。",
                      "runtimeKey":  null
                  },
                  {
                      "specId":  "TT_SPEC_SEVEN_STAR_GRADUATION_ARTIFACT",
                      "status":  "accepted_offline_design",
                      "role":  "周天校律盘是高阶可选单槽构筑收束；定序/辨序/开序只分别回应 stabilize/discern/open 的正确反制个人窗口，错配必须失效且不出回应卡；物品键、材料、配方、数值、收据和实际经济结果均保持 deferred。",
                      "runtimeKey":  null
                  }
              ],
    "maps":  [
                 {
                     "specId":  "TT_SPEC_MAINLINE_ROUTE_MAP_ROLES",
                     "status":  "offline_design_candidate",
                     "role":  "临时天庭、南天门、天宫道、天王殿、周天观台和凌霄外庭已有公共路线候选分布；实际地图仍未创建。",
                     "runtimeKey":  null
                 },
                 {
                     "specId":  "TT_SPEC_INSTANCE_SPACE_ROLES",
                     "status":  "offline_design_candidate",
                     "role":  "凌霄、七星星盘、四象阵台与四圣兽场地已有独立会话图候选尺寸和机制职责，未建地图。",
                     "runtimeKey":  null
                 },
                 {
                     "specId":  "TT_SPEC_TERRAIN_LAYOUT_DRY_RUN",
                     "status":  "offline_design_candidate",
                     "role":  "terrain-layout/layout.json 是可复现的预览布局，不是地图键、入口、传送、出生点、资源或编辑器逻辑资源。",
                     "runtimeKey":  null
                 },
                 {
                     "specId":  "TT_SPEC_TIANTING_MAP_SCALE_ALIGNMENT",
                     "status":  "offline_preconstruction_decision",
                     "role":  "640×416 为图解单位；224×80 天界容量、两张 96×64 公共白盒和独立会话包络为 dry-run 施工前口径，均无实际绑定。",
                     "runtimeKey":  null
                 }
             ],
    "ui":  [
               {
                   "specId":  "TT_SPEC_UI_AUTHORITY_BOUNDARY",
                   "status":  "fixed_boundary",
                   "role":  "UI 只展示权威章节、轮换快照、准入和结算结果，不能本地改写它们。",
                   "runtimeKey":  null
               },
               {
                   "specId":  "TT_SPEC_UI_TITLE_COLLECTION_DIRECTION",
                   "status":  "offline_design",
                   "role":  "展示七星/四圣收藏、聚合称号和独特效果方向；不创建 UI 资产。",
                   "runtimeKey":  null
               },
               {
                   "specId":  "TT_SPEC_UI_COMBAT_READABILITY",
                   "status":  "offline_design",
                   "role":  "关键机制以形状/轨迹/空间加独立声音、状态或文本表达，颜色不得作为唯一信息；UI 只展示权威状态。",
                   "runtimeKey":  null
               },
               {
                   "specId":  "TT_SPEC_TIANTING_UI_ACCESSIBILITY_INFORMATION_ARCHITECTURE",
                   "status":  "offline_design",
                   "role":  "双通道预警、轮换快照、队伍状态、失败复盘和七曜/四圣称号展示都只消费权威事实。",
                   "runtimeKey":  null
               }
           ],
    "economy":  [
                    {
                        "specId":  "TT_SPEC_ECONOMY_TIANTING_CANDIDATE_BOUNDARY",
                        "status":  "accepted_design_reference_runtime_not_integrated",
                        "role":  "只外部引用 economy-v2；当前仅凌霄主线成功可形成既有零价值来源事实候选，七星/普通星宿/噩梦星宿不得进入 handoff 或结算；不定义 XP、货币、掉率、保底、材料产出、装备或塔奖励。",
                        "runtimeKey":  null
                    },
                    {
                        "specId":  "TT_SPEC_MANSION_ECONOMY_GLOBAL_TOWER_RUN_SEASON",
                        "status":  "offline_design_candidate_pending_global_tower_adoption",
                        "role":  "待上位全局塔采纳的天庭侧 run 候选中，七星、星宿普通/噩梦、塔小 Boss、大 Boss 与完整 run 关闭均无来源事件、profile、slot、资格或收据；赛季值和掉落也保持 null/deferred。",
                        "runtimeKey":  null
                    }
                ],
    "progression":  [
                        {
                            "specId":  "TT_SPEC_PROGRESS_CHAPTER_ENTERED",
                            "status":  "offline_design",
                            "role":  "仅由 Lv41 与同角色 DF_E_YANLUO_HALL 成功交接证明共同触发的天庭入章逻辑记录；不消费 DF_PROGRESS_YANLUO_HALL_CLEARED。",
                            "runtimeKey":  null
                        },
                        {
                            "specId":  "TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN",
                            "status":  "offline_design",
                            "role":  "仅由周天观台主线节点权威成功写入，作为七星单人本的角色级重复准入门槛。",
                            "runtimeKey":  null
                        },
                        {
                            "specId":  "TT_SPEC_PROGRESS_MAINLINE_CLEARED",
                            "status":  "offline_design",
                            "role":  "仅由凌霄外庭·裂律观台的有效参与者权威成功写入，作为二十八星宿普通/噩梦的逐人门槛。",
                            "runtimeKey":  null
                        },
                        {
                            "specId":  "TT_SPEC_POST_MAINLINE_RAID_RELATION",
                            "status":  "offline_design",
                            "role":  "二十八星宿是常规主线收束后的可重复高端团队内容。",
                            "runtimeKey":  null
                        }
                    ],
    "waves":  [
                  {
                      "specId":  "TT_SPEC_MAINLINE_ENCOUNTER_FLOW",
                      "status":  "offline_design",
                      "role":  "公共路线的拆阵、救援、四门失衡和星历裂缝构成主线遭遇骨架。",
                      "runtimeKey":  null
                  },
                  {
                      "specId":  "TT_SPEC_MANSION_NORMAL_FOUR_SEGMENTS",
                      "status":  "offline_design",
                      "role":  "每个方位普通难度采用双宿、双宿、双宿、单宿的联动结构。",
                      "runtimeKey":  null
                  }
              ]
}
```

## MVP 范围

```json
{
    "mustHave":  [
                     "Lv41–60、Lv55 逐人校验、每五层休整和唯一全局塔边界。",
                     "天庭以入章、周天观台、常规完成三段离线权威进度合同承接 Lv41 阎罗殿交接证明，且不消费或写入 DF_PROGRESS_YANLUO_HALL_CLEARED。",
                     "七星固定单人本、十枚同星残片称号、七曜集合称号关系。",
                     "二十八星宿四象各七宿、十二时辰三轮轮换和权威快照边界。",
                     "普通到噩梦路径，以及七宿强化四圣、四圣庇护七宿的双向关系。",
                     "七星、主线终局、二十八星宿普通/噩梦的会话身份、清理确认、严格不重连和逐人资格合同。",
                     "二十八星官与四圣机制编排：普通四象精确 2+2+2+1、28 张读线/提交/反制/恢复卡、成员流失节拍降级与四圣同方位固定七链；机制层不改写会话、进度、资格、奖励或经济。",
                     "主线、七星、星宿与四圣的预警、决策、反制、可复盘失败、双通道可读性和 1–4 人适配。",
                     "四职业 Lv41/45/50/55/60 裸装包络、相对单位基线、共鸣系数和 1–4 人缩放，以及绝对对象字段的标定门禁。",
                     "公共路线与独立会话图的候选分布、场地职责和 dry-run 预览，同时保持无 Y3 写入。",
                     "640×416 图解、224×80 容量、两张 96×64 公共白盒和会话包络的唯一地图口径裁决。",
                     "UI 双通道预警、快照、队伍状态、失败复盘和称号展示的信息架构，以及无本地裁决约束。",
                     "Boss 轮廓、前摇、特效层级和场地交互的无 ID 资产需求蓝图。",
                     "受信任 Node/Fengari 离线基座对入章、观台、凌霄逐人完成、当前生命周期、回放字段和清理身份的回归。",
                     "待上位全局塔采纳的天庭侧四十层、八段五拍、每五层 Boss 槽、四个十层大 Boss 创意身份与第八段禁止继续交接的离线候选。",
                     "周天校律盘的高阶可选单槽定位、五段玩家路径、定序／辨序／开序与 stabilize/discern/open 的一对一个人回应、前序法宝保留、单人基础毕业保护、来源证据与失败优先级。",
                     "经济候选、通天塔复用和运行时施工的严格隔离。"
                 ],
    "shouldHave":  [
                       "七星/四圣称号的作用域、叠加、展示位和持久化裁决。",
                       "周天校律盘的实际材料键、数量、配方、扣除、珍贵材料结算来源与属性裁决。",
                       "七星/四圣称号的 UI 展示资产、周天校律盘的实际配方、珍贵材料收据、属性与对象绑定裁决。"
                   ],
    "later":  [
                  "候选布局之外的真实地图、对象、战斗数值、地图根 Lua、UI、存档、多人与性能施工。",
                  "全局塔实例、楼层地图、内容抽取、词缀、记录、失败恢复和季节服务。",
                  "economy-v2 的权威编译、持久化收据、证明解析和实际奖池接入。"
              ]
}
```

## 后续 Skill 交接包

```json
{
    "objectConfig":  [
                         "handoff/object-config-brief.json、object-blueprint/tianting-object-art-vfx-blueprint-contract.json、object-preallocation/tianting-object-field-reservation-contract.json、mansion-orchestration/tianting-mansion-encounter-orchestration-contract.json、enemy-ecology/tianting-enemy-ecology-contract.json、mainline-boss/tianting-mainline-boss-contract.json、combat-baseline/tianting-combat-numeric-unit-baseline-contract.json 与 implementation/combat-calibration：先用五十五张逻辑卡冻结声音／投射物／表现状态、技能壳、单位／机制体和遭遇组装，再等待稳定对象键、模板、真实字段盘点与 P0 七道绝对投影门禁逐项采纳；当前不得生成 assets、mode、插件或实际物编。"
                     ],
    "terrainLayout":  [
                          "handoff/terrain-layout-brief.json、terrain-layout/layout.json、scale-alignment/、mansion-orchestration/、enemy-ecology/、mainline-boss/、implementation/tianting-y3-construction-preflight 与 implementation/tianting-surface-construction-manifest：提供公共路线、五组主线首领级遭遇、七星星盘、四象阵台和四圣兽场地的读线职责；640×416 图解与 224×80/96×64 白盒口径均只供 dry-run，先经真实项目读取与结构预检，不含实际地图写入。"
                      ],
    "luaLogic":  [
                     "authority/tianting-progression-and-instance-authority-contract.json、主线纵切离线包、七星/星宿会话离线参考包、mansion-orchestration/、artifact-graduation/complete-design/、implementation/tianting-y3-construction-preflight、combat/、combat-baseline/、implementation/combat-calibration、enemy-ecology/、mainline-boss/ 与 handoff/lua-logic-brief.md：明确权威进度、当前生命周期、字段漂移、会话/清理、注入时辰、表现职责、周天校律盘的单槽／挑战锁／形态—标签一对一回应窗口／错配失效／零经济边界、P0 绝对字段门禁和真实 Y3 根预检；参考包只作进程内测试，不含 Y3 地图根 Lua 或绝对属性写入。"
                 ],
    "uiPipeline":  [
                       "handoff/ui-brief.md、ui/tianting-ui-accessibility-information-contract.json、mansion-orchestration/、mainline-presentation/ 与 implementation/tianting-surface-construction-manifest：描述轮换、队伍状态、失败复盘、称号收藏、双通道预警、星宿机制编排、五组主线表现职责、权威展示边界和未来 UI 根读取项；不含 UI 资产、节点或运行时命令写入。"
                   ],
    "reviewPanel":  [
                        "handoff/review-brief.md、mansion-orchestration/、artifact-graduation/complete-design/：复审用户固定内容、跨篇禁令、经济隔离、时间/赛季快照、战斗可读性、相对数值基线、P0 绝对标定协议、敌人生态、主线 Boss 深化、二十八星官/四圣机制编排、周天校律盘的单槽／来源证据／防双花／形态—标签一对一回应窗口、七星/星宿会话离线回归、主线叙事表现、白盒口径、纵切回归、Y3 结构预检、表面发现清单与施工门禁。"
                    ]
}
```

## 风险与未决项

```json
{
    "risks":  [
                  {
                      "id":  "TT-RISK-001",
                      "risk":  "旧“蟠桃园/御马监二选一”或“凌霄团队本”口径残留，与用户已选七星/星宿形成双重终局。",
                      "mitigation":  "显式记录七星为固定单人系列、星宿为最高端团队本；凌霄仅为常规主线收束。"
                  },
                  {
                      "id":  "TT-RISK-002",
                      "risk":  "时辰轮换由客户端或副本中途时间决定，造成队伍看到不同方位。",
                      "mitigation":  "入场由未来权威时间源冻结 rotation_snapshot，副本生命期内不可换宿。"
                  },
                  {
                      "id":  "TT-RISK-003",
                      "risk":  "把十枚称号倍率、夜巡钥或材料候选误写成现有经济资源/掉落数值。",
                      "mitigation":  "仅保留离线类别和用户指定配方倍率；资源表绑定、掉率、数量、保底和收据全部 deferred。"
                  },
                  {
                      "id":  "TT-RISK-004",
                      "risk":  "噩梦变成八单位血量膨胀，七宿机制在四圣兽战中失去意义。",
                      "mitigation":  "强制逐链净宿，只有解除七宿—四圣双向共鸣后才进入终局窗口。"
                  },
                  {
                      "id":  "TT-RISK-005",
                      "risk":  "把待采纳的四十层离线槽位误作全局已冻结地图/实例，或允许第八段 REST 后继续进入第九段，导致首轮状态语义与完整 run 分叉。",
                      "mitigation":  "只允许循环 1–7 的 NEXT_CYCLE_HANDOFF；第八段禁交接，经既有终局关闭；槽位不改状态/转移、不生成 runtime floor key、掉落或记录。"
                  },
                  {
                      "id":  "TT-RISK-006",
                      "risk":  "把候选分区、坐标、会话门廊或预览图误认为已创建的 Y3 地图、入口、传送或编辑器资源。",
                      "mitigation":  "所有布局工件均标为 offline dry-run candidate；实际写入前必须重新读取当前地图与资源并获得明确确认。"
                  },
                  {
                      "id":  "TT-RISK-007",
                      "risk":  "高密度特效、颜色复用或装饰遮挡让玩家无法读出预警、目标归属和反制路线。",
                      "mitigation":  "强制形状/轨迹/空间与独立辅助的双通道可读性，场地优先保证观察、反制、退路和 1–4 人处理路径。"
                  },
                  {
                      "id":  "TT-RISK-008",
                      "risk":  "将附属敌人、精英或机制回响做成独立清场 KPI，遮挡 P0 信息，或降格复用主线首领、七星首领、二十八星官与四圣兽。",
                      "mitigation":  "生态和首领深化合同均要求附属压力只放大既有来源、关系和反制；受保护首领身份不可复用，且所有单位、波次、掉落和经济绑定保持未施工。"
                  },
                  {
                      "id":  "TT-RISK-009",
                      "risk":  "在缺少技能循环、长期养成、伤害公式、动作帧和场地回放时，把相对系数误投影为 Y3 原始 HP、伤害或秒数。",
                      "mitigation":  "数值合同只接受无量纲系数和裸装参照；所有绝对字段必须等待完整标定门禁，不得绕过对象键与实机回放。"
                  }
              ],
    "unresolved":  [
                       "天庭逻辑进度、会话身份、可信时间基准和资格凭证的真实运行时键、持久化、提供方接入与迁移。",
                       "候选布局之外的真实地图绑定、地图键、入口/传送、出生点、对象、AI、技能、原始战斗属性/秒数、检查点、失败/清理/重连与多人同步。",
                       "镜头高度、缩放、性能预算、无障碍表现、真实地形/碰撞/寻路和官方资源绑定。",
                       "可信时间提供方的真实部署、维护窗口、异常回退与跨服务时钟对账。",
                       "七星/星宿/四圣材料、夜巡钥、称号、毕业法宝的资源表、所有权、收据、掉率、保底、数量和属性。",
                       "集合称号最终名称、效果作用域与实际叠加规则。",
                       "敌人生态与主线 Boss 的实际对象名册、技能/Buff、AI、波次/刷新、绝对值、性能、地图/出生点和施工资产绑定。",
                       "通天塔实际全局 run 服务、楼层地图/实例、内容抽取、词缀、记录、失败恢复、季节服务、掉落来源、资格、收据与奖励。"
                   ]
}
```

## 验收标准

- 规格精确声明天庭等级带为 Lv41–60，且不新增经验阈值或升级时长。
- 规格精确声明通天塔 Lv55 逐人校验与每五层休整，且不建立第二座长期塔。
- DF_PROGRESS_YANLUO_HALL_CLEARED 被声明为禁止默认消费或写入的受保护跨篇键。
- 入章只验证同角色、源自 DF_E_YANLUO_HALL 的权威交接证明与 Lv41，不能把该证明替换为客户端布尔、队长进度或受保护键读取。
- 入章、周天观台和常规完成各有唯一生产者、统一收据字段与 (actor_id,event_id) 幂等；所有实际运行时键保持 null。
- 七星名称、残片名称、星君称号、十枚同星配方倍率和七称号自动聚合关系完整。
- 七星的机制语法与展示方向彼此不同，集合称号不会与单称号重复叠加。
- 二十八星官正好四象各七名，均有签名动作、预警和反制方向。
- 二十八星官与四圣机制编排精确覆盖普通四象 2+2+2+1、28 张读线/提交/反制/恢复卡、权威成员元组降级、普通/噩梦只读终局候选及不可跳段、不可倒退的语义允许边；机制层不得改写会话、进度、资格、奖励或经济。
- 十二时辰精确覆盖三轮四象，Asia/Shanghai 权威快照锁定方位，客户端时间、方位与重试不可改写实例。
- 普通通关到噩梦钥候选的路径明确；噩梦中七宿强化四圣、四圣庇护七宿，并以逐链净宿建立终局窗口。
- 二十八星宿普通与噩梦逐人校验常规完成；噩梦逐人校验同方位资格，断线成员不可重连或领奖。
- 奖励只登记类别和用户指定称号倍率，不出现实际掉率、数量、保底、货币、属性或运行时资源键。
- 天庭侧已提出四十层、八段五拍、每五层 Boss 槽和第 10/20/30/40 层四个大 Boss 创意身份；它仍待上位全局塔采纳，第八段禁交接也不产生运行时楼层、掉落、记录或赛季值。
- 所有天庭局部内容使用 TT_SPEC_ 身份并保持 runtimeKey 为 null。
- 战斗规格覆盖主线、七星、普通星宿与四圣噩梦的预警、决策、反制、复盘和一至四人路径，且颜色不是唯一关键信息。
- 战斗数值合同精确覆盖四职业 Lv41/45/50/55/60 裸装参照、八个无量纲标尺、既有单位身份、七宿—四圣相对共鸣和 1–4 人缩放；原始对象字段、秒数和经济仍为空。
- 候选公共路线、七星七张、四方普通、四方噩梦和凌霄会话图均有空间职责，但布局保持 preview/dry-run，未写入 Y3。
- 当前仅凌霄主线成功可进入既有零价值来源事实候选；七星、普通星宿、噩梦星宿、塔小 Boss、大 Boss 与完整 run 关闭均不得形成 handoff candidate、资格或结算输入。
- 11 类非通天塔敌人生态都只表达职责、预警、反制与首领护栏；不得产生单位、波次、掉落、资格、进度、收据或经济输入。
- 五组主线首领级遭遇均具备 P0 来源/关系、独立第二通道、串行单人解、1–4 人适配、可见反制和可复盘失败；附属压力不得遮挡 P0 或越权写入会话、进度、奖励或结算。
- 七星与星宿会话参考模型只能以注入、进程内数据复核既有权威合同；它们不得创建真实进度、时间、成员、资格、会话、奖励、收据或 economy-v2 输入。
- 五组主线 Boss 的叙事与表现深化恰好保留三段锚点、双通道预警、失败复盘、非经济确认和 L0–L4 表现职责；它不能裁决权威事实或绑定任何实际资产。

## 下一步建议

- 先确认未决项，避免把关键设定、数值或资源 ID 硬编进后续产物。
- 用 y3-review-panel 对结构化规格进行多角度评审。
- 用 y3-object-config 继续规范化英雄、怪物、物品、技能等物编内容。
- 用 y3-terrain-layout 继续推导地图尺寸、分区、路线和刷怪点。
- 用 y3-lua-api 继续拆解运行时逻辑、事件、奖励和同步风险。
- 用官方 y3-ui-pipeline 继续制作 UI 面板与 Lua 绑定需求。
