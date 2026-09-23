// Body part slots (doc/medical_frameworks.md §2.2-2.3, slice O2).
//
// The limb tree is physically nested and the ledger is its source of truth:
//
//   mob (humanoid)   SLOT_ID_PART_ROOT   -> torso
//   limb             SLOT_ID_PART_CHILD  -> child limbs (keyed by organ_tag)
//   limb             SLOT_ID_PART_ORGANS -> internal organs (keyed by organ_tag)
//   limb             implants / embedded / cavity / splint / tourniquet
//
// Moves into and out of the three tree slots are what attach and detach a
// part (attach.dm, through the J6 on_slotted()/on_unslotted() hooks). The
// foreign-object slots are declared here so a limb's slot set is complete;
// O3b/O3c move implants, shrapnel, cavity items, splints and tourniquets into
// them.
//
// Destroy policies: a deleted limb deletes its tree slots children first
// (the ledger resolves nested holders before their parents); shrapnel and
// tourniquets fall out. See attach.dm for where O4's destroy transaction
// plugs in.

/datum/slot_def/part
	name = "body part"
	exposure = SLOT_EXPOSURE_INTERNAL
	capacity_model = SLOT_CAPACITY_NONE
	drop_policy = SLOT_DROP_DELETE
	// The body model decides what reaches a part (injure()); no path does.
	heat_transmission = 0
	radiation_transmission = 0
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

/// A humanoid mob's root part: the one limb with no parent_organ.
/datum/slot_def/part/root
	id = SLOT_ID_PART_ROOT
	name = "body"
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1

/datum/slot_def/part/root/refusal(atom/holder, atom/movable/thing, mob/actor)
	var/obj/item/organ/external/E = thing
	if(!istype(E))
		return "that isn't a body part"
	if(E.parent_organ)
		return "[E] has to join onto a [parse_zone(E.parent_organ)]"
	return ..()

/// A limb's child limbs: external organs whose parent_organ is this limb's tag.
/datum/slot_def/part/child
	id = SLOT_ID_PART_CHILD
	name = "limbs"
	keyed = TRUE

/datum/slot_def/part/child/refusal(atom/holder, atom/movable/thing, mob/actor)
	var/obj/item/organ/external/E = thing
	var/obj/item/organ/external/parent = holder
	if(!istype(E) || !istype(parent))
		return "that isn't a limb"
	if(E.parent_organ != parent.organ_tag)
		return "[E] doesn't join onto \the [parent]"
	return ..()

/// A limb's internal organs. Any internal organ may sit in any limb (surgery
/// and horror modifiers relocate organs), keyed by organ_tag.
/datum/slot_def/part/organs
	id = SLOT_ID_PART_ORGANS
	name = "organs"
	keyed = TRUE

/datum/slot_def/part/organs/refusal(atom/holder, atom/movable/thing, mob/actor)
	if(!istype(thing, /obj/item/organ) || istype(thing, /obj/item/organ/external))
		return "that isn't an organ"
	return ..()

/// Implants, NIFs and parasites.
/datum/slot_def/part/implants
	id = SLOT_ID_PART_IMPLANTS
	name = "implants"

/// Shrapnel and thrown weapons: they fall out when the limb goes.
/datum/slot_def/part/embedded
	id = SLOT_ID_PART_EMBEDDED
	name = "embedded objects"
	drop_policy = SLOT_DROP_SPILL

/// Surgically placed items. The default slot: a legacy forceMove of a
/// non-part into a limb lands here, never among its parts. Surgery enforces
/// the cavity size (surgical_cavity_capacity()) until O3c gives the ledger a
/// custom capacity model.
/datum/slot_def/part/cavity
	id = SLOT_ID_PART_CAVITY
	name = "cavity"
	is_default = TRUE

/datum/slot_def/part/splint
	id = SLOT_ID_PART_SPLINT
	name = "splint"
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1

/datum/slot_def/part/tourniquet
	id = SLOT_ID_PART_TOURNIQUET
	name = "tourniquet"
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	drop_policy = SLOT_DROP_SPILL

/// Every limb holds child limbs, organs and foreign objects. Declaration
/// order is destroy order: parts before what is merely stuck in them.
/obj/item/organ/external/slot_def_types()
	var/static/list/types = list(
		/datum/slot_def/part/child,
		/datum/slot_def/part/organs,
		/datum/slot_def/part/implants,
		/datum/slot_def/part/cavity,
		/datum/slot_def/part/splint,
		/datum/slot_def/part/embedded,
		/datum/slot_def/part/tourniquet,
	)
	return types
