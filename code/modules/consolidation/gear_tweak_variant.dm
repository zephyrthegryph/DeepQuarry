// gear_tweak/variant — populate a loadout picker from a variant registry
// instead of typesof()-enumerating subtypes. Used together with the variant
// consolidation pattern (one type with a `variant` arg, see clothing_*.dm).
//
// Construction:
//   new /datum/gear_tweak/variant(list("Display Name" = "variant_key", ...))
//
// On spawn the chosen variant_key is stashed in gear_data.variant; in
// tweak_item we set item.variant and call apply_variant() to reconfigure
// the freshly-spawned item with the variant's name/icon_state/etc.

/datum/gear_data
	// DQAdd — variant string set by gear_tweak/variant, consumed in tweak_item.
	var/variant

/datum/gear_tweak/variant
	var/list/valid_variants

/datum/gear_tweak/variant/New(list/valid_variants)
	src.valid_variants = valid_variants
	..()

/datum/gear_tweak/variant/get_contents(metadata)
	return "Variant: [metadata]"

/datum/gear_tweak/variant/get_default()
	for(var/k in valid_variants)
		return k

/datum/gear_tweak/variant/get_metadata(user, metadata)
	return tgui_input_list(user, "Choose a variant.", "Character Preference", valid_variants, metadata)

/datum/gear_tweak/variant/tweak_gear_data(metadata, datum/gear_data/gear_data)
	if(!(metadata in valid_variants))
		return
	gear_data.variant = valid_variants[metadata]

/datum/gear_tweak/variant/tweak_item(obj/item/I, metadata)
	if(!istype(I))
		return
	if(!(metadata in valid_variants))
		return
	var/v = valid_variants[metadata]
	I.variant = v
	I.apply_variant()

// Base hooks. Override apply_variant() on each consolidated type to apply
// the variant's overrides to the item. The default implementation does
// nothing so non-consolidated items can ignore this.
/obj/item
	var/variant

/obj/item/proc/apply_variant()
	return
