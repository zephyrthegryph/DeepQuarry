// Part attach and detach (doc/medical_frameworks.md §2.2-2.3, slice O2).
//
// A part is attached when it sits in a tree slot (part_slots.dm) of a tree
// whose root is in a mob's SLOT_ID_PART_ROOT. A mob with no part tree (simple
// mobs, larvae, butchery animals) keeps its organs loose in its interior slot,
// and they belong to it there. Nothing else attaches a part: the ledger's J6
// commit hooks call on_attached()/on_detached() after every move into or out
// of those slots, so every way a part moves (move_into, slot_remove, a legacy
// forceMove, qdel) runs the same bookkeeping.
//
// What the hooks derive, and who else may write it:
//   organ.owner                      only adopt_part()/release_part()
//   mob.organs, organs_by_name       only adopt_part()/release_part(): derived
//                                    caches of the ledger (external parts only)
//   limb.children, limb.parent       only link_to_holder()/unlink_from_holder():
//                                    structural caches of the tree, kept
//                                    whether or not the tree has an owner
// Internal organs have no cache at all (O-slots): the limb's keyed
// SLOT_ID_PART_ORGANS slot is the record, read by organ_in() (queries.dm).
// verify_body_tree() (verify.dm) recomputes all of it from the ledger.
//
// Destruction (O4 plugs in here). A deleted part leaves its holder's slot
// through the same on_unslotted() hook, and the ledger resolves nested holders
// children first, so a tree is released leaves first. When the holder itself
// is being destroyed (dq_part_holder_destroying()), the release clears the
// derived state (owner, caches, afflictions moved to the part) but skips every
// re-derivation: no invalidate (so no CHANGE_MOB_HEALTH), no verbs, no death check. The
// topmost detach, from a holder that survives, does that once for the whole
// subtree. O4 replaces the stub below with the destroy transaction's flag
// (doc/rewrite/lifecycle.md §2-3) and moves the remaining organ Destroy()
// work (organ.dm, organ_external.dm) onto the slot policies.

/// Logs every adopt and release. Off by default; turn it on with View Variables.
GLOBAL_VAR_INIT(dq_part_trace, FALSE)
/// The part place_into() is moving between two places in the same body, for
/// the length of that one move, or null. Its detach half is then a reparent.
GLOBAL_DATUM(dq_part_reparenting, /obj/item/organ)

/obj/item/organ
	has_slot_hooks = TRUE

/obj/item/organ/slot_key()
	return organ_tag

/// Whether `holder` is being destroyed while its slots are resolved. A stub
/// until the destroy transaction lands its flag (LEDGER_MOVE_DESTROYING or
/// holder_destroying(), doc/rewrite/lifecycle.md): qdel() marks the holder
/// QDELETED before its contents resolve, which is the same answer today.
/proc/dq_part_holder_destroying(atom/holder)
	return QDELETED(holder)

/// Whether an organ in `slot_id` on `holder` belongs to whatever `holder`'s
/// tree hangs from.
/proc/dq_part_attaching_slot(atom/holder, slot_id)
	if(IS_PART_TREE_SLOT(slot_id))
		return TRUE
	return slot_id == SLOT_ID_BODY && isliving(holder) && !holder.ledger?.def_by_id(SLOT_ID_PART_ROOT)

/obj/item/organ/on_slotted(atom/holder, slot_id)
	if(slot_id == SLOT_ID_PART_CHILD || slot_id == SLOT_ID_PART_ORGANS)
		link_to_holder(holder)
	if(dq_part_attaching_slot(holder, slot_id))
		on_attached(holder, slot_id)

/obj/item/organ/on_unslotted(atom/holder, slot_id)
	if(dq_part_attaching_slot(holder, slot_id))
		on_detached(holder, slot_id)
	if(slot_id == SLOT_ID_PART_CHILD || slot_id == SLOT_ID_PART_ORGANS)
		unlink_from_holder(holder)

/// This part (and its subtree) now sits in a tree slot of `holder`. If the
/// tree hangs from a mob, the mob's body adopts the subtree.
/obj/item/organ/proc/on_attached(atom/holder, slot_id)
	var/mob/living/M = resolve_owner()
	if(!M)
		return // a tree being assembled outside a body: nothing owns it yet
	if(!M.body)
		log_runtime("PARTS: [src] ([type]) joined [M] ([M.type]), which has no body; left unowned")
		return
	M.body.adopt_subtree(src)

