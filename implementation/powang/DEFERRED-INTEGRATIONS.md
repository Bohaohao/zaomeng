# Powang Deferred Integration Contracts

## Status

- Created: `2026-07-11`.
- Status: `planned`; no map-side Lua, UI asset, persistence record, or network handler has been created.
- Purpose: reserve explicit integration boundaries for systems that are outside the Powang combat bridge, without adding speculative Y3 API calls or empty runtime modules.
- Baseline: `docs/全局设计基线.md`, `docs/物编/03-破妄离线施工与Y3接入状态.md`, and `Y3-INTEGRATION.md`.

## Boundary Rules

- `powang_core.lua` owns deterministic profession combat state. It must not read UI, save files, player slots, or local-only state.
- `powang_runtime.lua` owns one registered actor's learned levels, transient combat state, effect store, and adapter command dispatch.
- `powang_y3_controller.lua` owns unit-event lifetime. It is the only current bridge that should register or remove combat triggers for a Powang actor.
- Save, UI, five-slot loadout, and multiplayer session systems are project-level callers of the controller. They must not mutate `Runtime.actors` directly.
- No `y3.save_data`, `y3.ui`, `y3.sync`, or local timer API is called by this package until a real map project, UI node tree, and API baseline are available.

## Deferred TODOs

### PWG-INT-001: Character Save and Reconnect

**Integration location:** character selection/load completion, before `Controller:register`; role removal/reconnect, before `Controller:remove`.

**Persistent profession payload:**

```yaml
schema_version: required
profession_id: C01
level: required
learned_active_levels: required
learned_passive_levels: required
ultimate_tier: required
skill_point_spent: required
loadout_presets: required
```

**Do not persist as a profession snapshot:** battle momentum, ultimate gauge, Dongming, temporary effects, charge recovery, pending casts, normal-attack stage, or control leases. These are cleared through `Controller:clear` / `Runtime:clear_transient` on death, challenge cleanup, cross-layer transfer, and reconnect.

**Contract:** validate profession, level range, learned ranks, prerequisite graph, total point budget, and five-slot presets before registering the hero. Register with the validated values as `state_options`; no saved value may be copied into the runtime state table without validation.

**Acceptance:** repeated load/reconnect is idempotent; the same save never duplicates growth, skills, charges, Buffs, triggers, or timers; malformed or newer-version data is rejected or migrated by the global save system before it reaches Powang.

### PWG-INT-002: Skill Tree Authority and HUD

**Integration location:** the future skill-tree UI submits a synchronized learn/reset request to the profession progression service; approved changes call `Controller:set_ability_level`.

**Contract:** the progression service is authoritative for free skill points, prerequisites, ultimate-trial grants, reset entitlement, and the `Lv60` skill-point budget. The UI is display and intent only; it cannot directly change learned ranks or consume points.

**Read model:** use the validated character payload plus the runtime state exposed by `Runtime:get_state`. Momentum, Dongming, ultimate gauge, charges, and short Buffs may be mirrored to HUD through `on_state_changed` and `sync_ability_charge`, but the HUD never becomes a combat source of truth.

**UI gate:** create the actual panel with `y3-ui-pipeline`, generate the UI node tree, then verify node paths before adding Lua event bindings. Do not reserve UI paths, callbacks, or component IDs before that step.

**Acceptance:** illegal prerequisites, unlearned skill use, overspent points, and unauthorised reset requests are rejected on the authoritative path; accepted updates immediately refresh ability rank, charge rules, tooltip data, and slot eligibility for that actor only.

### PWG-INT-003: Five-Slot Loadout and Presets

**Integration location:** loadout service, after PWG-INT-001 validation and after real ability IDs have been assigned; UI slot changes route through the same synchronized request path as PWG-INT-002.

**Contract:** each preset contains exactly five ordered slots. Each slot can contain one learned active skill from `C01_A01-C01_A08`; duplicates, passives, `C01_F01`, and `C01_U01` are invalid. The fixed passive, ultimate, dodge, and Dharma treasure actions do not consume a slot.

**Bridge point:** map the approved logical skill keys to real Y3 ability IDs and `skill_by_y3_id`. The map-side integration owns adding, removing, or rebinding the actual ability slots; `powang_runtime.lua` continues to receive logical keys only.

**Open rule:** preset switching time and combat restrictions are not decided. The eventual loadout system must define whether switching is limited to a main city, a safe point, or out-of-combat state before implementation.

**Acceptance:** three saved presets restore independently; an actor may know eight active skills but can expose only five; no delayed cast, cooldown, charge, or pending spender is stranded during a permitted switch.

### PWG-INT-004: Four-Player Authoritative Synchronization

**Integration location:** game-session bootstrap and every externally initiated state change: learning, reset, loadout switch, cast request, death, challenge lock, cross-layer transfer, disconnect, and reconnect.

**Contract:** all gameplay-affecting requests resolve on the synchronized authoritative path. Local UI may render state and submit intent but must not mutate learned ranks, loadout, momentum, ultimate gauge, damage, Buffs, control state, or rewards. Existing combat timers remain on `y3.timer`; client/local timers remain presentation-only.

**Existing support:** the Powang runtime is actor-keyed, effect ownership uses stable unit IDs, shared effects retain highest-value rules, and root control uses per-target leases. These mechanisms are prepared for concurrent actors but have not yet been verified in a live four-player session.

**Acceptance:** four concurrent Powang actors have isolated momentum, ultimate gauge, charges, cooldowns, personal Poxi, timers, and teardown records; Xianwang and Mingshi preserve their cross-source aggregation rules; reconnect and actor-ID reuse cannot revive old triggers or mutate a newly registered character.

## Integration Order

1. Establish a real Y3 map project, script root, object IDs, and the frozen API version.
2. Implement the global character persistence and migration service, then complete PWG-INT-001.
3. Create the skill-tree UI and its verified node tree, then complete PWG-INT-002.
4. Implement real ability slot mapping and preset rules, then complete PWG-INT-003.
5. Run a four-player synchronized session with persistence and reconnect traces, then complete PWG-INT-004.

No TODO in this document can be marked complete merely because the offline combat tests pass.
