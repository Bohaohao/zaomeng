# 地府中期法宝裁决包

## 状态

`accepted-offline-design / validation-required / production-gate-closed`

本包把地府 `Lv21–40` 的中期法宝定位、单槽兼容、可达性、前序保留与未来替换审计冻结为一个纯离线合同。它不是地府物品表、掉落表、经济表、Y3 物编或运行时实现。

## 唯一详细来源

- [地府中期法宝定位与替换合同](difu-midgame-artifact-positioning-and-replacement-contract.json)
- [地府中期法宝定位与替换原则](地府中期法宝定位与替换原则.md)
- [地府双法宝详细设计包](two-artifact-detail/README.md)
- [三篇法宝详细设计与材料来源包](../三篇法宝详细设计与材料来源包/README.md)

上位约束仍分别来自：

- [三篇成长谱系合同](../three-chapter-growth-lineage-contract.json)
- [装备、法宝、宠物与材料物编规格](../../19-装备、法宝、宠物与材料物编规格.md)
- [地府主线遭遇副本规格包](../../地府篇主线遭遇副本规格包/README.md)
- [天庭入章、完成进度与副本会话权威合同](../../天庭篇主线遭遇与通天塔规格包/authority/tianting-progression-and-instance-authority-contract.json)

## 本轮冻结

- 地府是中期构筑转向层，不是花果山法宝的强制淘汰线。
- `v1` 仍只有一个活动法宝槽；未启用法宝不默认生效。
- 未来地府标准法宝选择必须对常规路线玩家可达，但持有与装备保持可选。
- 花果山法宝保留、同槽选择与未来显式谱系迁移三条关系；不自动吞并或折算。
- 地府中期法宝恰好为**镇魂引灯**（镇魂／守序）和**勘命业镜**（勘命／破妄）两件 spec-local 设计身份；它们不是实际物品键。
- 回正／归律是“命册证据→裁决→回正”的章节共享正确结果，不由任何法宝独占、自动触发或替代。
- 镇魂引灯锚定接引院、勘命业镜锚定判官殿；锚点只说明叙事与机制时序，不是现有授予事件、来源档案或收据。
- 三篇材料来源包补充魂印灯芯、引渡丝、业镜纹、判词朱墨的设计级来源点与 D1–D3 相对难度；它不改变本包中“实际来源事件、材料键、掉落、配方、消耗与收据全部待定”的边界。
- 白骨秘境检验业镜，转轮殿检验横向协作；二者都不能成为基础取得、升级、材料或主线的唯一来源。
- 地府与天庭主线、团队本、毕业法宝均不要求任一具体法宝。

## 本轮未决定

实际法宝键、美术、数值、技能键、来源事件、掉落、资格、收据、材料键、配方、消耗、概率、保底、词条、精炼、进阶、迁移回退和 Y3 资源 ID 全部保持 `null/deferred`。展示名、材料主题、非数值技能卡与三段语义成长已在双法宝详细设计中冻结。

## 验收

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\成长数值与经济裁决包\validate-three-chapter-growth-continuity.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\validate-design-spec.ps1 -DesignPath .\docs\物编\成长数值与经济裁决包\地府中期法宝裁决包\two-artifact-detail\design-spec.json
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\score-spec-completeness.ps1 -DesignPath .\docs\物编\成长数值与经济裁决包\地府中期法宝裁决包\two-artifact-detail\design-spec.json
```

验证通过只说明设计边界完整且可交接，不代表物品、经济、Lua、Y3 对象、地图、存档或实机玩法已经完成。
