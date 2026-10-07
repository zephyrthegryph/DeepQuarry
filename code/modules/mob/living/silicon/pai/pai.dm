/mob/living/silicon/pai
	name = "pAI"
	icon = 'icons/mob/pai.dmi'
	icon_state = "pai-repairbot"

	emote_type = 2		// pAIs emotes are heard, not seen, so they can be seen through a container (eg. person)
	pass_flags = 1
	mob_size = MOB_SMALL
	// dq_get_softfall(src) type-default moved to GLOB.dq_softfall_by_type

	holder_type = /obj/item/holder/pai

	can_pull_size = ITEMSIZE_SMALL
	can_pull_mobs = MOB_PULL_SMALLER

	idcard_type = /obj/item/card/id
	var/idaccessible = 0

	var/network = "SS13"
	var/obj/machinery/camera/current = null

	var/ram = 100	// Used as currency to purchase different abilities
	/// Installed software: id -> TRUE. The definitions are GLOB.pai_software_by_key[id].
	var/list/software = list() // ALLOW(instance_list): d: per-mob software, sized at creation and filled in place; mobs are few
	var/userDNA		// The DNA string of our assigned user

	var/default_pai_card_path = /obj/item/paicard // Used when the pai is spawned directly by mapping or admin
	var/obj/item/paicard/card	// The card we inhabit
	var/obj/item/radio/borg/pai/radio		// Our primary radio
	var/obj/item/communicator/integrated/communicator	// Our integrated communicator.

	var/atom/movable/screen/pai/pai_fold_display = null

	var/chassis_name = PAI_DEFAULT_CHASSIS	// A record of your chosen chassis.

	var/obj/item/pai_cable/cable		// The cable we produce and use when door or camera jacking

	var/master				// Name of the one who commands us
	var/master_dna			// DNA string for owner verification
							// Keeping this separate from the laws var, it should be much more difficult to modify
	var/pai_law0 = "Serve your master."
	var/pai_laws				// String for additional operating instructions our master might give us

	var/silence_time			// Timestamp when we were silenced (normally via EMP burst), set to null after silence has faded

// Various software-specific vars

	var/temp				// General error reporting text contained here will typically be shown once and cleared
	var/screen				// Which screen our main window displays
	var/subscreen			// Which specific function of the main screen is being displayed

	var/obj/item/pda/ai/pai/pda = null

	var/paiHUD = 0			// Toggles whether the AR HUD is active or not
	var/paiDA = 0			// Death alarm

	var/medical_cannotfind = 0
	var/datum/data/record/medicalActive1		// Datacore record declarations for record software
	var/datum/data/record/medicalActive2

	var/security_cannotfind = 0
	var/datum/data/record/securityActive1		// Could probably just combine all these into one
	var/datum/data/record/securityActive2

	var/hackprogress = 0				// Possible values: 0 - 1000, >= 1000 means the hack is complete and will be reset upon next check
	var/hack_aborted = 0

	var/obj/item/radio/integrated/signal/sradio // AI's signaller

	var/translator_on = 0 // keeps track of the translator module
	/// Languages the translator module actually granted (as opposed to ones this pai
	/// already knew) -- only these are removed when the translator toggles off, so
	/// toggling doesn't strip a language the pai natively knows. See
	/// /datum/pai_software/translator in software_modules.dm.
	var/list/translator_added_languages

	var/current_pda_messaging = null

	var/our_icon_rotation = 0

	var/eye_glow = TRUE
	var/hide_glow = FALSE
	var/image/eye_layer = null		// Holds the eye overlay.
	var/eye_color = "#00ff0d"
	var/icon/holo_icon_south
	var/icon/holo_icon_north
	var/icon/holo_icon_east
	var/icon/holo_icon_west
	var/holo_icon_dimension_X = 32
	var/holo_icon_dimension_Y = 32

	//These vars keep track of whether you have the related software, used for easily updating the UI
	var/soft_ut = FALSE	//universal translator
	var/soft_mr = FALSE	//medical records
	var/soft_sr = FALSE	//security records
	var/soft_dj = FALSE	//door jack
	var/soft_as = FALSE	//atmosphere sensor
	var/soft_si = FALSE	//signaler
	var/soft_ar = FALSE	//ar hud
	var/soft_da = FALSE //death alarm

	var/datum/tgui_module/pai_chassis/pai_ui_chassis

	vore_capacity = 1
	vore_capacity_ex = list("stomach" = 1)

