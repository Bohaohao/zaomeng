# 花果山首 6 小时垂直切片：潮痕到成长结算

## 状态

- 包状态：`offline-bridge-validated`
- 接入状态：`offline-integrated-nonproduction`
- 生产门：`closed`
- 运行边界：受信任的离线 Node/Fengari 进程；没有真实 Y3 地图脚本根、物编对象、存档或在线结算服务。

本包把既有公共遭遇 `HG_E_TIDE_TRACE`（潮痕）的权威完成，接到 `implementation/growth/` 的 `f6h-v1` 未采纳离线候选模拟。它证明的是一次可追溯、可重放但不可重复变更的结算链路；它不把离线数值升级为生产基线。

```text
既有地图资源合同
  -> 潮痕权威交互（2 秒读取、30 秒余波）
  -> trace_action_completed
  -> 受信任资格证据
  -> vertical_slice_bridge
  -> implementation/growth 的版本化结算
  -> 不暴露奖励内容的稳定收据
```

## 已验证的边界

- 仅复用既有资源：`spawn_trace_tide_guard`、`pt_hg_tide_trace_stone`、`area_hg_tide_trace_interact`、`HG_U_TIDE_TRACE_GUARD` 与 `stabilize_tide_trace`。
- 调用方不能自行证明读取完成、存活、范围、完成时间或证明引用；这些信息只能由注入的受信任证据校验器返回。真实潮痕状态机直接输出 canonical `trace_action_completed` 证据，不由桥接测试手造字段。
- 桥接器只接受仍声明为 `offline_candidate_simulation_not_adopted`、`runtime_handoff=false`、`resource_table_status=offline_candidate_not_adopted` 且生产门关闭的注入成长运行时；构造后再次漂移也会在结算前 fail-closed。
- 请求必须匹配结算版本、资格证据版本、实例身份、资源表版本和确定性的资格快照；并且 `owner_id` 必须等于权威证据的 `actor_id`，不能把 A 的遭遇结算给 B。
- 收据以请求幂等键和潮痕来源身份双重防重：同一请求返回 `duplicate_replayed`；同一潮痕换身份重发会终止拒绝。
- 桥接层拒绝调用方内联经验、货币、材料、掉率、保底或数量字段。奖励只由成长资源表解析，回传的是账本引用而不是奖励明细。
- 完成结算不会跳过潮痕余波；原遭遇仍按既有状态机清理环境并关闭生命周期。

## 关键文件

- [slice-contract.json](slice-contract.json)：唯一可校验合同与生产门声明。
- [lua/vertical_slice_bridge.lua](lua/vertical_slice_bridge.lua)：引入受信任完成校验器和成长运行时的纯 Lua 桥接层。
- [tests/test_tide_trace_growth_bridge.lua](tests/test_tide_trace_growth_bridge.lua)：从既有潮痕状态机到成长账本的端到端回归。
- [tests/run-all.ps1](tests/run-all.ps1)：合同校验、可信 Lua 执行和离线 API 隔离门禁。

## 验证

在仓库根目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\huaguoshan\first-six-hours-vertical-slice\tests\run-all.ps1
```

或一次运行成长包及该切片的总回归：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\growth\tests\run-all.ps1
```

可信执行边界会清除并拒绝 `NODE_OPTIONS` 与 `NODE_PATH` 注入；它不使用 `NODE_PATH` 来解析 Lua 依赖。

## 明确未完成的生产项

- 真实 Y3 地图、地图根 Lua、对象 ID、事件适配器、UI、物编和多人实机。
- 持久化账本、跨进程传输、在线重试编排与断线恢复。
- `f6h-v1` 转为全局正式数值/掉落/保底资源表的裁决。
- 任何“真实可玩地图”或“生产经济已上线”的结论。
