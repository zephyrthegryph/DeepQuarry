/mob/living/silicon
	gender = NEUTER
	voice_name = "synthesized voice"
	var/syndicate = 0
	var/const/MAIN_CHANNEL = "Main Frequency"
	var/lawchannel = MAIN_CHANNEL // Default channel on which to state laws
	// ALLOW(instance_list): d: per-mob stating_laws, sized at creation and filled in place; mobs are few
	var/list/stating_laws = list()// Channels laws are currently being stated on
	var/obj/item/radio/common_radio

	has_huds = TRUE
	// ALLOW(instance_list): d: per-mob speech_synthesizer_langs, filled at runtime; mobs are few
	var/list/speech_synthesizer_langs = list()	//which languages can be vocalized by the speech synthesizer

	//Used in say.dm.
	var/speak_statement = "states"
	var/speak_exclamation = "declares"
	var/speak_query = "queries"
	var/pose //Yes, now AIs can pose too.
	var/obj/item/camera/siliconcam/aiCamera = null //photography
	var/local_transmit //If set, can only speak to others of the same type within a short range.

	var/next_alarm_notice
	/// One owned /datum/silicon_alarm_queue per registered alarm handler, keyed by "[handler.type]" text.
	var/list/queued_alarms

	var/list/access_rights
	var/obj/item/card/id/idcard

	var/sensor_type = 0 // add - silicon omni "is sensor on or nah"

	var/hudmode = null
	fire_stack_decay_rate = -0.55
	var/idcard_type = /obj/item/card/id/synthetic

CAPABILITIES(/mob/living/silicon)
	owns_one(nameof(aiCamera), /obj/item/camera/siliconcam)
	owns_one(nameof(alarm_monitor), /datum/tgui_module/alarm_monitor/all/robot)
	owns_one(nameof(atmos_control), /datum/tgui_module/atmos_control/robot)
	owns_one(nameof(crew_manifest), /datum/tgui_module/crew_manifest/robot)
	owns_one(nameof(crew_monitor), /datum/tgui_module/crew_monitor/robot)
	owns_one(nameof(idcard), /obj/item/card/id)
	owns_one(nameof(law_manager), /datum/tgui_module/law_manager/robot)
	owns_one(nameof(laws), /datum/ai_laws)
	owns_one(nameof(power_monitor), /datum/tgui_module/power_monitor/robot)
	owns_one(nameof(rcon), /datum/tgui_module/rcon/robot)
	owns_many(nameof(queued_alarms))
	param(nameof(decoy), pos = 1)

/// A decoy silicon (its constructor param): no ID, language or subsystems.
/mob/living/silicon/var/decoy = FALSE

// ALLOW(init/INSTANCE_STATE): a silicon that is not a decoy gets its ID, its language and its subsystems at init
/mob/living/silicon/Initialize(mapload)
	if(silicon_subsystems)
		silicon_subsystems = shared_type_list(type, "silicon_subsystems", silicon_subsystems)
	. = ..()
	if(!decoy)
		init_id(idcard_type)
		add_language(LANGUAGE_GALCOM)
		apply_default_language(GLOB.all_languages[LANGUAGE_GALCOM])
		init_subsystems()

		enable_footsteps(FOOTSTEP_MOB_SHOE, 1, -6)

REGISTRY_MEMBERSHIP(/mob/living/silicon, REGISTRY_SILICONS)

// The radio it speaks on belongs to the chassis (a borg's radio, an AI's aiRadio, a pAI's radio):
// common_radio is a plain relation (rel_set) naming it, never an owner.
// speech_synthesizer_langs holds shared language definitions: no declaration needed.

// leaves every alarm handler and its subsystems.
/mob/living/silicon/on_destroy(force)
	for(var/datum/alarm_handler/AH in all_alarm_handlers())
		AH.unregister_alarm(src)
	..()

/mob/living/silicon/proc/init_id(idcard_type)
	if(!idcard_type)
		return
	if(idcard)
		return
	rel_set(src, nameof(idcard), new idcard_type(src))
	set_id_info(idcard)

