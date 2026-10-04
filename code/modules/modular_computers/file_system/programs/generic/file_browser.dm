/datum/computer_file/program/filemanager
	filename = "filemanager"
	filedesc = "NTOS File Manager"
	extended_desc = "This program allows management of files."
	program_icon_state = "generic"
	program_key_state = "generic_key"
	program_menu_icon = "folder-collapsed"
	size = 8
	requires_ntnet = FALSE
	available_on_ntnet = FALSE
	undeletable = TRUE

	var/open_file
	var/error
	usage_flags = PROGRAM_ALL
	category = PROG_UTIL

TRACKED(/datum/computer_file/program/filemanager, open_file)

CAPABILITIES(/datum/computer_file/program/filemanager)
	interface("NtosFileManager")
	op("PRG_openfile", ui_act("PRG_openfile", arg("uid", num())), then(PROC_REF(ui_act_prg_openfile)))
	op("PRG_newtextfile", ui_act("PRG_newtextfile"), asks(/datum/prompt/text, fields = list("title" = "File rename", "question" = "Enter file name or leave blank to cancel:")), then(PROC_REF(ui_act_prg_newtextfile)))
	op("PRG_closefile", ui_act("PRG_closefile"), then(PROC_REF(ui_act_prg_closefile)))
	op("PRG_clone", ui_act("PRG_clone", arg("uid", num())), then(PROC_REF(ui_act_prg_clone)))
	op("PRG_edit", ui_act("PRG_edit"), asks(/datum/prompt/yes_no, fields = list("title" = "Incompatible File", "question" = "WARNING: This file is not compatible with editor. Editing it may result in permanently corrupted formatting or damaged data consistency. Edit anyway?"), step = "sure", when = PROC_REF(edit_file_incompatible)), asks(/datum/prompt/text, fields = list("title" = "Text Editor", "question" = computed(PROC_REF(edit_question)), "default" = computed(PROC_REF(edit_default)), "max_len" = MAX_TEXTFILE_LENGTH, "multiline" = TRUE), step = "text", when = PROC_REF(edit_file_ok)), then(PROC_REF(ui_act_prg_edit)))
	op("PRG_printfile", ui_act("PRG_printfile"), then(PROC_REF(ui_act_prg_printfile)))
	op("PRG_deletefile", ui_act("PRG_deletefile", arg("uid", num())), then(PROC_REF(ui_act_prg_deletefile)))
	op("PRG_rename", ui_act("PRG_rename", arg("new_name", schema_text(4096)), arg("uid", num())), then(PROC_REF(ui_act_prg_rename)))
	op("PRG_copytousb", ui_act("PRG_copytousb", arg("uid", num())), then(PROC_REF(ui_act_prg_copytousb)))
	op("PRG_copyfromusb", ui_act("PRG_copyfromusb", arg("uid", num())), then(PROC_REF(ui_act_prg_copyfromusb)))
	op("PRG_clearerror", ui_act("PRG_clearerror"), then(PROC_REF(ui_act_prg_clearerror)))

/datum/computer_file/program/filemanager/proc/ui_act_prg_openfile(datum/act/op/A, uid)
	set_open_file(uid)
	return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_newtextfile(datum/act/op/A)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	var/datum/prompt/P = A.answer
	var/newname = P?.value
	if(!newname)
		return
	if(HDD.find_file_by_name(newname))
		error = "I/O error: File already exists."
		return
	var/datum/computer_file/data/F = new/datum/computer_file/data/text()
	F.filename = newname
	HDD.store_file(F)
	return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_closefile(datum/act/op/A)
	set_open_file(null)
	return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_clone(datum/act/op/A, uid)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	var/datum/computer_file/F = HDD.find_file_by_uid(uid)
	if(!F || !istype(F))
		return
	var/datum/computer_file/C = F.clone(1)
	HDD.store_file(C)
	return TRUE

/// The file the window has open, when it is a data file.
/datum/computer_file/program/filemanager/proc/edited_file()
	var/obj/item/computer_hardware/hard_drive/HDD = computer()?.hard_drive
	if(!HDD || !open_file)
		return null
	var/datum/computer_file/data/F = computer().find_file_by_uid(open_file)
	return istype(F) ? F : null

/// A file the editor does not suit asks to be edited anyway first.
/datum/computer_file/program/filemanager/proc/edit_file_incompatible(datum/act/op/A)
	var/datum/computer_file/data/F = edited_file()
	return F?.do_not_edit

/// The text is asked for unless the file was refused.
/datum/computer_file/program/filemanager/proc/edit_file_ok(datum/act/op/A)
	var/datum/computer_file/data/F = edited_file()
	if(!F)
		return FALSE
	var/datum/prompt/P = A.step_answer("sure")
	return !F.do_not_edit || P?.value

/datum/computer_file/program/filemanager/proc/edit_question(datum/act/op/A)
	var/datum/computer_file/data/F = edited_file()
	return "Editing file [F?.filename].[F?.filetype]. You may use most tags used in paper formatting:"

/datum/computer_file/program/filemanager/proc/edit_default(datum/act/op/A)
	var/datum/computer_file/data/F = edited_file()
	var/oldtext = html_decode(F?.stored_data)
	return replacetext(oldtext, "\[br\]", "\n")

