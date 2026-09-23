// Codecs for the saved reference vars of the base types (doc/rewrite/state.md
// section 3). Saved reference vars without a codec are refused at runtime,
// which keeps their holder real; the lint allowlist says why each one is left so.

/atom/state_codecs()
	return ..() + list(
		"flags" = /datum/state_codec/atom_flags,
		"reagents" = /datum/state_codec/reagents,
		"forensic_data" = /datum/state_codec/owned,
		"wires" = /datum/state_codec/owned,
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

/obj/machinery/state_codecs()
	return ..() + list(
		"circuit" = /datum/state_codec/child,
		"paicard" = /datum/state_codec/child,
	)

// Sparse-var components (code/datums/components/sparse_vars/) come first, as
// state.md section 2 asks: the per-instance ones save, the caches are dropped.

/datum/component/forensics_state
	state_mode = STATE_COMPONENT_SAVE

/datum/component/forensics_state/state_codecs()
	return ..() + list("forensic_data" = /datum/state_codec/owned)

/datum/component/catalogue_delay_override
	state_mode = STATE_COMPONENT_SAVE

/datum/component/chat_color_cache
	state_mode = STATE_COMPONENT_DERIVED

/datum/component/update_on_z
	state_mode = STATE_COMPONENT_DERIVED
