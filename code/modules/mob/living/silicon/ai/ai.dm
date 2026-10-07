#define AI_CHECK_WIRELESS 1
#define AI_CHECK_RADIO 2

GLOBAL_LIST_INIT(ai_verbs_default, list(
	// /mob/living/silicon/ai/proc/ai_recall_shuttle,
	/mob/living/silicon/ai/proc/ai_emergency_message,
	/mob/living/silicon/ai/proc/ai_goto_location,
	/mob/living/silicon/ai/proc/ai_remove_location,
	/mob/living/silicon/ai/proc/ai_hologram_change,
	/mob/living/silicon/ai/proc/ai_network_change,
	/mob/living/silicon/ai/proc/ai_statuschange,
	/mob/living/silicon/ai/proc/ai_store_location,
	/mob/living/silicon/ai/proc/control_integrated_radio,
	/mob/living/silicon/ai/proc/pick_icon,
	/mob/living/silicon/ai/proc/sensor_mode,
	/mob/living/silicon/ai/proc/show_laws_verb,
	/mob/living/silicon/ai/proc/toggle_acceleration,
	/mob/living/silicon/ai/proc/toggle_hologram_movement,
	/mob/living/silicon/ai/proc/ai_announcement,
	/mob/living/silicon/ai/proc/ai_call_shuttle,
	/mob/living/silicon/ai/proc/ai_camera_track,
	/mob/living/silicon/ai/proc/ai_camera_list,
	/mob/living/silicon/ai/proc/ai_checklaws,
	/mob/living/silicon/ai/proc/toggle_camera_light,
	/mob/living/silicon/ai/proc/take_image,
	/mob/living/silicon/ai/proc/view_images,
	/mob/living/silicon/ai/proc/delete_images,
	/mob/living/silicon/ai/proc/toggle_multicam_verb,
	/mob/living/silicon/ai/proc/add_multicam_verb
))

//Not sure why this is necessary...
/proc/AutoUpdateAI(obj/subject)
	var/is_in_use = 0
	if (subject!=null)
		for(var/mob/living/silicon/ai/M as anything in REGISTRY_MEMBERS(REGISTRY_AIS))
			if ((M.client && M.check_current_machine(subject)))
				is_in_use = 1
				actor_use(/datum/input_adapter/ai, M, subject)
	return is_in_use

/// Full backup capacitor charge (the old 200-point oxyloss budget).
#define AI_BACKUP_CAPACITY 200

/mob/living/silicon/ai
	name = JOB_AI
	icon = 'icons/mob/AI.dmi'//
	icon_state = "ai"
	anchored = TRUE // -- TLE
	density = TRUE
	status_flags = CANPUSH
	shouldnt_see = list(/mob/observer/eye, /obj/effect/rune)
	var/list/network = list(NETWORK_DEFAULT) // ALLOW(instance_list): d: per-mob network with starting entries, edited at runtime; mobs are few
	var/obj/machinery/camera/camera = null
	var/aiRestorePowerRoutine = 0
	/// Backup capacitor charge, 0..AI_BACKUP_CAPACITY. Drains while the core is
	/// unpowered and recharges on mains/APU power; the AI shuts down at 0.
	var/backup_charge = AI_BACKUP_CAPACITY
	var/viewalerts = 0
	var/icon/holo_icon				//Default is assigned when AI is created.
	var/holo_color = null
	var/list/connected_robots = list() // ALLOW(instance_list): d: per-mob connected_robots, filled at runtime; mobs are few
	var/obj/item/pda/ai/aiPDA = null
	var/obj/item/communicator/aiCommunicator = null
	var/obj/item/multitool/aiMulti = null
	var/obj/item/radio/headset/heads/ai_integrated/aiRadio = null
	var/camera_light_on = 0	//Defines if the AI toggled the light on the camera it's looking through.
	var/datum/trackable/track = null
	var/last_announcement = ""
	var/control_disabled = 0
	var/datum/announcement/priority/announcement
	var/obj/machinery/ai_powersupply/psupply = null // Backwards reference to AI's powersupply object.
	var/hologram_follow = 1 //This is used for the AI eye, to determine if a holopad's hologram should follow it or not.
	var/is_dummy = 0 //Used to prevent dummy AIs from spawning with communicators.
	//NEWMALF VARIABLES
	var/malfunctioning = 0						// Master var that determines if AI is malfunctioning.
	var/datum/malf_hardware/hardware = null		// Installed piece of hardware.
	var/datum/malf_research/research = null		// Malfunction research datum.
	var/obj/machinery/power/apc/hack = null		// APC that is currently being hacked.
	var/list/hacked_apcs = null					// List of all hacked APCs
	var/APU_power = 0							// If set to 1 AI runs on APU power
	var/hacking = 0								// Set to 1 if AI is hacking APC, cyborg, other AI, or running system override.
	var/system_override = 0						// Set to 1 if system override is initiated, 2 if succeeded.
	var/hack_can_fail = 1						// If 0, all abilities have zero chance of failing.
	var/hack_fails = 0							// This increments with each failed hack, and determines the warning message text.
	/// The missing-research error is reported at most every two minutes.
	COOLDOWN_DECLARE(research_error_cooldown)
	var/bombing_core = 0						// Set to 1 if core auto-destruct is activated
	var/bombing_station = 0						// Set to 1 if station nuke auto-destruct is activated
	var/override_CPUStorage = 0					// Bonus/Penalty CPU Storage. For use by admins/testers.
	var/override_CPURate = 0					// Bonus/Penalty CPU generation rate. For use by admins/testers.

	var/datum/ai_icon/selected_sprite			// The selected icon set
	var/custom_sprite  = FALSE					// Whether the selected icon is custom
	var/carded

	// Multicam Vars
	var/multicam_allowed = TRUE
	var/multicam_on = FALSE
	var/atom/movable/screen/movable/pic_in_pic/ai/master_multicam
	var/list/multicam_screens // REL_LIST (multicam.dm)
	var/max_multicams = 6

	can_be_antagged = TRUE