/// This part (and its subtree) left a tree slot of `holder`.
/obj/item/organ/proc/on_detached(atom/holder, slot_id)
	var/mob/living/M = owner
	if(!M)
		return
	// A move within one body can commit the new slot before the old one lets go:
	// the part is already adopted again, so this late detach must not undo it.
	if(!QDELETED(src) && resolve_owner() == M)
		return
	if(!M.body)
		// The body is gone (the mob is mid-deletion): clear what we derived.
		for(var/obj/item/organ/part as anything in dq_part_subtree(src))
			dq_part_uncache(M, part)
			rel_clear(part, nameof(part.owner))
		return
	M.body.release_subtree(src, dq_part_holder_destroying(holder) || QDELETED(M))

/// The mob a part put in `slot_id` on `holder` would belong to, or null.
/proc/dq_part_destination_owner(atom/holder, slot_id)
	if(isliving(holder))
		return dq_part_attaching_slot(holder, slot_id) ? holder : null
	var/obj/item/organ/external/E = holder
	if(!istype(E) || !IS_PART_TREE_SLOT(slot_id))
		return null
	return E.owner

/// The mob whose body this part belongs to now: walks up the part tree
/// through the ledger, or null if the tree doesn't hang from a mob.
/obj/item/organ/proc/resolve_owner()
	var/atom/movable/part = src
	// A limb tree is a few levels deep; the bound only stops a corrupt loop.
	for(var/depth in 1 to 16)
		var/atom/holder = part.loc
		var/list/entry = holder?.ledger?.entries[part]
		if(!entry)
			return null
		var/slot_id = entry[LEDGER_E_SLOT]
		if(isliving(holder))
			return dq_part_attaching_slot(holder, slot_id) ? holder : null
		if((slot_id != SLOT_ID_PART_CHILD && slot_id != SLOT_ID_PART_ORGANS) || !istype(holder, /obj/item/organ/external))
			return null
		part = holder
	log_runtime("PARTS: [src] ([type]) sits in a part tree deeper than 16 levels")
	return null

// ---- Structural caches ----

/// Joined `holder`'s child or organ slot: record the edge in the tree caches.
/// An internal organ's edge is its ledger entry alone.
/obj/item/organ/proc/link_to_holder(atom/holder)
	return

/obj/item/organ/external/link_to_holder(atom/holder)
	var/obj/item/organ/external/parent_limb = holder
	if(!istype(parent_limb))
		return
	rel_set(src, nameof(parent), parent_limb)
	rel_add(parent_limb, nameof(parent_limb.children), src)

/// Left `holder`'s child or organ slot.
/obj/item/organ/proc/unlink_from_holder(atom/holder)
	return

/obj/item/organ/external/unlink_from_holder(atom/holder)
	var/obj/item/organ/external/parent_limb = holder
	if(istype(parent_limb))
		rel_remove(parent_limb, nameof(parent_limb.children), src)
	if(parent == holder)
		rel_clear(src, nameof(parent))

/// Changes this part's organ_tag, which is its key in its slot and in its
/// owner's caches.
/obj/item/organ/proc/set_organ_tag(new_tag)
	var/mob/living/M = owner
	if(M)
		dq_part_uncache(M, src)
	organ_tag = new_tag
	ledger_rekey()
	if(M)
		dq_part_cache(M, src)

// ---- Owner caches ----

/// Adds `part` to `M`'s organ caches. The caches are made on first use and
/// never nulled again: human code indexes them without a null check.
/proc/dq_part_cache(mob/living/M, obj/item/organ/part)
	if(istype(part, /obj/item/organ/external))
		if(!M.organs_by_name)
			M.organs_by_name = list()
		rel_add(M, nameof(M.organs), part)
		M.organs_by_name[part.organ_tag] = part // ALLOW(ownership): tag -> part lookup derived from the `organs` relation list; kept in step only here and in dq_part_uncache()
	// Internal organs: nothing to cache, the limb's keyed organ slot is the record.

/// Removes `part` from `M`'s organ caches. A key another part now holds stays.
/proc/dq_part_uncache(mob/living/M, obj/item/organ/part)
	if(istype(part, /obj/item/organ/external))
		rel_remove(M, nameof(M.organs), part)
		if(M.organs_by_name?[part.organ_tag] == part)
			M.organs_by_name -= part.organ_tag

