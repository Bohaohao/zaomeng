# 天庭 Y3 施工前置预检

这是一个独立的、只读的结构预检包。它用于回答“一个外部提供的地图目录是否具备进入天庭 Y3 施工的最低目录前提”，而不是创建任何施工内容。

它不会创建或编辑地图、地形、对象、`editor_table` JSON、Lua、UI、对象键、地图键或资源键。通过预检也不表示可以投产：实际编辑器回读、Y3 API 签名核验、对象接口可用性、权威服务、P0 绝对数值和多人验证仍是独立门禁。

## 检查范围

必需参数 `-TargetMapRoot` 指向一个已经存在的、地图本地式 Y3 地图根。预检只接受以下结构：

```text
<TargetMapRoot>/
  script/
    y3/
      meta/
      game/
  ui/
```

- `script/` 是未来地图 Lua 的合法候选根，但本包不写入任何 Lua。
- `script/y3/meta` 与 `script/y3/game` 只证明 Y3 库根的最低结构存在；每个实际 API 仍必须在真实 `y3/` 源码或参考库中逐项核对。
- `ui/` 只证明 UI 根目录存在；本包不创建、读取或验证 UI 节点、Y3 UI JSON 或 `.upui`。
- `-ObjectInterfaceIdentifier` 可以省略。若提供，它只能是小写的点分接口名，例如 `object-editor.adapter`；它不是对象 ID，也不会被调用或当作可用性证明。

## 使用

对一个已由编辑器创建并已回读的地图根执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-y3-construction-preflight\tests\Invoke-TiantingY3ConstructionPreflight.ps1 `
  -TargetMapRoot 'D:\path\to\existing\EntryMap' `
  -ObjectInterfaceIdentifier 'object-editor.adapter'
```

机器可读输出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-y3-construction-preflight\tests\Invoke-TiantingY3ConstructionPreflight.ps1 `
  -TargetMapRoot 'D:\path\to\existing\EntryMap' -AsJson
```

当前仓库根本身是预期失败样本：它没有真实 Y3 地图根、`script/y3` 或 `ui`。预检失败是正确结果，不能通过在本仓库补建这些目录来绕过。

## 测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\tianting-y3-construction-preflight\tests\test-preflight.ps1
```

测试在系统临时目录内根据 `tests/fixtures/synthetic-complete-directory.json` 创建一个仅含目录的合成结构。它不创建 `maps/`、Lua 文件、UI 节点或任何 Y3 对象；成功只说明预检的失败关闭逻辑与结构报告正确。

## 施工后的下一道门

结构预检通过后，仍应依次执行：读取真实地图与资源清单、确认脚本入口、核对真实 `y3/` API 源码、使用编辑器/MCP 或 `y3-obj-edit` 创建对象、回读对象与 UI 节点树、接入权威服务，并完成单人与四人实机验证。不得手写 Y3 工程 JSON。