CAPABILITIES(/mob/living/silicon/ai)
	every(PROC_REF(track_interval), then(PROC_REF(ai_track_step)), when = nameof(cameraFollow))
	immune_to(STAT_WEAKENED)
	owns_one(nameof(selected_sprite), on_destroy = ON_DESTROY_PRIVATE_COPY)
	ref_many(nameof(multicam_screens))
	remote_interface()
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(core_blast))))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(emp_shell_disconnect)))
	owns_one(nameof(aiCommunicator), /obj/item/communicator)
	owns_one(nameof(aiPDA), /obj/item/pda/ai)
	owns_one(nameof(aiRadio), /obj/item/radio/headset/heads/ai_integrated)
	owns_one(nameof(announcement), /datum/announcement/priority)
	owns_one(nameof(psupply), /obj/machinery/ai_powersupply)
	owns_one(nameof(research), /datum/malf_research)
	owns_one(nameof(track), /datum/trackable)
	owns_one(nameof(aiMulti), starts = /obj/item/multitool)
	owns_one(nameof(aiCamera), /obj/item/camera/siliconcam, starts = /obj/item/camera/siliconcam/ai_camera)
	op("ai_interaction_card", item(/obj/item/aicard), label("Transfer to card"), then(PROC_REF(ai_interaction_card)))
	param(nameof(laws), /datum/ai_laws, pos = 2)
	param(nameof(brain_at_make), pos = 3, keep = FALSE)
	param(nameof(spawn_safety), pos = 4)
	op("switchcamera", topic("switchcamera", arg("switchcamera", schema_ref(/obj/machinery/camera), optional = TRUE, among = PROC_REF(topic_cameras))), needs(req_self()), then(PROC_REF(topic_switchcamera)))
	op("jumptoholopad", topic("jumptoholopad", arg("jumptoholopad", schema_ref(/obj/machinery/hologram/holopad), optional = TRUE, among = TOPIC_IN_WORLD)), needs(req_self()), then(PROC_REF(topic_jumptoholopad)))
	op("track", topic("track", arg("track", schema_ref(/mob), optional = TRUE, among = TOPIC_IN_MOBS), arg("trackname", schema_text(MAX_NAME_LEN * 2), optional = TRUE)), needs(req_self()), then(PROC_REF(topic_track)))
	op("trackbot", topic("trackbot", arg("trackbot", schema_ref(/mob/living/bot), optional = TRUE, among = TOPIC_IN_MOBS)), needs(req_self()), then(PROC_REF(topic_trackbot)))
	op("open", topic("open", arg("open", schema_ref(/mob), optional = TRUE, among = TOPIC_IN_MOBS)), needs(req_self()), then(PROC_REF(topic_open_door)))

/mob/living/silicon/ai/proc/add_ai_verbs()
	om_grant_each(src, GRANT_VERB, GLOB.ai_verbs_default, src)
	om_grant_each(src, GRANT_VERB, silicon_subsystems, src)

/mob/living/silicon/ai/proc/remove_ai_verbs()
	om_revoke_each(src, GRANT_VERB, GLOB.ai_verbs_default, src)
	om_revoke_each(src, GRANT_VERB, silicon_subsystems, src)

/// The brain an AI is made from (its constructor param, read before its parents' init).
/mob/living/silicon/ai/var/tmp/obj/item/mmi/brain_at_make
/// Made by AIize(): no brain is needed (its constructor param).
/mob/living/silicon/ai/var/spawn_safety = FALSE

// ALLOW(init/INSTANCE_STATE): an AI sets up its announcement, name, radio, laws and languages before its parents' init, and leaves an empty core when made with no brain
/mob/living/silicon/ai/Initialize(mapload)
	var/mob/observer/eye/eyeobj = src?.active_eye()

	rel_set(src, nameof(announcement), new /datum/announcement/priority()) // ALLOW(decl): configured before parent init
	announcement.title = "A.I. Announcement"
	announcement.announcement_type = "A.I. Announcement"
	announcement.newscast = 1

	var/list/possibleNames = GLOB.ai_names

	var/pickedName = null
	while(!pickedName)
		pickedName = pick(GLOB.ai_names)
		for (var/mob/living/silicon/ai/A in REGISTRY_MEMBERS(REGISTRY_MOBS))
			if (A.real_name == pickedName && possibleNames.len > 1) //fixing the theoretically possible infinite loop
				possibleNames -= pickedName
				pickedName = null

	if(!is_dummy)
		rel_set(src, nameof(aiPDA), new/obj/item/pda/ai(src)) // ALLOW(decl): conditional on is_dummy
	SetName(pickedName)
	set_anchored(TRUE)
	canmove = 0
	set_density(TRUE)

	if(!is_dummy)
		rel_set(src, nameof(aiCommunicator), new /obj/item/communicator/integrated(src)) // ALLOW(decl): conditional on is_dummy

	holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holo1"))

	if(!laws)
		rel_set(src, nameof(laws), new using_map.default_law_type) // ALLOW(decl): only when no laws were passed in

	rel_set(src, nameof(aiRadio), new /obj/item/radio/headset/heads/ai_integrated(src)) // ALLOW(decl): wired to common_radio before parent init
	rel_set(src, nameof(common_radio), aiRadio) // an alias of the owned aiRadio
	rel_set(aiRadio, nameof(aiRadio.myAi), src)
	additional_law_channels["Binary"] = "#b"
	additional_law_channels["Holopad"] = ":h"

	if (istype(loc, /turf))
		add_ai_verbs(src)

	//Languages
	add_language(LANGUAGE_ROBOT_TALK, 1)
	add_language(LANGUAGE_GALCOM, 1)
	add_language(LANGUAGE_SOL_COMMON, 1)
	add_language(LANGUAGE_UNATHI, 1)
	add_language(LANGUAGE_SIIK, 1)
	add_language(LANGUAGE_AKHANI, 1)
	add_language(LANGUAGE_SKRELLIAN, 1)
	add_language(LANGUAGE_TRADEBAND, 1)
	add_language(LANGUAGE_GUTTER, 1)
	add_language(LANGUAGE_EAL, 1)
	add_language(LANGUAGE_SCHECHI, 1)
	add_language(LANGUAGE_SIGN, 1)
	add_language(LANGUAGE_ROOTLOCAL, 1)
	add_language(LANGUAGE_TERMINUS, 1)
	add_language(LANGUAGE_ZADDAT, 1)
	add_language(LANGUAGE_BIRDSONG, 1)
	add_language(LANGUAGE_SAGARU, 1)
	add_language(LANGUAGE_CANILUNZT, 1)
	add_language(LANGUAGE_ECUREUILIAN, 1)
	add_language(LANGUAGE_DAEMON, 1)
	add_language(LANGUAGE_ENOCHIAN, 1)
	add_language(LANGUAGE_DRUDAKAR, 1)
	add_language(LANGUAGE_TAVAN, 1)

	if(!spawn_safety)//Only used by AIize() to successfully spawn an AI.
		if (!brain_at_make)//If there is no player/brain inside.
			registry_join(REGISTRY_EMPTY_AI_CORES, new/obj/structure/AIcore/deactivated(loc))//New empty terminal.
			return INITIALIZE_HINT_QDEL //Delete AI.

		var/datum/mind_host/host = get_mind_host(brain_at_make)
		host?.release_mind(src, "AI core activated")

		on_mob_init()

	. = ..()
	init_id(idcard_type)

	new /obj/machinery/ai_powersupply(src)

	if(CONFIG_GET(flag/allow_ai_shells))
		om_grant(src, GRANT_VERB, /mob/living/silicon/ai/proc/deploy_to_shell_act, verb_source(VERB_SOURCE_CONFIG))

	create_eyeobj()
	if(eyeobj)
		eyeobj.forceMove(src.loc)

