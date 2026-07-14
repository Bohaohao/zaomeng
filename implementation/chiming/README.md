# 持明离线预施工包

`C03 持明` 的设计、物编规格和 Lua 均在此包中离线施工。它不是地图脚本根，未创建真实 Y3 单位、技能或魔法效果对象。

## 当前状态

- 状态为 `reviewed / official-subbaseline / offline-stage-accepted / P0-P1-revision-complete`。
- 法印来源队列、命中快照、净化、控制租约、生命周期和公共 BOSS 上报接口均以离线代码表达；真实地图 Hook 尚未绑定。
- `implementation/profession_common/` 是必要依赖；真实接入时必须与本包一起放入有效 Lua 脚本根。
- 生产 ID、模型、图标、施法距离尺度、物编回读、地图加载和四人实机仍保持延期。

## 内容

- `preconstruction-manifest.json`：1 英雄、18 技能、12 效果的 A 层预施工记录。
- `lua/chiming_core.lua`：法印、明台、绝技值、净化资格和临时状态机。
- `lua/chiming_skills.lua`：八主动、八被动和绝技的适配器中立命令。
- `lua/chiming_y3_*.lua`：固定公开 API 基线下的 Y3 桥接、目标筛选、控制租约与生命周期控制器。
- `tests/`：预检、命令构建、核心、目标归属、控制与生命周期、公共 BOSS 贡献测试。

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File .\implementation\chiming\tests\run-all.ps1
powershell -ExecutionPolicy Bypass -File .\implementation\run-all-professions.ps1
```

上述命令只做离线验证，不启动编辑器、不写入 Y3 JSON、不创建物编对象。
