// Body slots (doc/rewrite/containment.md §6, roadmap C3).
//
// A mob's slots belong to its body plan. Each plan returns its slot list from
// /datum/body/proc/slot_def_types(); the mob hands it to the ledger through
// /mob/living/slot_def_types(), keyed by "[mob type]|[plan type]".
//
// A body slot refuses a thing when:
//   1. the body part it hangs on is missing (required_parts / any_parts,
//      the part map below);
//   2. the holder's own rules say no (body_slot_refusal(): the species has no
//      such slot, a simple mob has no hands);
//   3. the slot's `accepts` predicate says no. For worn slots that is P3's
//      equip slot predicate (code/datums/properties/equip_slots.dm),
//      evaluated with the WEARER as PRED_ACTOR, as those predicates expect.
//
// Part map (humanoid; mirrors the old has_organ_for_slot()):
//   hand_l            BP_L_HAND
//   hand_r            BP_R_HAND
//   gloves            BP_L_HAND or BP_R_HAND
//   handcuffed        BP_L_HAND and BP_R_HAND
//   shoes             BP_L_FOOT or BP_R_FOOT
//   legcuffed         BP_L_FOOT and BP_R_FOOT
//   head, mask, eyes, ear_l, ear_r                                BP_HEAD
//   back, belt, uniform, suit, suit_storage, pocket_l, pocket_r   BP_TORSO
//   id, body          none
//
// Not slots: slot_tie (an accessory goes on the clothing, not the body),
// slot_in_backpack (a move into the back item's storage) and slot_legs (unused).
//
// Equipping, picking up, dropping and throwing are ledger moves into these
// slots (code/modules/mob/inventory.dm); the ledger is the only record of what
// a mob wears and holds.

/datum/om/relation/slot/body
	name = "body slot"
	exposure = SLOT_EXPOSURE_EXTERNAL
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	// Deleting a mob deletes what it wears and holds, as it always has (the
	// base Destroy() qdels contents); gibbing and death drops move items out
	// first. SPILL here would litter every deleted mob's turf.
	drop_policy = SLOT_DROP_HOLDER
	// Hits on the mob reach equipment through the zone armour (worn_protection.dm), not this path.
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
	/// slot_* number the equip API names this slot by, or null.
	var/legacy_slot
	/// BODY_SLOT_* roles.
	var/roles = NONE
	/// BP_* parts that must all be present (and not stumps).
	var/list/required_parts
	/// BP_* parts of which at least one must be present.
	var/list/any_parts

/datum/om/relation/slot/body/refusal(atom/holder, atom/movable/thing, mob/actor)
	var/mob/living/wearer = holder
	if(!istype(wearer))
		return "there's nowhere to put it"
	. = wearer.body_slot_refusal(src)
	if(.)
		return .
	if(accepts)
		var/datum/predicate/P = dq_predicate(accepts)
		return P.why_not(wearer, thing, null)
	return null

// ---- The shared slot ----

/// Organs, implants, bellies and anything else inside the mob.
/datum/om/relation/slot/body/interior
	slot_id = SLOT_ID_BODY
	name = "body"
	exposure = SLOT_EXPOSURE_INTERNAL
	capacity_model = SLOT_CAPACITY_NONE
	capacity = 0
	is_default = TRUE
	// Organs, implants and whatever else sits inside the body go with it when the mob is
	// deleted, as they always have (gibbing and surgery move them out first). SPILL here
	// dropped every deleted mob's organs on its turf.
	drop_policy = SLOT_DROP_HOLDER
	// The body model handles what reaches organs; nothing passes this way.
	heat_transmission = 0
	radiation_transmission = 0

// ---- Hands ----

/datum/om/relation/slot/body/hand
	exposure = SLOT_EXPOSURE_EXTERNAL

/datum/om/relation/slot/body/hand/left
	slot_id = SLOT_ID_HAND_L
	name = "left hand"
	legacy_slot = slot_l_hand
	required_parts = list(BP_L_HAND)

/datum/om/relation/slot/body/hand/right
	slot_id = SLOT_ID_HAND_R
	name = "right hand"
	legacy_slot = slot_r_hand
	required_parts = list(BP_R_HAND)

// ---- Humanoid equipment ----

/datum/om/relation/slot/body/head
	slot_id = SLOT_ID_HEAD
	name = "head"
	legacy_slot = slot_head
	accepts = /datum/predicate/equip_slot/head
	roles = BODY_SLOT_WORN | BODY_SLOT_ARMOR | BODY_SLOT_INSULATION
	required_parts = list(BP_HEAD)

