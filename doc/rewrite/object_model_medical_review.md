# Object model: medical/body review (MED-0)

Reviewer: DQ Medical lane, 2026-09-27. Reviewed `doc/rewrite/object_model.md` as on
`rewrite/om-integration`, against the medical code on `rewrite/reconcile` (Life already runs
on OM pipelines, `code/modules/mob/living/life/life_om.dm`; grants in
`code/datums/om/contribution.dm`). Verdict: **approved with the change requests below.**
The hold on code touching life systems, grants, traits/genes, body destruction and species
is lifted.

## Agree

- **Life systems as behaviours on one scheduler (§10).** Already true in practice:
  `/datum/om/decl/living` declares the `life`, `life_derive`, `life_present` and
  `life_vision` pipelines, and the pipeline runner owns idle/wake/park. `life_wake()` is the
  medical-side name for `wake()`; keep it as a thin wrapper so the hibernation lint and
  `MOB_HIBERNATE_AUDIT` keep one entry point. The generalised missed-wake audit (§10) is the
  same contract we already test.
- **Fixed-step Life frames.** `LIFE_CYCLE` stepping with `max_catchup` is what physiology
  and oxygen debt need (dose/time integrals). Behaviours with `period` must keep this
  fixed-step, catch-up semantics, not "run once when late".
- **Grants for traits/genes (§5.6).** Trait/gene/perk contributions of `BF_*` factors and
  flags fit the contribution/grant model. `GRANT_TRAIT` exists; revoke-on-source-loss is
  exactly what gene removal and organ/implant removal need.
- **Survivors leave first, outermost first (§14.1).** Matches `lifecycle.md` phase 0.5:
  body mind slot, then head, then brain; MMI/ghost spawn while the mob still has a `loc`.
- **Species and materials as frozen DEFs (§3).** Correct and overdue: the event-headset
  species mutation is the bug class. Per-mob variation belongs in body factors
  (`factor_baseline` read-only on species, deltas as contributions on the mob).
- **Afflictions as owned entities in datum slots (§4).** Afflictions are owned by the
  `/datum/body`, never shared; `DELETE` policy on body destruction, `TRANSFER` only for the
  organ-carried ones (see below).

## Change requests

1. **Grants: doc and code disagree.** §5.6 says grants are rich edges (150–250 B); the code
   implements them as `COMBINE_SUM_PER_KEY` contributions. Keep the contribution form (a
   human carries dozens of trait grants; rich edges would cost several KB per mob) and fix the
   doc. Use a rich edge only when the grant has its own state or behaviour.
2. **Add `GRANT_GENE`** (or document that genes are a `source` granting `GRANT_TRAIT`s).
   Gene activation must be revocable per source so a gene removed by surgery or
   mutation-cure revokes only what it gave.
3. **Organ-carried afflictions follow the organ.** Body destruction must `TRANSFER` an
   organ's own afflictions (infection, necrosis, implant rejection) with the organ when it
   spills, and `DELETE` body-level ones (shock, oxygen debt, vital systems). Name this as a
   slot policy on `/datum/body` afflictions (`KEEP_WITH(organ)`), not a Destroy override.
4. **`death()` is not destruction.** The doc should say explicitly that death is a state
   transition (behaviour state machine on the body), guarded and idempotent, and that
   destruction of a dead mob runs §14 normally. P2-D4/A8 (double death side effects, double
   loot) are this bug; MED-2 guards it now.
5. **Species DEF writes at runtime.** 39 sites assign through `species.<var> =`. Before
   `readonly` is enforced, those need moving to per-mob body factors or a cloned
   per-mob species override; list them in the ratchet rather than failing boot.
6. **Life frame requirements.** `stat == DEAD`, stasis (`BF_STASIS`) and "no body" must be
   requirements (§8) on the pipelines, not early returns inside stages, so the active set
   excludes corpses and stasis mobs for free.
7. **Timed contributions for modifiers (MED-5).** The `timer`/contribution expiry must be
   in the body's clock (stasis slows it), which `om_clock_rate` supports; call it out in §12.

## Risks

- **Two scheduler vocabularies** (`life_wake` bits vs OM channels) drifting. Mitigation:
  one mapping table, the hibernation audit in test builds.
- **Differential tests for Life.** Porting stages to behaviours can change ordering
  (breathing before circulation before metabolism). Keep the stage order declared
  (`after`/`before`) and diff physiology outputs old vs new over N frames.
- **Destroy ordering with brains in MMIs, heads, bodies inside sleepers/bellies.** Nested
  TRANSFER chains need a test each (brain in head in body in closet, destroyed from the
  closet).
- **Frozen species in test builds** will fail existing tests that mutate species; fix
  those tests first.
- **Track ownership.** DQ Medical owns mob Life stages, `/datum/body`, organs, species,
  afflictions, treatments, traits/genes grant kinds. The OM lane owns the scheduler,
  contribution store and destroy pipeline. Changes to `life_om.dm` pipeline declarations
  need both.
