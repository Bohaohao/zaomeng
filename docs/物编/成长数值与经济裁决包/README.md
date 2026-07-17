# 成长数值与经济裁决包

## 状态

- 版本：v0.3-decision-draft-with-locked-calibration-candidates。
- 建立日期：2026-07-17。
- 状态：decision-draft / review-ready / production-gates-closed。
- 范围：经验、货币、材料、装备成长、掉落、保底、公共 BOSS 参与箱、通天塔奖励和结算迁移。
- 定位：本包是对现有成长规格中数值与经济待决项的可审计整理，不是新的当前设计基线，也不代表任何生产数据已经批准。

当前正式详细来源仍是：

- [成长系统进度、掉落与长期目标契约](../18-成长系统进度、掉落与长期目标契约.md)
- [装备、法宝、宠物与材料物编规格](../19-装备、法宝、宠物与材料物编规格.md)
- [成长系统离线施工与 Y3 接入状态](../20-成长系统离线施工与Y3接入状态.md)
- [全局设计基线](../../全局设计基线.md)

只有用户明确采纳本包某项提案后，才可将对应状态写入上述当前来源、全局基线与后续归档。

## 包内文件

| 文件 | 用途 |
|---|---|
| [design-spec.json](design-spec.json) | 按 Y3 设计规格格式提供系统、风险、MVP 与下游交接入口。 |
| [design-spec-report.md](design-spec-report.md) | 由规格导出的可读报告；结构完整不等同于数值获批。 |
| [decision-register.json](decision-register.json) | 唯一裁决登记册；每项明确状态、证据、阻塞项与采纳条件。 |
| [experience-progression.json](tables/experience-progression.json) | Lv1-60 经验与组队规则的字段、锚点和白盒输入边界。 |
| [item-growth.json](tables/item-growth.json) | 装备、法宝、宠物、材料的已定边界与待填数值字段。 |
| [currency-ledger.json](tables/currency-ledger.json) | 货币候选稳定键、所有者范围与结算账本提案。 |
| [drop-and-pity.json](tables/drop-and-pity.json) | HG_DROP 来源键、资格分层、P1 冲突、保底与收据契约。 |
| [tower-reward.json](tables/tower-reward.json) | 通天塔已定门槛与奖励/赛季待决字段。 |
| [标定候选](calibration/README.md) | 采纳前的来源文件哈希、白盒快照、假设和四类非生产标定场景；全部输出保持空值。 |
| [validate-growth-economy-decision-package.ps1](validate-growth-economy-decision-package.ps1) | 阻止草案、白盒候选或冲突口径被误写成可施工数据的语义校验器。 |
| [validation-report.md](validation-report.md) | 本轮 JSON、结构、语义和交叉引用验证记录。 |
| [handoff](handoff) | 为物编、地形、Lua、UI 和复审生成的五类下游简报。 |

## 状态语义

| 状态 | 含义 | 是否可进入运行时或物编施工 |
|---|---|---|
| accepted-baseline | 已由当前基线明确确认的结构契约。 | 否；仍须等待完整数据和编辑器门禁。 |
| proposal | 有理由的推荐方案，等待主策明确采纳。 | 否。 |
| deferred | 已知需要，但尚无可采纳的数据或政策。 | 否。 |
| conflict | 当前来源存在互斥口径，必须先裁决。 | 否。 |
| whitebox-candidate | 离线白盒输入，只用于校准，不是生产数值。 | 否。 |

任何非 accepted-baseline 条目都必须保持 effective_value 为 null、runtime_handoff 为 false。即使是 accepted-baseline，本包也不生成 Lua、Y3 物编、UI 或生产掉落表。

标定候选使用独立的 `calibration_status=candidate`，不是新的采纳状态。它只引用登记册中已有决策并保存来源文件哈希、白盒快照、待验证假设和空的候选输出；不能借用 `proposal`、`deferred` 或 `whitebox-candidate` 的名称让任一数值提前生效。`non_production`、`observation_only` 和 `runtime_handoff` 必须是显式 JSON 布尔值；候选输出只能是 `null`。候选 JSON 使用封闭字段结构，未知字段、无关快照或未绑定白盒来源都会被拒绝。

## 本轮可审查的提案与冲突

1. 先建立版本化、按角色归属、由权威 event_id 去重的奖励收据与保底数据模型。
2. 将金币、塔币、团队本代币作为候选角色账本；团队只保存资格快照，不持有可分账余额。
3. 将公共 BOSS 参与箱 P1 的两条现存互斥口径与一个第三候选并列登记；第三候选不是推荐结论，也不会生效。稀有资格与保底继续独立。
4. 将经验、掉率、保底阈值、强化系数、装备槽位、法宝/宠物数值和塔奖励保留为 deferred，等待目标节奏与战斗日志。

上述均记为 proposal，未改写 18-20、花果山 manifest 或全局基线。

## 进入下一阶段的门槛

在建立独立 implementation/growth/ 离线数据包前，必须同时满足：

- 经验、装备/法宝/宠物、货币、掉落/保底/参与箱和通天塔的 implementation-critical 决策均有明确采纳记录。
- 每个生效数据项具有唯一稳定键、资源表版本、所有者范围、来源证据和幂等结算字段。
- 参与箱只有一个 final_policy_id，且与花果山正文、manifest、运行时资格字段一致。
- 本包的结构与语义校验通过；零付费 30/60/90 分钟验证指标已能由数据与日志覆盖。

在此之前，HG_DROP、reward_exp、reward_official_res_1 和现有白盒刷新/遭遇数值只能作为校准输入，不能成为正式经验、金币、概率、保底或货币结算数据。
