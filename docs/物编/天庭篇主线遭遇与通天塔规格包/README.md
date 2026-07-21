# 天庭篇主线、遭遇与通天塔首轮规格包

## 状态

offline-design-spec / review-ready / production-gate-closed

本包只整理天庭 Lv41-60 的章节职责、主线与副本关系，以及通天塔首轮五节拍子循环的离线状态/时序边界。它外部引用 runtime-closed 的 `economy-v2` 设计表，但不创建真实地图、Y3 对象、Lua、UI、账本、进度键或运行时遭遇。

## 当前可继承的结论

| 范围 | 本包可继承的事实 | 本包不得补写的内容 |
|---|---|---|
| 等级 | 天庭覆盖 Lv41-60，首发上限 Lv60。 | 经验阈值、升级时长、经验来源和分配。 |
| 通天塔首轮 | Lv55 后逐人校验；五个抽象节拍依次推进；仅第五节拍完成后打开休整；结算、失败、退出和下一循环交接均有离线状态边界；首通/重复奖励、周桶与收据语义外部引用 `economy-v2`。 | 总层数、后续节拍、层主题、词缀、记录范围、兑换目录、赛季、任何运行时状态键。 |
| 世界观 | 第三劫的天门倾覆、临时天庭主城、天宫道/南天门/天王殿外缘、凌霄相关团队内容和玲珑塔并入全局通天塔均是当前方向。 | 具体章节节点、地图邻接、Boss 名单、战斗阶段、物品或剧情台词。 |
| 单人内容 | 首发单人本在蟠桃园与御马监之间二选一。 | 选择结果、入口、时长、Boss、奖励和运行时键。 |
| 团队内容 | 天庭首发团队内容定位于凌霄宝殿；世界观保留杨戬线的方向。 | 常规完成者与团队终点的关系、入口、成员条件、最终 Boss 和完成键。 |
| 经济 | `economy-v2` 已冻结角色货币/材料、收据、花果山 profile 与塔首轮奖励；本包只引用其塔/收据边界。 | 天庭具体掉率、材料、保底、XP source_profile、兑换目录、赛季货币和任何运行时资源吞吐。 |

天庭不得默认消费 DF_PROGRESS_YANLUO_HALL_CLEARED。该键的当前跨篇消费者仅是花果山龙宫逆潮；若未来要建立地府至天庭的进度合同，必须先获得新决策并建立独立、受信任的写入/消费边界。

## 工件

| 工件 | 用途 |
|---|---|
| [tianting-mainline-tower-contract.json](tianting-mainline-tower-contract.json) | 本包唯一领域事实源：冻结约束、规格局部内容角色、塔循环边界、跨篇禁令和经济依赖。 |
| [decision-register.md](decision-register.md) | 区分 fixed、offline_design、deferred 与外部经济裁决状态。 |
| [mainline-route.md](mainline-route.md) | 世界观方向与尚未裁决的章节角色关系。 |
| [topology-whitebox.md](topology-whitebox.md) | 不含坐标、资源键或地图邻接的逻辑拓扑。 |
| [tower-first-cycle-state-contract.json](tower-first-cycle-state-contract.json) | 首轮五节拍的机器可校验状态、迁移、终态互斥、结算/失败/退出与幂等语义合同。 |
| [tower-first-cycle-sequence.md](tower-first-cycle-sequence.md) | 首轮五节拍的可读时序、休整与下一循环交接边界。 |
| [design-spec.json](design-spec.json) | 供设计规格校验与后续离线交接使用的规划视图。 |
| [design-spec-report.md](design-spec-report.md) | 可读的规划摘要与未决项说明。 |
| [acceptance-matrix.md](acceptance-matrix.md) | 离线规格、生产门禁和下游施工的验收分层。 |
| [handoff](handoff) | 物编、地形、Lua、UI 与复审的无代码简报。 |
| [validate-tianting-tower-spec.ps1](validate-tianting-tower-spec.ps1) | 校验冻结值、禁用跨篇消费、资源表边界、JSON 集合形状和负例。 |
| [validation-report.md](validation-report.md) | 本包最新离线验证记录。 |

## 来源优先级

1. [全局设计基线](../../全局设计基线.md)。
2. [成长系统进度、掉落与长期目标契约](../18-成长系统进度、掉落与长期目标契约.md) 与 [装备、法宝、宠物与材料物编规格](../19-装备、法宝、宠物与材料物编规格.md)。
3. [v1.0 首发内容范围](../../04-v1.0首发内容范围.md)、[项目统一世界观总纲](../../10-项目统一世界观总纲.md)、[公共野外与副本规则](../../02-公共野外与副本规则.md)。
4. [成长数值与经济裁决包](../成长数值与经济裁决包/README.md)。其中只有 accepted-baseline 可被引用为结构事实；proposal、deferred、conflict 和 whitebox-candidate 均不是生产数据。

## 生产边界

- `economy-v2` 已采纳为运行时关闭的设计表；所有天庭奖励只能外部引用它，不能内嵌或发放。`implementation/growth/` 仍是离线候选模拟，本包不得调用或提升它。
- 新增天庭 encounter、地图、对象、物品、技能、进度和资源键均保持 spec_id 或 deferred，不能伪装为 runtime key。
- 玲珑塔只能作为全局通天塔中的天庭主题表达，不能创建第二套长期爬塔系统。
- 首轮五节拍只是一段抽象子循环：第五节拍后的继续只能交接给未来全局塔运行合同，不能由本包隐式生成第六节拍或总层数。
- 准入、节拍终局、休整关闭、结算、失败与退出都须经未来权威逻辑和幂等语义包络裁决；重复请求只能返回既有权威结论。
- UI 只能展示权威状态和发起请求；传送、准入、结算、记录和奖励不得由本地 UI 改写。
- 团队与单人副本在真实施工时必须继承既有权威会话、成员锁、失败、清理确认和同步边界；本包不实现它们。

## 运行校验

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\天庭篇主线遭遇与通天塔规格包\validate-tianting-tower-spec.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\validate-design-spec.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\design-spec.json
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\score-spec-completeness.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\design-spec.json
~~~

通过只证明离线设计结构可交接，不等同于天庭地图、塔层、对象、奖励、存档、同步或多人实机已完成。
