# Powang Y3 Integration

## Status

This package uses `y3-lualib main@fe2fb0e55a76f73490cdcbef8cbfe7a61d124d63` as its provisional API baseline. The bridge is source-checked and offline-tested, but it has not been loaded by a real Y3 Lua 5.4 map.

## P1 Offline Bridge Repair

The Powang bridge now has actor lifecycle tokens, lifecycle-owned delayed timers, explicit per-target rank metadata for C01_A08, guard-hit qualification, and a categorical mitigation ledger. This closes the P1 findings at offline depth only. The map must still bind the three feature gates recorded in the manifest before the package can be treated as construction-ready.

## Modules

- `powang_y3_adapter.lua`: Unit attributes, damage, synchronized delayed damage, movers, Buff shells, cooldowns, controls, healing, charge display, and derived-state display.
- `powang_y3_targeting.lua`: default circle, sector, and rectangle targeting for the eight active skills and the ultimate.
- `powang_y3_controller.lua`: unit events, normal-attack resource gain, skill dispatch, level resync, guard counterattacks, death cleanup, trigger teardown, and the synchronized runtime tick.

The real script root must also contain `profession_common/lua/`, which provides the canonical target contract, effect store, control ledger, and adapter contract used by the Powang compatibility modules.

Modifier commands use explicit ownership: `self`, `primary`, `selected`, `team`, or `explicit`; `team` means other teammates and excludes the caster. Shared-highest effects present one highest source and fall back when that source expires. `powang_y3_targeting.lua` records both `Unit:get_id()` values and an ID-to-Unit map, so source cleanup and Buff presentation address the same target. Root control uses synchronized leases; overlapping roots keep the state until the final lease expires.

All authoritative timers use `y3.timer`. No gameplay state is mutated from local UI or client timers.

The default resolver treats a skill as an effective hit when its synchronized geometry contains at least one legal enemy. It filters invulnerable targets and sets skill damage to `no_miss`; normal attacks still require the engine's `单位-造成伤害后` event with damage greater than zero. If active skills later participate in hit/dodge rolls, replace this default with deferred damage-event confirmation.

## Required Project Mapping

```lua
local PowangController = require 'powang_y3_controller'

local controller = PowangController.new {
    ability_ids = {
        C01_A01 = PROJECT_ABILITY_ID,
        -- Fill all active skills and C01_U01 after object IDs are assigned.
    },
    ability_types = {
        C01_A01 = '英雄',
    },
    modifier_ids = {
        C01_M01_DONGMING = PROJECT_MODIFIER_ID,
        -- Fill all twelve modifier IDs.
    },
    skill_by_y3_id = {
        [PROJECT_ABILITY_ID] = 'C01_A01',
    },
    distance_scale = 100,
    apply_break = function(source, target, value, command, context)
        -- Connect the project's toughness/break system.
    end,
    classify_guardable_damage = function(actor_id, hero_unit, damage_data, context)
        -- Return guardable_hit only for a tagged enemy direct hit.
        return { guardable_hit = false, effective_protection = false }
    end,
    target_rank = function(target)
        return 'normal' -- Return normal, elite, or boss.
    end,
}

controller:register(actor_id, hero_unit, {
    level = hero_unit:get_level(),
    ability_levels = learned_active_levels,
    passive_levels = learned_passive_levels,
    ultimate_tier = ultimate_tier,
})
```

`distance_scale = 100` is a provisional conversion from one design body length to engine distance. Keep `distance_scale_verified = false` until collision, camera, melee range, and the 4.5-body dash are checked in a real map.

## Project Hooks

- classify_guardable_damage is required for C01_A07. It must return guardable_hit only for an eligible enemy direct hit. Without this hook, the bridge safely treats every damage event as ineligible.
- target_rank is consumed for every selected C01_A08 target. An unresolved target receives no hard control or BOSS conversion.
- `apply_break`: required for break/toughness damage and BOSS control conversion.
- `resolve_direction`: overrides unit facing when a vector indicator supplies a synchronized direction.
- `resolve_cast_context`: optional full replacement for the default geometry resolver; when supplying an explicit target ID without a Unit reference, also provide `target_refs_by_id[target_id] = unit`.
- `decorate_context`: appends project combat tags without replacing default targeting.
- `on_effect_payload`: handles project-specific values not represented by standard Unit attributes.
- `on_state_changed`: forwards momentum, ultimate, and cleanup state to HUD or persistence systems.

For a delayed hit, call `Runtime:commit_skill` at cast submission and later call `Controller:confirm_skill_hit` or `Controller:finish_skill_miss`. The callback must echo the lifecycle_id supplied at commit time; a missing or stale token is rejected. A committed miss consumes momentum but grants no ultimate gauge.

## Mitigation Contract

Powang mitigation is recomputed from active sources rather than directly added to the Unit attribute. The mobility category covers the dash window and post-move guard, the guard category covers C01_M04, and the recovery category covers C01_M07. Each category keeps its highest value; categories multiply; the final Powang total is capped at 70%. Future external mitigation must declare its own category and cannot bypass this cap.

## Deferred Verification

- Real object IDs, models, icons, and ability bindings.
- Distance and collision calibration.
- Y3 script-root loading and hot reload.
- Buff overlap/readback against actual modifier templates.
- Four-player synchronization, reconnect, death, and challenge cleanup traces.

None of these deferred items may be marked `verified` from offline results alone.

## Deferred System Contracts

The combat bridge intentionally does not own save data, skill-tree UI, five-slot loadouts, or multiplayer session authority. Their required entry points, data ownership, open rules, and acceptance conditions are recorded in [DEFERRED-INTEGRATIONS.md](DEFERRED-INTEGRATIONS.md). Complete those tasks through their project-level systems; do not add local UI or persistence mutations to `powang_core.lua`.