/mob/living/silicon/proc/SetName(pickedName as text)
	real_name = pickedName
	name = real_name

/mob/living/silicon/proc/show_laws()
	return

/mob/living/silicon/drop_item(atom/Target)
	return

/// An EMP is an electrical injury that brings a power fault with it. Blocking
/// components are asked before anything is pulsed, and the parent runs once.
/mob/living/silicon/emp_act(severity, recursive)
	if(om_has(src, EFFECT_GODMODE))
		return EMP_PROTECT_SELF
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	var/static/list/surge_by_severity = list(20, 15, 10, 5)
	var/static/list/confusion_by_severity = list(5, 4, 3, 2)
	var/band = round(severity)
	if(band >= 1 && band <= length(surge_by_severity))
		injure(INJURY_ELECTRIC, surge_by_severity[band], emp_injury_zone(), null, 0, /datum/affliction/synthetic/power_fault)
		status_at_least(EFFECT_CONFUSED, confusion_by_severity[band])
	flash_eyes(affect_silicon = 1)
	to_chat(src, span_bolddanger("*BZZZT*"))
	to_chat(src, span_danger("Warning: Electromagnetic pulse detected."))

/// Where an EMP surge lands. Robots route it past their armour plating.
/mob/living/silicon/proc/emp_injury_zone()
	return null

/mob/living/silicon/stun_effect_act(stun_amount, agony_amount, def_zone, used_weapon=null, electric = FALSE)
	return	//immune

/mob/living/silicon/electrocute_act(shock_damage, obj/source, siemens_coeff = 0.0, def_zone = null, stun = 1)
	if(shock_damage > 0)
		fx_sparks(loc, 5)

		shock_damage *= siemens_coeff	//take reduced damage
		receive_shock(shock_damage, source)
		act_message(src, source, MSG_SELF(span_danger("Energy pulse detected, system damaged!")), \
			MSG_OTHERS(span_warning("%U% was shocked by %T%!")), \
			MSG_BLIND(span_warning("You hear an electrical crack.")))
		if(prob(20))
			status_at_least(EFFECT_STUNNED, 2)
		return

/mob/living/silicon/IsAdvancedToolUser()
	return 1

/mob/living/silicon/bullet_act(obj/item/projectile/Proj)

	// Hardware takes located harm (impacts, burns, current); the synthetic body decides what each kind does.
	if(!Proj.nodamage && injury_is_located(Proj.injury_kind))
		Proj.inflict_injury(src, null)

	Proj.on_hit(src,2)
	return 2

/mob/living/silicon/apply_effect(effect = 0,effecttype = STUN, blocked = 0, check_protection = 1)
	return 0//The only effect that can hit them atm is flashes and they still directly edit so this works for now

/proc/islinked(mob/living/silicon/robot/bot, mob/living/silicon/ai/ai)
	if(!istype(bot) || !istype(ai))
		return 0
	if (bot.connected_ai == ai)
		return 1
	return 0

// this function shows the health of the AI in the Status panel
// TGPanel
/mob/living/silicon/proc/show_system_integrity()
	if(!src.stat)
		. = "System integrity: [round(vitality() * 100)]%"
	else
		. = "Systems nonfunctional"

// This is a pure virtual function, it should be overwritten by all subclasses
/mob/living/silicon/proc/show_malf_ai()
	return ""

// this function displays the shuttles ETA in the status panel if the shuttle has been called
/mob/living/silicon/proc/show_emergency_shuttle_eta()
	if(SSemergency_shuttle)
		var/eta_status = SSemergency_shuttle.get_status_panel_eta()
		if(eta_status)
			. = "[eta_status]"

// This adds the basic clock, shuttle recall timer, and malf_ai info to all silicon lifeforms
/mob/living/silicon/get_status_tab_items()
	. = ..()
	. += ""
	. += show_emergency_shuttle_eta()
	. += show_system_integrity()
	. += show_malf_ai()

