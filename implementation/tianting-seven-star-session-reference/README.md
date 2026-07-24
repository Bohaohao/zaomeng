# 七星单人会话参考包（纯离线）

这是一个不可直接投产的 Node 参考模型。它把既有七星内容和权威会话的最小交集固化为可执行的测试夹具：同一角色独占会话、周天观台进度准入、七条固定路线、会话清理和请求幂等。

它不是 Y3 脚本，也不创建 Lua、地图、UI、对象、实际进度、持久化、奖励、掉落、材料、称号、资格、收据或任何经济输入。模型中的身份、令牌、完成记录和进度解析均只存在于当前 Node 进程，不能作为真实服务端实现、跨进程存档或外部交接依据。

## 冻结的引用边界

- 七星内容仅引用 `TT_SPEC_SOLO_TIANSHU` 至 `TT_SPEC_SOLO_YAOGUANG` 七条固定单人路线；请求中的未知路线一律拒绝。
- 准入只认可受信任离线提供方对同一 `owner_actor_id`、当前 `lifecycle_id` 和 `TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN` 的解析。调用方自带的进度布尔值不具权威性。
- 会话身份始终成组比较：`owner_actor_id`、`lifecycle_id`、`session_instance_id`、`session_epoch`、`revision`、`cleanup_token`。
- 状态只能 `active → cleanup_pending → closed`。死亡、超时、断线和生命周期失效只会进入清理；匹配清理确认前禁止重入，当前会话也不支持重连。
- 正常完成只留下进程内完成记录，不写入天庭三段主线进度；后续错误、延迟或重放的清理请求不能抹除该记录。
- 幂等键是 `(operation, request_id)`。完全相同的重复请求返回既有进程内结果；同键载荷漂移拒绝，避免将旧会话身份拼接给新请求。

## 运行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-seven-star-session-reference\tests\run-all.ps1
```

测试仅需要可执行的 Node.js；没有 `npm install`、网络访问或 Y3 依赖。

## 仍然关闭的门禁

- P0 的七类跨职业绝对标定证据尚未全部采纳，任何天庭单位绝对属性仍不可填写。
- P1 真实 Y3 主线纵切、真实项目结构预检、权威存储与会话适配尚未接入；本包不得替代它们。
- 七星的实际场地、首领、技能、碰撞、镜头、AI、检查点、断线传输和 UI 仍未施工。
- 所有掉落、材料、称号、毕业法宝、次数、资格、收据与 economy-v2 关系继续由后续裁决包决定；本包不产生可供其消费的输入。
