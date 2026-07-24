# 地府篇前置接口包

## 状态

`offline-interface-ready / non-production / production-gate-closed`

本包只在地府完整制作开始前，冻结跨篇进度、团队死亡回传与龙宫逆潮消费边界。它不是地府篇单位包、地图包、掉落包或 Y3 施工包。

## 已冻结的接口结论

1. `DF_E_ZHUANLUN_HALL` 是地府篇团队本，运行时分类固定为 `team_instance`。
2. `DF_E_YANLUO_HALL` 是非团队的地府常规最终副本；本包不为它分配地图、单位、对象或战斗实现。
3. `DF_PROGRESS_YANLUO_HALL_CLEARED` 是角色级持久化进度键。只有阎罗殿的受信任完成事件能按 `(actor_id, event_id)` 幂等写入它；`event_id` 沿用现有权威事件口径，不另建第二套完成事件 ID。
4. 花果山 `HG_E_DRAGON_REVERSE_TIDE` 只可通过受信任进度查询，在角色等级至少 `38` 且持有该键时放行。旧的泛化 `underworld_late` 不能作为替代输入。
5. 团队成员被权威证明死亡后先复活并返回所属篇章的 `initial_spawn`，但保持 `dead` 与重入锁；只有匹配同一 `raid_instance_id + session_epoch + cleanup_token` 的 `cleanup_ack` 才能解除。`left` 不复活、不回传；全灭不得向已经死亡的成员再次回传；超时只回传当时仍为 `active` 的成员。
6. [花果山常规收束证明生产者合同](huaguoshan-mainline-closure-proof-contract.json) 是 `HG_SPEC_MAINLINE_CLOSURE_SUCCESS_V1` 的唯一详细来源：同一角色、同一**来源生命周期**内的未来必经公共路线确认 → `HG_E_SHARK_KING` 权威逐人有效参与 → 熔脉裂口发现，才可按 `(actor_id,event_id)` 生成或重放不透明证明；该来源生命周期作为不可变审计 claim 保存。蛟魔单独参与、鹏魔、龙宫、牛魔、队友、稀有、收集和塔均不能替代。
7. [花果山→地府入章合同](chapter-entry-contract.json) 是该证明的唯一详细消费者：入章只接受同一角色的权威 `Lv20` 与来自非团队、逐人花果山主线收束成功的不可伪造交接证明。来源生命周期只作不可变审计，不要求等于当前入章请求生命周期；当前请求生命周期仍须由受信任角色权威独立校验，因此同角色重连后可消费或幂等重放，而旧／伪造请求仍被拒绝。它仅写入或重放 spec-local 逻辑结果，不新增实际运行时键。`Lv21-40` 是地府成长带，不是入口硬门槛。既有 [cross-chapter-interface.json](cross-chapter-interface.json) 仍只负责其中已冻结的阎罗殿、转轮殿、逆潮和团队清理边界，不能替代或平行定义本入章资格。

## 明确不包含

- 地府单位、技能、效果、投射物、地图资源、地形坐标、Y3 ID 或编辑器对象。
- 经验、掉落、概率、保底、货币、物品、奖励、数值或资源吞吐。
- `implementation/difu/` 或任何可执行地图接入；工作区既有的 `implementation/growth/` 只能作为外部、runtime-closed 的离线候选，不能被本接口创建、消费或提升。

所有上述内容保持 `null`、`deferred` 或不存在，不能从本包推导为生产配置。

## 工件与校验

| 工件 | 用途 |
|---|---|
| [cross-chapter-interface.json](cross-chapter-interface.json) | 唯一机器可读接口契约与非生产证据协议 |
| [huaguoshan-mainline-closure-proof-contract.json](huaguoshan-mainline-closure-proof-contract.json) | 花果山→地府不透明常规收束证明的唯一生产者、鲨魔→裂口顺序、重放与拒绝来源边界 |
| [chapter-entry-contract.json](chapter-entry-contract.json) | 花果山→地府入章的唯一详细、纯离线资格与幂等合同；既有跨篇接口只作非重叠边界 |
| [design-spec.json](design-spec.json) | Y3 规划层交接视图；不替代接口契约 |
| [validate-underworld-preflight.ps1](validate-underworld-preflight.ps1) | 严格验证固定决策、非生产边界、来源与负例 |
| [validate-difu-huaguoshan-contract.ps1](validate-difu-huaguoshan-contract.ps1) | 通过受信任、离线、执行式 Node/Fengari Lua 表投影比对地府接口与花果山 manifest、绑定和有效 Lua 配置字段；不替代行为回归 |
| [validate-difu-chapter-entry-contract.ps1](validate-difu-chapter-entry-contract.ps1) | 严格验证入章资格、同角色绑定、来源生命周期审计与当前请求生命周期独立校验、重连幂等重放、拒绝来源与全量 `null/deferred` 边界，并执行负例 |
| [validate-huaguoshan-mainline-closure-proof-contract.ps1](validate-huaguoshan-mainline-closure-proof-contract.ps1) | 严格验证鲨魔逐人参与→熔脉裂口→唯一证明生产者、来源生命周期仅限签发证据、路线选择交错、精确重放、拒绝替代来源、交接消费者对齐与全量 `null/deferred` 边界，并执行负例 |
| [validation-report.md](validation-report.md) | 本包最新离线验证记录 |

