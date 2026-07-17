# 成长数值与经济裁决包验证记录

验证日期：2026-07-17。

## 结果

| 检查 | 结果 | 说明 |
|---|---|---|
| 包内 JSON 解析 | 通过 | 8 个核心 JSON（含标定候选）与 2 个生成的 JSON 交接简报均可解析。 |
| 自定义语义校验 | 通过 | 12 个决策、3 个候选货币键、21 个 HG_DROP 来源键、4 个标定场景；没有草案或候选数据进入 effective_value 或 runtime_handoff。 |
| 已采纳值负例 | 通过 | 临时把经验表的 level_cap 改为 61，校验器如预期报告 accepted_value_mismatch。 |
| 标定候选负例 | 通过 | 临时写入非空 effective_value 与伪造的白盒来源 SHA-256，校验器分别拒绝并报告 calibration_effective_value_forbidden、calibration_source_hash_mismatch。 |
| 标定候选安全负例 | 通过 | 临时注入改名经济字段、未知嵌套载荷、字符串/空值布尔门禁、空来源引用、无关快照和未绑定白盒来源；校验器分别拒绝候选输出、封闭字段结构、布尔类型、来源哈希链和场景快照绑定绕过。 |
| Y3 规格结构校验 | 通过 | 仅保留预期的 targetDurationMinutes 缺失警告。 |
| 规格完整性评分 | 100/100 ready | 只表示规格结构完整，不表示数值、政策或生产数据已经获批。 |
| 交接包生成 | 通过 | 已生成 object-config、terrain-layout、Lua、UI 与 review 五类简报。 |

## 已验证的安全边界

- 非 accepted-baseline 决策的 effective_value 均为 null，runtime_handoff 均为 false。
- 参与箱仍是 conflict，final_policy_id 为空，因此不会被视为可发放规则。
- 21 个 HG_DROP profile 全部保持 deferred，未出现有效掉落表。
- 表中没有 Y3 object ID；候选货币键、经验白盒输入、掉率、保底、强化数值和物品资产均未被伪装为生产数据。
- 资源表、收据和保底的角色归属与迁移方案仍为 proposal，必须由主策明确采纳。
- 标定候选的来源、快照、假设和场景引用均可解析；每个来源文件和白盒 manifest 的 SHA-256 已锁定，漂移会阻断校验。
- 四个标定场景均声明 JSON Boolean 的 non_production=true、effective_value=null、runtime_handoff=false；其 candidate_value 的全部字段、经验、货币、材料、概率和保底输出仍为空。
- 使用白盒输入的场景必须绑定同一 source_id 的来源快照；空、失效、重复或未绑定的来源/快照引用均会失败。
- 候选根、来源、快照、假设、场景、范围、模型选项、观测摘要和候选输出均采用封闭字段结构；任何未声明字段都会失败。

## 未解除的门禁

本包没有解除 18-20 中的生产门禁。尤其不能据此创建 implementation/growth、Y3 物编、Lua 运行时结算、UI、真实掉落表或商业字段。标定候选只定义采样与审阅工作；在获得显式采纳和实测证据前，不能替代正式数值表。
