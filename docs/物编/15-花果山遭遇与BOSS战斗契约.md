# 花果山遭遇与 BOSS 战斗契约

## 状态与来源

- 状态：`reviewed / offline-preconstruction / public-map-contract-complete / instance-map-contract-pending / execution-gated`。
- 地形来源：[花果山 96x72 白盒拆分](../归档/地图设计/14-花果山96x72白盒拆分.md)。
- 单位来源：[花果山怪物与 BOSS 单位物编规格](14-花果山怪物与BOSS单位物编规格.md)。
- 公共野外与副本边界：[公共野外与副本规则](../02-公共野外与副本规则.md)。
- 运行时与地图绑定：[花果山遭遇运行时与地图逻辑资源绑定](17-花果山遭遇运行时与地图逻辑资源绑定.md)。

本文件是遭遇侧的唯一详细来源。职业技能只能消费这里声明的权威事件，不能自行推断 BOSS 品级、交互成功、破韧、有效护守或掉落资格。

## 通用权威事件

伤害、破韧、护守与机制处理事件使用以下共同字段：

```text
kind | event_id | actor_id | lifecycle_id | authority_proof_ref | combat_scope
boss_instance_id | phase_id | target_id | target_lifecycle_id | sync_tick
skill_key | value | encounter_action_key | source_unit_id | source_unit_lifecycle_id
```

- `combat_scope=public` 的事件必须没有 `session_instance_id` 与 `session_epoch`。
- 龙宫单人本使用 `combat_scope=solo_instance`，必须带 `instance_slot_id` 与唯一 `session_instance_id`。
- 牛魔团本使用 `combat_scope=team_instance`，必须带 `raid_instance_id` 与成员快照。
- `final_damage`、`actual_break`、`actual_protection` 必须由地图桥接先证明 `source_unit_id + source_unit_lifecycle_id + skill_key` 合法，且 `value>0`；核心不得用默认技能键、调用方声称的品级或候选目标推断结果。
- 每个 `event_id` 在 `boss_instance_id + phase_id` 内只能结算一次。生命周期不匹配、对象已死亡、来源不合法或缺字段的事件静默拒绝，并写入诊断钩子。
- 任何要进入 `economy-v2` 收据的事件还必须带遭遇权威签发的 `authority_proof_ref`。收据适配器只能以 `(actor_id, lifecycle_id, authority_proof_ref)` 解析稳定 `owner_id`；客户端值、裸 `actor_id` 或裸 `lifecycle_id` 都不得写为账本所有者。证明缺失、映射不唯一、映射失效或与事件身份不一致时，拒绝收据且不改变资格、余额、保底或首通状态。
- 换相只能提交 `kind=boss_phase_transition`，结算只能提交 `kind=boss_finalization`。两者都必须携带稳定 `event_id`、当前 `boss_instance_id`、`from_phase`、当前 `boss_target_id + boss_target_lifecycle_id`；换相还必须携带下一阶段和下一目标生命周期。地图根的权威事件提供器负责签发水位证明，权威端再以当前阶段和目标生命周期作比较交换；调用方携带的 `authority_verified`、存活、范围、读条或水位断言一律拒绝，旧阶段、同阶段、回退、重复和复用旧 Boss 实例 ID 的回调同样拒绝。

公共行为另用严格的 `kind=encounter_action_success` 契约：

```text
window_id | mechanic_occurrence_id | completed_tick | completion_mode
boss_target_id | boss_target_lifecycle_id
interaction_unit_id | interaction_unit_lifecycle_id
encounter_action_key | actor_id | lifecycle_id | event_id | combat_scope=public
```

- 行为窗口只能由当前 BOSS 阶段的权威遭遇端开启；窗口记录 `open_tick/close_tick`，并要求 `open_tick=sync_tick`、读条长度等于配置的 `read_seconds`、窗口长度等于配置的 `window_seconds`。预约与完成由权威事件提供器分别签发观察时间、完成时间和读条证明；调用方传入的完成布尔值或时间不构成证明。预约到期、换相、BOSS 死亡或交互物重建都会释放预约并拒绝完成事件。
- 同一窗口的完成先进入待结算队列，只有权威水位推进后才按完成 tick、actor 和 event ID 稳定排序原子决定 `primary/assist`；行为完成本身不能改变稀有掉落资格。
- `combat_scope=public` 的行为不得带任何副本 session 字段；旧 `encounter_action` 事件一律无效。

