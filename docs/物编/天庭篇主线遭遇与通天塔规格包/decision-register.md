# 天庭篇与通天塔首轮决策登记

## 已冻结基础边界

| ID | 决策 | 状态 | 影响 |
|---|---|---|---|
| TT-FIX-001 | 天庭等级段为 Lv41–60，首发等级上限为 Lv60。 | fixed | 只定义章节定位，不推导经验表或时长。 |
| TT-FIX-002 | 通天塔入口要求单人或每一名团队成员均达到 Lv55。 | fixed | 不使用队伍平均等级或成员替代。 |
| TT-FIX-003 | 通天塔每五层设置构筑休整节点。 | fixed | 不定义楼层总数，也不决定小 Boss 与休整的先后。 |
| TT-FIX-004 | 玲珑塔主题并入唯一全局通天塔。 | fixed | 天庭只提供内容池接口，不能创建独立塔记录、赛季或账本。 |
| TT-FIX-005 | 首发公共地图、单人本与团队本最多四人；共享状态走权威玩法逻辑。 | fixed | 副本未来必须复用会话、成员锁、失败和清理边界。 |
| TT-FIX-006 | `DF_PROGRESS_YANLUO_HALL_CLEARED` 不是天庭门槛、写入目标或消费者。 | fixed | 天庭只可验证同角色、源自 `DF_E_YANLUO_HALL` 成功事件的跨章交接证明；不得直接消费受保护键。 |
| TT-FIX-007 | 成长、货币、掉落、保底和塔奖励由版本化资源表和幂等收据结算。 | fixed | economy-v2 仅是运行时关闭的设计引用；implementation/growth 仍禁止消费。 |

## 本轮内容设计结论

| ID | 结论 | 状态 | 约束 |
|---|---|---|---|
| TT-DESIGN-001 | 以天门倾覆、临时天庭、错误天律、四方轮值失衡和星历污染组织主线。 | offline_design | 保留“净化秩序而非只消灭守卫”的核心冲突。 |
| TT-DESIGN-002 | 常规路径为临时天庭主城 → 南天门 → 天宫道 → 天王殿外缘 → 周天观台 → 凌霄外庭。 | offline_design | 是内容路径，不是地图坐标、传送或进度实现。 |
| TT-DESIGN-003 | 凌霄外庭·裂律观台承担天庭常规主线收束。 | offline_design | 常规完成的唯一语义生产者已由权威合同指定；真实进度键、服务与实例仍为空。 |
| TT-DESIGN-004 | 旧“蟠桃园 / 御马监二选一单人本”被七星固定单人系列取代。 | fixed-user-requirement | 蟠桃园/御马监可保留为场景或支线，不再抢占单人本名额。 |
| TT-DESIGN-005 | 七星固定为天枢、天璇、天玑、天权、玉衡、开阳、瑶光；各有残片、星君称号、独立机制和展示方向。 | fixed-user-requirement | 残片运行时键、掉落、数值和称号实现均为空。 |
| TT-DESIGN-006 | 同种七星残片十枚可合成对应星君称号；七称号齐备自动解锁名称待定的集合称号。 | fixed-user-requirement | 十枚是用户固定的离线配方倍率，不是掉落量；集合称号不与单称号重复叠加。 |
| TT-DESIGN-007 | 二十八星宿是天庭常规主线后开放的最高端团队本；凌霄/杨戬方向降为主线高潮或后续故事素材。 | fixed-user-requirement | 不把团队本写成常规完成者。 |
| TT-DESIGN-008 | 十二时辰按四槽循环三次：子/辰/申青龙，丑/巳/酉朱雀，寅/午/戌白虎，卯/未/亥玄武。 | fixed-user-requirement | 以服务器 `Asia/Shanghai` 自然时辰生成并冻结 rotation_snapshot；实例中禁止换宿、客户端改时或重试重掷。 |
| TT-DESIGN-009 | 普通七宿完成产出方位夜巡钥候选；噩梦同方位四圣兽与七宿保持双向加成。 | fixed-user-requirement | 钥匙形态、消耗、归属、掉落和收据 deferred。 |
| TT-DESIGN-010 | 四圣称号经普通完成、噩梦完成与七链净宿取得；四象齐备自动取得四象镇天。 | offline_design | 无数值、无 title/cosmetic ID；集合效果不与单称号翻倍。 |
| TT-DESIGN-011 | 七星和二十八星宿可成为通天塔未来小 Boss 内容池；每三或五层尚未选择，每十层大 Boss 仅登记接口。 | fixed-user-requirement | 不绑定现有五节拍、不定义塔掉落、总层数、Boss 名单或赛季。 |

## 本轮权威合同结论

