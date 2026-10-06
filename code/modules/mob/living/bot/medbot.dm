// Medbot Info

#define MEDBOT_PANIC_NONE	0
#define MEDBOT_PANIC_LOW	15
#define MEDBOT_PANIC_MED	35
#define MEDBOT_PANIC_HIGH	55
#define MEDBOT_PANIC_FUCK	70
#define MEDBOT_PANIC_ENDING	90
#define MEDBOT_PANIC_END	100

/mob/living/bot/medbot
	name = "Medibot"
	desc = "A little medical robot. He looks somewhat underwhelmed."
	icon_state = "medibot0"
	req_one_access = list(ACCESS_ROBOTICS, ACCESS_MEDICAL)
	botcard_access = list(ACCESS_MEDICAL, ACCESS_MORGUE, ACCESS_SURGERY, ACCESS_CHEMISTRY, ACCESS_VIROLOGY, ACCESS_GENETICS)
	max_frustration = 7

	var/skin = null //Set to "tox", "ointment" or "o2" for the other two firstaid kits.

	//AI vars
	COOLDOWN_DECLARE(newpatient_speak_cooldown)
	var/vocal = 1

	//Healing vars
	var/obj/item/reagent_containers/glass/reagent_glass = null //Can be set to draw from this for reagents.
	var/injection_amount = 15 //How much reagent do we inject at a time?
	/// Treat when automated triage reports a demand at least this urgent
	/// (_dq_band_rank: 1 minor .. 4 critical).
	var/min_urgency = 1
	var/use_beaker = 0 //Use reagents in beaker instead of default treatment agents.
	var/treatment_emag = REAGENT_ID_TOXIN
	var/declare_treatment = 0 //When attempting to treat a patient, should it notify everyone wearing medhuds?

	// Are we tipped over?
	var/is_tipped = FALSE
	//How panicked we are about being tipped over (why would you do this?)
	var/tipped_status = MEDBOT_PANIC_NONE
	//The name we got when we were tipped
	var/tipper_name
	//The last time we were tipped/righted and said a voice line, to avoid spam
	COOLDOWN_DECLARE(tipping_voice_cooldown)

/mob/living/bot/medbot/mysterious
	name = "\improper Mysterious Medibot"
	desc = "International Medibot of mystery."
	skin = "bezerk"

/// Reagent ids the internal synthesizer can make. The medbot injects whichever
/// best answers the patient's treatment demand.
TYPE_TABLE_DECLARE(/mob/living/bot/medbot, synthesized_reagents, list(REAGENT_ID_TRICORDRAZINE))

TYPE_TABLE(/mob/living/bot/medbot/mysterious, synthesized_reagents, list(REAGENT_ID_BICARIDINE, REAGENT_ID_DERMALINE, REAGENT_ID_DEXALIN, REAGENT_ID_ANTITOXIN, REAGENT_ID_TRICORDRAZINE))

/mob/living/bot/medbot/handleIdle()
	if(is_tipped) // Don't handle idle things if we're incapacitated!
		return

	if(vocal && prob(1))
		var/message_options = list(
			"Radar, put a mask on!" = SFX_VOICE_MEDBOT_MRADAR,
			"There's always a catch, and it's the best there is." = SFX_VOICE_MEDBOT_MCATCH,
			"I knew it, I should've been a plastic surgeon." = SFX_VOICE_MEDBOT_MSURGEON,
			"What kind of medbay is this? Everyone's dropping like flies." = SFX_VOICE_MEDBOT_MFLIES,
			"Delicious!" = SFX_VOICE_MEDBOT_MDELICIOUS
			)
		var/message = pick(message_options)
		say(message)
		playsound(src, message_options[message], 50, 0)

/mob/living/bot/medbot/handleAdjacentTarget()
	if(is_tipped) // Don't handle targets if we're incapacitated!
		return

	UnarmedAttack(target)

/mob/living/bot/medbot/handlePanic()	// Speed modification based on alert level.
	. = 0
	switch(get_security_level())
		if("green")
			. = 0

		if("yellow")
			. = 0

		if("violet")
			. = 1

		if("orange")
			. = 0

		if("blue")
			. = 1

		if("red")
			. = 2

		if("delta")
			. = 2

	return .

