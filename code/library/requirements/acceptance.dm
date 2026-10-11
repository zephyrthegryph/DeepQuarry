// Native ordered acceptance requirements and their actual state dependencies.
// Requirement results are null to allow or the exact refusal reason.
/datum/entry/part/req/acceptance_leaf/holds(datum/act/op/A)
	return isnull(acceptance_reason(A))

/datum/entry/part/req/acceptance_leaf/refusal(datum/act/op/A)
	if(!isnull(src.args["because"]))
		return ..()
	return acceptance_reason(A)

/datum/entry/part/req/acceptance_leaf/proc/acceptance_reason(datum/act/op/A)
	return /datum/msg/req_failed

/proc/req_acceptance_type(types, exclude = FALSE, because = null)
	var/list/paths = ispath(types) ? list(types) : types
	if(!islist(paths))
		CRASH("acceptance type must be a path or list of paths")
	return part_make(/datum/entry/part/req/acceptance_leaf/type, list("types" = paths.Copy(), "exclude" = exclude, "because" = because))

/datum/entry/part/req/acceptance_leaf/type/acceptance_reason(datum/act/op/A)
	var/fits = FALSE
	if(A?.target)
		for(var/type in src.args["types"])
			if(istype(A.target, type))
				fits = TRUE
				break
	if(fits != !!src.args["exclude"])
		return null
	return src.args["exclude"] ? "not that kind of thing" : "only takes certain things"

/proc/fits(list/bodytypes, exclude = FALSE, because = null, negate = FALSE)
	if(!islist(bodytypes))
		CRASH("fits requires an explicit list of bodytype names")
	var/list/names = bodytypes.Copy()
	return part_make(/datum/entry/part/req/acceptance_leaf/fit, list("bodytypes" = names, "exclude" = exclude, "because" = because, "negate" = negate))

/datum/entry/part/req/acceptance_leaf/fit/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	var/obj/item/I = A?.target
	var/list/names = src.args["bodytypes"]
	var/exclude = src.args["exclude"]
	var/fits = TRUE
	var/bodytype = "your body"
	if(istype(H) && istype(I) && H.species)
		bodytype = H.species.get_bodytype(H)
		fits = dq_fits_bodytype(names, exclude, bodytype, I.sprite_sheets)
	if(fits != !!src.args["negate"])
		return null
	if(src.args["negate"])
		return "it fits you"
	if(exclude)
		return "it doesn't fit a [bodytype]"
	if(length(names) > 3)
		return "it isn't made for a [bodytype]"
	return "it only fits [english_list(names, and_text = " or ")]"

// Size requirements carry an explicit numeric size-class unit.
/proc/req_acceptance_max_size(size, unit, because = null)
	var/datum/property_def/D = dq_property_registry().defs[PROP_SIZE_CLASS]
	if(!D || D.kind != PROP_KIND_MEASURE || unit != D.unit || !isnum(size))
		CRASH("acceptance size limit must use the size-class property's numeric unit")
	return part_make(/datum/entry/part/req/acceptance_leaf/max_size, list("max_size" = size, "unit" = unit, "because" = because))

/datum/entry/part/req/acceptance_leaf/max_size/acceptance_reason(datum/act/op/A)
	if(!A?.target)
		return "needs something in hand"
	var/current = dq_property(A.target, PROP_SIZE_CLASS)
	if(isnull(current))
		var/datum/property_def/D = dq_property_registry().defs[PROP_SIZE_CLASS]
		return "[lowertext(D.name || D.id)] unknown"
	if(current <= src.args["max_size"])
		return null
	return "too big: [dq_format_measure(current, PROP_UNIT_SIZE_CLASS)] > [dq_format_measure(src.args["max_size"], PROP_UNIT_SIZE_CLASS)]"

/proc/req_acceptance_tag(tag_id, exclude = FALSE, because = null)
	var/datum/property_def/D = dq_property_registry().defs[tag_id]
	if(!D || D.kind != PROP_KIND_TAG)
		CRASH("tag requirement needs a known tag property")
	return part_make(/datum/entry/part/req/acceptance_leaf/property_tag, list("tag" = tag_id, "exclude" = exclude, "because" = because))

/datum/entry/part/req/acceptance_leaf/property_tag/acceptance_reason(datum/act/op/A)
	var/has_tag = A?.target && dq_has_tag(A.target, src.args["tag"])
	if(has_tag != !!src.args["exclude"])
		return null
	var/datum/property_def/D = dq_property_registry().defs[src.args["tag"]]
	var/adjective = D.adjective || lowertext(D.name || D.id)
	return src.args["exclude"] ? "must not be [adjective]" : "must be [adjective]"