/mob/living/silicon/ai/proc/on_mob_init()
	var/init_text = list(span_bold("You are playing the station's AI. The AI cannot move, but can interact with many objects while viewing them (through cameras)."),
							span_bold("To look at other parts of the station, click on yourself to get a camera menu."),
							span_bold("While observing through a camera, you can use most (networked) devices which you can see, such as computers, APCs, intercoms, doors, etc."),
							"To use something, simply click on it.",
							"For department channels, use the following say commands:")
	to_chat(src, span_filter_notice("[jointext(init_text, "<br>")]"))

	var/radio_text = ""
	for(var/i = 1 to common_radio.channels.len)
		var/channel = common_radio.channels[i]
		var/key = get_radio_key_from_channel(channel)
		radio_text += "[key] - [channel]"
		if(i != common_radio.channels.len)
			radio_text += ", "

	to_chat(src,radio_text)

	// Meta Info for AI's. Mostly used for Holograms
	if (client)
		identity().ooc_notes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes)
		identity().ooc_notes_likes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_likes)
		identity().ooc_notes_dislikes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_dislikes)
		identity().ooc_notes_favs = read_preference(/datum/preference/text/living/ooc_notes_favs)
		identity().ooc_notes_maybes = read_preference(/datum/preference/text/living/ooc_notes_maybes)
		identity().ooc_notes_style = read_preference(/datum/preference/toggle/living/ooc_notes_style)
		private_notes = client.prefs.read_preference(/datum/preference/text/living/private_notes)

	if (GLOB.malf && !(mind in GLOB.malf.current_antagonists))
		show_laws()
		to_chat(src, span_filter_notice(span_bold("These laws may be changed by other players, or by you being the traitor.")))

	job = JOB_AI
	setup_icon()

REGISTRY_MEMBERSHIP(/mob/living/silicon/ai, REGISTRY_AIS)

// GLOB.default_ai_icon or one of the shared icon sets (a custom one is only ever held here).

// the AI's eyes go with it: the active one and any other still linked to it (the eye
// create_eyeobj() made before another took over, multicam eyes). Unlinked, they outlived it.
/mob/living/silicon/ai/on_destroy(force)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	QDEL_NULL(eyeobj)
	for(var/mob/observer/eye/other as anything in eyes_list())
		if(!QDELETED(other))
			ended_with(other, src)
	destroy_eyeobj()
	..()

/mob/living/silicon/ai/get_status_tab_items()
	. = ..()
	. += ""
	if(!stat) // Make sure we're not unconscious/dead.
		. += "System integrity: [hardware_integrity()]%"
		. += "Connected synthetics: [connected_robots.len]"
		for(var/mob/living/silicon/robot/R in connected_robots)
			var/robot_status = "Nominal"
			if(R.shell)
				robot_status = "AI SHELL"
			else if(R.stat || !R.client)
				robot_status = "OFFLINE"
			else if(!R.cell || R.cell.charge <= 0)
				robot_status = "DEPOWERED"
			//Name, Health, Battery, Module, Area, and Status! Everything an AI wants to know about its borgies!
			. += "[R.name] | S.Integrity: [round(R.vitality() * 100)]% | Cell: [R.cell ? "[R.cell.charge]/[R.cell.maxcharge]" : "Empty"] | \
			Module: [R.modtype] | Loc: [get_area_name(R, TRUE)] | Status: [robot_status]"
		. += "AI shell beacons detected: [REGISTRY_COUNT(REGISTRY_AI_SHELLS)]" //Count of total AI shells
	else
		. += "Systems nonfunctional"

/mob/living/silicon/ai/proc/setup_icon()
	var/file = file2text("config/custom_sprites.txt")
	var/lines = splittext(file, "\n")

	for(var/line in lines)
	// split & clean up
		var/list/Entry = splittext(line, ":")
		for(var/i = 1 to Entry.len)
			Entry[i] = trim(Entry[i])

		if(Entry.len < 2)
			continue;

		if(Entry[1] == src.ckey && Entry[2] == src.real_name)
			icon = CUSTOM_ITEM_SYNTH
			custom_sprite = TRUE
			proto_set(src, nameof(selected_sprite), new/datum/ai_icon("Custom", "[src.ckey]-ai", "4", "[ckey]-ai-crash", "#FFFFFF", "#FFFFFF", "#FFFFFF")) // the AI's private custom icon
		else
			proto_set(src, nameof(selected_sprite), GLOB.default_ai_icon)
	update_icon()

/mob/living/silicon/ai/pointed(atom/A as mob|obj|turf in view())
	set popup_menu = 0
	set src = usr.contents
	return 0

/mob/living/silicon/ai/SetName(pickedName as text)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	..()
	announcement.announcer = pickedName
	if(eyeobj)
		eyeobj.name = "[pickedName] (AI Eye)"

	// Set ai pda name
	if(aiPDA)
		aiPDA.ownjob = JOB_AI
		aiPDA.owner = pickedName
		aiPDA.name = pickedName + " (" + aiPDA.ownjob + ")"

	if(aiCommunicator)
		aiCommunicator.register_device(src.name)

/*
	The AI Power supply is a dummy object used for powering the AI since only machinery should be using power.
	The alternative was to rewrite a bunch of AI code instead here we are.
*/
/obj/machinery/ai_powersupply
	name="Power Supply"
	active_power_usage=50000 // Station AIs use significant amounts of power. This, when combined with charged SMES should mean AI lasts for 1hr without external power.
	use_power = USE_POWER_ACTIVE
	power_channel = EQUIP
	var/mob/living/silicon/ai/powered_ai = null
	invisibility = INVISIBILITY_MAXIMUM

