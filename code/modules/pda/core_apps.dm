/datum/data/pda/app/main_menu
	icon = "home"
	template = "pda_main_menu"
	hidden = 1

/datum/data/pda/app/main_menu/update_ui(mob/user, list/data)
	title = pda().name

	data["app"]["is_home"] = 1

	data["apps"] = (pda().shortcut_cache || list())
	data["categories"] = (pda().shortcut_cat_order || list())
	data["pai"] = !isnull(pda().pai)				// pAI inserted?

	var/list/notifying[0]
	for(var/P in pda().notifying_programs)
		notifying["\ref[P]"] = 1
	data["notifying"] = notifying

UI_ACT(/datum/data/pda/app/main_menu, "UpdateInfo", ui_act_updateinfo)
UI_ACT_PROC(/datum/data/pda/app/main_menu, ui_act_updateinfo)
	pda().ownjob = pda().id.assignment
	pda().ownrank = pda().id.rank
	pda().name = "PDA-[pda().owner] ([pda().ownjob])"
	return TRUE

UI_ACT(/datum/data/pda/app/main_menu, "pai", ui_act_pai, UI_ARG_NUM("option"))
UI_ACT_PROC(/datum/data/pda/app/main_menu, ui_act_pai)
	if(pda().pai)
		if(pda().pai.loc != pda())
			pda().pai = null
		else
			switch(params["option"])
				if(1)		// Configure pAI device
					pda().pai.attack_self(ui.user)
				if(2)		// Eject pAI device
					var/turf/T = get_turf_or_move(pda().loc)
					if(T)
						pda().pai.forceMove(T)
						pda().pai = null
	return TRUE

/datum/data/pda/app/notekeeper
	name = "Notekeeper"
	icon = "sticky-note-o"
	template = "pda_notekeeper"

	var/greeted = FALSE
	var/note = null
	var/notetitle = null
	var/currentnote = 1
	var/list/storedtitles = list("","","","","","","","","","","","") // ALLOW(instance_list): d: edited in place per instance (2 writers)
	var/list/storednotes = list("","","","","","","","","","","","") // ALLOW(instance_list): d: edited in place per instance (2 writers)
	var/notehtml = ""

/datum/data/pda/app/notekeeper/start()
	. = ..()
	if(!note && greeted == FALSE)

		// display greeting!
		greeted = TRUE
		note = "Thank you for choosing the [pda().model_name]!"
		notetitle = "Congratulations!"

/datum/data/pda/app/notekeeper/update_ui(mob/user, list/data)
	data["note"] = note									// current pda notes
	data["notename"] = "Note [GLOB.alphabet_upper[currentnote]] : [notetitle]"

UI_ACT(/datum/data/pda/app/notekeeper, "Edit", ui_act_edit)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_edit)
	var/n = act_ask(ui.user, action, params, ui, "k75", /datum/om/prompt/text, message = "Please enter message", title = name, default = notehtml, multiline = TRUE, max_length = MAX_TGUI_INPUT)
	if(isnull(n))
		return
	if(pda().loc == ui.user)
		note = adminscrub(n)
		notehtml = html_decode(note)
		note = replacetext(note, "\n", "<br>")
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Titleset", ui_act_titleset)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_titleset)
	var/n = act_ask(ui.user, action, params, ui, "k84", /datum/om/prompt/text, message = "Please enter title", title = name, default = notetitle)
	if(isnull(n))
		return
	if(pda().loc == ui.user)
		notetitle = adminscrub(n)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Print", ui_act_print)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_print)
	if(pda().loc == ui.user)
		printnote(ui.user)
	else
		pda().close(ui.user)
	return TRUE
// dumb way to do this, but i don't know how to easily parse this without a lot of silly code outside the switch!

UI_ACT(/datum/data/pda/app/notekeeper, "Note1", ui_act_note1)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note1)
	if(pda().loc == ui.user)
		changetonote(1)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note2", ui_act_note2)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note2)
	if(pda().loc == ui.user)
		changetonote(2)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note3", ui_act_note3)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note3)
	if(pda().loc == ui.user)
		changetonote(3)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note4", ui_act_note4)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note4)
	if(pda().loc == ui.user)
		changetonote(4)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note5", ui_act_note5)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note5)
	if(pda().loc == ui.user)
		changetonote(5)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note6", ui_act_note6)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note6)
	if(pda().loc == ui.user)
		changetonote(6)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note7", ui_act_note7)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note7)
	if(pda().loc == ui.user)
		changetonote(7)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note8", ui_act_note8)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note8)
	if(pda().loc == ui.user)
		changetonote(8)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note9", ui_act_note9)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note9)
	if(pda().loc == ui.user)
		changetonote(9)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note10", ui_act_note10)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note10)
	if(pda().loc == ui.user)
		changetonote(10)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note11", ui_act_note11)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note11)
	if(pda().loc == ui.user)
		changetonote(11)
	else
		pda().close(ui.user)
	return TRUE