/datum/entry/part/req/acceptance_leaf/has_uniform/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	var/obj/item/I = A?.target
	if(!ishuman(H) || H.get_equipped_item(SLOT_ID_UNIFORM) || !(SLOT_ID_UNIFORM in dq_equip_slots_of(H)))
		return null
	return "you need a jumpsuit first"


/datum/entry/part/req/acceptance_leaf/glove_layering/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	var/obj/item/I = A?.target
	if(!ishuman(H) || !istype(I, /obj/item/clothing/gloves))
		return null
	var/obj/item/clothing/gloves/new_gloves = I
	if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/accessory))
		var/obj/item/clothing/accessory/ring = H.get_equipped_item(SLOT_ID_GLOVES)
		if(ring.glove_level >= new_gloves.glove_level)
			return "\the [ring] is in the way"
	else if(istype(H.get_equipped_item(SLOT_ID_GLOVES), /obj/item/clothing/gloves))
		var/obj/item/clothing/gloves/worn = H.get_equipped_item(SLOT_ID_GLOVES)
		if(worn.glove_level >= new_gloves.glove_level || worn.overgloves)
			return "\the [worn] are in the way"
	return null


/datum/entry/part/req/acceptance_leaf/left_ear_free/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	var/obj/item/I = A?.target
	return (ishuman(H) && H.get_equipped_item(SLOT_ID_EAR_L)) ? "it needs both ears free" : null


/datum/entry/part/req/acceptance_leaf/right_ear_free/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	var/obj/item/I = A?.target
	return (ishuman(H) && H.get_equipped_item(SLOT_ID_EAR_R)) ? "it needs both ears free" : null


/datum/entry/part/req/acceptance_leaf/accessory_attachable/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	var/obj/item/I = A?.target
	if(ishuman(H))
		for(var/obj/item/clothing/W in H.get_worn_clothing())
			if(W.can_attach_accessory(I))
				return null
	return "you're not wearing anything you can attach it to"


/datum/entry/part/req/acceptance_leaf/backpack_takes/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	var/obj/item/I = A?.target
	var/obj/item/storage/backpack/B = ishuman(H) ? H.get_equipped_item(SLOT_ID_BACK) : null
	if(!istype(B))
		return "you have no backpack"
	return dq_ledger_refusal(I, B, CONTAINER_SLOT_STORAGE, H)

/datum/entry/part/req/acceptance_leaf/suit_storage_takes/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	var/obj/item/I = A?.target
	if(!istype(H))
		return "there's nowhere to put it"
	var/obj/item/suit = H.get_equipped_item(SLOT_ID_SUIT)
	if(!suit)
		return "you need a suit first"
	// Engine must distinguish absent/cleared channel from a declared unconstrained channel.
	if(!dq_constraint_present(suit, CONSTRAINT_SUIT_STORAGE))
		return "\the [suit] has no suit storage"
	if(istype(I, /obj/item/pda) || istype(I, /obj/item/pen))
		return null
	return dq_constraint_refusal(suit, CONSTRAINT_SUIT_STORAGE, I, H, A.mover)

/proc/req_acceptance_has_uniform(because = null)
	return part_make(/datum/entry/part/req/acceptance_leaf/has_uniform, list("because" = because))

/proc/req_acceptance_glove_layering(because = null)
	return part_make(/datum/entry/part/req/acceptance_leaf/glove_layering, list("because" = because))

/proc/req_acceptance_left_ear_free(because = null)
	return part_make(/datum/entry/part/req/acceptance_leaf/left_ear_free, list("because" = because))

/proc/req_acceptance_right_ear_free(because = null)
	return part_make(/datum/entry/part/req/acceptance_leaf/right_ear_free, list("because" = because))

/proc/req_acceptance_accessory_attachable(because = null)
	return part_make(/datum/entry/part/req/acceptance_leaf/accessory_attachable, list("because" = because))

/proc/req_acceptance_backpack_takes(because = null)
	return part_make(/datum/entry/part/req/acceptance_leaf/backpack_takes, list("because" = because))

/proc/req_acceptance_suit_storage_takes(because = null)
	return part_make(/datum/entry/part/req/acceptance_leaf/suit_storage_takes, list("because" = because))