/datum/computer_file/program/filemanager/proc/ui_act_prg_edit(datum/act/op/A)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	var/datum/computer_file/data/F = edited_file()
	if(!F)
		return
	var/datum/prompt/sure_answer = A.step_answer("sure")
	if(F.do_not_edit && !sure_answer?.value)
		return
	var/datum/prompt/text_answer = A.step_answer("text")
	var/newtext = replacetext(text_answer?.value, "\n", "\[br\]")
	if(!newtext)
		return

	if(F)
		var/datum/computer_file/data/backup = F.clone()
		if(!F.holder().remove_file(F))
			qdel(backup)
			return TRUE
		F.stored_data = newtext
		F.calculate_size()
		// We can't store the updated file, it's probably too large. Print an error and restore backed up version.
		// This is mostly intended to prevent people from losing texts they spent lot of time working on due to running out of space.
		// They will be able to copy-paste the text from error screen and store it in notepad or something.
		var/obj/item/computer_hardware/hard_drive/drive = F.holder()
		if(!drive.store_file(F))
			error = "I/O error: Unable to overwrite file. Hard drive is probably full. You may want to backup your changes before closing this window:<br><br>[html_decode(F.stored_data)]<br><br>"
			drive.store_file(backup)
			qdel(F) // detached by remove_file() and not stored again
		else
			qdel(backup)
		return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_printfile(datum/act/op/A)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	if(!open_file)
		return
	var/datum/computer_file/data/F = computer().find_file_by_uid(open_file)
	if(!F || !istype(F))
		return
	if(!computer().nano_printer)
		error = "Missing Hardware: Your computer does not have required hardware to complete this operation."
		return TRUE
	if(!computer().nano_printer.print_text(pencode2html(F.stored_data)))
		error = "Hardware error: Printer was unable to print the file. It may be out of paper."
		return TRUE
	return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_deletefile(datum/act/op/A, uid)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	var/datum/computer_file/file = computer().find_file_by_uid(uid)
	if(!file || file.undeletable)
		return
	if(file.holder().remove_file(file))
		qdel(file)
	return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_rename(datum/act/op/A, new_name, uid)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	var/datum/computer_file/file = computer().find_file_by_uid(uid)
	if(!file)
		return
	var/newname = new_name
	if(!newname)
		return
	if(file.holder().find_file_by_name(newname))
		error = "I/O error: File already exists."
		return TRUE
	file.filename = newname
	return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_copytousb(datum/act/op/A, uid)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	var/obj/item/computer_hardware/hard_drive/RHDD = computer().portable_drive
	if(!HDD || !RHDD)
		return
	var/datum/computer_file/F = HDD.find_file_by_uid(uid)
	if(!F)
		return
	var/datum/computer_file/C = F.clone(FALSE)
	if(!RHDD.try_store_file(C))
		error = "I/O error: File already exists or insufficient space on drive."
		return TRUE
	RHDD.store_file(C)
	return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_copyfromusb(datum/act/op/A, uid)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	var/obj/item/computer_hardware/hard_drive/RHDD = computer().portable_drive
	if(!HDD || !RHDD)
		return
	var/datum/computer_file/F = RHDD.find_file_by_uid(uid)
	if(!F || !istype(F))
		return
	var/datum/computer_file/C = F.clone(FALSE)
	if(!HDD.try_store_file(C))
		error = "I/O error: File already exists or insufficient space on drive."
		return TRUE
	HDD.store_file(C)
	return TRUE

/datum/computer_file/program/filemanager/proc/ui_act_prg_clearerror(datum/act/op/A)
	error = null
	return TRUE

/datum/computer_file/program/filemanager/ui_data(datum/act/eval/A)
	var/list/data = get_header_data()

	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	var/obj/item/computer_hardware/hard_drive/portable/RHDD = computer().portable_drive

	data["error"] = null
	if(error)
		data["error"] = error
	if(!computer() || !HDD)
		data["error"] = "I/O ERROR: Unable to access hard drive."

	data["filedata"] = null
	data["filename"] = null
	data["files"] = list()
	data["usbconnected"] = FALSE
	data["usbfiles"] = list()

	if(open_file)
		var/datum/computer_file/data/file

		if(!computer() || (!computer().hard_drive && computer().portable_drive))
			data["error"] = "I/O ERROR: Unable to access hard drive."
		else
			file = computer().find_file_by_uid(open_file)
			if(!istype(file))
				data["error"] = "I/O ERROR: Unable to open file."
			else
				data["filedata"] = pencode2html(file.stored_data)
				data["filename"] = "[file.filename].[file.filetype]"
	else
		var/list/files = list()
		for(var/datum/computer_file/F in HDD.stored_files)
			files += list(list(
				"name" = F.filename,
				"type" = F.filetype,
				"uid" = F.uid,
				"size" = F.size,
				"undeletable" = F.undeletable
			))
		data["files"] = files
		if(RHDD)
			data["usbconnected"] = TRUE
			var/list/usbfiles = list()
			for(var/datum/computer_file/F in RHDD.stored_files)
				usbfiles += list(list(
					"name" = F.filename,
					"type" = F.filetype,
					"uid" = F.uid,
					"size" = F.size,
					"undeletable" = F.undeletable
				))
			data["usbfiles"] = usbfiles

	return data
