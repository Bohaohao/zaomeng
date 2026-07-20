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

## 明确不包含

- 地府单位、技能、效果、投射物、地图资源、地形坐标、Y3 ID 或编辑器对象。
- 经验、掉落、概率、保底、货币、物品、奖励、数值或资源吞吐。
- `implementation/difu/`、`implementation/growth/` 或任何可执行地图接入。

所有上述内容保持 `null`、`deferred` 或不存在，不能从本包推导为生产配置。

## 工件与校验

| 工件 | 用途 |
|---|---|
| [cross-chapter-interface.json](cross-chapter-interface.json) | 唯一机器可读接口契约与非生产证据协议 |
| [design-spec.json](design-spec.json) | Y3 规划层交接视图；不替代接口契约 |
| [validate-underworld-preflight.ps1](validate-underworld-preflight.ps1) | 严格验证固定决策、非生产边界、来源与负例 |
| [validate-difu-huaguoshan-contract.ps1](validate-difu-huaguoshan-contract.ps1) | 只读静态比对地府接口与花果山 manifest、绑定和 Lua 配置镜像；不执行 Lua，不替代行为回归 |
| [validation-report.md](validation-report.md) | 本包最新离线验证记录 |

执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\地府篇前置接口包\validate-underworld-preflight.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\地府篇前置接口包\validate-difu-huaguoshan-contract.ps1
```

随后使用 `y3-design-spec-normalizer` 的 `validate-design-spec.ps1` 与 `score-spec-completeness.ps1` 检查规划视图。其完整度分数只说明结构可交接，不解除任何生产门禁。

## 本轮详细施工计划

| 顺序 | 施工项 | 交付与验收边界 |
|---:|---|---|
| 1 | 冻结跨篇口径 | 将阎罗殿、转轮殿、逆潮门槛和团队死亡策略同步到全局、首发范围、花果山与成长契约；拒绝“地府末段推进”这类泛化替代条件。 |
| 2 | 建立唯一进度接口 | 以 `cross-chapter-interface.json` 固定 `DF_PROGRESS_YANLUO_HALL_CLEARED` 的角色归属、阎罗殿唯一写入者、`(actor_id,event_id)` 幂等键、完成收据字段和非写入者。 |
| 3 | 建立团队清理接口 | 固定 `dead -> revive -> chapter_initial_spawn`，并把 `left` 无回传、全灭去重、超时仅 `active`、以及 `raid_instance_id + session_epoch + cleanup_token` 的确认身份写入机器可读合同。 |
| 4 | 同步花果山消费者 | 逆潮只将 `Lv38 + DF_PROGRESS_YANLUO_HALL_CLEARED` 交给受信任查询；牛魔旧战场只投影死亡回传/会话锁命令，不创建地府写入、地图或奖励。 |
| 5 | 离线验证与终审 | 执行严格接口校验、生产值/Y3 ID/旧键/离场/确认身份负例、规格归一化、花果山预检和 Lua 回归；再做独立契约与运行时复审。 |
| 6 | 归档发布 | 更新索引和施工归档，记录证据与未关闭门禁；通过 `git diff --check`、全量离线入口后提交并推送。 |
| 7 | 后续地府篇施工（不在本轮） | 先在真实地图工程回读 `chapter_initial_spawn`、地图根和对象 ID，再创建地府单位、遭遇、地图、持久化写入与实机回归；数值、掉落和经济仍须先走裁决包。 |

## 后续交接

完整地府篇开始时，新增地府单位、遭遇、地图和运行时包必须消费本接口的稳定键与死亡策略；不得重命名、用客户端布尔值替代，或把非生产证据扩展成奖励结算。
