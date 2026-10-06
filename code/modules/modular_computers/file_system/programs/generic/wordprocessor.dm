/datum/computer_file/program/wordprocessor
	filename = "wordprocessor"
	filedesc = "NanoWord"
	extended_desc = "This program allows the editing and preview of text documents."
	program_icon_state = "word"
	program_key_state = "atmos_key"
	size = 4
	requires_ntnet = FALSE
	available_on_ntnet = TRUE

	var/browsing = FALSE
	var/open_file
	var/loaded_data
	var/error
	var/is_edited

	usage_flags = PROGRAM_ALL
	category = PROG_OFFICE

/datum/computer_file/program/wordprocessor/proc/get_file(filename)
	RETURN_TYPE(/datum/computer_file/data)
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	var/datum/computer_file/data/F = HDD.find_file_by_name(filename)
	if(!istype(F))
		return
	return F

/datum/computer_file/program/wordprocessor/proc/open_file(filename)
	var/datum/computer_file/data/F = get_file(filename)
	if(F)
		set_open_file(F.filename)
		loaded_data = F.stored_data
		return TRUE

/datum/computer_file/program/wordprocessor/proc/save_file(filename)
	var/datum/computer_file/data/F = get_file(filename)
	if(!F) //try to make one if it doesn't exist
		F = create_file(filename, loaded_data)
		return !isnull(F)
	var/datum/computer_file/data/backup = F.clone()
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	if(!HDD.remove_file(F))
		spent(backup)
		return 0
	F.stored_data = loaded_data
	F.calculate_size()
	if(!HDD.store_file(F))
		HDD.store_file(backup)
		spent(F) // detached by remove_file() and not stored again
		return 0
	spent(backup)
	set_is_edited(0)
	return TRUE

/datum/computer_file/program/wordprocessor/proc/create_file(newname, data = "")
	if(!newname)
		return
	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	if(!HDD)
		return
	if(get_file(newname))
		return
	var/datum/computer_file/data/F = new/datum/computer_file/data()
	F.filename = newname
	F.filetype = "TXT"
	F.stored_data = data
	F.calculate_size()
	if(HDD.store_file(F))
		return F

TRACKED(/datum/computer_file/program/wordprocessor, open_file)
TRACKED(/datum/computer_file/program/wordprocessor, is_edited)

