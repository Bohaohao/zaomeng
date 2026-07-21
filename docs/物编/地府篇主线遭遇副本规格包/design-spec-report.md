# Y3 设计规格报告

## 一句话项目定位

承命者进入轮回失序的幽冥，在鬼城与十司冲突中恢复命册秩序；常规篇章以阎罗殿收束，白骨秘境为不阻塞主线的可选单人挑战，转轮殿承载不替代主线完成的团队终局。

## Y3 适配性判断

```json
{
    "camera":  "2.5D俯视角",
    "sessionType":  "单局常规章节完成会话；白骨与转轮为独立内容轨道",
    "targetPlayers":  "公共路线支持多人；阎罗殿为非团队常规最终副本；转轮殿最多 4 人团队本",
    "targetDurationMinutes":  0
}
```

## 核心循环

```json
{
    "shortLoop":  "在鬼城至审判节点的公共路线中识别敌群主题、处理位置与协作压力，并获得下一叙事节点的明确方向。",
    "midLoop":  "通过官署冲突与判官审判理解轮回失序的原因，推进至非团队常规最终副本阎罗殿。",
    "longLoop":  "以阎罗殿的权威完成结果收束地府常规篇章；白骨秘境始终作为可选、并行、非阻塞的单人挑战，转轮殿作为阎罗叙事收束后的独立团队内容轨道且入口前置保持 deferred，不以阎罗完成键推导或声明入口；同一角色 Lv38 时，花果山龙宫逆潮才消费受信任完成键查询。",
    "rewards":  [
                    "叙事推进与章节完成回执",
                    "由 economy-v2 后续地府 source_profile 分配表决定的未来奖励来源类别",
                    "团队内容与后续长期挑战的目标感"
                ]
}
```

## 单局流程

- `{"phase":"鬼城入城","duration":"未定","playerGoal":"理解轮回司、鬼城安全区与公共路线的章节职责。","systemsUsed":["章节入口","叙事引导","公共路线"],"flow_track":"chapter_completion","flow_role":"chapter_entry","successCriteria":"玩家能明确进入第一段公共冲突，而非被直接投放到副本或团队会话。"}`
- `{"phase":"无常巷与鬼门关","duration":"未定","playerGoal":"从双目标、守卫和关隘压力理解失控鬼差造成的秩序阻塞。","systemsUsed":["公共遭遇主题","协同与位置决策"],"flow_track":"chapter_completion","flow_role":"route_escalation","successCriteria":"玩家获得通往官署审判节点的因果目标，不把参考主题误解为已实现团队副本。"}`
- `{"phase":"接引院与判官殿","duration":"未定","playerGoal":"发现命册与审判体系被扭曲，面对控制、判定和负面状态主题，并从档案与审判中理解转轮一系的重置企图。","systemsUsed":["叙事检查点","遭遇主题","构筑适应"],"flow_track":"chapter_completion","flow_role":"narrative_setup","successCriteria":"中段揭示将常规冲突升级为必须进入阎罗殿处理的命册问题，并以非门槛叙事伏笔承接转轮的重置企图。"}`
- `{"phase":"阎罗殿常规最终","duration":"未定","playerGoal":"在非团队副本中完成命册冲突的常规篇章高潮。","systemsUsed":["非团队常规最终副本","权威完成收据","角色级进度"],"contract_spec_id":"DF_NODE_YANLUO_HALL","flow_track":"chapter_completion","flow_role":"completion_final","successCriteria":"仅权威成功事件按 actor_id 与 event_id 幂等写入 DF_PROGRESS_YANLUO_HALL_CLEARED。"}`

## 系统拆分