### 跨篇 Lua 投影的信任边界

`validate-difu-huaguoshan-contract.ps1` 不是纯文本扫描，也不能描述为“不执行 Lua”：它会在受控、受信任的 Node/Fengari 边界中执行唯一的 canonical `huaguoshan_config.lua`，读取 Lua 最终表值，因此能识别重复字段的后写覆盖和注释伪命中。该执行只用于离线配置投影；不会启动 Y3 引擎、地图、生产服务或任何生产运行时。

校验器从自身的 `$ProjectRoot` 固定推导 `implementation/huaguoshan/tools/materialize-object-commands.ps1` 与 `implementation/huaguoshan/lua/huaguoshan_config.lua`，再对规范路径、项目根约束、文件名、链接状态和解析结果做校验；没有 `-MaterializerPath`、`-ConfigPath` 或正常导出的 `-LuaConfigPath` 覆盖入口，未知余参会被拒绝。材料器的常规 `-ExportCrossChapterLuaContract` 模式同样只能投影该 canonical 配置。

负例不复用正常入口：校验器只会在专用临时根 `huaguoshan-cross-chapter-fixtures` 下创建命名固定为 `huaguoshan_config.lua` 的一次性 fixture，并调用独立的 `-ExportCrossChapterLuaFixtureContract` 模式。fixture 用 `loadfile(path, 't', environment)` 的最小 Lua 环境运行；环境不暴露 `os`、`io`、`package`、`require`、`debug`、`load`、`dofile` 或 `loadfile` 等危险全局。fixture 的作用仅限离线负例，不能替换常规 canonical 配置或获得 Y3/生产执行权限。

投影会稳定导出所有有效 `Config.encounters` 的 `progression_key` 消费者；校验器断言 `DF_PROGRESS_YANLUO_HALL_CLEARED` 在有效 Lua 表中只能由 `HG_E_DRAGON_REVERSE_TIDE` 消费。

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\地府篇前置接口包\validate-underworld-preflight.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\地府篇前置接口包\validate-difu-huaguoshan-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\地府篇前置接口包\validate-huaguoshan-mainline-closure-proof-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\地府篇前置接口包\validate-difu-chapter-entry-contract.ps1
```

随后使用 `y3-design-spec-normalizer` 的 `validate-design-spec.ps1` 与 `score-spec-completeness.ps1` 检查规划视图。其完整度分数只说明结构可交接，不解除任何生产门禁。

## 本轮详细施工计划

| 顺序 | 施工项 | 交付与验收边界 |
|---:|---|---|
| 1 | 冻结跨篇口径 | 将阎罗殿、转轮殿、逆潮门槛和团队死亡策略同步到全局、首发范围、花果山与成长契约；拒绝“地府末段推进”这类泛化替代条件。 |
| 2 | 建立唯一进度接口 | 以 `cross-chapter-interface.json` 固定 `DF_PROGRESS_YANLUO_HALL_CLEARED` 的角色归属、阎罗殿唯一写入者、`(actor_id,event_id)` 幂等键、完成收据字段和非写入者。 |
| 3 | 建立团队清理接口 | 固定 `dead -> revive -> chapter_initial_spawn`，并把 `left` 无回传、全灭去重、超时仅 `active`、以及 `raid_instance_id + session_epoch + cleanup_token` 的确认身份写入机器可读合同。 |
| 4 | 同步花果山消费者 | 逆潮只将 `Lv38 + DF_PROGRESS_YANLUO_HALL_CLEARED` 交给受信任查询；牛魔旧战场只投影死亡回传/会话锁命令，不创建地府写入、地图或奖励。 |
| 5 | 离线验证与终审 | 执行严格接口校验、生产值/Y3 ID/旧键/离场/确认身份负例、受信任 Fengari 有效表投影与 Lua 回归；再做独立契约与运行时复审。 |
| 6 | 归档发布 | 更新索引和施工归档，记录证据与未关闭门禁；通过 `git diff --check`、全量离线入口后提交并推送。 |
| 7 | 后续地府篇施工（不在本轮） | 先在真实地图工程回读 `chapter_initial_spawn`、地图根和对象 ID，再创建地府单位、遭遇、地图、持久化写入与实机回归；经济只能在补地府 profile 且完成 `economy-v2` 运行时门禁后接入。 |

## 后续交接

完整地府篇开始时，新增地府单位、遭遇、地图和运行时包必须消费本接口的稳定键与死亡策略；不得重命名、用客户端布尔值替代，或把非生产证据扩展成奖励结算。
