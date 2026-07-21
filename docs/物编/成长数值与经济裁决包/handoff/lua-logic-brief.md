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
        "runtimeBehavior":  "未来权威端只能编译 economy-v2 或其后续版本，并以角色、遭遇实例、事件、来源和奖励槽幂等结算；当前没有运行时接入。",
        "owner":  "economy-v2 已冻结；实际运行时集成仍待独立施工与审查"
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
        "owner":  "装备、法宝、宠物数值仍待裁决；不因 economy-v2 自动开启物编或 Lua 施工"
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
        "runtimeBehavior":  "同一来源身份与指纹重放只返回原终态结算，不二次改变余额、材料、保底、首通或额度；新结算在同一可串行化事务内锁定身份和额度后才生成最终计划，不持久化 prepared 状态；跨版本同来源冲突而不重算。",
        "owner":  "economy-v2 已冻结；持久化账本、证明解析和重连对账仍待独立运行时施工"
    },
    {
        "name":  "公共 Boss 资格、掉落与保底",
        "category":  "economy",
        "designIntent":  "将荣誉、个人推进、参与箱、稀有资格、保底和 roll 保持分层，并执行已冻结的 P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION。",
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
        "runtimeBehavior":  "公共行为按 origin/window、event_id 和 occurrence 去重；P1 参与箱是三个公共 profile 的唯一基础包结算路径，公共首通/稀有必须绑定同事件已提交参与箱收据；团队稀有使用独立快照且不继承箱前置，primary/assist 不直接改变任何奖励资格。",
        "owner":  "economy-v2 已冻结；花果山候选 manifest 仍保持非生产，不自动同步"
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
                             "qualification snapshot",
                             "weekly counter before/after",
                             "season policy"
                         ],
        "runtimeBehavior":  "入口逐人校验；团队成员还须通过 TOWER_FIRST_CYCLE_QUALIFICATION_V1 的入场、在场、存活与贡献快照。每个权威确认五拍循环在锁定角色周额度后只能按 economy-v2 的首通/重复奖励、周桶计数和零奖励封顶语义结算；当前没有实际结算。",
        "owner":  "economy-v2 已冻结首轮奖励；塔运行时、地形和 UI 仍待独立施工"
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
    "在独立运行时施工获批后实现版本化经验授予、资格快照、结算收据、货币账本、保底和迁移。",
    "重放、断线、跨资源表版本、资格伪造和 primary/assist 误用必须有拒绝路径。"
]
