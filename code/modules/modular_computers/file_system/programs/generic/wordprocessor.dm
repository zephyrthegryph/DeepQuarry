/datum/computer_file/program/wordprocessor
	filename = "wordprocessor"
	filedesc = "NanoWord"
	extended_desc = "This program allows the editing and preview of text documents."
	program_icon_state = "word"
	program_key_state = "atmos_key"
	size = 4
	requires_ntnet = FALSE
	available_on_ntnet = TRUE
	tgui_id = "NtosWordProcessor"

	var/browsing = FALSE
	var/open_file
	var/loaded_data
	var/error
	var/is_edited

	usage_flags = PROGRAM_ALL
	category = PROG_OFFICE

/datum/computer_file/program/wordprocessor/proc/get_file(filename)
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
		open_file = F.filename
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
		qdel(backup)
		return 0
	F.stored_data = loaded_data
	F.calculate_size()
	if(!HDD.store_file(F))
		HDD.store_file(backup)
		qdel(F) // detached by remove_file() and not stored again
		return 0
	qdel(backup)
	is_edited = 0
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

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_txtrpeview", ui_act_prg_txtrpeview)
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_txtrpeview)
	// structured TGUI AdminReport.
	dq_admin_report_html(ui.user, open_file, "[pencode2html(loaded_data)]")
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_taghelp", ui_act_prg_taghelp)
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_taghelp)
	to_chat(ui.user, span_notice("The hologram of a googly-eyed paper clip helpfully tells you:"))
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

	to_chat(ui.user, help)
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_closebrowser", ui_act_prg_closebrowser)
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_closebrowser)
	browsing = 0
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_backtomenu", ui_act_prg_backtomenu)
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_backtomenu)
	error = null
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_loadmenu", ui_act_prg_loadmenu)
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_loadmenu)
	browsing = 1
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_openfile", ui_act_prg_openfile, UI_ARG_TEXT("PRG_openfile"))
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_openfile)
	if(is_edited)
		var/_answer_k126 = act_ask(ui.user, action, params, ui, "k126", /datum/om/prompt/choice/alert, message = "Would you like to save your changes first?", title = "Save Changes", choices = list("Yes","No"))
		if(isnull(_answer_k126))
			return
		if(_answer_k126 == "Yes")
			save_file(open_file)
	browsing = 0
	if(!open_file(params["PRG_openfile"]))
		error = "I/O error: Unable to open file '[params["PRG_openfile"]]'."
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_newfile", ui_act_prg_newfile, UI_ARG_TEXT("PRG_saveasfile"))
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_newfile)
	if(is_edited)
		var/_answer_k135 = act_ask(ui.user, action, params, ui, "k135", /datum/om/prompt/choice/alert, message = "Would you like to save your changes first?", title = "Save Changes", choices = list("Yes","No"))
		if(isnull(_answer_k135))
			return
		if(_answer_k135 == "Yes")
			save_file(open_file)

	var/newname = act_ask(ui.user, action, params, ui, "k138", /datum/om/prompt/text, message = "Enter file name:", title = "New File")
	if(isnull(newname))
		return
	if(!newname)
		return TRUE
	var/datum/computer_file/data/F = create_file(newname)
	if(F)
		open_file = F.filename
		loaded_data = ""
		return TRUE
	else
		error = "I/O error: Unable to create file '[params["PRG_saveasfile"]]'."
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_saveasfile", ui_act_prg_saveasfile, UI_ARG_TEXT("PRG_saveasfile"))
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_saveasfile)
	var/newname = act_ask(ui.user, action, params, ui, "k151", /datum/om/prompt/text, message = "Enter file name:", title = "Save As")
	if(isnull(newname))
		return
	if(!newname)
		return TRUE
	var/datum/computer_file/data/F = create_file(newname, loaded_data)
	if(F)
		open_file = F.filename
	else
		error = "I/O error: Unable to create file '[params["PRG_saveasfile"]]'."
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_savefile", ui_act_prg_savefile)
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_savefile)
	if(!open_file)
		var/_answer_k163 = act_ask(ui.user, action, params, ui, "k163", /datum/om/prompt/text, message = "Enter file name:", title = "Save As")
		if(isnull(_answer_k163))
			return
		open_file = _answer_k163
		if(!open_file)
			return 0
	if(!save_file(open_file))
		error = "I/O error: Unable to save file '[open_file]'."
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_editfile", ui_act_prg_editfile)
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_editfile)
	var/oldtext = html_decode(loaded_data)
	oldtext = replacetext(oldtext, "\[br\]", "\n")

	var/_answer_k174 = act_ask(ui.user, action, params, ui, "k174", /datum/om/prompt/text, message = "Editing file '[open_file]'. You may use most tags used in paper formatting:", title = "Text Editor", default = oldtext, max_length = MAX_TEXTFILE_LENGTH, multiline = TRUE)
	if(isnull(_answer_k174))
		return
	var/newtext = replacetext(_answer_k174, "\n", "\[br\]")
	if(!newtext)
		return
	loaded_data = newtext
	is_edited = 1
	return TRUE

UI_ACT(/datum/computer_file/program/wordprocessor, "PRG_printfile", ui_act_prg_printfile)
UI_ACT_PROC(/datum/computer_file/program/wordprocessor, ui_act_prg_printfile)
	if(!computer().nano_printer)
		error = "Missing Hardware: Your computer does not have the required hardware to complete this operation."
		return TRUE
	if(!computer().nano_printer.print_text(pencode2html(loaded_data)))
		error = "Hardware error: Printer was unable to print the file. It may be out of paper."
		return TRUE
	return TRUE

UI_DATA_REPLACE(/datum/computer_file/program/wordprocessor, "merge:ui_data_datum_computer_file_program_wordprocessor{error:text,browsing:num,files:list,usbconnected:num,usbfiles:list,filedata:unknown,filename:unknown}")

/// The computed part of /datum/computer_file/program/wordprocessor's window data (declared on its UI_DATA row).
/datum/computer_file/program/wordprocessor/proc/ui_data_datum_computer_file_program_wordprocessor(mob/user, datum/tgui/ui, datum/tgui_state/state)
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
