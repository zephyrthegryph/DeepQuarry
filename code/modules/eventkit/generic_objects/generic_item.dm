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

/obj/item/generic_item/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(activatable_hand)
		if(!on)
			if(delay_time && !delay_passed)
				om_do_after(user, delay_time, src, src, PROC_REF(delayed_use), list(user))
				return 0
			on = 1
			if(icon_on)
				icon = icon_on
			else
				icon = 'icons/obj/props/items.dmi'
			icon_state = icon_state_on
			if(user)
				user.visible_message(span_notice("[text_activated]"))
			update_icon()
			if(effect == 1)
				var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
				s.set_up(3, 1, src)
				s.start()
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
						var/obj/item/organ/internal/eyes/E = H.internal_organs_by_name[O_EYES]
						if(!E)
							return
						if(E.is_bruised() && prob(E.damage + 50))
							H.flash_eyes()
							H.injure(INJURY_BURN, rand(1, 5), E, src, flags = INJURE_SILENT)
					else
						if(!O.blinded && isliving(O))
							var/mob/living/L = O
							L.flash_eyes()
					O.status_at_least(EFFECT_WEAKENED, flash_time)
			if(effect == 4)
				var/atom/o = new object(get_turf(user))
				src.visible_message(span_notice("[src] has produced [o]!"))
			if(sound_activated)
				playsound(src, sound_activated, 50, 1)
		else if(togglable)
			if(delay_time && !delay_passed)
				om_do_after(user, delay_time, src, src, PROC_REF(delayed_use), list(user))
				return 0
			on = 0
			icon_state = icon_state_off
			if(icon_off)
				icon = icon_off
			else
				icon = 'icons/obj/props/items.dmi'
			if(user)
				user.visible_message(span_notice("[text_deactivated]"))
			update_icon()

ADMIN_VERB(generic_item, R_SPAWN, "Spawn Generic Item", "Spawn a customisable item with a range of different options.", ADMIN_CATEGORY_FUN_EVENT_KIT)
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
	var/list/icon_state_options = list("old_handheld",
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

	var/list/sound_options = list('sound/effects/alert.ogg',
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

	var/s_name = verb_prompt(user, "a1", list("kind" = "text", "message" = "Item Name:", "title" = "Name"), args)
	if(isnull(s_name))
		return
	var/s_desc = verb_prompt(user, "a2", list("kind" = "text", "message" = "Item Description:", "title" = "Description"), args)
	if(isnull(s_desc))
		return
	var/s_icon_state_off = verb_prompt(user, "a3", list("kind" = "list", "message" = "Choose starting icon state:", "title" = "icon_state_off", "choices" = icon_state_options), args)
	if(isnull(s_icon_state_off))
		return
	// Uploads (s_icon) are asked last: a file upload is a native dialog that waits.
	var/check_activatable = verb_prompt(user, "a4", list("message" = "Allow it to be turned on?", "title" = "activatable", "choices" = list("Yes", "No", "Cancel")), args)
	if(isnull(check_activatable))
		return
	if(!check_activatable || check_activatable == "Cancel")
		return
	if(check_activatable == "No")
		s_activatable = 0
	if(check_activatable == "Yes")
		s_activatable = 1
		var/_answer_a5 = verb_prompt(user, "a5", list("kind" = "text", "message" = "Activation text:", "title" = "Activation Text"), args)
		if(isnull(_answer_a5))
			return
		s_text_activated = _answer_a5
		var/_answer_a6 = verb_prompt(user, "a6", list("message" = "Allow it to be turned back off again?", "title" = "togglable", "choices" = list("Yes", "No", "Cancel")), args)
		if(isnull(_answer_a6))
			return
		check_togglable = _answer_a6
		if(!check_togglable || check_togglable == "Cancel")
			return
		if(check_togglable == "No")
			s_togglable = 0
		if(check_togglable == "Yes")
			var/_answer_a7 = verb_prompt(user, "a7", list("kind" = "text", "message" = "Deactivation text:", "title" = "Deactivation Text"), args)
			if(isnull(_answer_a7))
				return
			s_text_deactivated = _answer_a7
			s_togglable = 1
		var/_answer_a8 = verb_prompt(user, "a8", list("kind" = "list", "message" = "Choose activated icon state:", "title" = "icon_state_on", "choices" = icon_state_options), args)
		if(isnull(_answer_a8))
			return
		s_icon_state_on = _answer_a8
		// Uploads (s_icon2) are asked last: a file upload is a native dialog that waits.
		var/_answer_a9 = verb_prompt(user, "a9", list("kind" = "number", "message" = "Do you want it to take time to put turn on? Choose a number of deciseconds to activate, or 0 for instant.", "title" = "Delay"), args)
		if(isnull(_answer_a9))
			return
		s_delay = _answer_a9
		var/check_effect = verb_prompt(user, "a10", list("message" = "Produce an effect on activation?", "title" = "Effect?", "choices" = list("No", "Spark", "Flicker Lights", "Flash", "Spawn Item", "Cancel")), args)
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
			s_object = verb_prompt(user, "object", list("kind" = "typepath", "message" = "Enter full or partial typepath.", "title" = "Typepath"), args)
			if(isnull(s_object))
				return
		var/check_sound = verb_prompt(user, "a11", list("message" = "Play a sound when turning on?", "title" = "Sound", "choices" = list("Yes", "No", "Cancel")), args)
		if(isnull(check_sound))
			return
		if(!check_sound || check_sound == "Cancel")
			return
		if(check_sound == "Yes")
			var/_answer_a12 = verb_prompt(user, "a12", list("kind" = "list", "message" = "Choose a sound to play on activation:", "title" = "Sound", "choices" = sound_options), args)
			if(isnull(_answer_a12))
				return
			s_sound = _answer_a12

	// The uploads come last (allowlisted: a native file dialog, nothing to answer it asynchronously).
	if(s_icon_state_off == "Upload Own Sprite")
		s_icon = input(user, "Choose an image file to upload. Images that are not 32x32 will need to have their positions offset.","Upload Icon") as null|file // S10 keeps: file uploads need the BYOND file dialog
	if(s_icon_state_on == "Upload Own Sprite")
		s_icon2 = input(user, "Choose an image file to upload. Images that are not 32x32 will need to have their positions offset.","Upload Icon") as null|file // S10 keeps: file uploads need the BYOND file dialog

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
	P.update_icon()
