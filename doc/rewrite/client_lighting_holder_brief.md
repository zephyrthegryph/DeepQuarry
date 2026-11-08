# Client lighting: handoff brief (per-client glow holder, then compare mode)

Written 2026-11-08 at the end of the lighting session, for the next agent. Everything below is on master unless marked
otherwise.

## 1. Current state

Client lighting replaces the DM lighting corners and turf underlays with client-rendered glows. It is a live mode:

- `GLOB.client_lighting` (`code/content/lighting/client_glow.dm`) turns it on. `client_lighting_set(on)` switches live
  in one pass: on clears every lighting object and corner contribution and redraws each light as a glow; off removes the
  glows and rebuilds lighting objects. Admin verb **Toggle Client Lighting** (Debug Game).
- Config flag `CLIENT_LIGHTING` (`code/world/configuration/entries/general.dm`, default off in code) is **on in
  `config/example/config.txt`**, which the test server serves. `SSlighting.initialize()` (`code/world/systems/lighting.dm`)
  turns the mode on before any lighting object is made. Unit-test builds ignore the flag.
- **Glow** (`client_glow.dm`): one `/obj/effect/overlay/client_glow` per light source on `PLANE_LIGHTING`,
  `BLEND_ADD` over the plane's black backdrop; icon from `icons/effects/light_overlays/light_<size>.dmi` by range,
  colour and power from the light. In this mode `/datum/light_source/update_corners()` calls `client_glow_apply()` and
  returns; no corner is touched and no lighting object is created (`create_all_lighting_objects()`,
  `lighting_build_overlay()`, `lighting_ensure_object()` all skip). Dynamic turfs show to BYOND at luminosity 1.
- **Shadow mask** (`client_shadow.dm`): each glow has a hidden mask `/obj/effect/overlay/client_glow_mask` in its
  `vis_contents`, `render_target = "*client_glow_mask_[handle_of(light)]"`, used by the glow's `alpha` filter
  (`client_shadow`). The mask's overlays are one white tile (`LIGHTING_ICON` "transparent") per turf the light reaches,
  from `sight_view_turfs()` (Rust symmetric shadowcasting over the world opacity layer, `code/domains/verdigris/sight/`),
  in the glow sprite's own frame; its base icon is the glow icon made transparent so both are the same size. The mask is
  blurred 3 px (`client_shadow_soft`, `CLIENT_GLOW_MASK_BLUR`). Tile lists are a shared cache by shape
  (`DECLARE_SHARED_CACHE(client_glow_masks)`).
- **Updates are events only.** Glowing lights are indexed in 8x8 chunks (`GLOB.client_glow_chunks`,
  `client_glow_index()`). An opacity change calls `turf/reconsider_lights()` -> `client_glow_reconsider(T)` ->
  `client_glow_mask_refresh()` on each light in reach: it recomputes the reach and stops when the shape key is unchanged
  (about half the time). A light that moves or changes is redrawn by the normal light queue.