| ID | 结论 | 状态 | 约束 |
|---|---|---|---|
| TT-AUTH-001 | 建立 `TT_SPEC_PROGRESS_CHAPTER_ENTERED`、`TT_SPEC_PROGRESS_CELESTIAL_OBSERVATORY_OPEN`、`TT_SPEC_PROGRESS_MAINLINE_CLEARED` 三段角色级逻辑进度；生产者分别为天门过渡、周天观台主线节点和凌霄外庭·裂律观台权威成功。 | offline-contract-fixed | 运行时键均为 `null`；每次写入遵守 `(actor_id, event_id)` 幂等与完成收据语义。 |
| TT-AUTH-002 | 入章由权威端逐人确认达到 Lv41 与同角色的 `TT_SPEC_CHAPTER_ENTRY_HANDOFF_PROOF`（源自 `DF_E_YANLUO_HALL` 成功）。 | offline-contract-fixed | 不读写、不注册或转译 `DF_PROGRESS_YANLUO_HALL_CLEARED`；证明签发、验签与存储未实现。 |
| TT-AUTH-003 | `TT_SPEC_SESSION_LINGXIAO_MAINLINE` 是私有 1–4 人终局会话；每名入场者校验已入章，只有权威确认的有效参与者写入常规完成。 | offline-contract-fixed | 队长、旁观者、伪造成员或未授权队友不能代领；无真实实例或进度发放。 |
| TT-AUTH-004 | `TT_SPEC_SESSION_SEVEN_STAR` 复用单人会话身份与清理骨架；`TT_SPEC_SESSION_MANSION_NORMAL` / `TT_SPEC_SESSION_MANSION_NIGHTMARE` 复用团队成员快照与阶段骨架，状态为 `active → cleanup_pending → closed`。 | offline-contract-fixed | 死亡、超时、断线或生命周期失效进入失败清理；只有匹配实例身份、`session_epoch`、`revision` 和 cleanup token 的权威确认才可解除重入锁。 |
| TT-AUTH-005 | `TT_SPEC_TIME_BASIS_ASIA_SHANGHAI_SHICHEN` 在星宿会话首次成功创建时，以服务器 `Asia/Shanghai` 时辰冻结权威轮换快照。 | offline-contract-fixed | 客户端时钟、客户端方位及重试重算均禁止；真实时间提供方、存储和恢复策略仍延期。 |
| TT-AUTH-006 | `TT_SPEC_MANSION_NIGHTMARE_CREDENTIAL` 按角色逐人解析不透明凭证；每人都满足 `normal_clear.quadrant == credential.quadrant == nightmare.rotation_snapshot.quadrant`。 | offline-contract-fixed | 凭证物品形态、消耗、掉落、数量与收据仍由经济裁决包决定。 |
| TT-AUTH-007 | 建立天庭完成/会话 → economy-v2 权威收据输入交接合同；`TT_SPEC_ECONOMY_HANDOFF_SOURCE_EVIDENCE` 原子绑定同一完成 receipt/proof、会话 route/instance/epoch/revision、成员快照/状态与星宿轮换，才可形成零价值候选。 | offline-contract-fixed | 未分配 `source_profile`、slot、owner、qualification、roll、保底或任何奖励；主线成功不因 cleanup 自动结算，失败、`left` 或任意绑定字段漂移均不得成为输入候选。 |

## 明确延期

| ID | 未决项 | 阻塞原因 |
|---|---|---|
| TT-DEFER-001 | **合同语义已由 TT-AUTH-001～003 解决**；仍延期真实进度键、证明签发/验签、持久化存储、网络协议和运行时写入。 | 纯离线合同不能代替受信任运行时。 |
| TT-DEFER-002 | 真实地图、邻接、出生点、入口/出口、区域等级、对象、地形与资源。 | 当前为纯离线设计，未接入地图工程。 |
| TT-DEFER-003 | **会话身份、成员锁、失败、清理与幂等语义已由 TT-AUTH-004 解决**；仍延期真实创建、检查点、退出、锁、复活和恢复实现。 | 纯离线合同不能替代会话服务与 Y3 施工。 |
| TT-DEFER-004 | 七星残片、夜巡钥、星宿/四圣材料、装备、法宝和称号的资源表绑定、发放与收据。 | economy-v2 未分配天庭来源，且运行时账本尚未接入。 |
| TT-DEFER-005 | 全局通天塔 run、楼层计划、抽取、词缀、记录、失败恢复、赛季和奖励。 | 五节拍合同不替代全局塔合同。 |
| TT-DEFER-006 | **`Asia/Shanghai`、快照字段、冻结时点和客户端禁止项已由 TT-AUTH-005 解决**；仍延期真实时间提供方、时钟容错、存储、恢复和异常回退。 | 轮换合同不能代替时间服务。 |
| TT-DEFER-007 | Y3 对象、Lua、UI、持久化、多人同步、性能和实际美术资产。 | 需要后续专项施工。 |
| TT-DEFER-008 | 战斗数值、称号作用域、叠加细节、毕业法宝最终名称/配方/属性及四圣材料必要性。 | 需战斗、经济、物编与体验复审。 |

## 外部经济状态镜像

| 外部决策 | 当前状态 | 本包处理 |
|---|---|---|
| ECO-BASE-001：等级段、Lv55 塔门槛、每五层休整 | accepted-baseline | 精确继承为结构约束。 |
| ECO-BASE-002：装备/法宝/宠物/材料分类边界 | accepted-baseline | 只登记类别，不创建资产。 |
| ECO-QUAL-001：公共 Boss 资格四分与事件幂等 | accepted-baseline | 天庭公共内容未来复用其分层；星宿/塔不得默认套用未裁决奖励。 |
| economy-v2：曲线、塔首轮奖励和收据语义 | accepted-baseline / runtime-not-integrated | 可作设计引用；不得把七星、夜巡钥或四圣候选伪装成已存在资源键。 |
| 历史候选与 implementation/growth | proposal / deferred / offline candidate | 只能作为历史校准，不得成为天庭实现输入。 |