UI_ACT(/datum/data/pda/app/notekeeper, "Note12", ui_act_note12)
UI_ACT_PROC(/datum/data/pda/app/notekeeper, ui_act_note12)
	if(pda().loc == ui.user)
		changetonote(12)
	else
		pda().close(ui.user)
	return TRUE

/datum/data/pda/app/notekeeper/proc/printnote(mob/user)
	// get active hand of person holding PDA, and print the page to the paper in it
	if(istype( user, /mob/living/carbon/human ))
		var/mob/living/carbon/human/H = user
		var/obj/item/I = H.get_active_hand()
		if(istype(I,/obj/item/paper))
			var/obj/item/paper/P = I
			if(isnull(P.info) || P.info == "" )
				var/titlenote = "Note [GLOB.alphabet_upper[currentnote]]"
				if(!isnull(notetitle) && notetitle != "")
					titlenote = notetitle
				to_chat(user, span_notice("Successfully printed [titlenote]!"))
				P.set_content( pencode2html(note), titlenote)
			else
				to_chat(user, span_notice("You can only print to empty paper!"))
		else
			to_chat(user, span_notice("You must be holding paper for the pda to print to!"))


/datum/data/pda/app/notekeeper/proc/changetonote(noteindex)
	// save note to current slot, then load another slot
	storednotes[currentnote] = note
	storedtitles[currentnote] = notetitle

	currentnote = noteindex

	note = storednotes[currentnote]
	notetitle = storedtitles[currentnote]

	// update text on keeper, silly swapping!
	note = replacetext(note, "<br>", "\n")
	notehtml = html_decode(note)
	note = replacetext(note, "\n", "<br>")

/datum/data/pda/app/manifest
	name = "Crew Manifest"
	icon = "user"
	template = "pda_manifest"

/datum/data/pda/app/manifest/update_ui(mob/user, list/data)
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest



/datum/data/pda/app/atmos_scanner
	name = "Atmospheric Scan"
	icon = "fire"
	template = "pda_atmos_scan"
	category = "Utilities"

/datum/data/pda/app/atmos_scanner/update_ui(mob/user, list/data)
	var/turf/location = get_turf(user)
	data["aircontents"] = get_gas_mixture_default_scan_data(location?.return_air())

/datum/data/pda/app/news
	name = "News"
	icon = "newspaper"
	template = "pda_news"

	var/newsfeed_channel

/datum/data/pda/app/news/update_ui(mob/user, list/data)
	data["feeds"] = compile_news()
	data["latest_news"] = get_recent_news()
	if(newsfeed_channel)
		data["target_feed"] = data["feeds"][newsfeed_channel]
	else
		data["target_feed"] = null

UI_ACT(/datum/data/pda/app/news, "newsfeed", ui_act_newsfeed, UI_ARG_NUM("newsfeed"))
UI_ACT_PROC(/datum/data/pda/app/news, ui_act_newsfeed)
	newsfeed_channel = params["newsfeed"]

/datum/data/pda/app/news/proc/compile_news()
	var/list/feeds = list()
	for(var/datum/feed_channel/channel in GLOB.news_network.network_channels)
		var/list/messages = list()
		if(!channel.censored)
			var/index = 0
			for(var/datum/feed_message/FM in channel.messages)
				index++
				var/list/msgdata = list(
					"author" = FM.author,
					"body" = FM.body,
					"img" = null,
					"message_type" = FM.message_type,
					"time_stamp" = FM.time_stamp,
					"caption" = FM.caption,
					"index" = index
				)
				if(FM.img)
					msgdata["img"] = icon2base64(FM.img)
				messages[++messages.len] = msgdata

		feeds[++feeds.len] = list(
					"name" = channel.channel_name,
					"censored" = channel.censored,
					"author" = channel.author,
					"messages" = messages,
					"index" = feeds.len + 1
					)
	return feeds

