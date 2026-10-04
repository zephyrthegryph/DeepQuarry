/datum/pai_software
	// Name for the software. This is used as the button text when buying or opening/toggling the software
	var/name = "pAI software module"
	// RAM cost; pAIs start with 100 RAM, spending it on programs
	var/ram_cost = 0
	// ID for the software. This must be unique
	var/id = ""
	// Whether this software is a toggle or not
	// Toggled software should override toggle() and is_active()
	// Non-toggled software should override on_ui_interact() and Topic()
	var/toggle = 1
	// Whether pAIs should automatically receive this module at no cost
	var/default = 0

/datum/pai_software/proc/toggle(mob/living/silicon/pai/user)
	return

/datum/pai_software/proc/is_active(mob/living/silicon/pai/user)
	return 0

DECLARE_UI_STATE(/datum/pai_software, GLOB.tgui_always_state)

/datum/pai_software/tgui_status(mob/user)
	if(!ispAI(user))
		return STATUS_CLOSE
	return ..()

/datum/pai_software/directives
	name = "Directives"
	ram_cost = 0
	id = "directives"
	toggle = 0
	default = 1

DECLARE_UI(/datum/pai_software/directives, "pAIDirectives")

UI_DATA_REPLACE(/datum/pai_software/directives, "merge:ui_data_datum_pai_software_directives{master:unknown,dna:unknown,prime:text,supplemental:unknown}")