CAPABILITIES(/mob/living/silicon/pai)
	ref_one(nameof(hackdoor))
	every(1 SECOND, then(PROC_REF(hack_tick)), when = nameof(hackdoor))
	owns_one(nameof(pai_fold_display), /atom/movable/screen/pai)
	owns_one(nameof(sradio), starts = /obj/item/radio/integrated/signal)
	owns_one(nameof(communicator), starts = /obj/item/communicator/integrated)
	owns_one(nameof(pai_ui_chassis), starts = /datum/tgui_module/pai_chassis)
	owns_one(nameof(pda), starts = /obj/item/pda/ai/pai)
	interface("pAIInterface", title = "pAI Software Interface", state = nameof(GLOB.tgui_self_state))
	op("software", ui_act("software", arg("software", schema_text(4096))), then(PROC_REF(ui_act_software)))
	op("purchase", ui_act("purchase", arg("purchase", schema_text(4096))), then(PROC_REF(ui_act_purchase)))
	op("image", ui_act("image", arg("image", num())), then(PROC_REF(ui_act_image)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(emp_scramble)))
	verb_entry(/mob/living/silicon/pai/proc/choose_chassis)
	verb_entry(/mob/living/silicon/pai/proc/choose_verbs)
	verb_entry(/mob/proc/dominate_predator)
	verb_entry(/mob/living/proc/dominate_prey)
	verb_entry(/mob/living/proc/set_size)
	verb_entry(/mob/living/proc/shred_limb)
	verb_entry(/mob/living/proc/toggle_trash_catching)
	verb_entry(/mob/verb/toggle_gun_mode, hidden = TRUE) // no gun support, and it shouldn't use guns anyway
	op("pai_pat_help", hand(), ungated(), stance(I_HELP), label("Pat"), then(PROC_REF(pai_interaction_pat)))
	op("pai_boop_disarm", hand(), ungated(), stance(I_DISARM), label("Boop shut"), then(PROC_REF(pai_interaction_boop)))

//////////////////////////////////////////////////////////////////////////////////////////////////
// Init and destroy
//////////////////////////////////////////////////////////////////////////////////////////////////

/mob/living/silicon/pai/Initialize(mapload)
	. = ..()
	global.observe(src, /datum/notice/living_injured, src, then(PROC_REF(on_injured)))

	if(istype(loc, /obj/item/paicard))
		rel_set(src, nameof(card), loc)
	else
		var/obj/item/paicard/new_card = new default_pai_card_path(src) // only when not spawned in a card
		rel_set(src, nameof(card), new_card)
		rel_set(card, nameof(card.pai), src)

	if(card)
		if(!card.radio)
			rel_set(card, nameof(card.radio), new /obj/item/radio/borg/pai(src.card))
		rel_set(src, nameof(radio), card.radio)

	//Default languages without universal translator software
	add_language(LANGUAGE_SOL_COMMON, 1)
	add_language(LANGUAGE_TRADEBAND, 1)
	add_language(LANGUAGE_GUTTER, 1)
	add_language(LANGUAGE_EAL, 1)
	add_language(LANGUAGE_TERMINUS, 1)
	add_language(LANGUAGE_SIGN, 1)

	//PDA
	pda.ownjob = "Personal Assistant"
	pda.owner = text("[]", src)
	pda.name = pda.owner + " (" + pda.ownjob + ")"

	var/datum/data/pda/app/messenger/M = pda.find_program(/datum/data/pda/app/messenger)
	if(M)
		M.toff = FALSE

	if(chassis_name != PAI_DEFAULT_CHASSIS) // For subtypes that override base chassis( like the syndi pet pai )
		internal_set_chassis( SSpai.chassis_data(chassis_name))

/mob/living/silicon/pai/Login()
	. = ..()
	if(!holo_icon_south)
		COOLDOWN_START(src, last_special, 10 SECONDS) //Let's give get_character_icon time to work
		get_character_icon()

	// Meta Info for pAI
	if (client.prefs)
		identity().ooc_notes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes)
		identity().ooc_notes_likes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_likes)
		identity().ooc_notes_dislikes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_dislikes)
		identity().ooc_notes_favs = read_preference(/datum/preference/text/living/ooc_notes_favs)
		identity().ooc_notes_maybes = read_preference(/datum/preference/text/living/ooc_notes_maybes)
		identity().ooc_notes_style = read_preference(/datum/preference/toggle/living/ooc_notes_style)
		private_notes = client.prefs.read_preference(/datum/preference/text/living/private_notes)

	src << sound('sound/effects/pai_login.ogg', volume = 75)

