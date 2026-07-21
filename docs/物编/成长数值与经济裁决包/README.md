# 成长数值与经济裁决包

## 状态

- 版本：v2.0-economy-v2-accepted-design-baseline。
- 建立日期：2026-07-17。
- 最近采纳：2026-07-21。
- 状态：mixed decision-draft + economy-v2 accepted design baseline / economy-v1 superseded-historical / review-ready / production-gates-closed。
- 范围：经验、货币、材料、装备成长、掉落、保底、公共 BOSS 参与箱、通天塔奖励和结算迁移。
- 定位：`economy-v2` 是当前冻结的经验、货币、材料、花果山掉落/保底、P1、通天塔首轮奖励和持久化收据设计基线；`economy-v1` 仅保留为不可改写的历史冻结表。装备/法宝/宠物、地府/天庭来源分配、塔楼层/词缀/赛季仍是待决项。所有运行时与生产门禁仍关闭。

当前正式详细来源仍是：

- [成长系统进度、掉落与长期目标契约](../18-成长系统进度、掉落与长期目标契约.md)
- [装备、法宝、宠物与材料物编规格](../19-装备、法宝、宠物与材料物编规格.md)
- [成长系统离线施工与 Y3 接入状态](../20-成长系统离线施工与Y3接入状态.md)
- [全局设计基线](../../全局设计基线.md)
- [economy-v2 采纳与复审记录](adoption-record.md)
- [economy-v2 当前资源表](tables/economy-v2-resource-table.json)
- [economy-v1 历史冻结表](tables/economy-v1-resource-table.json)

本轮用户已明确采纳 `economy-v2`，并将 `economy-v1` 固化为其哈希绑定的历史前身。旧的 proposal、deferred、conflict 和白盒候选仍保留为历史校准证据，不能覆盖当前表，也不能把 `implementation/growth/` 提升为运行时。

## 包内文件

| 文件 | 用途 |
|---|---|
| [design-spec.json](design-spec.json) | 按 Y3 设计规格格式提供系统、风险、MVP 与下游交接入口。 |
| [design-spec-report.md](design-spec-report.md) | 由规格导出的可读报告；结构完整不等同于数值获批。 |
| [decision-register.json](decision-register.json) | 唯一裁决登记册；每项明确状态、证据、阻塞项与采纳条件。 |
| [adoption-record.md](adoption-record.md) | 本轮用户授权、冻结范围、版本边界与非实施边界。 |
| [economy-v2-resource-table.json](tables/economy-v2-resource-table.json) | 当前已采纳设计表：在不改变冻结数值的前提下，补强 XP、奖励投影、资格、保底、身份和终态收据语义。 |
| [economy-v1-resource-table.json](tables/economy-v1-resource-table.json) | 历史冻结表：由 `economy-v2` 的 `supersedes` 哈希绑定，不再作为当前跨包基线。 |
| [experience-progression.json](tables/experience-progression.json) | Lv1-60 经验与组队规则的字段、锚点和白盒输入边界。 |
| [item-growth.json](tables/item-growth.json) | 装备、法宝、宠物、材料的已定边界与待填数值字段。 |
| [currency-ledger.json](tables/currency-ledger.json) | 货币候选稳定键、所有者范围与结算账本提案。 |
| [drop-and-pity.json](tables/drop-and-pity.json) | HG_DROP 来源键、资格分层、P1 冲突、保底与收据契约。 |
| [tower-reward.json](tables/tower-reward.json) | 通天塔已定门槛与奖励/赛季待决字段。 |
| [标定候选](calibration/README.md) | 采纳前的来源文件哈希、白盒快照、假设和四类非生产标定场景；全部输出保持空值。 |
| [validate-growth-economy-decision-package.ps1](validate-growth-economy-decision-package.ps1) | 校验旧候选仍被隔离，并冻结 economy-v2 的数值、资格、塔结算和收据语义。 |
| [validation-report.md](validation-report.md) | 本轮 JSON、结构、语义和交叉引用验证记录。 |
| [handoff](handoff) | 为物编、地形、Lua、UI 和复审生成的五类下游简报。 |

## 状态语义