/datum/om/relation/slot/body/mask
	slot_id = SLOT_ID_MASK
	name = "mask"
	legacy_slot = slot_wear_mask
	accepts = /datum/predicate/equip_slot/mask
	roles = BODY_SLOT_WORN | BODY_SLOT_ARMOR | BODY_SLOT_INSULATION
	required_parts = list(BP_HEAD)

/datum/om/relation/slot/body/suit
	slot_id = SLOT_ID_SUIT
	name = "suit"
	legacy_slot = slot_wear_suit
	accepts = /datum/predicate/equip_slot/suit
	layer = SLOT_LAYER_SUIT
	roles = BODY_SLOT_WORN | BODY_SLOT_ARMOR | BODY_SLOT_INSULATION
	required_parts = list(BP_TORSO)

/datum/om/relation/slot/body/uniform
	slot_id = SLOT_ID_UNIFORM
	name = "uniform"
	legacy_slot = slot_w_uniform
	accepts = /datum/predicate/equip_slot/uniform
	layer = SLOT_LAYER_UNIFORM
	roles = BODY_SLOT_WORN | BODY_SLOT_ARMOR | BODY_SLOT_INSULATION
	required_parts = list(BP_TORSO)

/datum/om/relation/slot/body/gloves
	slot_id = SLOT_ID_GLOVES
	name = "gloves"
	legacy_slot = slot_gloves
	accepts = /datum/predicate/equip_slot/gloves
	roles = BODY_SLOT_WORN | BODY_SLOT_ARMOR | BODY_SLOT_INSULATION
	any_parts = list(BP_L_HAND, BP_R_HAND)

/datum/om/relation/slot/body/shoes
	slot_id = SLOT_ID_SHOES
	name = "shoes"
	legacy_slot = slot_shoes
	accepts = /datum/predicate/equip_slot/shoes
	roles = BODY_SLOT_WORN | BODY_SLOT_ARMOR | BODY_SLOT_INSULATION
	any_parts = list(BP_L_FOOT, BP_R_FOOT)

/// Glasses: armour (get_covering_clothing() counts them) but not conductivity
/// or thermal protection, as before.
/datum/om/relation/slot/body/eyes
	slot_id = SLOT_ID_EYES
	name = "eyes"
	legacy_slot = slot_glasses
	accepts = /datum/predicate/equip_slot/glasses
	roles = BODY_SLOT_WORN | BODY_SLOT_ARMOR
	required_parts = list(BP_HEAD)

/datum/om/relation/slot/body/ear_left
	slot_id = SLOT_ID_EAR_L
	name = "left ear"
	legacy_slot = slot_l_ear
	accepts = /datum/predicate/equip_slot/ear/left
	roles = BODY_SLOT_WORN
	required_parts = list(BP_HEAD)

/datum/om/relation/slot/body/ear_right
	slot_id = SLOT_ID_EAR_R
	name = "right ear"
	legacy_slot = slot_r_ear
	accepts = /datum/predicate/equip_slot/ear/right
	roles = BODY_SLOT_WORN
	required_parts = list(BP_HEAD)

/datum/om/relation/slot/body/back
	slot_id = SLOT_ID_BACK
	name = "back"
	legacy_slot = slot_back
	accepts = /datum/predicate/equip_slot/back
	roles = BODY_SLOT_WORN
	required_parts = list(BP_TORSO)

/datum/om/relation/slot/body/belt
	slot_id = SLOT_ID_BELT
	name = "belt"
	legacy_slot = slot_belt
	accepts = /datum/predicate/equip_slot/belt
	roles = BODY_SLOT_WORN
	required_parts = list(BP_TORSO)

/datum/om/relation/slot/body/id
	slot_id = SLOT_ID_ID
	name = "ID"
	legacy_slot = slot_wear_id
	accepts = /datum/predicate/equip_slot/id
	roles = BODY_SLOT_WORN

/// Suit storage: clipped inside the suit.
/datum/om/relation/slot/body/suit_storage
	slot_id = SLOT_ID_SUIT_STORAGE
	name = "suit storage"
	legacy_slot = slot_s_store
	exposure = SLOT_EXPOSURE_INTERNAL
	accepts = /datum/predicate/equip_slot/suit_storage
	roles = BODY_SLOT_WORN
	required_parts = list(BP_TORSO)

/datum/om/relation/slot/body/pocket
	exposure = SLOT_EXPOSURE_INTERNAL
	required_parts = list(BP_TORSO)

/datum/om/relation/slot/body/pocket/left
	slot_id = SLOT_ID_POCKET_L
	name = "left pocket"
	legacy_slot = slot_l_store
	accepts = /datum/predicate/equip_slot/pocket/left