//can't inject synths
/mob/living/silicon/can_inject(mob/user, error_msg, target_zone, ignore_thickness = FALSE, method = INJECT_METHOD_NEEDLE)
	if(error_msg)
		to_chat(user, span_warning("The armoured plating is too tough."))
	return 0

//Silicon mob language procs

/mob/living/silicon/can_speak(datum/language/speaking)
	if(universal_speak)
		return TRUE
	//need speech synthesizer support to vocalize a language
	if(speaking in speech_synthesizer_langs)
		return TRUE
	if(speaking && speaking.flags & INNATE)
		return TRUE
	return FALSE

/mob/living/silicon/add_language(language, can_speak=1)
	var/datum/language/added_language = GLOB.all_languages[language]
	if(!added_language)
		return

	. = ..(language)
	if (can_speak && (added_language in languages) && !(added_language in speech_synthesizer_langs))
		speech_synthesizer_langs += added_language
		return 1

/mob/living/silicon/remove_language(rem_language)
	var/datum/language/removed_language = GLOB.all_languages[rem_language]
	if(!removed_language)
		return

	..(rem_language)
	speech_synthesizer_langs -= removed_language

/mob/living/silicon/check_lang_data()
	. = ""

	if(default_language)
		. += "Current default language: [default_language] - <a href='byond://?src=\ref[src];default_lang=reset'>reset</a><br><br>"

	for(var/datum/language/L in languages)
		if(!(L.flags & NONGLOBAL))
			var/default_str
			if(L == default_language)
				default_str = " - default - <a href='byond://?src=\ref[src];default_lang=reset'>reset</a>"
			else
				default_str = " - <a href='byond://?src=\ref[src];default_lang=\ref[L]'>set default</a>"

			var/synth = (L in speech_synthesizer_langs)
			. += span_bold("[L.name] ([get_language_prefix()][L.key])") + "[synth ? default_str : null]<br>Speech Synthesizer: <i>[synth ? "YES" : "NOT SUPPORTED"]</i><br>[L.desc]<br><br>"

/mob/living/silicon/proc/toggle_sensor_mode() // to make borgs use omni starts here - Tank, clueless bird
	if(sensor_type)
		if(plane_holder)
			//Enable the planes, its basically just AR-Bs
			plane_holder.set_vis(VIS_CH_ID,TRUE)
			plane_holder.set_vis(VIS_CH_WANTED,TRUE)
			plane_holder.set_vis(VIS_CH_IMPLOYAL,TRUE) //antag related so prob not useful but leaving them in
			plane_holder.set_vis(VIS_CH_IMPTRACK,TRUE)
			plane_holder.set_vis(VIS_CH_IMPCHEM,TRUE)
			plane_holder.set_vis(VIS_CH_STATUS_R,TRUE)
			plane_holder.set_vis(VIS_CH_HEALTH_VR,TRUE)
			plane_holder.set_vis(VIS_CH_BACKUP,TRUE) //backup stuff from silicon_vr is here now
			return TRUE

	else
		if(plane_holder)
			//Disable the planes
			plane_holder.set_vis(VIS_CH_ID,FALSE)
			plane_holder.set_vis(VIS_CH_WANTED,FALSE)
			plane_holder.set_vis(VIS_CH_IMPLOYAL,FALSE)
			plane_holder.set_vis(VIS_CH_IMPTRACK,FALSE)
			plane_holder.set_vis(VIS_CH_IMPCHEM,FALSE)
			plane_holder.set_vis(VIS_CH_STATUS_R,FALSE)
			plane_holder.set_vis(VIS_CH_HEALTH_VR,FALSE)
			plane_holder.set_vis(VIS_CH_BACKUP,FALSE)
			return FALSE

//hudmode = sensor_type //This is checked in examine.dm on humans, so they can see medical/security records depending on mode
//I made it work like omnis with records by adding stuff to examine.dm
// ends here