// Resolve only actual registered property dependency providers.
/proc/acceptance_property_read_keys(datum/thing, property)
	. = list()
	if(!thing)
		return
	var/datum/property_registry/R = dq_property_registry()
	for(var/datum/property_provider/P as anything in R.contributors[property])
		if(istype(thing, P.applies_to))
			CRASH("acceptance property contributor [P.type] needs native dependency metadata")
	var/datum/property_provider/base = R.base_provider(thing.type, property)
	if(istype(base, /datum/property_provider/type_var/tag/slot_flag))
		var/obj/item/I = thing
		if(istype(I))
			. += list(list(I, ITEM_WORN_KEY))
		return
	if(istype(base, /datum/property_provider/type_var/tag/sharp))
		var/obj/item/I = thing
		if(istype(I))
			. += list(list(I, ITEM_COMBAT_KEY))
		return
	if(property == PROP_SIZE_CLASS && base?.state_var == "w_class")
		var/obj/O = thing
		if(istype(O))
			. += list(list(O, nameof(O.w_class)))
		return
	if(base)
		CRASH("acceptance property base [base.type] needs native dependency metadata")

/datum/entry/part/req/acceptance_leaf/type/read_keys(datum/act/op/A)
	return null
/datum/entry/part/req/acceptance_leaf/max_size/read_keys(datum/act/op/A)
	return acceptance_property_read_keys(A?.target, PROP_SIZE_CLASS)
/datum/entry/part/req/acceptance_leaf/property_tag/read_keys(datum/act/op/A)
	return acceptance_property_read_keys(A?.target, src.args["tag"])

/proc/acceptance_species_read_keys(mob/living/carbon/human/H)
	. = list()
	if(!istype(H))
		return
	. += list(list(H, nameof(H.species)))
	if(H.species)
		. += H.species.acceptance_bodytype_reads(H)

/datum/entry/part/req/acceptance_leaf/fit/read_keys(datum/act/op/A)
	. = acceptance_species_read_keys(A?.wearer)
	var/obj/item/I = A?.target
	if(istype(I))
		. += list(list(I, nameof(I.sprite_sheets)))

/proc/acceptance_wearer_slot_reads(mob/wearer)
	return wearer ? list(list(wearer, SLOT_OCCUPANCY_KEY)) : list()

