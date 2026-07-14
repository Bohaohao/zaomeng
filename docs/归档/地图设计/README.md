# 地图设计阶段归档

## 归档状态

- 归档日期：`2026-07-11`。
- 阶段状态：地图宏观结构和花果山第一版白盒已完成，当前冻结为物编设计的空间约束。
- 本目录保存设计文档、结构化 JSON、HTML 预览、PNG 预览和施工报告，不代表已经写入 Y3 编辑器。
- 后续如果实机白盒验证推翻战斗场尺寸，只修改对应区域参数，不直接重做六层世界拓扑。

## 当前有效基线

1. [地图与多主城结构](01-地图与多主城结构.md)
2. [世界篇章与地图扩展蓝图](11-世界篇章与地图扩展蓝图.md)
3. [首发地图推理基线与验证 TODO](13-首发地图推理基线与验证TODO.md)
4. [花果山 96x72 白盒拆分](14-花果山96x72白盒拆分.md)
5. [花果山 96x72 施工报告](terrain/huaguoshan-96x72/layout-report.md)

当前核心参数：

- 单关卡六层世界，中心区域先施工，外围按 `64 terrain cell` 批次扩容。
- 首发总图工作基线为 `384x320 terrain cell`。
- 花果山可玩场景为 `96x72 terrain cell`。
- 龙宫四房位于四海层，牛魔旧战场位于梦墟层；花果山只保留入口和集结点。
- 花果山三个传送点覆盖主城、副本枢纽和团队本入口。

## 历史方案

- [六层世界 Tile 比例与总图尺寸](12-六层世界Tile比例与总图尺寸.md)保存一次性 `640x512` 容量方案，仅用于追溯。
- [旧版花果山 360x260 施工报告](terrain/huaguoshan/layout-report.md)把龙宫四房和牛魔战场放入花果山本体，不再作为当前施工口径。
- [六层世界早期布局报告](terrain/world-layout/layout-report.md)、[中心扩容版报告](terrain/world-layout/center-expansion/layout-report.md)和[东胜神州大区报告](terrain/world-layout/east-shengzhou/layout-report.md)用于记录方案演变。

## 工件目录

```text
terrain/
├─ huaguoshan/              旧版花果山局部方案
├─ huaguoshan-96x72/        当前花果山白盒基线
└─ world-layout/            六层世界、中心扩容与东胜神州历史布局
```

每套完整布局包含：

- `layout.json`
- `layout-preview.html`
- `layout-preview.png`
- `layout-preview.meta.json`
- `layout-report.md`

## 交接给物编的空间约束

- 普通怪和精英应按现有区域职责设计，不在物编阶段擅自增加新的完整地图区域。
- 猕猴王候选战斗场为 `24x18`；蛟魔王、鲨魔王候选战斗场为 `23x21`。
- 狮驼王守门段为 `13x20`，鹏魔王高崖侧袋为 `17x16`。
- 公共主路候选宽度为 `8 cell`，普通支路为 `6 cell`，BOSS 入口为 `10 cell`。
- 位移、击退、召唤物数量和技能预警半径必须按上述候选空间设计，并保留实机缩放参数。
