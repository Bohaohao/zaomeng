# 通天塔：天庭 Boss 复用接口

## 已登记的用户方向

- 七星与二十八星宿作为唯一全局通天塔的小 Boss 内容池。
- 天庭侧候选完整 run 为四十层、八个五层段；每五层为一个 Boss 槽，仍待上位全局塔合同采纳。
- 天庭侧候选的第十、二十、三十、四十层升级为大 Boss，取代该槽的小 Boss：四门校律使、九曜司衡官、镇塔监律使、玲珑塔灵。
- 通天塔掉落材料、来源事件、资格、收据与奖励仍需独立经济裁决，当前全部为 `null/deferred`。

## 与既有通天塔合同的关系

| 已冻结事实 | 本接口如何遵守 |
|---|---|
| 通天塔是唯一全局长期塔；玲珑仅为其天庭主题。 | 不创建第二座塔、独立 run、记录、赛季或账本。 |
| Lv55 逐人准入，每五层休整。 | 不改动准入或休整；若上位采纳，每段第五拍标为 Boss 槽，十层节点升级为大 Boss。 |
| 现有首轮仅有五个抽象节拍。 | 只允许外层把每段第五拍标记为内容槽；不改状态名、转移、幂等语义或 runtime floor key，也不将五节拍误读为楼层总数。 |
| 塔首轮奖励外部引用 economy-v2。 | 不新增 tower_mode、不扩展现有奖励表、不登记材料或概率。 |

## 内容池标签

| 池 | 可复用内容 | 适合承担的学习/考验 | 不可在本轮决定 |
|---|---|---|---|
| 七星池 | 天枢至瑶光的空间规则与七位试炼首领。 | 轴线、轨道、辨识、平衡、调和、开窗、收束。 | 具体星君抽取、权重、词缀、奖励、难度与 Boss 数值。 |
| 星宿池 | 二十八星官的签名动作与四象共享语法。 | 连线、火候、围猎、封镇的团队协作。 | 具体星官抽取、实例化方式、成员条件、波次与塔结算。 |
| 大 Boss 池 | 第 10/20/30/40 层：四门校律使、九曜司衡官、镇塔监律使、玲珑塔灵。 | 作为四个十层篇章总结，而非七星/星宿的简单加血复刻。 | 实际剧情、机制、掉落、外观、对象、数值与地图。 |

## 冻结的离线接口

~~~text
global_tower_content_pool = { seven_stars, twenty_eight_mansions }
logical_full_run_floor_count = 40
logical_cycle_count = 8
mini_boss_interval = 5            # fifth-beat content slot
major_boss_interval = 10          # replaces mini slot at 10/20/30/40
major_boss_roster = { four_gate, nine_luminary, tower_warden, linglong_spirit }
cycles_1_to_7 = NEXT_CYCLE_HANDOFF only
cycle_8 = inherited_terminal_close_only
reward_binding = null_or_deferred
~~~

上面的伪代码只是设计接口说明，不是 Lua、配置或运行时键。真实施工前仍要由全局通天塔合同实现 run 服务、地图/实例、抽取算法、检查点、失败恢复、资格、记录、奖励收据和同步。
