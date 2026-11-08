# Client-side compositing and an async renderer for human looks

Status: approved direction (2026-11-08). Stages A (this document) and B (the comparison switch) are built. C and D wait on the
comparison result in section 7. Nothing here is the default yet.

## 1. Why the server composites today

`code/content/mob/living/carbon/human/human_look.dm` builds `/icon` objects in DM: body, hair, damage, tail, wings, eyes and bellies go
through `human_look_icon()` -> `CACHED_KEY(human_look_icons, ...)`. A hit is cheap. A miss pays the whole build on the tick, inside
`appearance_drain` (`refresh_drain()`, `code/engine/change/refresh.dm`), which checks its budget only between atoms, so one draw cannot be
split. Round 20.37.04 logged one human draw at 88.7 ms (a 411% tick); that figure covers every output of the draw, not only the icons.

The code is inherited. Each generated icon also has to be sent to every client as a new resource, so a composite costs tick time and
download.

The rest of the draw is already client-side: worn items are images, and `make_worn_icon()` already cuts a taur's clothing with an alpha
filter (for example `code/content/items/weapons/storage/belt.dm:44`).

## 2. What BYOND allows

From the DM reference (`filter()`, `blend_mode`, `color`, `appearance_flags`, `/icon`):

- `/icon` procs (`Blend`, `Insert`, `MapColors`, `SwapColor`, `Crop`, `ColorTone`, `SetIntensity`) run only on the server. The client
  cannot run them, so anything that truly needs new pixels is a server or native job.
