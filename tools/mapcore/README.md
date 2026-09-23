# DeepQuarry Mapcore

An offline Rust library and CLI for map tooling. It is separate from
`verdigris/`: the game still uses BYOND and DM to load maps, while mapcore is
native tooling for editors, validators, renderers, and future generators.

The library provides TGM/DMM dictionary and grid parsing, tile inspection and
replacement, deterministic TGM output, mapped atom path counts, and DMI
source-sheet frame extraction from `*.png` plus `*.dmi.toml`.

The CLI provides `inspect`, `roundtrip`, and `sprite`:

```powershell
cargo test --manifest-path tools/mapcore/Cargo.toml
cargo run --manifest-path tools/mapcore/Cargo.toml -- inspect maps/southern_cross/southern_cross-1.dmm
```

Map Studio uses the mapcore CLI as a second parser on every save. Its browser
view currently uses the equivalent Python sprite index to serve frames quickly;
the Rust frame extractor is available to other tooling. Runtime map loading is
in `code/modules/maps/reader.dm`, and Southern Cross deck maps are compiled
through `maps/southern_cross/southern_cross.dm`.