/// `part` and every part below it, parents before children, read from the
/// ledger's tree slots.
/proc/dq_part_subtree(obj/item/organ/root)
	var/list/tree = list(root)
	var/i = 0
	while(i < length(tree))
		i++
		var/obj/item/organ/external/E = tree[i]
		if(!istype(E))
			continue
		var/datum/ledger/L = dq_ledger_peek(E)
		if(!L)
			continue
		var/list/limbs = L.slots[SLOT_ID_PART_CHILD]
		if(length(limbs))
			tree += limbs
		var/list/inner = L.slots[SLOT_ID_PART_ORGANS]
		if(length(inner))
			tree += inner
	return tree

// ---- The body side ----

/// `root` and its subtree joined this body. Parents first.
/datum/body/proc/adopt_subtree(obj/item/organ/root)
	var/list/tree = dq_part_subtree(root)
	var/limbs = FALSE
	for(var/obj/item/organ/part as anything in tree)
		adopt_part(part)
		if(istype(part, /obj/item/organ/external))
			limbs = TRUE
	invalidate(BODY_DIRTY_ORGANS | BODY_DIRTY_VITALS | BODY_DIRTY_FACTORS | BODY_DIRTY_ARMOR)
	if(limbs)
		owner.hands_refresh() // the hands() provider follows the limbs
	if(limbs && ishuman(owner))
		var/mob/living/carbon/human/H = owner
		H.refresh_modular_limb_verbs()
	if(GLOB.dq_part_trace)
		log_runtime("PARTS: [key_name(owner)] adopted [root] ([root.type]) with [length(tree) - 1] part(s) below it")

/// One part joins: owner, caches, afflictions it carried, its own reaction.
/datum/body/proc/adopt_part(obj/item/organ/part)
	if(part.owner && part.owner != owner)
		// A move always detaches first, so this is a missed detach.
		log_runtime("PARTS: [part] ([part.type]) joined [key_name(owner)] still owned by [key_name(part.owner)]")
		dq_part_uncache(part.owner, part)
	rel_set(part, nameof(part.owner), owner)
	dq_part_cache(owner, part)
	attach_part(part)
	part.joined_body(owner)
	PUBLISH_LEGACY(owner, /datum/notice/body_part_attached, part)

/// `root` and its subtree left this body. Children first. `destroying`: the
/// holder is being destroyed, so only the derived state is cleared (see the
/// header).
/datum/body/proc/release_subtree(obj/item/organ/root, destroying = FALSE)
	// Moving within this body: the attach half re-adopts it at once, so this
	// half neither reacts (left_body) nor counts a loss.
	var/reparent = (root == GLOB.dq_part_reparenting)
	var/list/tree = dq_part_subtree(root)
	var/list/vital_lost
	for(var/i in length(tree) to 1 step -1)
		var/obj/item/organ/part = tree[i]
		if(part.owner != owner)
			continue
		// A deleted part doesn't kill on its way out: the body's own evaluation
		// notices a missing brain, as it always has.
		if(part.vital && !QDELETED(part) && !reparent)
			LAZYADD(vital_lost, part)
		release_part(part, destroying || reparent)
	if(GLOB.dq_part_trace)
		log_runtime("PARTS: [key_name(owner)] released [root] ([root.type]) with [length(tree) - 1] part(s) below it[destroying ? " (holder destroying)" : ""][reparent ? " (reparent)" : ""]")
	if(destroying || reparent)
		return
	invalidate(BODY_DIRTY_ORGANS | BODY_DIRTY_VITALS | BODY_DIRTY_FACTORS | BODY_DIRTY_ARMOR)
	owner.hands_refresh() // the hands() provider follows the limbs
	if(ishuman(owner))
		var/mob/living/carbon/human/H = owner
		H.refresh_modular_limb_verbs()
	// A deleted part (a species change rebuilding the tree, a gibbed hand) is
	// judged by the body's next evaluation, not on the spot mid-rebuild.
	if(QDELETED(root))
		return
	on_status_changed()
	// Losing a vital part kills (organ.dm's old removed()). After all the
	// bookkeeping, so death() sees a consistent body.
	if(length(vital_lost) && !owner.is_dead())
		var/obj/item/organ/first = vital_lost[1]
		log_game("PARTS: [key_name(owner)] lost vital part [first] ([first.type]); dying")
		if(ishuman(owner))
			var/mob/living/carbon/human/H = owner
			H.can_defib = FALSE
		owner.death()