## 参与与奖励边界

### 公共野外

公共 BOSS 的 DPS 主归属仍按最高有效伤害，且同队成员严格大于 `10%` 有效伤害才同步计入荣誉、公告和队伍战绩。

角色个人有效参与改用下列任一条件：

```text
damage_ratio >= 0.03
OR
达到本场显式一次性破韧阈值
OR
在标记直击中产生一次实际护盾吸收或减伤
OR
完成本场 BOSS 明确开放、成功结算且未重复的 encounter_action_success
```

每种非伤害贡献在单场内只提供一次参与信用；行为交互必须要求角色存活、处于交互半径、完成完整读条且事件生命周期匹配，因此不能靠挂机取得。该个人有效参与是 `progression_participation`，只用于篇章入口、保证性收集和日常；它不自动成为参与箱、稀有装备、宠物、保底或最高 DPS 击杀资格。

正式参与箱使用 [economy-v2](成长数值与经济裁决包/tables/economy-v2-resource-table.json) 的 `P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION`：当本场曾开启合格公共行为窗口时，角色必须同时有一次有效公共行为，并满足有效伤害占比 `>=3%`、合格破韧或实际护守之一；本场从未开启该窗口时，只需后三者之一。稀有资格还必须有权威稀有通关证明，且稀有收据绑定同角色、同遭遇实例、同事件、同资格快照的已提交参与箱收据；参与箱结果本身不推导稀有资格或保底。团队团本使用 `TEAM_RAID_RARE_ELIGIBILITY_V1`，不继承公共参与箱前置。

### 单人本与团本

- 龙宫：挑战者是唯一参与者；旧潮的发现/引导提示需“已发现龙宫且 Lv8+”，但启动旧潮挑战还需同一 `actor_id` 已完成当前职业 60 秒 Lv8 核心路线。C01/C02/C03 分别只接受 `C01_ROUTE_LV8_core`、`C02_ROUTE_LV8_core`、`C03_ROUTE_LV8_core`；C04 只接受持久化的当前所选 `C04_ROUTE_LV8_hunt|wind|bind`。逆潮需同一角色 `Lv38+`，且受信任进度查询已证明角色级键 `DF_PROGRESS_YANLUO_HALL_CLEARED`；该键只可由常规最终副本 `DF_E_YANLUO_HALL` 的权威通关写入，团队本 `DF_E_ZHUANLUN_HALL` 不可替代。可信进度验证器拒绝调用方布尔值。死亡、超时、离开或跨层后先进入 `cleanup_pending`；地图根以当前 `session_instance_id` 解析会话，并在其权威证明中携带 `cleanup_token`，确认后才释放房间锁。调用方不得提交结束原因或清理令牌。
- 牛魔：开启瞬间固定最多 4 名成员；仅成员事件能写入本次贡献和奖励。成员被权威证明为 `dead` 后，立即复活并传送至当前篇章初始出生点 `pt_hg_spawn`，但仍保持本次 `raid_instance_id + session_epoch` 的死亡状态和重入锁，直至收到完全匹配的清理确认；`left` 不触发复活或回传。仅当前会话快照内全员状态为 `dead`，或权威 `now >= deadline_at` 时会失败；全灭不得二次回传已死亡成员，超时只回传当时仍为 `active` 的成员。外部伪造的 `all_members_dead`/提前超时不会结算。失败/成功同样先进入 `cleanup_pending`，清理确认后才解除成员锁。

## 公共野外遭遇