// ALLOW(init/INSTANCE_STATE): binds to the AI it is made inside and stands where that AI is
/obj/machinery/ai_powersupply/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(powered_ai), loc)
	if(!istype(powered_ai))
		return INITIALIZE_HINT_QDEL
	rel_set(powered_ai, nameof(powered_ai.psupply), src)
	if(istype(powered_ai,/mob/living/silicon/ai/announcer))	//Don't try to get a loc for a nullspace announcer mob, just put it into it
		forceMove(powered_ai)
	else
		forceMove(powered_ai.loc)

	use_power(1) // Just incase we need to wake up the power system.

// Its periodic work: work_step() while it is started (code/library/machine/started_work.dm).
CAPABILITIES(/obj/machinery/ai_powersupply)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(step_start_condition))

/obj/machinery/ai_powersupply/proc/work_step(datum/act/timer/A)
	if(!powered_ai || powered_ai.stat == DEAD)
		spent(src)
		return
	if(powered_ai.psupply != src) // For some reason, the AI has different powersupply object. Delete this one, it's no longer needed.
		spent(src)
		return
	if(powered_ai.APU_power)
		set_use_power(USE_POWER_OFF)
		return
	if(!powered_ai.anchored)
		forceMove(powered_ai.loc)
		set_use_power(USE_POWER_OFF)
		use_power(50000) // Less optimalised but only called if AI is unwrenched. This prevents usage of wrenching as method to keep AI operational without power. Intellicard is for that.
	if(powered_ai.anchored)
		set_use_power(USE_POWER_ACTIVE)

/mob/living/silicon/ai/proc/pick_icon()
	set category = VERB_CAT_AI_SETTINGS
	set name = "Set AI Core Display"
	if(stat || aiRestorePowerRoutine)
		return

	if (!custom_sprite)
		open_request(src, /datum/prompt/choice, PROC_REF(ai_icon_chosen), answerer = src, valid = PROC_REF(ai_icon_askable), title = "AI", question = "Select an icon!", choices = GLOB.ai_icons, timeout = 0)
		return
	update_icon()

/// Re-checked on the answer: the AI is up, powered and has no custom sprite.
/mob/living/silicon/ai/proc/ai_icon_askable(datum/request/R)
	return !(stat || aiRestorePowerRoutine || custom_sprite)

/mob/living/silicon/ai/proc/ai_icon_chosen(datum/act/request/A)
	if(!A.answer)
		return
	proto_set(src, nameof(selected_sprite), A.answer.value)
	update_icon()

/mob/living/silicon/ai/var/announcement_cooldown = 0
/mob/living/silicon/ai/proc/ai_announcement()
	set category = VERB_CAT_AI_STATION_COMMANDS
	set name = "Make Station Announcement"
	if(check_unable(AI_CHECK_WIRELESS | AI_CHECK_RADIO))
		return

	if(!COOLDOWN_FINISHED(src, announcement_cooldown))
		to_chat(src, span_filter_notice("Please allow one minute to pass between announcements."))
		return
	open_request(src, /datum/prompt/text, PROC_REF(ai_announcement_entered), answerer = src, valid = PROC_REF(ai_announcement_askable), title = "A.I. Announcement", question = "Please write a message to announce to the station crew.", timeout = 0)

/// Re-checked on the answer: off cooldown, with wireless and radio.
/mob/living/silicon/ai/proc/ai_announcement_askable(datum/request/R)
	return COOLDOWN_FINISHED(src, announcement_cooldown) && !check_unable(AI_CHECK_WIRELESS | AI_CHECK_RADIO)

/mob/living/silicon/ai/proc/ai_announcement_entered(datum/act/request/A)
	if(!A.answer)
		return
	announcement.Announce(A.answer.value)
	COOLDOWN_START(src, announcement_cooldown, 1 MINUTE)

/mob/living/silicon/ai/proc/ai_call_shuttle()
	set category = VERB_CAT_AI_STATION_COMMANDS
	set name = "Call Emergency Shuttle"
	if(check_unable(AI_CHECK_WIRELESS))
		return

	open_request(src, /datum/prompt/yes_no, PROC_REF(ai_call_shuttle_confirmed), answerer = src, valid = PROC_REF(ai_command_askable), title = "Confirm Shuttle Call", question = "Are you sure you want to call the shuttle?", timeout = 0)

/// An AI station command's "are you sure?" is re-checked on the answer: the AI still has wireless.
/mob/living/silicon/ai/proc/ai_command_askable(datum/request/R)
	return !check_unable(AI_CHECK_WIRELESS)

/mob/living/silicon/ai/proc/ai_call_shuttle_confirmed(datum/act/request/A)
	if(!A.answer)
		return
	if(A.answer.value)
		call_shuttle_proc(src)

	// hack to display shuttle timer
	if(SSemergency_shuttle.online())
		post_status(src, "shuttle", user = src)

/mob/living/silicon/ai/proc/ai_recall_shuttle()
	set category = VERB_CAT_AI_STATION_COMMANDS
	set name = "Recall Emergency Shuttle"

	if(check_unable(AI_CHECK_WIRELESS))
		return

	open_request(src, /datum/prompt/yes_no, PROC_REF(ai_recall_shuttle_confirmed), answerer = src, valid = PROC_REF(ai_command_askable), title = "Confirm Shuttle Recall", question = "Are you sure you want to recall the shuttle?", timeout = 0)

