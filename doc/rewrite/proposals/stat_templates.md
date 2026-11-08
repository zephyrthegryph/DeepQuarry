# Stat templates and hook baselines at birth (E4)

Status: design, not implemented. Owner: perf/engine-init.

## Problem

Each atom's birth runs the same work as every other instance of its type:

- `stat_holder_init()` recomputes every computed stat of the type (`I.init_todo`): it evaluates each contribution's gates and values.
- The on_change hooks take their baseline. The baseline is the values a hook compares against at the first drain.

For most instances every input of that work equals the type's default. Examples are a light fixture in a powered area, or a pipe with no map edits. So the result is the same per type, but it is computed once per instance.

## Template

A template is recorded per type, the first time an instance's inputs all equal the type defaults. It holds two things:

- the computed value of each stat in `init_todo`;
- the baseline of each hook.

A later instance takes the template when its inputs equal the defaults the template was recorded under. Otherwise it falls back to the full computation, as today. A template is only ever a cache of that computation; it never replaces it with something different.

### When an instance may take the template

- **No per-instance edits.** The instance has no map-edited stat constant (`rec.constants` is null) and no own value on any var a stat reads. The type's `stat_input_keys` give that set, and the check uses the DM per-instance store (`initial()`).
- **Its gates read nothing outside itself.** A contribution's gate or value that reads through a relation, a hop, a system or a capability key makes the type ineligible. A machine's power stat reads `power_area.power_equip`, so it does not template. That includes the machines, which are the main cost in `machine_power_start()`. They stay on the fallback; they got cheaper through the shared evaluation context (one per stat compute, landed with this design).
- **Its gate procs are declared pure.** CG_PROC gates already run under the purity guard. A template is allowed only when the generated reads (`deps.dm`) of each gate proc cover only the instance's own vars.

Eligibility is decided once per type from its declarations. The template's values are taken from the first eligible instance, never guessed.

### Parity

- **Test builds.** For the first N instances of each templated type, both paths run and the stat records and hook baselines are compared. A mismatch fails there. The same pattern as `pool_direct_reset_check()`.
- **Golden test.** A test in `dq_init_plan_golden.dm` style records the full computation for every templated type and compares it with the template.

## Hook baselines

Silent construction already publishes construction writes once, at birth. The hook census found 31 (type, hook) pairs whose content relies on firing for what setup wrote. Those must still fire. Their baseline is the init-time value, and the template must keep that value rather than the post-setup one.

A hook baseline goes in the template only when the hook's reads are template-eligible by the same rules as above.

## Expected saving and decision

The deep boot profile puts `stat_holder_init` at the bulk of `stat_recompute`'s 130k calls. Templates would apply to the types without relation reads: pipes, cables, structures and items with gated stats.

The decision: implement templates only after a census shows that the template-eligible instances at least a third of the remaining stat_recompute time. Machines, which were the motivating case, are not eligible. Their saving was taken with the shared evaluation context.
