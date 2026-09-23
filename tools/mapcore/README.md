# DeepQuarry Mapcore

An offline Rust library and CLI for map tooling. It is separate from
`verdigris/`: the game still uses BYOND and DM to load maps, while mapcore is
native tooling for editors, validators, renderers, and future generators.

The library provides TGM/DMM dictionary and grid parsing, tile inspection and
replacement, deterministic TGM output, mapped atom path counts, DMI
source-sheet frame extraction, network route topology, and ordered sprite
compositing for offline PNG previews.

The CLI provides `inspect`, `roundtrip`, `sprite`, and `render`:

```powershell
cargo test --manifest-path tools/mapcore/Cargo.toml
cargo run --manifest-path tools/mapcore/Cargo.toml -- inspect maps/southern_cross/southern_cross-1.dmm
cargo run --manifest-path tools/mapcore/Cargo.toml -- render scene.json preview.png
```

`render` accepts ordered quads with `x`, `y`, `width`, `height`, optional `tint`
(RGBA bytes), optional `sprite` (PNG path relative to the scene file), and an
optional `[x,y,width,height]` crop. The scene sets `width`, `height`, optional
`background`, and `quads`. This is suitable for thumbnails and preview tools.

Map Studio calls the long-lived native mapcore process for route edits and uses
the WASM build of the same route engine for immediate drag previews. Its browser
viewport draws sprites with WebGL2; a 2D canvas draws editing controls and is
the fallback if WebGL2 is unavailable. Sprite indexing and full edit transactions
still run in Python. Map Studio also uses the mapcore CLI as a second parser on
every save. Runtime map loading is
in `code/modules/maps/reader.dm`, and Southern Cross deck maps are compiled
through `maps/southern_cross/southern_cross.dm`.
