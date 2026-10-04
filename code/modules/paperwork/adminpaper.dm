//Adminpaper - it's like paper, but more adminny!
/obj/item/paper/admin
	/// The name the [sign] tags of the last write sign with.
	var/admin_signature
	name = "administrative paper"
	desc = "If you see this, something has gone horribly wrong."
	var/tmp/datum/admins/admindatum

	var/admin_fax_links = null
	var/isCrayon = 0
	var/origin = null
	var/tmp/mob/sender
	var/tmp/obj/machinery/photocopier/faxmachine/destination

	var/header = null
	var/headerOn = TRUE

	var/footer = null
	var/footerOn = FALSE

/obj/item/paper/admin/Initialize(mapload, text, title)
	. = ..()
	generateInteractions()


/obj/item/paper/admin/proc/generateInteractions()
	//clear first
	admin_fax_links = null

	//Snapshot is crazy and likes putting each topic hyperlink on a seperate line from any other tags so it's nice and clean.
	admin_fax_links += "<HR><center><font size= \"1\">The fax will transmit everything above this line</font><br>"
	admin_fax_links += "<A href='byond://?src=\ref[src];[HrefToken()];confirm=1'>Send fax</A> "
	admin_fax_links += "<A href='byond://?src=\ref[src];[HrefToken()];penmode=1'>Pen mode: [isCrayon ? "Crayon" : "Pen"]</A> "
	admin_fax_links += "<A href='byond://?src=\ref[src];[HrefToken()];cancel=1'>Cancel fax</A> "
	admin_fax_links += "<BR>"
	admin_fax_links += "<A href='byond://?src=\ref[src];[HrefToken()];toggleheader=1'>Toggle Header</A> "
	admin_fax_links += "<A href='byond://?src=\ref[src];[HrefToken()];togglefooter=1'>Toggle Footer</A> "
	admin_fax_links += "<A href='byond://?src=\ref[src];[HrefToken()];clear=1'>Clear page</A> "
	admin_fax_links += "</center>"

/obj/item/paper/admin/proc/generateHeader(logo)
	var/originhash = md5("[origin]")
	var/timehash = copytext(md5("[world.time]"),1,10)
	var/text = null
	if(!logo)
		return
	if(logo == "SolGov")
		logo = 'html/images/sglogo.png'
	// /Add
	else if(logo == "NanoTrasen")
		logo = 'html/images/ntlogo.png'
	else if(logo == "Talon")
		logo = 'html/images/talonlogo.png'
	else
		logo = 'html/images/trader.png'
	// /Add End
	//TODO change logo based on who you're contacting.
	text = "<center><img src=\ref[logo]></br>"
	text += span_bold("[origin] Quantum Uplink Signed Message") + "<br>"
	text += span_small("Encryption key: [originhash]<br>Challenge: [timehash]") + "<br></center><hr>"

	header = text

/obj/item/paper/admin/proc/generateFooter()
	var/text = null

	text = "<hr><font size= \"1\">"
	text += "This transmission is intended only for the addressee and may contain confidential information. Any unauthorized disclosure is strictly prohibited. <br><br>"
	text += "If this transmission is received in error, please notify both the sender and the office of [using_map.boss_name] Internal Affairs immediately so that corrective action may be taken."
	text += "Failure to comply is a breach of regulation and may be prosecuted to the fullest extent of the law, where applicable."
	text += "</font>"

	footer = text


// full TGUI migration. AdminPaper.tsx renders the
// segment-based body + structured admin controls; tgui_act handles
// the admin actions. No more byond:// hrefs, no more admin_fax_links HTML.
/obj/item/paper/admin/proc/adminbrowse(mob/user)
	generateFooter()
	tgui_view = "write"
	// Closing the logo question opens the fax without a header.
	om_ask(user, /datum/om/prompt/choice, PROC_REF(header_logo_chosen), title = "Fax Logo", message = "Do you want the header of your fax to have a NanoTrasen, SolGov, Talon or Trader logo?", choices = list("NanoTrasen", "SolGov", "Talon", "Trader"), cancel_answer = "", requires = PROMPT_ADMIN(R_ADMIN|R_EVENT))

/obj/item/paper/admin/proc/header_logo_chosen(datum/om/prompt/choice/ask)
	generateHeader(ask.choice)
	tgui_interact(ask.answerer)

CAPABILITIES(/obj/item/paper/admin)
	op("penmode", ui_act("penmode"), then(PROC_REF(admin_paper_penmode)))
	op("clear", ui_act("clear"), then(PROC_REF(admin_paper_clear)))
	op("toggleheader", ui_act("toggleheader"), then(PROC_REF(admin_paper_toggleheader)))
	op("togglefooter", ui_act("togglefooter"), then(PROC_REF(admin_paper_togglefooter)))

