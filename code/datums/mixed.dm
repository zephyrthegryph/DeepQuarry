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