/mob/living/silicon/ai/proc/ai_recall_shuttle_confirmed(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	cancel_call_proc(src)

/mob/living/silicon/ai/var/emergency_message_cooldown = 0

/mob/living/silicon/ai/proc/ai_emergency_message()
	set category = VERB_CAT_AI_STATION_COMMANDS
	set name = "Send Emergency Message"

	if(check_unable(AI_CHECK_WIRELESS))
		return
	if(!COOLDOWN_FINISHED(src, emergency_message_cooldown))
		to_chat(src, span_warning("Arrays recycling. Please stand by."))
		return
	open_request(src, /datum/prompt/text, PROC_REF(ai_emergency_message_entered), answerer = src, valid = PROC_REF(ai_emergency_message_askable), title = "To abort, send an empty message.", question = "Please choose a message to transmit to [using_map.boss_short] via quantum entanglement.  Please be aware that this process is very expensive, and abuse will lead to... termination.  Transmission does not guarantee a response. There is a 30 second delay before you may send another message, be clear, full and concise.", timeout = 0)

/// Re-checked on the answer: off cooldown, with wireless.
/mob/living/silicon/ai/proc/ai_emergency_message_askable(datum/request/R)
	return COOLDOWN_FINISHED(src, emergency_message_cooldown) && !check_unable(AI_CHECK_WIRELESS)

/mob/living/silicon/ai/proc/ai_emergency_message_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/input = A.answer.value
	CentCom_announce(input, src)
	to_chat(src, span_notice("Message transmitted."))
	log_game("[key_name(src)] has made an IA [using_map.boss_short] announcement: [input]")
	COOLDOWN_START(src, emergency_message_cooldown, 30 SECONDS)

/mob/living/silicon/ai/restrained()
	return 0

/mob/living/silicon/ai/proc/emp_shell_disconnect(datum/act/A)
	disconnect_shell("Disconnected from remote shell due to ionic interfe%*@$^___")
	if (prob(30))
		view_core()


/// TOPIC_REF source: the camera network.
/mob/living/silicon/ai/proc/topic_cameras()
	return REGISTRY_MEMBERS(REGISTRY_CAMERAS)

// These links work only for the AI itself (others still reach the rows every mob has).
/mob/living/silicon/ai/proc/topic_switchcamera(datum/act/op/A, href_switchcamera)
	switchCamera(href_switchcamera)
	return TRUE

/mob/living/silicon/ai/proc/topic_jumptoholopad(datum/act/op/A, href_jumptoholopad)
	var/obj/machinery/hologram/holopad/H = href_jumptoholopad
	if(stat == CONSCIOUS)
		if(H)
			actor_use(/datum/input_adapter/ai, src, H) //may as well recycle
		else
			to_chat(src, span_notice("Unable to locate the holopad."))
	return TRUE

/mob/living/silicon/ai/proc/topic_track(datum/act/op/A, href_track, href_trackname)
	var/mob/target = href_track
	var/trackname = html_decode(href_trackname)
	var/mob/living/carbon/human/H = target
	if(target && (!istype(H) || trackname == H.get_face_name()))
		ai_actual_track(target)
	else
		to_chat(src, span_filter_warning("[span_red("System error. Cannot locate [trackname].")]"))
	return TRUE

/mob/living/silicon/ai/proc/topic_trackbot(datum/act/op/A, href_trackbot)
	var/mob/living/bot/target = href_trackbot
	if(target)
		ai_actual_track(target)
	else
		to_chat(src, span_warning("Target is not on or near any active cameras on the station."))
	return TRUE

/mob/living/silicon/ai/proc/topic_open_door(datum/act/op/A, href_open)
	var/mob/target = href_open
	if(target)
		open_nearest_door(target)
	return TRUE

/mob/living/silicon/ai/proc/camera_visibility(mob/observer/eye/aiEye/moved_eye)
	GLOB.cameranet.visibility(moved_eye, client, src?.eyes_list())

/mob/living/silicon/ai/forceMove(atom/destination, direction, movetime)
	. = ..()
	if(.)
		end_multicam()

/mob/living/silicon/ai/reset_perspective(atom/new_eye)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(camera)
		camera.set_light(0)
	if(istype(new_eye,/obj/machinery/camera))
		rel_set(src, nameof(camera), new_eye)
	if(new_eye != GLOB.ai_camera_room_landmark)
		end_multicam()
	. = ..()
	if(.)
		if(!new_eye && isturf(loc) && eyeobj)
			end_multicam()
			reset_perspective(eyeobj)
	if(istype(new_eye,/obj/machinery/camera))
		if(camera_light_on)
			new_eye.set_light(AI_CAMERA_LUMINOSITY)
		else
			new_eye.set_light(0)

/mob/living/silicon/ai/proc/switchCamera(obj/machinery/camera/C)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if (!C || stat == DEAD) //C.can_use())
		return 0

	if(!eyeobj)
		view_core()
		return
	// ok, we're alive, camera is good and in our network...
	eyeobj.setLoc(get_turf(C))

	return 1

/mob/living/silicon/ai/cancel_camera()
	set category = VERB_CAT_AI_CAMERA_CONTROL
	set name = "Cancel Camera View"
	view_core()

//Replaces /mob/living/silicon/ai/verb/change_network() in ai.dm & camera.dm
//Adds in /mob/living/silicon/ai/proc/ai_network_change() instead
//Addition by Mord_Sith to define AI's network change ability
/mob/living/silicon/ai/proc/get_camera_network_list()
	if(check_unable())
		return

	var/list/cameralist = new()
	for (var/obj/machinery/camera/C in REGISTRY_MEMBERS(REGISTRY_CAMERAS))
		if(!C.can_use())
			continue
		var/list/tempnetwork = difflist(C.network, GLOB.restricted_camera_networks, 1)
		for(var/i in tempnetwork)
			cameralist[i] = i

	cameralist = sortAssoc(cameralist)
	return cameralist

/mob/living/silicon/ai/proc/ai_network_change(network in get_camera_network_list())
	var/mob/observer/eye/eyeobj = src?.active_eye()
	set category = VERB_CAT_AI_CAMERA_CONTROL
	set name = "Jump To Network"
	unset_machine()

	if(!network)
		return

	if(!eyeobj)
		view_core()
		return

	src.network = network

	for(var/obj/machinery/camera/C in REGISTRY_MEMBERS(REGISTRY_CAMERAS))
		if(!C.can_use())
			continue
		if(network in C.network)
			eyeobj.setLoc(get_turf(C))
			break
	to_chat(src, span_notice("Switched to [network] camera network."))
//End of code by Mord_Sith

/mob/living/silicon/ai/proc/ai_statuschange()
	set category = VERB_CAT_AI_SETTINGS
	set name = "AI Status"

	if(check_unable(AI_CHECK_WIRELESS))
		return

	set_ai_status_displays()
	return

//I am the icon meister. Bow fefore me.	//>fefore
/mob/living/silicon/ai/proc/hologram_from_dummy(mob/living/carbon/human/dummy/dummy)
	dummy.regenerate_icons()
	var/new_holo = getHologramIcon(getCompoundIcon(dummy))
	spent(holo_icon)
	spent(dummy)
	holo_icon = new_holo

/mob/living/silicon/ai/proc/ai_hologram_change()
	set name = "Change Hologram"
	set desc = "Change the default hologram available to AI to something else."
	set category = VERB_CAT_AI_SETTINGS

	if(check_unable())
		return

	open_request(src, /datum/prompt/choice, PROC_REF(hologram_change_chosen), answerer = src, valid = PROC_REF(ai_able_askable), title = "Modify Hologram", question = "Would you like to modify your hologram's model, or color?", choices = list("Model", "Color", "Cancel"), buttons = TRUE, timeout = 0)

/// An AI settings choice is re-checked on the answer: the AI is able to act (check_unable()).
/mob/living/silicon/ai/proc/ai_able_askable(datum/request/R)
	return !check_unable()

/mob/living/silicon/ai/proc/hologram_change_chosen(datum/act/request/A)
	if(!A.answer)
		return
	switch(A.answer.value)
		if("Color")
			open_request(src, /datum/prompt/color, PROC_REF(hologram_color_chosen), answerer = src, title = "Hologram Color", question = "Choose a color:", default = holo_color, timeout = 0)
		if("Model")
			open_request(src, /datum/prompt/choice, PROC_REF(hologram_model_kind_chosen), answerer = src, valid = PROC_REF(ai_able_askable), title = "Hologram Selection", question = "Would you like to select a hologram based on a (visible) crew member, switch to unique avatar, or load your character from your character slot?", choices = list("Crew Member", "Unique", "My Character"), buttons = TRUE, timeout = 0)

/mob/living/silicon/ai/proc/hologram_color_chosen(datum/act/request/A)
	if(!A.answer)
		return
	holo_color = A.answer.value

/mob/living/silicon/ai/proc/hologram_model_kind_chosen(datum/act/request/A)
	if(!A.answer)
		return
	switch(A.answer.value)
		if("Crew Member") //A seeable crew member (or a dog)
			var/list/targets = trackable_mobs()
			if(targets.len)
				open_request(src, /datum/prompt/choice, PROC_REF(hologram_crew_chosen), answerer = src, title = "Hologram Choice", question = "Select a crew member:", choices = targets, timeout = 0) //The definition of "crew member" is a little loose...
			else
				tgui_alert_async(src, "No suitable records found. Aborting.")

		if("My Character") //Loaded character slot
			if(!client || !client.prefs) return
			var/mob/living/carbon/human/dummy/dummy = new ()
			//This doesn't include custom_items because that's ... hard.
			client.prefs.dress_preview_mob(dummy)
			after(src, 1 SECOND, PROC_REF(hologram_from_dummy), with = list(dummy)) //Strange bug in preview code? Without this, certain things won't show up. Yay race conditions?

		else //A premade from the dmi
			var/icon_list[] = list(
				"default",
				"floating face",
				"singularity",
				"drone",
				"carp",
				"spider",
				"bear",
				"fox", // Fox holograms!
				"fox, alt", // Fox holograms!
				"syndifox", // Fox holograms!
				"slime",
				"ian",
				"runtime",
				"poly",
				"pun pun",
				"male human",
				"female human",
				"male unathi",
				"female unathi",
				"male tajaran",
				"female tajaran",
				"male tesharii",
				"female tesharii",
				"male skrell",
				"female skrell"
			)
			open_request(src, /datum/prompt/choice, PROC_REF(hologram_premade_chosen), answerer = src, title = "Hologram Choice", question = "Please select a hologram:", choices = icon_list, timeout = 0)

/mob/living/silicon/ai/proc/hologram_crew_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/input = A.answer.value
	//This is torture, I know. If someone knows a better way...
	var/list/targets = trackable_mobs()
	if(!targets[input])
		return
	var/new_holo = getHologramIcon(getCompoundIcon(targets[input]))
	spent(holo_icon)
	holo_icon = new_holo

/mob/living/silicon/ai/proc/hologram_premade_chosen(datum/act/request/A)
	if(!A.answer)
		return
	spent(holo_icon)
	switch(A.answer.value)
		if("default")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holo1"))
		if("floating face")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holo2"))
		if("singularity")
			holo_icon = getHologramIcon(icon('icons/obj/singularity.dmi',"singularity_s1"))
		if("drone")
			holo_icon = getHologramIcon(icon('icons/mob/animal.dmi',"drone"))
		if("carp")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holo4"))
		if("spider")
			holo_icon = getHologramIcon(icon('icons/mob/animal.dmi',"nurse"))
		if("bear")
			holo_icon = getHologramIcon(icon('icons/mob/animal.dmi',"brownbear"))
		if("slime")
			holo_icon = getHologramIcon(icon('icons/mob/slimes.dmi',"cerulean adult slime"))
		if("ian")
			holo_icon = getHologramIcon(icon('icons/mob/pets.dmi',"corgi"))
		if("runtime")
			holo_icon = getHologramIcon(icon('icons/mob/pets.dmi',"cat"))
		if("poly")
			holo_icon = getHologramIcon(icon('icons/mob/birds.dmi',"poly-flap"))
		if("pun pun")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"punpun"))
		if("male human")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holohumm"))
		if("female human")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holohumf"))
		if("male unathi")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holounam"))
		if("female unathi")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holounaf"))
		if("male tajaran")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holotajm"))
		if("female tajaran")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holotajf"))
		if("male tesharii")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holotesm"))
		if("female tesharii")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holotesf"))
		if("male skrell")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holoskrm"))
		if("female skrell")
			holo_icon = getHologramIcon(icon('icons/mob/AI.dmi',"holoskrf"))
		if("fox") // Fox holograms!
			holo_icon = getHologramIcon(icon('icons/mob/pets.dmi',"fox")) // Fox holograms!
		if("syndifox") // Fox holograms!
			holo_icon = getHologramIcon(icon('icons/mob/pets.dmi',"syndifox")) // Fox holograms!
		if("fox, alt") // Fox holograms!
			holo_icon = getHologramIcon(icon('icons/mob/pets.dmi',"fox2")) // Fox holograms!

