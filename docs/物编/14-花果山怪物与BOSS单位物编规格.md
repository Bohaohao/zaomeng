# 花果山怪物与 BOSS 单位物编规格

## 状态与边界

- 状态：`reviewed / offline-preconstruction`。
- 适用范围：花果山公共野外、龙宫单人本和牛魔旧战场团队本的敌对单位。
- 真实 Y3 单位 ID、模型、头像、技能 ID、效果 ID、投射物 ID 均未分配；不得据此文档直接创建对象。
- 本文只锁定稳定键、单位模板、白盒基础属性、能力依赖和运行时职责。掉落概率、资源吞吐、装备数值与正式地图尺度继续延期。

唯一机器可读来源为 [花果山预施工清单](../../implementation/huaguoshan/preconstruction-manifest.json)。本文件是该清单的策划说明，不复制其全部字段。

## 对象规模

| 类型 | 数量 | 说明 |
|---|---:|---|
| 普通怪单位 | 16 | 五段公共野外的基础生态 |
| 精英/大精英单位 | 12 | 含两名残响载体与龟丞相 |
| BOSS 单位 | 7 | 3 个公共 BOSS、2 个龙王版本、牛魔双形态 |
| 单位合计 | 35 | 每个单位均有独立稳定键 |
| 主动能力 | 55 | 只承载可见施法入口；伤害、AI 与阶段走 Lua B 层 |
| 魔法效果 | 12 | 护盾、减速、残响、狂暴和牛气冲天等可见状态 |
| 投射物 | 7 | 只记录稳定弹道载体，特效资源待查询 |

## 白盒数值口径

这些值是花果山 `Lv1-Lv20` 的首轮战斗尺度，不是资源吞吐表，也不代表最终掉落或毕业环境。

| 区段 | 推荐等级 | 普通怪生命参考 | 普通怪攻击参考 | 设计目标 |
|---|---:|---:|---:|---|
| 山道 | 1-4 | 280-420 | 22-30 | 单人能读出前摇，四人不被怪群堵路 |
| 水帘溪谷 | 4-8 | 430-620 | 31-42 | 处理辅助、远程与临水突进 |
| 桃林/蝙蝠窟 | 8-12 | 620-850 | 43-56 | 明暗双路线的控制和飞行教学 |
| 七星洞/高崖 | 12-16 | 880-1180 | 58-76 | 明确地面预警和高机动检查 |
| 东海前缘 | 16-20 | 1200-1550 | 78-98 | 为公共 BOSS 与火焰山做战力检查 |

公共 BOSS 的基础生命按单名参与者白盒值记录；实际生成时由遭遇的参与人数与推荐等级快照等比放大，不能用客户端本地人数计算。单人本和团本使用各自实例快照，不能从公共野外继承。

## 单位清单

### 山道与水帘溪谷

| 稳定键 | 名称 | 等级段 / 层级 | Y3 模板 | 基础生命 / 物攻 | 核心能力 |
|---|---|---|---|---:|---|
| `HG_U_MOUNTAIN_MONKEY` | 山猴 | 1-3 / 普通 | 近战小怪 | 280 / 22 | 普攻群体压迫 |
| `HG_U_STONEHIDE_BEAST` | 石皮山怪 | 2-4 / 普通 | 近战小怪 | 420 / 26 | `HG_A_STONE_SMASH` |
| `HG_U_VINE_IMP` | 藤叶小妖 | 2-4 / 普通 | 远程小怪 | 320 / 24 | `HG_A_VINE_DART` |
| `HG_U_MONKEY_PACK_LEADER` | 猴群头目 | 3-5 / 精英 | 近战精英 | 1250 / 38 | `HG_A_PACK_LEAP`、`HG_A_PACK_CALL` |
| `HG_U_GREAT_APE` | 大猩猩 | 4-6 / 大精英 | 近战精英 | 4200 / 52 | `HG_A_APE_QUAKE`、`HG_A_APE_THROW` |
| `HG_U_WATERFALL_IMP` | 水帘小妖 | 4-6 / 普通 | 近战小怪 | 460 / 32 | `HG_A_WATER_DASH` |
| `HG_U_SPRING_SPIRIT` | 泉灵 | 4-7 / 普通辅助 | 远程小怪 | 430 / 28 | `HG_A_SPRING_BLESS` |
| `HG_U_FISH_SENTINEL` | 鱼妖哨兵 | 5-8 / 普通远程 | 远程小怪 | 520 / 35 | `HG_A_FISH_BOLT` |
| `HG_U_WATERFALL_GUARD` | 水帘妖卫 | 6-8 / 精英 | 近战精英 | 1900 / 48 | `HG_A_WATER_GUARD_WAVE` |
| `HG_U_TIDE_TRACE_GUARD` | 水帘妖卫·潮痕载体 | 6-8 / 特殊精英 | 近战精英 | 2100 / 50 | `HG_A_TRACE_OVERFLOW`、`stabilize_tide_trace` |
| `HG_U_MACAQUE_KING` | 猕猴王·化身 | 7-10 / 区域 BOSS | 近战boss | 10000 / 68 | `HG_A_MACAQUE_CLONE`、`HG_A_MACAQUE_SPIN`、`HG_A_MACAQUE_WIND_EYE` |

