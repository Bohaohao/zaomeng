# 地府中期法宝决策登记

| ID | 决策 | 状态 | 约束 |
|---|---|---|---|
| `DF-ART-FIX-001` | 地府法宝承担 `medium` 中期构筑转向，而非花果山法宝的强制升阶。 | `accepted-offline-design` | 不以纯倍率碾压定义替换。 |
| `DF-ART-FIX-002` | `v1` 保持一个活动法宝槽。 | `accepted-offline-design` | 不新增第二槽，未启用法宝不默认生效。 |
| `DF-ART-FIX-003` | 地府提供对常规路线可达的确定性中期选择机会，但持有与装备均可选。 | `accepted-offline-design` | 不能由隐藏、稀有、团队、重复或塔内容独占。 |
| `DF-ART-FIX-004` | 花果山法宝与其长期状态必须保留。 | `accepted-offline-design` | 不自动消耗、删除、降级、折算或设为地府前序。 |
| `DF-ART-FIX-005` | 镇魂／守序、勘命／破妄是地府双法宝的两个主轴；回正／归律是章节共享结果。 | `accepted-offline-design` | 每件只有一个主轴；回正不被法宝独占、自动触发或替代。 |
| `DF-ART-FIX-006` | 地府法宝不得触碰地府/天庭准入、阎罗殿完成、死亡、清理和跨章交接边界。 | `accepted-offline-design` | 不读取或写入 `DF_PROGRESS_YANLUO_HALL_CLEARED` 作为法宝依据。 |
| `DF-ART-FIX-007` | 镇魂引灯、勘命业镜是恰好两件 spec-local 详细设计身份。 | `accepted-offline-design` | 锚定接引院／判官殿语义，不分配实际 `ART_DF_*`、事件或收据。 |
| `DF-ART-FIX-008` | 白骨秘境与转轮殿只检验横向玩法。 | `accepted-offline-design` | 不能成为基础取得、升级、材料、资格、配方或主线唯一来源。 |
| `DF-ART-DEFER-001` | 实际法宝资产、来源事件与经济归属。 | `deferred` | 需要地府 source-profile、会话事实与收据合同。 |
| `DF-ART-DEFER-002` | 数值、技能、词条、精炼、追加、进阶与配方。 | `deferred` | 需要跨职业绝对标定与物编字段回读。 |
| `DF-ART-DEFER-003` | 花果山→地府、地府→天庭的继承、共鸣、重铸或毕业替换。 | `deferred` | 需要独立谱系迁移与经济消耗合同。 |

本登记不分配实际物品键、Y3 ID、材料、货币、奖励、掉率、保底或收据。
