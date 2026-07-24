# 二十八星宿会话、时辰与资格离线参考包

## 状态

- `package_status`: `offline-reference-only`
- `runtime_handoff`: `false`
- `production_gate`: `closed`

本包把既有二十八星宿合同的会话边界收敛为一个无外部依赖的进程内 JavaScript 参考模型。它只验证输入与状态转换，不连接任何引擎、场景、对象、持久化、网络或真实时间来源。

## 覆盖内容

- 仅接受显式注入的 `Asia/Shanghai` 权威时辰槽；模型不读取系统时间、客户端时间或本地时区。
- 首次成功建本冻结 `rotation_snapshot_id`、时辰槽、推导方位、难度、实例域、时间基准和捕获时刻；重试只能读取原快照。
- 普通与噩梦都冻结 `1–4` 位成员，并对每位成员独立验证天庭常规主线完成摘要与当前生命周期。
- 噩梦额外逐人校验不透明资格摘要，并强制 `normal_clear.quadrant == credential.quadrant == nightmare.rotation_snapshot.quadrant`。
- 断线成员转为 `left` 后不能回到当前实例，也没有当前实例完成资格；其余 `active` 成员仍可继续。
- 会话仅经过 `active → cleanup_pending → closed`；清理确认必须同时匹配实例、epoch、revision 和令牌。
- 完成写入后，即使后续清理失败或错误确认，也不会被回滚；同一操作标识的逐字段一致重放只返回首个结果。特别是创建事件重放始终返回首次冻结的 `active` 视图，不会读回后续完成或清理后的会话现态。

## 噩梦资格 fixture 与上位合同

`contract/mansion-session-time-qualification-reference-contract.json` 的 `nightmare_fixture_to_authority_crosswalk` 明确把上位 `TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL.required_fields` 作为唯一语义源。

- `opaque_credential_ref`、`credential_quadrant`、`credential_subject_lifecycle_id` 只是离线测试适配字段：前者代指不透明资格，后两者分别测试三方位关系和当前生命周期绑定。
- 上位 `nightmare_access_credential`、`nightmare_rotation_snapshot_id` 与 `owner_scope` 不由 fixture 自行定义；模型只把它们约束到已冻结成员和快照。
- fixture 不能扩展或改写上位字段，也不定义资格形态、持久化、所有权、消耗、价值或结算。

## 明确不做

- 不接入真实时间、成员、进度、资格、清理或重连提供方。
- 不创建场景、对象、界面、脚本、运行时键或持久化记录。
- 不定义绝对战斗属性、物品形态、材料、概率、保底、价值或结算结果。
- 不将本地 fixture 输入提升为可信证明；未来接入必须在参考模型之外完成真实解析与鉴权。

## 运行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-mansion-session-reference\tests\run-all.ps1
```

运行器只调用系统已安装的 Node 标准库，不安装或加载第三方包。所有 PowerShell JSON 读取均显式使用 UTF-8。

## 施工门禁

此包不解除 P3 门禁。真实二十八星宿仍需要：P1 的逐人主线完成事实、可信 `Asia/Shanghai` 时间提供方、成员/断线传输、快照与资格持久化、真实团本场地，以及 P0 的绝对字段投影采纳。详见 [施工顺序与就绪门禁台账](../../docs/物编/天庭篇主线遭遇与通天塔规格包/construction-readiness-ledger.md)。
