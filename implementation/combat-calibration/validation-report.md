# 跨职业战斗绝对标定包：离线验证报告

## 结论

`implementation/combat-calibration/` 通过离线合同和参考实现验证，但仍是 `offline-calibration-reference-only`。它已将四职业裸装锚点、旧物理静态夹具、D90/B10、动作/移动、场地碰撞与 1–4 人回放所需的证据格式收口为可测试边界；`evidence-adoption/` 将真实采集、摘要/哈希、独立复核和外部采纳分层，`external-capture-onboarding/` 再将来源—预检证明、四角色两两隔离与单向 manifest 审阅边界冻结，但没有生成任何真实战斗数值、对象键、插件、Lua、地图或经济结果。

## 已执行

| 检查 | 结果 |
| --- | --- |
| `tests/test-calibration.js` | 通过，37 条断言：四职业 12 个属性锚点、半上取整、旧物理公式拒绝越界、D90/B10、设计空间移动、碰撞/回放 schema、绝对字段 null 门禁。 |
| `tests/test-execution-boundary.ps1` | 通过：运行时 handoff 关闭、无 Lua、无 Y3/`GameAPI` 标记、绝对对象字段全为 null。 |
| `evidence-adoption/tests/test-evidence-adoption.js` | 通过，65 条断言：父合同字节指纹、七门空模板、精确 envelope、静态门级 scope/覆盖预览、可信外部引用形状、独立复核和三份支撑模板的深层字段白名单；拒绝假证据、自由文本摘要、非法时间、重复 run、重复队伍规模、混版本、对象键/目标选择器/嵌套投影字段注入、伪造合同扩展、伪造 token/采集链/采纳态、scope 漂移、模板隐藏采纳/投影字段、原型链/不可枚举/getter/symbol 隐藏字段和自我采纳。 |
| `evidence-adoption/tests/test-execution-boundary.ps1` | 通过：没有采集提供方、真实工程、证据账本、采纳决定或投影；无 Lua/Y3 运行时文件。 |
| `external-capture-onboarding/tests/test-external-capture-onboarding.js` | 通过，29 条断言：三份上游来源 SHA-256、七门 0/7、外部隔离/JSON-IPC 边界、四角色两两隔离、真实 map-local 预检的合同/runner 摘要与来源—预检证明、首次现场采集顺序和六份空接入模板均保持关闭；拒绝本地提供方、端点、环境摘要、预检冒充真实来源、Node/Fengari 信任根、manifest 采纳循环、审阅自我采纳与隐蔽资格字段。 |
| `external-capture-onboarding/tests/test-execution-boundary.ps1` | 通过：当前工作目录不注册提供方、不保存凭证/端点/工程/环境/manifest/审阅/采纳，不授权 Y3、Lua、地图、UI、经济或奖励写入。 |
| `tests/run-all.ps1` | 通过。 |
| JSON 解析 | `package-contract.json` 与主合同通过 Node JSON 解析。 |
| `git diff --check -- implementation/combat-calibration` | 通过。 |

## 当前阻塞

以下不是本包可自行补写的空白，均需后续独立实机/设计裁决：

1. 受信任的外部只读采集提供方，以及 C01–C04 在 Lv41、Lv55、Lv60 的 12 个完整构筑与每份三次确定性动作日志；
2. 泛用物理/魔法伤害、双防/穿透、暴击、命中/闪避、控制抗性公式；
3. 真实 Y3 的动作帧、攻速、移速字段、射程与模板回读；
4. 真实白盒场地的碰撞、寻路、镜头与安全落点记录；
5. 与既有天庭权威合同兼容的 1–4 人回放；
6. 已审定的天庭单位稳定对象键和模板字段；
7. 外部逐门采纳账本与七门齐备之后、绝对字段投影之前的独立投影复审。

在以上七项全部被独立采纳前，`TT_CAL_ABSOLUTE_OBJECT_FIELDS_V1` 中的 `hp_max`、双攻、双防、攻速、移速、技能伤害与秒数，以及目标对象/单位 ID 均必须保持 `null` / `blocked`。