DECLARE_UI(/obj/item/paper/admin, "AdminPaper")

UI_DATA_REPLACE(/obj/item/paper/admin, "title=name:text", "merge:ui_data_obj_item_paper_admin{segments:unknown,stamps:bool,header_html:bool,footer_html:bool,header_on:bool,footer_on:bool,is_crayon:bool}")

/// The computed part of /obj/item/paper/admin's window data (declared on its UI_DATA row).
/obj/item/paper/admin/proc/ui_data_obj_item_paper_admin(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["segments"] = get_segments()
	data["stamps"] = stamps || ""
	data["header_html"] = header || ""
	data["footer_html"] = footer || ""
	data["header_on"] = !!headerOn
	data["footer_on"] = !!footerOn
	data["is_crayon"] = !!isCrayon
	return data

UI_ACT(/obj/item/paper/admin, "write_field", ui_act_write_field, UI_ARG_TEXT("id"))
UI_ACT_OVERRIDE(/obj/item/paper/admin, ui_act_write_field)
	admin_write("[params["id"]]", user)
	return TRUE

UI_ACT(/obj/item/paper/admin, "write_end", ui_act_write_end)
UI_ACT_OVERRIDE(/obj/item/paper/admin, ui_act_write_end)
	admin_write("end", user)
	return TRUE

UI_ACT(/obj/item/paper/admin, "confirm", ui_act_confirm)
UI_ACT_PROC(/obj/item/paper/admin, ui_act_confirm)
	switch(act_ask(user, action, params, ui, "send", /datum/om/prompt/choice/alert, message = "Are you sure you want to send the fax as is?", title = "Send Fax", choices = list("Yes", "No")))
		if("Yes")
			if(headerOn)
				info = header + info
			if(footerOn)
				info += footer
			updateinfolinks()
			SStgui.close_uis(src)
			admindatum().faxCallback(src, destination())
	return TRUE

/obj/item/paper/admin/proc/admin_paper_penmode(datum/act/op/A)
	isCrayon = !isCrayon
	return OP_OK

UI_ACT(/obj/item/paper/admin, "cancel", ui_act_cancel)
UI_ACT_PROC(/obj/item/paper/admin, ui_act_cancel)
	SStgui.close_uis(src)
	qdel(src)
	return TRUE

/obj/item/paper/admin/proc/admin_paper_clear(datum/act/op/A)
	clearpaper()
	return OP_OK

/obj/item/paper/admin/proc/admin_paper_toggleheader(datum/act/op/A)
	headerOn = !headerOn
	return OP_OK

/obj/item/paper/admin/proc/admin_paper_togglefooter(datum/act/op/A)
	footerOn = !footerOn
	return OP_OK

// Admin variant uses no pen/range checks (admins fax from anywhere) and
// always pencode-parses with the chosen crayon flag.
/obj/item/paper/admin/proc/admin_write(id, mob/user)
	if(free_space <= 0)
		to_chat(user, span_info("There isn't enough space left on \the [src] to write anything."))
		return
	// The answers re-run this write.
	var/t = rerun_ask(user, "text", PROC_REF(admin_write), args, /datum/om/prompt/text, message = "Enter what you want to write:", title = "Write", max_length = free_space, multiline = TRUE)
	if(!t)
		return
	if(findtext(t, "\[sign\]"))
		var/signature = rerun_ask(user, "signature", PROC_REF(admin_write), args, /datum/om/prompt/text, message = "Enter the name you wish to sign the paper with", title = "Signature")
		if(isnull(signature))
			return
		admin_signature = signature
	var/last_fields_value = fields
	t = replacetext(t, "\n", "<BR>")
	t = parsepencode(t, null, null, isCrayon)
	if(fields > 50)
		to_chat(user, span_warning("Too many fields. Sorry, you can't do this."))
		fields = last_fields_value
		return
	if(id != "end")
		addtofield(text2num(id), t)
	else
		info += t
		updateinfolinks()
	update_space(t)
	update_icon()

/obj/item/paper/admin/proc/updateDisplay()
	SStgui.update_uis(src)

/// The signature the admin gave for the [sign] tags of their last write.
/obj/item/paper/admin/get_signature(obj/item/pen/P, mob/user)
	return admin_signature || "Anonymous"

/// The admindatum this refers to (a relation view: null once that is deleted).
/obj/item/paper/admin/proc/admindatum() as /datum/admins
	return admindatum

/// The sender this refers to (a relation view: null once that is deleted).
/obj/item/paper/admin/proc/sender() as /mob
	return sender

/// The destination this refers to (a relation view: null once that is deleted).
/obj/item/paper/admin/proc/destination() as /obj/machinery/photocopier/faxmachine
	return destination
