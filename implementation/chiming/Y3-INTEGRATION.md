# 持明 Y3 接入说明

## 状态

`C03` 为 `reviewed / official-subbaseline / offline-stage-accepted / P0-P1-revision-complete`。桥接按 `y3-lualib main@fe2fb0e55a76f73490cdcbef8cbfe7a61d124d63` 离线构建；真实命中、选点、品级、净化、保护和 Boss Hook 均未绑定地图。

真实接入必须同时部署：

```text
profession_common/lua/
chiming/lua/
```

职业核心不直接调用 Y3。Y3 调用只位于 `chiming_y3_adapter.lua`、`chiming_y3_targeting.lua` 和 `chiming_y3_controller.lua`。

## 必需项目回调

```lua
local ChimingController = require 'chiming_y3_controller'

local controller = ChimingController.new {
    ability_ids = { C03_A01 = PROJECT_ABILITY_ID },
    ability_types = { C03_A01 = '英雄' },
    modifier_ids = { C03_M01_MINGTAI = PROJECT_MODIFIER_ID },
    skill_by_y3_id = { [PROJECT_ABILITY_ID] = 'C03_A01' },
    distance_scale = 100,

    resolve_primary_target = function(runtime, actor_id, skill_key, source, ability, event_data)
        -- Required for A01/A03/A06. Return a live Unit or { target_id, target }.
    end,
    resolve_cast_point = function(runtime, actor_id, skill_key, source, ability, event_data)
        -- Required for A05/A08. Return one synchronized authoritative point.
    end,
    resolve_team_members = function(runtime, actor_id, skill_key, source, ability, event_data, radius)
        -- Return only current party members inside radius. Never include source,
        -- NPCs, summons, or players outside the party.
    end,
    resolve_pulse_targets = function(actor_id, pulse_key, command, cast_context)
        -- Required for every A05/A08 pulse. Return { targets, target_ids,
        -- target_meta_by_id }; an empty or absent result deliberately hits nobody.
    end,
    target_rank = function(target, command, context)
        -- Return exactly 'normal', 'elite', or 'boss'. Nil/invalid becomes unknown.
    end,
    on_cast_committed = function(actor_id, cast_id, snapshot, cast_context)
        -- Register project hit listeners. The listener must later call
        -- controller:confirm_skill_hit(actor_id, cast_id, hit_context).
    end,
    resolve_self_purge = function(runtime, actor_id, skill_key, source, ability, event_data, context)
        -- Return an authoritative self-purge result.
    end,
    resolve_team_purge = function(runtime, actor_id, source, ability, event_data, team_targets, context)
        -- Return actual purged party targets/IDs only. The bridge intersects the
        -- result with the committed team snapshot and removes the caster.
    end,
    classify_effective_protection = function(actor_id, unit, damage_data, context)
        -- Return { effective_protection, cast_id, effect_key, target_id,
        -- lifecycle_id, absorbed, reduced, boss_contribution? }.
    end,
    apply_break = function(source, target, value, command, context)
        -- Return { actual_break = true, value = accepted_value } only after
        -- project toughness accepts an explicit boss-only break command.
    end,
    resolve_boss_context = function(target, event_or_command, context)
        -- Return boss_instance_id, phase_id, event_id for a real boss event.
    end,
    report_boss_contribution = function(event)
        -- Project encounter layer owns rewards and kill attribution.
    end,
}
```

## Cast And Hit Contract

`on_cast_committed` receives a snapshot with `actor_id`、`lifecycle_id`、`cast_id`、`skill_key`、`primary_target_id`、`target_refs_by_id`、`cast_point`、`team_target_ids`.

For hit-confirmed skills, call `controller:confirm_skill_hit` with the same lifecycle and one or more events:

```lua
{
    lifecycle_id = snapshot.lifecycle_id,
    hit_events = {
        {
            cast_id = snapshot.cast_id,
            lifecycle_id = snapshot.lifecycle_id,
            phase = 'direct', -- A02 uses 'outbound' or 'return'; A05/A08 use 'impact'
            target_id = unit:get_id(),
            target = unit,
            damage_dealt = final_damage,
            hit_time = synchronized_time,
            path_distance = path_distance,
            target_rank = 'normal',
            alive = true,
        },
    },
}
```

Only current-lifecycle events with positive `damage_dealt` are accepted. A01/A03/A06 require the snapshot primary; A02 keeps the first event per target per path; A05/A08 pulses must ask `resolve_pulse_targets` again.

## Hard Contracts

- Every magic effect command has `self`、`primary`、`selected`、`team` or `explicit` scope. The bridge never falls back to `context.targets`.
- Unknown rank receives only generic damage, slow and private marks. It cannot receive control, M09, or a Boss break.
- A08 at rank 5 can report at most one initial `2.3` break, one M06 `0.4` break and one P07 `0.3` break for the cast; its later pulses have no break. A05 pulse breaks are individually `boss_only`.
- `refunded` and `external` seals can pay skills but never add ultimate. Only effective `earned` consumption adds `5` ultimate.
- Death, challenge failure, cross-layer, repeat registration and removal invalidate the old lifecycle before timers, source-owned control leases and transient effects are cleared.
- Boss contribution requires `kind`、`event_id`、`actor_id`、`lifecycle_id`、`boss_instance_id`、`phase_id` and `target_id`; the controller deduplicates by `boss_instance_id + phase_id + event_id`.

## Deferred Validation

- Real IDs, icons, models, attack template, distance scale and object readback.
- Map event binding for every callback above, including target-rank resolver gate.
- Script-root load, hot reload, real four-player synchronization, reconnection and challenge flow.
