# Native compiler: `render_source` declared on a type fails the build with an internal error

For Codex (compiler owner). Found 2026-11-08 on the client lighting compare lane (`client-glow-holder`, pool-5).

## Symptom

`bash tools/dq_focused_test.sh <any test>` fails to build: `deepquarry.test.dmb - 1 error, 0 warnings`, and the only message is

    native internal: initializer diagnostic has no matching captured source projection

(`tools/dmb/crates/dmbc/src/initializer_diagnostics.rs`, the `InitializerOriginKind::Declaration` arm). The real diagnostic is lost, so the
user sees no file or line. DreamMaker cannot cross-check it at the moment: the tree fails there on unrelated files
(`code/library/atom/states/*_state.dm:6: error: var: expected end of statement`).

## Minimal repro

Add to any content file (the define is the same shape as `EMISSIVE_RENDER_TARGET`, from `code/defines/base/_planes+layers.dm`):

```dm
#define REPRO_RENDER_TARGET "*REPRO_PLANE"

/atom/movable/screen/repro_relay
	render_source = REPRO_RENDER_TARGET
```

Bisected on that lane: with the declaration the build fails as above; with the type empty and `R.render_source = REPRO_RENDER_TARGET`
set at runtime it builds and runs. The same macro as a `render_target = ...` declaration (`/atom/movable/screen/plane_master/client_glow`)
builds fine, and no other type in the tree declares `render_source`, so the trigger is a `render_source` declaration (possibly only
with a macro value; a string literal was not tried).

## Workaround in the tree

`/atom/movable/screen/client_glow_relay` (`code/content/lighting/client_lighting_compare.dm`) sets `render_source` in
`client_glow_screen_objects()` when the shared relay is made. Two things to fix: the declaration itself, and the diagnostic path,
which should report the underlying error with its location even when no captured projection matches.