- `color` on an atom or image is a multiply by an RGB value or a colour matrix. A matrix has a constant row, so "add this colour" is expressible.
- `KEEP_TOGETHER` renders an atom and its overlays as one surface first. Colour and transform then apply to the group, and the reference
  notes `RESET_COLOR` is meaningless for a child of a `KEEP_TOGETHER` parent. (This caught client lighting's masks, `f726426042`.)
- `BLEND_INSET_OVERLAY` draws an overlay only where the surface below it has alpha. It needs `KEEP_TOGETHER`.
- The `alpha` filter masks by an icon or a render source, with x/y offsets. Filters cost client frame time per filtered thing, so they are
  used only where nothing else works.
- Overlay frames follow the holder's `dir`, but an overlay cannot be hidden per facing without either a frame that is blank for that facing
  (generated pixels) or a redraw that reads `dir`.

## 3. Every operation in `human_look.dm`, classified

Read from each builder on master. "Client" = overlays, colour or a matrix. "Filter" = expressible, at a per-frame client cost. "Pixels" = needs a
generated icon. Exactness marked "approx" must be compared by eye before it is the default.

| Builder | Operation | Class |
|---|---|---|
| `build_body_icon`, per limb (`organ_icon.dm` `get_icon`) | limb sprite | Client |
| `apply_colouration`, skin | `Blend` ICON_MULTIPLY / ICON_ADD | Client (`color`, or a matrix for add) |
| `apply_colouration`, transparent limb | `MapColors` + `SetIntensity` | Client (matrix) |
| `apply_colouration`, dead limb | `ColorTone` + `SetIntensity` | Client, approx (ColorTone is not a single linear map) |
| `get_icon`, markings, body hair, nail polish | tinted overlay | Client |
| `get_icon`, transparent limb `+= rgb(,,,180)` | alpha | Client (`alpha`) |
| `build_body_icon`, taur leg cutter (ICON_AND at an offset) | mask | Filter, one per clipped limb or one on a `KEEP_TOGETHER` leg group |
| `build_body_icon`, left/right `Insert` per facing | limb order differs by facing | Pixels, or a draw that reads `dir` (open question 1) |
| `build_body_icon`, `base_icon += rgb(,,,180)` | whole-body alpha | Client |
| husk `ColorTone` | tone | Client, approx |
| hulk `MapColors` | matrix | Client |
| husk overlay, masked to the body | inset | Client (`BLEND_INSET_OVERLAY` in `KEEP_TOGETHER`) |
| `build_damage_look`: overlay x limb mask x blood | icon times icon | Filter per damaged limb, or Pixels (the renderer's natural job) |
| `build_hair_look`, facial and hair tint, `icon_add` | tint, add | Client (two images; add is a `BLEND_ADD` overlay in the group) |
| `build_hair_look`, gradient ICON_AND hair | inset | Client (`BLEND_INSET_OVERLAY` in `KEEP_TOGETHER`) |
| `build_hair_look`, `Crop` for tall ears | canvas | Client (not needed: overlays may exceed the canvas) |
| `get_ears_overlay` | tint, up to 3 parts, alpha | Client |
| `build_eyes_look` | tint, add, alpha | Client |
| `build_species_tail_dirs`, `icon_keep_dirs` | frames per facing | Pixels, or a draw that reads `dir` |
| `build_tail_icon` | whole file tinted, hair overlay | Client (animation is native) |
| `build_tail_image`, `build_wing_image` | tint, up to 3 parts | Client; a tail still needs `icon_keep_dirs` as above |
| `build_vore_belly` | tint | Client |
| `body_taur_cutter`, its `SwapColor`s | invert a mask | Pixels, once per taur style (a static input, no per-player cost) |

Summary: nearly all of a human is client-expressible. What needs pixels or a filter is four things: damage masks, facing-dependent order
(legs, tails), taur cutters, and exact `ColorTone`. Taur and husk are not blanket exceptions, as an earlier estimate guessed.

## 4. Client cost: the reason to measure

Layering moves work from a one-time server build to every client's frame. A body becomes roughly 10-30 overlays instead of 1, and a filter adds
a render pass. Appearances are shared by content and should cost little on the wire, but frame cost is unknown and agents cannot see client
frames. Section 7's switch exists to measure this.

## 5. The renderer (`verdigris`)

Replaces on-tick `/icon` composition for what needs pixels. Iconforge's limit is its fixed operation list plus our exact-match fallback; the
renderer implements every operation we use, so there is no fallback path.

- **Job API over FFI.** DM submits a recipe (the ordered operation list, file references, colours, the content key) and gets a job id; a
  worker pool composes off-thread; one system polls completed jobs with a per-tick budget (the shape of `portrait_cache.dm`'s poll).
- **Inputs.** Source DMIs are decoded once in Rust and retained.
- **Delivery.** A result is written as a DMI, then loaded on the main thread (`icon()`/`fcopy_rsc`). That load stays on the tick; it is one
  load per finished job, under the system's budget, and must be counted.
- **Sending.** A generated icon is still a resource sent to each client that sees it. Layering first shrinks how many exist.
- **First build.** No previous look exists: show the species' base body as a placeholder until the job lands, then mark the human for redraw. A
  first build never runs synchronously. There is no pre-warming of common looks.
- **Later looks.** Keep the previous icon until the new one lands.
- **Determinism.** Same recipe, same bytes; cached by content key as today.

## 6. Migration order

1. (B) Comparison switch for the plain body. Off by default.
2. (C) If layering is cheap enough: body, hair, ears, eyes, wings, tails and bellies become layers, default on, one builder family at a time.
3. (D) Renderer core and FFI, then damage masks, facing frames and taur cutters.
4. Delete the `/icon` builders as each loses its last caller. The other `.Blend(` and `getFlatIcon(` sites convert in their own lanes.

## 7. How the comparison runs (stage B)

Admin verbs under Debug: **Spawn Look Test Crowd** puts 20 humans around you, and **Toggle Layered Human Bodies** switches every human's body
between composited and layered. Compare client frame rate and feel with the crowd on screen, in both states. The switch covers the plain body
only; bodies that need section 3's other classes (taur cutters, husk, hulk, skeleton, transparent or dead limbs) stay composited.

In layered mode side-facing legs draw in one fixed order. That is an approximation for the comparison, not the proposed final look.

## 8. Rollback

Until C the flag is off by default and nothing changes. During C each builder family converts in its own commit, revertible on its own. The
`/icon` builders stay until the replacement has been played on.

## 9. Open questions

1. Facing-dependent order: generated frames (cheap to draw, needs the renderer) or a draw that reads `dir` (no pixels, but every turn redraws).
   Recommendation: generated frames, keeping the "a turn redraws nothing" property.
2. How far layering goes depends on section 7's result.
3. `ColorTone` approximation: acceptable, or renderer?
4. The exact semantics of `icon += rgb(,,,a)` against `image.alpha` should be checked by eye during C.