- **Gameplay light level** (`client_light_level.dm`): `turf/get_lumcount()` in client mode sums the glowing lights in
  reach (chunk index + each light's `glow_reach`), with the corner engine's falloff. Within 0.04 of the corner engine.
- **Lum band watches** (`code/domains/heat/watched.dm`): in client mode `SSwatched` keeps the rows itself
  (`client_lum_watch`, `lum_rows()`); a mask rebuild or removal reports the watched turfs in its old and new reach.
- `light_step()` drops a deleted or marked-for-deletion source still in its queue instead of spinning on it.
- Constants in `code/defines/base/lighting.dm`: `CLIENT_GLOW_CHUNK` 8, `CLIENT_GLOW_MAX_RANGE` 6, `CLIENT_GLOW_MASK_BLUR` 3.
- `GLOB.client_glow_bounds` exists and is off (FALSE): glow bounds over the reach. Do not turn it on (section 4).

**Open defect this brief is for:** BYOND sends a glow only to clients that see the light's own turf, so a light just
off-screen does not spill its glow onto the screen, and its glow pops in as the player walks. The user's rule: nothing
may visibly pop in.

## 2. Commits (all landed)

| Commit | What |
|---|---|
| `e4c457227be0` | Lazy lighting objects: only lit turfs get one (11110 -> 2751 objects on the test map) |
| `41758fa8bbef` | World opacity layer in Rust (`SYSTEM_DEF(sight)`), symmetric shadowcasting `sight_view_turfs()`; lights use it (4.2x faster than `view()`) |
| `9707c948c71b` | Client glows + live toggle (off) |
| `8b620d8f5ee8` | Shadow masks (3 px blur, shared cache, chunk index); `light_step()` never spins on deleted sources |
| `26dead8f8fdc` | Gameplay light level under client lighting |
| `6dace5996746` | Lum watches under client lighting; `CLIENT_LIGHTING` config, on for the test server |
| `0e9f7be45de5` | Mask-only refresh on opacity change with early-out; `client_lighting_play` bench; glow bounds code (off) |

## 3. Benchmark

`code/tests/benchmarks/client_lighting_play.dm`. Run from a lane:

    bash tools/build/build.sh bench --scenario=client_lighting_play --label=<name> [--arg rounds=20] [--arg doors=40] [--profile]

It flips the opacity of up to `doors` airlocks closed and open and steps 10 light fixtures one tile east and back, for
`rounds` rounds, each followed by `SSlighting.light_step(0, TRUE)`, first with DM lighting, then client lighting (inside a
bench window, so `--profile` dumps a proc profile to `data/bench/profiles/<stamp>_<sha>_<label>/iteration1/profiler-*.json`),
then again with bounds off. It reports `client_play_dm_ms`, `client_play_dm_move_ms`, `client_play_client_ms`,
`client_play_client_move_ms`, `client_play_client_nobounds_ms`, `client_play_mask_builds` (each = one appearance change
sent to viewers: the bandwidth stand-in), `..._per_door_flip`, `client_play_opacity_redraws`, and a full-map turf contents
sweep (`contents_loop_*_ms` / `_entries`). Timings are single wall-clock runs on a loaded machine: compare within one run.

Results on the test map (18 airlocks, 10 lights, 20 rounds):

| Run | DM lighting | Client lighting | Notes |
|---|---|---|---|
| before the early-out | 2153-3172 ms | 4241-6075 ms | door flips were ~4.9 s of it |
| `0e9f7be45de5` | 3009 ms (moves 1884) | 1459 ms (moves 362) | 2280 mask builds, 3.17 per door flip |
| margin bounds, 2 tiles (not landed) | 3031 ms | 1569 ms margin / 1275 ms none | contents sweep 9261 entries vs 4197 none, 3986 DM |
| full-reach bounds (not landed) | 3172 ms | 4606 ms | contents sweep 27053 entries vs 4197 none |

Profile of the client play (`0e9f7be45de5`): `client_glow_mask_apply` 0.68 s self (shape-key `jointext`), `/datum/New`
0.2 s, `vg_sight_view` 0.07 s over 5040 calls.

## 4. Approaches rejected (do not redo)

- **Glow bounds over the reach** (`GLOB.client_glow_bounds`): BYOND counts the glow on every turf its bounds cover
  (`locs`) and sends it; works, but each glow joins ~100 turfs' contents: 6.4x the entries in every contents loop.
- **Margin-only bounds** (2 tiles): 2.2x the entries, and a long-range glow's dim edge still pops in. Rejected by the user.
- **A screen object holder**: screen objects do not scroll with the map or follow its glide; glows would jump each step.
- **The player's mob as holder (`vis_contents`)**: every client viewing that mob draws them; glows are additive, so other
  players see doubled light.
- **Images on the mob**: per-step offset updates for every overlapping light.

## 5. The design to build: per-client glow images anchored on in-view turfs

For each client, for each glowing light whose reach overlaps the client's view but whose own turf is **not** in the
client's view:

1. Pick an **anchor**: the in-view turf nearest the light along the line from the client's eye to the light (a turf at
   the view edge on that line). It is on the map, so an image on it glides with the world; no update when the player steps.
2. Show that client an `/image` (`client.images`) on the anchor, with `pixel_x/y = (light.x - anchor.x) * 32 + the glow's
   own offset`, plane `PLANE_LIGHTING`, `BLEND_ADD`, the glow's icon, colour and alpha.