/// One part leaves: afflictions travel with it, caches, its own reaction
/// (after the caches, so shared organ verbs are counted without it), owner.
/// `quiet`: the holder is being destroyed, or this is a reparent; the part
/// doesn't react.
/datum/body/proc/release_part(obj/item/organ/part, quiet)
	detach_part(part)
	dq_part_uncache(owner, part)
	if(!quiet && !QDELETED(part))
		part.left_body(owner)
	rel_clear(part, nameof(part.owner))
	part.recalc_integrity()
	PUBLISH_LEGACY(owner, /datum/notice/body_part_detached, part)

// ---- Per-type reactions ----

/// A part out of a body that hasn't died ticks on its own (decay, loose afflictions) every LOOSE_ORGAN_STEP while it holds
/// this; attached parts are ticked by the body's organ clock. The organ holds it itself (loose_refresh()) when it leaves a body,
/// and drops it when it joins one, dies or is ruined.
STAT(/obj/item/organ, ticks_loose, ANY)

/// How often a loose organ ticks (one cycle's work per tick, as the old slow cadence ran it).
#define LOOSE_ORGAN_STEP (2 SECONDS)

/// The loose-organ tick's entries, for the organ's CAPABILITIES block.
/proc/loose_organ_clock()
	return every(LOOSE_ORGAN_STEP, then(TYPE_PROC_REF(/obj/item/organ, loose_tick)), when = STAT_TICKS_LOOSE)

/obj/item/organ/proc/loose_tick(datum/act/timer/A)
	organ_tick(1)
	loose_refresh()

/// Ticking loose: it came out of a body, has not joined another, and is not dead (a dead prosthetic has no ORGAN_DEAD flag: it is
/// dead at max damage). An organ that never was in a body (a spare in storage) does not tick.
/obj/item/organ/proc/organ_ticks_loose()
	return ticks_loose && loose_alive()

/obj/item/organ/proc/loose_alive()
	if(owner || (status & ORGAN_DEAD))
		return FALSE
	return !(is_robotic() && damage >= max_damage)

/// It is coming out of a body (its owner is still set): tick while it lasts.
/obj/item/organ/proc/loose_start()
	if(QDELETED(src) || (status & ORGAN_DEAD) || (is_robotic() && damage >= max_damage))
		return
	hold(src, STAT_TICKS_LOOSE, null, src)

/// Stop ticking once it joined a body, died or was ruined.
/obj/item/organ/proc/loose_refresh()
	if(!QDELETED(src) && ticks_loose && !loose_alive())
		release(src, STAT_TICKS_LOOSE, src)

/// This part just joined `M`'s body. Runs inside the move: must not sleep,
/// move or delete anything.
/obj/item/organ/proc/joined_body(mob/living/M)
	loose_refresh()
	handle_organ_mod_special()

/obj/item/organ/external/joined_body(mob/living/M)
	..()
	// The limb is back: the stump wound on its parent closes.
	for(var/datum/affliction/wound/lost_limb/W in parent?.get_wounds())
		parent.remove_wound(W)
		parent.update_damages()
		break

/// This part is leaving `M`'s body: out of its caches, still owned. Same
/// constraints as joined_body(). Not called while the holder or the part is
/// being destroyed.
/obj/item/organ/proc/left_body(mob/living/M)
	handle_organ_mod_special(TRUE)
	loose_start()
	rejecting = null
	// Keep a blood sample, for transplant matching and forensics.
	var/mob/living/carbon/human/C = M
	if(!istype(C) || !C.vessel)
		return
	var/datum/reagent/blood/organ_blood = reagents ? locate_in_list(reagents.reagent_list, /datum/reagent/blood) : null
	if(!organ_blood || !organ_blood.data["blood_DNA"])
		C.vessel.trans_to(src, 5, 1, 1)

/obj/item/organ/external/left_body(mob/living/M)
	..()
	set_status(status | ORGAN_CUT_AWAY) // checked by the reattachment surgery