| 稳定键 | 场地 / 锚点 | 敌人 | 规则 |
|---|---|---|---|
| `HG_E_MOUNTAIN_PATH` | `area_hg_public_mountain` | 山猴、石皮山怪、藤叶小妖、猴群头目、大猩猩 | 主路外精英庭，不阻断 `path_hg_main` |
| `HG_E_WATERFALL_PATH` | `area_hg_public_waterfall` | 水帘小妖、泉灵、鱼妖哨兵、水帘妖卫 | 引入远程、水盾和辅助目标 |
| `HG_E_TIDE_TRACE` | `spawn_trace_tide_guard` / `area_hg_tide_trace_interact` | 潮痕载体 | 所有职业可用 `stabilize_tide_trace`，2 cell 读条区，30 秒局部环境态 |
| `HG_E_MACAQUE_KING` | `arena_mihouwang` / `area_hg_wind_eye_interact` | 猕猴王 | 24x18 侧袋，四名玩家可并发 `stabilize_wind_eye` |
| `HG_E_PEACH_GROVE` | `area_hg_public_peach` | 桃花妖、迷踪猴、禺狨王 | 明亮支路，不锁通行 |
| `HG_E_BAT_CAVE` | `area_hg_public_bat` | 洞窟蝙蝠、洞窟小妖、蝙蝠石像 | 阴暗支路，机关召唤不堵出口 |
| `HG_E_SEVENSTAR_PATH` | `area_hg_public_sevenstar` | 七星洞妖、山魈术士、飞翼妖、牛魔斥候、狮驼王 | 狮驼王战圈与主路绕行带隔离 |
| `HG_E_PENG_SIDE` | `arena_peng` / `area_hg_elite_garuda` | 鹏魔王 | 可选侧袋，不得作为东海、龙宫或团本通行门槛 |
| `HG_E_EASTSEA_PATH` | `area_hg_public_east_sea` | 鱼妖巡兵、龟甲守卫、水灵术士、漩涡妖兵 | 东海主路常通，后续扩展接口不被刷怪封锁 |
| `HG_E_RIPTIDE_NODE` | `spawn_trace_vortex_node` / `area_hg_vortex_trace_interact` | 裂潮节点 | 所有职业可用 `seal_vortex`，不计入巡猎教学 |
| `HG_E_JIAO_KING` | `arena_jiaomowang_phase1` / `area_hg_tide_eye_interact` | 蛟魔王一阶段 | 23x21 侧湾，四名玩家可并发 `drain_tide_eye` |
| `HG_E_SHARK_KING` | `arena_shamowang_phase1` / `area_hg_vortex_anchor_interact` | 鲨魔王一阶段 | 23x21 侧湾，锚点必须在安全线内、涡流核外 |

## 三个公共 BOSS

### `HG_E_MACAQUE_KING`：猕猴王·化身

- 重生：`10` 分钟；战斗半径仅限 `arena_mihouwang`，脱战完整回满并重置本次贡献。
- 破韧：阈值 `8`，破韧窗口 `4` 秒；同一次施法的重复回调不得重复上报。
- 100%-30%：`HG_A_MACAQUE_CLONE` 召唤 2 个独立 Unit ID 分身，持续 `2.5` 秒；真身始终可攻击，分身无掉落、无参与账本、不得继承玩家私有猎印。
- 30% 以下：获得 `HG_M_BOSS_FRENZY`，仅提高攻击节奏与分身数量，不新增不可读的伤害。
- 公共行为：分身结束后的当前 occurrence 才开放 `stabilize_wind_eye`，`3 cell` 交互区、`2` 秒读条、`8` 秒窗口，最多 4 个 actor 并发。成功仅写本场非稀有行为参与，不改变击杀或稀有资格。

| 能力 | 标签 | 职业交互 |
|---|---|---|
| `HG_A_MACAQUE_SPIN` | `periodic_or_area` | 不可由格挡/护守刷资源 |
| 分身突袭落点 | `guardable_direct` | 允许镇界的真实格挡/护守结算 |
| 分身投石与残风 | `periodic_or_area` | 仅走位与公共交互 |

### `HG_E_JIAO_KING`：蛟魔王·一阶段化身