/mob/living/bot/medbot/lookForTargets()
	if(is_tipped) // Don't look for targets if we're incapacitated!
		return

	for(var/mob/living/carbon/human/H in view(7, src)) // Time to find a patient!
		if(confirmTarget(H))
			rel_set(src, nameof(target), H)
			if(COOLDOWN_FINISHED(src, newpatient_speak_cooldown))
				if(vocal)
					var/message_options = list(
						"Hey, [H.name]! Hold on, I'm coming." = SFX_VOICE_MEDBOT_MCOMING,
						"Wait [H.name]! I want to help!" = SFX_VOICE_MEDBOT_MHELP,
						"[H.name], you appear to be injured!" = SFX_VOICE_MEDBOT_MINJURED
						)
					var/message = pick(message_options)
					say(message)
					playsound(src, message_options[message], 50, 0)
				automatic_custom_emote(VISIBLE_MESSAGE, "points at [H.name].")
				COOLDOWN_START(src, newpatient_speak_cooldown, 30 SECONDS)
			break

/mob/living/bot/medbot/UnarmedAttack(mob/living/carbon/human/H)
	if(!..())
		return

	if(!on)
		return

	if(!istype(H))
		return

	if(task_busy(src))
		return

	var/t = confirmTarget(H)
	if(!t)
		return

	act_message(src, H, others = span_warning("%U% is trying to inject %T%!"))
	if(declare_treatment)
		var/area/location = get_area(src)
		GLOB.global_announcer.autosay("[src] is treating <b>[H]</b> in <b>[location]</b>", "[src]", "Medical")
	bot_work(3 SECONDS, H, PROC_REF(UnarmedAttack_medbot_done), list(H, t))

	if(H.stat == DEAD) // This is down here because this proc won't be called again due to losing a target because of parent AI loop.
		rel_clear(src, nameof(target))
		if(vocal)
			var/death_messages = list(
				"No! Stay with me!" = SFX_VOICE_MEDBOT_MNO,
				"Live, damnit! LIVE!" = SFX_VOICE_MEDBOT_MLIVE,
				"I... I've never lost a patient before. Not today, I mean." = SFX_VOICE_MEDBOT_MLOST
				)
			var/message = pick(death_messages)
			say(message)
			playsound(src, death_messages[message], 50, 0)

	// This is down here for the same reason as above.
	else
		t = confirmTarget(H)
		if(!t)
			rel_clear(src, nameof(target))
			if(vocal)
				var/possible_messages = list(
					"All patched up!" = SFX_VOICE_MEDBOT_MPATCHEDUP,
					"An apple a day keeps me away." = SFX_VOICE_MEDBOT_MAPPLE,
					"Feel better soon!" = SFX_VOICE_MEDBOT_MFEELBETTER
					)
				var/message = pick(possible_messages)
				say(message)
				playsound(src, possible_messages[message], 50, 0)

/mob/living/bot/medbot/proc/UnarmedAttack_medbot_done(mob/living/carbon/human/H, t)
	if(!emagged && use_beaker && reagent_glass?.reagents.has_reagent(t))
		reagent_glass.reagents.trans_id_to(H, t, injection_amount)
	else
		H.reagents.add_reagent(t, injection_amount)
	log_game("MEDBOT: [src] injected [key_name(H)] with [injection_amount]u of [t].")
	act_message(src, H, others = span_warning("%U% injects %T% with the syringe!"))
	if(SScontracts)
		emit_contract_event(CONTRACT_EVENT_AUTOMATION_TASK_COMPLETED, list(
			"department" = DEPARTMENT_SYNTHETIC,
			"bot_id" = REF(src),
			"task_kind" = "medical_assistance",
			"target_id" = SScontracts.subject_identity(H)?.id,
			"successful" = TRUE,
			"work_units" = injection_amount,
			"detail" = "[src] completed an autonomous treatment for [H].",
		), "automation:[REF(src)]:medical:[REF(H)]:[world.time]", src, null, H)

/mob/living/bot/medbot/update_icons()
	cut_overlays()
	if(skin)
		add_overlay("medskin_[skin]")
	if(task_busy(src))
		icon_state = "medibots"
	else
		icon_state = "medibot[on]"

