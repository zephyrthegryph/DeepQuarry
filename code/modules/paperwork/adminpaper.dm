//Adminpaper - it's like paper, but more adminny!
/obj/item/paper/admin
	name = "administrative paper"
	desc = "If you see this, something has gone horribly wrong."
	var/datum/admins/admindatum = null

	var/interactions = null
	var/isCrayon = 0
	var/origin = null
	var/mob/sender = null
	var/obj/machinery/photocopier/faxmachine/destination

	var/header = null
	var/headerOn = TRUE

	var/footer = null
	var/footerOn = FALSE

/obj/item/paper/admin/Initialize(mapload, text, title)
	. = ..()
	generateInteractions()


/obj/item/paper/admin/proc/generateInteractions()
	//clear first
	interactions = null

	//Snapshot is crazy and likes putting each topic hyperlink on a seperate line from any other tags so it's nice and clean.
	interactions += "<HR><center><font size= \"1\">The fax will transmit everything above this line</font><br>"
	interactions += "<A href='byond://?src=\ref[src];[HrefToken()];confirm=1'>Send fax</A> "
	interactions += "<A href='byond://?src=\ref[src];[HrefToken()];penmode=1'>Pen mode: [isCrayon ? "Crayon" : "Pen"]</A> "
	interactions += "<A href='byond://?src=\ref[src];[HrefToken()];cancel=1'>Cancel fax</A> "
	interactions += "<BR>"
	interactions += "<A href='byond://?src=\ref[src];[HrefToken()];toggleheader=1'>Toggle Header</A> "
	interactions += "<A href='byond://?src=\ref[src];[HrefToken()];togglefooter=1'>Toggle Footer</A> "
	interactions += "<A href='byond://?src=\ref[src];[HrefToken()];clear=1'>Clear page</A> "
	interactions += "</center>"

/obj/item/paper/admin/proc/generateHeader()
	var/originhash = md5("[origin]")
	var/timehash = copytext(md5("[world.time]"),1,10)
	var/text = null
	var/logo = tgui_alert(usr, "Do you want the header of your fax to have a NanoTrasen, SolGov, Talon or Trader logo?","Fax Logo",list("NanoTrasen","SolGov", "Talon", "Trader")) // Trader
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
// the admin actions. No more byond:// hrefs, no more interactions HTML.
/obj/item/paper/admin/proc/adminbrowse()
	generateHeader()
	generateFooter()
	tgui_view = "write"
	tgui_interact(usr)

/obj/item/paper/admin/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "AdminPaper", name)
		ui.open()

/obj/item/paper/admin/tgui_data(mob/user)
	var/list/data = list()
	data["title"] = name
	data["segments"] = get_segments()
	data["stamps"] = stamps || ""
	data["header_html"] = header || ""
	data["footer_html"] = footer || ""
	data["header_on"] = !!headerOn
	data["footer_on"] = !!footerOn
	data["is_crayon"] = !!isCrayon
	return data

/obj/item/paper/admin/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	switch(action)
		if("write_field")
			admin_write("[params["id"]]", usr)
			return TRUE
		if("write_end")
			admin_write("end", usr)
			return TRUE
		if("confirm")
			switch(tgui_alert(usr, "Are you sure you want to send the fax as is?", "Send Fax", list("Yes", "No")))
				if("Yes")
					if(headerOn)
						info = header + info
					if(footerOn)
						info += footer
					updateinfolinks()
					SStgui.close_uis(src)
					admindatum.faxCallback(src, destination)
			return TRUE
		if("penmode")
			isCrayon = !isCrayon
			return TRUE
		if("cancel")
			SStgui.close_uis(src)
			qdel(src)
			return TRUE
		if("clear")
			clearpaper()
			return TRUE
		if("toggleheader")
			headerOn = !headerOn
			return TRUE
		if("togglefooter")
			footerOn = !footerOn
			return TRUE

// Admin variant uses no pen/range checks (admins fax from anywhere) and
// always pencode-parses with the chosen crayon flag.
/obj/item/paper/admin/proc/admin_write(id, mob/user)
	if(free_space <= 0)
		to_chat(user, span_info("There isn't enough space left on \the [src] to write anything."))
		return
	var/t = tgui_input_text(user, "Enter what you want to write:", "Write", "", free_space, TRUE, prevent_enter = TRUE)
	if(!t)
		return
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

/obj/item/paper/admin/get_signature()
	return tgui_input_text(usr, "Enter the name you wish to sign the paper with (will prompt for multiple entries, in order of entry)", "Signature")
