// Codecs for the saved reference vars of the base types (doc/rewrite/state.md
// section 3). Saved reference vars without a codec are refused at runtime,
// which keeps their holder real; the lint allowlist says why each one is left so.

/atom/state_codecs()
	return ..() + list(
		"flags" = /datum/state_codec/atom_flags,
		"reagents" = /datum/state_codec/reagents,
		"forensic_data" = /datum/state_codec/owned,
		"wires" = /datum/state_codec/owned,
		"artifact_master" = /datum/state_codec/pinned,
	)

/// Integrity starts at max_integrity (set by Initialize()), so it is only state once it differs.
/atom/state_exclude()
	. = ..()
	if(atom_integrity == max_integrity)
		. += "atom_integrity"

/// /datum/wires excludes its own holder ref from state (C5); restore it once
/// the atom's own vars, including a decoded wires datum, are all applied.
/atom/state_post_apply(list/blob, flags)
	..()
	if(wires)
		wires.holder = src

// constraint_overrides holds compiled /datum/predicate instances (rules.md
// §3), each a cached, shared-by-key singleton rather than owned by this item
// (C5); excluded rather than refused, so a latent-safe item with one (a
// refitted suit, an exact-fit box) still serializes.
/obj/item/state_exclude()
	. = ..()
	. += "constraint_overrides"

// Variants (code/datums/variants/): a variant's own vars are left out of the
// delta, and restored by applying the variant before the delta is written.
/obj/item/state_variant_baseline()
	return dq_variant_vars(type, variant)

/obj/item/state_pre_apply(list/vars, flags)
	..()
	if(!("variant" in vars) || vars["variant"] == variant)
		return
	variant = vars["variant"]
	apply_variant()

// Generated in Initialize(), so a sampled pristine instance can't stand in for another's.
/obj/item/clothing/head/fishing/state_nondeterministic_list_vars()
	return ..() + list("item_state_slots")

/obj/item/trash/material/state_nondeterministic_list_vars()
	return ..() + list("material_mix")

/obj/machinery/state_codecs()
	return ..() + list(
		"circuit" = /datum/state_codec/child,
		"paicard" = /datum/state_codec/child,
	)

// Sparse per-instance state (code/datums/sparse_vars/) lives in plain vars:
// forensics saves with the atom's delta, the caches are tmp. Live references
// (HUD alternate appearances, observer listeners, movement relays, cloak and
// light state) keep the object real, as their components used to.

/atom/state_refusal()
	. = ..()
	if(.)
		return
	if(alt_appearances_owned || alt_appearances_viewing)
		return "has alternate appearances, which cannot be serialized"
	if(observer_event_listeners)
		return "has observer-event listeners, which cannot be serialized"

/atom/movable/state_refusal()
	. = ..()
	if(.)
		return
	if(recursive_move)
		return "has a recursive move relay, which cannot be serialized"
	if(dq_movable_state_set(src))
		return "has live movement state (sparse movable vars), which cannot be serialized"

/// Owned children with live wiring pin their holder (/datum/state_codec/pinned).
/obj/item/state_codecs()
	return ..() + list(
		"mind_host" = /datum/state_codec/pinned,
		"economic_adoption" = /datum/state_codec/pinned,
		"material_response" = /datum/state_codec/pinned,
		"carried_afflictions" = /datum/state_codec/pinned,
	)

/obj/item/paper/state_codecs()
	return ..() + list("contract_document" = /datum/state_codec/pinned)