/mob/living/silicon/verb/pose()
	set name = "Set Pose"
	set desc = "Sets a description which will be shown when someone examines you."
	set category = VERB_CAT_IC_SETTINGS

	// A cancel answers "": the pose is cleared.
	open_request(src, /datum/prompt/text, PROC_REF(silicon_pose_entered), answerer = src, title = "Pose", question = "This is [src]. It is...", timeout = 0)

/mob/living/silicon/proc/silicon_pose_entered(datum/act/request/A)
	var/text = A.answer ? A.answer.value : ""
	pose = text ? strip_html_simple(text) : null

/mob/living/silicon/verb/set_flavor()
	set name = "Set Flavour Text"
	set desc = "Sets an extended description of your character's features."
	set category = VERB_CAT_IC_SETTINGS

	open_request(src, /datum/prompt/text, PROC_REF(silicon_flavor_entered), answerer = src, title = "Flavour text", question = "Please enter your new flavour text.", default = flavor_text, multiline = TRUE, timeout = 0)

/mob/living/silicon/proc/silicon_flavor_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_flavortext = strip_html_simple(A.answer.value)
	if(new_flavortext)
		flavor_text = new_flavortext

/mob/living/silicon/binarycheck()
	return 1

/mob/living/silicon/ex_act(severity)
	if(..())
		return
	if(!blinded)
		flash_eyes()

	var/explosion_shift = factor(BF_EXPLOSION_SHIFT)
	if(explosion_shift)
		severity = CLAMP(severity + explosion_shift, 1, 4)

	severity = round(severity)

	if(severity > 3)
		return

	switch(severity)
		if(1.0)
			if (stat != 2)
				injure(INJURY_BLUNT, 100, null, null, 0, null, INJURE_SILENT)
				injure(INJURY_BURN, 100, null, null, 0, null, INJURE_SILENT)
				if(!anchored)
					gib()
		if(2.0)
			if (stat != 2)
				injure(INJURY_BLUNT, 60, null, null, 0, null, INJURE_SILENT)
				injure(INJURY_BURN, 60, null, null, 0, null, INJURE_SILENT)
		if(3.0)
			if (stat != 2)
				injure(INJURY_BLUNT, 30, null, null, 0, null, INJURE_SILENT)

/mob/living/silicon/proc/receive_alarm(datum/alarm_handler/alarm_handler, datum/alarm/alarm, was_raised)
	if(!next_alarm_notice)
		COOLDOWN_START(src, next_alarm_notice, (10 SECONDS))
	if(alarm.hidden)
		return
	if(alarm.origin() && !(get_z(alarm.origin()) in using_map.get_map_levels(get_z(src), TRUE, om_range = DEFAULT_OVERMAP_RANGE)))
		return

	var/datum/silicon_alarm_queue/Q = LAZYACCESS(queued_alarms, "[alarm_handler.type]")
	if(!Q)
		return
	if(was_raised)
		// Raised alarms are always set
		rel_remove(Q, nameof(Q.cleared), alarm)
		rel_add(Q, nameof(Q.raised), alarm)
	else
		// Alarms that were raised but then cleared before the next notice are instead removed
		if((alarm in Q.raised) || (alarm in Q.cleared))
			rel_remove(Q, nameof(Q.raised), alarm)
			rel_remove(Q, nameof(Q.cleared), alarm)
		// And alarms that have only been cleared thus far are set as such
		else
			rel_add(Q, nameof(Q.cleared), alarm)