/datum/entry/part/req/acceptance_leaf/has_uniform/read_keys(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	. = acceptance_wearer_slot_reads(H)
	if(!istype(H))
		return
	. += list(list(H, nameof(H.species)))
	var/datum/species/S = H.species
	if(!S)
		return
	. += list(list(S, nameof(S.hud)))
	var/datum/hud_data/HUD = S.hud
	if(HUD)
		. += list(list(HUD, nameof(HUD.equip_slots)))

/datum/entry/part/req/acceptance_leaf/glove_layering/read_keys(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	. = acceptance_wearer_slot_reads(H)
	var/obj/item/clothing/gloves/new_gloves = A?.target
	if(istype(new_gloves))
		. += list(list(new_gloves, nameof(new_gloves.glove_level)))
	if(!istype(H))
		return
	var/obj/item/worn = H.get_equipped_item(SLOT_ID_GLOVES)
	if(istype(worn, /obj/item/clothing/accessory))
		var/obj/item/clothing/accessory/ring = worn
		. += list(list(ring, nameof(ring.glove_level)))
	if(istype(worn, /obj/item/clothing/gloves))
		var/obj/item/clothing/gloves/G = worn
		. += list(list(G, nameof(G.glove_level)), list(G, nameof(G.overgloves)))

/datum/entry/part/req/acceptance_leaf/left_ear_free/read_keys(datum/act/op/A)
	return acceptance_wearer_slot_reads(A?.wearer)
/datum/entry/part/req/acceptance_leaf/right_ear_free/read_keys(datum/act/op/A)
	return acceptance_wearer_slot_reads(A?.wearer)

/datum/entry/part/req/acceptance_leaf/accessory_attachable/read_keys(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	. = acceptance_wearer_slot_reads(H)
	var/obj/item/clothing/accessory/incoming = A?.target
	if(istype(incoming))
		. += list(list(incoming, nameof(incoming.slot)))
	if(!istype(H))
		return
	for(var/obj/item/clothing/W in H.get_worn_clothing())
		// Base owns_many exists in integrated_electronics/assemblies/clothing.dm:49.
		. += list(list(W, nameof(W.accessories)), list(W, nameof(W.valid_accessory_slots)), list(W, nameof(W.restricted_accessory_slots)))
		for(var/obj/item/clothing/accessory/attached in W.accessories)
			. += list(list(attached, nameof(attached.slot)))

/datum/entry/part/req/acceptance_leaf/suit_storage_takes/read_keys(datum/act/op/A)
	var/mob/living/carbon/human/H = A?.wearer
	. = acceptance_wearer_slot_reads(H)
	var/obj/item/I = A?.target
	if(!istype(H))
		return
	var/obj/item/suit = H.get_equipped_item(SLOT_ID_SUIT)
	if(suit)
		. += suit.acceptance_override_reads()
		. += dq_constraint_read_keys(suit, CONSTRAINT_SUIT_STORAGE, I, H, A.mover)

// Backpack read_keys supplied by pure admission worker, never legacy ACT_TRY.

/datum/entry/part/req/acceptance_leaf/backpack_takes/read_keys(datum/act/op/A)
	var/mob/living/carbon/human/H = A.wearer
	var/obj/item/I = A.target
	. = acceptance_wearer_slot_reads(H)
	if(!istype(H))
		return
	var/obj/item/storage/backpack/B = H.get_equipped_item(SLOT_ID_BACK)
	if(istype(B))
		. += dq_ledger_read_keys(I, B, CONTAINER_SLOT_STORAGE, H)

/datum/entry/part/req/acceptance_leaf/proc/suit_clearance_reads(datum/act/op/A)
	. = list()
	var/mob/living/carbon/human/H = A.wearer
	if(!istype(H))
		return
	. += list(list(H, SLOT_OCCUPANCY_KEY))
	var/obj/item/suit = H.get_equipped_item(SLOT_ID_SUIT)
	if(!suit)
		return
	. += list(list(suit, ITEM_WORN_KEY), list(suit, SLOT_OCCUPANCY_KEY))
	// The actual clearance callbacks iterate suit contents, not the accessories
	// lookup list; contents ledger covers physical insertion and removal.
	for(var/obj/item/clothing/accessory/W in suit)
		. += list(list(W, ITEM_WORN_KEY))



/// Whether clothing restricted to `bodytypes` fits `bodytype`. Custom-fitted
/// Vox, Werebeast and Teshari clothing fits only them, and Teshari and
/// Werebeasts need their own sprites for anything restricted.
/proc/dq_fits_bodytype(list/bodytypes, exclusive, bodytype, list/sprite_sheets)
	if(exclusive)
		return !(bodytype in bodytypes)
	if(bodytype in bodytypes)
		return TRUE
	if(((SPECIES_VOX in bodytypes) && bodytype != SPECIES_VOX) || ((SPECIES_WEREBEAST in bodytypes) && bodytype != SPECIES_WEREBEAST) || ((SPECIES_TESHARI in bodytypes) && bodytype != SPECIES_TESHARI))
		return FALSE
	if((bodytype == SPECIES_TESHARI || bodytype == SPECIES_WEREBEAST) && !LAZYACCESS(sprite_sheets, bodytype))
		return FALSE
	return TRUE



/proc/req_acceptance_owner_key(owner_key, because)
	return part_make(/datum/entry/part/req/acceptance_leaf/owner_key, list("owner_key" = owner_key, "because" = because))
/datum/entry/part/req/acceptance_leaf/owner_key/acceptance_reason(datum/act/op/A)
	var/mob/wearer = A.wearer
	return wearer?.ckey == src.args["owner_key"] ? null : src.args["because"]
/datum/entry/part/req/acceptance_leaf/owner_key/read_keys(datum/act/op/A)
	var/mob/wearer = A.wearer
	// Generic client lifecycle and registered key setters publish genuine identity changes.
	return wearer ? list(list(wearer, MOB_KEY_CLIENT)) : list()

/proc/req_acceptance_taur_shape(tail_type, because)
	return part_make(/datum/entry/part/req/acceptance_leaf/taur_shape, list("tail_type" = tail_type, "because" = because))
/datum/entry/part/req/acceptance_leaf/taur_shape/acceptance_reason(datum/act/op/A)
	var/mob/living/carbon/human/H = istype(A.wearer, /mob/living/carbon/human) ? A.wearer : null
	return H && istype(H.tail_style, src.args["tail_type"]) ? null : src.args["because"]
/datum/entry/part/req/acceptance_leaf/taur_shape/read_keys(datum/act/op/A)
	var/mob/living/carbon/human/H = istype(A.wearer, /mob/living/carbon/human) ? A.wearer : null
	return H ? list(list(H, nameof(H.tail_style))) : list()