/datum/data/pda/app/news/proc/get_recent_news()
	var/list/news = list()

	// Compile all the newscasts
	for(var/datum/feed_channel/channel in GLOB.news_network.network_channels)
		if(!channel.censored)
			var/index = 0
			for(var/datum/feed_message/FM in channel.messages)
				index++
				var/body = replacetext(FM.body, "\n", "<br>")
				news[++news.len] = list(
							"channel" = channel.channel_name,
							"author" = FM.author,
							"body" = body,
							"message_type" = FM.message_type,
							"time_stamp" = FM.time_stamp,
							"has_image" = (FM.img != null),
							"caption" = FM.caption,
							"time" = FM.post_time,
							"index" = index
							)

	// Cut out all but the youngest three
	if(news.len > 3)
		sortByKey(news, "time")
		news.Cut(1, news.len - 2) // Last three have largest timestamps, youngest posts
		news.Swap(1, 3) // List is sorted in ascending order of timestamp, we want descending

	return news


/datum/data/pda/app/timeclock
	name = "Timeclock"
	icon = "clock"
	template = "pda_timeclock"

	var/channel = "Common"
	var/obj/item/radio/intercom/announce

CAPABILITIES(/datum/data/pda/app/timeclock)
	owns_one(nameof(announce), /obj/item/radio/intercom)

/datum/data/pda/app/timeclock/start()
	. = ..()
	//Initialize an intercom to announce going on/off duty
	if(!announce)
		rel_set(src, nameof(announce), new /obj/item/radio/intercom(src))

/datum/data/pda/app/timeclock/update_ui(mob/user as mob, list/data)
	//Because tgui_data seems a bit weird with pda apps
	// Okay, data for showing the user's OWN PTO stuff
	if(user.client)
		data["department_hours"] = SANITIZE_LIST(user.client.department_hours)
	data["user_name"] = "[user]"
	data["is_human"] = ishuman(user)
	data["area_clockout"] = isAllowedAreaClockout(user)
	// Data about the card that we put into it.
	data["card"] = null
	data["assignment"] = null
	data["job_datum"] = null
	data["allow_change_job"] = null
	data["job_choices"] = null
	if(pda().id)
		data["card"] = "[pda().id]"
		data["assignment"] = pda().id.assignment
		data["card_cooldown"] = getCooldown()
		var/datum/job/job = SSjob.get_job(pda().id.rank)
		if(job)
			data["job_datum"] = list(
				"title" = job.title,
				"departments" = english_list(job.departments),
				"selection_color" = job.selection_color,
				"economic_modifier" = job.economic_modifier,
				"timeoff_factor" = job.timeoff_factor,
				"pto_department" = job.pto_type
			)
		if(CONFIG_GET(flag/time_off) && CONFIG_GET(flag/pto_job_change))
			data["allow_change_job"] = TRUE
			if(job && job.timeoff_factor < 0) // Currently are Off Duty, so gotta lookup what on-duty jobs are open
				data["job_choices"] = getOpenOnDutyJobs(user, job.pto_type)

UI_ACT(/datum/data/pda/app/timeclock, "switch-to-onduty-rank", ui_act_switch_to_onduty_rank, UI_ARG_VALUE("switch-to-onduty-assignment"), UI_ARG_VALUE("switch-to-onduty-rank"))
UI_ACT_PROC(/datum/data/pda/app/timeclock, ui_act_switch_to_onduty_rank)
	if(checkFace(ui.user))
		if(checkCardCooldown(ui.user))
			makeOnDuty(ui.user, params["switch-to-onduty-rank"], params["switch-to-onduty-assignment"])
	return TRUE

UI_ACT(/datum/data/pda/app/timeclock, "switch-to-offduty", ui_act_switch_to_offduty)
UI_ACT_PROC(/datum/data/pda/app/timeclock, ui_act_switch_to_offduty)
	if(checkFace(ui.user))
		if(checkCardCooldown(ui.user))
			makeOffDuty(ui.user)
	return TRUE

/datum/data/pda/app/timeclock/proc/getOpenOnDutyJobs(mob/user, department)
	var/list/available_jobs = list()
	for(var/datum/job/job in SSjob.occupations)
		if(isOpenOnDutyJob(user, department, job))
			available_jobs[job.title] = list(job.title)
			if(job.alt_titles)
				for(var/alt_job in job.alt_titles)
					if(alt_job != job.title)
						available_jobs[job.title] += alt_job
	return available_jobs

/datum/data/pda/app/timeclock/proc/isOpenOnDutyJob(mob/user, department, datum/job/job)
	return job \
		   && job.is_position_available() \
		   && !job.whitelist_only \
		   && !jobban_isbanned(user,job.title) \
		   && job.player_old_enough(user.client) \
		   && job.player_has_enough_playtime(user.client) \
		   && job.pto_type == department \
		   && !job.disallow_jobhop \
		   && job.timeoff_factor > 0

