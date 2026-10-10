// Body part slots (doc/medical_frameworks.md §2.2-2.3, slice O2; as relation
// slots, doc/rewrite/object_model_core.md §7 and containment.md §3).
//
// The limb tree is physically nested and the ledger is its source of truth:
//
//   humanoid body plan  SLOT_ID_PART_ROOT   -> torso
//   limb                SLOT_ID_PART_CHILD  -> child limbs (keyed by organ_tag)
//   limb                SLOT_ID_PART_ORGANS -> internal organs (keyed by organ_tag)
//   limb                ORGAN_SLOT_IMPLANTS (implant_site, organ_external.dm),
//                       embedded / cavity / splint / tourniquet
//
// Each slot is a /datum/relation_definition/slot decl with a declared `holder`, so a
// part in a slot is also linked to its holder by that relation. Moves into and
// out of the three tree slots are what attach and detach a part (attach.dm,
// through the ledger's J6 on_slotted()/on_unslotted() commit hooks on the
// organ). Implants use the integration branch's implant_site slot; O2's own
// SLOT_ID_PART_IMPLANTS declaration is not carried over (one slot per concern).
//
// Destroy policies: a deleted limb deletes its tree slots' children first
// (the ledger resolves nested holders before their parents); shrapnel and
// tourniquets fall out.

/datum/relation_definition/slot/part
	abstract_type = /datum/relation_definition/slot/part
	holder = /obj/item/organ/external
	name = "body part"
	exposure = SLOT_EXPOSURE_INTERNAL
	capacity_model = SLOT_CAPACITY_NONE
	drop_policy = SLOT_DROP_DELETE
	// The body model decides what reaches a part (injure()); no path does.
	heat_transmission = 0
	radiation_transmission = 0
	damage_transmission = list(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

/// A humanoid's root part: the one limb with no parent_organ. Declared on the
/// humanoid plan after its equipment and before its interior, which is the
/// order a deleted mob releases them in.
/datum/relation_definition/slot/part/root
	holder = /datum/body/humanoid
	slot_id = SLOT_ID_PART_ROOT
	name = "body"
	order = 19.5
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1

/datum/relation_definition/slot/part/root/refusal(atom/holder, atom/movable/thing, mob/actor)
	var/obj/item/organ/external/E = thing
	if(!istype(E))
		return "that isn't a body part"
	if(E.parent_organ)
		return "[E] has to join onto a [parse_zone(E.parent_organ)]"
	return ..()

/// A limb's child limbs: external organs whose parent_organ is this limb's tag.
/datum/relation_definition/slot/part/child
	slot_id = SLOT_ID_PART_CHILD
	name = "limbs"
	order = 1
	keyed = TRUE

/datum/relation_definition/slot/part/child/refusal(atom/holder, atom/movable/thing, mob/actor)
	var/obj/item/organ/external/E = thing
	var/obj/item/organ/external/parent = holder
	if(!istype(E) || !istype(parent))
		return "that isn't a limb"
	if(E.parent_organ != parent.organ_tag)
		return "[E] doesn't join onto \the [parent]"
	return ..()

/// A limb's internal organs. Any internal organ may sit in any limb (surgery
/// and horror modifiers relocate organs), keyed by organ_tag.
/datum/relation_definition/slot/part/organs
	slot_id = SLOT_ID_PART_ORGANS
	name = "organs"
	order = 2
	keyed = TRUE

/datum/relation_definition/slot/part/organs/refusal(atom/holder, atom/movable/thing, mob/actor)
	if(!istype(thing, /obj/item/organ) || istype(thing, /obj/item/organ/external))
		return "that isn't an organ"
	return ..()

/// Surgically placed items. The default slot: a legacy forceMove of a
/// non-part into a limb lands here, never among its parts. Surgery enforces
/// the cavity size (surgical_cavity_capacity()) until the ledger has a
/// custom capacity model for it.
/datum/relation_definition/slot/part/cavity
	slot_id = SLOT_ID_PART_CAVITY
	name = "cavity"
	order = 4
	is_default = TRUE

/datum/relation_definition/slot/part/splint
	slot_id = SLOT_ID_PART_SPLINT
	name = "splint"
	order = 5
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1

/// Shrapnel and thrown weapons: they fall out when the limb goes.
/datum/relation_definition/slot/part/embedded
	slot_id = SLOT_ID_PART_EMBEDDED
	name = "embedded objects"
	order = 6
	drop_policy = SLOT_DROP_SPILL

/datum/relation_definition/slot/part/tourniquet
	slot_id = SLOT_ID_PART_TOURNIQUET
	name = "tourniquet"
	order = 7
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1
	drop_policy = SLOT_DROP_SPILL
