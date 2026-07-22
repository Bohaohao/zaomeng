# economy-v2 权威结算内核：纯离线验收报告

## 当前结论

- 报告状态：`offline-acceptance-passed`
- `package_status`：`offline-acceptance-reference-only`
- `runtime_handoff`：`false`
- `production_gate`：`closed`

本包已通过可重复的纯离线验收。它验证的是冻结表编译、canonical Tide Trace 适配与完整外部 fixture 闭包、受信任 proof-to-owner/origin-binding 夹具、Tide evidence attestation、终态收据状态机、HMAC 保护的离线恢复模型、天庭零价值输入交接和受信任 Node/Fengari 执行边界；它不是 Y3 运行时、真实服务端账本、真实权威证明服务或生产迁移实现。

## 已执行证据

> 文件系统前提：本报告的 Node/Fengari/编译器结论只在包根、输出父目录、选中的 Node 和固定 Fengari 闭包在单次运行中由受信任主体独占时成立。它拒绝已观察到的非目录/符号链接输出父路径、解析到包外的输出路径与环境注入；不声称用路径 API 对抗检查后的并发本地目录或可执行文件替换。

在工作区根目录运行：

```powershell
implementation/economy-v2-authoritative-settlement/tests/run-all.ps1
```

该入口依次验证：

- 精确输入编译门：原表 SHA-256、版本、关闭门禁、BOM、重复 JSON key、路径与候选/旧版本漂移；
- Node 签名/固定 `v20.19.5` 字节哈希二次核验，`NODE_OPTIONS`、`NODE_PATH`、`LUA_*` 与假 `node.exe` PATH 注入负例；
- 固定 Fengari `0.1.0` 闭包、`-E` 执行，以及 Lua/Y3 API 隔离；完整外部 Tide Trace fixture 闭包在每次执行前后复核，并以受控 scratch root 进行 API 隔离扫描；
- 真实 `huaguoshan_public_trace` 状态机生成的 `trace_action_completed`，经独立适配器输出固定 v2 `drop_bundle/HG_DROP_WATERFALL_ELITE/base_bundle` intent；Fengari 输出先与独立 canonical evidence 精确对照，才进入 Node 参考结算器；
- 编译基线篡改、可变 request/baseline/恢复对象的 getter 交换、authority profile/event 伪造、proof 换主（包含已拒绝来源）、Tide attestation 漂移、裸/篡改/HMAC 失配重启状态、保留原型 map key、残缺或重复 owner 的 P1/团队/塔快照、保底计数/分支失配、无效 XP 等级、首通重复、收据、重放/重启、冲突、P1、团队稀有、XP、塔、封顶和故障原子性回归；另有天庭交接的字段/资格/重放/断线/清理/零价值交叉合同断言。

## 验收矩阵

| ID | 结果 | 离线证据 |
| --- | --- | --- |
| AC-01 | 通过 | 精确原表字节、SHA、版本、关闭门禁与篡改 compiled baseline 拒绝。 |
| AC-02 | 通过 | 真实 Tide Trace canonical evidence、独立固定 evidence 对照、适配、stable owner 与可信 resolver origin binding 夹具解析。 |
| AC-03 | 通过 | 客户端 owner、内联奖励、无效 proof、authority profile/event 伪造、已提交/已拒绝来源的换主 proof、伪造/缺失 snapshot 与 roll 拒绝。 |
| AC-04 | 通过 | 相同请求、字段乱序和 HMAC 快照恢复后的终态收据重放；裸状态、HMAC/内容失配和 getter 状态交换均拒绝导入。 |
| AC-05 | 通过 | 同一六元身份下的表版本/输入漂移返回 `receipt_identity_conflict`。 |
| AC-06 | 通过 | proof ref 不进入请求指纹；当前 proof 仍须重新解析同一 owner/event/instance。 |
| AC-07 | 通过 | `experience`、`drop_bundle`、`participation_chest`、`first_clear_grant`、`public_rare_drop`、`team_raid_rare_drop`、`tower_reward` 的表驱动投影，及收据条件字段/空值规则。 |
| AC-08 | 通过 | 余额/堆叠、稀有重复转化、塔周额度均为全有或全无零奖励；不消耗首通/保底。 |
| AC-09 | 通过 | `committed/rejected` 仅两种终态；重放、冲突、拒绝和故障注入不留下经济副作用或 `prepared`。 |
| AC-10 | 通过 | API 隔离及 Node/Fengari 环境、PATH、固定签名 Node、闭包、`-E` 与完整外部 Tide Trace fixture 闭包回归；前提是声明的受信任文件系统独占条件。 |
| AC-11 | 通过 | 保留原型 map key、畸形塔周计数器、不安全 owner 与越界 XP 等级均被拒绝，状态不变。 |
| AC-12 | 通过 | Tide Trace attestation 对完整 canonical evidence 绑定；来源 evidence 或 attestation ref 漂移冲突。当前 proof 仍逐次复验，且要回放必须复用同一 evidence-stable attestation ref。 |
| AC-13 | 通过 | 天庭完成/会话仅映射为零价值输入候选；source-profile 未分配时不可形成结算请求或经济收据。 |

## 本轮复审修订与可复现结果

初审发现外部花果山 fixture 的动态加载未形成完整可信闭包、塔周桶可被原型键绕过，以及 XP、Tide 证明绑定和 Lua/Node 标识符边界的离线 P2。修订后，最终 runner 的实际输出为：

```text
PASS: 225 economy-v2 settlement assertions
PASS: 395 economy-v2 TianTing authority-handoff assertions
PASS: 83 economy-v2 Tide Trace adapter assertions
```

外部 fixture 闭包校验另计 `186` 条断言，并已在每个 Fengari 调用的前后复核。上述数字仅说明离线回归覆盖；它们不把内存参考、Node、Fengari 或交接 JSON 提升为生产服务。

## 未解除的生产门禁

以下事项不属于本包已通过的结论，仍必须独立设计、实现和复审：

- 可持久化且可串行化的生产账本、跨进程锁与灾难恢复；
- 真实 authority proof、资格快照、稀有 roll 与 owner 映射服务；
- 真实 resolver origin-owner 持久绑定、密钥管理、重连/迁移/保留期处理，以及生产可观测性与审计；
- Y3 地图脚本根、对象/物编、UI、网络协议和实机多人验收；
- 地府、天庭的新来源 profile、数值分配与平衡验证；天庭已具零价值输入交接，但尚未获得任何 source-profile 或奖励映射授权。

因此，任何后续运行时实现都必须独立复现本包合同并再次接受生产级审查；不得直接提升本内存参考模型或 `implementation/growth/` 的 `f6h-v1` 候选夹具。
