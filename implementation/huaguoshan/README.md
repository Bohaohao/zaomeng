# Huaguoshan Encounter Preconstruction Package

This package is the offline object, encounter runtime, and map-logic binding contract for the Huaguoshan chapter.

## Contents

- `preconstruction-manifest.json`: 35 units, 55 abilities, 12 modifiers, 7 projectiles, and 15 encounters.
- `map-logic-binding.json`: typed stable-key contract from the 96x72 whitebox to runtime resources; `HG_E_DRAGON_OLD_TIDE` and `HG_E_DRAGON_REVERSE_TIDE` share the single four-slot `HG_I_DRAGON_FOUR_SEAS` contract.
- `lua/`: engine-neutral encounter authority, public-Boss ledger, Dragon Palace slots, Ox Battlefield lifecycle, adapter, and controller.
- `tests/preflight.ps1`: validates stable keys, cross-object dependencies, map logic resources, runtime modules, public boss contracts, and instance bounds.
- `tests/test-preflight.ps1`: proves that a missing unit-to-ability reference is rejected.
- `tests/test-map-binding.ps1`: proves a whitebox resource type mismatch is rejected.
- `tests/test_map_binding.lua`, `test_public_trace.lua`, `test_public_boss.lua`, `test_instances.lua`, `test_controller.lua`, `test_runtime.lua`, `test_controller_runtime_adapter_integration.lua`: offline runtime regression coverage, including the real Controller + Runtime + Adapter chain, authority-provider proofs, watermark-ordered public actions, lifecycle cancellation, CAS Boss identity, and delivery reconciliation. Unknown execution states are never blindly replayed.
- `tests/test-config-binding-parity.ps1`: verifies configuration parity.
- `tests/y3-api-baseline.json`, `tests/test-y3-api-baseline.ps1`, `tests/verify-y3-api.ps1`: define and test the offline API isolation gate. The verifier tokenizes every Lua file under `lua/`, ignores ordinary text in comments and string values, and rejects explicit engine/environment identifiers, restricted string-index access such as `host['os']`, dynamic loaders, and qualified, dynamic, or non-package-local `require` use. The only accepted import form is an unqualified direct call with a quoted package-local module name, for example `require("huaguoshan_config")` or `require 'huaguoshan_config'`. `-BaselinePath` may select only the package authority under `tests/` or the package-root fallback. The selected document and every present authority/fallback copy must satisfy the fixed schema and be semantically identical.
- `tools/materialize-object-commands.ps1`: generates Y3 object commands only after every production gate and the manifest, binding, and Lua Config instance contracts agree, including globally unique verified stable object IDs.
- `tests/test-materializer.ps1`: proves pending, drifted, unreadable, duplicate-ID, or path-escaping runtime contracts produce no command file.

## Offline API isolation status

This package has no Y3 API compatibility baseline. Its real map script root is not integrated, so `modules` and `events` are intentionally empty and the metadata explicitly declares `offline_api_isolation_only`. An empty record set can pass this static isolation gate, but it cannot be reported as API compatibility evidence. The metadata gate requires `schema_version: 1`, non-empty string provenance/scope fields, boolean status flags, a `modules` object, and an `events` array. A declared module must list at least one non-empty method name; an empty method array is invalid schema and never counts as a compatibility record. The verifier retains the non-empty compatibility-record checks for a future, real map-root integration.

The isolation verifier is a conservative lexical gate, not a Lua sandbox or a whole-program data-flow proof. It does not establish the provenance of aliases, computed property names, or objects/capabilities injected at runtime. A pass means the checked source files contain none of the prohibited token forms and their metadata is internally consistent; it does not prove that arbitrary future runtime injection is safe or that Y3 API compatibility has been verified.

## Run

Run only the offline API isolation regression and scanner:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\huaguoshan\tests\test-y3-api-baseline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\huaguoshan\tests\verify-y3-api.ps1
```

Run the full Huaguoshan offline package:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\implementation\huaguoshan\tests\run-all.ps1
```

`run-all.ps1` uses the same lexer verifier for the package and for a comment/string regression fixture; it does not perform a second raw-text API scan. Executed Lua tests still must emit exactly one `PASS` line with a positive assertion count.

The offline Lua runner is fixed to cached `fengari-node-cli 0.1.0`, pnpm snapshot `41ec8406e7a68140b8436c01df2bb294a02c6dc5111f463b8777f1ec3b7eef50`, with resolver-closure SHA-256 `E8E88EFDB5BEFFE0F140BA72EDDCEC5E1B52D7788062A9FCF0E09F6988745AF4`. `run-all.ps1` hashes the CLI's complete parent `node_modules` boundary by logical path, entry type, and file bytes while following every symlink or junction target, so the files Node actually resolves for `fengari`, `readline-sync`, and `sprintf-js` are pinned even when pnpm stores them outside the CLI package directory. A temporary real Node resolver layout verifies that mutating a reparse target changes the hash. Every cached Fengari CLI candidate is validated before the deterministic first matching copy is selected, so cache-scanning child gates cannot resolve another version. Missing, extra unpinned, or integrity-mismatched cache entries fail closed. The script never invokes `pnpm dlx`, and `-PnpmPath` is rejected because it cannot supply an exact offline dependency graph.

The package is intentionally blocked from live encounter activation until a real Y3 map, object IDs, resources, map logic objects, verified runtime hooks, and an authoritative event provider have been bound. The offline runtime can validate its contracts now, but it cannot spawn or control production units before those gates are opened.

In live mode, the map root must supply an authoritative, idempotent `delivery_id` ledger and a side-effect-free `reconcile_command` query. The adapter only suppresses a command after confirmed delivery; an unknown outcome stays isolated until reconciliation proves whether a retry is safe.

Once the runtime accepts an operation, Controller results remain accepted even when Adapter delivery fails. The returned payload carries stable `operation_id` and batch `delivery_id` values plus `delivery_pending` and, when applicable, `delivery_error`; `retry_pending_deliveries()` continues to report transport failures directly. Every live Controller boot must supply a stable, boot-unique `delivery_namespace` (or `delivery_boot_epoch`); `require_delivery_namespace = true` applies the same durable requirement outside live mode. Omitting the namespace creates a process-local offline namespace for compatibility, but must not be used where Controller reconstruction can share a delivery ledger.
