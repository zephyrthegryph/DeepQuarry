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
//   adopt_occupant(other)   the view (with its mind) moves host to host,
//                           e.g. brain organ <-> MMI
// Each logs, and minds move through transfer_mind(). There is no raw key path.

/datum/component/mind_host
	/// The view mob the hosted mind occupies. Created on demand.
	var/mob/living/carbon/brain/occupant
	/// Brain organ whose state decides the occupant's status. Null for
	/// synthetic hosts (posibrain, robot intelligence circuit).
	var/obj/item/organ/internal/brain/tissue
	/// Type of view mob to create.
	var/occupant_type = /mob/living/carbon/brain

/datum/component/mind_host/Initialize(obj/item/organ/internal/brain/tissue)
	if(!isobj(parent))
		return COMPONENT_INCOMPATIBLE
	set_tissue(tissue)

/datum/component/mind_host/Destroy(force)
	// Detach the view before dropping the tissue, so it isn't put through a death on the way out.
	if(occupant)
		var/mob/living/carbon/brain/view = occupant
		occupant = null
		view.host = null
		view.container = null
		if(!QDELETED(view))
			qdel(view)
	set_tissue(null)
	return ..()

/// The brain organ backing the occupant's status.
/datum/component/mind_host/proc/set_tissue(obj/item/organ/internal/brain/new_tissue)
	if(tissue == new_tissue)
		return
	if(tissue)
		UnregisterSignal(tissue, COMSIG_QDELETING)
	tissue = new_tissue
	if(tissue)
		RegisterSignal(tissue, COMSIG_QDELETING, PROC_REF(on_tissue_deleted))
	occupant?.refresh_host_status()

/datum/component/mind_host/proc/on_tissue_deleted(datum/source)
	SIGNAL_HANDLER
	set_tissue(null)

/// The view mob, creating it if needed.
/datum/component/mind_host/proc/ensure_occupant()
	if(!occupant)
		var/atom/movable/holder = parent
		occupant = new occupant_type(holder)
		attach_occupant(occupant)
	return occupant

/datum/component/mind_host/proc/attach_occupant(mob/living/carbon/brain/view)
	occupant = view
	view.host = src
	view.container = parent
	if(view.loc != parent)
		view.forceMove(parent)
	view.refresh_host_status()

/// The mind this host holds, if any.
/datum/component/mind_host/proc/hosted_mind()
	return occupant?.mind

/// A mind comes into this host. With no mind, the view is still made (an
/// empty, waiting host). Returns the view.
/datum/component/mind_host/proc/receive_mind(datum/mind/M, reason = "received")
	ensure_occupant()
	if(M)
		transfer_mind(M, occupant, "[reason] (into [parent])")
	return occupant

/// The hosted mind goes into `dest`. Returns TRUE on success.
/datum/component/mind_host/proc/release_mind(mob/living/dest, reason = "released")
	var/datum/mind/M = hosted_mind()
	if(!M)
		return FALSE
	return transfer_mind(M, dest, "[reason] (from [parent])")

/// Delete the (now empty) view once its mind has left.
/datum/component/mind_host/proc/discard_occupant()
	if(!occupant)
		return
	var/mob/living/carbon/brain/view = occupant
	occupant = null
	view.host = null
	view.container = null
	qdel(view)

/// Move `other`'s view (and the mind in it) into this host. Returns TRUE if a
/// view moved.
/datum/component/mind_host/proc/adopt_occupant(datum/component/mind_host/other, reason = "handed over")
	if(!other?.occupant || occupant)
		return FALSE
	var/mob/living/carbon/brain/view = other.occupant
	other.occupant = null
	log_game("MIND: [view.mind ? "[view.mind.key] ([view.mind.name])" : "empty view [view]"] moved from host [other.parent] to [parent]: [reason]")
	attach_occupant(view)
	return TRUE

/// The mind host of `A`, if it is one.
/proc/get_mind_host(atom/A)
	return A?.GetComponent(/datum/component/mind_host)

/// The view mob a mind host holds (its hosted mind lives there), if any.
/obj/proc/hosted_view()
	var/datum/component/mind_host/host = GetComponent(/datum/component/mind_host)
	return host?.occupant
