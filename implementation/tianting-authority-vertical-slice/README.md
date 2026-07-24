# 天庭权威运行时基座与主线纵切（离线测试包）

这是一个不可直接投产的纯离线 Lua 参考包。它只把已冻结的天庭权威合同收敛为可执行的白盒模型：`入章 → 周天观台 → 凌霄外庭`。

它不是 Y3 地图脚本、不是进度/存档服务，也不创建任何真实资源、事件、物品、奖励、经济收据或地图对象。

## 覆盖边界

- 入章只接受权威端确认的 Lv41 与同角色 `DF_E_YANLUO_HALL` 成功交接证明；Lua 代码不读取、写入或登记 `DF_PROGRESS_YANLUO_HALL_CLEARED`。
- 三段角色级逻辑进度按 `TT_SPEC_PROGRESS_CHAPTER_ENTERED → TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN → TT_SPEC_PROGRESS_MAINLINE_CLEARED` 顺序写入；前置收据必须匹配当前 `actor_lifecycle_id`，且 `(actor_id,event_id)` 只会在全部绑定收据字段不漂移时回放既有结果。
- 凌霄外庭只冻结 1–4 名权威成员。旁观者、队长代领、未冻结成员、旧生命周期和伪造成员均不能获得完成。
- 会话只会经过 `active → cleanup_pending → closed`；释放重入锁必须匹配实例、epoch、revision 与 cleanup token。已确认的常规完成不会因之后清理失败而回滚。

`resolve_yanluo_handoff` 在这个离线模型里只接受受信任提供方已经验证完成的交接信封；fixture 为了聚焦主线纵切而缩减了信封外形，但不表示调用者可以提交一个裸的 `source_success=true` 布尔值作为证明。未来接入时，完整同角色、来源事件、会话身份、生命周期和权威证明的验证必须先发生在该解析边界之外。

## 为什么这里仍使用 Node/Fengari

Lua 逻辑本身是引擎无关的；Node 仅作为离线测试宿主，Fengari 仅作为受控 Lua 执行器。`tests/run-all.ps1` 复用花果山包已固定的受信任执行边界：验证 Node 身份和固定 Fengari 闭包、校验测试文件哈希、清空/拒绝 `NODE_*` 与 `LUA_*` 注入，并扫描本包 Lua 不含 Y3 API。

因此 `NODE_PATH` 不是用来找模块的配置项，而是必须拒绝的注入面：本包不从 `NODE_PATH` 加载任何依赖。

## 运行

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-authority-vertical-slice\tests\test-execution-boundary.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-authority-vertical-slice\tests\run-all.ps1
```

运行前提是同一受信任执行主体在单次调用内控制本包、继承的离线运行器、选中的 Node 和固定的 Fengari 闭包。它并不声称可对抗并发本地路径替换，也不等同于生产级密钥、存档或服务端隔离。

## 后续边界

- 七星、二十八星宿和四圣运行时尚未开始；它们仍只受规格合同约束。
- economy-v2 只能读取已批准的零价值权威来源事实，不能被本包直接调用。
- 接入真实 Y3 前，必须另行批准并绑定真实地图根、对象、持久化、权威提供方和网络协议。