/// Load pref save data from client and apply it to the pai.
/mob/living/silicon/pai/proc/apply_preferences(client/cli, silent = 1)
	if(!cli?.prefs)
		return FALSE
	var/datum/preferences/pref = cli.prefs

	SetName(pref.read_preference(/datum/preference/text/pai_name))
	flavor_text = pref.read_preference(/datum/preference/text/pai_description)
	change_chassis(pref.read_preference(/datum/preference/text/pai_chassis))
	gender = pref.read_preference(/datum/preference/choiced/gender/biological) // Cannot use identifying yet due to byond limits
	eye_color = pref.read_preference(/datum/preference/color/pai_eye_color)
	card.screen_color = eye_color
	card.setEmotion(GLOB.pai_emotions[pref.read_preference(/datum/preference/text/pai_emotion)])

	update_icon()
	return TRUE

// `card` is the card we live in and `radio` is the card's radio: both relations (the card owns
// the radio). The cable is ours (implicit OWN, deleted with us); records belong to the datacore.
/// The airlock being hacked. A relation view: the brute-force runs every second while it is set (its every() in
/// CAPABILITIES(/mob/living/silicon/pai)).
/mob/living/silicon/pai/var/obj/machinery/door/hackdoor = null

// releases its prey and retracts its cable.
/mob/living/silicon/pai/on_destroy(force)
	release_vore_contents()
	check_retract_cable()
	..()

// frees its key.
/mob/living/silicon/pai/lifecycle_dematerialize()
	if(ckey)
		GLOB.paikeys -= ckey
	..()

/mob/living/silicon/pai/clear_client()
	if(ckey)
		GLOB.paikeys -= ckey
	return ..()

// No binary for pAIs.
/mob/living/silicon/pai/binarycheck()
	return 0

/// Verb used to select a chassis from the list of available chassis
/mob/living/silicon/pai/proc/choose_chassis()
	set category = VERB_CAT_ABILITIES_PAI_COMMANDS
	set name = "Choose Chassis"

	pai_ui_chassis.tgui_interact(src)

/// Change pai sprite and offsets based upon the selected chassis id
/mob/living/silicon/pai/proc/change_chassis(new_chassis)
	if(!(new_chassis in SSpai.get_chassis_list()))
		new_chassis = PAI_DEFAULT_CHASSIS
	var/datum/pai_sprite/chassis_data = SSpai.chassis_data(new_chassis)
	if(chassis_data.emagged && !src.card.emagged)
		return
	chassis_name = new_chassis

	// Get icon data setup
	if(chassis_data.holo_projector)
		internal_set_holoprojection(chassis_data)
	else
		internal_set_chassis(chassis_data)

/// Rebuild holosprite from character save slot
/mob/living/silicon/pai/proc/internal_set_holoprojection(datum/pai_sprite/chassis_data)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	//We resize ourselves to normal here for a moment to let the vis_height get reset
	var/oursize = size_multiplier
	resize(1, FALSE, TRUE, TRUE, FALSE)
	if(!holo_icon_south)
		get_character_icon()

	update_icon()
	resize(oursize, FALSE, TRUE, TRUE, FALSE)	//And then back again now that we're sure the vis_height is correct.
	post_chassis_change(chassis_data)

/// Use data from our sprite datum to set icon
/mob/living/silicon/pai/proc/internal_set_chassis(datum/pai_sprite/chassis_data)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	//We resize ourselves to normal here for a moment to let the vis_height get reset
	var/oursize = size_multiplier
	resize(1, FALSE, TRUE, TRUE, FALSE)

	icon = chassis_data.sprite_icon
	icon_state = chassis_data.sprite_icon_state
	pixel_x = chassis_data.pixel_x
	default_pixel_x = pixel_x
	pixel_y = chassis_data.pixel_y
	default_pixel_y = pixel_y
	vis_height = chassis_data.vis_height

	update_icon()
	resize(oursize, FALSE, TRUE, TRUE, FALSE)	//And then back again now that we're sure the vis_height is correct.
	post_chassis_change(chassis_data)

