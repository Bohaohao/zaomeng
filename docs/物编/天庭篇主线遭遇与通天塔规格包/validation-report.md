# 天庭篇离线规格验证记录

## 结论

验证日期：2026-07-22。内容深化与 economy-v2 收据输入交接后的离线校验全部通过。结果只证明规格、边界、内容合同和交接字段自洽；不代表天庭地图、对象、Lua、UI、时间服务、多人、存档或经济结算已实现。

| 校验 | 命令结果 | 结论 |
|---|---|---|
| 包内边界与内容合同校验 | VALIDATION PASSED: 1887 checks | 既有等级、跨篇、经济、塔首轮五节拍和运行时键边界仍通过；新增三段天庭逻辑进度、阎罗殿不透明交接证明（不消费地府进度键）、私有主线终局、七星/星宿逐人准入、`Asia/Shanghai` 冻结快照、同方位逐人噩梦资格、断线离场、含 `revision` 的清理确认与完成不回滚均通过。 |
| economy-v2 双向交接校验 | PASS: 395 assertions | 天庭与 economy-v2 的互链、`TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 的完成 receipt/proof/快照原子绑定、封闭路由映射、资格快照边界、重放/断线/cleanup 规则、全量 `null/deferred` 经济字段与无 source-profile 结算禁令均通过。 |
| 设计规格结构校验 | ok: true；errors: [] | 规划字段、会话流程、内容桶、MVP、交接、验收和内容深化合同引用均有效。 |
| 设计完整度校验 | 100/100；grade: ready | 设计层字段完整；不会把 deferred 内容提升为生产资产。 |
| 差异空白检查 | git diff --check 通过 | 本包变更无空白错误。 |

## 预期提示

设计规格校验仅报告一条预期提示：targetDurationMinutes = 0。单次时长尚无批准来源，保留为未裁定而不臆造数值。另有六项 unresolved，它们是生产门禁，不是应自动填充的设计空值。

## 本轮关键验证点

- 七星精确为天枢、天璇、天玑、天权、玉衡、开阳、瑶光；每星有对应残片、星君称号、独立机制与展示方向。
- 同种七星残片十枚合成对应星君称号；七称号聚合称号名称保持待定，且不与单称号重复叠加。
- 二十八星宿精确为四象各七名、全名无重；每名保留签名动作。
- 十二时辰完整映射为三轮四象，并规定入场权威 rotation_snapshot 锁定副本方位。
- 三段天庭逻辑进度均只有唯一生产者，按 `(actor_id, event_id)` 幂等；阎罗殿交接只验证同角色、源自 `DF_E_YANLUO_HALL` 成功事件的不透明证明，绝不读取、写入或注册 `DF_PROGRESS_YANLUO_HALL_CLEARED`。
- 主线终局、七星和星宿均验证冻结成员与当前生命周期；清理确认同时比对实例身份、`session_epoch`、`revision` 和 `cleanup_token`，且已确认成功不受后续清理失败影响。
- 噩梦保留七宿→四圣的七条宿曜贡辉和四圣→七宿的七条圣兽庇护；数值与 Buff ID 为空。
- 普通到夜巡钥只表达用户指定的设计语义，钥匙形态、消耗、数量、掉落、收据未定。
- 七星/星宿仅是未来全局通天塔内容池；小 Boss 三或五层未选，十层大 Boss 名单与塔掉落未定。
- 天庭仍未默认消费或写入 DF_PROGRESS_YANLUO_HALL_CLEARED，且未伪造 economy-v2 资源键或 tower_mode。
- 新交接合同只保留由 `TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 从同一完成 receipt/proof、冻结会话与星宿轮换原子绑定的来源事实；未经独立批准的 source profile 之前，不可调用 economy-v2 materializer、创建经济实例/收据，也不可把噩梦准入凭证或 cleanup 成功变成奖励资格。

## 可复现命令

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\docs\物编\天庭篇主线遭遇与通天塔规格包\validate-tianting-tower-spec.ps1
node .\implementation\economy-v2-authoritative-settlement\tests\test-tianting-authority-handoff.js
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\validate-design-spec.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\design-spec.json
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Administrator\.codex\skills\y3-design-spec-normalizer\scripts\score-spec-completeness.ps1 -DesignPath .\docs\物编\天庭篇主线遭遇与通天塔规格包\design-spec.json
git diff --check -- .\docs\物编\天庭篇主线遭遇与通天塔规格包
~~~
