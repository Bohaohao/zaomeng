# 跨职业战斗绝对标定包

## 状态

- `package_status`: `offline-calibration-reference-only`
- `runtime_handoff`: `false`
- `production_gate`: `closed`
- 运行时、Y3 对象、Lua、地图、UI、进度与经济写入：均不在本包范围内。

本包是天庭相对战斗基线进入真实单位字段前的**标定控制面**。它不把缺失证据伪装成 HP、攻击、双防、攻速或技能秒数；它只把已经可证的属性锚点和白盒公式写成可测试合同，并把未证部分固定为显式门禁。

## 已冻结的事实

- C01–C04 的 Lv41 / Lv55 / Lv60 裸装属性公式与整数锚点；最终属性使用正数四舍五入 `floor(value + 0.5)`。
- D90：`[0, 5400)` tick 内合格 `final_damage` 之和；B10：所有 600 tick 窗中的最大合格伤害，平手取最早开始 tick。
- 旧 `COMBAT_REF_L60_BOSS_01` 的**物理**静态目标公式：`floor(原始物理伤害 × 100 / (100 + 180))`。它只适用于该夹具，不能推导天庭单位或泛用物理/魔法伤害。
- 夹具设计空间的移动换算：`距离 = 设计移速 × tick / 60`。这不是 Y3 的 `ori_speed`、地图坐标或动画帧回读。

## 已冻结但尚未填满的内容

`fixed_build_declaration_ledger` 覆盖全部 `4 × 3 = 12` 个职业/等级组合。当前仅 C01/C04 Lv60 有局部静态木桩构筑，C03 Lv60 有槽位配方；其余构筑、引擎帧、三次可重放日志仍保持 `blocked`。因此这些输入不能声称已完成四职业横向平衡。

泛用物理伤害、魔法伤害、双防/穿透顺序、暴击顺序与上限、命中闪避、控制抗性公式全部为 `null`。未知分支必须 fail-closed，不能从职业描述、相对压强或客户端命中结果补全。

## 天庭绝对字段投影交接

唯一机器可读交接点是 [cross-profession-combat-calibration-contract.json](contract/cross-profession-combat-calibration-contract.json) 的 `absolute_projection_gate.candidate`：

```text
target_object_or_unit_id = null
hp_max / attack_phy / attack_mag / defense_phy / defense_mag = null
attack_speed / attack_interval_seconds / move_speed_field = null
skill_damage / skill_duration_seconds = null
status = blocked
```

只有以下七项均由后续独立复审采纳，才允许创建新的投影裁决；本包不能自行把任何门禁改为通过：

1. C01–C04 在 Lv41/Lv55/Lv60 的 12 个完整构筑和三次确定性日志；
2. 泛用物理/魔法/双防/穿透公式；
3. 命中、暴击与控制抗性公式；
4. Y3 实机动作帧、攻速和移速字段回读；
5. 真实白盒场地的碰撞、路径、射程与镜头记录；
6. 不改变既有权威语义的 1–4 人战斗回放；
7. 稳定对象键、模板与真实字段回读。

本包不分配对象键，也不生成 `y3-object-config` 插件。

## 实证采集与采纳入口

[evidence-adoption/](evidence-adoption/README.md) 是 P0 的独立离线采集控制面。它把七门拆成“真实 Y3 只读采集 → 外部工件摘要/哈希 → 独立复核 → 外部授权采纳 → 另行绝对字段投影复审”的固定链路，并以主合同的字节 SHA-256 和完整七门 ID 序列绑定来源。

该子包当前没有采集提供方、真实工程引用、证据账本或采纳决定；因此任何格式正确的演练提交仍只会得到 `blocked_provider_unavailable`，不能改写 `current_satisfied_gate_ids`，更不能生成对象键、对象字段或经济输入。`synthetic-schema-test-only`、结构预检、施工发现清单、客户端声明、自由文本摘要、重复 run 与跨版本记录都不是采纳证据。

## 外部采集方接入前置

[external-capture-onboarding/](external-capture-onboarding/README.md) 是与 `evidence-adoption/` 并列的纯离线接入包。它不新增证据或采纳账本，而是为未来受信任实机采集方冻结资格、隔离进程/JSON-IPC 边界、真实工程环境证明、规范化 profile、外部工件 manifest 与独立审阅交接。结构预检仅是必要条件：还必须有外部来源—预检证明精确绑定预检合同/runner/报告、只读授权、权威时间与不泄露路径的工程/地图指纹；采集方、操作者、独立审阅者与采纳机关两两隔离，manifest 只能单向交给审阅，不能预引用采纳决定。

当前工作目录没有真实 map-local Y3 工程，因此该包的提供方、工程、环境证明、外部 manifest、审阅交接和采纳决定全部为 `null`，P0 仍为 `0/7`。它要求现场先完成 G07 对象/模板读回、G04 引擎字段读回与 G05 地图白盒读回，再进入构筑、公式和 1–4 人回放；这不改变七门最终采纳的唯一顺序。

## 运行校验

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\combat-calibration\tests\run-all.ps1
```

校验会复算四职业属性、验证旧物理夹具拒绝越界输入、测试 D90/B10、设计空间移动接口、碰撞/多人回放 schema 和绝对字段 `blocked/null` 边界，并继续运行实证采集包与外部采集方接入包的拒绝回归。测试中的 `synthetic-schema-test-only` 仅验证 schema，不是实机或权威战斗证据。

## 下游交接顺序

1. 由受信任的外部只读采集方按 `evidence-adoption/` 提交 12 个固定构筑、泛用公式、引擎读回、白盒和 1–4 人权威回放、对象/模板盘点的不可变工件引用；
2. 逐门独立复核，不接受离线 schema、客户端结果、预检或发现清单充数；
3. 在外部授权系统中记录七门采纳决定；
4. 单独复审绝对字段投影；
5. 仅在该复审通过后，由物编施工包消费已采纳的字段候选。
