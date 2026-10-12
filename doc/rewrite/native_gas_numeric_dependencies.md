# Committed native gas numeric dependencies

## Contract

A cached reader must observe the same pressure as `return_pressure()` immediately after a synchronous gas operation. The turf getter includes accepted local commands before the worker frame; numeric readers sample that actual host-visible value immediately, then sample again when the worker view commits. They never publish the mutation's tentative calculation instead of the getter's real view.

The branch implements `gas_numeric_read(air = nameof(air_contents))` and the pure accessor `gas_numeric_pressure(air_contents)`. This first form supports pressure only. It prepares a shared numeric producer outside pure evaluation. The producer's `pressure_kpa` field contains actual kPa; its native subscription and identity are framework state. It does not use a synthetic revision as the reader's value or invent a holder state key. Verification is pending.

The holder's declared mixture relation and the mixture's actual native identity are dependencies. Replacing `air_contents`, rebinding a mixture datum to a pipe region, deleting a mixture, or retiring its native slot rebinds the producer before evaluation resumes. The old subscription cannot overwrite the new producer. An absent mixture reads zero. A destroyed holder releases its subscription and producer scope.

The synchronous engine `HOLDER_HOOK_RELATION` hook prepares real relation-dependent producers before a relation write publishes. Deferred `on_change()` alone cannot do this: a new mixture could otherwise be read before its numeric producer exists. Native identity bindings capture the old actual opaque handle and run its registered setter at the completed binding boundary. Existing `READ_LOOKUP` ties the live numeric identity and the selected producer's tracked pressure into menu/output dependencies. Capability IDs are generated from the normal `CAPABILITY_TYPE` registry; the new holder-hook bit is 9, outside the existing bits 0–8.

Pure UI and requirement code only reads the prepared numeric producer. Preparing, allocating, subscribing, refreshing or retargeting a producer in `ui_data`, requirements or memo callbacks is forbidden. Existing effectful lookup preparation is the appropriate integration point; its declared registry identity and selected result field must be genuine producers.

## Commit transport

Use a separate native numeric-commit queue. Do not consume `drain_observations()`, clear `HELD` gas watches, or run ordinary frame dispatch from a synchronous gas write. Queue records name the live subscription and carry the actual final pressure, sampled from committed storage. Emit no record for a rejected, immutable, failed or unchanged write. Native identity retirement is a separate lifetime event and must occur before slot reuse.

Drain once at completion of the outer mutation binding, after native borrow guards have unwound. Apply all committed numeric records through their real setters inside `state_batch()`. This prevents a two-mixture transfer from presenting one side's new value and the other side's old value to an operation requirement. A public compound gas operation such as `copy_from_ratio()` must preserve its existing operation boundary: it currently issues copy and multiply as two separate bindings, and must bracket their numeric publication rather than expose a new intermediate admission state.

An explicit generated mutation-binding post-hook is necessary. Attaching the hook to every gas binding would run effects during pure getter calls. Attaching it only to a handful of DM convenience setters would miss direct bindings and pump/transfer paths. Mutation metadata must enumerate actual bindings and be validated by the generator.

## Actual commit paths

- `verdigris/ffi/src/gas/mix.rs:store`: Main replaces the live slab value; Pipe applies the conserved delta to the actual region. Publish after storage succeeds, sampling `load(r)`, not the caller's tentative `after` value. Turf only submits `GasCmd::Delta` and must not publish a numeric commit there.
- `with_mix_mut` commits one mixture. `with_mixes_mut` commits both participants; delivery happens after both stores. Gas temperature, volume and mole setters reach these helpers.
- `verdigris/ffi/src/gas/binds.rs` also calls `store` directly for transfers, pump operations and bulk updates. Those bindings need the same outer completion boundary.
- `copy_from_ratio` in `code/ATMOSPHERICS/gasmixtures/gas_mixture.dm` calls copy and multiply separately. Its publication scope must enclose both.
- Native handle registration and `__bind_handle` use `MixRef::store` (identity assignment, distinct from gas-state `store`). These must publish the real identity change and seed/rebind any demanded producer.
- `free`, `retain` and pipe topology retirement must retire numeric identities before reuse. Numeric arena IDs alone are insufficient evidence that a queued observation still belongs to the same live subscription.
- Pipe network/device commits can bypass mixture `store`. `refresh_pipe_mirrors` discovers the committed region changes and must also feed demanded numeric producers.
- `frame` calls `world::pace`, then takes committed gas observations. Turf producers refresh from the same pinned committed world view at this boundary, before the frame binding returns to DM. Reuse `turf_refresh_plan`'s committed chunk selection; include numeric-only subscribers, not just existing ordinary watch subscribers.

## Required focused regressions

1. Warm the real disposal UI, change temperature, volume and moles with real gas APIs, and read again before normal native-watch drain. The percentage equals `return_pressure()` after each commit; repeated reads reuse the cached output.
2. Transfer, merge and copy-ratio operations update both participating producers atomically. A pending operation whose final requirement remains satisfied must not be cancelled by an intermediate publication.
3. Replace the disposal reservoir and deliver an old reservoir event afterwards. The new UI follows the new live mixture and ignores the old identity.
4. Delete a holder, mixture or native identity and reuse a slot. No callback updates the deleted holder or a producer belonging to a prior subscription.
5. Submit a turf command: the dependency and native getter remain on the old committed value. Commit the worker view: both change together, including native pipe/device changes outside host mixture setters.
6. Rejected, immutable, zero-effect and invalid mutations publish no fictitious pressure change. Preserve the getter's existing zero-volume behavior exactly.

## Migration gate

The disposal pressure read now uses the committed producer and its former broad settings publication is removed. Source regressions are present, but generation, compilation and focused verification have not run on this draft. No claim of a completed channel landing is made until that gate passes.

## Validated lookup argument providers

`READ_LOOKUP_ARGUMENT(/type/proc/getter, reads = list(nameof(field)))` declares a zero-argument numeric identity getter. This is separate from `READS_AS`: the generator does not substitute the raw field for the getter's result. The analyzer validates the actual getter and every descendant override before accepting it: receiver reads must be covered by the listed tracked fields; effects, volatile globals, allocation and uncovered reads are rejected. Undeclared opaque getters remain rejected.

The generated lookup descriptor carries the real receiver path, declaring type, absolute `TYPE_PROC_REF`, and tracked input keys. During lookup binding preparation, the engine walks the actual receiver path, subscribes to those inputs, evaluates the actual dynamically dispatched getter under the pure guard, then binds the resulting numeric registry identity and selected producer. No pooled action context is captured. Input changes rerun the getter and retarget the producer binding.

Native identity completion drains numeric retirement records before delivering the actual identity setter, within the same atomic publication boundary. Even when the numeric arena slot is reused immediately and the setter's numeric value compares equal, surviving consumers whose old source was retired attach to the newly live native occupant. The `dq_gas_numeric_live_identity_reuse` test exercises real native unregister/register reuse and a warmed disposal UI; `dq_lookup_argument_provider_runtime` independently proves a transformed getter drives menu retargeting instead of its raw input.
## Relation-preparation failure cleanup

Holder hooks borrow a pooled `/datum/act/eval`. The shared `run_holder_hook()` boundary releases that lease on both success and exception, then rethrows the original exception without removing existing tracing. This also protects preinit, init and destroy hooks that share the same dispatch boundary. `dq_gas_numeric_relation_hook_exception` dispatches an actual declared throwing relation preparer and checks the original exception, exact release count, outstanding pool leases, released context state and reset borrowed references. It fails if the hook bypasses release.