CAPABILITIES(/datum/computer_file/program/wordprocessor)
	interface("NtosWordProcessor")
	op("PRG_txtrpeview", ui_act("PRG_txtrpeview"), then(PROC_REF(ui_act_prg_txtrpeview)))
	op("PRG_taghelp", ui_act("PRG_taghelp"), then(PROC_REF(ui_act_prg_taghelp)))
	op("PRG_closebrowser", ui_act("PRG_closebrowser"), then(PROC_REF(ui_act_prg_closebrowser)))
	op("PRG_backtomenu", ui_act("PRG_backtomenu"), then(PROC_REF(ui_act_prg_backtomenu)))
	op("PRG_loadmenu", ui_act("PRG_loadmenu"), then(PROC_REF(ui_act_prg_loadmenu)))
	op("PRG_openfile", ui_act("PRG_openfile", arg("PRG_openfile", schema_text(4096))), asks(/datum/prompt/yes_no, fields = list("title" = "Save Changes", "question" = "Would you like to save your changes first?"), step = "save", when = PROC_REF(unsaved_changes)), then(PROC_REF(ui_act_prg_openfile)))
	op("PRG_newfile", ui_act("PRG_newfile", arg("PRG_saveasfile", schema_text(4096))), asks(/datum/prompt/yes_no, fields = list("title" = "Save Changes", "question" = "Would you like to save your changes first?"), step = "save", when = PROC_REF(unsaved_changes)), asks(/datum/prompt/text, fields = list("title" = "New File", "question" = "Enter file name:"), step = "name"), then(PROC_REF(ui_act_prg_newfile)))
	op("PRG_saveasfile", ui_act("PRG_saveasfile", arg("PRG_saveasfile", schema_text(4096))), asks(/datum/prompt/text, fields = list("title" = "Save As", "question" = "Enter file name:")), then(PROC_REF(ui_act_prg_saveasfile)))
	op("PRG_savefile", ui_act("PRG_savefile"), asks(/datum/prompt/text, fields = list("title" = "Save As", "question" = "Enter file name:"), step = "name", when = PROC_REF(no_open_file)), then(PROC_REF(ui_act_prg_savefile)))
	op("PRG_editfile", ui_act("PRG_editfile"), asks(/datum/prompt/text, fields = list("title" = "Text Editor", "question" = computed(PROC_REF(edit_question)), "default" = computed(PROC_REF(edit_default)), "max_len" = MAX_TEXTFILE_LENGTH, "multiline" = TRUE)), then(PROC_REF(ui_act_prg_editfile)))
	op("PRG_printfile", ui_act("PRG_printfile"), then(PROC_REF(ui_act_prg_printfile)))

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_txtrpeview(datum/act/op/A)
	var/mob/user = A.actor
	// structured TGUI AdminReport.
	dq_admin_report_html(user, open_file, "[pencode2html(loaded_data)]")
	return TRUE

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_taghelp(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("The hologram of a googly-eyed paper clip helpfully tells you:"))
	var/help = {"
	\[br\] : Creates a linebreak.
	\[center\] - \[/center\] : Centers the text.
	\[h1\] - \[/h1\] : First level heading.
	\[h2\] - \[/h2\] : Second level heading.
	\[h3\] - \[/h3\] : Third level heading.
	\[b\] - \[/b\] : Bold.
	\[i\] - \[/i\] : Italic.
	\[u\] - \[/u\] : Underlined.
	\[small\] - \[/small\] : Decreases the size of the text.
	\[large\] - \[/large\] : Increases the size of the text.
	\[field\] : Inserts a blank text field, which can be filled later. Useful for forms.
	\[date\] : Current station date.
	\[time\] : Current station time.
	\[list\] - \[/list\] : Begins and ends a list.
	\[*\] : A list item.
	\[hr\] : Horizontal rule.
	\[table\] - \[/table\] : Creates table using \[row\] and \[cell\] tags.
	\[grid\] - \[/grid\] : Table without visible borders, for layouts.
	\[row\] - New table row.
	\[cell\] - New table cell.
	\[logo\] - Inserts NT logo image.
	\[talogo\] - Inserts Talon company logo image.
	\[redlogo\] - Inserts red NT logo image.
	\[sglogo\] - Inserts Solgov insignia image."}

	to_chat(user, help)
	return TRUE

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_closebrowser(datum/act/op/A)
	browsing = 0
	return OP_OK

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_backtomenu(datum/act/op/A)
	error = null
	return OP_OK

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_loadmenu(datum/act/op/A)
	browsing = 1
	return OP_OK

/// Unsaved changes are asked about before another file replaces them.
/datum/computer_file/program/wordprocessor/proc/unsaved_changes(datum/act/op/A)
	return !!is_edited

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_openfile(datum/act/op/A, PRG_openfile)
	var/datum/prompt/save_answer = A.step_answer("save")
	if(is_edited && save_answer?.value)
		save_file(open_file)
	browsing = 0
	if(!open_file(PRG_openfile))
		error = "I/O error: Unable to open file '[PRG_openfile]'."
	return TRUE

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_newfile(datum/act/op/A, PRG_saveasfile)
	var/datum/prompt/save_answer = A.step_answer("save")
	if(is_edited && save_answer?.value)
		save_file(open_file)

	var/datum/prompt/name_answer = A.step_answer("name")
	var/newname = name_answer?.value
	if(!newname)
		return TRUE
	var/datum/computer_file/data/F = create_file(newname)
	if(F)
		set_open_file(F.filename)
		loaded_data = ""
		return TRUE
	else
		error = "I/O error: Unable to create file '[PRG_saveasfile]'."
	return TRUE

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_saveasfile(datum/act/op/A, PRG_saveasfile)
	var/datum/prompt/P = A.answer
	var/newname = P?.value
	if(!newname)
		return TRUE
	var/datum/computer_file/data/F = create_file(newname, loaded_data)
	if(F)
		set_open_file(F.filename)
	else
		error = "I/O error: Unable to create file '[PRG_saveasfile]'."
	return TRUE

/// A document with no name yet asks for one.
/datum/computer_file/program/wordprocessor/proc/no_open_file(datum/act/op/A)
	return !open_file

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_savefile(datum/act/op/A)
	if(!open_file)
		var/datum/prompt/name_answer = A.step_answer("name")
		set_open_file(name_answer?.value)
		if(!open_file)
			return 0
	if(!save_file(open_file))
		error = "I/O error: Unable to save file '[open_file]'."
	return TRUE

/datum/computer_file/program/wordprocessor/proc/edit_question(datum/act/op/A)
	return "Editing file '[open_file]'. You may use most tags used in paper formatting:"

/datum/computer_file/program/wordprocessor/proc/edit_default(datum/act/op/A)
	var/oldtext = html_decode(loaded_data)
	return replacetext(oldtext, "\[br\]", "\n")

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_editfile(datum/act/op/A)
	var/datum/prompt/P = A.answer
	var/newtext = replacetext(P?.value, "\n", "\[br\]")
	if(!newtext)
		return
	loaded_data = newtext
	set_is_edited(1)
	return TRUE

/datum/computer_file/program/wordprocessor/proc/ui_act_prg_printfile(datum/act/op/A)
	if(!computer().nano_printer)
		error = "Missing Hardware: Your computer does not have the required hardware to complete this operation."
		return TRUE
	if(!computer().nano_printer.print_text(pencode2html(loaded_data)))
		error = "Hardware error: Printer was unable to print the file. It may be out of paper."
		return TRUE
	return TRUE

/datum/computer_file/program/wordprocessor/ui_data(datum/act/eval/A)
	var/list/data = get_header_data()

	var/obj/item/computer_hardware/hard_drive/HDD = computer().hard_drive
	var/obj/item/computer_hardware/hard_drive/portable/RHDD = computer().portable_drive
	data["error"] = null
	if(error)
		data["error"] = error

	data["browsing"] = null
	data["files"] = list()
	data["usbconnected"] = FALSE
	data["usbfiles"] = list()
	data["filedata"] = null
	data["filename"] = null

	if(browsing)
		data["browsing"] = browsing
		if(!computer() || !HDD)
			data["error"] = "I/O ERROR: Unable to access hard drive."
		else
			var/list/files = list()
			for(var/datum/computer_file/F in HDD.stored_files)
				if(F.filetype == "TXT")
					files.Add(list(list(
						"name" = F.filename,
						"size" = F.size
					)))
			data["files"] = files

			if(RHDD)
				data["usbconnected"] = 1
				var/list/usbfiles = list()
				for(var/datum/computer_file/F in RHDD.stored_files)
					if(F.filetype == "TXT")
						usbfiles.Add(list(list(
							"name" = F.filename,
							"size" = F.size,
						)))
				data["usbfiles"] = usbfiles
	else if(open_file)
		data["filedata"] = pencode2html(loaded_data)
		data["filename"] = is_edited ? "[open_file]*" : open_file
	else
		data["filedata"] = pencode2html(loaded_data)
		data["filename"] = "UNNAMED"

	return data
