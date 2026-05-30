// All the procs that admins can use to view something like a global list in a cleaner manner than just View Variables are contained in this file.

/datum/admins/proc/list_bombers()
	if(!SSticker.HasRoundStarted())
		tgui_alert(usr, "The game hasn't started yet!")
		return
	// DQEdit — structured TGUI AdminReport.
	var/list/lines = list()
	for(var/entry in GLOB.bombers)
		lines += "[entry]"
	dq_admin_report_lines(usr, "Bombers", lines, "<b>Bombing List</b>")

/datum/admins/proc/list_signalers()
	if(!SSticker.HasRoundStarted())
		tgui_alert(usr, "The game hasn't started yet!")
		return
	// DQEdit — structured TGUI AdminReport.
	var/list/lines = list()
	for(var/entry in GLOB.lastsignalers)
		lines += "[entry]"
	dq_admin_report_lines(usr, "Last Signalers", lines, "<b>Showing last [length(GLOB.lastsignalers)] signalers.</b>")

/datum/admins/proc/list_law_changes()
	if(!SSticker.HasRoundStarted())
		tgui_alert(usr, "The game hasn't started yet!")
		return
	// DQEdit — structured TGUI AdminReport.
	var/list/lines = list()
	for(var/entry in GLOB.lawchanges)
		lines += "[entry]"
	dq_admin_report_lines(usr, "Law Changes", lines, "<b>Showing last [length(GLOB.lawchanges)] law changes.</b>")

/datum/admins/proc/list_dna()
	// DQEdit — structured TGUI AdminReport with typed table.
	var/list/rows = list()
	for(var/entry in GLOB.mob_list)
		var/mob/living/carbon/human/subject = entry
		if(!subject.ckey)
			continue
		rows += list(list(
			"[subject]",
			"[subject.dna?.unique_enzymes]",
			"[subject.dna ? subject.dna.b_type : DEFAULT_BLOOD_TYPE]",
		))
	dq_admin_report_table(usr, "DNA Log", list("Name", "DNA", "Blood Type"), rows, "<b>Showing DNA from blood.</b>")

/datum/admins/proc/list_fingerprints() //kid named fingerprints
	// DQEdit — structured TGUI AdminReport with typed table.
	var/list/rows = list()
	for(var/entry in GLOB.mob_list)
		var/mob/living/carbon/human/subject = entry
		if(!subject.ckey)
			continue
		rows += list(list(
			"[subject]",
			"[md5(subject.dna?.uni_identity)]",
		))
	dq_admin_report_table(usr, "Fingerprint Log", list("Name", "Fingerprints"), rows, "<b>Showing Fingerprints.</b>")

/datum/admins/proc/show_manifest()
	if(!SSticker.HasRoundStarted())
		tgui_alert(usr, "The game hasn't started yet!")
		return
	// DQEdit — structured TGUI AdminReport; manifest body stays as
	// pre-formatted HTML (per-department tables formatted by data_core).
	dq_admin_report_html(usr, "Manifest", "<h4>Crew Manifest</h4>[GLOB.data_core.get_manifest()]")

/datum/admins/proc/output_ai_laws()
	var/ai_number = 0
	for(var/mob/living/silicon/S in GLOB.mob_list)
		ai_number++
		if(isAI(S))
			to_chat(usr, span_bold("AI [key_name(S, usr)]'s laws:"))
		else if(isrobot(S))
			var/mob/living/silicon/robot/R = S
			to_chat(usr, span_bold("CYBORG [key_name(S, usr)] [R.connected_ai?"(Slaved to: [R.connected_ai])":"(Independent)"]: laws:"))
		else if (ispAI(S))
			to_chat(usr, span_bold("pAI [key_name(S, usr)]'s laws:"))
		else
			to_chat(usr, span_bold("SOMETHING SILICON [key_name(S, usr)]'s laws:"))

		if (S.laws == null)
			to_chat(usr, "[key_name(S, usr)]'s laws are null?? Contact a coder.")
		else
			S.laws.show_laws(usr)
	if(!ai_number)
		to_chat(usr, span_bold("No AIs located")) //Just so you know the thing is actually working and not just ignoring you.

	/* This part would require an update of the ai laws datum, but is replacing the above if implemented
	var/law_bound_entities = 0
	for(var/mob/living/silicon/subject as anything in mob_list)
		law_bound_entities++

		var/message = ""

		if(isAI(subject))
			message += "<b>AI [key_name(subject, usr)]'s laws:</b>"
		else if(isrobot(subject))
			var/mob/living/silicon/robot/borg = subject
			message += "<b>CYBORG [key_name(subject, usr)] [borg.connected_ai?"(Slaved to: [key_name(borg.connected_ai)])":"(Independent)"]: laws:</b>"
		else if (ispAI(subject))
			message += "<b>pAI [key_name(subject, usr)]'s laws:</b>"
		else
			message += "<b>SOMETHING SILICON [key_name(subject, usr)]'s laws:</b>"

		message += "<br>"

		if (!subject.laws)
			message += "[key_name(subject, usr)]'s laws are null?? Contact a coder."
		else
			message += jointext(subject.laws.get_law_list(include_zeroth = TRUE), "<br>")

		to_chat(usr, message, confidential = TRUE)

	if(!law_bound_entities)
		to_chat(usr, "<b>No law bound entities located</b>", confidential = TRUE)
	*/
