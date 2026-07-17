# Y3 设计规格报告

## 一句话项目定位

为 Lv1-Lv60 的长期成长建立可追溯的经验、经济、奖励资格、掉落收据与数值标定边界；先固定审计和公平契约，再由采纳后的数据表驱动 Y3 子会话结算。

## Y3 适配性判断

```json
{
    "camera":  "Y3 2.5D 俯视角",
    "sessionType":  "公共地图中的存档制游玩会话；野外、副本与通天塔为可重复的权威子会话",
    "targetPlayers":  "1-4 人",
    "targetDurationMinutes":  0
}
```

## 核心循环

```json
{
    "shortLoop":  "在 10-60 秒内完成战斗或遭遇行为，记录可复核的伤害、破韧、护守或机制证据。",
    "midLoop":  "在 2-8 分钟内完成野外、公共 Boss、单人本或团队本，并以个人资格快照结算经验、材料或可见进度。",
    "longLoop":  "在三篇成长、装备/法宝养成、收集和通天塔之间循环；每一类长期收益都受版本化资源表、角色归属和幂等收据约束。",
    "rewards":  [
                    "等级与自由技能点",
                    "装备、材料与法宝进度",
                    "个人主线、收集和首通资格",
                    "通天塔长期目标",
                    "可审计的非稀有与稀有结算结果"
                ]
}
```

## 单局流程

- `{"phase":"角色读取与版本确认","duration":"0-2 分钟","playerGoal":"读取角色等级、构筑、长期物品与资源表版本。","systemsUsed":["character state","resource table version","receipt ledger"],"successCriteria":"重连或重复初始化不复制长期属性、货币、材料、保底或奖励。"}`
- `{"phase":"花果山基础战斗","duration":"0-5 分钟","playerGoal":"完成普通怪和精英战斗，获得可见但尚待校准的经验与掉落反馈。","systemsUsed":["experience source policy","HG_DROP profile","qualification evidence"],"successCriteria":"白盒 reward_exp 不能被当作生产经验，所有奖励来源可追溯。"}`
- `{"phase":"职业路线与升级锚点","duration":"5-15 分钟","playerGoal":"推进 Lv8 核心路线、理解技能点和龙宫入口提示。","systemsUsed":["level progression","skill budget","private route completion"],"successCriteria":"经验表在采纳前不实现；已采纳的 Lv8 门槛不被经济数据绕过。"}`
- `{"phase":"公共 Boss 贡献与个人结算","duration":"15-40 分钟","playerGoal":"通过伤害、破韧、护守或公共行为获得个人推进，并理解参与箱与稀有资格分离。","systemsUsed":["public qualification","encounter origin/window","settlement receipt"],"successCriteria":"DPS 荣誉、个人推进、参与箱、稀有资格和保底不可互相隐式推导。"}`
- `{"phase":"副本、强化与长期资源","duration":"花果山后段至 Lv60","playerGoal":"从单人本、团队本和主城循环中取得装备、材料、法宝进度并安全强化或进阶。","systemsUsed":["item growth","currency ledger","drop and pity"],"successCriteria":"没有已采纳数值、版本和收据前，任何掉落 profile 继续保持 deferred。"}`
- `{"phase":"通天塔验证","duration":"Lv55 后","playerGoal":"使用已合法取得的长期成长挑战更高层。","systemsUsed":["tower gate","tower reward policy","loadout lock"],"successCriteria":"任何成员低于 Lv55 被拒绝；塔奖励、词缀与赛季在采纳前不伪装为已实现。"}`

## 系统拆分

