# 地府篇前置接口包验证报告

## 结果

验证日期：`2026-07-21`

| 检查 | 结果 | 证据 |
|---|---|---|
| JSON 解析 | 通过 | `cross-chapter-interface.json`、`design-spec.json` 均可由 PowerShell `ConvertFrom-Json` 解析。 |
| 严格接口校验 | 通过 | `validate-underworld-preflight.ps1` 返回 `ok=true`、`0` errors，并通过 `7/7` 负例。 |
| 负例：非空生产值 | 通过 | 向 `production_value` 注入 `1`，被 `non_null_nonproduction_value` 拒绝。 |
| 负例：伪造 Y3 ID | 通过 | 注入 `y3_id`，被 `forbidden_production_field` 拒绝。 |
| 负例：工作区外来源 | 通过 | 注入绝对来源， 被 `non_relative_source_ref` 拒绝。 |
| 负例：非规范进度键 | 通过 | 把逆潮完成键改为 `underworld_late`，被 `fixed_value_mismatch` 拒绝。 |
| 负例：离场复活/回传 | 通过 | 把 `left_behavior` 改为复活回传，被 `fixed_value_mismatch` 拒绝。 |
| 负例：清理确认身份顺序 | 通过 | 改写 `raid_instance_id + session_epoch + cleanup_token` 身份字段顺序，被 `fixed_array_mismatch` 拒绝。 |
| 负例：非写入者集合漂移 | 通过 | 将白骨秘境替换为 `DF_E_YANLUO_HALL`，被 `fixed_array_mismatch` 拒绝，保持阎罗殿的唯一写入者语义。 |
| 地府—花果山执行式 Lua 合同校验 | 通过 | `validate-difu-huaguoshan-contract.ps1` 通过固定 canonical materializer 调用受控 Node/Fengari，对接口、花果山 manifest、地图绑定及唯一 canonical Lua 表字段做离线比对；`0` errors、`28/28` 镜像、固定合同与入口边界负例均通过。 |
| 负例：Lua 重复键/注释伪命中 | 通过 | 重复 `progression_key`、重复 `unlock_rule` 的后写覆盖，以及将正确键留在 Lua 注释中的伪命中，均被有效表投影拒绝。 |
| 负例：Lua 第二消费者 | 通过 | 向 `HG_E_OX_BATTLEFIELD` 注入 `DF_PROGRESS_YANLUO_HALL_CLEARED`，被 `unauthorized_lua_progression_consumer` 拒绝。 |
| 负例：受限 fixture 载荷 | 通过 | fixture 中尝试 `os.execute` 创建临时标记文件，被 `trusted_fixture_projection_failed` 拒绝，标记文件未创建。 |
| 负例：入口路径覆盖 | 通过 | validator 的 `-ConfigPath`、常规导出的 `-LuaFixturePath`、以及旧 `-LuaConfigPath` 均被拒绝；常规入口只能使用 canonical 配置。 |
| Normalizer 校验 | 通过 | `0` errors；保留 `missing_duration` 警告，因为本前置接口包不定义生产会话时长。 |
| Normalizer 完整度 | `100/100 ready` | 仅表示规划结构可交接；不表示地府内容、Y3 接入或生产门禁已开放。 |

## 已验证边界

- 固定 `DF_E_ZHUANLUN_HALL` 为 `team_instance`，`DF_E_YANLUO_HALL` 为非团队地府常规最终副本。
- 固定 `DF_PROGRESS_YANLUO_HALL_CLEARED` 为角色级、受信任、按 `(actor_id, event_id)` 幂等写入的进度键；花果山只能经受信任查询直接读取这一稳定键，不存在第二个写入键或第二套幂等收据。
- 固定 `HG_E_DRAGON_REVERSE_TIDE` 必须同时满足等级至少 `38` 与受信任查询命中该键；`underworld_late` 明确被拒绝。
- 跨篇校验不是 Lua 源码文本匹配：它在受控、受信任的 Node/Fengari 边界中离线执行唯一 canonical 配置并读取最终表语义。材料器与配置均由校验器的 `$ProjectRoot` 固定推导为 `implementation/huaguoshan/tools/materialize-object-commands.ps1` 与 `implementation/huaguoshan/lua/huaguoshan_config.lua`；规范路径、项目根、链接状态和解析结果均受校验，且不存在 `-MaterializerPath`、`-ConfigPath` 或常规导出的 `-LuaConfigPath` 覆盖入口。
- Lua 负例只使用 `huaguoshan-cross-chapter-fixtures` 临时根下的专用 `huaguoshan_config.lua` fixture，并通过独立的 fixture 导出模式加载。其 `loadfile(path, 't', environment)` 环境不暴露 `os`、`io`、`package`、`require`、`debug`、`load`、`dofile` 或 `loadfile`；`os.execute` 标记载荷已证明不能创建文件。
- 投影稳定枚举所有有效 `Config.encounters` 的 `progression_key` 消费者，并断言 `DF_PROGRESS_YANLUO_HALL_CLEARED` 只能由 `HG_E_DRAGON_REVERSE_TIDE` 消费；这不是 Y3 引擎、地图或生产运行时的启动/接入。
- 固定团队成员死亡后的“先复活、再回章节 `initial_spawn`、保留 `dead` 与重入锁”顺序；只有同一 `raid_instance_id + session_epoch + cleanup_token` 的 `cleanup_ack` 才可解锁。`left` 不复活、不回传；全灭不重复回传死者，超时只回传 `active` 成员。
- 校验器确认 `implementation/difu/` 不存在；工作区既有 `implementation/growth/` 仅在其保持 `offline_candidate_simulation_not_adopted` 与 `runtime_handoff=false` 时被视为外部候选。本包未创建或消费地府单位、地图、对象、Y3 ID、掉落、货币、物品、概率、保底或任何生产数值。

## 未验证且不得误报

- 阎罗殿的真实完成事件、持久化写入、地府地图、章节出生点和 Y3 地图根尚未存在。
- 花果山离线查询须直接读取 `DF_PROGRESS_YANLUO_HALL_CLEARED`；真实地图绑定、持久化查询与实机回读仍是后续接入任务。
- 本报告中的 Node/Fengari 求值仅是受控离线配置投影，不可误报为 Y3 Lua 运行、生产环境加载或行为回归。
- 所有经验、奖励、掉落、概率、货币、物品和保底仍处于非生产边界。