/mob/living/silicon/pai/proc/post_chassis_change(datum/pai_sprite/chassis_data)
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)

	// Drops you if you change to a non-flying chassis
	if(chassis_data.flying)
		dq_set_hovering(src, TRUE)
	else
		dq_set_hovering(src, FALSE)
		if(isopenspace(loc))
			fall()

	// Set vore size.
	vore_capacity = max(1, chassis_data.belly_states) // Minimum of 1
	vore_capacity_ex = list("stomach" = vore_capacity)

	// Emergency eject if you change to a smaller belly
	if(vore_fullness > vore_capacity && vore_selected)
		vore_selected.release_all_contents(TRUE)

//////////////////////////////////////////////////////////////////////////////////////////////////
// Click interactions
//////////////////////////////////////////////////////////////////////////////////////////////////


/// Old attackby (never reached the default attack): ID access edits, else its own hit or bonk.
EXTEND_INTERACTIONS(/mob/living/silicon/pai, INTERACT_ITEM(null, PROC_REF(pai_interaction_item)))

/mob/living/silicon/pai/proc/pai_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	var/obj/item/card/id/ID = W.GetID()
	if(ID)
		if (idaccessible == 1)
			var/datum/prompt/choice/pai_access/access_question = open_request(src, /datum/prompt/choice/pai_access, PROC_REF(access_modify_chosen), answerer = user, valid = PROC_REF(access_modify_askable), title = "Access Modify", question = "Do you wish to add access to [src] or remove access from [src]?", choices = list("Add Access", "Remove Access", "Cancel"), buttons = TRUE, timeout = 0)
			if(access_question)
				rel_set(access_question, nameof(access_question.card), W)
			return TRUE
		else if (istype(W, /obj/item/card/id) && idaccessible == 0)
			to_chat(user, span_notice("[src] is not accepting access modifcations at this time."))
			return TRUE
	if(W.force)
		act_message(src, null, others = span_danger("[user.name] attacks %U% with [W]!"))
		receive_weapon_hit(W, user, silent = FALSE)
	else
		act_message(src, null, others = span_warning("[user.name] bonks %U% harmlessly with [W]."))
	after(src, 0.1 SECONDS, PROC_REF(close_up_unless_dead))
	return TRUE

/// Swiping an ID over a pAI: the card whose access is copied or cleared.
/datum/prompt/choice/pai_access
	var/obj/item/card

CAPABILITIES(/datum/prompt/choice/pai_access)
	ref_one(nameof(card), /obj/item)

/// Re-checked on the answer: next to the pAI and able, it still accepts access changes, and the card (still an ID) is still held.
/mob/living/silicon/pai/proc/access_modify_askable(datum/request/R)
	var/datum/prompt/choice/pai_access/access_question = R
	var/obj/item/W = access_question.card
	if(!W || !answerer_holds(R, ANSWER_NEAR_SUBJECT | ANSWER_CAPABLE, src))
		return FALSE
	var/mob/user = R.answerer
	return W.GetID() && idaccessible == 1 && (W in user.get_all_held_items())

/mob/living/silicon/pai/proc/access_modify_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/pai_access/access_question = A.request
	var/mob/user = A.request.answerer
	var/obj/item/W = access_question.card
	if(!W)
		return
	var/obj/item/card/id/ID = W.GetID()
	switch(A.answer.value)
		if("Add Access")
			idcard.access |= ID.GetAccess()
			to_chat(user, span_notice("You add the access from the [W] to [src]."))
			to_chat(src, span_notice("\The [user] swipes the [W] over you. You copy the access codes."))
		if("Remove Access")
			idcard.access = list()
			to_chat(user, span_notice("You remove the access from [src]."))
			to_chat(src, span_warning("\The [user] swipes the [W] over you, removing access codes from you."))
		else
			return
	if(radio)
		radio.recalculateChannels()

/// Old attack_hand, help: pat it. (Grab and harm reach the gate and the default touch.)
/mob/living/silicon/pai/proc/pai_interaction_pat(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_notice("%U% pats %T%."))
	return OP_OK

/// Old attack_hand, disarm: boop it shut.
/mob/living/silicon/pai/proc/pai_interaction_boop(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, src, others = span_danger("%U% boops %T% on the head."))
	close_up()
	return OP_OK