/datum/om/relation/slot/body/pocket/right
	slot_id = SLOT_ID_POCKET_R
	name = "right pocket"
	legacy_slot = slot_r_store
	accepts = /datum/predicate/equip_slot/pocket/right

/datum/om/relation/slot/body/handcuffed
	slot_id = SLOT_ID_HANDCUFFED
	name = "wrists"
	legacy_slot = slot_handcuffed
	accepts = /datum/predicate/equip_slot/handcuffs
	required_parts = list(BP_L_HAND, BP_R_HAND)

/datum/om/relation/slot/body/legcuffed
	slot_id = SLOT_ID_LEGCUFFED
	name = "ankles"
	legacy_slot = slot_legcuffed
	accepts = /datum/predicate/equip_slot/legcuffs
	required_parts = list(BP_L_FOOT, BP_R_FOOT)

// ---- Cyborg modules ----

/// A cyborg's active module slot: takes only its own module's tools.
/datum/om/relation/slot/body/module
	/// Module slot number, 1-3.
	var/module_index

/datum/om/relation/slot/body/module/one
	slot_id = SLOT_ID_MODULE_1
	name = "module 1"
	module_index = 1

/datum/om/relation/slot/body/module/two
	slot_id = SLOT_ID_MODULE_2
	name = "module 2"
	module_index = 2

/datum/om/relation/slot/body/module/three
	slot_id = SLOT_ID_MODULE_3
	name = "module 3"
	module_index = 3

// ---- Per-plan slot lists ----
//
// Each decl's `holder` (slot_def.dm, object_model_core.md) names the body
// plan type it belongs to -- the registry builds each plan's slot list once,
// grouped by holder, replacing the old per-plan slot_def_types() override.
// Declaration order (the `order` field below) matters to the worn-protection
// cache: head, mask, suit, uniform, gloves, shoes, eyes is the old
// covering-clothing order.
//
// Silicon mobs are keyed by their own mob type, not their body plan
// (/mob/living/silicon/slot_holder_key() below): drones and the AI decoy
// share the same plain /datum/body/simple/machine plan, but only drones (and
// other /mob/living/silicon/robot subtypes -- cyborgs) get module slots. A
// decoy's own type has no declared group, so it gets no ledger at all, same
// as before.

/datum/om/relation/slot/body/hand/left
	holder = list(/datum/body/simple, /datum/body/humanoid)
	order = 1

/datum/om/relation/slot/body/hand/right
	holder = list(/datum/body/simple, /datum/body/humanoid)
	order = 2

/datum/om/relation/slot/body/interior
	holder = list(/datum/body/simple, /datum/body/humanoid, /mob/living/silicon/robot)
	order = 20

/datum/om/relation/slot/body/module/one
	holder = /mob/living/silicon/robot

/datum/om/relation/slot/body/module/two
	holder = /mob/living/silicon/robot

/datum/om/relation/slot/body/module/three
	holder = /mob/living/silicon/robot
	slot_id = SLOT_ID_MODULE_3

/datum/om/relation/slot/body/head
	holder = /datum/body/humanoid
	order = 3

/datum/om/relation/slot/body/mask
	holder = /datum/body/humanoid
	order = 4

/datum/om/relation/slot/body/suit
	holder = /datum/body/humanoid
	order = 5

/datum/om/relation/slot/body/uniform
	holder = /datum/body/humanoid
	order = 6

/datum/om/relation/slot/body/gloves
	holder = /datum/body/humanoid
	order = 7

/datum/om/relation/slot/body/shoes
	holder = /datum/body/humanoid
	order = 8

/datum/om/relation/slot/body/eyes
	holder = /datum/body/humanoid
	order = 9

/datum/om/relation/slot/body/ear_left
	holder = /datum/body/humanoid
	order = 10

/datum/om/relation/slot/body/ear_right
	holder = /datum/body/humanoid
	order = 11

/datum/om/relation/slot/body/back
	holder = /datum/body/humanoid
	order = 12

/datum/om/relation/slot/body/belt
	holder = /datum/body/humanoid
	order = 13

/datum/om/relation/slot/body/id
	holder = /datum/body/humanoid
	order = 14

/datum/om/relation/slot/body/suit_storage
	holder = /datum/body/humanoid
	order = 15

/datum/om/relation/slot/body/pocket/left
	holder = /datum/body/humanoid
	order = 16

/datum/om/relation/slot/body/pocket/right
	holder = /datum/body/humanoid
	order = 17

