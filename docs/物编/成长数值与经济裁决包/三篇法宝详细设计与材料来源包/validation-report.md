# 三篇法宝详细设计与材料来源包｜离线验收报告

- 验收日期：2026-07-25
- 验收范围：花果山两件、地府两件、天庭一件法宝的设计级获取路线、玩法作用、推荐携带阶段、材料主题／来源点、相对难度，以及它们与既有成长、经济和章节合同的交接。
- 结论：**通过纯离线设计验收，可进入后续数值／经济／物编施工前的受控交接；不允许直接进入运行时或生产。**

## 已验收事实

| 检查项 | 结果 | 说明 |
|---|---|---|
| 五件范围 | 通过 | 花果山 `ART_HG_TIDE_SEAL`／`ART_HG_FLAME_CORE`、地府镇魂引灯／勘命业镜、天庭 `TT_SPEC_SEVEN_STAR_GRADUATION_ARTIFACT`／周天校律盘；不偷渡候选法宝。 |
| 主线与世界观 | 通过 | 花果山复刷是梦墟劫痕；地府基础来源不触碰白骨秘境／转轮殿与受保护阎罗进度键；天庭基础毕业保留七星单人＋常规主线路径，四圣噩梦可选。 |
| 经济边界 | 通过 | 仅引用 `economy-v2` 的潮印首通、炎核 `800 bp` 与合格第六次保底；地府／天庭材料均为来源蓝图，不生成掉率、物品键、数量、配方、资格或收据。 |
| 单槽与非门槛 | 通过 | 五件法宝共用一个活动槽；任何法宝均不成为入章、常规主线、团队资格或清理流程的前置。 |
| 数值门禁 | 通过 | 战斗属性、伤害、冷却、范围、目标数、精确装备等级均保持 `null/deferred`，等待 P0 标定与经济裁决。 |

## 可复现校验

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\成长数值与经济裁决包\三篇法宝详细设计与材料来源包\validate-three-chapter-artifact-detail-and-material-source.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\成长数值与经济裁决包\validate-three-chapter-growth-continuity.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\成长数值与经济裁决包\validate-growth-economy-decision-package.ps1

powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\validate-design-spec.ps1 -DesignPath .\docs\物编\成长数值与经济裁决包\三篇法宝详细设计与材料来源包\design-spec.json

powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\score-spec-completeness.ps1 -DesignPath .\docs\物编\成长数值与经济裁决包\三篇法宝详细设计与材料来源包\design-spec.json
```

执行结果：三份合同校验全部通过；设计规格结构校验为 `ok`、无 errors/warnings，完整度 `100/100 (ready)`。规格校验报告中的五项 unresolved 是刻意保留的生产门禁，而不是缺失的设计意图。

跨篇回归同时通过：地府主线合同负向测试、地府战斗可读性 `170` 项、天庭规格 `8071` 项、花果山→地府入章／常规收束证明与跨篇接口负向测试。天庭四圣铸核还被限定为四象覆环的可选展示／叙事印证，不构成基础毕业或战斗强度来源。它们证明本包没有破坏各篇既有的主线、会话、清理与进度保护边界。

## 修复记录

- 修正了材料来源合同中花果山说明页的相对路径，并让校验器对所有声明来源逐一解析，防止将来再次留下失效引用。
- 花果山说明页新增三篇法宝蓝图链接后，按候选校准包的完整性规则刷新了该说明页的来源快照哈希；未改变任何战斗、掉落或经济事实。
- 将 `D2` 从“可选单人精进”改为 `D2_NONTEAM_MECHANISM_VERIFICATION`，使其同时准确描述龙宫的可选单人精进与判官殿的常规主线非团队机制验证；不会把后者误导为可选门槛。
- 将地府中期法宝父合同列为直接上游，并回归其单活动槽、受保护 `DF_PROGRESS_YANLUO_HALL_CLEARED`、天庭非门槛等关键边界。
- 补强花果山既有经济回归：潮印重复转换 `MAT_ARTIFACT_DUST ×8`、炎核 `PITY_HG_RAID_ARTIFACT`、`800 bp`、合格第六次保底与重复转换 `CUR_RAID_MARK ×3` 均被显式断言。

## 保留的后续门禁

1. P0 跨职业绝对标定通过后，才能填写真实属性、伤害、冷却、持续时间、范围、目标数与精确装备等级。
2. 各篇 `source_profile`、资格、掉率／保底、材料数量、配方、消耗与收据必须由经济合同统一采纳；本包不具备分配权。
3. Y3 物品、能力、Lua、背包与持久化施工必须在上述裁决和对象回读完成后另行验收。

## 独立复审

花果山／天庭与地府两个独立阅读面复审均已完成：

- 花果山／天庭面确认没有改写 `economy-v2`，劫痕世界观、七星单人基础毕业、四圣可选性、十枚同星称号和防双花延后边界全部一致。
- 地府面确认白骨秘境／转轮殿未进入基础来源，阎罗进度键未被读取、写入或替代，双法宝与共享回正、单槽、前序保留和常规可达性一致。
- 复审提出的 D2 命名歧义、来源报告入口、直接父合同关联及花果山重复转换／保底回归覆盖均已修复并复跑。

最终复审结论：**P0=0、P1=0、P2=0。**
