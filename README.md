# 造梦 ORPG 策划与离线施工基线

> 本仓库当前是策划、物编规格和 Lua 离线施工成果的版本库，不是已经可直接运行的 Y3 游戏工程。

## 真实进度

- 已形成首发三篇章（花果山、地府、天庭）的世界观、公共野外、单人本、团本、长期挑战、成长与公平商业化基线。
- 已归档六层世界、东胜神州扩容、花果山白盒布局、怪物/BOSS 与传送点等地图设计；`terrain/` 中的布局 JSON、报告和预览图是正式的离线地编交付物，不是编辑器内已落地地图。
- C01 破妄、C02 镇界、C03 持明已具备职业设计、物编预施工规格和离线 Lua/桥接包；其中 C03 已进入离线施工验收状态，但真实命中、地图 Hook、物编对象和多人实机验证仍未绑定。
- C04 巡猎已作为正式职业子基线归档，并已具备物编预施工规格、离线 Lua/桥接包与离线回归；真实命中、地图 Hook、物编对象和多人实机验证仍未绑定。
- 公共职业契约、效果/控制租约、离线测试入口和 API 基线检查已纳入 `implementation/`，用于后续职业施工复用。

## 尚未完成

- 未创建或回读真实 Y3 地图、单位、技能、效果等物编对象，未填写生产 ID。
- 未绑定地图脚本根、真实伤害/选点/品级/净化/保护/Boss 事件 Hook。
- 未实现存档、技能树 UI、五槽装配、多人联机同步、公共野外刷新和副本实例运行时。
- 未完成编辑器加载、四人联机、数值实机调参与上架验收。

## 目录

- [`docs/`](docs/README.md)：策划总索引、世界观、地图、物编规格和职业设计归档。
- [`docs/归档/地图设计/`](docs/归档/地图设计/README.md)：地形布局、扩容策略和花果山白盒交付。
- [`docs/归档/职业设计/`](docs/归档/职业设计/README.md)：职业蓝本及 C01-C04 子基线。
- [`docs/物编/`](docs/物编/README.md)：英雄、技能、效果的预施工字段规范。
- [`implementation/`](implementation/)：C01-C04 职业包与花果山遭遇包的离线 Lua、桥接契约、预检与测试入口。

## 验证入口

在具备 Node.js、PowerShell 和本地 Fengari 缓存的环境中，可按验证范围选择一个入口。

仅验证 C01-C04 职业离线包（不运行花果山遭遇包）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\run-all-professions.ps1
```

验证全部离线预施工包（该汇总会先运行上述职业验证，再运行花果山遭遇包，无需重复执行上一条）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\run-all-preconstruction.ps1
```

这些入口均只验证离线契约与纯 Lua 测试；通过不等同于已完成 Y3 编辑器、地图或多人实机验证。花果山当前执行的是“离线 API 隔离检查”；真实地图脚本根未接入，因此无 Y3 API 兼容性基线。

### 本次归档验证（2026-07-14）

- `implementation/run-all-professions.ps1` 只覆盖 C01-C04 职业包；`implementation/run-all-preconstruction.ps1` 是全量汇总入口，内部已包含前者并追加花果山遭遇包的离线预检、物编命令构建、纯 Lua/桥接、地图绑定投影与离线 API 隔离检查。通过不等同于编辑器或多人实机验证。
- 仍由施工门禁明确阻止编辑器落地：生产 ID、地图路径、脚本根、真实命中与品级解析、保护/净化/Boss 事件契约、图标模型和多人实机验证均未完成。
- 已检查本仓库全部本地 Markdown 链接；布局预览 JSON 也已作为离线交付物保留。

### 后续复审归档（2026-07-17）

- [花果山离线复审修订归档](docs/归档/物编施工/01-花果山离线复审修订归档.md) 已补记蛟魔王 3 秒潜入、物化器完整性与职业入口 Node 信任链的 P1 闭环。
- 物化器已拒绝对象集/依赖/owner 关系漂移、非法 `record_key` 与单位未决字段；职业入口覆盖 Node 发现期和执行前的替换对抗夹具。
- `implementation/test-run-all-preconstruction-integrity.ps1`、`implementation/run-all-professions.ps1`、花果山总入口及 `implementation/run-all-preconstruction.ps1` 已在本机重新通过；代码终审为 `APPROVE`，架构终审为非阻断 `WATCH`。
- 全量离线验收结论仅覆盖离线契约；生产 ID、编辑器地图、真实脚本根和多人实机门禁仍保持关闭。

## 版本管理范围

仓库保留正式策划文档、离线 Lua、测试、预施工规格及布局预览交付物；`.omx/`、`.omc/`、`.subagent-runs/`、本地缓存、日志和环境文件由 [`.gitignore`](.gitignore) 排除。