### 桃林、蝙蝠窟与七星洞

| 稳定键 | 名称 | 等级段 / 层级 | Y3 模板 | 基础生命 / 物攻 | 核心能力 |
|---|---|---|---|---:|---|
| `HG_U_PEACH_SPIRIT` | 桃花妖 | 8-10 / 普通远程 | 远程小怪 | 650 / 43 | `HG_A_PEACH_POLLEN` |
| `HG_U_MIST_MONKEY` | 迷踪猴 | 8-11 / 普通 | 近战小怪 | 710 / 47 | `HG_A_MIST_STEP` |
| `HG_U_CAVE_BAT` | 洞窟蝙蝠 | 8-11 / 普通飞行 | 远程小怪 | 580 / 45 | `HG_A_BAT_DIVE` |
| `HG_U_CAVE_IMP` | 洞窟小妖 | 9-12 / 普通 | 近战小怪 | 820 / 52 | 普攻群体压迫 |
| `HG_U_YURONG_KING` | 禺狨王·化身 | 10-12 / 大精英 | 近战精英 | 5600 / 68 | `HG_A_YURONG_FOG`、`HG_A_YURONG_PHANTOM` |
| `HG_U_BAT_STATUE` | 蝙蝠石像·劫痕 | 10-12 / 机关大精英 | 远程精英 | 6100 / 64 | `HG_A_BAT_SONIC`、`HG_A_BAT_CALL` |
| `HG_U_SEVENSTAR_DEMON` | 七星洞妖 | 12-14 / 普通 | 近战小怪 | 920 / 60 | `HG_A_SEVENSTAR_REND` |
| `HG_U_SHANXIAO_CASTER` | 山魈术士 | 12-15 / 普通远程 | 远程小怪 | 880 / 58 | `HG_A_SHANXIAO_SPIKE` |
| `HG_U_WINGED_DEMON` | 飞翼妖 | 13-16 / 普通飞行 | 近战小怪 | 1020 / 64 | `HG_A_WING_DIVE` |
| `HG_U_BULL_SCOUT` | 牛魔斥候 | 13-16 / 精英 | 近战精英 | 3300 / 78 | `HG_A_BULL_CHARGE`、`HG_A_BULL_FLAME_SLASH` |
| `HG_U_LION_CAMEL_KING` | 狮驼王·化身 | 15-17 / 大精英 | 近战精英 | 8200 / 92 | `HG_A_LION_CHARGE`、`HG_A_LION_ROAR` |
| `HG_U_PENG_KING` | 鹏魔王·化身 | 16-18 / 可选大精英 | 远程精英 | 9000 / 96 | `HG_A_PENG_DIVE`、`HG_A_PENG_WIND_BLADE`、`HG_A_PENG_WIND_EYE` |

### 东海前缘、龙宫与牛魔旧战场