/datum/om/relation/slot/body/handcuffed
	holder = /datum/body/humanoid
	order = 18

/datum/om/relation/slot/body/legcuffed
	holder = /datum/body/humanoid
	order = 19

// ---- The mob side ----

/mob/living/slot_holder_key()
	return body?.type || type

/mob/living/silicon/slot_holder_key()
	return type

/// A slot's contents changed (ledger moves): worn protection and, for items
/// with worn factors, the body factors are stale.
/mob/living/on_slot_changed(slot_id, atom/movable/thing, inserted)
	. = ..()
	var/obj/item/I = thing
	var/domains = BODY_DIRTY_ARMOR
	if(istype(I) && I.worn_factors)
		domains |= BODY_DIRTY_FACTORS
	body?.invalidate(domains)
	on_equipment_changed()

/// Why this mob can't use body slot `def` right now, or null: the holder's own
/// rules, checked before the slot's `accepts`.
/mob/living/proc/body_slot_refusal(datum/om/relation/slot/body/def)
	if(istype(def, /datum/om/relation/slot/body/hand) && !has_hands_to_hold())
		return "you have no hands"
	return null

/// Whether this mob has working hands for its hand slots.
/mob/living/proc/has_hands_to_hold()
	return FALSE

/mob/living/carbon/has_hands_to_hold()
	return !istype(src, /mob/living/carbon/brain)

/mob/living/simple_mob/has_hands_to_hold()
	return has_hands

/mob/living/silicon/robot/body_slot_refusal(datum/om/relation/slot/body/def)
	if(istype(def, /datum/om/relation/slot/body/module))
		return module ? null : "you have no module"
	return ..()

/mob/living/silicon/robot/has_hands_to_hold()
	return FALSE

/// Species slots and body parts. Species gating is the species HUD's slot list
/// (what mob_can_equip() checked); body parts are the part map above.
/mob/living/carbon/human/body_slot_refusal(datum/om/relation/slot/body/def)
	if(def.legacy_slot && species && !(def.legacy_slot in dq_equip_slots_of(src)))
		return "you have nowhere to wear it"
	for(var/part in def.required_parts)
		if(!has_body_part(part))
			return "you have no [parse_zone(part)]"
	if(length(def.any_parts))
		for(var/part in def.any_parts)
			if(has_body_part(part))
				return null
		return "you have no [parse_zone(def.any_parts[1])]"
	return null

/mob/living/carbon/human/has_hands_to_hold()
	return TRUE

/// Whether external part `part` (BP_*) is attached and not a stump.
/mob/living/carbon/human/proc/has_body_part(part)
	var/obj/item/organ/external/E = organs_by_name[part]
	return E && !E.is_stump()

/// Whether this mob has body slot `id` and can use it now (its body part is
/// there, its species has it): the old has_organ_for_slot().
/mob/living/proc/body_slot_usable(id)
	var/datum/ledger/L = dq_ledger(src)
	var/datum/om/relation/slot/body/def = L?.def_by_id(id)
	return istype(def) && !body_slot_refusal(def)

/// What is in body slot `def`.
/mob/living/proc/body_slot_item(datum/om/relation/slot/body/def)
	var/datum/ledger/L = dq_ledger(src)
	var/list/things = L?.slots[def.slot_id]
	return length(things) ? things[1] : null

/// Every item in this mob's body slots with any of `roles` (BODY_SLOT_*), in
/// slot declaration order.
/mob/living/proc/body_slot_items(roles)
	. = list()
	for(var/datum/om/relation/slot/body/def in dq_slot_defs_for(src))
		if(!(def.roles & roles))
			continue
		var/obj/item/I = body_slot_item(def)
		if(I)
			. += I

/// The body plan changed (species change): the slot set is keyed by plan, so
/// the ledger is rebuilt from the new set. Things keep their slot where the
/// new plan has it and fall back to the default slot where it doesn't.
/mob/living/proc/rebuild_slot_ledger()
	var/datum/ledger/old = ledger
	if(!old)
		return
	var/list/placed = list()
	for(var/atom/movable/thing as anything in old.entries)
		placed[thing] = old.entries[thing][LEDGER_E_SLOT]
	qdel(old)
	var/datum/ledger/fresh = dq_ledger(src)
	if(!fresh)
		return
	for(var/atom/movable/thing as anything in placed)
		if(thing.loc == src && fresh.entries[thing] && fresh.def_by_id(placed[thing]))
			fresh.reslot(thing, placed[thing])
	body?.invalidate(BODY_DIRTY_ARMOR | BODY_DIRTY_FACTORS)
