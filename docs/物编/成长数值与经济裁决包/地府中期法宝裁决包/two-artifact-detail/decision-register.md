# 地府双法宝详细设计：决策登记

| ID | 决策 | 状态 | 边界 |
|---|---|---|---|
| `DF-ART-DETAIL-FIX-001` | 地府中期法宝恰好为镇魂引灯、勘命业镜两件。 | `accepted-offline-design` | 仅为 spec-local 身份；不分配 `ART_DF_*`、Y3 或运行时键。 |
| `DF-ART-DETAIL-FIX-002` | 两件主轴分别是镇魂／守序、勘命／破妄。 | `accepted-offline-design` | 每件只有一个主轴，不能被做成万能法宝。 |
| `DF-ART-DETAIL-FIX-003` | 回正／归律是地府全篇共享正确结果。 | `accepted-offline-design` | 不由任意法宝拥有、自动触发或替代。 |
| `DF-ART-DETAIL-FIX-004` | 镇魂引灯锚定接引院，勘命业镜锚定判官殿。 | `accepted-offline-design` | 是常规主线语义锚点，不是现有授予事件、资格或奖励来源。 |
| `DF-ART-DETAIL-FIX-005` | 白骨秘境检验业镜，转轮殿检验两件的横向协作。 | `accepted-offline-design` | 二者不能成为基础取得、升级、材料或准入的唯一来源。 |
| `DF-ART-DETAIL-FIX-006` | 两件均先要求玩家亲自完成核验，再提供可读反馈。 | `accepted-offline-design` | 禁止自动判真、自动裁决、自动回正和跳机制。 |
| `DF-ART-DETAIL-DEFER-001` | 实际授予、拥有、升级与迁移。 | `deferred` | 需要权威来源事实、资格、收据和持久化。 |
| `DF-ART-DETAIL-DEFER-002` | 属性、伤害、CD、时长、范围、目标数和状态效果。 | `deferred` | P0 外部实证仍未采纳，绝对投影关闭。 |
| `DF-ART-DETAIL-DEFER-003` | 材料键、数量、配方、消耗、掉率、保底与货币。 | `deferred` | 需要地府 source-profile 与经济裁决；不可挪用花果山材料。 |