| 稳定键 | 名称 | 等级段 / 层级 | Y3 模板 | 基础生命 / 物攻 | 核心能力 |
|---|---|---|---|---:|---|
| `HG_U_FISH_PATROLLER` | 鱼妖巡兵 | 16-18 / 普通 | 近战小怪 | 1200 / 78 | `HG_A_FISH_PATROL_DASH` |
| `HG_U_TURTLE_GUARD` | 龟甲守卫 | 16-19 / 普通坦克 | 近战小怪 | 1550 / 72 | `HG_A_TURTLE_SHELL` |
| `HG_U_WATER_MAGE` | 水灵术士 | 17-20 / 普通远程 | 远程小怪 | 1250 / 82 | `HG_A_WATER_MAGE_POOL` |
| `HG_U_VORTEX_SOLDIER` | 漩涡妖兵 | 17-20 / 精英 | 近战精英 | 3900 / 98 | `HG_A_VORTEX_PULL` |
| `HG_U_RIPTIDE_NODE_SOLDIER` | 漩涡妖兵·裂潮节点 | 18-20 / 特殊精英 | 近战精英 | 4300 / 102 | `HG_A_RIPTIDE_ANCHOR`、`seal_vortex` |
| `HG_U_JIAO_KING_P1` | 蛟魔王·一阶段化身 | 18-20 / 区域 BOSS | 近战boss | 17000 / 112 | `HG_A_JIAO_COLUMN`、`HG_A_JIAO_TAIL`、`HG_A_JIAO_SUBMERGE`、`HG_A_JIAO_TIDE_EYE` |
| `HG_U_SHARK_KING_P1` | 鲨魔王·一阶段化身 | 19-20 / 区域 BOSS | 近战boss | 22000 / 124 | `HG_A_SHARK_BITE`、`HG_A_SHARK_VORTEX`、`HG_A_SHARK_FRENZY`、`HG_A_SHARK_ANCHOR` |
| `HG_U_TURTLE_MINISTER` | 龟丞相·海眼门将化身 | 10-25 / 副本精英 | 近战精英 | 7200 / 82 | `HG_A_TURTLE_MINISTER_SHELL` |
| `HG_U_DRAGON_KING_P1` | 龙王·旧潮化身 | 10-25 / 单人本 BOSS | 远程boss | 13500 / 96 | `HG_A_DRAGON_WATER_LANCE`、`HG_A_DRAGON_TIDE_FIELD`、`HG_A_DRAGON_SEA_EYE` |
| `HG_U_DRAGON_KING_P2` | 龙王·逆潮极化体 | 38-45 / 单人本 BOSS | 远程boss | 43000 / 260 | `HG_A_DRAGON_WATER_LANCE`、`HG_A_DRAGON_REVERSE_TIDE`、`HG_A_DRAGON_FALL` |
| `HG_U_OX_KING_HUMAN` | 牛魔·人形劫痕 | 18-24 / 团本 BOSS | 近战boss | 40000 / 132 | `HG_A_OX_CLEAVE`、`HG_A_OX_EARTH_CRACK` |
| `HG_U_ARMORED_WHITE_OX` | 披甲白牛·劫痕 | 18-24 / 团本 BOSS | 近战boss | 48000 / 150 | `HG_A_OX_WHITE_CHARGE`、`HG_A_OX_HUMAN_ECHO`、`HG_A_OX_MAGMA_RING` |

## 单位模板与运行时分层

### A 层：Y3 单位字段

每个单位在清单中固定填写：`unit_type`、`hp_max`、`mp_max`、`attack_phy`、`defense_phy`、`defense_mag`、`attack_speed`、`attack_interval`、`ori_speed`、`turn_speed`、`sight_range`、`reward_exp` 与 `reward_official_res_1`。

`common_atk_type` 与 `common_atk_range` 受真实攻击模板和地图距离尺度门禁保护，当前明确登记为未解析。尺度验证后，`common_atk_range` 必须在创建后通过最小 `-edit` 写入；不能假设 `-create` 已生效。

### B 层：遭遇运行时字段

以下不属于基础物编，统一从遭遇清单读取并由权威 Lua/同步逻辑执行：

- 等级段、参与人数快照和实例倍率。
- 仇恨、巡逻、脱战、重置、碰撞边界与刷新规则。
- 技能命中、伤害公式、位移、召唤、地面危险、阶段和破韧。
- 公共 BOSS 有效参与、击杀荣誉、机制行为、个人箱与稀有掉落资格。
- 龙宫四房分配、单人失败清理、牛魔团本成员锁和牛气冲天。

## 资产复用与资源约束

- 水帘溪谷、东海前缘和龙宫优先复用水系基础动作、鱼妖、龟甲守卫与水弹弹道，只在阶段技能和材质上做差异。
- `潮痕载体` 与 `裂潮节点` 是独立单位稳定键，因为它们有专属公共行为和环境状态；它们不能通过给普通精英临时改名代替。
- 猕猴王分身、禺狨王幻影、牛魔人形回响属于运行时无奖励召唤体，不单独建可掉落单位对象。每个体仍必须有独立 Unit ID、生命周期和不可继承玩家私有标记的约束。
- 所有模型、头像、图标、特效 ID 必须等接入 Y3 编辑器后查询；不得用本文中的稳定键伪造 ID。

## 验收

1. 清单必须恰好包含 `35` 单位、`55` 能力、`12` 效果、`7` 投射物，稳定键全局唯一。
2. 每个单位的能力依赖、每个能力的效果/投射物依赖都必须解析到清单内对象。
3. 三个公共 BOSS 必须为猕猴王、蛟魔王一阶段、鲨魔王一阶段；龙王和牛魔不得被误登记为公共野外 BOSS。
4. 未完成真实地图、资源、ID、脚本根和编辑器连接门禁时，命令生成器必须拒绝输出可执行创建命令。
