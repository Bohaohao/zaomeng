# 镇界离线预施工包

## 定位

这是 `C02 镇界` 的离线设计与施工包，不是 Y3 地图脚本根目录，也没有创建任何真实单位、技能或效果对象。

镇界使用守势、界势、格挡、有效护守和归垣绝技；它独立保存职业资源与技能状态，并通过公共层复用目标归属、效果状态、控制租约和命令契约。

## 当前状态

- 设计、物编规格、预施工清单和离线 Lua 已完成 P1 修订并通过离线校验。
- 真实 Y3 ID、模型、图标、近战模板、距离尺度、编辑器对象回读和多人实机验证均延期。
- `implementation/profession_common/` 是本包的必要依赖；真实接入时必须与本包一并放入有效 Lua 脚本根。

## 内容

- `preconstruction-manifest.json`：1 英雄、18 技能、12 效果的 A 层字段与执行门禁。
- `lua/zhenjie_config.lua`：镇界成长、守势、技能、被动、绝技和效果策略。
- `lua/zhenjie_core.lua`：守势、界势、格挡、有效护守、绝技与清理状态机。
- `lua/zhenjie_skills.lua`：八主动、八被动和绝技的适配器中立指令。
- `lua/zhenjie_effects.lua`：绑定公共来源感知效果存储的职业入口。
- `lua/zhenjie_y3_*.lua`：固定 API 基线下的 Y3 桥接、目标筛选和单位事件控制器。
- `tests/`：预检、物编命令构建、核心、目标归属、控制生命周期与 API 基线验证。
- `Y3-INTEGRATION.md`：真实地图映射与项目钩子。
- `DEFERRED-INTEGRATIONS.md`：存档、技能树、五槽和多人同步的职业接入 TODO。

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File .\implementation\zhenjie\tests\run-all.ps1
powershell -ExecutionPolicy Bypass -File .\implementation\run-all-professions.ps1
```

上述命令只做离线验证，不启动编辑器、不修改 Y3 JSON、不热更对象。真实接入还必须绑定 A05/A08 施法点、A04/A07 伤害分类和生命周期命中确认契约。
