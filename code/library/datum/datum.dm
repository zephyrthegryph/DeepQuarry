/**
 * The absolute base class for everything
 *
 * A datum instantiated has no physical world prescence, use an atom if you want something
 * that actually lives in the world
 *
 * Be very mindful about adding variables to this class, they are inherited by every single
 * thing in the entire game, and so you can easily cause memory usage to rise a lot with careless
 * use of variables at this level
 */
/datum
	#ifdef REFERENCE_TRACKING
	/// Remaining references requested by the debug reference walker.
	var/tmp/references_to_clear
	#endif
	/**
	  * Tick count time when this object was destroyed.
	  *
	  * If this is non zero then the object has been garbage collected and is awaiting either
	  * a hard del by the GC subsystme, or to be autocollected (if it has no references)
	  */
	var/tmp/gc_destroyed
	/// The LIFECYCLE_PHASE_* its destroy transaction has reached (0: alive). Read through
	/// LIFECYCLE_DYING() / OWN_GUARD(); written only by destroy_transaction_phases().
	var/tmp/destroy_phase = 0

	/// Open uis owned by this datum
	/// Lazy, since this case is semi rare
	var/tmp/list/open_tguis // FIXME: open_uis

	/// Status traits attached to this datum. associative list of the form: list(trait name (string) = list(source1, source2, source3,...))

	/// Datum level flags
	var/tmp/datum_flags = NONE



	/// List for handling persistent filters.
	var/tmp/list/filter_data

#ifdef REFERENCE_TRACKING
	var/tmp/last_find_references = 0
	var/tmp/find_references_on_destroy = FALSE //set this to true on an item to have it find refs after
	#ifdef REFERENCE_TRACKING_DEBUG
	///Stores info about where refs are found, used for sanity checks and testing
	var/tmp/list/found_refs
	#endif
#endif

	// If we have called dump_harddel_info already. Used to avoid duped calls (since we call it immediately in some cases on failure to process)
	// Create and destroy is weird and I wanna cover my bases
	var/tmp/harddel_deets_dumped = FALSE

/**
 * Called when a href for this datum is clicked
 */
/**
 * The base of the core Destroy() chain: phase 7 of destroy_transaction()
 * (code/datums/lifecycle/transaction.dm). Only qdel() reaches it.
 *
 * Do not override Destroy() in a type: tools/ci/lifecycle_counts_lint.py allows
 * only the core chain (/datum, /atom, /atom/movable, /client, the MC). A type
 * declares its references with relations (links, phase 4), puts domain
 * consequences in on_destroy(), and sets destroy_hint for a different GC hint.
 * Declared links and timers, hooks, tasks and behaviours are already gone
 * by now (phases 4 and 5).
 *
 * This base clears the tag, closes the datum's tgui windows and, under
 * REFERENCE_TRACKING, does the reference-finder bookkeeping.
 *
 * Returns [QDEL_HINT_QUEUE] (or a reference-finding hint under REFERENCE_TRACKING).
 */
// The base of the core chain: tag, tgui and reference tracking.
/datum/proc/Destroy(force = FALSE)
	SHOULD_CALL_PARENT(TRUE)
	SHOULD_NOT_SLEEP(TRUE)
	tag = null

	#ifdef REFERENCE_TRACKING
	#ifdef REFERENCE_TRACKING_DEBUG
	found_refs = null
	#endif
	#endif


	SStgui.close_uis(src)

	#ifdef REFERENCE_TRACKING
	if(find_references_on_destroy)
		return QDEL_HINT_FINDREFERENCE
	if(SSgarbage.find_reference_on_fail_enabled())
		return QDEL_HINT_IFFAIL_FINDREFERENCE
	#endif

	return QDEL_HINT_QUEUE


/// Return text from this proc to provide extra context to hard deletes that happen to it
/// Optional, you should use this for cases where replication is difficult and extra context is required
/// Can be called more then once per object, use harddel_deets_dumped to avoid duplicate calls (I am so sorry)
///images are pretty generic, this should help a bit with tracking harddels related to them
/image/proc/dump_harddel_info()
	if(harddel_deets_dumped)
		return
	harddel_deets_dumped = TRUE
	return "Image icon: [icon] - icon_state: [icon_state] [loc ? "loc: [loc] ([loc.x],[loc.y],[loc.z])" : ""]"

/// Begin coordinated remote viewing, this will call look() when the view begins, and unlook() when it ends.
/proc/start_coordinated_remoteview(datum/coordinator, mob/user, atom/target, list/viewer_managed_list, remote_view_config_path = null)
	user.begin_remote_view(/datum/remote_view/viewer_managed, target, null, remote_view_config_path, coordinator, viewer_managed_list)

/// Called from /datum/remote_view/viewer_managed when the view begins.
/datum/proc/look(mob/user)
	return

/// Called from /datum/remote_view/viewer_managed when the view ends.
/datum/proc/unlook(mob/user)
	return
