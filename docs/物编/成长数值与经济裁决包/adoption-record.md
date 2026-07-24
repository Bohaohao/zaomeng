# economy-v2 基线与 economy-v3 路线覆盖采纳记录

初始采纳日期：2026-07-21
收据合同复审：2026-07-21
纯离线权威结算验收：2026-07-22
复审修订与天庭零价值收据输入交接：2026-07-22
三篇连续性复审与花果山路线覆盖：2026-07-24

## 采纳范围

用户已要求决定并冻结经验、货币、掉落/保底、公共 BOSS 参与箱 P1、通天塔奖励和持久化收据规则。初始表 [economy-v1-resource-table.json](tables/economy-v1-resource-table.json) 保留为不可改写的历史冻结证据；经收据合同复审后，当前完整资源设计基线为 [economy-v2-resource-table.json](tables/economy-v2-resource-table.json)。本轮另采纳 [economy-v3-resource-table.json](tables/economy-v3-resource-table.json) 作为**仅限未来花果山首通 XP 路线及两段必经公共主线语义**的版本化覆盖：它不能静默改写 v2、历史收据或货币、材料、掉落、保底、资格、塔、装备和法宝规则。三张表均不是 Y3、服务端或存档实现。

## economy-v2

`economy-v2` 继承并以 SHA-256 绑定 `economy-v1`，以免静默改写历史表。它新增或精确化：

1. XP 收据必须由冻结来源行、等级差倍率和首次/重复结算类型精确推导。
2. 每个奖励计划必须是冻结 bundle、首通/重复转化、稀有 roll 或塔奖励类别的全量非负投影，拒绝部分 bundle、表外额度和未绑定 grant。
3. 公共首通/稀有绑定已提交 P1 参与箱；牛魔团队的基础包、首通和稀有都绑定团队资格快照、完成事件和团本实例。
4. 所有收据统一要求权威 owner 解析、遭遇实例、证明、终态状态/结果矩阵；塔实例必须等于 `tower_run_id`。
5. 保底冻结计数初值、判定顺序、普通/强制成功、重复转化、零奖励和显式迁移记录；不持久化 `prepared` 状态。

## 本轮裁定

1. `P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION` 成为唯一公共参与箱规则；剧情参与、参与箱、稀有资格和保底继续四分，不互相推导。
2. `CUR_GOLD`、`CUR_RAID_MARK`、`CUR_TOWER_TOKEN` 均为角色绑定余额；无团队钱包、无交易，材料不伪装为货币。
3. 花果山 21 个 `HG_DROP_*` profile、两条个人保底池、首通和重复转化采用已有 `f6h-v1` 离线值作为 `economy-v2` 的设计数值来源。
4. Lv1–20 保留现有 9,485 XP / 55 活跃分钟锚点；`economy-v3` 以“可选鹏魔王或非战斗裂口发现”恰选其一消除必经缺口，历史 v2 收据不重算。Lv21–60 使用 `economy-v2` 的明确公式、累计经验和活跃时间锚点，不从白盒 `reward_exp` 推导。
5. 通天塔以五个抽象节拍为一轮：首通每角色 3 塔币 + 3 强化碎片，重复每角色 1 塔币 + 1 强化碎片，塔币按权威服务时钟的上海时区 ISO 周桶每周最多 15。团队角色还须通过 `TOWER_FIRST_CYCLE_QUALIFICATION_V1` 的逐人等级、入场、在场、存活与贡献快照；收据记录周额度前后值。封顶或余额/堆叠溢出均提交可重放的整笔零奖励收据，不截断、不邮寄、不消耗首通；失败和退出没有奖励，也不提供经验或保底。
6. 收据以角色、遭遇实例、事件、来源和奖励槽组成来源身份；来源、奖励槽与塔模式都是精确、大小写敏感的冻结枚举。资源表版本、资格快照、roll、保底池、公共参与箱引用、XP 的输入/输出、塔运行身份、周额度前后值和奖励计划组成指纹。相同身份相同指纹只重放原终态结果；不同版本或任一指纹差异都是终态冲突，不能借升级表版本重发历史事件。
7. `P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION` 是三个公共 profile 的唯一基础包结算路径：参与箱收据记录 profile 和政策，公共首通与公共稀有必须绑定同角色、同 profile、同遭遇实例、同事件、同资格快照、同版本的已提交参与箱收据。团队团本稀有只使用独立团队资格快照，不继承公共参与箱前置。
8. 所有长期状态采用锁后决策、同一可串行化事务的终态收据模型；不持久化 `prepared` 状态。中断重试只能携带同一组权威输入，已终态收据只会重放；向前迁移不重算旧收据。