/mob/living/silicon/proc/process_queued_alarms()
	if(next_alarm_notice && (COOLDOWN_FINISHED(src, next_alarm_notice)))
		next_alarm_notice = 0

		var/alarm_raised = 0
		for(var/key in queued_alarms)
			var/datum/silicon_alarm_queue/Q = queued_alarms[key]
			var/reported = 0
			for(var/datum/alarm/A in Q.raised)
				alarm_raised = 1
				if(!reported)
					reported = 1
					to_chat(src, span_warning("--- [Q.category] Detected ---"))
				raised_alarm(A)

		for(var/key in queued_alarms)
			var/datum/silicon_alarm_queue/Q = queued_alarms[key]
			var/reported = 0
			for(var/datum/alarm/A in Q.cleared)
				if(!reported)
					reported = 1
					to_chat(src, span_notice("--- [Q.category] Cleared ---"))
				to_chat(src, "\The [A.alarm_name()].")

		if(alarm_raised)
			to_chat(src, span_filter_notice("<A HREF='byond://?src=\ref[src];showalerts=1'>\[Show Alerts\]</A>"))

		for(var/key in queued_alarms)
			var/datum/silicon_alarm_queue/Q = queued_alarms[key]
			rel_clear(Q, nameof(Q.raised))
			rel_clear(Q, nameof(Q.cleared))

/// A silicon's pending alarm notices for one alarm handler: what was raised and what was cleared
/// since the last notice. Owned by the silicon; the alarms themselves belong to their handler.
/datum/silicon_alarm_queue
	var/category
	var/list/raised
	var/list/cleared

/datum/silicon_alarm_queue/New(category)
	..()
	src.category = category

CAPABILITIES(/datum/silicon_alarm_queue)
	ref_many(nameof(raised))
	ref_many(nameof(cleared))

/mob/living/silicon/proc/raised_alarm(datum/alarm/A)
	to_chat(src, span_filter_warning("[A.alarm_name()]!"))

/mob/living/silicon/ai/raised_alarm(datum/alarm/A)
	var/cameratext = ""
	for(var/obj/machinery/camera/C in A.cameras())
		cameratext += "[(cameratext == "")? "" : "|"]<A HREF='byond://?src=\ref[src];switchcamera=\ref[C]'>[C.c_tag]</A>"
	to_chat(src, span_filter_warning("[A.alarm_name()]! ([(cameratext)? cameratext : "No Camera"])"))

/mob/living/silicon/proc/is_traitor()
	return mind && (mind in GLOB.traitors.current_antagonists)

/mob/living/silicon/proc/is_malf()
	return mind && (mind in GLOB.malf.current_antagonists)

/mob/living/silicon/proc/is_malf_or_traitor()
	return is_traitor() || is_malf()

/mob/living/silicon/adjustEarDamage()
	return

/mob/living/silicon/setEarDamage()
	return

/mob/living/silicon/reset_perspective(atom/new_eye)
	. = ..()
	rel_clear(src, nameof(cameraFollow))

/mob/living/silicon/flash_eyes(intensity = FLASH_PROTECTION_MODERATE, override_blindness_check = FALSE, affect_silicon = FALSE, visual = FALSE, type = /atom/movable/screen/fullscreen/flash)
	if(affect_silicon)
		return ..()

/mob/living/silicon/proc/clear_client()
	//Handle job slot/tater cleanup.
	var/job = mind.assigned_role

	SSjob.free_role(job)

	if(mind.objectives.len)
		own_clear(mind, nameof(/datum/mind::objectives), OWN_DELETE)
		mind.special_role = null

	SSantag.clear_antag_roles(mind)

	ghostize(0)
	spent(src)

/mob/living/silicon/has_vision()
	return 0 //NOT REAL EYES

/mob/living/silicon/can_feed()
	return FALSE

// === merged from silicon_vr.dm during hard-fork de-suffix (verified no override-order change) ===
// For handling any custom visibility in borgo sensor modes, like sleeve implants - not needed anymore but leaving anyways - Tank
///mob/living/silicon/toggle_sensor_mode()
//	. = ..()
//	switch(hudmode) // This is set in parent
//		if ("Security")
//			//Disable Medical planes
//			plane_holder?.set_vis(VIS_CH_BACKUP,FALSE)
//
//		if ("Medical")
//			//Enable Medical planes
//			plane_holder?.set_vis(VIS_CH_BACKUP,TRUE)
//
//		if ("Disable")
//			//Disable Medical planes
//			plane_holder?.set_vis(VIS_CH_BACKUP,FALSE)