- 重生：`12` 分钟；破韧阈值 `12`，窗口 `4` 秒。
- `HG_A_JIAO_SUBMERGE` 固定 `3.0` 秒，BOSS 不可攻击，但必须保持同一 Unit ID 并上报 `trace_pause`；若实现替换单位，必须上报一对一 `trace_transition`。
- `trace_pause` 必须携带按遭遇、Boss 实例、阶段、目标生命周期与 `marker_occurrence_id` 派生的稳定 `pause_id`；到期、换相与终结只允许用同一 `pause_id` 发出一次配对 `trace_resume`，重复、过期或重叠潜入不得延长冻结。
- 潜入期开放 `drain_tide_eye`，`2` 秒读条、`8` 秒窗口。读条成功只影响本轮出水后首个水柱的范围，不删除 BOSS 伤害或贡献。
- 潜入期可对当前有效参与者施加 `HG_BOSS_WATER_CHAIN`。它是遭遇侧显式机制键，不是泛化减速 Buff：持明的合法 `purge_mechanic` 可清除，其他职业可通过完成 `drain_tide_eye` 或在水压生效前离开潮线解除。每名角色每阶段最多登记一次有效处理，不能用重复净化刷公共贡献。

| 能力 | 标签 | 职业交互 |
|---|---|---|
| `HG_A_JIAO_COLUMN` 的中心重击 | `guardable_direct` | 允许有效护守 |
| `HG_A_JIAO_TAIL` | `guardable_direct` | 允许格挡与反震 |
| 潜入水洼 / 持续水流 | `periodic_or_area` | 不得给受击资源 |

### `HG_E_SHARK_KING`：鲨魔王·一阶段化身

- 重生：`12` 分钟；破韧阈值 `16`，窗口 `4` 秒。
- 本体在撕咬和涡流期间保持可攻击，不发送 `trace_pause` 或 `trace_transition`。
- 30% 以下开启 `HG_A_SHARK_FRENZY`，叠加 `HG_M_BOSS_FRENZY`，只缩短能力节奏并增加涡流预警次数。
- `stabilize_vortex_anchor` 必须位于 `area_hg_shark_anchor_safe_line` 内、`area_hg_shark_vortex_core` 外；`2` 秒读条、`8` 秒窗口，最多 4 人并发，不采用先点先占。

| 能力 | 标签 | 职业交互 |
|---|---|---|
| `HG_A_SHARK_BITE` | `guardable_direct` | 允许真实格挡/护守 |
| `HG_A_SHARK_VORTEX` | `periodic_or_area` | 只产生牵引与地面压力 |
| 低血量涡流 | `periodic_or_area` | 必须有独立安全线与读条锚点 |

## 副本遭遇

### `HG_E_DRAGON_OLD_TIDE`：龙宫旧潮

- 类型：`solo_instance`；旧潮与逆潮共同引用 `HG_I_DRAGON_FOUR_SEAS` 的四份独立挑战房。角色、边界、出生点、BOSS 战圈和出口仍是**待编辑器绑定**的实例地图契约；离线包只验证槽位状态机。推荐 `Lv10-25`，白盒时限 `12` 分钟。
- 单位：鱼妖哨兵、龟甲守卫、龟丞相、龙王·旧潮化身。
- 过程：门将短战 -> 海眼阶梯 -> 龙王战。龟丞相的护壳是单人本第一次“先处理护盾窗口”的精英检查。
- 龙王机制：水枪直击可护守；潮汐地面不可护守刷资源；`HG_A_DRAGON_SEA_EYE` 在 55% 与 25% 各一次，只要求玩家离开水压核，不设置职业专属交互。
- 破韧：阈值 `11`，窗口 `4` 秒。旧潮不掉落龙王二阶段或东海篇毕业材料。

### `HG_E_DRAGON_REVERSE_TIDE`：龙宫逆潮