/// The computed part of /datum/pai_software/directives's window data (declared on its UI_DATA row).
/datum/pai_software/directives/proc/ui_data_datum_pai_software_directives(mob/living/silicon/pai/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["master"] = user.master
	data["dna"] = user.master_dna
	data["prime"] = user.pai_law0
	data["supplemental"] = user.pai_laws

	return data

/datum/pai_software/directives/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/mob/living/silicon/pai/P = ui.user
	if(!istype(P))
		return FALSE
	return TRUE

UI_ACT(/datum/pai_software/directives, "getdna", ui_act_getdna)
UI_ACT_PROC(/datum/pai_software/directives, ui_act_getdna)
	var/mob/living/silicon/pai/P = ui.user
	var/mob/living/M = P.loc

	var/count = 0
	// Find the carrier
	while(!isliving(M))
		if(!M || !M.loc || count > 6)
			//For a runtime where M ends up in nullspace (similar to bluespace but less colourful)
			to_chat(src, span_infoplain("You are not being carried by anyone!"))
			return 0
		M = M.loc
		count++

	// Check the carrier
	var/datum/prompt/yes_no/pai_dna_sample/sample = open_request(src, /datum/prompt/yes_no/pai_dna_sample, PROC_REF(dna_sample_answered), answerer = M, title = "[P] Check DNA", question = "[P] is requesting a DNA sample from you. Will you allow it to confirm your identity?", timeout = 0)
	if(sample)
		rel_set(sample, nameof(sample.pai), P)
	return TRUE

/// A pAI asks its carrier for a DNA sample. The answer proc runs on no too (the pAI is told).
/datum/prompt/yes_no/pai_dna_sample
	var/mob/living/silicon/pai/pai

CAPABILITIES(/datum/prompt/yes_no/pai_dna_sample)
	ref_one(nameof(pai), /mob/living/silicon/pai)

/datum/pai_software/directives/proc/dna_sample_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/yes_no/pai_dna_sample/sample = A.request
	var/mob/living/M = A.request.answerer
	var/mob/living/silicon/pai/P = sample.pai
	if(!P || !M)
		return
	if(A.answer.answer_value)
		var/turf/T = get_turf(P.loc)
		for (var/mob/v in viewers(T))
			v.show_message(span_notice("[M] presses [M.p_their()] thumb against [P]."), 3, span_notice("[P] makes a sharp clicking sound as it extracts DNA material from [M]."), 2)
		var/datum/dna/dna = M.dna
		to_chat(P, span_infoplain(span_red("<h3>[M]'s UE string : [dna.unique_enzymes]</h3>")))
		if(dna.unique_enzymes == P.master_dna)
			to_chat(P, span_infoplain(span_bold("DNA is a match to stored Master DNA.")))
		else
			to_chat(P, span_infoplain(span_bold("DNA does not match stored Master DNA.")))
	else
		to_chat(P, span_infoplain("[M] does not seem like [M.p_theyre()] going to provide a DNA sample willingly."))
	return TRUE

/datum/pai_software/radio_config
	name = "Radio Configuration"
	ram_cost = 0
	id = "radio"
	toggle = 0
	default = 1

/datum/pai_software/radio_config/ui_redirect(mob/living/silicon/pai/user)
	return user.radio

/datum/pai_software/crew_manifest
	name = "Crew Manifest"
	ram_cost = 0
	id = "manifest"
	toggle = 0
	default = 1		//Comes with the communicator already, also why not

DECLARE_UI(/datum/pai_software/crew_manifest, "CrewManifest")

UI_DATA(/datum/pai_software/crew_manifest, "merge:ui_data_datum_pai_software_crew_manifest{manifest:unknown}")

/// The computed part of /datum/pai_software/crew_manifest's window data (declared on its UI_DATA row).
/datum/pai_software/crew_manifest/proc/ui_data_datum_pai_software_crew_manifest(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	if(GLOB.data_core)
		GLOB.data_core.get_manifest_list()
	data["manifest"] = GLOB.PDA_Manifest
	return data

/datum/pai_software/messenger
	name = "Digital Messenger"
	ram_cost = 0
	id = "messenger"
	toggle = 0
	default = 1		//Can already be accessed through verbs, and also why not

/datum/pai_software/messenger/ui_redirect(mob/living/silicon/pai/user)
	return user.pda

/datum/pai_software/med_records
	name = "Medical Records"
	ram_cost = 15
	id = "med_records"
	toggle = 0

DECLARE_UI(/datum/pai_software/med_records, "pAIMedrecords")

UI_DATA(/datum/pai_software/med_records, "merge:ui_data_datum_pai_software_med_records{records:list,general:text,medical:text,could_not_find:num}")

/// The computed part of /datum/pai_software/med_records's window data (declared on its UI_DATA row).
/datum/pai_software/med_records/proc/ui_data_datum_pai_software_med_records(mob/living/silicon/pai/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/records = list()
	for(var/datum/data/record/general in sortRecord(GLOB.data_core.general))
		var/list/record = list()
		record["name"] = general.fields["name"]
		record["ref"] = "\ref[general]"
		records.Add(list(record))

	data["records"] = records

	var/datum/data/record/G = user.medicalActive1
	var/datum/data/record/M = user.medicalActive2
	data["general"] = G ? G.fields : null
	data["medical"] = M ? M.fields : null
	data["could_not_find"] = user.medical_cannotfind

	return data

/datum/pai_software/med_records/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/mob/living/silicon/pai/P = ui.user
	if(!istype(P))
		return FALSE
	return TRUE

UI_ACT(/datum/pai_software/med_records, "select", ui_act_select, UI_ARG_REF("select", null, /datum/data/record))
UI_ACT_PROC(/datum/pai_software/med_records, ui_act_select)
	var/mob/living/silicon/pai/P = ui.user
	var/datum/data/record/record = params["select"]
	if(record)
		var/datum/data/record/R = record
		var/datum/data/record/M = null
		if (!( GLOB.data_core.general.Find(R) ))
			P.medical_cannotfind = 1
		else
			P.medical_cannotfind = 0
			for(var/datum/data/record/E in GLOB.data_core.medical)
				if ((E.fields["name"] == R.fields["name"] || E.fields["id"] == R.fields["id"]))
					M = E
			rel_set(P, nameof(/mob/living/silicon/pai::medicalActive1), R)
			rel_set(P, nameof(/mob/living/silicon/pai::medicalActive2), M)
	else
		P.medical_cannotfind = 1
	return 1

/datum/pai_software/sec_records
	name = "Security Records"
	ram_cost = 15
	id = "sec_records"
	toggle = 0

DECLARE_UI(/datum/pai_software/sec_records, "pAISecrecords")

UI_DATA(/datum/pai_software/sec_records, "merge:ui_data_datum_pai_software_sec_records{records:list,general:text,security:text,could_not_find:num}")

/// The computed part of /datum/pai_software/sec_records's window data (declared on its UI_DATA row).
/datum/pai_software/sec_records/proc/ui_data_datum_pai_software_sec_records(mob/living/silicon/pai/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/list/records = list()
	for(var/datum/data/record/general in sortRecord(GLOB.data_core.general))
		var/list/record = list()
		record["name"] = general.fields["name"]
		record["ref"] = "\ref[general]"
		records.Add(list(record))

	data["records"] = records

	var/datum/data/record/G = user.securityActive1
	var/datum/data/record/S = user.securityActive2
	data["general"] = G ? G.fields : null
	data["security"] = S ? S.fields : null
	data["could_not_find"] = user.security_cannotfind

	return data

/datum/pai_software/sec_records/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/mob/living/silicon/pai/P = ui.user
	if(!istype(P))
		return FALSE
	return TRUE

UI_ACT(/datum/pai_software/sec_records, "select", ui_act_select, UI_ARG_REF("select", null, /datum/data/record))
UI_ACT_PROC(/datum/pai_software/sec_records, ui_act_select)
	var/mob/living/silicon/pai/P = ui.user
	var/datum/data/record/record = params["select"]
	if(record)
		var/datum/data/record/R = record
		var/datum/data/record/S = null
		if (!( GLOB.data_core.general.Find(R) ))
			rel_clear(P, nameof(/mob/living/silicon/pai::securityActive1))
			rel_clear(P, nameof(/mob/living/silicon/pai::securityActive2))
			P.security_cannotfind = 1
		else
			P.security_cannotfind = 0
			for(var/datum/data/record/E in GLOB.data_core.security)
				if ((E.fields["name"] == R.fields["name"] || E.fields["id"] == R.fields["id"]))
					S = E
			rel_set(P, nameof(/mob/living/silicon/pai::securityActive1), R)
			rel_set(P, nameof(/mob/living/silicon/pai::securityActive2), S)
	else
		rel_clear(P, nameof(/mob/living/silicon/pai::securityActive1))
		rel_clear(P, nameof(/mob/living/silicon/pai::securityActive2))
		P.security_cannotfind = 1
	return TRUE

/datum/pai_software/door_jack
	name = "Door Jack"
	ram_cost = 30
	id = "door_jack"
	toggle = 0

DECLARE_UI(/datum/pai_software/door_jack, "pAIDoorjack", UI_TITLE("Door Jack"))

UI_DATA(/datum/pai_software/door_jack, "merge:ui_data_datum_pai_software_door_jack{cable:bool,machine:unknown,inprogress:bool,progress_a:num,progress_b:num,aborted:num}")

/// The computed part of /datum/pai_software/door_jack's window data (declared on its UI_DATA row).
/datum/pai_software/door_jack/proc/ui_data_datum_pai_software_door_jack(mob/living/silicon/pai/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	data["cable"] = user.cable != null
	data["machine"] = !!user.cable?.machine()
	data["inprogress"] = user.hackdoor != null
	data["progress_a"] = round(user.hackprogress / 10)
	data["progress_b"] = user.hackprogress % 10
	data["aborted"] = user.hack_aborted

	return data

/datum/pai_software/door_jack/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/mob/living/silicon/pai/P = ui.user
	if(!istype(P))
		return FALSE
	return TRUE

UI_ACT(/datum/pai_software/door_jack, "jack", ui_act_jack)
UI_ACT_PROC(/datum/pai_software/door_jack, ui_act_jack)
	var/mob/living/silicon/pai/P = ui.user
	if(P.cable && P.cable.machine())
		rel_set(P, nameof(/mob/living/silicon/pai::hackdoor), P.cable.machine())
		P.hackloop()
	return 1

UI_ACT(/datum/pai_software/door_jack, "cancel", ui_act_cancel)
UI_ACT_PROC(/datum/pai_software/door_jack, ui_act_cancel)
	var/mob/living/silicon/pai/P = ui.user
	rel_clear(P, nameof(/mob/living/silicon/pai::hackdoor))
	return 1

UI_ACT(/datum/pai_software/door_jack, "cable", ui_act_cable)
UI_ACT_PROC(/datum/pai_software/door_jack, ui_act_cable)
	var/mob/living/silicon/pai/P = ui.user
	var/turf/T = get_turf(P)
	P.hack_aborted = 0
	rel_set(P, nameof(/obj/machinery/cablelayer::cable), new /obj/item/pai_cable(T))
	for(var/mob/M in viewers(T))
		M.show_message(span_warning("A port on [P] opens to reveal [P.cable], which promptly falls to the floor."), 3,
						span_warning("You hear the soft click of something light and hard falling to the ground."), 2)
	return 1

/mob/living/silicon/pai/proc/hackloop()
	var/turf/T = get_turf(src)
	for(var/mob/living/silicon/ai/AI in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(T.loc)
			to_chat(AI, span_bolddanger("Network Alert: Brute-force encryption crack in progress in [T.loc]."))
		else
			to_chat(AI, span_bolddanger("Network Alert: Brute-force encryption crack in progress. Unable to pinpoint location."))
	var/obj/machinery/door/D = cable.machine()
	if(!istype(D))
		hack_aborted = 1
		hackprogress = 0
		rel_clear(cable, nameof(cable.machine))
		rel_clear(src, nameof(hackdoor))
		return
	hack_tick()

/// DECLARE_REPEAT while hackdoor is set: one second of brute-forcing the door.
/mob/living/silicon/pai/proc/hack_tick()
	if(cable && cable.machine() == hackdoor && get_dist(src, hackdoor) <= 1)
		hackprogress = min(hackprogress+rand(1, 20), 1000)
	else
		hack_aborted = 1
		hackprogress = 0
		rel_clear(src, nameof(hackdoor))
		return REPEAT_STOP
	if(hackprogress >= 1000)
		hackprogress = 0
		hackdoor.open()
		rel_clear(cable, nameof(cable.machine))
		rel_clear(src, nameof(hackdoor))
		return REPEAT_STOP

/datum/pai_software/atmosphere_sensor
	name = "Atmosphere Sensor"
	ram_cost = 5
	id = "atmos_sense"
	toggle = 0

DECLARE_UI(/datum/pai_software/atmosphere_sensor, "pAIAtmos")

UI_DATA(/datum/pai_software/atmosphere_sensor, "merge:ui_data_datum_pai_software_atmosphere_sensor{aircontents:unknown}")

/// The computed part of /datum/pai_software/atmosphere_sensor's window data (declared on its UI_DATA row).
/datum/pai_software/atmosphere_sensor/proc/ui_data_datum_pai_software_atmosphere_sensor(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/turf/location = get_turf(user)
	data["aircontents"] = get_gas_mixture_default_scan_data(location?.return_air())
	return data

/datum/pai_software/pai_hud
	name = "AR HUD"
	ram_cost = 30
	id = "ar_hud"

/datum/pai_software/pai_hud/toggle(mob/living/silicon/pai/user)
	user.paiHUD = !user.paiHUD
	user.plane_holder.set_vis(VIS_CH_ID,user.paiHUD)
	user.plane_holder.set_vis(VIS_CH_WANTED,user.paiHUD)
	user.plane_holder.set_vis(VIS_CH_IMPTRACK,user.paiHUD)
	user.plane_holder.set_vis(VIS_CH_IMPCHEM,user.paiHUD)
	user.plane_holder.set_vis(VIS_CH_STATUS_R,user.paiHUD)
	user.plane_holder.set_vis(VIS_CH_HEALTH_VR,user.paiHUD)
	user.plane_holder.set_vis(VIS_CH_BACKUP,user.paiHUD) //backup stuff from silicon_vr is here now
	user.plane_holder.set_vis(VIS_AUGMENTED,user.paiHUD)

/datum/pai_software/pai_hud/is_active(mob/living/silicon/pai/user)
	return user.paiHUD

/datum/pai_software/translator
	name = "Universal Translator"
	ram_cost = 35
	id = "translator"
	/// Languages the translator offers. A `/datum/pai_software/translator`
	/// instance is a single GLOBAL_LIST_EMPTY(pai_software_by_key) singleton
	/// shared by every pAI, so this must stay a read-only candidate list --
	/// per-pai state (what was actually granted) lives on the pai mob itself,
	/// in `translator_added_languages`.
	var/static/list/candidate_languages = list(
		LANGUAGE_UNATHI, LANGUAGE_SIIK, LANGUAGE_AKHANI, LANGUAGE_SKRELLIAN,
		LANGUAGE_ZADDAT, LANGUAGE_SCHECHI, LANGUAGE_DRUDAKAR, LANGUAGE_SLAVIC,
		LANGUAGE_BIRDSONG, LANGUAGE_SAGARU, LANGUAGE_CANILUNZT, LANGUAGE_ECUREUILIAN,
		LANGUAGE_DAEMON, LANGUAGE_ENOCHIAN, LANGUAGE_VESPINAE, LANGUAGE_SPACER,
		LANGUAGE_TAVAN, LANGUAGE_ECHOSONG, LANGUAGE_ROOTLOCAL, LANGUAGE_VOX,
		LANGUAGE_MINBUS, LANGUAGE_ALAI, LANGUAGE_PROMETHEAN, LANGUAGE_GIBBERISH,
		LANGUAGE_MOUSE, LANGUAGE_ANIMAL, LANGUAGE_TEPPI
	)

/datum/pai_software/translator/toggle(mob/living/silicon/pai/user)
	// 	Sol Common, Tradeband, Terminus and Gutter are added with New() and are therefore the current default, always active languages
	user.translator_on = !user.translator_on
	if(user.translator_on)
		// Only track (and later remove) languages the pai didn't already
		// know -- a pai that natively knows one of these must keep it after
		// toggling the translator off.
		for(var/language in candidate_languages)
			if(user.add_language(language))
				LAZYADD(user.translator_added_languages, language)
	else
		for(var/language in user.translator_added_languages)
			user.remove_language(language)
		user.translator_added_languages = null

/datum/pai_software/translator/is_active(mob/living/silicon/pai/user)
	return user.translator_on

/datum/pai_software/signaller
	name = "Remote Signaler"
	ram_cost = 5
	id = "signaller"
	toggle = 0

DECLARE_UI(/datum/pai_software/signaller, "Signaler", UI_TITLE("Signaler"))

UI_DATA(/datum/pai_software/signaller, "merge:ui_data_datum_pai_software_signaller{frequency:num,minFrequency:num,maxFrequency:num,code:num}")

/// The computed part of /datum/pai_software/signaller's window data (declared on its UI_DATA row).
/datum/pai_software/signaller/proc/ui_data_datum_pai_software_signaller(mob/living/silicon/pai/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	var/obj/item/radio/integrated/signal/R = user.sradio

	data["frequency"] = R.frequency
	data["minFrequency"] = RADIO_LOW_FREQ
	data["maxFrequency"] = RADIO_HIGH_FREQ
	data["code"] = R.code

	return data

UI_ACT(/datum/pai_software/signaller, "signal", ui_act_signal)
UI_ACT_PROC(/datum/pai_software/signaller, ui_act_signal)
	var/mob/living/silicon/pai/pai = ui.user
	if(!istype(pai))
		return
	var/obj/item/radio/integrated/signal/R = pai.sradio
	R.send_signal("ACTIVATE")
	for(var/mob/O in hearers(1, R.loc))
		O.show_message("[icon2html(R,O.client)] *beep* *beep*", 3, "*beep* *beep*", 2)

UI_ACT(/datum/pai_software/signaller, "freq", ui_act_freq, UI_ARG_NUM("freq"))
UI_ACT_PROC(/datum/pai_software/signaller, ui_act_freq)
	var/mob/living/silicon/pai/pai = ui.user
	if(!istype(pai))
		return
	var/obj/item/radio/integrated/signal/R = pai.sradio
	var/frequency = unformat_frequency(params["freq"])
	frequency = sanitize_frequency(frequency, RADIO_LOW_FREQ, RADIO_HIGH_FREQ)
	R.set_frequency(frequency)
	. = TRUE

UI_ACT(/datum/pai_software/signaller, "code", ui_act_code, UI_ARG_NUM("code", 1, 100))
UI_ACT_PROC(/datum/pai_software/signaller, ui_act_code)
	var/mob/living/silicon/pai/pai = ui.user
	if(!istype(pai))
		return
	var/obj/item/radio/integrated/signal/R = pai.sradio
	R.code = round(params["code"])
	. = TRUE

UI_ACT(/datum/pai_software/signaller, "reset", ui_act_reset, UI_ARG_TEXT("reset"))
UI_ACT_PROC(/datum/pai_software/signaller, ui_act_reset)
	var/mob/living/silicon/pai/pai = ui.user
	if(!istype(pai))
		return
	var/obj/item/radio/integrated/signal/R = pai.sradio
	if(params["reset"] == "freq")
		R.set_frequency(initial(R.frequency))
	else
		R.code = initial(R.code)
	. = TRUE

/datum/pai_software/deathalarm
	name = "Death Alarm"
	ram_cost = 25
	id = "death_alarm"

/datum/pai_software/deathalarm/toggle(mob/living/silicon/pai/user)
	user.paiDA = !user.paiDA

/datum/pai_software/deathalarm/is_active(mob/living/silicon/pai/user)
	return user.paiDA
