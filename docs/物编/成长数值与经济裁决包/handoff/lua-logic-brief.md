# Lua 逻辑交接简报

## 项目

{
    "name":  "造梦 ORPG 成长数值与经济裁决包",
    "genre":  "最多 4 人同游的存档制西游题材 ORPG",
    "camera":  "Y3 2.5D 俯视角",
    "sessionType":  "公共地图中的存档制游玩会话；野外、副本与通天塔为可重复的权威子会话",
    "targetPlayers":  "1-4 人",
    "targetDurationMinutes":  0,
    "pitch":  "为 Lv1-Lv60 的长期成长建立可追溯的经验、经济、奖励资格、掉落收据与数值标定边界；先固定审计和公平契约，再由采纳后的数据表驱动 Y3 子会话结算。"
}

## 核心循环

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

## 系统拆分

[
    {
        "name":  "经验曲线与来源结算",
        "category":  "progression",
        "designIntent":  "将 Lv1-Lv60 的章节成长和来源权重交给版本化数据表，而非怪物白盒字段。",
        "requiredData":  [
                             "xp_to_next",
                             "cumulative_xp",
                             "source weights",
                             "party qualification",
                             "party distribution",
                             "level difference",
                             "death and reconnect rules",
                             "event receipt"
                         ],
        "runtimeBehavior":  "权威端仅在已采纳的资源表下授予经验，并以角色、事件、来源和版本去重。",
        "owner":  "数值裁决后交给 y3-lua-api；当前仅规格数据"
    },
    {
        "name":  "装备、法宝、宠物和材料成长",
        "category":  "economy",
        "designIntent":  "在既定五品质、强化、进阶、合成和宠物资产边界上，逐步确定可审计的长期成长。",
        "requiredData":  [
                             "slots",
                             "profession limits",
                             "base stats",
                             "affixes",
                             "strengthen and advance",
                             "recipes",
                             "material throughput",
                             "duplicate conversion",
                             "storage and migration"
                         ],
        "runtimeBehavior":  "强化、进阶、合成和孵化必须以物品谱系、材料收据和原子事务结算。",
        "owner":  "数值裁决后交给 y3-object-config 与 y3-lua-api"
    },
    {
        "name":  "货币账本与结算收据",
        "category":  "economy",
        "designIntent":  "让货币、材料、保底、roll 和消耗都有角色归属、版本、事件和可重放的原结果。",
        "requiredData":  [
                             "currency keys",
                             "owner scope",
                             "balance cap",
                             "sources",
                             "sinks",
                             "receipt identity",
                             "migration",
                             "cleanup policy"
                         ],
        "runtimeBehavior":  "同一收据重放只返回原结算，不二次改变余额、材料、保底或消耗。",
        "owner":  "数值裁决后交给 y3-lua-api"
    },
    {
        "name":  "公共 Boss 资格、掉落与保底",
        "category":  "economy",
        "designIntent":  "将荣誉、个人推进、参与箱、稀有资格、保底和 roll 保持分层，并消除参与箱 P1 双口径。",
        "requiredData":  [
                             "qualification snapshots",
                             "final participation chest policy",
                             "rare rule",
                             "drop tables",
                             "pity pools",
                             "duplicate rules",
                             "resource table version",
                             "receipt policy"
                         ],
        "runtimeBehavior":  "公共行为按 origin/window、event_id 和 occurrence 去重；primary/assist 不直接改变任何奖励资格。",
        "owner":  "数值裁决后交给 y3-lua-api；花果山 manifest 仅在 P1 采纳后同步"
    },
    {
        "name":  "通天塔长期奖励",
        "category":  "progression",
        "designIntent":  "以逐人 Lv55 门槛锁定入口，再由独立规则决定层数、词缀、首通/重复奖励与赛季。",
        "requiredData":  [
                             "record scope",
                             "floor plan",
                             "affix pool",
                             "first clear",
                             "repeat rewards",
                             "tower currency",
                             "season policy"
                         ],
        "runtimeBehavior":  "入口逐人校验；奖励在版本化资源表批准前不产生实际结算。",
        "owner":  "数值裁决后交给 y3-lua-api、y3-terrain-layout 和官方 y3-ui-pipeline"
    },
    {
        "name":  "零付费经济门禁",
        "category":  "monetization",
        "designIntent":  "禁止通过商品、价格、概率或便利字段改变角色强度、成长速度、资格、掉率、保底或塔门槛。",
        "requiredData":  [
                             "30/60/90 minute free-play samples",
                             "combat BAL logs",
                             "resource throughput",
                             "public Boss fairness logs"
                         ],
        "runtimeBehavior":  "所有未登记或影响成长公平的商业字段被拒绝，不存在付费绕过经济结算的路径。",
        "owner":  "多维评审"
    }
]
## 技能与运行时需求

[
    "四职业技能点、绝技和构筑均受既有成长基线约束",
    "职业战斗日志是后续装备与经验数值标定的输入，不是由经济表替代"
]
## 后续 Lua 任务

[
    "在决策采纳后实现版本化经验授予、资格快照、结算收据、货币账本、保底和迁移。",
    "重放、断线、跨资源表版本、资格伪造和 primary/assist 误用必须有拒绝路径。"
]