EXTEND_INTERACTIONS(/mob/living/bot/medbot, \
	INTERACT_INSERT(/obj/item/reagent_containers/glass, PROC_REF(medbot_interaction_item), "Insert beaker", REQ_FIELD_NOT("locked", "the panel is locked"), REQ_FIELD_NOT("reagent_glass")), \
	INTERACT_HAND_UNGATED_AS(I_HELP, "Right or open controls", PROC_REF(medbot_interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_DISARM, "Tip over", PROC_REF(medbot_interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_GRAB, "Open controls", PROC_REF(medbot_interaction_hand)), \
	INTERACT_HAND_UNGATED_AS(I_HURT, "Open controls", PROC_REF(medbot_interaction_hand)))

/// Old attack_hand (no gate, no default touch): disarm tips it, help rights it, else open the controls.
/mob/living/bot/medbot/proc/medbot_interaction_hand(mob/living/carbon/human/H, obj/item/held, datum/interaction/interaction)
	. = TRUE
	if(istype(H) && interaction.stance == I_DISARM && !is_tipped)
		act_message(H, src, MSG_SELF(span_warning("You begin tipping over %T%...")), MSG_OTHERS(span_danger("%U% begins tipping over %T%.")))

		if(COOLDOWN_FINISHED(src, tipping_voice_cooldown))
			COOLDOWN_START(src, tipping_voice_cooldown, 15 SECONDS)// message for tipping happens when we start interacting, message for righting comes after finishing
			var/list/messagevoice = list("Hey, wait..." = SFX_VOICE_MEDBOT_HEY_WAIT,"Please don't..." = SFX_VOICE_MEDBOT_PLEASE_DONT,"I trusted you..." = SFX_VOICE_MEDBOT_I_TRUSTED_YOU, "Nooo..." = SFX_VOICE_MEDBOT_NOOO, "Oh fuck-" = SFX_VOICE_MEDBOT_OH_FUCK)
			var/message = pick(messagevoice)
			say(message)
			playsound(src, messagevoice[message], 70, FALSE)

		task_timed(H, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_medbot_done), done_args = list(H))

	else if(istype(H) && interaction.stance == I_HELP && is_tipped)
		act_message(H, src, MSG_SELF(span_notice("You begin righting %T%...")), MSG_OTHERS(span_notice("%U% begins righting %T%.")))
		task_timed(H, 3 SECONDS, target = src, receiver = src, on_done = PROC_REF(attack_hand_medbot_done2), done_args = list(H))
	else
		tgui_interact(H)

/mob/living/bot/medbot/proc/attack_hand_medbot_done(mob/living/carbon/human/H)
	tip_over(H)
/mob/living/bot/medbot/proc/attack_hand_medbot_done2(mob/living/carbon/human/H)
	set_right(H)

// The hand ops above open the controls (or tip the bot), so the window's own open op answers the menu and a remote user only.
CAPABILITIES(/mob/living/bot/medbot)
	interface("Medbot", input = menu())
	op("power", ui_act("power"), then(PROC_REF(ui_act_power)))
	op("adj_urgency", ui_act("adj_urgency", arg("val", num())), then(PROC_REF(ui_act_adj_urgency)))
	op("adj_inject", ui_act("adj_inject", arg("val", num(MEDBOT_MIN_INJECTION, MEDBOT_MAX_INJECTION))), then(PROC_REF(ui_act_adj_inject)))
	op("use_beaker", ui_act("use_beaker"), then(PROC_REF(ui_act_use_beaker)))
	op("eject", ui_act("eject"), then(PROC_REF(ui_act_eject)))
	op("togglevoice", ui_act("togglevoice"), then(PROC_REF(ui_act_togglevoice)))
	op("declaretreatment", ui_act("declaretreatment"), then(PROC_REF(ui_act_declaretreatment)))

/// The window's data: the bot's state, the beaker, and the settings for whoever may see them (a silicon, or anyone while the panel is unlocked).
/mob/living/bot/medbot/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	data["on"] = on
	data["open"] = open
	data["locked"] = locked
	data["beaker"] = FALSE
	if(reagent_glass)
		data["beaker"] = TRUE
		data["beaker_total"] = reagent_glass.reagents.total_volume
		data["beaker_max"] = reagent_glass.reagents.maximum_volume
	data["min_urgency"] = null
	data["urgency_bands"] = list(DIAG_BAND_MINOR, DIAG_BAND_MODERATE, DIAG_BAND_SEVERE, DIAG_BAND_CRITICAL)
	data["injection_amount_min"] = MEDBOT_MIN_INJECTION
	data["injection_amount"] = null
	data["injection_amount_max"] = MEDBOT_MAX_INJECTION
	data["use_beaker"] = null
	data["declare_treatment"] = null
	data["vocal"] = null
	if(!locked || issilicon(user))
		data["min_urgency"] = min_urgency
		data["injection_amount"] = injection_amount
		data["use_beaker"] = use_beaker
		data["declare_treatment"] = declare_treatment
		data["vocal"] = vocal
	return data

/// Old attackby: load a beaker; anything else falls to the bot's item handling.
/mob/living/bot/medbot/proc/medbot_interaction_item(mob/user, obj/item/O, datum/interaction/interaction)

	if(!move_into(src, nameof(src.reagent_glass), O, user))
		return TRUE
	to_chat(user, span_notice("You insert [O]."))
	return TRUE

/mob/living/bot/medbot/proc/ui_act_power(datum/act/op/A)
	. = TRUE
	if(!access_scanner.allowed(A.actor))
		return FALSE
	if(on)
		turn_off()
	else
		turn_on()

/mob/living/bot/medbot/proc/ui_act_adj_urgency(datum/act/op/A, val)
	. = TRUE
	if(locked && !issilicon(A.actor))
		return TRUE
	var/rank = val
	if(isnull(rank))
		return FALSE
	min_urgency = clamp(round(rank), MEDBOT_MIN_URGENCY, MEDBOT_MAX_URGENCY)
	. = TRUE

/mob/living/bot/medbot/proc/ui_act_adj_inject(datum/act/op/A, val)
	. = TRUE
	if(locked && !issilicon(A.actor))
		return TRUE
	injection_amount = val
	. = TRUE

/mob/living/bot/medbot/proc/ui_act_use_beaker(datum/act/op/A)
	. = TRUE
	if(locked && !issilicon(A.actor))
		return TRUE
	use_beaker = !use_beaker
	. = TRUE

/mob/living/bot/medbot/proc/ui_act_eject(datum/act/op/A)
	. = TRUE
	if(locked && !issilicon(A.actor))
		return TRUE
	if(reagent_glass)
		reagent_glass.forceMove(get_turf(src))
		own_take(src, nameof(/mob/living/bot/medbot::reagent_glass))
	. = TRUE

/mob/living/bot/medbot/proc/ui_act_togglevoice(datum/act/op/A)
	. = TRUE
	if(locked && !issilicon(A.actor))
		return TRUE
	vocal = !vocal
	. = TRUE

/mob/living/bot/medbot/proc/ui_act_declaretreatment(datum/act/op/A)
	. = TRUE
	if(locked && !issilicon(A.actor))
		return TRUE
	declare_treatment = !declare_treatment
	. = TRUE

/mob/living/bot/medbot/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	. = ..()
	if(!emagged)
		if(user)
			to_chat(user, span_warning("You short out [src]'s reagent synthesis circuits."))
		act_message(src, null, others = span_warning("%U% buzzes oddly!"))
		flick("medibot_spark", src)
		rel_clear(src, nameof(target))
		task_release_busy(src, "emagged")
		emagged = 1
		set_on(1)
		update_icons()
		. = 1
	rel_add(src, nameof(ignore_list), user)

/mob/living/bot/medbot/explode()
	set_on(0)
	act_message(src, null, others = span_danger("%U% blows apart!"))
	var/turf/Tsec = get_turf(src)

	new /obj/item/storage/firstaid(Tsec)
	new /obj/item/assembly/prox_sensor(Tsec)
	new /obj/item/healthanalyzer(Tsec)
	if (prob(50))
		new /obj/item/robot_parts/l_arm(Tsec)

	if(reagent_glass)
		reagent_glass.forceMove(Tsec)
		own_take(src, nameof(reagent_glass))

	if(emagged && prob(25))
		play_sfx(src, SFX_VOICE_MEDBOT_MINSULT)

	fx_sparks(src, 3)
	return ..()

/mob/living/bot/medbot/handleRegular()
	. = ..()

	if(is_tipped)
		handle_panic()
		return

/mob/living/bot/medbot/proc/tip_over(mob/user)
	play_sfx(src, SFX_MACHINES_WARNING_BUZZER)
	act_message(user, src, MSG_SELF(span_danger("You tip %T% over!")), MSG_OTHERS(span_danger("%U% tips over %T%!")))
	is_tipped = TRUE
	tipper_name = user.name
	var/matrix/mat = transform
	transform = mat.Turn(180)

/mob/living/bot/medbot/proc/set_right(mob/user)
	var/list/messagevoice
	if(user)
		act_message(user, src, MSG_SELF(span_green("You set %T% right-side up!")), MSG_OTHERS(span_notice("%U% sets %T% right-side up!")))
		if(user.name == tipper_name)
			messagevoice = list("I forgive you." = SFX_VOICE_MEDBOT_FORGIVE)
		else
			messagevoice = list("Thank you!" = SFX_VOICE_MEDBOT_THANK_YOU, "You are a good person." = SFX_VOICE_MEDBOT_YOURE_GOOD)
	else
		act_message(src, null, others = span_notice("%U% manages to [pick("writhe", "wriggle", "wiggle")] enough to right itself."))
		messagevoice = list("Fuck you." = SFX_VOICE_MEDBOT_FUCK_YOU, "Your behavior has been reported, have a nice day." = SFX_VOICE_MEDBOT_REPORTED)

	tipper_name = null
	if(COOLDOWN_FINISHED(src, tipping_voice_cooldown))
		COOLDOWN_START(src, tipping_voice_cooldown, 15 SECONDS)
		var/message = pick(messagevoice)
		say(message)
		playsound(src, messagevoice[message], 70)
	tipped_status = MEDBOT_PANIC_NONE
	is_tipped = FALSE
	transform = matrix()

// if someone tipped us over, check whether we should ask for help or just right ourselves eventually
/mob/living/bot/medbot/proc/handle_panic()
	tipped_status++
	var/list/messagevoice
	switch(tipped_status)
		if(MEDBOT_PANIC_LOW)
			messagevoice = list("I require assistance." = SFX_VOICE_MEDBOT_I_REQUIRE_ASST)
		if(MEDBOT_PANIC_MED)
			messagevoice = list("Please put me back." = SFX_VOICE_MEDBOT_PLEASE_PUT_ME_BACK)
		if(MEDBOT_PANIC_HIGH)
			messagevoice = list("Please, I am scared!" = SFX_VOICE_MEDBOT_PLEASE_IM_SCARED)
		if(MEDBOT_PANIC_FUCK)
			messagevoice = list("I don't like this, I need help!" = SFX_VOICE_MEDBOT_DONT_LIKE, "This hurts, my pain is real!" = SFX_VOICE_MEDBOT_PAIN_IS_REAL)
		if(MEDBOT_PANIC_ENDING)
			messagevoice = list("Is this the end?" = SFX_VOICE_MEDBOT_IS_THIS_THE_END, "Nooo!" = SFX_VOICE_MEDBOT_NOOO)
		if(MEDBOT_PANIC_END)
			GLOB.global_announcer.autosay("PSYCH ALERT: Crewmember [tipper_name] recorded displaying antisocial tendencies torturing bots in [get_area(src)]. Please schedule psych evaluation.", "[src]", "Medical")
			set_right() // strong independent medbot


	if(messagevoice)
		var/message = pick(messagevoice)
		say(message)
		playsound(src, messagevoice[message], 70)
	else if(prob(tipped_status * 0.2))
		play_sfx(src, SFX_MACHINES_WARNING_BUZZER, 0.6, extrarange = -2)

/mob/living/bot/medbot/examine(mob/user)
	. = ..()
	if(tipped_status == MEDBOT_PANIC_NONE)
		return

	switch(tipped_status)
		if(MEDBOT_PANIC_NONE to MEDBOT_PANIC_LOW)
			. += "It appears to be tipped over, and is quietly waiting for someone to set it right."
		if(MEDBOT_PANIC_LOW to MEDBOT_PANIC_MED)
			. += "It is tipped over and requesting help."
		if(MEDBOT_PANIC_MED to MEDBOT_PANIC_HIGH)
			. += "They are tipped over and appear visibly distressed." // now we humanize the medbot as a they, not an it
		if(MEDBOT_PANIC_HIGH to MEDBOT_PANIC_FUCK)
			. += span_warning("They are tipped over and visibly panicking!")
		if(MEDBOT_PANIC_FUCK to INFINITY)
			. += span_boldwarning("They are freaking out from being tipped over!")

/mob/living/bot/medbot/confirmTarget(mob/living/carbon/human/H)
	if(!..())
		return 0

	if(H.stat == DEAD) // He's dead, Jim
		return 0

	if(H.suiciding)
		return 0

	if(emagged)
		return treatment_emag

	return choose_treatment(H)

/// What to inject into `H`, decided from automated triage alone: the
/// reagent in the reservoir (the beaker when enabled, then the synthesizer)
/// whose treatment tags best answer the most urgent treatment demand. Null
/// when nothing is demanded urgently enough or nothing in the reservoir helps.
/mob/living/bot/medbot/proc/choose_treatment(mob/living/carbon/human/H)
	var/list/demand = H.treatment_demand(/datum/diagnostic_profile/automation)
	if(demand_urgency(demand) < min_urgency)
		return null
	if(use_beaker && reagent_glass?.reagents.total_volume)
		. = best_reagent_for_demand(demand, reagent_glass.reagents.reagent_list, H)
		if(.)
			return
	return best_reagent_for_demand(demand, TYPE_TABLE_GET(src, synthesized_reagents), H)

/* Construction */

MSG_DEF_SELF(medbot/empty_first, "You need to empty the first aid kit out first.")

// A robot arm (a part, or a robotic arm organ) on an empty kit starts a medibot; on a kit with things in it the kit is to be emptied first; anything
// else goes on to the storage.
CAPABILITIES(/obj/item/storage/firstaid)
	op("add_arm", inputs(item(/obj/item/robot_parts/l_arm), item(/obj/item/robot_parts/r_arm), item(/obj/item/organ/external/arm)),
		when(req(PROC_REF(arm_is_robotic))), label("Add robot arm"),
		needs(req_storage_empty(because = MSG(medbot/empty_first))), then(PROC_REF(add_robot_arm)))
	rolls(nameof(icon_state), PROC_REF(roll_icon_state), when = nameof(icon_variety))

/// A robot arm part, or an arm organ that is robotic.
/obj/item/storage/firstaid/proc/arm_is_robotic(datum/act/op/A)
	var/obj/item/S = A.held
	if(istype(S, /obj/item/robot_parts/l_arm) || istype(S, /obj/item/robot_parts/r_arm))
		return TRUE
	var/obj/item/organ/external/arm/organ_arm = S
	return istype(organ_arm) && organ_arm.robotic == ORGAN_ROBOT

/obj/item/storage/firstaid/proc/add_robot_arm(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/S = A.held
	var/obj/item/firstaid_arm_assembly/assembly = new /obj/item/firstaid_arm_assembly
	if(istype(src, /obj/item/storage/firstaid/fire))
		assembly.skin = "ointment"
	else if(istype(src, /obj/item/storage/firstaid/toxin))
		assembly.skin = "tox"
	else if(istype(src, /obj/item/storage/firstaid/o2))
		assembly.skin = "o2"

	consume(S, user)
	user.put_in_hands(assembly)
	to_chat(user, span_notice("You add the robot arm to the first aid kit."))
	consume(src, user)
	return OP_OK

/obj/item/firstaid_arm_assembly
	name = "first aid/robot arm assembly"
	desc = "A first aid kit with a robot arm permanently grafted to it."
	icon = 'icons/obj/aibots.dmi'
	icon_state = "firstaid_arm"
	var/build_step = 0
	var/created_name = "Medibot" //To preserve the name if it's a unique medbot I guess
	var/skin = null //Same as medbot, set to tox or ointment for the respective kits.
	w_class = ITEMSIZE_NORMAL

DECLARE_APPEARANCE(/obj/item/firstaid_arm_assembly, "skin", list("ointment" = list(APPEARANCE_OVERLAYS = list("kit_skin_ointment")), "tox" = list(APPEARANCE_OVERLAYS = list("kit_skin_tox")), "o2" = list(APPEARANCE_OVERLAYS = list("kit_skin_o2"))))

DECLARE_INTERACTIONS(/obj/item/firstaid_arm_assembly, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/firstaid_arm_assembly/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/pen))
		ask_name_var(user)
	else
		switch(build_step)
			if(0)
				if(istype(W, /obj/item/healthanalyzer))
					user.drop_item()
					consume(W, user)
					build_step++
					to_chat(user, span_notice("You add the health sensor to [src]."))
					name = "First aid/robot arm/health analyzer assembly"
					add_overlay("na_scanner")

			if(1)
				if(isprox(W))
					user.drop_item()
					consume(W, user)
					to_chat(user, span_notice("You complete the Medibot! Beep boop."))
					var/turf/T = get_turf(src)
					var/mob/living/bot/medbot/S = new /mob/living/bot/medbot(T)
					S.skin = skin
					S.name = created_name
					consume(src, user)
	return INTERACTION_HANDLED_PASS

// Undefine these.
#undef MEDBOT_PANIC_NONE
#undef MEDBOT_PANIC_LOW
#undef MEDBOT_PANIC_MED
#undef MEDBOT_PANIC_HIGH
#undef MEDBOT_PANIC_FUCK
#undef MEDBOT_PANIC_ENDING
#undef MEDBOT_PANIC_END

/mob/living/bot/medbot/ownership()
	. = ..()
	. += owns(nameof(reagent_glass), policy = OWN_CONTAINED)
