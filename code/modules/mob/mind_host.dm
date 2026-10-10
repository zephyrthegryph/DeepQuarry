// Mind hosting: the one interface for anything that holds a mind outside a
// living body. Implemented by the brain organ, the MMI, the posibrain / robot
// intelligence circuit (digital MMIs, which includes the protean core) and,
// through those, cyborg and AI brains.
//
// A host owns the thin view mob (/mob/living/carbon/brain) a client needs
// while the mind is held. The view has no health of its own: its status is
// read from `tissue` (the brain organ whose lesions and state it shows), or it
// simply stays up for synthetic hosts without tissue.
//
// Moving a mind is always one of:
//   receive_mind(mind)      a body's mind comes into this host
//   release_mind(dest)      the hosted mind goes into a body/mob
//   adopt_view(other)       the view (with its mind) moves host to host,
//                           e.g. brain organ <-> MMI
// Each logs, and minds move through transfer_mind(). There is no raw key path.
//
// `view` (not `occupant`): this is a thin display mob, not a containment
// relationship -- it is never linked through a slot, and there is no
// /datum/relation_definition naming it. Renamed off `occupant` (OM relations step 3)
// so it can't be mistaken for one, and so the core-owned-field lint (any
// relation's declared target_ref_field, containment.md) never has a reason to
// look at this file.

/// (Was /datum/mind_host; now a plain datum owned by the hosting item, /obj/item var mind_host.)
/datum/mind_host
	/// The hosting item (brain organ, MMI, posibrain...).
	var/obj/item/owner
	/// The view mob the hosted mind occupies. Created on demand.
	var/mob/living/carbon/brain/view
	/// Brain organ whose state decides the view's status. Null for synthetic
	/// hosts (posibrain, robot intelligence circuit).
	var/obj/item/organ/internal/brain/tissue
	/// Type of view mob to create.
	var/view_type = /mob/living/carbon/brain

CAPABILITIES(/datum/mind_host)
	owns_one(nameof(view), /mob/living/carbon/brain)

/datum/mind_host/New(obj/item/new_owner, obj/item/organ/internal/brain/tissue)
	..()
	if(!isitem(new_owner))
		log_world("[type] was created for a non-item host ([new_owner]); it hosts nothing.")
		return
	rel_set(src, nameof(owner), new_owner)
	set_tissue(tissue)

/// Makes `holder` a mind host (was AddComponent(/datum/mind_host, tissue)).
/obj/item/proc/make_mind_host(obj/item/organ/internal/brain/tissue) as /datum/mind_host
	if(mind_host)
		rel_clear(src, nameof(mind_host))
	rel_set(src, nameof(mind_host), new /datum/mind_host(src, tissue))
	return mind_host

/// Owned: this item's mind host, if it holds minds.
/obj/item/var/datum/mind_host/mind_host
/// Pinned in the saved state (code/datums/state/codecs.dm, /datum/state_codec/pinned).


/// Phase 1: the view (owned) is detached before the tissue drops, so it isn't put through a
/// death on the way out.
/datum/mind_host/lifecycle_unbind()
	if(view)
		var/mob/living/carbon/brain/old_view = view
		rel_take(src, nameof(view))
		rel_clear(old_view, nameof(old_view.host))
		rel_clear(old_view, nameof(old_view.container))
		if(!QDELETED(old_view))
			spent(old_view)
	set_tissue(null)
	rel_clear(src, nameof(owner))


/// The brain organ backing the view's status.
/datum/mind_host/proc/set_tissue(obj/item/organ/internal/brain/new_tissue)
	// Compare the view var, not tissue(): a tissue being deleted already reads null through
	// tissue() (QDELETED), so on_tissue_deleted()'s set_tissue(null) would look like a no-op
	// and the view would never learn its brain is gone.
	if(tissue == new_tissue)
		return
	if(tissue)
		unobserve(tissue, /datum/notice/qdeleting, src)
	rel_set(src, nameof(tissue), QDELETED(new_tissue) ? null : new_tissue)
	if(tissue)
		observe(tissue, /datum/notice/qdeleting, src, then(PROC_REF(on_tissue_deleted)))
	view?.refresh_host_status()

/datum/mind_host/proc/on_tissue_deleted(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	set_tissue(null)

/// The view mob, creating it if needed.
/datum/mind_host/proc/ensure_view()
	if(!view)
		var/atom/movable/holder = owner
		var/mob/living/carbon/brain/new_view = new view_type(holder)
		attach_view(new_view)
	return view

/datum/mind_host/proc/attach_view(mob/living/carbon/brain/new_view)
	rel_set(src, nameof(view), new_view)
	rel_set(new_view, nameof(new_view.host), src)
	rel_set(new_view, nameof(new_view.container), owner) // the item holding the view (it owns us, not the view)
	if(new_view.loc != owner)
		new_view.forceMove(owner)
	new_view.refresh_host_status()

/// The mind this host holds, if any.
/datum/mind_host/proc/hosted_mind()
	return view?.mind

/// A mind comes into this host. With no mind, the view is still made (an
/// empty, waiting host). Returns the view.
/datum/mind_host/proc/receive_mind(datum/mind/M, reason = "received")
	ensure_view()
	if(M)
		transfer_mind(M, view, "[reason] (into [owner])")
	return view

/// The hosted mind goes into `dest`. Returns TRUE on success.
/datum/mind_host/proc/release_mind(mob/living/dest, reason = "released")
	var/datum/mind/M = hosted_mind()
	if(!M)
		return FALSE
	return transfer_mind(M, dest, "[reason] (from [owner])")

/// Delete the (now empty) view once its mind has left.
/datum/mind_host/proc/discard_view()
	if(!view)
		return
	var/mob/living/carbon/brain/old_view = view
	rel_take(src, nameof(view))
	rel_clear(old_view, nameof(old_view.host))
	rel_clear(old_view, nameof(old_view.container))
	spent(old_view)

/// Move `other`'s view (and the mind in it) into this host. Returns TRUE if a
/// view moved.
/datum/mind_host/proc/adopt_view(datum/mind_host/other, reason = "handed over")
	if(!other?.view || view)
		return FALSE
	var/mob/living/carbon/brain/moved_view = other.view
	rel_take(other, nameof(other.view))
	log_game("MIND: [moved_view.mind ? "[moved_view.mind.key] ([moved_view.mind.name])" : "empty view [moved_view]"] moved from host [other.owner] to [owner]: [reason]")
	attach_view(moved_view)
	return TRUE

/// The mind host of `A`, if it is one.
/proc/get_mind_host(atom/A)
	if(!isitem(A))
		return null
	var/obj/item/I = A
	return I.mind_host

/// The view mob a mind host holds (its hosted mind lives there), if any.
/obj/proc/hosted_view()
	RETURN_TYPE(/mob/living/carbon/brain)
	var/datum/mind_host/host = get_mind_host(src)
	return host?.view

/// The brain organ backing the view (a relation view).
/datum/mind_host/proc/tissue() as /obj/item/organ/internal/brain
	return tissue
