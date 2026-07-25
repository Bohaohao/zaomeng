# 地府中期法宝定位与替换原则：离线验收报告

验收日期：2026-07-25
验收范围：`DF_SPEC_MIDGAME_ARTIFACT_POSITIONING_REPLACEMENT_V1` 及其对三篇成长谱系、地府主线、地府战斗可读性与经济裁决包的静态接入。

## 结论

通过。该包只冻结地府中期法宝的定位、替换边界与未来施工前置，不产生可投产的物品、能力、数值、掉落、配方、货币或收据。

“通过”仅表示离线规格在当前约束下完整、自洽且可校验；不表示已经具备 Y3 运行时、物编、美术资源、经济数值或线上投产条件。

## 已验证的合同结果

| 检查点 | 结果 | 证据 |
|---|---|---|
| 三篇成长谱系接入 | 通过 | `validate-three-chapter-growth-continuity.ps1` 返回 PASS；地府中期法宝保持 `medium` 阶段，所有实际键、来源、数值与配方仍为 `null/deferred`。 |
| 经济裁决包回归 | 通过 | `validate-growth-economy-decision-package.ps1` 返回 `ok: true`，0 errors、0 warnings。 |
| Y3 设计规格结构 | 通过 | `validate-design-spec.ps1` 返回 `ok: true`，0 errors、0 warnings；5 项未决均为刻意保留的数值、资产与经济施工输入。 |
| 规格完整度 | 通过 | `score-design-spec-completeness.ps1` 评估为 100/100、`ready`；该分数仅代表设计结构完整度。 |
| 地府主线回归 | 通过 | `validate-difu-mainline-spec.ps1` 通过，既有负向用例均保持拒绝。 |
| 地府战斗可读性回归 | 通过 | `validate-difu-combat-readability.ps1` 通过，共 170 项检查。 |
| 差异格式 | 通过 | `git diff --check` 无输出且退出成功。 |

## 冻结后的关键边界

1. 地府法宝是“中期构筑转向层”，不是花果山法宝的强制数值淘汰层。
2. v1 始终只有一个生效法宝槽；未装备法宝不提供默认战斗叠加，挑战锁定期间不能逐件换装。
3. 标准路径只保证每位玩家获得至少一次确定性的中期法宝选择机会；拥有、装备与更换均可选，不作为地府、天庭或副本进度门槛。
4. `ART_HG_TIDE_SEAL` 与 `ART_HG_FLAME_CORE` 保持既有身份与规则。未来如需跨阶段迁移，必须另行采纳谱系、经济与收据合同；本包不自动消耗、删除、降级或兑换任何旧法宝。
5. 法宝合同不得读取、写入或以 `DF_PROGRESS_YANLUO_HALL_CLEARED` 作为来源；不得把 `MAT_ARTIFACT_DUST`、`MAT_ADVANCE_HG` 推断为地府法宝配方成本。

## 尚未解除的施工前置

- P0 跨职业绝对标定结果；
- 地府来源档案与 economy-v2 收据输入的后续采纳；
- 具体法宝资产键、技能、数值、来源、掉落、材料、概率、保底、配方与消耗；
- Y3 物编、Lua、存档与玩家会话运行时实现。
