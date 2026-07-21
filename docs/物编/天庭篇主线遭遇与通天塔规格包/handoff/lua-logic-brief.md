# Lua 逻辑交接简报

## 项目

{
    "name":  "天庭篇主线、遭遇与通天塔首轮离线规格",
    "genre":  "最多 4 人同游、存档制的西游题材 ORPG 离线设计层",
    "camera":  "2.5D 俯视角",
    "sessionType":  "公共地图与可重复副本组成的单局会话；天庭运行时尚未施工",
    "targetPlayers":  "1-4 人",
    "targetDurationMinutes":  0,
    "pitch":  "以第三劫下的临时天庭为 Lv41-60 的内容锚点，先锁定跨篇、会话与经济边界；通天塔只承接 Lv55 逐人准入、每 5 层休整与玲珑主题并入全局塔的既定事实。"
}

## 核心循环

{
    "shortLoop":  "确认权威章节条件后，在临时天庭及其公共压力方向中承接遭遇角色；具体事件、怪物和战斗流程待裁定。",
    "midLoop":  "以公共区域、单人候选与凌霄团队方向形成内容职责分层；二者的准入、完成关系与失败处理必须在后续合同中固定。",
    "longLoop":  "Lv55 后逐人满足准入要求，按五个抽象节拍推进首轮子循环并在第五节拍后休整；结算、失败、退出与下一循环交接遵循离线状态合同，但全局楼层方案、记录、重开与赛季政策均不在本包定义。",
    "rewards":  [
                    "外部引用 runtime-closed economy-v2 的首轮奖励设计与收据字段；本包不内嵌物品、掉率、货币、保底或奖励数值。"
                ]
}

## 系统拆分

[
    {
        "name":  "天庭章节进度合同",
        "category":  "progression",
        "designIntent":  "为天庭建立独立、受信任的入口与完成合同，避免隐式耦合地府完成键。",
        "requiredData":  [
                             "新进度键",
                             "写入者",
                             "受信任消费者",
                             "事件标识",
                             "断线与重连语义"
                         ],
        "runtimeBehavior":  "deferred；本包不创建运行时键。",
        "owner":  "后续成长/实现合同裁决"
    },
    {
        "name":  "天庭公共遭遇职责",
        "category":  "encounter",
        "designIntent":  "以临时天庭与三处公共方向承接第三劫压力，不预设实体或数值。",
        "requiredData":  [
                             "区域职责",
                             "事件触发合同",
                             "参与者归属",
                             "失败与清理规则"
                         ],
        "runtimeBehavior":  "offline_design；必须继承权威共享状态边界。",
        "owner":  "后续遭遇与地图施工"
    },
    {
        "name":  "单人和团队副本关系",
        "category":  "instance",
        "designIntent":  "在不替代现有会话合同的前提下，裁决单人候选、凌霄方向与常规完成的关系。",
        "requiredData":  [
                             "单人选择结果",
                             "团队关系",
                             "准入规则",
                             "失败、退出和清理语义"
                         ],
        "runtimeBehavior":  "deferred；不创建副本、地图或成员限制数据。",
        "owner":  "后续副本合同裁决"
    },
    {
        "name":  "通天塔首轮五节拍状态与时序合同",
        "category":  "long_term",
        "designIntent":  "承接唯一全局塔的天庭主题，将 Lv55 逐人准入、五个抽象节拍、第五节拍休整、终局互斥和幂等边界结构化为可验证的离线合同。",
        "requiredData":  [
                             "未来 run 范围",
                             "幂等语义包络",
                             "记录范围与持久化",
                             "后续循环合同",
                             "失败、退出、结算与恢复语义"
                         ],
        "runtimeBehavior":  "offline_design；只引用 tower-first-cycle-state-contract.json，不创建状态键、节拍内容、楼层总数、词缀、记录、奖励或赛季。",
        "owner":  "后续全局通天塔合同"
    },
    {
        "name":  "经济与奖励收据依赖",
        "category":  "economy",
        "designIntent":  "确保天庭内容只外部引用被采纳、但运行时关闭的 economy-v2，而不是把数值写进规格或误用旧候选。",
        "requiredData":  [
                             "resource_table_version",
                             "owner_id",
                             "qualification_snapshot_id",
                             "encounter_instance_id",
                             "event_id",
                             "reward_slot_key",
                             "receipt_id",
                             "award_plan_hash",
                             "tower_run_id",
                             "tower_cycle_id",
                             "tower_week_bucket",
                             "tower_mode",
                             "tower_weekly_token_before",
                             "tower_weekly_token_after",
                             "award_outcome"
                         ],
        "runtimeBehavior":  "accepted_design_reference_runtime_not_integrated；economy-v2 可以被设计合同引用，但天庭不得调用、编译或创建生产资源；implementation/growth/ 仍为离线候选。",
        "owner":  "成长数值与经济裁决的独立运行时实施"
    }
]

## 技能与运行时需求

{
    "specId":  "TT_SPEC_ABILITY_BOUNDARY",
    "status":  "deferred",
    "role":  "不新增天庭技能、Buff 或数值；构筑切换只在通天塔每 5 层休整边界中被允许。",
    "runtimeKey":  null
}

## 后续 Lua 任务

handoff/lua-logic-brief.md：补充首轮状态/时序与幂等边界；不含 Lua 实现。
