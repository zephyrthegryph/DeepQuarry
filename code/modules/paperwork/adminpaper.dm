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
	open_request(src, /datum/prompt/choice, PROC_REF(header_logo_chosen), answerer = user, timeout = 0, title = "Fax Logo", question = "Do you want the header of your fax to have a NanoTrasen, SolGov, Talon or Trader logo?", choices = list("NanoTrasen", "SolGov", "Talon", "Trader"), rights = R_ADMIN|R_EVENT)

/obj/item/paper/admin/proc/header_logo_chosen(datum/act/request/A)
	var/datum/request/ask = A.request
	if(QDELETED(ask.answerer))
		return
	if(!A.answer && !(ask.outcome == REQ_CANCELLED && isnull(ask.value)))
		return
	generateHeader(A.answer ? ask.value : "")
	tgui_interact(ask.answerer)

CAPABILITIES(/obj/item/paper/admin)
	op("penmode", ui_act("penmode"), then(PROC_REF(admin_paper_penmode)))
	op("clear", ui_act("clear"), then(PROC_REF(admin_paper_clear)))
	op("toggleheader", ui_act("toggleheader"), then(PROC_REF(admin_paper_toggleheader)))
	op("togglefooter", ui_act("togglefooter"), then(PROC_REF(admin_paper_togglefooter)))
	interface("AdminPaper")
	without("ui_open")
	op("write_field", ui_act("write_field", arg("id", schema_text(4096))), then(PROC_REF(ui_act_write_field)))
	op("write_end", ui_act("write_end"), then(PROC_REF(ui_act_write_end)))
	op("confirm", ui_act("confirm"), asks(/datum/prompt/choice/admin_paper_send, step = "send"), then(PROC_REF(ui_act_confirm)))
	op("cancel", ui_act("cancel"), then(PROC_REF(ui_act_cancel)))

/obj/item/paper/admin/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["title"] = name
	var/list/merged_1 = ui_data_obj_item_paper_admin(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/paper/admin's window data.
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

/obj/item/paper/admin/ui_act_write_field(datum/act/op/A, id)
	var/mob/user = A.actor
	admin_write("[id]", user)
	return TRUE

/obj/item/paper/admin/ui_act_write_end(datum/act/op/A)
	var/mob/user = A.actor
	admin_write("end", user)
	return TRUE

/obj/item/paper/admin/proc/ui_act_confirm(datum/act/op/A)
	apply_send_confirmation(A.step_value("send"))
	return TRUE

/obj/item/paper/admin/proc/apply_send_confirmation(selected)
	if(selected == "Yes")
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

/obj/item/paper/admin/proc/ui_act_cancel(datum/act/op/A)
	SStgui.close_uis(src)
	spent(src)
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
	return admin_write_stage(id, user, list())

/obj/item/paper/admin/proc/admin_write_stage(id, mob/user, list/write_answers)
	if(free_space <= 0)
		to_chat(user, span_info("There isn't enough space left on \the [src] to write anything."))
		return
	// The answers re-run this write.
	if(!("text" in write_answers))
		open_request(src, /datum/prompt/text/admin_paper_write_review, PROC_REF(admin_write_answered), answerer = user, write_operator = user, write_id = id, write_answers = write_answers, write_key = "text", question = "Enter what you want to write:", title = "Write", max_len = free_space, multiline = TRUE, name_text = (free_space <= MAX_NAME_LEN))
		return
	var/t = write_answers["text"]
	if(!t)
		return
	if(findtext(t, "\[sign\]"))
		if(!("signature" in write_answers))
			open_request(src, /datum/prompt/text/admin_paper_write_review, PROC_REF(admin_write_answered), answerer = user, write_operator = user, write_id = id, write_answers = write_answers, write_key = "signature", question = "Enter the name you wish to sign the paper with", title = "Signature")
			return
		var/signature = write_answers["signature"]
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

/obj/item/paper/admin/proc/admin_write_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = admin_write_apply(A)
	SStgui.update_uis(src)

/obj/item/paper/admin/proc/admin_write_apply(datum/act/request/A)
	var/datum/prompt/text/admin_paper_write_review/ask = A.answer
	ask.write_answers[ask.write_key] = ask.value
	return admin_write_stage(ask.write_id, ask.write_operator, ask.write_answers)

/datum/prompt/text/admin_paper_write_review
	timeout = 0
	var/mob/write_operator
	var/write_operator_expected = FALSE
	var/write_id
	var/list/write_answers
	var/write_key

CAPABILITIES(/datum/prompt/text/admin_paper_write_review)
	ref_one(nameof(write_operator), /mob)

/datum/prompt/text/admin_paper_write_review/prepare(datum/act/A)
	. = ..()
	var/mob/captured_operator = write_operator
	write_operator_expected = !isnull(captured_operator)
	rel_clear(src, nameof(write_operator))
	if(captured_operator && !QDELETED(captured_operator))
		rel_set(src, nameof(write_operator), captured_operator)

/datum/prompt/text/admin_paper_write_review/recheck_extra()
	if(write_operator_expected && QDELETED(write_operator))
		return "gone"

/datum/prompt/choice/admin_paper_send
	question = "Are you sure you want to send the fax as is?"
	title = "Send Fax"
	choices = list("Yes", "No")
	buttons = TRUE
	timeout = 0