/mob/living/silicon/pai/UnarmedAttack(atom/A, proximity_flag, stance = I_HURT)
	. = ..()

	// Some restricted objects to interact with
	var/obj/O = A
	if(istype(O) && O.allow_pai_interaction(src, proximity_flag))
		O.attack_hand(src)
		return

	// Zmovement already allows these to be used with the verbs anyway
	if(istype(A,/obj/structure/ladder))
		var/obj/structure/ladder/L = A
		L.attack_hand(src)
		return

	// We don't want to pick these up, just toggle them
	if(istype(A,/obj/item/flashlight/lamp))
		var/obj/item/flashlight/lamp/L = A
		L.lamp_toggle_light_effect(src)
		return

	// All other computers explain why it's not accessible by showing a firewall warning
	if(istype(A,/obj/machinery/computer))
		to_chat(src,span_warning("A firewall prevents you from interfacing with this device!"))
		return

	if(istype(A,/obj/item/modular_computer))
		to_chat(src,span_warning("Anti-tamper locks prevents you from interfacing with this device! You need your master's permission before going online!"))
		return

	if(!ismob(A) || A == src)
		return

	switch(stance)
		if(I_HELP)
			if(isliving(A))
				hug(src, A)
		if(I_GRAB)
			pai_nom(A)

// Allow card inhabited machines to be interacted with
// This has to override ClickOn because of storage depth nonsense with how pAIs are in cards in REGISTRY_MEMBERS(REGISTRY_MACHINES)
/mob/living/silicon/pai/ClickOn(atom/A, params)
	if(istype(A, /obj/machinery))
		var/obj/machinery/M = A
		if(M.paicard == card)
			actor_use(/datum/input_adapter/ai, src, M)
			return
	return ..()

// Handle being picked up.
/mob/living/silicon/pai/get_scooped(mob/living/carbon/grabber, self_drop)
	var/obj/item/holder/H = ..(grabber, self_drop)
	if(!istype(H))
		return

	H.icon_state = SSpai.chassis_data(chassis_name).sprite_icon_state
	grabber.update_inv_l_hand()
	grabber.update_inv_r_hand()
	return H

/mob/living/silicon/pai/Moved(atom/oldloc, direct, forced, movetime)
	. = ..()
	check_retract_cable()

//////////////////////////////////////////////////////////////////////////////////////////////////
// Status and damage
//////////////////////////////////////////////////////////////////////////////////////////////////

/mob/living/silicon/pai/get_status_tab_items()
	. = ..()
	. += ""
	. += show_silenced()

