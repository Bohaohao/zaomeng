# 天庭物编字段预占包

`TT_SPEC_TIANTING_OBJECT_FIELD_RESERVATION` 把已经通过离线设计审查的天庭敌人、主线遭遇、七星、二十八星官与四圣，整理成可追溯的逻辑单位／技能／Buff／投射物／声音卡。

它是 `y3-object-config` 的**预规范输入**，不是可生成的 Y3-Helper `*.design.json`：本包不含 `assets`、`mode`、稳定对象键、`copyFrom`、模板、资源 ID、对象字段、绝对数值或插件脚本。

## 本包交付

- [天庭物编字段预占规格.md](天庭物编字段预占规格.md)：人可读的卡面、复用边界与后续落地顺序。
- [tianting-object-field-reservation-contract.json](tianting-object-field-reservation-contract.json)：机器可读的五十五张逻辑卡与全空字段预占模板。
- [tests/Test-ObjectFieldReservation.ps1](tests/Test-ObjectFieldReservation.ps1)：离线边界、精确文件白名单、来源路径／身份／SHA-256 快照、空绑定、P0 门禁、逻辑卡语义快照和禁止生成模型的 fail-closed 回归测试。

## 当前施工结论

`production_gate = closed`。真实物编仍同时依赖：

1. P0 跨职业绝对标定的七道投影门全部经外部独立采纳；当前机器合同还直接追溯其 `evidence-adoption` 关闭态、内容 SHA-256 与 `0/7` 快照，不能由物编侧自行改写；
2. 已读取的真实 Y3 项目对象／资源清单、稳定对象键与经确认的模板；
3. 用户针对真实工程写入的明确授权。

在此之前，卡只冻结“谁是什么、要让玩家看见什么、怎样反制、哪些东西不能共用”，不会创建单位、技能、Buff、投射物、物品、资源、Lua、地图或经济事实。

来源合同的路径、身份和内容 SHA-256 均由机器合同与测试双向锁定；五十五张卡、共享语义族和卡面结构也有独立语义快照。上游来源或卡面发生任何变更，都必须显式更新并复审该包，不能借同名 `spec_id`、附加 JSON、文本化字段或绕过子测试悄然带入真实物编数据。

## 校验

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\天庭篇主线遭遇与通天塔规格包\object-preallocation\tests\run-all.ps1
```
