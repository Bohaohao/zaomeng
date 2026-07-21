# First-six-hours growth and reward offline environment

## Status

- Package status: `offline_candidate_simulation_not_adopted`; execution readiness: `offline_simulation_ready`.
- Production gate: `closed`.
- Runtime handoff: `false`; the candidate resource table cannot be consumed by Y3, a production ledger, or TianTing.
- Scope: one character, one to four qualified players, `0–360` active minutes, and the Lv1–20 Huaguoshan loop.
- Runtime: pure Lua under a controlled offline Node/Fengari runner; it has no Y3 API calls, map binding, object IDs, save backend, or live currency mutation.

This package turns the previously deferred first-session questions into a deterministic **offline simulation contract**. It does not promote the figures to the global production baseline and does not override the production gates in `docs/物编/成长数值与经济裁决包/`.

## What is settled for the offline environment

- Lv1–20 is a continuous 9,485 XP curve; the scripted content trace reaches Lv20 at active minute 55.
- A qualified party member receives the full personal XP award once. Party size never divides it; over-level farming falls to 80%, 50%, then 20%.
- Death prevents new live-combat XP, while a previously issued receipt replays unchanged after revive or reconnect.
- `P1_PUBLIC_CHEST_BALANCED_CONTRIBUTION` is the `ECO-P1-001` conflict candidate selected only for this isolated simulation; it is not a final policy. Progression, chest, rare eligibility, and pity are separately calculated and recorded.
- `HG_DROP_OX_RAID` uses a distinct `F6H_TEAM_RAID_RARE_ELIGIBILITY_V1` snapshot: exactly 1–4 members, a correlated completed raid event/profile, an authority-proof reference, and per-member lock/presence/alive/contribution/rare attestations. A plain `encounter_qualified` flag cannot enter its rare or pity path.
- Each reward receipt is keyed by character owner, event, source profile, reward slot, and resource-table version. Replaying it never changes XP, balances, first clear, unique items, or pity.
- Reward settlement validates its rare roll before any state commit and stages currency, unique, first-clear, pity, receipt, and origin changes together. Out-of-range, `NaN`, and fractional rare rolls have zero state side effects.
- All 21 `HG_DROP_*` source keys have an offline reward bundle. Only `CUR_GOLD` and `CUR_RAID_MARK` can circulate in this six-hour simulation; `CUR_TOWER_TOKEN` is reserved for the Tower package.
- The first five build changes are: Lv3 second active, Lv8 core route, first weapon, first enhancement, and first artifact.

## Contents

- `data/first-six-hours-v1.json`: human-readable scope, policy, milestones, and profile coverage.
- `lua/growth_config.lua`: immutable simulation inputs.
- `lua/growth_runtime.lua`: XP, qualification, receipt, reward, pity, and spending state machine.
- `tests/test_growth_runtime.lua`: deterministic regression tests.
- `tests/validate-first-six-hours-package.ps1`: data/schema/contract gate.
- `tests/run-all.ps1`: invokes the package gate, offline API-isolation gate, and the trusted Lua test runner.

## Explicit non-goals

- No actual Y3 object, terrain, UI, map logic, account save, transaction, trade, or live reward configuration is created.
- No existing `reward_exp`, `reward_official_res_1`, or Y3 object field is treated as the source of XP or currency.
- Lv20 does not grant a chapter-entry key. Difu and Tianting entry remain their own contracts.
- Tower rewards, seasons, and currency sinks remain outside this first-six-hours simulation.

## Verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\growth\tests\run-all.ps1
```

The runner requires the already pinned Node/Fengari boundary from the Huaguoshan offline package. It rejects `NODE_OPTIONS` and `NODE_PATH` injection; no `NODE_PATH` is used to resolve Lua dependencies.