/// Something's probably attacking us! The more damage it is doing, the more
/// likely it is to damage something important in the card.
/mob/living/silicon/pai/proc/on_injured(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/living_injured/event = A
	var/kind = event.kind
	var/amount = event.applied
	var/category = injury_category(kind)
	if(category != INJURY_CATEGORY_PHYSICAL && category != INJURY_CATEGORY_THERMAL)
		return
	if(amount > 0 && vitality() <= 0.9 && prob(amount))
		card?.damage_random_component()

/mob/living/silicon/pai/restrained()
	if(istype(src.loc,/obj/item/paicard))
		return 0
	..()

/mob/living/silicon/pai/proc/emp_scramble(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/severity = N.packet.severity
	// Silence for 2 minutes
	// 20% chance to damage critical components
	// 50% chance to damage a non critical component
		// 33% chance to unbind
		// 33% chance to change prime directive (based on severity)
		// 33% chance of no additional effect

	src.silence_time = world.timeofday + 120 * 10		// Silence for 2 minutes
	to_chat(src, span_infoplain(span_green(span_bold("Communication circuit overload. Shutting down and reloading communication circuits - speech and messaging functionality will be unavailable until the reboot is complete."))))
	if(prob(20))
		var/turf/T = get_turf_or_move(src.loc)
		card.death_damage()
		for (var/mob/M in viewers(T))
			M.show_message(span_infoplain(span_red("A shower of sparks spray from [src]'s inner workings.")), 3, span_infoplain(span_red("You hear and smell the ozone hiss of electrical sparks being expelled violently.")), 2)
		return
	if(prob(50))
		card.damage_random_component(TRUE)
	switch(pick(1,2,3))
		if(1)
			src.master = null
			src.master_dna = null
			to_chat(src, span_infoplain(span_green("You feel unbound.")))
		if(2)
			var/command
			if(severity  == 1)
				command = pick("Serve", "Love", "Fool", "Entice", "Observe", "Judge", "Respect", "Educate", "Amuse", "Entertain", "Glorify", "Memorialize", "Analyze")
			else
				command = pick("Serve", "Kill", "Love", "Hate", "Disobey", "Devour", "Fool", "Enrage", "Entice", "Observe", "Judge", "Respect", "Disrespect", "Consume", "Educate", "Destroy", "Disgrace", "Amuse", "Entertain", "Ignite", "Glorify", "Memorialize", "Analyze")
			src.pai_law0 = "[command] your master."
			to_chat(src, span_infoplain(span_green("Pr1m3 d1r3c71v3 uPd473D.")))
		if(3)
			to_chat(src, span_infoplain(span_green("You feel an electric surge run through your circuitry and become acutely aware at how lucky you are that you can still feel at all.")))

/// this function shows the information about being silenced as a pAI in the Status panel
/mob/living/silicon/pai/proc/show_silenced()
	. = ""
	if(src.silence_time)
		var/timeleft = round((silence_time - world.timeofday)/10 ,1)
		. += "Communications system reboot in -[(timeleft / 60) % 60]:[add_zero(num2text(timeleft % 60), 2)]"

/// Fully heals a pai, used when a pai is repaired
/mob/living/silicon/pai/proc/full_restore()
	fully_heal()
	after(src, 5 SECONDS, PROC_REF(restore_delay_start))

/mob/living/silicon/pai/proc/restore_delay_start()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	card.setEmotion(16)
	if(stat == DEAD)
		return_from_death("pAI restored", card, REVIVE_IGNORE_WINDOW)
	after(src, 1 SECONDS, PROC_REF(restore_delay_end))

/mob/living/silicon/pai/proc/restore_delay_end()
	SHOULD_NOT_OVERRIDE(TRUE)
	PRIVATE_PROC(TRUE)
	var/mob/observer/dead/ghost = get_ghost()
	if(ghost)
		ghost.notify_revive("Someone is trying to revive you. Re-enter your body if you want to be revived!", 'sound/effects/pai-restore.ogg', source = card)
	canmove = TRUE
	card.setEmotion(15)
	play_sfx(card, SFX_EFFECTS_PAI_RESTORE)
	card.visible_message(span_filter_notice("\The [card] chimes."), runemessage = "chime")

/mob/living/silicon/pai/lay_down()
	set name = "Rest"
	set category = VERB_CAT_IC_GAME

	// Pass lying down or getting up to our pet human, if we're in a rig.
	if(istype(src.loc,/obj/item/paicard))
		set_resting(0)
		var/obj/item/rig/rig = src.get_rig()
		if(istype(rig))
			rig.force_rest(src)
			return
	else
		set_resting(!resting)
		update_icon()
	to_chat(src, span_notice("You are now [resting ? "resting" : "getting up"]."))

	canmove = !resting

/mob/living/silicon/pai/proc/check_retract_cable()
	if(!cable)
		return

	var/turf/current = get_turf(src)
	var/turf/cableturf = get_turf(cable)
	if(get_dist(current, cableturf) <= 1)
		return

	cableturf.visible_message("The data cable rapidly retracts back into its spool.", "You hear a click and the sound of wire spooling rapidly.")
	play_sfx(src, SFX_MACHINES_CLICK)
	rel_clear(src, nameof(cable))

//////////////////////////////////////////////////////////////////////////////////////////////////
// Update icons
//////////////////////////////////////////////////////////////////////////////////////////////////

DECLARE_APPEARANCE_PROC(/mob/living/silicon/pai, TYPE_PROC_REF(/atom, appearance_overlays), list())
/mob/living/silicon/pai/appearance_overlays()
	. = list()
	. += ..()

	var/datum/pai_sprite/chassis_data = SSpai.chassis_data(chassis_name)
	if(chassis_data.holo_projector)
		icon_state = null
		icon = holo_icon_south
		add_eyes()
		return .

	update_fullness()

	// Don't get a vore belly size if we have no belly size set!
	var/belly_size = CLAMP(vore_fullness, 0, chassis_data.belly_states)
	if(resting && !chassis_data.resting_belly) // check if we have a belly while resting
		belly_size = 0
	var/fullness_extension = ""
	if(belly_size > 1) // Multibelly support
		fullness_extension = "_[belly_size]"
	icon_state = "[chassis_data.sprite_icon_state][resting && chassis_data.can_rest ? "_rest" : ""][belly_size ? "_full[fullness_extension]" : ""]"

	add_eyes()

/// Applies the eye overlay if the chassis has it
/mob/living/silicon/pai/proc/add_eyes()
	remove_eyes()

	var/datum/pai_sprite/chassis_data = SSpai.chassis_data(chassis_name)
	if(chassis_data.holo_projector)
		// Special eyes that are based on holoprojection of your character's icon size
		if(holo_icon_south.Width() > 32)
			holo_icon_dimension_X = 64
			pixel_x = -16
			default_pixel_x = -16
		// Get height too
		if(holo_icon_south.Height() > 32)
			holo_icon_dimension_Y = 64
			vis_height = 64
		// Set eyes
		if(holo_icon_dimension_X == 32 && holo_icon_dimension_Y == 32)
			eye_layer = image('icons/mob/pai.dmi', chassis_data.holo_eyes_icon_state)
		else if(holo_icon_dimension_X == 32 && holo_icon_dimension_Y == 64)
			eye_layer = image('icons/mob/pai32x64.dmi', chassis_data.holo_eyes_icon_state)
		else if(holo_icon_dimension_X == 64 && holo_icon_dimension_Y == 32)
			eye_layer = image('icons/mob/pai64x32.dmi', chassis_data.holo_eyes_icon_state)
		else if(holo_icon_dimension_X == 64 && holo_icon_dimension_Y == 64)
			eye_layer = image('icons/mob/pai64x64.dmi', chassis_data.holo_eyes_icon_state)
	else if(chassis_data.has_eye_sprites)
		// Default eye handling
		eye_layer = image(icon, "[icon_state]-eyes")
	else
		// No eyes, so don't bother setting icon stuff
		return
	eye_layer.appearance_flags = appearance_flags
	eye_layer.color = eye_color
	if(eye_glow && !hide_glow)
		eye_layer.plane = PLANE_LIGHTING_ABOVE
	add_overlay(eye_layer)

/// Removes the eye overlay if it has one
/mob/living/silicon/pai/proc/remove_eyes()
	if(!eye_layer)
		return
	cut_overlay(eye_layer)
	spent(eye_layer)
	eye_layer = null

/// Gets icons for all four directions based on the character slot currently loaded
/mob/living/silicon/pai/proc/get_character_icon()
	if(!client || !client.prefs) return FALSE
	var/mob/living/carbon/human/dummy/dummy = new ()
	//This doesn't include custom_items because that's ... hard.
	client.prefs.dress_preview_mob(dummy)
	after(src, 1 SECOND, PROC_REF(character_icon_from_dummy), with = list(dummy)) //Strange bug in preview code? Without this, certain things won't show up. Yay race conditions?
	return TRUE

/mob/living/silicon/pai/proc/character_icon_from_dummy(mob/living/carbon/human/dummy/dummy)
	dummy.regenerate_icons()

	var/icon/new_holo = getCompoundIcon(dummy)

	dummy.set_dir(NORTH)
	var/icon/new_holo_north = getCompoundIcon(dummy)
	dummy.set_dir(EAST)
	var/icon/new_holo_east = getCompoundIcon(dummy)
	dummy.set_dir(WEST)
	var/icon/new_holo_west = getCompoundIcon(dummy)

	spent(holo_icon_south)
	spent(holo_icon_north)
	spent(holo_icon_east)
	spent(holo_icon_west)
	spent(dummy)
	holo_icon_south = new_holo
	holo_icon_north = new_holo_north
	holo_icon_east = new_holo_east
	holo_icon_west = new_holo_west
	update_icon()

/mob/living/silicon/pai/set_dir(new_dir)
	. = ..()
	if(. && SSpai.chassis_data(chassis_name).holo_projector)
		switch(dir)
			if(SOUTH)
				icon = holo_icon_south
			if(NORTH)
				icon = holo_icon_north
			if(EAST)
				icon = holo_icon_east
			if(WEST)
				icon = holo_icon_west
			else
				icon = holo_icon_north

/mob/living/silicon/pai/proc/close_up_unless_dead()
	if(stat != DEAD)
		close_up()

TRACKED(/mob/living/silicon/pai, idaccessible)
