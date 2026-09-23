# vg-gas

The gas domain of Verdigris (`doc/rewrite/simulation.md` §4, roadmap M1b):

- `cell.rs`: turf gas as a vg-core field (`TurfGas`), with its flux, reaction
  check, channels and commands;
- `pipes.rs`: pipes as a vg-core network (`Pipes`, `PipeNet`);
- `world.rs`: the gas world that owns every mixture and hands DM handles;
- `turf.rs`, `lib.rs`: the BYOND binds; `heat.rs`: the heat domain's binds;
- `gas/`: the gas registry and mixture maths, originally from
  [auxmos](https://github.com/Putnam3145/auxmos) (see `UPSTREAM.md`).

`verdigris/README.md` (M1b notes) describes ownership, frames, events, watches
and what M2 builds on. `code/ATMOSPHERICS/README.md` describes the DM side.

Tests: `cargo test --target i686-pc-windows-msvc -p vg-gas` (the crate links
byondapi, so it builds for the i686 targets only).
