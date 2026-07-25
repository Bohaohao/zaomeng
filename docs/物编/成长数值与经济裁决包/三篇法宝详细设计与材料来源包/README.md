# 三篇法宝详细设计与材料来源包

## 结论

本包把三篇现有法宝补全为五件可复审的离线设计：花果山的**定潮玄印**、**熔脉劫核**，地府的**镇魂引灯**、**勘命业镜**，以及天庭正式显示名为**周天校律盘**（说明性称谓“七曜毕业法宝”）的高阶构筑法宝。

它冻结的是玩法作用、主线位置、推荐携带阶段、设计级取得路线、材料主题、材料来源点和相对难度；不是运行时物品表、配方表或掉落表。

## 文件入口

| 文件 | 责任 |
|---|---|
| [机器合同](three-chapter-artifact-detail-and-material-source-contract.json) | 五件法宝、材料来源蓝图、难度阶梯、禁止项与验收矩阵的唯一机器可读来源。 |
| [可读设计](三篇法宝详细设计与材料来源.md) | 面向策划、战斗、经济与内容施工的完整说明。 |
| [决策登记](decision-register.md) | 本轮锁定项与不可越界项。 |
| [设计规格](design-spec.json) | Y3 离线设计结构、范围与交接入口。 |
| [验收报告](validation-report.md) | 静态回归、规格完整度与独立复审证据。 |
| [校验器](validate-three-chapter-artifact-detail-and-material-source.ps1) | 检查五件范围、主线锚点、材料来源、难度、单槽与空值边界。 |

## 口径

- “材料掉落点”是**设计级来源蓝图**：它说明未来应从哪一个主线／副本事实生成哪类材料意象，以及其相对难度；当前不产生材料键、数量、掉率、背包、配方、扣除、资格或收据。
- 花果山只引用 `economy-v2` 已冻结的潮印首通、炎核稀有和保底事实，不改写它们。
- 地府基础机会只能从接引院与判官殿的普通主线学习节点获得；白骨秘境、转轮殿不生产基础材料或资格。
- 天庭基础毕业只走七星单人收集加凌霄外庭的天律校印；四圣噩梦的四圣铸核只服务四象覆环的可选展示／叙事印证，不提供战斗强度。
- 所有法宝共用一个活动槽；主线、入章、清理和跨章交接均不要求某一具体法宝。

## 仍未授权的字段

战斗属性、伤害、冷却、持续时间、范围、目标数、推荐装备等级、真实物品／材料键、数量、配方、消耗、掉率、保底、资格、收据、迁移成本、Y3对象和Lua实现均保持 `null/deferred`。

这些字段依赖 P0 跨职业绝对标定、各篇 `source_profile`／资格／收据合同以及实际 Y3 对象回读；本包不能提前替代它们。

## 自检

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\成长数值与经济裁决包\三篇法宝详细设计与材料来源包\validate-three-chapter-artifact-detail-and-material-source.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\validate-design-spec.ps1 -DesignPath .\docs\物编\成长数值与经济裁决包\三篇法宝详细设计与材料来源包\design-spec.json

powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\score-spec-completeness.ps1 -DesignPath .\docs\物编\成长数值与经济裁决包\三篇法宝详细设计与材料来源包\design-spec.json
```