/datum/data/pda/app/timeclock/proc/makeOnDuty(mob/user, newrank, newassignment)
	var/datum/job/oldjob = SSjob.get_job(pda().id.rank)
	var/datum/job/newjob = SSjob.get_job(newrank)
	if(!oldjob || !isOpenOnDutyJob(user, oldjob.pto_type, newjob))
		return
	if(newassignment != newjob.title && !(newassignment in newjob.alt_titles))
		return
	if(newjob.camp_protection && round_duration_in_ds < CONFIG_GET(number/job_camp_time_limit))
		if(length(SSjob.restricted_keys))
			var/list/check = LAZYACCESS(SSjob.restricted_keys, newjob.title)
			if(user.client.ckey in check)
				to_chat(user,span_danger("[newjob.title] is not presently selectable because you played as it last round. It will become available to you in [round((CONFIG_GET(number/job_camp_time_limit) - round_duration_in_ds) / 600)] minutes, if slots remain open."))
				return
	if(newjob)
		newjob.register_shift_key(user.client.ckey)
		pda().id.access = newjob.get_access()
		pda().id.rank = newjob.title
		pda().id.assignment = newassignment
		pda().id.name = text("[pda().id.registered_name]'s ID Card ([pda().id.assignment])")
		GLOB.data_core.manifest_modify(pda().id.registered_name, pda().id.assignment, pda().id.rank)
		EXPIRY_STAMP(pda().id, last_job_switch, CLOCK_WORLD)
		callHook("reassign_employee", list(pda().id))
		newjob.current_positions++
		user.mind.assigned_role = pda().id.rank
		user.mind.role_alt_title = pda().id.assignment
		announce.autosay("[pda().id.registered_name] has moved On-Duty as [pda().id.assignment].", "Employee Oversight", channel, zlevels = using_map.get_map_levels(get_z(src)))
	return

/datum/data/pda/app/timeclock/proc/makeOffDuty(mob/user)
	var/datum/job/foundjob = SSjob.get_job(pda().id.rank)
	if(!foundjob)
		return
	//If we're not in an area that allows clockout and not in a belly, shouldn't be able to clock out.
	if(!isAllowedAreaClockout(user))
		to_chat(user, span_notice("You cannot clock out from your PDA in this area"))
		return
	var/new_dept = foundjob.pto_type || PTO_CIVILIAN
	var/datum/job/ptojob = null
	for(var/datum/job/job in SSjob.occupations)
		if(job.pto_type == new_dept && job.timeoff_factor < 0)
			ptojob = job
			break
	if(ptojob)
		var/oldtitle = pda().id.assignment
		pda().id.access = ptojob.get_access()
		pda().id.rank = ptojob.title
		pda().id.assignment = ptojob.title
		pda().id.name = text("[pda().id.registered_name]'s ID Card ([pda().id.assignment])")
		GLOB.data_core.manifest_modify(pda().id.registered_name, pda().id.assignment, pda().id.rank)
		EXPIRY_STAMP(pda().id, last_job_switch, CLOCK_WORLD)
		callHook("reassign_employee", list(pda().id))
		user.mind.assigned_role = ptojob.title
		user.mind.role_alt_title = ptojob.title
		foundjob.current_positions--
		announce.autosay("[pda().id.registered_name], [oldtitle], has moved Off-Duty.", "Employee Oversight", channel, zlevels = using_map.get_map_levels(get_z(src)))
	return

/datum/data/pda/app/timeclock/proc/isAllowedAreaClockout(mob/user)
	return (get_area(user).flag_check(AREA_ALLOW_CLOCKOUT) || isbelly(user.loc))

/datum/data/pda/app/timeclock/proc/checkCardCooldown(mob/user)
	if(!pda().id)
		return FALSE
	var/time_left = getCooldown()
	if(time_left > 0)
		to_chat(user, span_notice("You need to wait another [round((time_left/10)/60, 1)] minute\s before you can switch."))
		return FALSE
	return TRUE


/datum/data/pda/app/timeclock/proc/getCooldown()
	return 1 MINUTES - ELAPSED(pda().id, last_job_switch, CLOCK_WORLD)

/datum/data/pda/app/timeclock/proc/checkFace(mob/user)
	var/turf/location = get_turf(user)
	if(!pda().id)
		to_chat(user, span_notice("No ID is inserted."))
		return FALSE
	if(pda().id.registered_name != user.real_name)
		to_chat(user, span_notice("This does not appear to be your ID"))
		return FALSE
	else
		message_admins("[key_name_admin(user)] has modified '[pda().id.registered_name]' 's ID with a pda timeclock. [ADMIN_JMP(location)]")
		log_game("[key_name_admin(user)] has modified '[pda().id.registered_name]' 's ID with a pda timeclock.")
		return TRUE