- `{"name":"经验曲线与来源结算","category":"progression","designIntent":"将 Lv1-Lv60 的章节成长和来源权重交给版本化数据表，而非怪物白盒字段。","requiredData":["xp_to_next","cumulative_xp","source weights","party qualification","party distribution","level difference","death and reconnect rules","event receipt"],"runtimeBehavior":"权威端仅在已采纳的资源表下授予经验，并以角色、事件、来源和版本去重。","owner":"数值裁决后交给 y3-lua-api；当前仅规格数据"}`
- `{"name":"装备、法宝、宠物和材料成长","category":"economy","designIntent":"在既定五品质、强化、进阶、合成和宠物资产边界上，逐步确定可审计的长期成长。","requiredData":["slots","profession limits","base stats","affixes","strengthen and advance","recipes","material throughput","duplicate conversion","storage and migration"],"runtimeBehavior":"强化、进阶、合成和孵化必须以物品谱系、材料收据和原子事务结算。","owner":"数值裁决后交给 y3-object-config 与 y3-lua-api"}`
- `{"name":"货币账本与结算收据","category":"economy","designIntent":"让货币、材料、保底、roll 和消耗都有角色归属、版本、事件和可重放的原结果。","requiredData":["currency keys","owner scope","balance cap","sources","sinks","receipt identity","migration","cleanup policy"],"runtimeBehavior":"同一收据重放只返回原结算，不二次改变余额、材料、保底或消耗。","owner":"数值裁决后交给 y3-lua-api"}`
- `{"name":"公共 Boss 资格、掉落与保底","category":"economy","designIntent":"将荣誉、个人推进、参与箱、稀有资格、保底和 roll 保持分层，并消除参与箱 P1 双口径。","requiredData":["qualification snapshots","final participation chest policy","rare rule","drop tables","pity pools","duplicate rules","resource table version","receipt policy"],"runtimeBehavior":"公共行为按 origin/window、event_id 和 occurrence 去重；primary/assist 不直接改变任何奖励资格。","owner":"数值裁决后交给 y3-lua-api；花果山 manifest 仅在 P1 采纳后同步"}`
- `{"name":"通天塔长期奖励","category":"progression","designIntent":"以逐人 Lv55 门槛锁定入口，再由独立规则决定层数、词缀、首通/重复奖励与赛季。","requiredData":["record scope","floor plan","affix pool","first clear","repeat rewards","tower currency","season policy"],"runtimeBehavior":"入口逐人校验；奖励在版本化资源表批准前不产生实际结算。","owner":"数值裁决后交给 y3-lua-api、y3-terrain-layout 和官方 y3-ui-pipeline"}`
- `{"name":"零付费经济门禁","category":"monetization","designIntent":"禁止通过商品、价格、概率或便利字段改变角色强度、成长速度、资格、掉率、保底或塔门槛。","requiredData":["30/60/90 minute free-play samples","combat BAL logs","resource throughput","public Boss fairness logs"],"runtimeBehavior":"所有未登记或影响成长公平的商业字段被拒绝，不存在付费绕过经济结算的路径。","owner":"多维评审"}`

## 内容清单

```json
{
    "heroes":  [
                   "C01 破妄",
                   "C02 镇界",
                   "C03 持明",
                   "C04 巡猎"
               ],
    "abilities":  [
                      "四职业技能点、绝技和构筑均受既有成长基线约束",
                      "职业战斗日志是后续装备与经验数值标定的输入，不是由经济表替代"
                  ],
    "units":  [
                  "花果山普通怪、精英、公共 Boss、龙宫 Boss、牛魔旧战场 Boss",
                  "现有单位 reward_exp 仅为白盒校准输入"
              ],
    "monsters":  [
                     "花果山怪物和 Boss 等级带",
                     "后续地府与天庭来源表"
                 ],
    "bosses":  [
                   "猕猴王、蛟魔王、鲨魔王",
                   "龙王旧潮与逆潮",
                   "牛魔旧战场",
                   "通天塔 Boss"
               ],
    "items":  [
                  "装备",
                  "强化石与进阶石",
                  "Boss 材料",
                  "法宝",
                  "龙蛋",
                  "宠物材料"
              ],
    "waves":  [
                  "通天塔波次、楼层和词缀需要独立资源表"
              ],
    "maps":  [
                 "花果山公共野外、龙宫、牛魔旧战场",
                 "地府和天庭成长区域",
                 "通天塔"
             ],
    "ui":  [
               "等级经验",
               "货币与材料",
               "掉落结算收据",
               "参与资格反馈",
               "保底与资源表版本说明",
               "通天塔奖励"
           ],
    "economy":  [
                    "候选 CUR_GOLD、CUR_TOWER_TOKEN、CUR_RAID_MARK",
                    "版本化 currency ledger、drop receipt、pity progress",
                    "HG_DROP 来源键全部 deferred",
                    "公共 Boss 参与箱 P1 的两条现存口径与第三候选均待唯一政策采纳"
                ],
    "progression":  [
                        "Lv1-Lv60 三篇成长",
                        "装备、法宝、宠物、收集与塔层长期目标",
                        "经验表、装备数值和塔奖励尚待数值裁决"
                    ],
    "monetization":  [
                         "成长强度和速度禁止商业化",
                         "零付费 30/60/90 分钟样本是未来经济表启用门禁"
                     ]
}
```

## MVP 范围

```json
{
    "mustHave":  [
                     "唯一的决策登记册和数值/经济分域数据表",
                     "经验、货币、掉落、保底、资格和收据的状态语义",
                     "禁止白盒候选、冲突口径和未采纳提案进入 runtime_handoff 的校验",
                     "公共 Boss 四资格分层与 P1 冲突可追溯"
                 ],
    "shouldHave":  [
                       "主策裁决经验、参与箱唯一政策、货币归属和收据迁移提案",
                       "基于已采纳数据生成 implementation/growth 离线预检包",
                       "从花果山开始做无白盒泄漏的资源表切片",
                       "用 30/60/90 分钟零付费样本验证节奏和资源吞吐"
                   ],
    "later":  [
                  "完整 Lv1-Lv60 数值表与战斗日志标定",
                  "装备、法宝、宠物、塔奖励和赛季的生产数据",
                  "真实 Y3 对象、Lua、UI、地图绑定和多人实机验证"
              ]
}
```