## 非实施边界

- `implementation/growth/` 仍是 `f6h-v1` 的 Node/Fengari 离线测试夹具，不是 `economy-v2` 的运行时实现。
- 本轮生成了独立的 Node 内存结算参考与 Tide Trace 离线 Lua 适配器，并已通过受信任 Node/Fengari 验收；没有生成 **Y3 运行时** Lua、Y3 物编、地图、存档后端、对象 ID、UI、交易、兑换商店或多人同步。
- 离线参考实现只证明冻结表编译、proof-to-owner 夹具、origin 防换主、终态收据、重放/恢复和七类已冻结事件的合同一致性；它不是生产账本、真实证明服务或运行时接入授权。
- 本轮数值作为版本化设计基线冻结；实机日志可以提出新版本，不得静默改写 `economy-v3`、`economy-v2`、`economy-v1` 或历史收据。地府与天庭的具体 XP source_profile 分配、塔楼层/词缀/赛季和装备/法宝/宠物数值不在本次采纳范围。

## 2026-07-22 复审修订与天庭交接

本轮对独立离线验收包的复审补齐了三类防漂移边界：外部花果山 Tide Trace fixture 必须是完整哈希闭包，保留原型 map key/畸形塔周桶/越界 XP 必须 fail-closed，Tide canonical evidence 必须经 resolver attestation 绑定到回放与奖励计划指纹。所有修订仍在 Node/Fengari 纯离线参考中完成，未改变资源表数值或生产门禁。

同时建立[天庭完成/会话 → economy-v2 权威收据输入交接合同](../../../implementation/economy-v2-authoritative-settlement/contract/tianting-authority-receipt-input-contract.json)。`TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 把同一完成 receipt/proof、route/instance/epoch/revision、成员快照/状态与星宿轮换原子绑定；它只冻结这些来源事实与资格边界、重放、断线和 cleanup 规则。在独立采纳天庭 source-profile 前，`source_profile`、slot、owner、资格、roll、保底、经济收据和一切奖励值均保持 `null/deferred`，且合同不得调用 materializer。

## 2026-07-24 三篇连续性修订与 economy-v3

复审发现原 `economy-v2` 的花果山首次路线把可选鹏魔王的 `500 XP` 计入了通往 Lv20 的总额；跳过它的玩家会在不触碰任何错误内容的情况下少 `500 XP`。因此新增 `economy-v3` **限域覆盖**，而不是修改 v2：`XP_EASTSEA` 从 `900` 调整为 `1490`、`XP_CHAPTER_CLEAR` 从 `1735` 调整为 `1145`，并新增非战斗 `XP_HG_CRACK_DISCOVERY=500`。同一未来路线必须在 `XP_PENG` 与裂口发现之间恰选其一，两个分支都在常规收束前到达 `8340 XP / Lv19`，结算后仍为 `9485 XP / Lv20`。同一覆盖还明确：历史 `XP_PEACH=side_quest` 与 `XP_CAVE=solo_instance` 的记录不改、历史收据不重算，但未来首通路线分别只绑定桃林／蝙蝠窟的必经公共主线语义，不产生 source profile、单人本、奖励或运行时映射；不得双领，也不得把鹏魔王、龙宫、牛魔旧战场、团队、稀有或通天塔设为章节门槛。

[三篇成长谱系合同](three-chapter-growth-lineage-contract.json) 同时冻结了：同角色 `Lv20 + 花果山常规收束证明` 入地府、地府开局以既有 `1250 XP` 门槛进入 Lv21 成长带、同角色 `Lv41 + 阎罗殿不透明成功证明` 入天庭，以及 Lv20→41→60 的非运行时预算。它不分配真实 `source_profile`、奖励、对象、经济收据或运行时键；后续施工必须将基表、覆盖层、交接证明与权威收据在同一受审计编译边界接入。
