# Profession Common

This offline library contains only profession-neutral behavior proven by `C01`, `C02`, and `C03`:

- explicit target ownership and stable unit IDs;
- source-aware modifier state and cleanup;
- overlapping control leases;
- adapter command validation and dispatch.

It deliberately does not contain a resource loop, skill tree, numerical configuration, target geometry, hero growth, or Y3 object IDs. Those remain owned by each profession package.

When a real map is connected, copy this library into the valid Lua script root beside the profession modules. It is not a Y3 editor object package and must not be copied into `editor_table/`.
