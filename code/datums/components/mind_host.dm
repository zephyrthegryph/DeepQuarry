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
// /datum/om/relation naming it. Renamed off `occupant` (OM relations step 3)
// so it can't be mistaken for one, and so the core-owned-field lint (any
// relation's declared target_ref_field, containment.md) never has a reason to
// look at this file.

/datum/component/mind_host
	/// The view mob the hosted mind occupies. Created on demand.
	var/mob/living/carbon/brain/view
	/// Brain organ whose state decides the view's status. Null for synthetic
	/// hosts (posibrain, robot intelligence circuit).
	var/obj/item/organ/internal/brain/tissue
	/// Type of view mob to create.
	var/view_type = /mob/living/carbon/brain

/datum/component/mind_host/Initialize(obj/item/organ/internal/brain/tissue)
	if(!isobj(parent))
		return COMPONENT_INCOMPATIBLE
	set_tissue(tissue)

/datum/component/mind_host/Destroy(force)
	// Detach the view before dropping the tissue, so it isn't put through a death on the way out.
	if(view)
		var/mob/living/carbon/brain/old_view = view
		view = null
		old_view.host = null
		old_view.container = null
		if(!QDELETED(old_view))
			qdel(old_view)
	set_tissue(null)
	return ..()

/// The brain organ backing the view's status.
/datum/component/mind_host/proc/set_tissue(obj/item/organ/internal/brain/new_tissue)
	if(tissue == new_tissue)
		return
	if(tissue)
		UnregisterSignal(tissue, COMSIG_QDELETING)
	tissue = new_tissue
	if(tissue)
		RegisterSignal(tissue, COMSIG_QDELETING, PROC_REF(on_tissue_deleted))
	view?.refresh_host_status()

/datum/component/mind_host/proc/on_tissue_deleted(datum/source)
	SIGNAL_HANDLER
	set_tissue(null)

/// The view mob, creating it if needed.
/datum/component/mind_host/proc/ensure_view()
	if(!view)
		var/atom/movable/holder = parent
		var/mob/living/carbon/brain/new_view = new view_type(holder)
		attach_view(new_view)
	return view

/datum/component/mind_host/proc/attach_view(mob/living/carbon/brain/new_view)
	view = new_view
	new_view.host = src
	new_view.container = parent
	if(new_view.loc != parent)
		new_view.forceMove(parent)
	new_view.refresh_host_status()

/// The mind this host holds, if any.
/datum/component/mind_host/proc/hosted_mind()
	return view?.mind

/// A mind comes into this host. With no mind, the view is still made (an
/// empty, waiting host). Returns the view.
/datum/component/mind_host/proc/receive_mind(datum/mind/M, reason = "received")
	ensure_view()
	if(M)
		transfer_mind(M, view, "[reason] (into [parent])")
	return view

/// The hosted mind goes into `dest`. Returns TRUE on success.
/datum/component/mind_host/proc/release_mind(mob/living/dest, reason = "released")
	var/datum/mind/M = hosted_mind()
	if(!M)
		return FALSE
	return transfer_mind(M, dest, "[reason] (from [parent])")

/// Delete the (now empty) view once its mind has left.
/datum/component/mind_host/proc/discard_view()
	if(!view)
		return
	var/mob/living/carbon/brain/old_view = view
	view = null
	old_view.host = null
	old_view.container = null
	qdel(old_view)

/// Move `other`'s view (and the mind in it) into this host. Returns TRUE if a
/// view moved.
/datum/component/mind_host/proc/adopt_view(datum/component/mind_host/other, reason = "handed over")
	if(!other?.view || view)
		return FALSE
	var/mob/living/carbon/brain/moved_view = other.view
	other.view = null
	log_game("MIND: [moved_view.mind ? "[moved_view.mind.key] ([moved_view.mind.name])" : "empty view [moved_view]"] moved from host [other.parent] to [parent]: [reason]")
	attach_view(moved_view)
	return TRUE

/// The mind host of `A`, if it is one.
/proc/get_mind_host(atom/A)
	return A?.GetComponent(/datum/component/mind_host)

/// The view mob a mind host holds (its hosted mind lives there), if any.
/obj/proc/hosted_view()
	var/datum/component/mind_host/host = GetComponent(/datum/component/mind_host)
	return host?.view
