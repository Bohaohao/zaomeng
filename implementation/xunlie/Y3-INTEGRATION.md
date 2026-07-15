# 巡猎 Y3 接入说明

## 状态

`C04` 已完成离线桥接验证，固定在 `y3-lualib main@fe2fb0e55a76f73490cdcbef8cbfe7a61d124d63`。真实主目标、选区、点位、落点、品级、命中、遭遇快照和地图生命周期尚未绑定，不能据此宣称已在地图中可用。

真实接入需同时部署：

```text
implementation/profession_common/lua/
implementation/xunlie/lua/
```

## 必需项目回调

```lua
local XunlieController = require 'xunlie_y3_controller'

local controller = XunlieController.new {
    ability_ids = { C04_A01 = PROJECT_ABILITY_ID },
    ability_types = { C04_A01 = '英雄' },
    modifier_ids = { C04_M01_HUNT = PROJECT_MODIFIER_ID },
    unit_by_actor = function(actor_id) end,

    resolve_primary_target = function(runtime, actor_id, skill_key, source, ability, event_data)
        -- A01/A03/A06/A07/U01: return one live, authoritative Unit.
    end,
    resolve_selected_targets = function(runtime, actor_id, skill_key, source, ability, event_data)
        -- A05/A08/U01: return all legal in-range candidates. The C04 bridge
        -- applies its private-mark or distance ordering and final target cap.
    end,
    resolve_cast_direction = function(runtime, actor_id, skill_key, source, ability, event_data) end,
    resolve_cast_point = function(runtime, actor_id, skill_key, source, ability, event_data) end,
    resolve_safe_landing = function(runtime, actor_id, skill_key, source, ability, event_data) end,
    resolve_pulse_targets = function(actor_id, pulse_key, command, cast_context)
        -- Missing or empty results deliberately produce no pulse damage.
    end,
    target_rank = function(target) return 'normal' end,
    target_distance = function(source, target) return 0 end,
    resolve_combat_scope = function(runtime, actor_id, source, event_data) return 'public' end,
    report_boss_contribution = function(event) end,
}
```

`target_rank` may only return `normal`、`elite` or `boss`; other values are `unknown`. Unknown targets receive generic damage only and cannot acquire C04 slow effects. C04 has no team effect, hard control, Boss break, purge or protection contribution path.

## Cast And Hit Contract

1. Map logic calls `controller:begin_cast(...)` or `controller:begin_normal_attack(...)` with the synchronized input event.
2. The hit system confirms only a positive, current-lifecycle hit through `controller:confirm_skill_hit(...)` or `controller:confirm_normal_attack(...)`.
3. Every confirmed event carries the originating Unit identity, `lifecycle_id`, `combat_scope`, private-session fields when applicable, target ID/reference, a unique `hit_key`, `component_key`, positive `damage_dealt`, target liveness and any required phase/path data.
4. Map logic calls `finalize_phase` for each A07 deadline and `finalize_cast` for A02/A05/A08 closure. Unconfirmed reservations are released. A05/A08 submit at most one already-created recovery candidate on this close step.

The controller never substitutes a generic candidate for a primary target. A04 only completes after the safe-move callback, and its wind window is consumed by the first matching normal/A01 hit snapshot.

## Public Boss Boundary

Only a real accepted Boss hit may carry a frozen `encounter_snapshot` and a unique final-damage event ID. The bridge forwards valid public `final_damage` to the project encounter layer; it does not compute reward, kill attribution, drop, party DPS or collection credit.

## Deferred Validation

- Production IDs, models, icons, range template and map distance conversion.
- Map-script loading, hot reload and object readback.
- All target/point/hit/encounter hooks, including delayed arrows, fields, trace ticks and Boss phase changes.
- Four-player synchronization, reconnect, challenge cleanup and C04 balance replay logs.
