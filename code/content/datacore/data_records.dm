//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:31

/datum/data
	var/name = "data"
	var/size = 1.0

/datum/data/function
	name = "function"
	size = 2.0

/datum/data/function/data_control
	name = "data control"

/datum/data/function/id_changer
	name = "id changer"

/datum/data/record
	name = "record"
	size = 5.0
	var/list/fields = list(  ) // ALLOW(instance_list): d: every record has fields
	/// Immutable disposition audit entries. This belongs to the records system;
	/// contracts are only one consumer of the same authoritative history.
	var/list/disposition_history
	/// "[dir]" -> the portrait key whose picture is still rendering for this record's photo in that direction (see request_photos()).
	var/list/photos_waiting

/// The record's two photos (front: SOUTH, side: WEST) are those of `M` as it looks now. They come from the shared portrait cache
/// (code/content/appearance/portrait_cache.dm), rendered off the tick: drawing the compound icon of a dressed human on the spot cost about
/// 300 ms of every join (playtest 2026-11-09, LATEJOIN_REGISTER manifest record 325 ms). The fields hold the no-image picture until each lands.
/datum/data/record/proc/request_photos(mob/M, only_dir = null)
	if(QDELETED(M))
		return
	for(var/dir in (isnull(only_dir) ? list(SOUTH, WEST) : list(only_dir)))
		var/datum/portrait/P = portrait_request(M, dir, src, PROC_REF(photo_landed))
		if(P)
			apply_photo(dir, P)
		else
			LAZYSET(photos_waiting, "[dir]", portrait_key_of(M, dir))

/// A rendering portrait landed: it is the photo of every direction that was waiting on its key.
/datum/data/record/proc/photo_landed(datum/portrait/P)
	for(var/dir_text in photos_waiting?.Copy())
		if(photos_waiting[dir_text] == P.key)
			LAZYREMOVE(photos_waiting, dir_text)
			apply_photo(text2num(dir_text), P)

/datum/data/record/proc/apply_photo(dir, datum/portrait/P)
	if(!P?.b64)
		return
	var/shown = "'data:image/png;base64,[P.b64]'"
	if(dir == WEST)
		set_fields_at("photo_side", icon(P.picture)) // a copy: the cached picture is shared
		set_fields_at("photo-west", shown)
	else
		set_fields_at("photo_front", icon(P.picture))
		set_fields_at("photo-south", shown)

// Mostly used for data_core records, but unfortuantely used some other places too.  But mostly here, so lets make a good effort.
// TODO - Some machines/computers might be holding references to us.  Lets look into that, but at least for now lets make sure that the manifest is cleaned up.
// Locked records refuse deletion unless forced.
/datum/data/record/lifecycle_keep(force)
	if(force || !(src in GLOB.data_core.locked))
		return FALSE
	stack_trace("Someone tried to qdel a record that was in GLOB.data_core.locked [log_info_line(src)]")
	return TRUE

// Records leave the data core by ownership: GLOB.data_core owns its general/medical/security/locked
// lists, and a dying record leaves its owner's var in phase 2.

/datum/data/text
	name = "text"
	var/data = null
