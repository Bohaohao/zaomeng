# 镇界 Y3 接入说明

## 状态

桥接按 `y3-lualib main@fe2fb0e55a76f73490cdcbef8cbfe7a61d124d63` 的公开 API 进行离线校验，但尚未加载到真实 Y3 Lua 5.4 地图。

真实接入必须同时部署：

```text
profession_common/lua/
zhenjie/lua/
```

职业核心不直接调用 Y3；Y3 调用只在 `zhenjie_y3_adapter.lua`、`zhenjie_y3_targeting.lua` 和 `zhenjie_y3_controller.lua` 中出现。

## 项目映射

```lua
local ZhenjieController = require 'zhenjie_y3_controller'

local controller = ZhenjieController.new {
    ability_ids = {
        C02_A01 = PROJECT_ABILITY_ID,
        -- Fill C02_A01-A08 and C02_U01 after object IDs are assigned.
    },
    ability_types = { C02_A01 = '英雄' },
    modifier_ids = {
        C02_M01_JIESHI = PROJECT_MODIFIER_ID,
        -- Fill all twelve modifier IDs.
    },
    skill_by_y3_id = { [PROJECT_ABILITY_ID] = 'C02_A01' },
    distance_scale = 100,
    apply_break = function(source, target, value, command, context)
        -- Connect the project toughness/break system.
    end,
    target_rank = function(target)
        return 'normal' -- normal, elite, or boss
    end,
    resolve_cast_point = function(runtime, actor_id, skill_key, source, ability, event_data)
        -- Required for C02_A05 and C02_A08. Return an authoritative synced point.
    end,
    classify_guardable_damage = function(actor_id, unit, data, context)
        -- Return only authoritative encounter classifications.
        return { guardable_hit = false, effective_protection = false }
    end,
}
```

`distance_scale = 100` is provisional. Keep the scale gate closed until collision, camera, melee range, A04 parry readability and A08 area dimensions are checked in a real map.

## Project Hooks

- `apply_break` is required for all BOSS control conversion and break damage.
- `target_rank` is required for A02 elite/BOSS break and A08 normal/elite/BOSS branching.
- `resolve_cast_point` is required for A05/A08. The public `单位-施放技能` event does not supply a point in the checked API baseline, so this hook must use a project-owned synchronized cast record. Missing data rejects the cast; it must never default to the caster position.
- `classify_guardable_damage` is required before enabling A04/A07 resource behavior. It owns hostile/direct/periodic checks, encounter attack tags and actual barrier or reduction confirmation.
- `resolve_direction` may replace facing for synchronized vector casts.
- `resolve_cast_context` may replace default geometry; explicit IDs must also provide `target_refs_by_id`.
- `decorate_context` may add encounter data, but cannot bypass the required cast-point or damage-classification contracts.
- `on_effect_payload` handles project-specific effect payloads not represented by standard Unit attributes.
- `on_state_changed` forwards guard, Jieshi, ultimate gauge and cleanup to HUD or persistence read models.

## Guard Event Contract

`单位-受到伤害后` only forwards raw event data. A04 and A07 may resolve only after `classify_guardable_damage` explicitly returns `guardable_hit = true` or `effective_protection = true`. A04 and A07 each consume one internal guard opportunity per cast; repeated damage events must never generate additional guard, counters or ultimate value.

The controller assigns a monotonically increasing `lifecycle_id` to each registration. Any delayed hit confirmation or miss callback must return that original value to `Controller:confirm_skill_hit` or `Controller:finish_skill_miss`; missing or stale values are rejected.

All authoritative timers use `y3.timer`. Local UI and client timers may render guard, Jieshi and Buff state but cannot mutate them.

## Deferred Verification

- Production IDs, icons, models, passive template, melee template and geometry calibration.
- Actual Buff overlap/readback, shield behavior and control-state cleanup.
- Script-root loading, hot reload, four-player synchronization, reconnect and challenge traces.

None of these items becomes `verified` from offline tests alone.
