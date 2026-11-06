// gear_tweak/variant — populate a loadout picker from a variant registry
// instead of typesof()-enumerating subtypes. Used together with the variant
// variant pattern (one type with a `variant` arg; see README.md here).
//
// Construction:
//   new /datum/gear_tweak/variant(list("Display Name" = "variant_key", ...))
//
// On spawn the chosen variant_key is stashed in gear_data.variant; in
// tweak_item we set item.variant and call apply_variant() to reconfigure
// the freshly-spawned item with the variant's name/icon_state/etc.

/datum/gear_data
	// variant string set by gear_tweak/variant, consumed in tweak_item.
	var/variant

/datum/gear_tweak/variant
	var/list/valid_variants

/datum/gear_tweak/variant/New(list/valid_variants)
	src.valid_variants = valid_variants
	..()

/// The picker choices of a variant family: display name -> key. The parent with no key is offered first, under its own name.
/proc/gear_variant_choices(obj/item/parent)
	var/list/choices = list()
	choices[initial(parent.name)] = null
	var/list/table = dq_variant_table(parent)
	for(var/key in table)
		var/list/row = table[key]
		choices[row["name"] || key] = key
	return choices

/// Saved metadata is the display name. A save made when each variant was a type (or by key) holds the name that type had or the key.
/datum/gear_tweak/variant/migrate_metadata(metadata)
	if(!istext(metadata) || (metadata in valid_variants))
		return metadata
	for(var/name in valid_variants)
		if(valid_variants[name] == metadata || lowertext(name) == lowertext(metadata))
			return name
	return metadata

/datum/gear_tweak/variant/get_inline_choices()
	return valid_variants ? assoc_to_keys(valid_variants) : list()

/datum/gear_tweak/variant/validate_inline_value(value, mob/user)
	if(!(value in valid_variants))
		return PREF_UPDATE_REJECTED
	return value

/datum/gear_tweak/variant/get_contents(metadata)
	return "Variant: [metadata]"

/datum/gear_tweak/variant/get_default()
	for(var/k in valid_variants)
		return k

/datum/gear_tweak/variant/metadata_steps(mob/user, metadata, datum/gear/gear, title = "Character Preference")
	return list(gear_ask_choice("value", title, "Choose a variant.", valid_variants, metadata))

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
	I.set_variant(v)
	I.apply_variant()

// Base hooks. A consolidated type declares its table with variants(nameof(variant), PROC_REF(x)) (code/engine/lifeforms/variants.dm),
// applied at preinit; apply_variant() applies it again when a loadout tweak sets the key after creation. A type whose table is not
// a row of vars (the crayons') overrides apply_variant() instead.
/obj/item
	var/variant

/obj/item/proc/apply_variant()
	variant_apply(src)