//Toggles the luminosity and applies it by re-entereing the camera.
/mob/living/silicon/ai/proc/toggle_camera_light()
	set name = "Toggle Camera Light"
	set desc = "Toggles the light on the camera the AI is looking through."
	set category = VERB_CAT_AI_CAMERA_CONTROL
	if(check_unable())
		return

	camera_light_on = !camera_light_on
	to_chat(src, span_filter_notice("Camera lights [camera_light_on ? "activated" : "deactivated"]."))
	if(!camera_light_on)
		if(camera)
			camera.set_light(0)
			rel_clear(src, nameof(camera))
	else
		lightNearbyCamera()

// Handled camera lighting, when toggled.
// It will get the nearest camera from the eyeobj, lighting it.

/mob/living/silicon/ai/proc/lightNearbyCamera()
	var/mob/observer/eye/eyeobj = src?.active_eye()
	if(camera_light_on && camera_light_on < world.timeofday)
		if(src.camera)
			var/obj/machinery/camera/camera = near_range_camera(eyeobj)
			if(camera && src.camera != camera)
				src.camera.set_light(0)
				if(!camera.light_disabled)
					rel_set(src, nameof(camera), camera)
					src.camera.set_light(AI_CAMERA_LUMINOSITY)
				else
					rel_clear(src, nameof(camera))
			else if(isnull(camera))
				src.camera.set_light(0)
				rel_clear(src, nameof(camera))
		else
			var/obj/machinery/camera/camera = near_range_camera(eyeobj)
			if(camera && !camera.light_disabled)
				rel_set(src, nameof(camera), camera)
				src.camera.set_light(AI_CAMERA_LUMINOSITY)
		camera_light_on = world.timeofday + 1 * 20 // Update the light every 2 seconds.

