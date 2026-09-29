GLOBAL_VAR_INIT(file_uid, 0)

/datum/computer_file/
	/// Placeholder. Whitespace and most special characters are not allowed.
	var/filename = "NewFile"
	/// File full names are [filename].[filetype] so like NewFile.XXX in this case
	var/filetype = "XXX"
	/// File size in GQ. Integers only!
	var/size = 1
	/// Holder that contains this file.
	var/tmp/obj/item/computer_hardware/hard_drive/holder
	//// Whether the file may be sent to someone via NTNet transfer, email or other means.
	var/unsendable = FALSE
	/// Whether the file may be deleted. Setting to TRUE prevents deletion/renaming/etc.
	var/undeletable = FALSE
	/// Whether the file is hidden from view in the OS
	var/hidden = FALSE
	/// Protects files that should never be edited by the user due to special properties.
	var/read_only = FALSE
	/// UID of this file
	var/uid
	/// Any metadata the file uses.
	var/list/metadata
	/// Paper type to use for printing
	var/papertype = /obj/item/paper

/datum/computer_file/New(list/md = null)
	..()
	uid = GLOB.file_uid
	GLOB.file_uid++
	if(islist(md))
		metadata = md.Copy()

// leaves its drive; a running program is killed.
/datum/computer_file/on_destroy(force)
	if(holder())
		holder().remove_file(src)
		// holder.holder is the computer that has drive installed. If we are deleting the program that's currently running kill it.
		var/obj/item/modular_computer/computer = holder().holder2()
		if(computer && (computer.active_program == src))
			rel_clear(computer, "active_program") // active_program() no longer resolves us
			computer.kill_program(1)
	..()

// Returns independent copy of this file.
/datum/computer_file/proc/clone(rename = 0)
	var/datum/computer_file/temp = new type
	temp.unsendable = unsendable
	temp.undeletable = undeletable
	temp.hidden = hidden
	temp.size = size
	if(metadata)
		temp.metadata = metadata.Copy()
	if(rename)
		temp.filename = filename + "(Copy)"
	else
		temp.filename = filename
	temp.filetype = filetype
	return temp

/// The holder this refers to (a relation view: null once that is deleted).
/datum/computer_file/proc/holder() as /obj/item/computer_hardware/hard_drive
	return holder
