# P0 受信任外部实机采集方接入前置包

## 结论

`CAL_SPEC_EXTERNAL_CAPTURE_ONBOARDING_V1` 是 P0 的**接入准备层**：它规定未来真实 Y3 只读采集方进入既有 `evidence-adoption/` 控制面以前，必须具备哪些外部证明、隔离边界、规范化规则、工件 manifest 与独立审阅交接。

它不是采集方，不连接 Y3 编辑器或服务器，不保存原始日志、工程路径、对象键、模板、证据账本或采纳决定。

当前工作目录不存在真实 map-local Y3 工程、`script/y3/{meta,game}` 或 `ui` 根。因此本包固定为：

```text
production_gate = closed
actual_capture_provider = null
actual_y3_project_ref = null
currently_satisfied_gate_ids = []
absolute_projection_payload = null
```

## 它补上的缺口

既有 `evidence-adoption/` 已定义“什么样的外部证据才可能送审”，但不负责替未来操作者约束：谁有资格采集、真实工程如何先被验证、摘要如何规范化、何时可以交给独立审阅者。

本包补齐以下前置工件，全部为空模板：

1. 提供方资格：只读授权、隔离边界、权威时钟、工具链身份与撤销能力。
2. 来源—预检证明：把预检合同与 runner 摘要、不可变报告摘要、只读授权、权威时间及无路径泄露的工程/地图指纹绑定为外部证明。结构预检通过本身不足以证明真实地图来源。
3. 环境证明：引擎、真实工程、地图/夹具、对象库存、模板读回、时钟与工具链的冻结依据。
4. 规范化 profile：编码、字段顺序、时间格式、摘要算法与禁止非确定性输入。
5. 外部工件 manifest：将一个冻结环境族、原始工件、规范工件、输入轨迹与 scope 关联为一个外部 bundle；它不能前置或反向引用采纳决定。
6. 独立审阅交接：只可单向引用已冻结 manifest 并请求采纳机关裁决，不能替代采纳，也不能投影对象字段。

## 现场顺序

真实工程到位后，操作者应先运行既有 [Y3 施工结构预检](../../tianting-y3-construction-preflight/README.md)，并使用操作者明确给出的真实 map-local 根；不得把当前仓库根、合成目录、布局预览、离线 Lua 或 Node/Fengari 夹具当作证据源。

首轮外部采集的依赖顺序为：

```text
授权与角色分离
  → 真实 map-local 结构预检
  → 提供方资格 / 来源—预检证明 / 环境证明
  → G07 对象、模板、字段与资源库存
  → G04 引擎动作帧、攻速与移速读回
  → G05 地图碰撞、寻路与镜头读回
  → G01 十二构筑 × 三次回放
  → G02 / G03 公式观察与保留验证
  → G06 1–4 人权威回放
  → 规范化 manifest / 独立审阅交接
  → 既有 evidence-adoption 外部采纳
  → 单独绝对字段投影复审
```

这只是**采集依赖顺序**，不改变父 P0 合同中七门的唯一身份与最终采纳顺序。

## 信任边界

- 真实采集方必须是外部隔离进程，采用 JSON/IPC 或等价不可变工件传输。
- Node/Fengari 仅可作为离线测试或未来物化边界，不能成为实机采集信任根。
- 提供方、采集操作者、独立审阅者与采纳机关两两必须分离；审阅通过不等于采纳。
- 结构预检是必要条件而不是来源证明。只有绑定预检合同、runner、报告、只读授权、权威时间和工程/地图指纹的外部来源证明，才能继续环境冻结。
- 工程、地图、模板、库存、工具链、时钟或采集依据任一漂移，整个 bundle 必须拒绝，不能拼接重试。
- 本仓库只保存规则、模板和上游指纹；不保存凭证、私钥、端点、项目引用、原始日志或真实摘要。

## 校验

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\combat-calibration\external-capture-onboarding\tests\run-all.ps1
```

通过只代表接入前置工件保持 fail-closed，不代表已有受信任采集方或任何 P0 实证。
