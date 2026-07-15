# 巡猎离线施工包

`C04 巡猎`的物编规格和 Lua 桥接在此包中完成离线施工。它不属于地图脚本根，未创建真实 Y3 单位、技能或魔法效果对象。

## 当前状态

- `reviewed / official-subbaseline / offline-stage-accepted`。
- 已有 1 个英雄、18 个技能和 12 个效果的预施工清单；生产 ID、图标、模型、距离尺度和对象回读仍为空或延期。
- `implementation/profession_common/lua/` 是必需依赖；真实接入时必须同 `implementation/xunlie/lua/` 一起部署到有效脚本根。

## 内容

- `preconstruction-manifest.json`：A 层物编字段、Lua B 层边界和生产门禁。
- `lua/xunlie_core.lua`：猎印、预留、定猎回收、绝技和生命周期无关的状态机。
- `lua/xunlie_skills.lua`：八个主动、被动派生与绝技的显式目标命令。
- `lua/xunlie_y3_*.lua`：受固定公开 API 基线约束的适配器、目标快照和生命周期控制器。
- `tests/`：预检、命令构建、核心、目标、生命周期、Boss 贡献和 API 基线校验。

## 验证

```powershell
powershell -ExecutionPolicy Bypass -File .\implementation\xunlie\tests\run-all.ps1
powershell -ExecutionPolicy Bypass -File .\implementation\run-all-professions.ps1
```

这些命令只做离线验证，不启动编辑器、不写入 Y3 JSON、不创建物编对象。