/// Old attackby: an intelliCard pulls the AI in.
/mob/living/silicon/ai/proc/ai_interaction_card(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/aicard/card = A.held
	card.grab_ai(src, user)
	return TRUE

/mob/living/silicon/ai/wrench_act(mob/user, obj/item/tool)
	if(user == deployed_shell)
		to_chat(user, span_notice("The shell's subsystems resist your efforts to tamper with your bolts."))
		return ITEM_INTERACT_BLOCKING
	use_tool(user, tool, src, delay = 4 SECONDS, quality = TOOL_WRENCH, volume = 50, start_others = "\The [user] starts to [anchored ? "unbolt" : "bolt"] \the [src] [anchored ? "from" : "to"] the plating...", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user), on_fail = PROC_REF(wrench_act_tool_failed), fail_args = list(user))
	return ITEM_INTERACT_SUCCESS

/mob/living/silicon/ai/proc/wrench_act_tool_done(mob/user)
	set_anchored(!anchored)
	act_message(user, src, others = span_notice("%U% finishes [anchored ? "fastening down" : "unfastening"] %T%!"))
	return ITEM_INTERACT_SUCCESS

/mob/living/silicon/ai/proc/wrench_act_tool_failed(mob/user)
	act_message(user, src, others = span_notice("%U% decides not to [anchored ? "unbolt" : "bolt"] %T%."))
	return ITEM_INTERACT_BLOCKING

/mob/living/silicon/ai/proc/control_integrated_radio()
	set name = "Radio Settings"
	set desc = "Allows you to change settings of your radio."
	set category = VERB_CAT_AI_SETTINGS

	if(check_unable(AI_CHECK_RADIO))
		return

	to_chat(src, span_filter_notice("Accessing Subspace Transceiver control..."))
	if (src.aiRadio)
		src.aiRadio.interact(src)

/mob/living/silicon/ai/proc/sensor_mode()
	set name = "Toggle Sensor Augmentation"
	set category = VERB_CAT_AI_SETTINGS
	set desc = "Augment visual feed with internal sensor overlays"
	sensor_type = !sensor_type
	to_chat(src, "You [sensor_type ? "enable" : "disable"] your sensors.")
	toggle_sensor_mode()

/mob/living/silicon/ai/proc/toggle_hologram_movement()
	set name = "Toggle Hologram Movement"
	set category = VERB_CAT_AI_SETTINGS
	set desc = "Toggles hologram movement based on moving with your virtual eye."

	hologram_follow = !hologram_follow
	// Required to stop movement because we use walk_to(wards) in hologram.dm
	if(holo)
		var/obj/effect/overlay/aiholo/hologram = LAZYACCESS(holo.masters, src)
		walk(hologram, 0)
	to_chat(src, span_filter_notice("Your hologram will [hologram_follow ? "follow" : "no longer follow"] you now."))

/mob/living/silicon/ai/proc/check_unable(flags = NONE, feedback = 1)
	if(stat == DEAD)
		if(feedback)
			to_chat(src, span_warning("You are dead!"))
		return 1

	if(aiRestorePowerRoutine)
		if(feedback)
			to_chat(src, span_warning("You lack power!"))
		return 1

	if((flags & AI_CHECK_WIRELESS) && src.control_disabled)
		if(feedback)
			to_chat(src, span_warning("Wireless control is disabled!"))
		return 1
	if((flags & AI_CHECK_RADIO) && src.aiRadio.disabledAi)
		if(feedback)
			to_chat(src, span_warning("System Error - Transceiver Disabled!"))
		return 1
	return 0

/mob/living/silicon/ai/proc/is_in_chassis()
	return istype(loc, /turf)

/mob/living/silicon/ai/proc/open_nearest_door(mob/living/target) // Rykka ports AI opening doors
	if(!istype(target))
		return

	if(target && ai_actual_track(target))
		var/obj/machinery/door/airlock/A = null

		var/dist = -1
		for(var/obj/machinery/door/airlock/D in range(3, target))
			if(!D.density)
				continue

			var/curr_dist = get_dist(D, target)

			if(dist < 0)
				dist = curr_dist
				A = D
			else if(dist > curr_dist)
				dist = curr_dist
				A = D

		if(istype(A))
			var/datum/prompt/yes_no/ai_door_request/asked = open_request(src, /datum/prompt/yes_no/ai_door_request, PROC_REF(open_door_request_answered), answerer = src, title = "Doorknob_v2a.exe", question = "Do you want to open \the [A] for [target]?", timeout = 0)
			if(asked)
				rel_set(asked, nameof(asked.door), A)
				rel_set(asked, nameof(asked.requester), target)
		else
			to_chat(src, span_warning("Unable to locate an airlock near [target]."))

	else
		to_chat(src, span_warning("Target is not on or near any active cameras on the station."))

/// Someone asks the AI to open a door. The answer proc runs on no too (it reports the denial).
/datum/prompt/yes_no/ai_door_request
	var/obj/machinery/door/airlock/door
	var/mob/living/requester

CAPABILITIES(/datum/prompt/yes_no/ai_door_request)
	ref_one(nameof(door), /obj/machinery/door/airlock)
	ref_one(nameof(requester), /mob/living)

/mob/living/silicon/ai/proc/open_door_request_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/yes_no/ai_door_request/asked = A.request
	var/obj/machinery/door/airlock/door = asked.door
	var/mob/living/target = asked.requester
	if(!door || !target)
		return
	if(A.answer.value && !check_unable(AI_CHECK_WIRELESS))
		perform_op(src, door, "open_close", null, ORIGIN_MENU, AUTH_REMOTE_ACCESS)
		to_chat(src, span_notice("You open \the [door] for [target]."))
	else
		to_chat(src, span_warning("You deny the request."))

/// A direct blast destroys the core outright; weaker ones go through the silicon ladder.
/mob/living/silicon/ai/proc/core_blast(datum/act/hit/explosion/A)
	if(A.packet.severity != 1)
		return HOOK_DECLINE
	destroyed(src, null, "explosion")
	return TRUE