- `{"system":"章节因果与内容分轨","designIntent":"保留鬼城到转轮殿的参考素材顺序，同时将常规完成会话、可选并行白骨单人本与独立转轮团队内容显式拆开。","requiredData":["十个 spec-local 节点与白骨秘境的固定 spec-local 单人副本角色（optional_parallel_nonblocking、非路线节点）","参考顺序","常规完成路径","固定团队终点及其 deferred 入口与路线","白骨与转轮的独立 parallelContentFlows"],"runtimeBoundary":"不生成地图库、入口条件或物理连接。","downstreamOwner":"y3-terrain-layout（真实地图工程存在后）"}`
- `{"system":"阎罗殿跨篇完成","designIntent":"使非团队常规最终副本成为唯一可信完成键生产者。","requiredData":["DF_E_YANLUO_HALL","DF_PROGRESS_YANLUO_HALL_CLEARED","actor_id 与 event_id 幂等收据"],"runtimeBoundary":"本包仅引用现有接口，不实现持久化或完成事件。","downstreamOwner":"y3-lua-api（地图根与持久化方案明确后）"}`
- `{"system":"转轮殿团队清理","designIntent":"复用统一团队会话、死亡回传与匹配清理确认，而不将死亡回城误解为重入解锁。","requiredData":["DF_E_ZHUANLUN_HALL","TEAM_INSTANCE_RETURN_TO_CHAPTER_INITIAL_SPAWN_V1","raid_instance_id、session_epoch、cleanup_token"],"runtimeBoundary":"不实现副本状态机、传送、清理或多人同步。","downstreamOwner":"y3-lua-api（团队运行时开工后）"}`
- `{"system":"遭遇主题目录","designIntent":"将鬼灯、无常、关隘、审判、魂河、桥面、梦境与轮回重置组织为可评审的主题，不偷渡为单位或技能对象。","requiredData":["spec-local 节点","主题标签","来源追踪"],"runtimeBoundary":"不含单位模板、能力、波次、刷怪、伤害、状态时长或数值。","downstreamOwner":"y3-object-config 与 y3-lua-api（前置决策和地图回读后）"}`
- `{"system":"成长与经济隔离","designIntent":"地府内容只声明奖励来源类别；economy-v2 已冻结全局曲线/账本/收据边界，但未分配地府 profile，任何生产结算仍被禁止。","requiredData":["来源类别","成长裁决包引用"],"runtimeBoundary":"不生成经验、货币、物品、掉率、保底或资格规则。","downstreamOwner":"成长数值与经济裁决包"}`

## 内容清单

```json
{
    "heroes":  [

               ],
    "abilities":  [

                  ],
    "units":  [

              ],
    "monsters":  [
                     "鬼灯、尸怪、失控鬼差、牛头马面和花妖仅作为遭遇主题标签；本轮不建立单位记录。"
                 ],
    "bosses":  [
                   "白骨精、阎罗王与转轮王仅保留章节/副本职责和多形态或多阶段主题；本轮不建立 Boss 对象、技能或数值。"
               ],
    "items":  [

              ],
    "waves":  [

              ],
    "maps":  [
                 "鬼城、公共路线、阎罗殿、可选并行白骨秘境与独立转轮团队内容均以逻辑拓扑表达；不含坐标、尺寸、资源键或真实地图绑定。"
             ],
    "ui":  [
               "章节入口、非团队常规最终状态、团队成员锁/清理提示和 deferred 内容提示仅作为未来 UI 需求。"
           ],
    "economy":  [

                ],
    "progression":  [
                        "DF_PROGRESS_YANLUO_HALL_CLEARED：角色级 chapter_unlocks 键，仅由 DF_E_YANLUO_HALL 的受信任成功回执幂等写入。",
                        "HG_E_DRAGON_REVERSE_TIDE：同一角色至少 Lv38 且受信任查询命中 DF_PROGRESS_YANLUO_HALL_CLEARED 后放行；本包不实现该消费者。"
                    ],
    "monetization":  [

                     ]
}
```

## MVP 范围

```json
{
    "mustHave":  [
                     "十个地府节点与白骨秘境独立单人副本角色的 spec-local 内容卡、来源追踪、状态分层，以及 optional_parallel_nonblocking 关系",
                     "阎罗殿非团队常规最终与转轮殿团队本的固定职责",
                     "常规完成路径、参考顺序、固定团队终点及其 deferred 入口/路线的明确区分",
                     "不含坐标的逻辑拓扑、章节初始出生点回读清单和成长经济隔离边界",
                     "跨篇契约、花果山消费者与团队清理合同的静态回归校验"
                 ],
    "shouldHave":  [
                       "未来对象、地图、Lua、UI 与评审的无代码交接简报",
                       "历史文档中已过期的地府团本候选标注与索引修正"
                   ],
    "later":  [
                  "真实地图拓扑、坐标、出生点和资源回读",
                  "地府单位、Boss、技能、波次、对象和副本运行时",
                  "地府奖励、掉落、经验、货币与保底的 source_profile 分配，以及 economy-v2 的运行时账本/证明解析接入",
                  "持久化、多人实机、Y3 编辑器与 UI 交付"
              ]
}
```

## 后续 Skill 交接包