| 状态 | 含义 | 是否可进入运行时或物编施工 |
|---|---|---|
| accepted-baseline | 已由当前基线明确确认的设计契约或版本化资源表。 | 不能直接进入运行时；仍须通过独立实现、持久化和权威证明门禁。 |
| proposal | 有理由的推荐方案，等待主策明确采纳。 | 否。 |
| deferred | 已知需要，但尚无可采纳的数据或政策。 | 否。 |
| conflict | 当前来源存在互斥口径，必须先裁决。 | 否。 |
| whitebox-candidate | 离线白盒输入，只用于校准，不是生产数值。 | 否。 |

任何非 accepted-baseline 条目都必须保持 effective_value 为 null、runtime_handoff 为 false。即使是 `economy-v2` accepted-baseline，本包也不生成 Lua、Y3 物编、UI、服务端账本或生产掉落表。

标定候选使用独立的 `calibration_status=candidate`，不是新的采纳状态。它只引用登记册中已有决策并保存来源文件哈希、白盒快照、待验证假设和空的候选输出；不能借用 `proposal`、`deferred` 或 `whitebox-candidate` 的名称让任一数值提前生效。`non_production`、`observation_only` 和 `runtime_handoff` 必须是显式 JSON 布尔值；候选输出只能是 `null`。候选 JSON 使用封闭字段结构，未知字段、无关快照或未绑定白盒来源都会被拒绝。

## 已采纳的 economy-v2

1. 冻结 Lv1-Lv60 经验曲线、花果山 9,485 XP / 55 分钟锚点、Lv21-Lv60 公式曲线、来源预算、组队、级差、死亡、重连与重复结算规则。
2. 冻结 `CUR_GOLD`、`CUR_RAID_MARK`、`CUR_TOWER_TOKEN` 和三个角色绑定材料键的上限；无交易、无团队钱包，余额/堆叠封顶为整笔零奖励而非截断。
3. 冻结 `P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION`、公共资格快照、三个公共 profile 的唯一基础包参与箱路径、团队本独立稀有资格、21 个花果山 `HG_DROP_*` profile、两条保底池与首通/重复转化。
4. 冻结通天塔逐人 Lv55、团队资格快照、五拍循环首通 `3 塔币 + 3 强化碎片`、重复 `1 塔币 + 1 强化碎片`、上海时区 ISO 周桶、周额度前后值和每周 15 塔币全有或全无封顶；不发 XP、不产生保底。
5. 冻结遭遇实例级幂等终态收据、权威 owner 解析、稳定来源/奖励槽、XP 来源行/倍率/首次或重复结算、奖励计划精确投影、roll 证明/保底状态机、跨版本来源冲突、公共首通/稀有与参与箱收据绑定、团队团本资格快照、锁后决策的原子提交、前进迁移、证明解析和功能性保留期。

仍待决的是装备/法宝/宠物数值、地府/天庭每个来源 profile 的分配、塔楼层/词缀/兑换目录/赛季，以及实际运行时接入。

## 进入下一阶段的门槛

`implementation/growth/` 现已存在，但只是一套隔离的 `f6h-v1` 离线候选模拟：它只能在受信任 Node/Fengari 测试边界中运行，`runtime_handoff=false`，不得被 Y3、物编、生产账本或天庭资源表调用。它不是 `economy-v2` 的实现。将 `economy-v2` 接入任何运行时前，必须同时满足：

- 资源表被精确编译并以文件哈希/版本绑定；旧候选夹具不能作为编译输入。
- 持久化账本跨重启与重连执行来源身份、指纹冲突和原子提交；权威证明、资格快照与稀有参与箱绑定可解析。
- 参与箱只有一个 final_policy_id，且未来运行时资格字段、owner 解析、奖励投影和保底/roll 收据都与 `economy-v2` 一致；花果山旧 manifest 继续仅作候选参与证据。
- 本包的结构与语义校验通过；零付费 30/60/90 分钟验证指标已能由数据与日志覆盖。

在此之前，HG_DROP、reward_exp、reward_official_res_1 和现有白盒刷新/遭遇数值只能作为校准输入，不能成为正式经验、金币、概率、保底或货币结算数据。
