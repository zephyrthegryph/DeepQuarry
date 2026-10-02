# Object model event subscriptions

Subscriptions extend the existing `om_emit()` event dispatcher. They do not
replace events or automatically detect writes. An observable producer must use
its checked setter and call `om_changed()` (or `om_mark_changed()` for typed
change groups) after state changes.

## Behaviour declarations

Override `declare_observers()` on a shared behaviour definition:

```dm
/datum/object_model/behaviour/medical_display/declare_observers(datum/object_model/subscription_plan/P)
	var/datum/object_model/subscription_rule/R = P.on(
		/datum/object_model/event/health_changed,
		TYPE_PROC_REF(/obj/machinery/medical_display, on_health_changed))
	R.from_related(/datum/object_model/relation/scanned_patient)
	R.when_all(list(
		/datum/object_model/subscription_condition/display_powered,
		/datum/object_model/subscription_condition/patient_in_range))
	R.on_match(TYPE_PROC_REF(/obj/machinery/medical_display, refresh_patient))
```

The behaviour singleton builds this plan once. Activation installs one token
per rule on each entity; deactivation and deletion cancel those tokens.
`om_validate_observer_plan()` checks callbacks, event and relation paths,
condition expressions, and duplicate rules during archetype validation.

Use `R.from_any()` for a global event subscription. It receives every source
emitting that event and should be reserved for service-style consumers.
Direct subscriptions need a target at runtime:

```dm
var/datum/object_model/subscription/token = om_subscribe(
	src, /datum/object_model/subscription_rule/my_direct_rule, patient)
```

The token is owned by `src`; it also cancels if the direct target is deleted.
Call `qdel(token)` to cancel early. A related rule follows all targets currently
linked from the listener through its declared relation and automatically
rebinds after `om_link()` or `om_unlink()`.

## Conditions

A leaf condition is a shared `/datum/object_model/subscription_condition`
definition. Override its pure, non-sleeping `test(listener, source)` proc. For
additional state owners read by that predicate, override `dependencies()` to
return those datums. A change producer must publish `om_changed()` on each of
those datums so `on_match` refreshes when the condition becomes true.

`R.when_all(list(...))`, `R.when_any(list(...))`, and `R.when_not(condition)`
compose predicates. Nested expressions use `om_condition_all(list(...))`,
`om_condition_any(list(...))`, and `om_condition_not(condition)`. The expression
is built once on the shared plan. `on_match` is a current-state refresh when a
target newly satisfies the condition; events skipped while a predicate is false
are not replayed. Event handlers receive `(source, event, a, b, c, d)`, and
match handlers receive `(source)`.

Direct and related event dispatch is indexed by `(source, event path)`; global
subscriptions are indexed by event path. Event delivery is synchronous unless
the event definition requests deferred coalescing. Conditions should be cheap;
do not perform diagnosis or other expensive derived calculations inside them.