3. **The mask render-target pitfall.** The glow's `alpha` filter reads its mask through `render_source`. A render target
   only renders if its object is itself drawn for that client. The real mask sits in the real glow's `vis_contents` on the
   light's turf, which this client cannot see, so a filter on the image pointing at that mask draws **no mask**: the glow
   shines through walls. Each client image needs **its own mask copy** that this client renders: a second image (or the
   image's own `vis_contents`/overlay that carries the mask) on the same anchor with the same offsets, with its own
   `render_target` name (unique per client and light, e.g. `*cglow_mask_[handle_of(light)]_[ckey]`), and the glow image's
   alpha filter pointing at that name. Verify the mask image renders without being visible (leading `*`).
4. Lights whose own turf **is** in the client's view keep the normal glow object; no image copy (no double drawing).
   When a light crosses into view, drop its image; when it leaves view while its reach still overlaps, add one.
5. **Events, no polling.** Recompute a client's set when:
   - its eye crosses a chunk or the view edge moves (the interest system, `code/engine/change/interest.dm`,
     already reports chunk entry/exit per owner: `interest_arrive()`, `interest_hold_set()`, counters
     `interest_chunks_entered/left`);
   - a light glows, moves, changes range or turns off (`client_glow_apply()` / `client_glow_clear()`);
   - its mask rebuilds (`client_glow_mask_apply()` when the key changes: update that light's mask image for each client
     showing it).
   Find candidate lights by reach-overlap through `GLOB.client_glow_chunks` (chunks within `CLIENT_GLOW_MAX_RANGE` of the
   view rectangle). Keep per-client state as an owned datum (relation forms, `owns_one`/`owns_many`), not raw lists on `/client`.
6. Drop an image when the light's reach no longer overlaps the view, the light is deleted, client lighting is switched
   off (`client_lighting_set(FALSE)`), or the client logs out.

## 6. Tests to add (`code/tests/unit_tests/dq_client_lighting_tests.dm`)

- **A light just off-screen shows its glow on screen**: a test client or eye at a known turf; a light `range` tiles
  beyond its view edge; assert the client's `images` hold a glow image whose anchor turf is in view and whose offsets put
  it at the light's true position, plus a mask image whose `render_target` the glow's filter names.
- **No double drawing**: the light moves into view -> its image is dropped, the normal glow is in view.
- **Occlusion still applies**: a wall between light and view edge; the mask image's tiles exclude the shadowed turfs.
- **Event-driven**: stepping the eye within one chunk does not touch images (count image updates); crossing a chunk does.
- **Cleanup**: client lighting off, light deleted and logout each leave no images.
- Keep the existing ones passing: `dq_client_lighting_toggle`, `dq_client_lighting_shadows`,
  `dq_client_light_level_parity`, `dq_client_lighting_lum_watch`, `dq_light_step_drops_deleted_sources`,
  `dq_sight_layer_follows_opacity`.
- Tests that switch the mode must call `set_global(nameof(GLOB.client_lighting), FALSE)` first (state-leak check), and
  must never use `CHECK_TICK` paths (the test clock does not resume them; `client_lighting_set()` has none).

Bench the holder with `client_lighting_play` against no bounds: add the holder bookkeeping cost (images created/updated
per round) as metrics.

## 7. Then: per-client compare mode

The user wants to flip between old and new lighting live and compare. Today the switch is server-wide. Proposal: a
compare mode where the server runs both paths (lighting objects and glows); a per-client preference picks which one the
client sees by hiding one plane's contents for that client (old underlays live on turfs on `PLANE_LIGHTING`; give glows
their own plane, e.g. a new `PLANE_CLIENT_LIGHTING` with the same multiply master, and toggle plane-master alpha per
client). Compare mode costs both engines at once, so it is admin-only and off by default; normal mode runs one engine.

## 8. Rules that bit this session

- Lint (`bash tools/ci/check_ratchets.sh --changed-only`) rejects: raw `icon/pixel/color/alpha` writes on atoms (use
  `set_*`), `qdel()` in content (use `spent()`), hand-rolled `var/static/list` caches (use `DECLARE_SHARED_CACHE`),
  counter-minted ids (use `handle_of()`), damage-entry overrides like `ex_act()`, turf vars written raw (annotate as
  the lighting turf caches are).
- Defines a file needs before its includes go in `code/defines/...` (file order is alphabetical).
- Bench `--profile` only dumps inside `begin_window()`/`end_window()`.
- A requeued deleted light source used to spin `light_step()`; it is guarded now, but still skip `QDELETED` sources
  in any loop that requeues lights.
- I could not run a client: everything above is verified server-side only. The user judges the look in play.
