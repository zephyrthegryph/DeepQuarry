#define VORE_SIZE_MULT_MOB "mob"
#define VORE_SIZE_MULT_ITEM "item"
#define VORE_SIZE_MULT_OVERALL "overall"

/datum/vore_look/proc/attr_b_name(mob/user, list/params, extra)
	var/new_name = html_encode(params["val"])

	var/failure_msg
	if(length(new_name) > BELLIES_NAME_MAX || length(new_name) < BELLIES_NAME_MIN)
		failure_msg = "Entered belly name length invalid (must be longer than [BELLIES_NAME_MIN], no more than than [BELLIES_NAME_MAX])."
	else
		for(var/obj/belly/B as anything in host().vore_organs)
			if(lowertext(new_name) == lowertext(B.name))
				failure_msg = "No duplicate belly names, please."
				break

	if(failure_msg) //Something went wrong.
		tgui_alert_async(user,failure_msg,"Error!")
		return FALSE

	host().vore_selected.name = new_name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_display_name(mob/user, list/params, extra)
	var/new_name = html_encode(params["val"])
	if(length(new_name) > BELLIES_NAME_MAX)
		return FALSE
	host().vore_selected.display_name = new_name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_message_mode(mob/user, list/params, extra)
	host().vore_selected.message_mode = !host().vore_selected.message_mode
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_wetness(mob/user, list/params, extra)
	host().vore_selected.is_wet = !host().vore_selected.is_wet
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_wetloop(mob/user, list/params, extra)
	host().vore_selected.wet_loop = !host().vore_selected.wet_loop
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_mode(mob/user, list/params, extra)
	var/new_mode = params["val"]
	if(!(new_mode in host().vore_selected.digest_modes))
		return FALSE

	host().vore_selected.digest_mode = new_mode
	host().vore_selected.updateVRPanels()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_addons(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(toggle_addon in host().vore_selected.mode_flag_list))
		return FALSE
	host().vore_selected.mode_flags ^= host().vore_selected.mode_flag_list[toggle_addon]
	host().vore_selected.items_preserved = null //Re-evaltuate all items in belly on
	host().vore_selected.slow_digestion = FALSE
	if(host().vore_selected.mode_flags & DM_FLAG_SLOWBODY)
		host().vore_selected.slow_digestion = TRUE
	if(toggle_addon == "TURBO MODE")
		if(host().vore_selected.mode_flags & DM_FLAG_TURBOMODE)
			host().vore_selected.speedy_mob_processing = TRUE
			to_chat(user, span_warning("TURBO MODE activated! Belly processing speed tripled! This also affects timed settings, such as autotransfer and liquid generation."))
		else
			host().vore_selected.speedy_mob_processing = FALSE
			to_chat(user, span_warning("TURBO MODE deactivated. Belly processing returned to normal speed."))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_item_mode(mob/user, list/params, extra)
	var/new_mode = params["val"]
	if(!(new_mode in host().vore_selected.item_digest_modes))
		return FALSE

	host().vore_selected.item_digest_mode = new_mode
	host().vore_selected.items_preserved = null //Re-evaltuate all items in belly on belly-mode change
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_contaminates(mob/user, list/params, extra)
	host().vore_selected.contaminates = !host().vore_selected.contaminates
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_contamination_flavor(mob/user, list/params, extra)
	var/new_flavor = params["val"]
	if(!(new_flavor in GLOB.contamination_flavors))
		return FALSE
	host().vore_selected.contamination_flavor = new_flavor
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_contamination_color(mob/user, list/params, extra)
	var/new_color = params["val"]
	if(!(new_color in GLOB.contamination_colors))
		return FALSE
	host().vore_selected.contamination_color = new_color
	host().vore_selected.items_preserved = null //To re-contaminate for new color
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_egg_type(mob/user, list/params, extra)
	var/new_egg_type = params["val"]
	if(!(new_egg_type in GLOB.global_vore_egg_types))
		return FALSE
	host().vore_selected.egg_type = new_egg_type
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_egg_name(mob/user, list/params, extra)
	var/new_egg_name = sanitize(params["val"], BELLIES_NAME_MAX, FALSE, TRUE, FALSE)
	if(!new_egg_name)
		host().vore_selected.egg_name = null
	else
		host().vore_selected.egg_name = new_egg_name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_egg_size(mob/user, list/params, extra)
	var/new_egg_size = params["val"]
	if(!isnum(new_egg_size))
		return FALSE
	if(new_egg_size == 0) //Disable.
		host().vore_selected.egg_size = 0
		to_chat(user,span_notice("Eggs will automatically calculate size depending on contents."))
	else
		new_egg_size = CLAMP(new_egg_size, 25, 200)
		host().vore_selected.egg_size = (new_egg_size/100)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_recycling(mob/user, list/params, extra)
	host().vore_selected.recycling = !host().vore_selected.recycling
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_storing_nutrition(mob/user, list/params, extra)
	host().vore_selected.storing_nutrition = !host().vore_selected.storing_nutrition
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_belly_description_message(mob/user, list/params, extra)
	var/new_desc = html_encode(params["val"])

	if(new_desc)
		new_desc = readd_quotes(new_desc)
		if(length(new_desc) > BELLIES_DESC_MAX)
			tgui_alert_async(user, "Entered belly desc too long. [BELLIES_DESC_MAX] character limit.","Error")
			return FALSE
		host().vore_selected.desc = new_desc
		. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_belly_description_message_absroed(mob/user, list/params, extra)
	var/new_desc = html_encode(params["val"])

	if(new_desc)
		new_desc = readd_quotes(new_desc)
		if(length(new_desc) > BELLIES_DESC_MAX)
			tgui_alert_async(user, "Entered belly desc too long. [BELLIES_DESC_MAX] character limit.","Error")
			return FALSE
		host().vore_selected.absorbed_desc = new_desc
		. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_msgs(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	switch(params["msgtype"])
		if(DIGEST_PREY)
			host().vore_selected.set_messages(params["val"], DIGEST_PREY, limit = BELLIES_MESSAGE_MAX)

		if(DIGEST_OWNER)
			host().vore_selected.set_messages(params["val"], DIGEST_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORB_PREY)
			host().vore_selected.set_messages(params["val"], ABSORB_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORB_OWNER)
			host().vore_selected.set_messages(params["val"], ABSORB_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(UNABSORBS_PREY)
			host().vore_selected.set_messages(params["val"], UNABSORBS_PREY, limit = BELLIES_MESSAGE_MAX)

		if(UNABSORBS_OWNER)
			host().vore_selected.set_messages(params["val"], UNABSORBS_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(STRUGGLE_OUTSIDE)
			host().vore_selected.set_messages(params["val"], STRUGGLE_OUTSIDE, limit = BELLIES_MESSAGE_MAX)

		if(STRUGGLE_INSIDE)
			host().vore_selected.set_messages(params["val"], STRUGGLE_INSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_STRUGGLE_OUSIDE)
			host().vore_selected.set_messages(params["val"], ABSORBED_STRUGGLE_OUSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_STRUGGLE_INSIDE)
			host().vore_selected.set_messages(params["val"], ABSORBED_STRUGGLE_INSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ATTEMPT_PREY)
			host().vore_selected.set_messages(params["val"], ESCAPE_ATTEMPT_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ATTEMPT_OWNER)
			host().vore_selected.set_messages(params["val"], ESCAPE_ATTEMPT_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_PREY)
			host().vore_selected.set_messages(params["val"], ESCAPE_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_OWNER)
			host().vore_selected.set_messages(params["val"], ESCAPE_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_OUTSIDE)
			host().vore_selected.set_messages(params["val"], ESCAPE_OUTSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ITEM_PREY)
			host().vore_selected.set_messages(params["val"], ESCAPE_ITEM_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ITEM_OWNER)
			host().vore_selected.set_messages(params["val"], ESCAPE_ITEM_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ITEM_OUTSIDE)
			host().vore_selected.set_messages(params["val"], ESCAPE_ITEM_OUTSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_FAIL_PREY)
			host().vore_selected.set_messages(params["val"], ESCAPE_FAIL_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_FAIL_OWNER)
			host().vore_selected.set_messages(params["val"], ESCAPE_FAIL_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_ATTEMPT_PREY)
			host().vore_selected.set_messages(params["val"], ABSORBED_ESCAPE_ATTEMPT_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_ATTEMPT_OWNER)
			host().vore_selected.set_messages(params["val"], ABSORBED_ESCAPE_ATTEMPT_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_PREY)
			host().vore_selected.set_messages(params["val"], ABSORBED_ESCAPE_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_OWNER)
			host().vore_selected.set_messages(params["val"], ABSORBED_ESCAPE_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_OUTSIDE)
			host().vore_selected.set_messages(params["val"], ABSORBED_ESCAPE_OUTSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_FAIL_PREY)
			host().vore_selected.set_messages(params["val"], ABSORBED_ESCAPE_FAIL_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_FAIL_OWNER)
			host().vore_selected.set_messages(params["val"], ABSORBED_ESCAPE_FAIL_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(PRIMARY_TRANSFER_PREY)
			host().vore_selected.set_messages(params["val"], PRIMARY_TRANSFER_PREY, limit = BELLIES_MESSAGE_MAX)

		if(PRIMARY_TRANSFER_OWNER)
			host().vore_selected.set_messages(params["val"], PRIMARY_TRANSFER_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(SECONDARY_TRANSFER_PREY)
			host().vore_selected.set_messages(params["val"], SECONDARY_TRANSFER_PREY, limit = BELLIES_MESSAGE_MAX)

		if(SECONDARY_TRANSFER_OWNER)
			host().vore_selected.set_messages(params["val"], SECONDARY_TRANSFER_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(PRIMARY_AUTO_TRANSFER_PREY)
			host().vore_selected.set_messages(params["val"], PRIMARY_AUTO_TRANSFER_PREY, limit = BELLIES_MESSAGE_MAX)

		if(PRIMARY_AUTO_TRANSFER_OWNER)
			host().vore_selected.set_messages(params["val"], PRIMARY_AUTO_TRANSFER_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(SECONDARY_AUTO_TRANSFER_PREY)
			host().vore_selected.set_messages(params["val"], SECONDARY_AUTO_TRANSFER_PREY, limit = BELLIES_MESSAGE_MAX)

		if(SECONDARY_AUTO_TRANSFER_OWNER)
			host().vore_selected.set_messages(params["val"], SECONDARY_AUTO_TRANSFER_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(DIGEST_CHANCE_PREY)
			host().vore_selected.set_messages(params["val"], DIGEST_CHANCE_PREY, limit = BELLIES_MESSAGE_MAX)

		if(DIGEST_CHANCE_OWNER)
			host().vore_selected.set_messages(params["val"], DIGEST_CHANCE_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORB_CHANCE_PREY)
			host().vore_selected.set_messages(params["val"], ABSORB_CHANCE_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORB_CHANCE_OWNER)
			host().vore_selected.set_messages(params["val"], ABSORB_CHANCE_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(EXAMINES)
			host().vore_selected.set_messages(params["val"], EXAMINES, limit = BELLIES_EXAMINE_MAX)

		if(EXAMINES_ABSORBED)
			host().vore_selected.set_messages(params["val"], EXAMINES_ABSORBED, limit = BELLIES_EXAMINE_MAX)

		if(GENERAL_EXAMINE_NUTRI)
			sanitize_fixed_list(params["val"], GENERAL_EXAMINE_NUTRI, limit = BELLIES_EXAMINE_MAX)

		if(GENERAL_EXAMINE_WEIGHT)
			sanitize_fixed_list(params["val"], GENERAL_EXAMINE_WEIGHT, limit = BELLIES_EXAMINE_MAX)

		if(BELLY_TRASH_EATER_IN)
			host().vore_selected.set_messages(params["val"], BELLY_TRASH_EATER_IN, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_TRASH_EATER_OUT)
			host().vore_selected.set_messages(params["val"], BELLY_TRASH_EATER_OUT, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_MODE_DIGEST)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_DIGEST, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_HOLD)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_HOLD, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_HOLD_ABSORB)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_HOLD_ABSORB, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_ABSORB)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_ABSORB, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_HEAL)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_HEAL, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_DRAIN)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_DRAIN, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_STEAL)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_STEAL, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_EGG)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_EGG, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_SHRINK)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_SHRINK, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_GROW)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_GROW, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_UNABSORB)
			host().vore_selected.set_messages(params["val"], BELLY_MODE_UNABSORB, limit = BELLIES_IDLE_MAX)

		if(BELLY_LIQUID_MESSAGE1)
			host().vore_selected.set_messages(params["val"], BELLY_LIQUID_MESSAGE1, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_LIQUID_MESSAGE2)
			host().vore_selected.set_messages(params["val"], BELLY_LIQUID_MESSAGE2, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_LIQUID_MESSAGE3)
			host().vore_selected.set_messages(params["val"], BELLY_LIQUID_MESSAGE3, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_LIQUID_MESSAGE4)
			host().vore_selected.set_messages(params["val"], BELLY_LIQUID_MESSAGE4, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_LIQUID_MESSAGE5)
			host().vore_selected.set_messages(params["val"], BELLY_LIQUID_MESSAGE5, limit = BELLIES_MESSAGE_MAX)

		if("reset")
			open_request(ui, /datum/prompt/choice/vore_reset_messages, TYPE_PROC_REF(/datum/tgui, vore_reset_messages_answered), answerer = user, question = "This will delete any custom messages. Are you sure?", title = "Confirmation", choices = list("Cancel", "DELETE"), buttons = TRUE)
			return
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_verb(mob/user, list/params, extra)
	var/new_verb = html_encode(params["val"])

	if(length(new_verb) > BELLIES_NAME_MAX || length(new_verb) < BELLIES_NAME_MIN)
		tgui_alert_async(user, "Entered verb length invalid (must be longer than [BELLIES_NAME_MIN], no longer than [BELLIES_NAME_MAX]).","Error")
		return FALSE

	host().vore_selected.vore_verb = new_verb
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_release_verb(mob/user, list/params, extra)
	var/new_release_verb = html_encode(params["val"])

	if(length(new_release_verb) > BELLIES_NAME_MAX || length(new_release_verb) < BELLIES_NAME_MIN)
		tgui_alert_async(user, "Entered verb length invalid (must be longer than [BELLIES_NAME_MIN], no longer than [BELLIES_NAME_MAX]).","Error")
		return FALSE

	host().vore_selected.release_verb = new_release_verb
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_eating_privacy(mob/user, list/params, extra)
	var/privacy_choice = params["val"]
	if(!(privacy_choice in list("default", "subtle", "loud")))
		return FALSE
	host().vore_selected.eating_privacy_local = privacy_choice
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_silicon_belly(mob/user, list/params, extra)
	var/belly_choice = params["val"]
	if(!(belly_choice in list("Sleeper", "Vorebelly", "Both")))
		return FALSE
	for(var/obj/belly/B in host().vore_organs)
		B.silicon_belly_overlay_preference = belly_choice
	host().update_icon()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_belly_mob_mult(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	open_request(ui, /datum/prompt/number/vore_size_multiplier, TYPE_PROC_REF(/datum/tgui, vore_size_multiplier_answered), answerer = user, multiplier_kind = VORE_SIZE_MULT_MOB, displayed_max = 5, default = host().vore_selected.belly_mob_mult, question = "Choose the multiplier for mobs contributing to belly size, ranging from 0 to 5. Set to 0 to disable mobs contributing to belly size", title = "Set Prey Multiplier")

/datum/vore_look/proc/attr_b_belly_item_mult(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	open_request(ui, /datum/prompt/number/vore_size_multiplier, TYPE_PROC_REF(/datum/tgui, vore_size_multiplier_answered), answerer = user, multiplier_kind = VORE_SIZE_MULT_ITEM, displayed_max = 10, default = host().vore_selected.belly_item_mult, question = "Choose the multiplier for items contributing to belly size, ranging from 0 to 10. (Item size affects how much they contribute as well) Set to 0 to disable size checks", title = "Set Item Multiplier")

/datum/vore_look/proc/attr_b_belly_overall_mult(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	open_request(ui, /datum/prompt/number/vore_size_multiplier, TYPE_PROC_REF(/datum/tgui, vore_size_multiplier_answered), answerer = user, multiplier_kind = VORE_SIZE_MULT_OVERALL, displayed_max = 5, default = host().vore_selected.belly_overall_mult, question = "Choose the overall multiplier to be applied to belly contents after specific multipliers, ranging from 0 to 5. Set to 0 to disable showing belly sprites at all.", title = "Set minimum prey amount")

/datum/vore_look/proc/attr_b_fancy_sound(mob/user, list/params, extra)
	host().vore_selected.fancy_vore = !host().vore_selected.fancy_vore
	host().vore_selected.vore_sound = "Gulp"
	host().vore_selected.release_sound = "Splatter"
	// defaults as to avoid potential bugs
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_release(mob/user, list/params, extra)
	var/choice = params["val"]
	if(host().vore_selected.fancy_vore)
		if(!(choice in GLOB.fancy_release_sounds))
			return FALSE
	else if (!(choice in GLOB.classic_release_sounds))
		return FALSE
	host().vore_selected.release_sound = choice
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_releasesoundtest(mob/user, list/params, extra)
	var/sound/releasetest
	if(host().vore_selected.fancy_vore)
		releasetest = GLOB.fancy_release_sounds[host().vore_selected.release_sound]
	else
		releasetest = GLOB.classic_release_sounds[host().vore_selected.release_sound]

	if(releasetest)
		releasetest = sound(releasetest)
		releasetest.volume = host().vore_selected.sound_volume
		releasetest.frequency = host().vore_selected.noise_freq
		SEND_SOUND(user, releasetest)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_sound(mob/user, list/params, extra)
	var/choice = params["val"]
	if(host().vore_selected.fancy_vore)
		if(!(choice in GLOB.fancy_vore_sounds))
			return FALSE
	else if (!(choice in GLOB.classic_vore_sounds))
		return FALSE
	host().vore_selected.vore_sound = choice
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_soundtest(mob/user, list/params, extra)
	var/sound/voretest
	if(host().vore_selected.fancy_vore)
		voretest = GLOB.fancy_vore_sounds[host().vore_selected.vore_sound]
	else
		voretest = GLOB.classic_vore_sounds[host().vore_selected.vore_sound]
	if(voretest)
		voretest = sound(voretest)
		voretest.volume = host().vore_selected.sound_volume
		voretest.frequency = host().vore_selected.noise_freq
		SEND_SOUND(user, voretest)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_sound_volume(mob/user, list/params, extra)
	var/sound_volume_input = params["val"]
	if(!isnum(sound_volume_input))
		return FALSE
	host().vore_selected.sound_volume = sanitize_integer(sound_volume_input, 0, 100, initial(host().vore_selected.sound_volume))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_noise_freq(mob/user, list/params, extra)
	var/choice = params["val"]
	if(!isnum(choice))
		return FALSE
	if(choice == 0)
		choice = rand(MIN_VOICE_FREQ, MAX_VOICE_FREQ)
	host().vore_selected.noise_freq = CLAMP(choice, MIN_VOICE_FREQ, MAX_VOICE_FREQ)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_tastes(mob/user, list/params, extra)
	host().vore_selected.can_taste = !host().vore_selected.can_taste
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_feedable(mob/user, list/params, extra)
	host().vore_selected.is_feedable = !host().vore_selected.is_feedable
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_entrance_logs(mob/user, list/params, extra)
	host().vore_selected.entrance_logs = !host().vore_selected.entrance_logs
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_item_digest_logs(mob/user, list/params, extra)
	host().vore_selected.item_digest_logs = !host().vore_selected.item_digest_logs
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_bulge_size(mob/user, list/params, extra)
	var/new_bulge = params["val"]
	if(!isnum(new_bulge))
		return FALSE
	if(new_bulge == 0) //Disable.
		host().vore_selected.bulge_size = 0
		to_chat(user,span_notice("Your stomach will not be seen on examine."))
	else if(new_bulge)
		new_bulge = CLAMP(new_bulge, 25, 200)
		host().vore_selected.bulge_size = (new_bulge/100)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_display_absorbed_examine(mob/user, list/params, extra)
	host().vore_selected.display_absorbed_examine = !host().vore_selected.display_absorbed_examine
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_display_outside_struggle(mob/user, list/params, extra)
	host().vore_selected.toggle_displayed_message_flags(MS_FLAG_STRUGGLE_OUTSIDE)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_display_absorbed_outside_struggle(mob/user, list/params, extra)
	host().vore_selected.toggle_displayed_message_flags(MS_FLAG_STRUGGLE_ABSORBED_OUTSIDE)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_grow_shrink(mob/user, list/params, extra)
	var/new_grow = params["val"]
	if (!isnum(new_grow))
		return
	host().vore_selected.shrink_grow_size = CLAMP(new_grow, 25, 200) * 0.01
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_nutritionpercent(mob/user, list/params, extra)
	var/new_nutrition = params["val"]
	if(!isnum(new_nutrition))
		return FALSE
	host().vore_selected.nutrition_percent = CLAMP(new_nutrition, 0.01, 100)
	. = TRUE
	// modified these to be flexible rather than maxing at 6/6/12/6/6
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_burn_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	host().vore_selected.digest_burn = CLAMP(new_damage, 0, host().vore_selected.get_unused_digestion_damage() + host().vore_selected.digest_burn) // sanity check following tgui input
	host().vore_selected.items_preserved = null
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_brute_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	host().vore_selected.digest_brute = CLAMP(new_damage, 0, host().vore_selected.get_unused_digestion_damage() + host().vore_selected.digest_brute)
	host().vore_selected.items_preserved = null
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_oxy_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	host().vore_selected.digest_oxy = CLAMP(new_damage, 0, host().vore_selected.get_unused_digestion_damage() + host().vore_selected.digest_oxy)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_tox_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	host().vore_selected.digest_tox = CLAMP(new_damage, 0, host().vore_selected.get_unused_digestion_damage() + host().vore_selected.digest_tox)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_clone_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	host().vore_selected.digest_clone = CLAMP(new_damage, 0, host().vore_selected.get_unused_digestion_damage() + host().vore_selected.digest_clone)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_bellytemperature(mob/user, list/params, extra)
	var/new_temp = params["val"]
	if(!isnum(new_temp))
		return FALSE
	new_temp = new_temp + T0C
	host().vore_selected.bellytemperature = CLAMP(new_temp, T0C, 473.15)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_temperature_damage(mob/user, list/params, extra)
	host().vore_selected.temperature_damage = !host().vore_selected.temperature_damage
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_drainmode(mob/user, list/params, extra)
	var/new_drainmode = params["val"]
	if(!(new_drainmode in host().vore_selected.drainmodes))
		return FALSE
	host().vore_selected.drainmode = new_drainmode
	host().vore_selected.updateVRPanels()
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_emoteactive(mob/user, list/params, extra)
	host().vore_selected.emote_active = !host().vore_selected.emote_active
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_selective_mode_pref_toggle(mob/user, list/params, extra)
	var/new_mode = params["val"]
	switch(new_mode)
		if(DM_DIGEST)
			host().vore_selected.selective_preference = DM_DIGEST
		if(DM_ABSORB)
			host().vore_selected.selective_preference = DM_ABSORB
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_emotetime(mob/user, list/params, extra)
	var/new_time = params["val"]
	if(!isnum(new_time))
		return FALSE
	host().vore_selected.emote_time = CLAMP(new_time, 60, 600)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_escapable(mob/user, list/params, extra)
	var/new_mode = params["val"]
	switch(new_mode)
		if(B_ESCAPABLE_NONE) //Never escapable.
			host().vore_selected.escapable = B_ESCAPABLE_NONE
			to_chat(user,span_warning("Prey will not be able to have special interactions with your [lowertext(host().vore_selected.name)]."))
		if(B_ESCAPABLE_DEFAULT) //Possibly escapable and special interactions.
			host().vore_selected.escapable = B_ESCAPABLE_DEFAULT
			to_chat(user,span_warning("Prey now have special interactions with your [lowertext(host().vore_selected.name)] depending on your settings."))
		if(B_ESCAPABLE_INTENT) //Possibly escapable and special intent based interactions.
			host().vore_selected.escapable = B_ESCAPABLE_INTENT
			to_chat(user,span_warning("Prey now have special interactions with your [lowertext(host().vore_selected.name)] depending on your settings and their intent."))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_escapechance(mob/user, list/params, extra)
	var/escape_chance_input = params["val"]
	if(!isnum(escape_chance_input))
		return FALSE
	host().vore_selected.escapechance = sanitize_integer(escape_chance_input, 0, 100, initial(host().vore_selected.escapechance))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_belchchance(mob/user, list/params, extra)
	var/belch_chance_input = params["val"]
	if(!isnum(belch_chance_input))
		return FALSE
	host().vore_selected.belchchance = sanitize_integer(belch_chance_input, 0, 100, initial(host().vore_selected.belchchance))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_escapechance_absorbed(mob/user, list/params, extra)
	var/escape_absorbed_chance_input = params["val"]
	if(!isnum(escape_absorbed_chance_input))
		return FALSE
	host().vore_selected.escapechance_absorbed = sanitize_integer(escape_absorbed_chance_input, 0, 100, initial(host().vore_selected.escapechance_absorbed))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_escapetime(mob/user, list/params, extra)
	var/escape_time_input = params["val"]
	if(!isnum(escape_time_input))
		return FALSE
	host().vore_selected.escapetime = sanitize_integer(escape_time_input*10, 10, 600, initial(host().vore_selected.escapetime))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_transferchance(mob/user, list/params, extra)
	var/transfer_chance_input = params["val"]
	if(!isnum(transfer_chance_input))
		return FALSE
	host().vore_selected.transferchance = sanitize_integer(transfer_chance_input, 0, 100, initial(host().vore_selected.transferchance))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_transferlocation(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]

	if(!istype(choice))
		host().vore_selected.transferlocation = null
	else
		host().vore_selected.transferlocation = choice.name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_transferchance_secondary(mob/user, list/params, extra)
	var/transfer_secondary_chance_input = params["val"]
	if(!isnum(transfer_secondary_chance_input))
		return FALSE
	host().vore_selected.transferchance_secondary = sanitize_integer(transfer_secondary_chance_input, 0, 100, initial(host().vore_selected.transferchance_secondary))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_transferlocation_secondary(mob/user, list/params, extra)
	var/obj/belly/choice_secondary = params["val"]

	if(!istype(choice_secondary))
		host().vore_selected.transferlocation_secondary = null
	else
		host().vore_selected.transferlocation_secondary = choice_secondary.name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_absorbchance(mob/user, list/params, extra)
	var/absorb_chance_input = params["val"]
	if(!isnum(absorb_chance_input))
		return FALSE
	host().vore_selected.absorbchance = sanitize_integer(absorb_chance_input, 0, 100, initial(host().vore_selected.absorbchance))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_digestchance(mob/user, list/params, extra)
	var/digest_chance_input = params["val"]
	if(!isnum(digest_chance_input))
		return FALSE
	host().vore_selected.digestchance = sanitize_integer(digest_chance_input, 0, 100, initial(host().vore_selected.digestchance))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransferchance_primary(mob/user, list/params, extra)
	var/autotransferchance_input = params["val"]
	if(!isnum(autotransferchance_input))
		return FALSE
	host().vore_selected.autotransferchance = sanitize_integer(autotransferchance_input, 0, 100, initial(host().vore_selected.autotransferchance))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransferwait(mob/user, list/params, extra)
	var/autotransferwait_input = params["val"]
	if(!isnum(autotransferwait_input))
		return FALSE
	host().vore_selected.autotransferwait = sanitize_integer(autotransferwait_input*10, 10, 18000, initial(host().vore_selected.autotransferwait))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransferlocation_primary(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]

	if(!istype(choice))
		host().vore_selected.autotransferlocation = null
	else
		host().vore_selected.autotransferlocation = choice.name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransferextralocation_primary(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]
	if(!istype(choice))
		return FALSE
	else if(choice.name in host().vore_selected.autotransferextralocation)
		host().vore_selected.autotransferextralocation = host().vore_selected.autotransferextralocation - choice.name // Replace: the list may be shared
	else
		host().vore_selected.autotransferextralocation = host().vore_selected.autotransferextralocation + choice.name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransferchance_secondary(mob/user, list/params, extra)
	var/autotransferchance_secondary_input = params["val"]
	if(!isnum(autotransferchance_secondary_input))
		return FALSE
	host().vore_selected.autotransferchance_secondary = sanitize_integer(autotransferchance_secondary_input, 0, 100, initial(host().vore_selected.autotransferchance_secondary))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransferlocation_secondary(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]

	if(!choice)
		host().vore_selected.autotransferlocation_secondary = null
	else
		host().vore_selected.autotransferlocation_secondary = choice.name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransferextralocation_secondary(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]
	if(!istype(choice)) //They cancelled, no changes
		return FALSE
	else if(choice.name in host().vore_selected.autotransferextralocation_secondary)
		host().vore_selected.autotransferextralocation_secondary = host().vore_selected.autotransferextralocation_secondary - choice.name // Replace: the list may be shared
	else
		host().vore_selected.autotransferextralocation_secondary = host().vore_selected.autotransferextralocation_secondary + choice.name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_whitelist_primary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(host().vore_selected.autotransfer_flags_list[toggle_addon]))
		return FALSE
	host().vore_selected.autotransfer_whitelist ^= host().vore_selected.autotransfer_flags_list[toggle_addon]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_blacklist_primary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(host().vore_selected.autotransfer_flags_list[toggle_addon]))
		return FALSE
	host().vore_selected.autotransfer_blacklist ^= host().vore_selected.autotransfer_flags_list[toggle_addon]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_whitelist_secondary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(host().vore_selected.autotransfer_flags_list[toggle_addon]))
		return FALSE
	host().vore_selected.autotransfer_secondary_whitelist ^= host().vore_selected.autotransfer_flags_list[toggle_addon]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_blacklist_secondary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(host().vore_selected.autotransfer_flags_list[toggle_addon]))
		return FALSE
	host().vore_selected.autotransfer_secondary_blacklist ^= host().vore_selected.autotransfer_flags_list[toggle_addon]
	. = TRUE
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_whitelist_items_primary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(host().vore_selected.autotransfer_flags_list_items[toggle_addon]))
		return FALSE
	host().vore_selected.autotransfer_whitelist_items ^= host().vore_selected.autotransfer_flags_list_items[toggle_addon]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_blacklist_items_primary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(host().vore_selected.autotransfer_flags_list_items[toggle_addon]))
		return FALSE
	host().vore_selected.autotransfer_blacklist_items ^= host().vore_selected.autotransfer_flags_list_items[toggle_addon]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_whitelist_items_secondary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(host().vore_selected.autotransfer_flags_list_items[toggle_addon]))
		return FALSE
	host().vore_selected.autotransfer_secondary_whitelist_items ^= host().vore_selected.autotransfer_flags_list_items[toggle_addon]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_blacklist_items_secondary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(host().vore_selected.autotransfer_flags_list_items[toggle_addon]))
		return FALSE
	host().vore_selected.autotransfer_secondary_blacklist_items ^= host().vore_selected.autotransfer_flags_list_items[toggle_addon]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_min_amount(mob/user, list/params, extra)
	var/autotransfer_min_amount_input = params["val"]
	if(!isnum(autotransfer_min_amount_input))
		return FALSE
	host().vore_selected.autotransfer_min_amount = sanitize_integer(autotransfer_min_amount_input, 0, 100, initial(host().vore_selected.autotransfer_min_amount))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_max_amount(mob/user, list/params, extra)
	var/autotransfer_max_amount_input = params["val"]
	if(!isnum(autotransfer_max_amount_input))
		return FALSE
	host().vore_selected.autotransfer_max_amount = sanitize_integer(autotransfer_max_amount_input, 0, 100, initial(host().vore_selected.autotransfer_max_amount))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_autotransfer_enabled(mob/user, list/params, extra)
	host().vore_selected.autotransfer_enabled = !host().vore_selected.autotransfer_enabled
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_fullscreen(mob/user, list/params, extra)
	host().vore_selected.belly_fullscreen = params["val"]
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_disable_hud(mob/user, list/params, extra)
	host().vore_selected.disable_hud = !host().vore_selected.disable_hud
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_colorization_enabled(mob/user, list/params, extra)
	host().vore_selected.colorization_enabled = !host().vore_selected.colorization_enabled
	host().vore_selected.belly_fullscreen = "dark" //This prevents you from selecting a belly that is not meant to be colored and then turning colorization on.
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_preview_belly(mob/user, list/params, extra)
	host().vore_selected.vore_preview(host()) //Gives them the stomach overlay. It fades away after ~2 seconds as human/life.dm removes the overlay if not in a gut.
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_clear_preview(mob/user, list/params, extra)
	host().vore_selected.clear_preview(host()) //Clears the stomach overlay. This is a failsafe but shouldn't occur.
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_fullscreen_color(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		host().vore_selected.belly_fullscreen_color = newcolor
		host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_fullscreen_color2(mob/user, list/params, extra)
	var/newcolor2 = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor2)
		host().vore_selected.belly_fullscreen_color2 = newcolor2
		host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_fullscreen_color3(mob/user, list/params, extra)
	var/newcolor3 = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor3)
		host().vore_selected.belly_fullscreen_color3 = newcolor3
		host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_fullscreen_color4(mob/user, list/params, extra)
	var/newcolor4 = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor4)
		host().vore_selected.belly_fullscreen_color4 = newcolor4
		host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_fullscreen_alpha(mob/user, list/params, extra)
	var/newalpha = params["val"]
	if(!isnum(newalpha))
		return FALSE
	host().vore_selected.belly_fullscreen_alpha = newalpha
	host().vore_selected.update_internal_overlay()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_save_digest_mode(mob/user, list/params, extra)
	host().vore_selected.save_digest_mode = !host().vore_selected.save_digest_mode
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_del(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	open_request(ui, /datum/prompt/choice/vore_delete_belly, TYPE_PROC_REF(/datum/tgui, vore_delete_belly_answered), answerer = user, question = "Are you sure you want to delete your [lowertext(host().vore_selected.name)]?", title = "Confirmation", choices = list("Cancel", "Delete"), buttons = TRUE)

/datum/vore_look/proc/attr_b_private_struggle(mob/user, list/params, extra)
	host().vore_selected.private_struggle = !host().vore_selected.private_struggle
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_absorbedrename_enabled(mob/user, list/params, extra)
	host().vore_selected.absorbedrename_enabled = !host().vore_selected.absorbedrename_enabled
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_absorbedrename_name(mob/user, list/params, extra)
	var/new_absorbedrename_name = sanitize(params["val"], MAX_MESSAGE_LEN, FALSE, TRUE, FALSE)
	if(new_absorbedrename_name)
		host().vore_selected.absorbedrename_name = new_absorbedrename_name
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_vorespawn_blacklist(mob/user, list/params, extra)
	host().vore_selected.vorespawn_blacklist = !host().vore_selected.vorespawn_blacklist
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_vorespawn_whitelist(mob/user, list/params, extra)
	var/new_vorespawn_whitelist = sanitize(params["val"], MAX_MESSAGE_LEN, FALSE, TRUE, FALSE)
	if(new_vorespawn_whitelist)
		host().vore_selected.vorespawn_whitelist = splittext(lowertext(new_vorespawn_whitelist),"\n")
	else
		host().vore_selected.vorespawn_whitelist = list()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_vorespawn_absorbed(mob/user, list/params, extra)
	var/current_number = params["val"]
	switch(current_number)
		if("Yes")
			host().vore_selected.vorespawn_absorbed |= VS_FLAG_ABSORB_YES
		if("Prey Choice")
			host().vore_selected.vorespawn_absorbed |= VS_FLAG_ABSORB_PREY
		if("No")
			host().vore_selected.vorespawn_absorbed &= ~(VS_FLAG_ABSORB_YES)
			host().vore_selected.vorespawn_absorbed &= ~(VS_FLAG_ABSORB_PREY)
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_belly_sprite_to_affect(mob/user, list/params, extra)
	var/belly_choice = params["val"]
	if(!(belly_choice in host().vore_icon_bellies))
		return FALSE
	host().vore_selected.belly_sprite_to_affect = belly_choice
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_affects_vore_sprites(mob/user, list/params, extra)
	host().vore_selected.affects_vore_sprites = !host().vore_selected.affects_vore_sprites
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_count_absorbed_prey_for_sprites(mob/user, list/params, extra)
	host().vore_selected.count_absorbed_prey_for_sprite = !host().vore_selected.count_absorbed_prey_for_sprite
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_absorbed_multiplier(mob/user, list/params, extra)
	var/absorbed_multiplier_input = params["val"]
	if(!isnum(absorbed_multiplier_input))
		return FALSE
	host().vore_selected.absorbed_multiplier = CLAMP(absorbed_multiplier_input, 0.1, 3)
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_count_items_for_sprites(mob/user, list/params, extra)
	host().vore_selected.count_items_for_sprite = !host().vore_selected.count_items_for_sprite
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_item_multiplier(mob/user, list/params, extra)
	var/item_multiplier_input = params["val"]
	if(!isnum(item_multiplier_input))
		return FALSE
	host().vore_selected.item_multiplier = CLAMP(item_multiplier_input, 0.1, 10)
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_health_impacts_size(mob/user, list/params, extra)
	host().vore_selected.health_impacts_size = !host().vore_selected.health_impacts_size
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_resist_animation(mob/user, list/params, extra)
	host().vore_selected.resist_triggers_animation = !host().vore_selected.resist_triggers_animation
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_size_factor_sprites(mob/user, list/params, extra)
	var/size_factor_input = params["val"]
	if(!isnum(size_factor_input))
		return FALSE
	host().vore_selected.size_factor_for_sprite = CLAMP(size_factor_input, 0.1, 3)
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_vore_sprite_flags(mob/user, list/params, extra)
	var/toggle_vs_flag = params["val"]
	if(!(toggle_vs_flag in host().vore_selected.vore_sprite_flag_list))
		return FALSE
	host().vore_selected.vore_sprite_flags ^= host().vore_selected.vore_sprite_flag_list[toggle_vs_flag]
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_count_liquid_for_sprites(mob/user, list/params, extra)
	host().vore_selected.count_liquid_for_sprite = !host().vore_selected.count_liquid_for_sprite
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_liquid_multiplier(mob/user, list/params, extra)
	var/liquid_multiplier_input = params["val"]
	if(!isnum(liquid_multiplier_input))
		return FALSE
	host().vore_selected.liquid_multiplier = CLAMP(liquid_multiplier_input, 0.1, 10)
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_undergarment_choice(mob/user, list/params, extra)
	var/new_undergarment = params["val"]
	if(!(GLOB.global_underwear.categories_by_name[new_undergarment]))
		return FALSE
	host().vore_selected.undergarment_chosen = new_undergarment
	host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_undergarment_if_none(mob/user, list/params, extra)
	var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories_by_name[host().vore_selected.undergarment_chosen]
	var/selected_underwear = UWC.items_by_name[params["val"]]
	if(!selected_underwear) //They cancelled, no changes
		return FALSE

	host().vore_selected.undergarment_if_none = selected_underwear
	host().handle_belly_update()
	host().updateVRPanel()
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_undergarment_color(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		host().vore_selected.undergarment_color = newcolor
		host().handle_belly_update()
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_tail_to_change_to(mob/user, list/params, extra)
	var/tail_choice = params["val"]
	if(!(tail_choice in GLOB.tail_styles_list))
		return FALSE
	host().vore_selected.tail_to_change_to_static = tail_choice
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_tail_color(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		host().vore_selected.tail_colouration = newcolor
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_tail_color2(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		host().vore_selected.tail_extra_overlay = newcolor
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_tail_color3(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		host().vore_selected.tail_extra_overlay2 = newcolor
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_show_liq_fullness(mob/user, list/params, extra)
	if(!host().vore_selected.show_fullness_messages)
		host().vore_selected.show_fullness_messages = 1
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] now has liquid examination options."))
	else
		host().vore_selected.show_fullness_messages = 0
		to_chat(user,span_warning("Your [lowertext(host().vore_selected.name)] no longer has liquid examination options."))
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_liq_msg_toggle1(mob/user, list/params, extra)
	host().vore_selected.liquid_fullness1_messages = !host().vore_selected.liquid_fullness1_messages
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_liq_msg_toggle2(mob/user, list/params, extra)
	host().vore_selected.liquid_fullness2_messages = !host().vore_selected.liquid_fullness2_messages
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_liq_msg_toggle3(mob/user, list/params, extra)
	host().vore_selected.liquid_fullness3_messages = !host().vore_selected.liquid_fullness3_messages
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_liq_msg_toggle4(mob/user, list/params, extra)
	host().vore_selected.liquid_fullness4_messages = !host().vore_selected.liquid_fullness4_messages
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/datum/vore_look/proc/attr_b_liq_msg_toggle5(mob/user, list/params, extra)
	host().vore_selected.liquid_fullness5_messages = !host().vore_selected.liquid_fullness5_messages
	. = TRUE
	if(.)
		unsaved_changes = TRUE

/// A nested attribute replay retains its original UI, but rereads the current selected belly.
/datum/prompt/number/vore_size_multiplier
	timeout = 0
	recheck_on_open = TRUE
	var/multiplier_kind
	var/displayed_max

/datum/prompt/number/vore_size_multiplier/normalize(given)
	return given

/datum/prompt/number/vore_size_multiplier/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title, default || 0, displayed_max, 0, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/number/vore_size_multiplier/recheck_extra()
	if(QDELETED(answerer))
		return "gone"
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui))
		return "gone"
	var/datum/vore_look/panel = original_ui.src_object()
	if(!istype(panel) || QDELETED(panel))
		return "gone"
	return null

/datum/tgui/proc/vore_size_multiplier_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/vore_size_multiplier/request = A.answer
	var/datum/vore_look/panel = src_object()
	switch(request.multiplier_kind)
		if(VORE_SIZE_MULT_MOB)
			panel.host().vore_selected.belly_mob_mult = CLAMP(request.value, 0, 5)
		if(VORE_SIZE_MULT_ITEM)
			panel.host().vore_selected.belly_item_mult = CLAMP(request.value, 0, 10)
		if(VORE_SIZE_MULT_OVERALL)
			panel.host().vore_selected.belly_overall_mult = CLAMP(request.value, 0, 5)
	panel.host().update_icon()
	panel.unsaved_changes = TRUE

#undef VORE_SIZE_MULT_MOB
#undef VORE_SIZE_MULT_ITEM
#undef VORE_SIZE_MULT_OVERALL


/datum/prompt/choice/vore_reset_messages
	timeout = 0
	recheck_on_open = TRUE

/datum/prompt/choice/vore_reset_messages/recheck_extra()
	if(QDELETED(answerer))
		return "gone"
	var/datum/tgui/original_ui = owner
	if(!istype(original_ui) || QDELETED(original_ui))
		return "gone"
	var/datum/vore_look/panel = original_ui.src_object()
	if(!istype(panel) || QDELETED(panel))
		return "gone"
	return null

/datum/tgui/proc/vore_reset_messages_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/vore_look/panel = src_object()
	if(A.answer.value == "DELETE")
		panel.host().vore_selected.digest_messages_prey = panel.host().vore_selected.belly_shared_list("digest_messages_prey")
		panel.host().vore_selected.digest_messages_owner = panel.host().vore_selected.belly_shared_list("digest_messages_owner")
		panel.host().vore_selected.absorb_messages_prey = panel.host().vore_selected.belly_shared_list("absorb_messages_prey")
		panel.host().vore_selected.absorb_messages_owner = panel.host().vore_selected.belly_shared_list("absorb_messages_owner")
		panel.host().vore_selected.unabsorb_messages_prey = panel.host().vore_selected.belly_shared_list("unabsorb_messages_prey")
		panel.host().vore_selected.unabsorb_messages_owner = panel.host().vore_selected.belly_shared_list("unabsorb_messages_owner")
		panel.host().vore_selected.struggle_messages_outside = panel.host().vore_selected.belly_shared_list("struggle_messages_outside")
		panel.host().vore_selected.struggle_messages_inside = panel.host().vore_selected.belly_shared_list("struggle_messages_inside")
		panel.host().vore_selected.absorbed_struggle_messages_outside = panel.host().vore_selected.belly_shared_list("absorbed_struggle_messages_outside")
		panel.host().vore_selected.absorbed_struggle_messages_inside = panel.host().vore_selected.belly_shared_list("absorbed_struggle_messages_inside")
		panel.host().vore_selected.escape_attempt_messages_owner = panel.host().vore_selected.belly_shared_list("escape_attempt_messages_owner")
		panel.host().vore_selected.escape_attempt_messages_prey = panel.host().vore_selected.belly_shared_list("escape_attempt_messages_prey")
		panel.host().vore_selected.escape_messages_owner = panel.host().vore_selected.belly_shared_list("escape_messages_owner")
		panel.host().vore_selected.escape_messages_prey = panel.host().vore_selected.belly_shared_list("escape_messages_prey")
		panel.host().vore_selected.escape_messages_outside = panel.host().vore_selected.belly_shared_list("escape_messages_outside")
		panel.host().vore_selected.escape_item_messages_owner = panel.host().vore_selected.belly_shared_list("escape_item_messages_owner")
		panel.host().vore_selected.escape_item_messages_prey = panel.host().vore_selected.belly_shared_list("escape_item_messages_prey")
		panel.host().vore_selected.escape_item_messages_outside = panel.host().vore_selected.belly_shared_list("escape_item_messages_outside")
		panel.host().vore_selected.escape_fail_messages_owner = panel.host().vore_selected.belly_shared_list("escape_fail_messages_owner")
		panel.host().vore_selected.escape_fail_messages_prey = panel.host().vore_selected.belly_shared_list("escape_fail_messages_prey")
		panel.host().vore_selected.escape_attempt_absorbed_messages_owner = panel.host().vore_selected.belly_shared_list("escape_attempt_absorbed_messages_owner")
		panel.host().vore_selected.escape_attempt_absorbed_messages_prey = panel.host().vore_selected.belly_shared_list("escape_attempt_absorbed_messages_prey")
		panel.host().vore_selected.escape_absorbed_messages_owner = panel.host().vore_selected.belly_shared_list("escape_absorbed_messages_owner")
		panel.host().vore_selected.escape_absorbed_messages_prey = panel.host().vore_selected.belly_shared_list("escape_absorbed_messages_prey")
		panel.host().vore_selected.escape_absorbed_messages_outside = panel.host().vore_selected.belly_shared_list("escape_absorbed_messages_outside")
		panel.host().vore_selected.escape_fail_absorbed_messages_owner = panel.host().vore_selected.belly_shared_list("escape_fail_absorbed_messages_owner")
		panel.host().vore_selected.escape_fail_absorbed_messages_prey = panel.host().vore_selected.belly_shared_list("escape_fail_absorbed_messages_prey")
		panel.host().vore_selected.primary_transfer_messages_owner = panel.host().vore_selected.belly_shared_list("primary_transfer_messages_owner")
		panel.host().vore_selected.primary_transfer_messages_prey = panel.host().vore_selected.belly_shared_list("primary_transfer_messages_prey")
		panel.host().vore_selected.secondary_transfer_messages_owner = panel.host().vore_selected.belly_shared_list("secondary_transfer_messages_owner")
		panel.host().vore_selected.secondary_transfer_messages_prey = panel.host().vore_selected.belly_shared_list("secondary_transfer_messages_prey")
		panel.host().vore_selected.primary_autotransfer_messages_owner = panel.host().vore_selected.belly_shared_list("primary_autotransfer_messages_owner")
		panel.host().vore_selected.primary_autotransfer_messages_prey = panel.host().vore_selected.belly_shared_list("primary_autotransfer_messages_prey")
		panel.host().vore_selected.secondary_autotransfer_messages_owner = panel.host().vore_selected.belly_shared_list("secondary_autotransfer_messages_owner")
		panel.host().vore_selected.secondary_autotransfer_messages_prey = panel.host().vore_selected.belly_shared_list("secondary_autotransfer_messages_prey")
		panel.host().vore_selected.digest_chance_messages_owner = panel.host().vore_selected.belly_shared_list("digest_chance_messages_owner")
		panel.host().vore_selected.digest_chance_messages_prey = panel.host().vore_selected.belly_shared_list("digest_chance_messages_prey")
		panel.host().vore_selected.absorb_chance_messages_owner = panel.host().vore_selected.belly_shared_list("absorb_chance_messages_owner")
		panel.host().vore_selected.absorb_chance_messages_prey = panel.host().vore_selected.belly_shared_list("absorb_chance_messages_prey")
		panel.host().vore_selected.examine_messages = panel.host().vore_selected.belly_shared_list("examine_messages")
		panel.host().vore_selected.examine_messages_absorbed = panel.host().vore_selected.belly_shared_list("examine_messages_absorbed")
		panel.host().vore_selected.emote_lists = panel.host().vore_selected.belly_shared_list("emote_lists")
		panel.host().vore_selected.trash_eater_in = panel.host().vore_selected.belly_shared_list("trash_eater_in")
		panel.host().vore_selected.trash_eater_out = panel.host().vore_selected.belly_shared_list("trash_eater_out")
		panel.host().vore_selected.liquid_fullness1_messages = panel.host().vore_selected.belly_shared_list("fullness1_messages")
		panel.host().vore_selected.liquid_fullness2_messages = panel.host().vore_selected.belly_shared_list("fullness2_messages")
		panel.host().vore_selected.liquid_fullness3_messages = panel.host().vore_selected.belly_shared_list("fullness3_messages")
		panel.host().vore_selected.liquid_fullness4_messages = panel.host().vore_selected.belly_shared_list("fullness4_messages")
		panel.host().vore_selected.liquid_fullness5_messages = panel.host().vore_selected.belly_shared_list("fullness5_messages")
		panel.unsaved_changes = TRUE

/datum/prompt/choice/vore_delete_belly
	parent_type = /datum/prompt/choice/vore_reset_messages

/datum/prompt/choice/vore_delete_belly/recheck_extra()
	. = ..()
	if(.)
		return
	if(value != "Delete")
		return null
	var/datum/tgui/original_ui = owner
	var/datum/vore_look/panel = original_ui.src_object()
	return panel.vore_delete_belly_refusal()

/datum/vore_look/proc/vore_delete_belly_refusal()
	var/failure_msg = ""

	var/dest_for //Check to see if it's the destination of another vore organ.
	for(var/obj/belly/B as anything in host().vore_organs)
		if(B.transferlocation == host().vore_selected)
			dest_for = B.name
			failure_msg += "This is the destiantion for at least '[dest_for]' belly transfers. Remove it as the destination from any bellies before deleting it. "
			break
		if(B.transferlocation_secondary == host().vore_selected)
			dest_for = B.name
			failure_msg += "This is the destiantion for at least '[dest_for]' secondary belly transfers. Remove it as the destination from any bellies before deleting it. "
			break

	if(contents_count(host().vore_selected))
		failure_msg += "You cannot delete bellies with contents! " //These end with spaces, to be nice looking. Make sure you do the same.
	if(host().vore_selected.immutable)
		failure_msg += "This belly is marked as undeletable. "
	if(length(host().vore_organs) == 1)
		failure_msg += "You must have at least one belly. "

	return length(failure_msg) ? failure_msg : null

/datum/tgui/proc/vore_delete_belly_answered(datum/act/request/A)
	var/datum/vore_look/panel = src_object()
	if(!A.answer)
		if(!isnull(A.request.value) && A.request.last_error && A.request.last_error != "gone")
			tgui_alert_async(A.request.answerer, A.request.last_error, "Error!")
		return
	if(A.answer.value == "Delete")
		panel.vore_delete_belly_apply()
		panel.unsaved_changes = TRUE

/datum/vore_look/proc/vore_delete_belly_apply()
	if(host().soulgem?.linked_belly() == host().vore_selected)
		host().soulgem.linked_belly = null

	spent(host().vore_selected, src)
	host().vore_selected = host().vore_organs[1]

/// /datum/vore_look's "attr" sub-actions (a nested message its window op routes): each one's arguments go through their schemas first.
/datum/vore_look/proc/attr_subaction(action, list/data, mob/user, extra)
	switch(action)
		if(BELLY_DESCRIPTION_MESSAGE)
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_belly_description_message(user, typed, extra) : FALSE
		if(BELLY_DESCRIPTION_MESSAGE_ABSROED)
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_belly_description_message_absroed(user, typed, extra) : FALSE
		if("b_name")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_name(user, typed, extra) : FALSE
		if("b_display_name")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_display_name(user, typed, extra) : FALSE
		if("b_message_mode")
			return attr_b_message_mode(user, list(), extra)
		if("b_wetness")
			return attr_b_wetness(user, list(), extra)
		if("b_wetloop")
			return attr_b_wetloop(user, list(), extra)
		if("b_mode")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_mode(user, typed, extra) : FALSE
		if("b_addons")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_addons(user, typed, extra) : FALSE
		if("b_item_mode")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_item_mode(user, typed, extra) : FALSE
		if("b_contaminates")
			return attr_b_contaminates(user, list(), extra)
		if("b_contamination_flavor")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_contamination_flavor(user, typed, extra) : FALSE
		if("b_contamination_color")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_contamination_color(user, typed, extra) : FALSE
		if("b_egg_type")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_egg_type(user, typed, extra) : FALSE
		if("b_egg_name")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_egg_name(user, typed, extra) : FALSE
		if("b_egg_size")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_egg_size(user, typed, extra) : FALSE
		if("b_recycling")
			return attr_b_recycling(user, list(), extra)
		if("b_storing_nutrition")
			return attr_b_storing_nutrition(user, list(), extra)
		if("b_msgs")
			var/list/typed = payload_args(src, data, list("msgtype" = null, "val" = schema_text(4096)))
			return typed ? attr_b_msgs(user, typed, extra) : FALSE
		if("b_verb")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_verb(user, typed, extra) : FALSE
		if("b_release_verb")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_release_verb(user, typed, extra) : FALSE
		if("b_eating_privacy")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_eating_privacy(user, typed, extra) : FALSE
		if("b_silicon_belly")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_silicon_belly(user, typed, extra) : FALSE
		if("b_belly_mob_mult")
			return attr_b_belly_mob_mult(user, list(), extra)
		if("b_belly_item_mult")
			return attr_b_belly_item_mult(user, list(), extra)
		if("b_belly_overall_mult")
			return attr_b_belly_overall_mult(user, list(), extra)
		if("b_fancy_sound")
			return attr_b_fancy_sound(user, list(), extra)
		if("b_release")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_release(user, typed, extra) : FALSE
		if("b_releasesoundtest")
			return attr_b_releasesoundtest(user, list(), extra)
		if("b_sound")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_sound(user, typed, extra) : FALSE
		if("b_soundtest")
			return attr_b_soundtest(user, list(), extra)
		if("b_sound_volume")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_sound_volume(user, typed, extra) : FALSE
		if("b_noise_freq")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_noise_freq(user, typed, extra) : FALSE
		if("b_tastes")
			return attr_b_tastes(user, list(), extra)
		if("b_feedable")
			return attr_b_feedable(user, list(), extra)
		if("b_entrance_logs")
			return attr_b_entrance_logs(user, list(), extra)
		if("b_item_digest_logs")
			return attr_b_item_digest_logs(user, list(), extra)
		if("b_bulge_size")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_bulge_size(user, typed, extra) : FALSE
		if("b_display_absorbed_examine")
			return attr_b_display_absorbed_examine(user, list(), extra)
		if("b_display_outside_struggle")
			return attr_b_display_outside_struggle(user, list(), extra)
		if("b_display_absorbed_outside_struggle")
			return attr_b_display_absorbed_outside_struggle(user, list(), extra)
		if("b_grow_shrink")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_grow_shrink(user, typed, extra) : FALSE
		if("b_nutritionpercent")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_nutritionpercent(user, typed, extra) : FALSE
		if("b_burn_dmg")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_burn_dmg(user, typed, extra) : FALSE
		if("b_brute_dmg")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_brute_dmg(user, typed, extra) : FALSE
		if("b_oxy_dmg")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_oxy_dmg(user, typed, extra) : FALSE
		if("b_tox_dmg")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_tox_dmg(user, typed, extra) : FALSE
		if("b_clone_dmg")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_clone_dmg(user, typed, extra) : FALSE
		if("b_bellytemperature")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_bellytemperature(user, typed, extra) : FALSE
		if("b_temperature_damage")
			return attr_b_temperature_damage(user, list(), extra)
		if("b_drainmode")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_drainmode(user, typed, extra) : FALSE
		if("b_emoteactive")
			return attr_b_emoteactive(user, list(), extra)
		if("b_selective_mode_pref_toggle")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_selective_mode_pref_toggle(user, typed, extra) : FALSE
		if("b_emotetime")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_emotetime(user, typed, extra) : FALSE
		if("b_escapable")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_escapable(user, typed, extra) : FALSE
		if("b_escapechance")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_escapechance(user, typed, extra) : FALSE
		if("b_belchchance")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_belchchance(user, typed, extra) : FALSE
		if("b_escapechance_absorbed")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_escapechance_absorbed(user, typed, extra) : FALSE
		if("b_escapetime")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_escapetime(user, typed, extra) : FALSE
		if("b_transferchance")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_transferchance(user, typed, extra) : FALSE
		if("b_transferlocation")
			var/list/typed = payload_args(src, data, list("val" = schema_ref(/obj/belly)))
			return typed ? attr_b_transferlocation(user, typed, extra) : FALSE
		if("b_transferchance_secondary")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_transferchance_secondary(user, typed, extra) : FALSE
		if("b_transferlocation_secondary")
			var/list/typed = payload_args(src, data, list("val" = schema_ref(/obj/belly)))
			return typed ? attr_b_transferlocation_secondary(user, typed, extra) : FALSE
		if("b_absorbchance")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_absorbchance(user, typed, extra) : FALSE
		if("b_digestchance")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_digestchance(user, typed, extra) : FALSE
		if("b_autotransferchance_primary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransferchance_primary(user, typed, extra) : FALSE
		if("b_autotransferwait")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_autotransferwait(user, typed, extra) : FALSE
		if("b_autotransferlocation_primary")
			var/list/typed = payload_args(src, data, list("val" = schema_ref(/obj/belly)))
			return typed ? attr_b_autotransferlocation_primary(user, typed, extra) : FALSE
		if("b_autotransferextralocation_primary")
			var/list/typed = payload_args(src, data, list("val" = schema_ref(/obj/belly)))
			return typed ? attr_b_autotransferextralocation_primary(user, typed, extra) : FALSE
		if("b_autotransferchance_secondary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransferchance_secondary(user, typed, extra) : FALSE
		if("b_autotransferlocation_secondary")
			var/list/typed = payload_args(src, data, list("val" = schema_ref(/obj/belly)))
			return typed ? attr_b_autotransferlocation_secondary(user, typed, extra) : FALSE
		if("b_autotransferextralocation_secondary")
			var/list/typed = payload_args(src, data, list("val" = schema_ref(/obj/belly)))
			return typed ? attr_b_autotransferextralocation_secondary(user, typed, extra) : FALSE
		if("b_autotransfer_whitelist_primary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransfer_whitelist_primary(user, typed, extra) : FALSE
		if("b_autotransfer_blacklist_primary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransfer_blacklist_primary(user, typed, extra) : FALSE
		if("b_autotransfer_whitelist_secondary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransfer_whitelist_secondary(user, typed, extra) : FALSE
		if("b_autotransfer_blacklist_secondary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransfer_blacklist_secondary(user, typed, extra) : FALSE
		if("b_autotransfer_whitelist_items_primary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransfer_whitelist_items_primary(user, typed, extra) : FALSE
		if("b_autotransfer_blacklist_items_primary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransfer_blacklist_items_primary(user, typed, extra) : FALSE
		if("b_autotransfer_whitelist_items_secondary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransfer_whitelist_items_secondary(user, typed, extra) : FALSE
		if("b_autotransfer_blacklist_items_secondary")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_autotransfer_blacklist_items_secondary(user, typed, extra) : FALSE
		if("b_autotransfer_min_amount")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_autotransfer_min_amount(user, typed, extra) : FALSE
		if("b_autotransfer_max_amount")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_autotransfer_max_amount(user, typed, extra) : FALSE
		if("b_autotransfer_enabled")
			return attr_b_autotransfer_enabled(user, list(), extra)
		if("b_fullscreen")
			var/list/typed = payload_args(src, data, list("val" = null))
			return typed ? attr_b_fullscreen(user, typed, extra) : FALSE
		if("b_disable_hud")
			return attr_b_disable_hud(user, list(), extra)
		if("b_colorization_enabled")
			return attr_b_colorization_enabled(user, list(), extra)
		if("b_preview_belly")
			return attr_b_preview_belly(user, list(), extra)
		if("b_clear_preview")
			return attr_b_clear_preview(user, list(), extra)
		if("b_fullscreen_color")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_fullscreen_color(user, typed, extra) : FALSE
		if("b_fullscreen_color2")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_fullscreen_color2(user, typed, extra) : FALSE
		if("b_fullscreen_color3")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_fullscreen_color3(user, typed, extra) : FALSE
		if("b_fullscreen_color4")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_fullscreen_color4(user, typed, extra) : FALSE
		if("b_fullscreen_alpha")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_fullscreen_alpha(user, typed, extra) : FALSE
		if("b_save_digest_mode")
			return attr_b_save_digest_mode(user, list(), extra)
		if("b_del")
			return attr_b_del(user, list(), extra)
		if("b_private_struggle")
			return attr_b_private_struggle(user, list(), extra)
		if("b_absorbedrename_enabled")
			return attr_b_absorbedrename_enabled(user, list(), extra)
		if("b_absorbedrename_name")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_absorbedrename_name(user, typed, extra) : FALSE
		if("b_vorespawn_blacklist")
			return attr_b_vorespawn_blacklist(user, list(), extra)
		if("b_vorespawn_whitelist")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_vorespawn_whitelist(user, typed, extra) : FALSE
		if("b_vorespawn_absorbed")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_vorespawn_absorbed(user, typed, extra) : FALSE
		if("b_belly_sprite_to_affect")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_belly_sprite_to_affect(user, typed, extra) : FALSE
		if("b_affects_vore_sprites")
			return attr_b_affects_vore_sprites(user, list(), extra)
		if("b_count_absorbed_prey_for_sprites")
			return attr_b_count_absorbed_prey_for_sprites(user, list(), extra)
		if("b_absorbed_multiplier")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_absorbed_multiplier(user, typed, extra) : FALSE
		if("b_count_items_for_sprites")
			return attr_b_count_items_for_sprites(user, list(), extra)
		if("b_item_multiplier")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_item_multiplier(user, typed, extra) : FALSE
		if("b_health_impacts_size")
			return attr_b_health_impacts_size(user, list(), extra)
		if("b_resist_animation")
			return attr_b_resist_animation(user, list(), extra)
		if("b_size_factor_sprites")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_size_factor_sprites(user, typed, extra) : FALSE
		if("b_vore_sprite_flags")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_vore_sprite_flags(user, typed, extra) : FALSE
		if("b_count_liquid_for_sprites")
			return attr_b_count_liquid_for_sprites(user, list(), extra)
		if("b_liquid_multiplier")
			var/list/typed = payload_args(src, data, list("val" = num()))
			return typed ? attr_b_liquid_multiplier(user, typed, extra) : FALSE
		if("b_undergarment_choice")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_undergarment_choice(user, typed, extra) : FALSE
		if("b_undergarment_if_none")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_undergarment_if_none(user, typed, extra) : FALSE
		if("b_undergarment_color")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_undergarment_color(user, typed, extra) : FALSE
		if("b_tail_to_change_to")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_tail_to_change_to(user, typed, extra) : FALSE
		if("b_tail_color")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_tail_color(user, typed, extra) : FALSE
		if("b_tail_color2")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_tail_color2(user, typed, extra) : FALSE
		if("b_tail_color3")
			var/list/typed = payload_args(src, data, list("val" = schema_text(4096)))
			return typed ? attr_b_tail_color3(user, typed, extra) : FALSE
		if("b_show_liq_fullness")
			return attr_b_show_liq_fullness(user, list(), extra)
		if("b_liq_msg_toggle1")
			return attr_b_liq_msg_toggle1(user, list(), extra)
		if("b_liq_msg_toggle2")
			return attr_b_liq_msg_toggle2(user, list(), extra)
		if("b_liq_msg_toggle3")
			return attr_b_liq_msg_toggle3(user, list(), extra)
		if("b_liq_msg_toggle4")
			return attr_b_liq_msg_toggle4(user, list(), extra)
		if("b_liq_msg_toggle5")
			return attr_b_liq_msg_toggle5(user, list(), extra)
	return null
