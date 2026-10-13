# Staleness findings (2026-10-12)

The staleness checker (`code/engine/change/staleness.dm`, `doc/rewrite/final_api.html` section 7, "The staleness checker") is fully enforcing: any report
fails the current test. Its first measurement (over `dq_staleness_*`, `dq_life_*`, `dq_stat*`, `dx_*stat*`, `dq_generated_deps*`, `dq_power_wakes*`, `dq_draw_*`,
`dq_boot_gate` and the two look pins) found three root causes, all fixed before it landed enforcing:

1. A stat var written raw by game code: `invisibility` on pipes and terminals (`hide()`).
2. Door `density` and `opacity` written raw.
3. A lapsed `LIFE_CYCLE` status hold left `blinded` set on humans.

The draw, `derive()` and keyed-image checks found nothing in that set. That is a result about the set (mostly draw tests that write through setters), not a proof
for the `draw_untracked` sites.

## Exempt by design: a read during teardown (`trait_holds`)

The checker skips an entity that is `QDELING`. Recorded because it is a real ordering fact: `/datum/capability/lib/climb/on_holder_destroy` (and the closet, mouse and
radiation-clothing capabilities) call `remove_trait()`, whose first line `has_trait()` reads the keyed `trait_holds` stat after the holder's own holds were taken
apart, so it answers from a list that still names the trait (cached `{"trait_climbable":1}`, fresh `[]`). It was 291 reports across about 30 tests. Harmless today
(`remove_trait` finds nothing to release); if a capability ever acts on that answer in a destroy hook, it acts on a trait it no longer holds.

## Failures seen that are not staleness (on `80f838d71b` without the checker)

`dq_draw_turkeygirl_follows_nutrition`, `dx_deps_output_writes_state` (`refresh_flush` still queued after 20 passes), `dq_look_state_pin` (snapshot rows differ) and
`dq_look_tree_pin` (`DECLARE ... is not an entry or a capability` on the metroid and syndicate mobs). `dq_state_latent_round_trip` failed on 2 of 6425 types in a
checker run (`/image` has no codec: `emotions.joymask_designs`, `tactical_sec_vis.tac_sec_vis_anim`); that was not confirmed against master.