DECLARE_APPEARANCE_PROC(/mob/living/silicon/ai, TYPE_PROC_REF(/atom, appearance_overlays), list())
/mob/living/silicon/ai/appearance_overlays()
	. = list()
	if(!selected_sprite)
		proto_set(src, nameof(selected_sprite), GLOB.default_ai_icon)

	if(stat == DEAD)
		icon_state = selected_sprite.dead_icon
		set_light(3, 1, selected_sprite.dead_light)
	else if(aiRestorePowerRoutine)
		icon_state = selected_sprite.nopower_icon
		set_light(1, 1, selected_sprite.nopower_light)
	else
		icon_state = selected_sprite.alive_icon
		set_light(1, 1, selected_sprite.alive_light)

// Pass lying down or getting up to our pet human, if we're in a rig.
/mob/living/silicon/ai/lay_down()
	set name = "Rest"
	set category = VERB_CAT_IC_GAME

	set_resting(0)
	var/obj/item/rig/rig = src.get_rig()
	if(rig)
		rig.force_rest(src)

/mob/living/silicon/ai/is_sentient()
	// AI cores don't store what brain was used to build them so we're just gonna assume they can think to some degree.
	// If that is ever fixed please update this proc.
	return TRUE

/mob/living/silicon/ai/handle_track(message, verb = "says", mob/speaker = null, speaker_name, hard_to_hear)
	if(hard_to_hear)
		return

	var/jobname // the mob's "job"
	var/mob/living/carbon/human/impersonating //The crew member being impersonated, if any.
	var/changed_voice

	if(ishuman(speaker))
		var/mob/living/carbon/human/H = speaker

		if(H.get_equipped_item(SLOT_ID_MASK) && istype(H.get_equipped_item(SLOT_ID_MASK),/obj/item/clothing/mask/gas/voice))
			changed_voice = 1
			var/list/impersonated = new()
			var/mob/living/carbon/human/I = impersonated[speaker_name]

			if(!I)
				for(var/mob/living/carbon/human/M in REGISTRY_MEMBERS(REGISTRY_MOBS))
					if(M.real_name == speaker_name)
						I = M
						impersonated[speaker_name] = I
						break

			// If I's display name is currently different from the voice name and using an agent ID then don't impersonate
			// as this would allow the AI to track I and realize the mismatch.
			if(I && !(I.name != speaker_name && I.get_equipped_item(SLOT_ID_ID) && istype(I.get_equipped_item(SLOT_ID_ID),/obj/item/card/id/syndicate)))
				impersonating = I
				jobname = impersonating.get_assignment()
			else
				jobname = "Unknown"
		else
			jobname = H.get_assignment()

	else if(iscarbon(speaker)) // Nonhuman carbon mob
		jobname = "No id"
	else if(isAI(speaker))
		jobname = JOB_AI
	else if(isrobot(speaker))
		jobname = JOB_CYBORG
	else if(ispAI(speaker))
		jobname = "Personal AI"
	else
		jobname = "Unknown"

	var/track = ""
	if(changed_voice)  // They have a fake name
		if(impersonating) // And we found a mob with that name above, track them instead
			track = "<a href='byond://?src=\ref[src];trackname=[html_encode(speaker_name)];track=\ref[impersonating]'>[speaker_name] ([jobname])</a>"
			track += "<a href='byond://?src=\ref[src];trackname=[html_encode(speaker_name)];open=\ref[impersonating]'>\[OPEN\]</a>" // Rykka ports AI opening doors
		else // We couldn't find a mob with their fake name, don't track at all
			track = "[speaker_name] ([jobname])"
	else // Not faking their name
		if(isbot(speaker)) // It's a bot, and no fake name! (That'd be kinda weird.) :p
			track = "<a href='byond://?src=\ref[src];trackbot=\ref[speaker]'>[speaker_name] ([jobname])</a>"
		else // It's not a bot, and no fake name!
			track = "<a href='byond://?src=\ref[src];trackname=[html_encode(speaker_name)];track=\ref[speaker]'>[speaker_name] ([jobname])</a>"
			track += "<a href='byond://?src=\ref[src];trackname=[html_encode(speaker_name)];open=\ref[speaker]'>\[OPEN\]</a>" // Rykka ports AI opening doors

	return track // Feed variable back to AI

/mob/living/silicon/ai/proc/relay_speech(mob/living/M, list/message_pieces, verb)
	var/list/combined = combine_message(message_pieces, verb, M)
	var/message = combined["formatted"]
	var/name_used = M.GetVoice()
	//This communication is imperfect because the holopad "filters" voices and is only designed to connect to the master only.
	var/rendered = span_game(span_say(span_italics("Relayed Speech: [span_name(name_used)] [message]")))
	show_message(rendered, 2)

/mob/living/silicon/ai/proc/toggle_multicam_verb()
	set name = "Toggle Multicam"
	set category = VERB_CAT_AI_CAMERA_CONTROL
	toggle_multicam()

/mob/living/silicon/ai/proc/add_multicam_verb()
	set name = "Add Multicam Viewport"
	set category = VERB_CAT_AI_CAMERA_CONTROL
	drop_new_multicam()

//Special subtype kept around for global announcements
/mob/living/silicon/ai/announcer
	is_dummy = 1

/mob/living/silicon/ai/announcer/Initialize(mapload)
	var/mob/observer/eye/eyeobj = src?.active_eye()
	. = ..()
	QDEL_NULL(eyeobj)

/// The announcer is in no mob registry.
/mob/living/silicon/ai/announcer/skips_registry(registry_id)
	return TRUE

/mob/living/silicon/ai/announcer
	life_set = LIFE_SET_DELIST

/mob/living/silicon/ai/announcer/life_delist(datum/seq_frame/life/F)
	spent(src?.active_eye())

#undef AI_CHECK_WIRELESS
#undef AI_CHECK_RADIO

/mob/AIize(move = TRUE)
	. = ..()
	add_language(LANGUAGE_BIRDSONG,		1)
	add_language(LANGUAGE_SAGARU,		1)
	add_language(LANGUAGE_CANILUNZT,	1)
	add_language(LANGUAGE_ECUREUILIAN,	1)
	add_language(LANGUAGE_DAEMON,		1)
	add_language(LANGUAGE_ENOCHIAN,		1)
	add_language(LANGUAGE_DRUDAKAR,		1)
	add_language(LANGUAGE_TAVAN,		1)

/// Whether its work starts at initialization (started_work(starts =)).
/obj/machinery/ai_powersupply/step_start_condition()
	return TRUE // made when an AI needs power

/// A short system operation (an emergency forcefield) is over.
/mob/living/silicon/ai/proc/hacking_done()
	hacking = 0

// A registered AI icon, or the AI's private custom icon (copy-on-write).
