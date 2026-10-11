// Concrete body-slot policy metadata. Holder is always the wearer; actor is
// the actual mover, retained independently for any transfer requirement.
/datum/relation_definition/slot/body/admission_read_keys(atom/holder, atom/movable/thing, mob/actor)
	. = ..()
	var/mob/living/wearer = holder
	if(!istype(wearer))
		return
	. += wearer.body_slot_read_keys(src)
	if(acceptance_declared(GLOB.native_equipment_acceptance, slot_id))
		. += dq_native_equip_slot_reads(wearer, slot_id, thing, actor)

/datum/relation_definition/slot/body/removal_read_keys(atom/holder, atom/movable/thing, mob/actor)
	. = ..()
	var/mob/wearer = holder
	var/obj/item/I = thing
	if(istype(wearer) && istype(I))
		. += wearer.unequip_read_keys(I)

/mob/living/proc/body_slot_read_keys(datum/relation_definition/slot/body/def)
	return list(list(src, SLOT_OCCUPANCY_KEY), list(src, nameof(body)))

/mob/living/simple_mob/body_slot_read_keys(datum/relation_definition/slot/body/def)
	. = ..()
	if(istype(def, /datum/relation_definition/slot/body/hand))
		. += list(list(src, nameof(has_hands)))

/mob/living/silicon/robot/body_slot_read_keys(datum/relation_definition/slot/body/def)
	. = ..()
	if(istype(def, /datum/relation_definition/slot/body/module))
		. += list(list(src, nameof(module)))

/mob/living/carbon/human/body_slot_read_keys(datum/relation_definition/slot/body/def)
	. = ..()
	. += list(list(src, nameof(species)), list(src, nameof(organs)))
	if(species)
		. += list(list(species, nameof(species.hud)))
		var/datum/hud_data/HUD = species.hud
		if(HUD)
			. += list(list(HUD, nameof(HUD.equip_slots)))
	// The cache is external parts derived from the ledger. Every nested part
	// holder can gain, lose or rekey a part even when the root remains fixed.
	for(var/obj/item/organ/external/E as anything in organs)
		. += list(list(E, SLOT_OCCUPANCY_KEY), list(E, nameof(E.organ_tag)))

// Part slots' keyed capacity and join rules read candidate identity even
// before it has a holder. Type membership and stump behavior are immutable.
/datum/relation_definition/slot/part/admission_read_keys(atom/holder, atom/movable/thing, mob/actor)
	. = ..()
	var/obj/item/organ/O = thing
	if(istype(O))
		. += list(list(O, nameof(O.organ_tag)), list(O, nameof(O.parent_organ)))

/datum/relation_definition/slot/part/child/admission_read_keys(atom/holder, atom/movable/thing, mob/actor)
	. = ..()
	var/obj/item/organ/external/parent = holder
	if(istype(parent))
		. += list(list(parent, nameof(parent.organ_tag)))

// Downstream inventory provider; no query-time mutation or message output.
/mob/proc/unequip_read_keys(obj/item/I)
	. = list(list(src, SLOT_OCCUPANCY_KEY))
	if(!I)
		return
	. += list(list(I, ATOM_KEY_LOC), list(I, nameof(I.canremove)), list(I, nameof(I.body_parts_covered)))
	var/slot = inventory_slot_id(I)
	var/datum/relation_definition/slot/body/def = dq_ledger_peek(src)?.def_by_id(slot)
	if(!istype(def) || !def.covered_by)
		return
	var/obj/item/covering = get_equipped_item(def.covered_by)
	if(covering)
		. += list(list(covering, ATOM_KEY_LOC), list(covering, nameof(covering.body_parts_covered)))
