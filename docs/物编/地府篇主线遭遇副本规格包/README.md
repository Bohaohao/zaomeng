# 地府篇主线、遭遇与副本规格包

## 状态

`offline-design-spec / review-ready / production-gate-closed`

本包把地府 `Lv21-40` 的章节主线、遭遇主题、逻辑拓扑与三类副本职责整理为可校验的离线设计规格。它消费既有地府跨篇接口，但不创建 `implementation/difu/`、真实地图、Y3 对象、Lua、奖励或数值。

## 已固定的核心结论

1. 常规篇章完成路径止于 `DF_E_YANLUO_HALL`；它是非团队常规最终副本，且唯一能写入角色级 `DF_PROGRESS_YANLUO_HALL_CLEARED`。
2. `DF_E_ZHUANLUN_HALL` 是地府唯一首发团队本；它消费团队死亡与清理合同，绝不替代阎罗殿写入完成键。
3. 鬼城至转轮殿的十节点顺序保留为参考素材；`DF_E_ZHUANLUN_HALL` 的团队终点职责已固定，忘川河、奈何桥、望乡台及通向该终点的物理连接、入口与内部前置仍是 `deferred`。
4. 白骨秘境以独立的 `DF_SIDE_BAIGU_SECRET_REALM` 规格局部角色固定为单人本，且为 `optional_parallel_nonblocking`：不在常规完成路径或团队内容路径中，不要求阎罗完成，也绝不阻塞阎罗常规完成；它不写入或消费阎罗完成键，也不产生奖励或数值定义。
5. 除上述两个既有 encounter key 外，新增标识一律明确标注为 `spec_id` 或 `spec_chapter_id` 的规格局部标识，不新增运行时 encounter、地图、对象或资源键。
6. 地府产出只能表达为来源类别；`economy-v2` 已冻结全局 XP/货币/收据与花果山 profile，但地府尚无 source_profile 分配，因此经验、货币、物品、掉落、概率、保底、资格和资源吞吐不得在本包结算。
7. 接引院与判官殿以异常档案和审判揭示承接转轮一系的重置企图；这是非物理、非门槛的叙事伏笔，不新增入口、前置或阎罗完成键消费。

## 工件

| 工件 | 用途 |
|---|---|
| [difu-mainline-encounter-contract.json](difu-mainline-encounter-contract.json) | 本包唯一领域事实源：十节点、白骨秘境独立副本角色、双轨路径、跨篇同步与非生产边界。 |
| [design-spec.json](design-spec.json) | 供 `y3-design-spec-normalizer` 校验与下游交接的规划视图。 |
| [mainline-route.md](mainline-route.md) | 参考顺序、常规完成路径与团队内容路径的因果拆分。 |
| [topology-whitebox.md](topology-whitebox.md) | 不含坐标、尺寸、资源键的逻辑拓扑与未来地图回读清单。 |
| [decision-register.md](decision-register.md) | `fixed / offline_design / deferred` 的决策分层。 |
| [handoff/](handoff/) | 对象、地形、Lua、UI 与复审的无代码交接简报；当前 JSON 简报的约定集合字段必须保持 JSON array，不能坍缩为 object、string 或 null。 |
| [validate-difu-mainline-spec.ps1](validate-difu-mainline-spec.ps1) | 严格检查十节点、白骨秘境的并行非阻塞关系、固定团队终点/延期入口路径、跨篇合同、可解析来源、非生产边界、全部受约束 JSON 交接简报的集合形状、终审状态与负例。 |
| [validation-report.md](validation-report.md) | 本包最新验证记录。 |

## 执行与验收

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\地府篇主线遭遇副本规格包\validate-difu-mainline-spec.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\地府篇前置接口包\validate-difu-huaguoshan-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\validate-design-spec.ps1 -DesignPath .\docs\物编\地府篇主线遭遇副本规格包\design-spec.json
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\score-spec-completeness.ps1 -DesignPath .\docs\物编\地府篇主线遭遇副本规格包\design-spec.json
```

通过只证明设计结构可交接：不等同于地图、对象、Lua、持久化、同步、奖励结算或多人实机已完成。

本轮结论、复审与验证证据已归档至[地府篇主线、遭遇与副本规格整包归档](../../归档/物编施工/04-地府篇主线遭遇与副本规格整包归档.md)；当前合同与规格文件仍是唯一详细来源。

## 终审通过后的施工顺序

| 顺序 | 施工项 | 当前边界 |
|---:|---|---|
| 1 | 归档、提交与推送本次规格修复 | 仅在本轮复审和回归验证无阻塞项后执行；归档须保留合同镜像与并行内容轨道的证据。 |
| 2 | 真实地图回读 | 查询地图根、`chapter_initial_spawn`、入口/出口、资源与对象 ID；没有这些证据不得建运行时包。 |
| 3 | 地形与对象规格 | 由 `y3-terrain-layout`、`y3-object-config` 在真实工程中消费本包逻辑角色，不得反向猜测物理数据，也不得把白骨/转轮的叙事关系变为门槛。 |
| 4 | 运行时与持久化 | 由 `y3-lua-api` 落实阎罗完成收据、转轮团队清理和受信任查询；先完成同步边界设计。 |
| 5 | 成长与经济接入 | `economy-v2` 已采纳设计基线；先补地府 source_profile 分配与权威运行时账本/证明门禁，才可定义地府奖励、掉落和结算。 |
| 6 | UI 与多人实机 | 由官方 `y3-ui-pipeline` 和真实四人场景验证入口、成员锁、死亡回城与结算显示。 |