```json
{
    "objectConfig":  [
                         "成长经济以已采纳的 economy-v2 设计基线为引用；待真实地图工程与后续权威运行时接入完成后，再将主题标签转换为可审阅的单位、Boss、技能和物品资产；本轮不分配对象或 ID。"
                     ],
    "terrainLayout":  [
                          "真实地图工程出现后，以鬼城安全区、公共路线、阎罗殿、可选并行白骨秘境、独立转轮团队内容和 chapter_initial_spawn 逻辑角色为输入进行地图布局；不得从本包猜测坐标、尺寸、资源键或未裁决入口关系。"
                      ],
    "luaLogic":  [
                     "地图根、持久化与同步边界确认后，实现阎罗殿完成收据、转轮殿成员锁/清理确认和受信任查询；不得以客户端布尔值或队友进度替代。"
                 ],
    "uiPipeline":  [
                       "未来 UI 需展示章节入口、常规最终完成状态、团队成员锁与清理提示；UI 只能请求或展示权威结果。"
                   ],
    "reviewPanel":  [
                        "复审常规终点与团队终局的双轨叙事、遭遇主题可读性、范围边界、成长经济隔离与跨篇键不外溢。"
                    ]
}
```

## 风险与未决项

```json
{
    "risks":  [
                  "参考资料把转轮殿置于顺序末端，而当前基线已将阎罗殿定为常规最终副本；必须持续保持双轨表达。",
                  "若把白骨秘境或转轮殿重新串入常规 sessionFlow，会凭数组顺序伪造未批准的完成门槛或入口关系。",
                  "任何将阎罗完成键复用于转轮、忘川、奈何或望乡内部入口的做法都会扩张既有跨篇接口。",
                  "团队死亡、全灭、超时与离场的细节必须依赖既有会话合同和花果山行为回归，静态镜像检查不能冒充运行时证明。",
                  "地图白盒如果被误读为物理施工，会导致无资源回读情况下的坐标、规模和性能假设。",
                  "魂石、法宝材料和抗性装备只能作为题材来源，不得绕过成长裁决包生成生产经济内容。"
              ],
    "unresolved":  [
                       "地府真实地图根、章节初始出生点、传送/副本入口资源、坐标和地形尺寸。",
                       "无常巷、接引院、忘川河、奈何桥与望乡台的最终内容形态、物理连接和入口条件。",
                       "转轮殿的地府内部前置、Boss 阶段参数、对象、运行时会话与实机协作节奏。",
                       "地府常规完成会话及两个独立内容轨道的实际时长；本规格因此保留 targetDurationMinutes=0。",
                       "经验、掉落、货币、物品、保底、资格与资源吞吐的权威运行时接入、持久化收据与生产裁决；当前仅引用已采纳且 runtime_handoff=false 的 economy-v2 设计基线。",
                       "地府主城收集项、塔主题层与后续螺旋地狱扩展的具体规则。"
                   ]
}
```

## 验收标准

- difu-mainline-encounter-contract.json 恰好包含十个 spec-local 节点与一个固定的白骨秘境 spec-local 单人副本角色，且除 DF_E_YANLUO_HALL 与 DF_E_ZHUANLUN_HALL 外不新增运行时 encounter key。
- 阎罗殿固定为 DF_E_YANLUO_HALL / non_team_normal_final，并且唯一写入 DF_PROGRESS_YANLUO_HALL_CLEARED。
- 转轮殿固定为 DF_E_ZHUANLUN_HALL / team_instance，显式禁止写入阎罗完成键并引用既有团队清理合同。
- sessionFlow 只包含以阎罗殿收束的常规章节完成会话；parallelContentFlows 恰好包含白骨秘境 optional_parallel_nonblocking 与转轮殿 post_completion_nonblocking 两条独立轨道，且均不阻塞常规完成。
- 参考顺序、常规完成路径、固定团队终点及其 deferred 路线分别存在，且没有把阎罗完成键改写为未批准的地府内部入口条件。
- 十个路线节点与白骨秘境独立副本角色均有可解析来源、内容职责、状态、合同依赖和未决项；所有真实地图、对象、数值和运行时字段保持 deferred 或不存在。
- 严格规格校验器、跨包地府—花果山镜像校验、JSON 解析、本地 Markdown 链接与 design-spec normalizer 结构校验通过。
- 完整度评分只作为规划可交接证据，不解除 production_gate=closed 或声称 Y3、Lua、对象、地图、持久化和实机验证已经完成。

## 下一步建议

- 先确认未决项，避免把关键设定、数值或资源 ID 硬编进后续产物。
- 用 y3-review-panel 对结构化规格进行多角度评审。
- 用 y3-object-config 继续规范化英雄、怪物、物品、技能等物编内容。
- 用 y3-terrain-layout 继续推导地图尺寸、分区、路线和刷怪点。
- 用 y3-lua-api 继续拆解运行时逻辑、事件、奖励和同步风险。
- 用官方 y3-ui-pipeline 继续制作 UI 面板与 Lua 绑定需求。
