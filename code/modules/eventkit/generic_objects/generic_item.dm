/obj/item/generic_item
	name = "unusual object"
	desc = "An unusual object of some sort."
	icon = 'icons/obj/props/items.dmi'
	icon_state = "old_handheld"
	var/on = 0
	var/icon_state_off = "old_handheld"
	var/icon_state_on = "old_handheld_on"
	var/activatable_hand = 1
	var/togglable = 1
	var/text_activated = "The item turns on."
	var/text_deactivated = "The item turns off."
	var/effect = 0
	var/object = 0
	var/sound_activated = 0
	var/delay_time = 0
	var/icon_off = 0
	var/icon_on = 0

/// The use after its delay: attack_self() again, past the delay.
/obj/item/generic_item/proc/delayed_use(mob/user)
	delay_passed = TRUE
	attack_self(user)
	delay_passed = FALSE

/obj/item/generic_item/var/delay_passed = FALSE

CAPABILITIES(/obj/item/generic_item)
	op("self", in_hand(), then(PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/generic_item/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(activatable_hand)
		if(!on)
			if(delay_time && !delay_passed)
				om_task_timed(user, delay_time, src, src, PROC_REF(delayed_use), list(user))
				return TRUE
			on = 1
			if(icon_on)
				icon = icon_on
			else
				icon = 'icons/obj/props/items.dmi'
			icon_state = icon_state_on
			if(user)
				user.visible_message(span_notice("[text_activated]"))
			if(effect == 1)
				fx_sparks(src, 3)
			if(effect == 2)
				for(var/obj/machinery/light/L in REGISTRY_MEMBERS(REGISTRY_MACHINES))
					if(L.z != user.z || get_dist(user,L) > 10)
						continue
					else
						L.flicker(10)
			if(effect == 3)
				for (var/mob/O in viewers(user, null))
					if(get_dist(user, O) > 3)
						continue

					var/flash_time = 10
					if(ishuman(O))
						var/mob/living/carbon/human/H = O
						if(H.nif && H.nif.flag_check(NIF_V_FLASHPROT,NIF_FLAGS_VISION))
							H.nif.notify("High intensity light detected, and blocked!",TRUE)
							continue
						if(H.has_mutation(FLASHPROOF))
							continue
						if(H.eyecheck() <= 0)
							continue
						flash_time *= H.species.flash_mod
						var/obj/item/organ/internal/eyes/E = H.organ_in(O_EYES)
						if(!E)
							return TRUE
						if(E.is_bruised() && prob(E.damage + 50))
							H.flash_eyes()
							H.injure(INJURY_BURN, rand(1, 5), E, src, flags = INJURE_SILENT)
					else
						if(!O.blinded && isliving(O))
							var/mob/living/L = O
							L.flash_eyes()
					O.status_at_least(STAT_WEAKENED, flash_time)
			if(effect == 4)
				var/atom/o = new object(get_turf(user))
				src.visible_message(span_notice("[src] has produced [o]!"))
			if(sound_activated)
				playsound(src, sound_activated, 50, 1)
		else if(togglable)
			if(delay_time && !delay_passed)
				om_task_timed(user, delay_time, src, src, PROC_REF(delayed_use), list(user))
				return TRUE
			on = 0
			icon_state = icon_state_off
			if(icon_off)
				icon = icon_off
			else
				icon = 'icons/obj/props/items.dmi'
			if(user)
				user.visible_message(span_notice("[text_deactivated]"))
	return TRUE

ADMIN_VERB(generic_item, R_SPAWN, "Spawn Generic Item", "Spawn a customisable item with a range of different options.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	return generic_setup_stage(user, list())

/datum/admin_verb/generic_item/proc/generic_setup_stage(client/user, list/setup_answers)
	if(!user || !user.mob || QDELETED(user.mob))
		return
	var/s_activatable = 0
	var/s_togglable = 0
	var/s_icon_state_on = 0
	var/s_icon = 0
	var/s_icon2 = 0
	var/s_delay = 0
	var/s_text_activated = 0
	var/s_text_deactivated = 0
	var/s_effect = 0
	var/s_sound = 0
	var/s_object = 0
	var/static/list/icon_state_options = list("old_handheld",
										"old_handheld_on",
										"switch",
										"switch_on",
										"chalice",
										"staffofnothing",
										"staffofchange",
										"staffofanimation",
										"staffofchaos",
										"scroll_rolledup",
										"scroll_blank",
										"scroll_text",
										"scroll_textseal",
										"scroll_rolledupseal",
										"revolver",
										"universal_id",
										"universal_id_glow",
										"partypopper",
										"partypopper_e",
										"screwdriver",
										"screwdriver_glow",
										"crystal",
										"crystal_red",
										"old_phone",
										"old_phone_on",
										"flash",
										"flash_red",
										"flash_burnt",
										"techball_green",
										"techball_yellow",
										"techball_red",
										"techball_blue",
										"fleshorb",
										"fleshorb_moving",
										"Upload Own Sprite")

	var/static/list/sound_options = list('sound/effects/alert.ogg',
								'sound/effects/bamf.ogg',
								'sound/effects/bang.ogg',
								'sound/effects/blobattack.ogg',
								'sound/effects/cascade.ogg',
								'sound/effects/clockcult_gateway_disrupted.ogg',
								'sound/effects/closet_close.ogg',
								'sound/effects/confetti_ball.ogg',
								'sound/effects/deskbell.ogg',
								'sound/effects/EMPulse.ogg',
								'sound/effects/Explosion1.ogg',
								'sound/effects/ghost.ogg',
								'sound/effects/Glassbr1.ogg',
								'sound/effects/lightningshock.ogg',
								'sound/effects/lighton.ogg',
								'sound/effects/magnetclamp.ogg',
								'sound/effects/pai_boot.ogg',
								'sound/effects/pai_login.ogg',
								'sound/effects/pai-restore.ogg',
								'sound/effects/radio_common.ogg',
								'sound/effects/refill.ogg',
								'sound/effects/siren.ogg',
								'sound/effects/smoke.ogg',
								'sound/effects/sparks1.ogg',
								'sound/effects/spray.ogg',
								'sound/effects/squelch1.ogg',
								'sound/effects/supermatter.ogg',
								'sound/effects/Whipcrack.ogg',
								'sound/effects/woodcutting.ogg')

	var/check_togglable

	if(!("a1" in setup_answers))
		open_request(src, /datum/prompt/text/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a1", question = "Item Name:", title = "Name")
		return
	var/s_name = setup_answers["a1"]
	if(isnull(s_name))
		return
	if(!("a2" in setup_answers))
		open_request(src, /datum/prompt/text/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a2", question = "Item Description:", title = "Description")
		return
	var/s_desc = setup_answers["a2"]
	if(isnull(s_desc))
		return
	if(!("a3" in setup_answers))
		open_request(src, /datum/prompt/choice/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a3", question = "Choose starting icon state:", title = "icon_state_off", choices = icon_state_options)
		return
	var/s_icon_state_off = setup_answers["a3"]
	if(isnull(s_icon_state_off))
		return
	// Uploads (s_icon) are asked last: a file upload is a native dialog that waits.
	if(!("a4" in setup_answers))
		open_request(src, /datum/prompt/choice/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a4", question = "Allow it to be turned on?", title = "activatable", choices = list("Yes", "No", "Cancel"), buttons = TRUE)
		return
	var/check_activatable = setup_answers["a4"]
	if(isnull(check_activatable))
		return
	if(!check_activatable || check_activatable == "Cancel")
		return
	if(check_activatable == "No")
		s_activatable = 0
	if(check_activatable == "Yes")
		s_activatable = 1
		if(!("a5" in setup_answers))
			open_request(src, /datum/prompt/text/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a5", question = "Activation text:", title = "Activation Text")
			return
		var/_answer_a5 = setup_answers["a5"]
		if(isnull(_answer_a5))
			return
		s_text_activated = _answer_a5
		if(!("a6" in setup_answers))
			open_request(src, /datum/prompt/choice/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a6", question = "Allow it to be turned back off again?", title = "togglable", choices = list("Yes", "No", "Cancel"), buttons = TRUE)
			return
		var/_answer_a6 = setup_answers["a6"]
		if(isnull(_answer_a6))
			return
		check_togglable = _answer_a6
		if(!check_togglable || check_togglable == "Cancel")
			return
		if(check_togglable == "No")
			s_togglable = 0
		if(check_togglable == "Yes")
			if(!("a7" in setup_answers))
				open_request(src, /datum/prompt/text/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a7", question = "Deactivation text:", title = "Deactivation Text")
				return
			var/_answer_a7 = setup_answers["a7"]
			if(isnull(_answer_a7))
				return
			s_text_deactivated = _answer_a7
			s_togglable = 1
		if(!("a8" in setup_answers))
			open_request(src, /datum/prompt/choice/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a8", question = "Choose activated icon state:", title = "icon_state_on", choices = icon_state_options)
			return
		var/_answer_a8 = setup_answers["a8"]
		if(isnull(_answer_a8))
			return
		s_icon_state_on = _answer_a8
		// Uploads (s_icon2) are asked last: a file upload is a native dialog that waits.
		if(!("a9" in setup_answers))
			open_request(src, /datum/prompt/number/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a9", question = "Do you want it to take time to put turn on? Choose a number of deciseconds to activate, or 0 for instant.", title = "Delay")
			return
		var/_answer_a9 = setup_answers["a9"]
		if(isnull(_answer_a9))
			return
		s_delay = _answer_a9
		if(!("a10" in setup_answers))
			open_request(src, /datum/prompt/choice/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a10", question = "Produce an effect on activation?", title = "Effect?", choices = list("No", "Spark", "Flicker Lights", "Flash", "Spawn Item", "Cancel"), buttons = TRUE)
			return
		var/check_effect = setup_answers["a10"]
		if(isnull(check_effect))
			return
		if(!check_effect || check_effect == "Cancel")
			return
		if(check_effect == "No")
			s_effect = 0
		if(check_effect == "Spark")
			s_effect = 1
		if(check_effect == "Flicker Lights")
			s_effect = 2
		if(check_effect == "Flash")
			s_effect = 3
		if(check_effect == "Spawn Item")
			s_effect = 4
			if(!("object" in setup_answers))
				open_request(src, /datum/prompt/text/generic_spawn_type_query, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "object", question = "Enter full or partial typepath.", title = "Typepath", max_len = MAX_TGUI_INPUT)
				return
			s_object = setup_answers["object"]
			if(isnull(s_object))
				return
		if(!("a11" in setup_answers))
			open_request(src, /datum/prompt/choice/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a11", question = "Play a sound when turning on?", title = "Sound", choices = list("Yes", "No", "Cancel"), buttons = TRUE)
			return
		var/check_sound = setup_answers["a11"]
		if(isnull(check_sound))
			return
		if(!check_sound || check_sound == "Cancel")
			return
		if(check_sound == "Yes")
			if(!("a12" in setup_answers))
				open_request(src, /datum/prompt/choice/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = user.mob, setup_answers = setup_answers, setup_key = "a12", question = "Choose a sound to play on activation:", title = "Sound", choices = sound_options)
				return
			var/_answer_a12 = setup_answers["a12"]
			if(isnull(_answer_a12))
				return
			s_sound = _answer_a12

	// The uploads come last (allowlisted: a native file dialog, nothing to answer it asynchronously).
	if(s_icon_state_off == "Upload Own Sprite")
		s_icon = input(user, "Choose an image file to upload. Images that are not 32x32 will need to have their positions offset.","Upload Icon") as null|file // ALLOW(scheduler): file uploads need the BYOND file dialog
	if(s_icon_state_on == "Upload Own Sprite")
		s_icon2 = input(user, "Choose an image file to upload. Images that are not 32x32 will need to have their positions offset.","Upload Icon") as null|file // ALLOW(scheduler): file uploads need the BYOND file dialog

	var/spawnloc = get_turf(user.mob)
	var/obj/item/generic_item/P = new(spawnloc)
	P.name = s_name
	P.desc = s_desc
	P.icon_state_off = s_icon_state_off
	P.icon_state_on = s_icon_state_on
	P.activatable_hand = s_activatable
	P.togglable = s_togglable
	P.text_activated = s_text_activated
	P.text_deactivated = s_text_deactivated
	P.effect = s_effect
	P.sound_activated = s_sound
	P.delay_time = s_delay
	P.object = s_object
	P.icon_state = s_icon_state_off
	P.icon_off = s_icon
	P.icon_on = s_icon2
	if(s_icon)
		P.icon = s_icon

/datum/admin_verb/generic_item/proc/generic_setup_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/mob/answerer = context.request.answerer
	var/client/user = answerer?.client
	if(!user)
		return
	var/list/setup_answers
	var/setup_key
	if(istype(context.answer, /datum/prompt/text/generic_spawn_setup))
		var/datum/prompt/text/generic_spawn_setup/text_request = context.answer
		setup_answers = text_request.setup_answers.Copy()
		setup_key = text_request.setup_key
	else if(istype(context.answer, /datum/prompt/choice/generic_spawn_setup))
		var/datum/prompt/choice/generic_spawn_setup/choice_request = context.answer
		setup_answers = choice_request.setup_answers.Copy()
		setup_key = choice_request.setup_key
	else if(istype(context.answer, /datum/prompt/number/generic_spawn_setup))
		var/datum/prompt/number/generic_spawn_setup/number_request = context.answer
		setup_answers = number_request.setup_answers.Copy()
		setup_key = number_request.setup_key
	else
		return
	var/is_type_query = istype(context.answer, /datum/prompt/text/generic_spawn_type_query)
	var/selected = context.answer.value
	if(setup_key == "object" && istext(selected))
		var/list/matches = list()
		for(var/path in typesof(/atom))
			if(findtext("[path]", selected))
				matches += path
		if(length(matches) == 1)
			selected = matches[1]
		else if(!length(matches))
			to_chat(answerer, span_warning("No results found.  Sorry."))
			return
		else
			open_request(src, /datum/prompt/choice/generic_spawn_setup, PROC_REF(generic_setup_answered), answerer = answerer, setup_answers = setup_answers, setup_key = "object", question = "Select a type", title = "Typepath", choices = matches)
			return
	// Old typepath refinement preceded the permission recheck, including its picker/no-results UI.
	if(is_type_query && (!admin_can(user, 0) || !check_rights_for(user, R_SPAWN)))
		return
	// This is the old dynamic-dispatch boundary, after type refinement and prompt rights checks.
	if(generic_spawn_advanced_call(answerer))
		message_admins("PERMISSION ELEVATION: [key_name_admin(user)] attempted to dynamically invoke admin verb '[src.type]'.")
		return
	if(debug_only)
		log_admin("DEBUG VERB: [key_name(user)] invoked '[name]' ([src.type])")
	METRICS_EVENT(METRICS_EVENT_ADMIN_VERB, category, "[src.type]", user.ckey, name, null)
	setup_answers[setup_key] = selected
	return generic_setup_stage(user, setup_answers)


/proc/generic_spawn_advanced_call(mob/actor)
#ifdef TESTING
	return FALSE
#else
	return (GLOB.AdminProcCaller && GLOB.AdminProcCaller == actor?.client?.ckey) || (GLOB.AdminProcCallHandler && actor == GLOB.AdminProcCallHandler)
#endif

/datum/prompt/text/generic_spawn_setup
	timeout = 0
	recheck_on_open = TRUE
	rights = R_SPAWN
	var/list/setup_answers
	var/setup_key

/datum/prompt/text/generic_spawn_setup/recheck_extra()
	var/mob/admin = answerer
	if(!admin_can(admin?.client, 0))
		return "no admin rights"

/datum/prompt/text/generic_spawn_setup/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/generic_spawn_setup
	timeout = 0
	recheck_on_open = TRUE
	rights = R_SPAWN
	var/list/setup_answers
	var/setup_key

/datum/prompt/choice/generic_spawn_setup/recheck_extra()
	var/mob/admin = answerer
	if(!admin_can(admin?.client, 0))
		return "no admin rights"

/datum/prompt/number/generic_spawn_setup
	timeout = 0
	recheck_on_open = TRUE
	rights = R_SPAWN
	var/list/setup_answers
	var/setup_key

/datum/prompt/number/generic_spawn_setup/recheck_extra()
	var/mob/admin = answerer
	if(!admin_can(admin?.client, 0))
		return "no admin rights"

/datum/prompt/text/generic_spawn_type_query
	parent_type = /datum/prompt/text/generic_spawn_setup
	rights = 0

/datum/prompt/text/generic_spawn_type_query/normalize(given)
	return given

/datum/prompt/text/generic_spawn_type_query/recheck_extra()
	// Refinement has no permission gate; the callback rechecks after the old matching step.
	return null
