# Lua 逻辑交接简报

## 项目

{
    "name":  "造梦：地府篇主线、遭遇与副本规格",
    "genre":  "2.5D 俯视角多人 ARPG 的第二篇章节规格",
    "camera":  "2.5D俯视角",
    "sessionType":  "单局常规章节完成会话；白骨与转轮为独立内容轨道",
    "targetPlayers":  "公共路线支持多人；阎罗殿为非团队常规最终副本；转轮殿最多 4 人团队本",
    "targetDurationMinutes":  0,
    "pitch":  "承命者进入轮回失序的幽冥，在鬼城与十司冲突中恢复命册秩序；常规篇章以阎罗殿收束，白骨秘境为不阻塞主线的可选单人挑战，转轮殿承载不替代主线完成的团队终局。"
}

## 核心循环

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

## 系统拆分

[
    {
        "system":  "章节因果与内容分轨",
        "designIntent":  "保留鬼城到转轮殿的参考素材顺序，同时将常规完成会话、可选并行白骨单人本与独立转轮团队内容显式拆开。",
        "requiredData":  [
                             "十个 spec-local 节点与白骨秘境的固定 spec-local 单人副本角色（optional_parallel_nonblocking、非路线节点）",
                             "参考顺序",
                             "常规完成路径",
                             "固定团队终点及其 deferred 入口与路线",
                             "白骨与转轮的独立 parallelContentFlows"
                         ],
        "runtimeBoundary":  "不生成地图库、入口条件或物理连接。",
        "downstreamOwner":  "y3-terrain-layout（真实地图工程存在后）"
    },
    {
        "system":  "阎罗殿跨篇完成",
        "designIntent":  "使非团队常规最终副本成为唯一可信完成键生产者。",
        "requiredData":  [
                             "DF_E_YANLUO_HALL",
                             "DF_PROGRESS_YANLUO_HALL_CLEARED",
                             "actor_id 与 event_id 幂等收据"
                         ],
        "runtimeBoundary":  "本包仅引用现有接口，不实现持久化或完成事件。",
        "downstreamOwner":  "y3-lua-api（地图根与持久化方案明确后）"
    },
    {
        "system":  "转轮殿团队清理",
        "designIntent":  "复用统一团队会话、死亡回传与匹配清理确认，而不将死亡回城误解为重入解锁。",
        "requiredData":  [
                             "DF_E_ZHUANLUN_HALL",
                             "TEAM_INSTANCE_RETURN_TO_CHAPTER_INITIAL_SPAWN_V1",
                             "raid_instance_id、session_epoch、cleanup_token"
                         ],
        "runtimeBoundary":  "不实现副本状态机、传送、清理或多人同步。",
        "downstreamOwner":  "y3-lua-api（团队运行时开工后）"
    },
    {
        "system":  "遭遇主题目录",
        "designIntent":  "将鬼灯、无常、关隘、审判、魂河、桥面、梦境与轮回重置组织为可评审的主题，不偷渡为单位或技能对象。",
        "requiredData":  [
                             "spec-local 节点",
                             "主题标签",
                             "来源追踪"
                         ],
        "runtimeBoundary":  "不含单位模板、能力、波次、刷怪、伤害、状态时长或数值。",
        "downstreamOwner":  "y3-object-config 与 y3-lua-api（前置决策和地图回读后）"
    },
    {
        "system":  "成长与经济隔离",
        "designIntent":  "地府内容只声明奖励来源类别；economy-v2 已冻结全局曲线/账本/收据边界，但未分配地府 profile，任何生产结算仍被禁止。",
        "requiredData":  [
                             "来源类别",
                             "成长裁决包引用"
                         ],
        "runtimeBoundary":  "不生成经验、货币、物品、掉率、保底或资格规则。",
        "downstreamOwner":  "成长数值与经济裁决包"
    }
]

## 技能与运行时需求

无

## 后续 Lua 任务

地图根、持久化与同步边界确认后，实现阎罗殿完成收据、转轮殿成员锁/清理确认和受信任查询；不得以客户端布尔值或队友进度替代。