## 后续 Skill 交接包

```json
{
    "objectConfig":  [
                         "仅在装备/法宝/材料/宠物的稳定键、部位、数值、配方和真实 Y3 资源已采纳并回读后，生成 item 或 pet unit/ability 配置。",
                         "货币账本、掉落 profile、保底和收据不生成物编对象。"
                     ],
    "terrainLayout":  [
                          "为三篇等级引导、公共 Boss 行为窗、龙宫与塔入口保留可读的奖励来源提示。",
                          "地形不裁决经验、概率、保底、货币或参与箱资格。"
                      ],
    "luaLogic":  [
                     "在决策采纳后实现版本化经验授予、资格快照、结算收据、货币账本、保底和迁移。",
                     "重放、断线、跨资源表版本、资格伪造和 primary/assist 误用必须有拒绝路径。"
                 ],
    "uiPipeline":  [
                       "展示等级、货币、材料、参与资格、掉落结果、保底进度和塔奖励。",
                       "UI 只能展示权威收据和发起请求，不能本地授予成长或奖励。"
                   ],
    "reviewPanel":  [
                        "复审经验节奏、公共 Boss 公平、零付费路径、掉落/保底、迁移和资源吞吐。",
                        "首先裁决 ECO-P1-001、ECO-XP-001、ECO-LEDGER-001 和 ECO-LEDGER-002。"
                    ]
}
```

## 风险与未决项

```json
{
    "risks":  [
                  "将 reward_exp、reward_official_res_1 或 HG_DROP 名称直接接入生产会错误冻结经济。",
                  "参与箱 P1 存在 OR 与 AND 的冲突；在唯一 final_policy_id 前任何发箱都不安全。",
                  "没有版本化收据时，断线、重放与资源表更新会产生双结算或保底丢失。",
                  "装备、法宝和宠物的数值如果先于职业战斗日志确定，会破坏四职业统一平衡。",
                  "未通过零付费样本的便利或商业字段会破坏公平门禁。"
              ],
    "unresolved":  [
                       "项目级目标游玩会话时长。",
                       "Lv1-Lv60 经验阈值、来源权重、组队分配、级差、死亡和重连规则。",
                       "装备部位、职业限制、词条、强化/进阶/套装、材料吞吐和重复转化。",
                       "法宝/宠物槽位、配方、孵化、绑定、成长与数值。",
                       "参与箱 P1 的唯一 final_policy_id。",
                       "货币最终稳定键、余额上限、来源、消耗、兑换、保留期和迁移期限。",
                       "掉率、稀有资格、保底阈值、重复收益和团队分配。",
                       "通天塔记录、楼层、词缀、奖励、最终层数和赛季。",
                       "独立全角色境界系统是否存在。"
                   ]
}
```

## 验收标准

- 所有 JSON 可解析，设计规格结构验证通过，唯一预期结构警告是未知项目会话时长。
- 决策登记册中的 decision_id 唯一；每个表项均能回溯到登记册决策。
- proposal、deferred、conflict 和 whitebox-candidate 的 effective_value 保持 null，runtime_handoff 保持 false。
- 任何 accepted-baseline 条目都有当前基线来源；本包不把草案写成已采纳。
- 所有 HG_DROP profile 在资源表、资格、版本和收据策略采纳前保持 deferred。
- 公共资格四分保持独立，participation_chest_eligibility 在 final_policy_id 为空时不可能启用。
- 每个未来收据需要角色归属、资格快照、事件、来源、奖励槽、版本和幂等重放规则。
- 白盒 reward_exp、资源字段、刷新周期和旧建议区间不被当成正式经济数值。
- 零付费 30/60/90 分钟样本、公共 Boss 公平日志和职业 BAL 日志是生产资源表的启用门禁。

## 下一步建议

- 先确认未决项，避免把关键设定、数值或资源 ID 硬编进后续产物。
- 用 y3-review-panel 对结构化规格进行多角度评审。
- 用 y3-object-config 继续规范化英雄、怪物、物品、技能等物编内容。
- 用 y3-terrain-layout 继续推导地图尺寸、分区、路线和刷怪点。
- 用 y3-lua-api 继续拆解运行时逻辑、事件、奖励和同步风险。
- 用官方 y3-ui-pipeline 继续制作 UI 面板与 Lua 绑定需求。