- 类型：`solo_instance`；需要 `Lv38`，且受信任进度查询已返回角色级 `DF_PROGRESS_YANLUO_HALL_CLEARED`；该键只能由 `DF_E_YANLUO_HALL` 的权威通关记录写入，`DF_E_ZHUANLUN_HALL` 的团队通关、队友状态或调用方布尔值均不得替代。推荐 `Lv38-45`，白盒时限 `15` 分钟。四房实际资源与旧潮共用 `HG_I_DRAGON_FOUR_SEAS` 这一份待绑定的四海层契约，不能因入口/回传点存在而宣称副本可启动。
- 复用四份房间的地形槽位，但独立初始化敌人、时限、掉落和生命周期。
- 龙王·逆潮极化体在 60% 开启 `HG_A_DRAGON_REVERSE_TIDE`，50% 以下追加 `HG_A_DRAGON_FALL`。每次阶段只能结算一次，不能借回调重放累积破韧或奖励。
- 破韧：阈值 `18`，窗口 `3.5` 秒；掉落只按逆潮清单结算，旧潮仍可独立重复挑战。

### `HG_E_OX_BATTLEFIELD`：牛魔旧战场

- 类型：`team_instance`；开启时快照入口范围内最多 4 名成员，白盒时限 `20` 分钟。梦墟层的战圈、成员出生点、BOSS 锚和出口为待绑定契约，离线状态机不得替代这些资源。
- 第一阶段 `HG_U_OX_KING_HUMAN`：人形挥砍、裂地与冲锋压制。
- 第二阶段 `HG_U_ARMORED_WHITE_OX`：击杀人形后以同一 `boss_instance_id` 进入白牛形态，成员、贡献、牛气冲天和清理令牌不得重置。
- 破韧：人形阈值 `20`，白牛阈值 `24`；所有 Boss 控制都转为破韧，不保留普通/精英硬控。
- 成员死亡与失败：成员被证明 `dead` 时先按成员身份立即复活并回到 `pt_hg_spawn`，同时拒绝其以同一 `raid_instance_id + session_epoch` 重入；只有匹配当前实例的 `cleanup_token` 确认才能释放该锁。全员死亡只封存实例和发起一次清理，不得再次传送已经死亡的成员；超时只将当时 `active` 的成员回传至 `pt_hg_spawn`。`left` 仅退出成员资格，不触发复活。旧会话或错阶段回调一律不能影响新团本。
- `HG_M_OX_ARROGANCE`：每次全灭后层数 `+1`，每层属性 `+5%`，持续 `5` 分钟；5 分钟内再开本时倒计时暂停，再次失败后续期重置；击杀或自然结束清零。掉率补偿只登记为后续资源表参数，不能在遭遇层直接伪造概率。

## 刷新、清理与反阻塞规则

| 层级 | 重生 / 清理 | 主路与并发约束 |
|---|---|---|
| 普通怪 | 45-75 秒，按锚点独立 | 不得在 8 cell 主路中央刷新 |
| 精英 | 120-180 秒 | 固定小庭或侧袋，战斗不封锁传送点 |
| 大精英 | 180-360 秒 | 个人参与奖励，不作为篇章硬门 |
| 公共 BOSS | 600-720 秒 | BOSS 口袋、交互锚与主路无面积重叠 |
| 龙宫 | 成功/失败后进入 `cleanup_pending`，确认后释放槽位 | 四个 `instance_slot_id` 完全隔离 |
| 牛魔 | 成功/失败后进入 `cleanup_pending`，确认后释放成员锁 | 未入队角色不可进入、不可伤害、不可贡献 |

## 验收

1. 每个公共 BOSS 行为都具有明确 `encounter_action_key`、半径、并发上限、事件字段、成功影响和不影响的奖励边界。
2. 所有标为 `guardable_direct` 的攻击均能上报真实命中、吸收与减伤；`periodic_or_area` 绝不触发反击或受击资源。
3. 三个公共 Boss 的重置、分身/潜入/涡流均不阻断主路，且不与巡猎私有教学会话混用状态。
4. 龙宫四房、牛魔团本和公共野外的 `combat_scope`、实例 ID、成员边界、清理确认与旧会话回调不会互相串写；牛魔死亡成员回到 `pt_hg_spawn` 后仍不能在相同 `raid_instance_id + session_epoch` 重入，直至匹配清理确认。
