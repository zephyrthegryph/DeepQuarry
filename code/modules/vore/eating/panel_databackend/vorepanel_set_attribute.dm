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

	vore_selected_of(host()).name = new_name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_display_name(mob/user, list/params, extra)
	var/new_name = html_encode(params["val"])
	if(length(new_name) > BELLIES_NAME_MAX)
		return FALSE
	vore_selected_of(host()).display_name = new_name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_message_mode(mob/user, list/params, extra)
	vore_selected_of(host()).message_mode = !vore_selected_of(host()).message_mode
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_wetness(mob/user, list/params, extra)
	vore_selected_of(host()).is_wet = !vore_selected_of(host()).is_wet
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_wetloop(mob/user, list/params, extra)
	vore_selected_of(host()).wet_loop = !vore_selected_of(host()).wet_loop
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_mode(mob/user, list/params, extra)
	var/new_mode = params["val"]
	if(!(new_mode in vore_selected_of(host()).digest_modes))
		return FALSE

	vore_selected_of(host()).digest_mode = new_mode
	vore_selected_of(host()).updateVRPanels()
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_addons(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(toggle_addon in vore_selected_of(host()).mode_flag_list))
		return FALSE
	vore_selected_of(host()).mode_flags ^= vore_selected_of(host()).mode_flag_list[toggle_addon]
	vore_selected_of(host()).items_preserved = null //Re-evaltuate all items in belly on
	vore_selected_of(host()).slow_digestion = FALSE
	if(vore_selected_of(host()).mode_flags & DM_FLAG_SLOWBODY)
		vore_selected_of(host()).slow_digestion = TRUE
	if(toggle_addon == "TURBO MODE")
		if(vore_selected_of(host()).mode_flags & DM_FLAG_TURBOMODE)
			vore_selected_of(host()).speedy_mob_processing = TRUE
			to_chat(user, span_warning("TURBO MODE activated! Belly processing speed tripled! This also affects timed settings, such as autotransfer and liquid generation."))
		else
			vore_selected_of(host()).speedy_mob_processing = FALSE
			to_chat(user, span_warning("TURBO MODE deactivated. Belly processing returned to normal speed."))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_item_mode(mob/user, list/params, extra)
	var/new_mode = params["val"]
	if(!(new_mode in vore_selected_of(host()).item_digest_modes))
		return FALSE

	vore_selected_of(host()).item_digest_mode = new_mode
	vore_selected_of(host()).items_preserved = null //Re-evaltuate all items in belly on belly-mode change
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_contaminates(mob/user, list/params, extra)
	vore_selected_of(host()).contaminates = !vore_selected_of(host()).contaminates
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_contamination_flavor(mob/user, list/params, extra)
	var/new_flavor = params["val"]
	if(!(new_flavor in GLOB.contamination_flavors))
		return FALSE
	vore_selected_of(host()).contamination_flavor = new_flavor
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_contamination_color(mob/user, list/params, extra)
	var/new_color = params["val"]
	if(!(new_color in GLOB.contamination_colors))
		return FALSE
	vore_selected_of(host()).contamination_color = new_color
	vore_selected_of(host()).items_preserved = null //To re-contaminate for new color
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_egg_type(mob/user, list/params, extra)
	var/new_egg_type = params["val"]
	if(!(new_egg_type in GLOB.global_vore_egg_types))
		return FALSE
	vore_selected_of(host()).egg_type = new_egg_type
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_egg_name(mob/user, list/params, extra)
	var/new_egg_name = sanitize(params["val"], BELLIES_NAME_MAX, FALSE, TRUE, FALSE)
	if(!new_egg_name)
		vore_selected_of(host()).egg_name = null
	else
		vore_selected_of(host()).egg_name = new_egg_name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_egg_size(mob/user, list/params, extra)
	var/new_egg_size = params["val"]
	if(!isnum(new_egg_size))
		return FALSE
	if(new_egg_size == 0) //Disable.
		vore_selected_of(host()).egg_size = 0
		to_chat(user,span_notice("Eggs will automatically calculate size depending on contents."))
	else
		new_egg_size = CLAMP(new_egg_size, 25, 200)
		vore_selected_of(host()).egg_size = (new_egg_size/100)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_recycling(mob/user, list/params, extra)
	vore_selected_of(host()).recycling = !vore_selected_of(host()).recycling
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_storing_nutrition(mob/user, list/params, extra)
	vore_selected_of(host()).storing_nutrition = !vore_selected_of(host()).storing_nutrition
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_belly_description_message(mob/user, list/params, extra)
	var/new_desc = html_encode(params["val"])

	if(new_desc)
		new_desc = readd_quotes(new_desc)
		if(length(new_desc) > BELLIES_DESC_MAX)
			tgui_alert_async(user, "Entered belly desc too long. [BELLIES_DESC_MAX] character limit.","Error")
			return FALSE
		vore_selected_of(host()).desc = new_desc
		. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_belly_description_message_absroed(mob/user, list/params, extra)
	var/new_desc = html_encode(params["val"])

	if(new_desc)
		new_desc = readd_quotes(new_desc)
		if(length(new_desc) > BELLIES_DESC_MAX)
			tgui_alert_async(user, "Entered belly desc too long. [BELLIES_DESC_MAX] character limit.","Error")
			return FALSE
		vore_selected_of(host()).absorbed_desc = new_desc
		. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_msgs(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	switch(params["msgtype"])
		if(DIGEST_PREY)
			vore_selected_of(host()).set_messages(params["val"], DIGEST_PREY, limit = BELLIES_MESSAGE_MAX)

		if(DIGEST_OWNER)
			vore_selected_of(host()).set_messages(params["val"], DIGEST_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORB_PREY)
			vore_selected_of(host()).set_messages(params["val"], ABSORB_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORB_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ABSORB_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(UNABSORBS_PREY)
			vore_selected_of(host()).set_messages(params["val"], UNABSORBS_PREY, limit = BELLIES_MESSAGE_MAX)

		if(UNABSORBS_OWNER)
			vore_selected_of(host()).set_messages(params["val"], UNABSORBS_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(STRUGGLE_OUTSIDE)
			vore_selected_of(host()).set_messages(params["val"], STRUGGLE_OUTSIDE, limit = BELLIES_MESSAGE_MAX)

		if(STRUGGLE_INSIDE)
			vore_selected_of(host()).set_messages(params["val"], STRUGGLE_INSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_STRUGGLE_OUSIDE)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_STRUGGLE_OUSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_STRUGGLE_INSIDE)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_STRUGGLE_INSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ATTEMPT_PREY)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_ATTEMPT_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ATTEMPT_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_ATTEMPT_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_PREY)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_OUTSIDE)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_OUTSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ITEM_PREY)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_ITEM_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ITEM_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_ITEM_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_ITEM_OUTSIDE)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_ITEM_OUTSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_FAIL_PREY)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_FAIL_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ESCAPE_FAIL_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ESCAPE_FAIL_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_ATTEMPT_PREY)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_ESCAPE_ATTEMPT_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_ATTEMPT_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_ESCAPE_ATTEMPT_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_PREY)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_ESCAPE_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_ESCAPE_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_OUTSIDE)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_ESCAPE_OUTSIDE, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_FAIL_PREY)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_ESCAPE_FAIL_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORBED_ESCAPE_FAIL_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ABSORBED_ESCAPE_FAIL_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(PRIMARY_TRANSFER_PREY)
			vore_selected_of(host()).set_messages(params["val"], PRIMARY_TRANSFER_PREY, limit = BELLIES_MESSAGE_MAX)

		if(PRIMARY_TRANSFER_OWNER)
			vore_selected_of(host()).set_messages(params["val"], PRIMARY_TRANSFER_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(SECONDARY_TRANSFER_PREY)
			vore_selected_of(host()).set_messages(params["val"], SECONDARY_TRANSFER_PREY, limit = BELLIES_MESSAGE_MAX)

		if(SECONDARY_TRANSFER_OWNER)
			vore_selected_of(host()).set_messages(params["val"], SECONDARY_TRANSFER_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(PRIMARY_AUTO_TRANSFER_PREY)
			vore_selected_of(host()).set_messages(params["val"], PRIMARY_AUTO_TRANSFER_PREY, limit = BELLIES_MESSAGE_MAX)

		if(PRIMARY_AUTO_TRANSFER_OWNER)
			vore_selected_of(host()).set_messages(params["val"], PRIMARY_AUTO_TRANSFER_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(SECONDARY_AUTO_TRANSFER_PREY)
			vore_selected_of(host()).set_messages(params["val"], SECONDARY_AUTO_TRANSFER_PREY, limit = BELLIES_MESSAGE_MAX)

		if(SECONDARY_AUTO_TRANSFER_OWNER)
			vore_selected_of(host()).set_messages(params["val"], SECONDARY_AUTO_TRANSFER_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(DIGEST_CHANCE_PREY)
			vore_selected_of(host()).set_messages(params["val"], DIGEST_CHANCE_PREY, limit = BELLIES_MESSAGE_MAX)

		if(DIGEST_CHANCE_OWNER)
			vore_selected_of(host()).set_messages(params["val"], DIGEST_CHANCE_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(ABSORB_CHANCE_PREY)
			vore_selected_of(host()).set_messages(params["val"], ABSORB_CHANCE_PREY, limit = BELLIES_MESSAGE_MAX)

		if(ABSORB_CHANCE_OWNER)
			vore_selected_of(host()).set_messages(params["val"], ABSORB_CHANCE_OWNER, limit = BELLIES_MESSAGE_MAX)

		if(EXAMINES)
			vore_selected_of(host()).set_messages(params["val"], EXAMINES, limit = BELLIES_EXAMINE_MAX)

		if(EXAMINES_ABSORBED)
			vore_selected_of(host()).set_messages(params["val"], EXAMINES_ABSORBED, limit = BELLIES_EXAMINE_MAX)

		if(GENERAL_EXAMINE_NUTRI)
			sanitize_fixed_list(params["val"], GENERAL_EXAMINE_NUTRI, limit = BELLIES_EXAMINE_MAX)

		if(GENERAL_EXAMINE_WEIGHT)
			sanitize_fixed_list(params["val"], GENERAL_EXAMINE_WEIGHT, limit = BELLIES_EXAMINE_MAX)

		if(BELLY_TRASH_EATER_IN)
			vore_selected_of(host()).set_messages(params["val"], BELLY_TRASH_EATER_IN, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_TRASH_EATER_OUT)
			vore_selected_of(host()).set_messages(params["val"], BELLY_TRASH_EATER_OUT, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_MODE_DIGEST)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_DIGEST, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_HOLD)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_HOLD, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_HOLD_ABSORB)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_HOLD_ABSORB, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_ABSORB)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_ABSORB, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_HEAL)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_HEAL, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_DRAIN)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_DRAIN, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_STEAL)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_STEAL, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_EGG)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_EGG, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_SHRINK)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_SHRINK, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_GROW)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_GROW, limit = BELLIES_IDLE_MAX)

		if(BELLY_MODE_UNABSORB)
			vore_selected_of(host()).set_messages(params["val"], BELLY_MODE_UNABSORB, limit = BELLIES_IDLE_MAX)

		if(BELLY_LIQUID_MESSAGE1)
			vore_selected_of(host()).set_messages(params["val"], BELLY_LIQUID_MESSAGE1, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_LIQUID_MESSAGE2)
			vore_selected_of(host()).set_messages(params["val"], BELLY_LIQUID_MESSAGE2, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_LIQUID_MESSAGE3)
			vore_selected_of(host()).set_messages(params["val"], BELLY_LIQUID_MESSAGE3, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_LIQUID_MESSAGE4)
			vore_selected_of(host()).set_messages(params["val"], BELLY_LIQUID_MESSAGE4, limit = BELLIES_MESSAGE_MAX)

		if(BELLY_LIQUID_MESSAGE5)
			vore_selected_of(host()).set_messages(params["val"], BELLY_LIQUID_MESSAGE5, limit = BELLIES_MESSAGE_MAX)

		if("reset")
			open_request(ui, /datum/prompt/choice/vore_reset_messages, TYPE_PROC_REF(/datum/tgui, vore_reset_messages_answered), answerer = user, question = "This will delete any custom messages. Are you sure?", title = "Confirmation", choices = list("Cancel", "DELETE"), buttons = TRUE)
			return
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_verb(mob/user, list/params, extra)
	var/new_verb = html_encode(params["val"])

	if(length(new_verb) > BELLIES_NAME_MAX || length(new_verb) < BELLIES_NAME_MIN)
		tgui_alert_async(user, "Entered verb length invalid (must be longer than [BELLIES_NAME_MIN], no longer than [BELLIES_NAME_MAX]).","Error")
		return FALSE

	vore_selected_of(host()).vore_verb = new_verb
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_release_verb(mob/user, list/params, extra)
	var/new_release_verb = html_encode(params["val"])

	if(length(new_release_verb) > BELLIES_NAME_MAX || length(new_release_verb) < BELLIES_NAME_MIN)
		tgui_alert_async(user, "Entered verb length invalid (must be longer than [BELLIES_NAME_MIN], no longer than [BELLIES_NAME_MAX]).","Error")
		return FALSE

	vore_selected_of(host()).release_verb = new_release_verb
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_eating_privacy(mob/user, list/params, extra)
	var/privacy_choice = params["val"]
	if(!(privacy_choice in list("default", "subtle", "loud")))
		return FALSE
	vore_selected_of(host()).eating_privacy_local = privacy_choice
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_silicon_belly(mob/user, list/params, extra)
	var/belly_choice = params["val"]
	if(!(belly_choice in list("Sleeper", "Vorebelly", "Both")))
		return FALSE
	for(var/obj/belly/B in host().vore_organs)
		B.silicon_belly_overlay_preference = belly_choice
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_belly_mob_mult(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	open_request(ui, /datum/prompt/number/vore_size_multiplier, TYPE_PROC_REF(/datum/tgui, vore_size_multiplier_answered), answerer = user, multiplier_kind = VORE_SIZE_MULT_MOB, displayed_max = 5, default = vore_selected_of(host()).belly_mob_mult, question = "Choose the multiplier for mobs contributing to belly size, ranging from 0 to 5. Set to 0 to disable mobs contributing to belly size", title = "Set Prey Multiplier")

/datum/vore_look/proc/attr_b_belly_item_mult(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	open_request(ui, /datum/prompt/number/vore_size_multiplier, TYPE_PROC_REF(/datum/tgui, vore_size_multiplier_answered), answerer = user, multiplier_kind = VORE_SIZE_MULT_ITEM, displayed_max = 10, default = vore_selected_of(host()).belly_item_mult, question = "Choose the multiplier for items contributing to belly size, ranging from 0 to 10. (Item size affects how much they contribute as well) Set to 0 to disable size checks", title = "Set Item Multiplier")

/datum/vore_look/proc/attr_b_belly_overall_mult(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	open_request(ui, /datum/prompt/number/vore_size_multiplier, TYPE_PROC_REF(/datum/tgui, vore_size_multiplier_answered), answerer = user, multiplier_kind = VORE_SIZE_MULT_OVERALL, displayed_max = 5, default = vore_selected_of(host()).belly_overall_mult, question = "Choose the overall multiplier to be applied to belly contents after specific multipliers, ranging from 0 to 5. Set to 0 to disable showing belly sprites at all.", title = "Set minimum prey amount")

/datum/vore_look/proc/attr_b_fancy_sound(mob/user, list/params, extra)
	vore_selected_of(host()).fancy_vore = !vore_selected_of(host()).fancy_vore
	vore_selected_of(host()).vore_sound = "Gulp"
	vore_selected_of(host()).release_sound = "Splatter"
	// defaults as to avoid potential bugs
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_release(mob/user, list/params, extra)
	var/choice = params["val"]
	if(vore_selected_of(host()).fancy_vore)
		if(!(choice in GLOB.fancy_release_sounds))
			return FALSE
	else if (!(choice in GLOB.classic_release_sounds))
		return FALSE
	vore_selected_of(host()).release_sound = choice
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_releasesoundtest(mob/user, list/params, extra)
	var/sound/releasetest
	if(vore_selected_of(host()).fancy_vore)
		releasetest = GLOB.fancy_release_sounds[vore_selected_of(host()).release_sound]
	else
		releasetest = GLOB.classic_release_sounds[vore_selected_of(host()).release_sound]

	if(releasetest)
		releasetest = sound(releasetest)
		releasetest.volume = vore_selected_of(host()).sound_volume
		releasetest.frequency = vore_selected_of(host()).noise_freq
		SEND_SOUND(user, releasetest)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_sound(mob/user, list/params, extra)
	var/choice = params["val"]
	if(vore_selected_of(host()).fancy_vore)
		if(!(choice in GLOB.fancy_vore_sounds))
			return FALSE
	else if (!(choice in GLOB.classic_vore_sounds))
		return FALSE
	vore_selected_of(host()).vore_sound = choice
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_soundtest(mob/user, list/params, extra)
	var/sound/voretest
	if(vore_selected_of(host()).fancy_vore)
		voretest = GLOB.fancy_vore_sounds[vore_selected_of(host()).vore_sound]
	else
		voretest = GLOB.classic_vore_sounds[vore_selected_of(host()).vore_sound]
	if(voretest)
		voretest = sound(voretest)
		voretest.volume = vore_selected_of(host()).sound_volume
		voretest.frequency = vore_selected_of(host()).noise_freq
		SEND_SOUND(user, voretest)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_sound_volume(mob/user, list/params, extra)
	var/sound_volume_input = params["val"]
	if(!isnum(sound_volume_input))
		return FALSE
	vore_selected_of(host()).sound_volume = sanitize_integer(sound_volume_input, 0, 100, initial(vore_selected_of(host()).sound_volume))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_noise_freq(mob/user, list/params, extra)
	var/choice = params["val"]
	if(!isnum(choice))
		return FALSE
	if(choice == 0)
		choice = rand(MIN_VOICE_FREQ, MAX_VOICE_FREQ)
	vore_selected_of(host()).noise_freq = CLAMP(choice, MIN_VOICE_FREQ, MAX_VOICE_FREQ)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_tastes(mob/user, list/params, extra)
	vore_selected_of(host()).can_taste = !vore_selected_of(host()).can_taste
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_feedable(mob/user, list/params, extra)
	vore_selected_of(host()).is_feedable = !vore_selected_of(host()).is_feedable
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_entrance_logs(mob/user, list/params, extra)
	vore_selected_of(host()).entrance_logs = !vore_selected_of(host()).entrance_logs
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_item_digest_logs(mob/user, list/params, extra)
	vore_selected_of(host()).item_digest_logs = !vore_selected_of(host()).item_digest_logs
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_bulge_size(mob/user, list/params, extra)
	var/new_bulge = params["val"]
	if(!isnum(new_bulge))
		return FALSE
	if(new_bulge == 0) //Disable.
		vore_selected_of(host()).bulge_size = 0
		to_chat(user,span_notice("Your stomach will not be seen on examine."))
	else if(new_bulge)
		new_bulge = CLAMP(new_bulge, 25, 200)
		vore_selected_of(host()).bulge_size = (new_bulge/100)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_display_absorbed_examine(mob/user, list/params, extra)
	vore_selected_of(host()).display_absorbed_examine = !vore_selected_of(host()).display_absorbed_examine
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_display_outside_struggle(mob/user, list/params, extra)
	vore_selected_of(host()).toggle_displayed_message_flags(MS_FLAG_STRUGGLE_OUTSIDE)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_display_absorbed_outside_struggle(mob/user, list/params, extra)
	vore_selected_of(host()).toggle_displayed_message_flags(MS_FLAG_STRUGGLE_ABSORBED_OUTSIDE)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_grow_shrink(mob/user, list/params, extra)
	var/new_grow = params["val"]
	if (!isnum(new_grow))
		return
	vore_selected_of(host()).shrink_grow_size = CLAMP(new_grow, 25, 200) * 0.01
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_nutritionpercent(mob/user, list/params, extra)
	var/new_nutrition = params["val"]
	if(!isnum(new_nutrition))
		return FALSE
	vore_selected_of(host()).nutrition_percent = CLAMP(new_nutrition, 0.01, 100)
	. = TRUE
	// modified these to be flexible rather than maxing at 6/6/12/6/6
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_burn_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	vore_selected_of(host()).digest_burn = CLAMP(new_damage, 0, vore_selected_of(host()).get_unused_digestion_damage() + vore_selected_of(host()).digest_burn) // sanity check following tgui input
	vore_selected_of(host()).items_preserved = null
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_brute_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	vore_selected_of(host()).digest_brute = CLAMP(new_damage, 0, vore_selected_of(host()).get_unused_digestion_damage() + vore_selected_of(host()).digest_brute)
	vore_selected_of(host()).items_preserved = null
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_oxy_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	vore_selected_of(host()).digest_oxy = CLAMP(new_damage, 0, vore_selected_of(host()).get_unused_digestion_damage() + vore_selected_of(host()).digest_oxy)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_tox_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	vore_selected_of(host()).digest_tox = CLAMP(new_damage, 0, vore_selected_of(host()).get_unused_digestion_damage() + vore_selected_of(host()).digest_tox)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_clone_dmg(mob/user, list/params, extra)
	var/new_damage = params["val"]
	if(!isnum(new_damage))
		return FALSE
	vore_selected_of(host()).digest_clone = CLAMP(new_damage, 0, vore_selected_of(host()).get_unused_digestion_damage() + vore_selected_of(host()).digest_clone)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_bellytemperature(mob/user, list/params, extra)
	var/new_temp = params["val"]
	if(!isnum(new_temp))
		return FALSE
	new_temp = new_temp + T0C
	vore_selected_of(host()).bellytemperature = CLAMP(new_temp, T0C, 473.15)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_temperature_damage(mob/user, list/params, extra)
	vore_selected_of(host()).temperature_damage = !vore_selected_of(host()).temperature_damage
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_drainmode(mob/user, list/params, extra)
	var/new_drainmode = params["val"]
	if(!(new_drainmode in vore_selected_of(host()).drainmodes))
		return FALSE
	vore_selected_of(host()).drainmode = new_drainmode
	vore_selected_of(host()).updateVRPanels()
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_emoteactive(mob/user, list/params, extra)
	vore_selected_of(host()).emote_active = !vore_selected_of(host()).emote_active
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_selective_mode_pref_toggle(mob/user, list/params, extra)
	var/new_mode = params["val"]
	switch(new_mode)
		if(DM_DIGEST)
			vore_selected_of(host()).selective_preference = DM_DIGEST
		if(DM_ABSORB)
			vore_selected_of(host()).selective_preference = DM_ABSORB
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_emotetime(mob/user, list/params, extra)
	var/new_time = params["val"]
	if(!isnum(new_time))
		return FALSE
	vore_selected_of(host()).emote_time = CLAMP(new_time, 60, 600)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_escapable(mob/user, list/params, extra)
	var/new_mode = params["val"]
	switch(new_mode)
		if(B_ESCAPABLE_NONE) //Never escapable.
			vore_selected_of(host()).escapable = B_ESCAPABLE_NONE
			to_chat(user,span_warning("Prey will not be able to have special interactions with your [lowertext(vore_selected_of(host()).name)]."))
		if(B_ESCAPABLE_DEFAULT) //Possibly escapable and special interactions.
			vore_selected_of(host()).escapable = B_ESCAPABLE_DEFAULT
			to_chat(user,span_warning("Prey now have special interactions with your [lowertext(vore_selected_of(host()).name)] depending on your settings."))
		if(B_ESCAPABLE_INTENT) //Possibly escapable and special intent based interactions.
			vore_selected_of(host()).escapable = B_ESCAPABLE_INTENT
			to_chat(user,span_warning("Prey now have special interactions with your [lowertext(vore_selected_of(host()).name)] depending on your settings and their intent."))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_escapechance(mob/user, list/params, extra)
	var/escape_chance_input = params["val"]
	if(!isnum(escape_chance_input))
		return FALSE
	vore_selected_of(host()).escapechance = sanitize_integer(escape_chance_input, 0, 100, initial(vore_selected_of(host()).escapechance))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_belchchance(mob/user, list/params, extra)
	var/belch_chance_input = params["val"]
	if(!isnum(belch_chance_input))
		return FALSE
	vore_selected_of(host()).belchchance = sanitize_integer(belch_chance_input, 0, 100, initial(vore_selected_of(host()).belchchance))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_escapechance_absorbed(mob/user, list/params, extra)
	var/escape_absorbed_chance_input = params["val"]
	if(!isnum(escape_absorbed_chance_input))
		return FALSE
	vore_selected_of(host()).escapechance_absorbed = sanitize_integer(escape_absorbed_chance_input, 0, 100, initial(vore_selected_of(host()).escapechance_absorbed))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_escapetime(mob/user, list/params, extra)
	var/escape_time_input = params["val"]
	if(!isnum(escape_time_input))
		return FALSE
	vore_selected_of(host()).escapetime = sanitize_integer(escape_time_input*10, 10, 600, initial(vore_selected_of(host()).escapetime))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_transferchance(mob/user, list/params, extra)
	var/transfer_chance_input = params["val"]
	if(!isnum(transfer_chance_input))
		return FALSE
	vore_selected_of(host()).transferchance = sanitize_integer(transfer_chance_input, 0, 100, initial(vore_selected_of(host()).transferchance))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_transferlocation(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]

	if(!istype(choice))
		vore_selected_of(host()).transferlocation = null
	else
		vore_selected_of(host()).transferlocation = choice.name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_transferchance_secondary(mob/user, list/params, extra)
	var/transfer_secondary_chance_input = params["val"]
	if(!isnum(transfer_secondary_chance_input))
		return FALSE
	vore_selected_of(host()).transferchance_secondary = sanitize_integer(transfer_secondary_chance_input, 0, 100, initial(vore_selected_of(host()).transferchance_secondary))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_transferlocation_secondary(mob/user, list/params, extra)
	var/obj/belly/choice_secondary = params["val"]

	if(!istype(choice_secondary))
		vore_selected_of(host()).transferlocation_secondary = null
	else
		vore_selected_of(host()).transferlocation_secondary = choice_secondary.name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_absorbchance(mob/user, list/params, extra)
	var/absorb_chance_input = params["val"]
	if(!isnum(absorb_chance_input))
		return FALSE
	vore_selected_of(host()).absorbchance = sanitize_integer(absorb_chance_input, 0, 100, initial(vore_selected_of(host()).absorbchance))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_digestchance(mob/user, list/params, extra)
	var/digest_chance_input = params["val"]
	if(!isnum(digest_chance_input))
		return FALSE
	vore_selected_of(host()).digestchance = sanitize_integer(digest_chance_input, 0, 100, initial(vore_selected_of(host()).digestchance))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransferchance_primary(mob/user, list/params, extra)
	var/autotransferchance_input = params["val"]
	if(!isnum(autotransferchance_input))
		return FALSE
	vore_selected_of(host()).autotransferchance = sanitize_integer(autotransferchance_input, 0, 100, initial(vore_selected_of(host()).autotransferchance))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransferwait(mob/user, list/params, extra)
	var/autotransferwait_input = params["val"]
	if(!isnum(autotransferwait_input))
		return FALSE
	vore_selected_of(host()).autotransferwait = sanitize_integer(autotransferwait_input*10, 10, 18000, initial(vore_selected_of(host()).autotransferwait))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransferlocation_primary(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]

	if(!istype(choice))
		vore_selected_of(host()).autotransferlocation = null
	else
		vore_selected_of(host()).autotransferlocation = choice.name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransferextralocation_primary(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]
	if(!istype(choice))
		return FALSE
	else if(choice.name in vore_selected_of(host()).autotransferextralocation)
		vore_selected_of(host()).autotransferextralocation = vore_selected_of(host()).autotransferextralocation - choice.name // Replace: the list may be shared
	else
		vore_selected_of(host()).autotransferextralocation = vore_selected_of(host()).autotransferextralocation + choice.name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransferchance_secondary(mob/user, list/params, extra)
	var/autotransferchance_secondary_input = params["val"]
	if(!isnum(autotransferchance_secondary_input))
		return FALSE
	vore_selected_of(host()).autotransferchance_secondary = sanitize_integer(autotransferchance_secondary_input, 0, 100, initial(vore_selected_of(host()).autotransferchance_secondary))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransferlocation_secondary(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]

	if(!choice)
		vore_selected_of(host()).autotransferlocation_secondary = null
	else
		vore_selected_of(host()).autotransferlocation_secondary = choice.name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransferextralocation_secondary(mob/user, list/params, extra)
	var/obj/belly/choice = params["val"]
	if(!istype(choice)) //They cancelled, no changes
		return FALSE
	else if(choice.name in vore_selected_of(host()).autotransferextralocation_secondary)
		vore_selected_of(host()).autotransferextralocation_secondary = vore_selected_of(host()).autotransferextralocation_secondary - choice.name // Replace: the list may be shared
	else
		vore_selected_of(host()).autotransferextralocation_secondary = vore_selected_of(host()).autotransferextralocation_secondary + choice.name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_whitelist_primary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(vore_selected_of(host()).autotransfer_flags_list[toggle_addon]))
		return FALSE
	vore_selected_of(host()).autotransfer_whitelist ^= vore_selected_of(host()).autotransfer_flags_list[toggle_addon]
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_blacklist_primary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(vore_selected_of(host()).autotransfer_flags_list[toggle_addon]))
		return FALSE
	vore_selected_of(host()).autotransfer_blacklist ^= vore_selected_of(host()).autotransfer_flags_list[toggle_addon]
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_whitelist_secondary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(vore_selected_of(host()).autotransfer_flags_list[toggle_addon]))
		return FALSE
	vore_selected_of(host()).autotransfer_secondary_whitelist ^= vore_selected_of(host()).autotransfer_flags_list[toggle_addon]
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_blacklist_secondary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(vore_selected_of(host()).autotransfer_flags_list[toggle_addon]))
		return FALSE
	vore_selected_of(host()).autotransfer_secondary_blacklist ^= vore_selected_of(host()).autotransfer_flags_list[toggle_addon]
	. = TRUE
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_whitelist_items_primary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(vore_selected_of(host()).autotransfer_flags_list_items[toggle_addon]))
		return FALSE
	vore_selected_of(host()).autotransfer_whitelist_items ^= vore_selected_of(host()).autotransfer_flags_list_items[toggle_addon]
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_blacklist_items_primary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(vore_selected_of(host()).autotransfer_flags_list_items[toggle_addon]))
		return FALSE
	vore_selected_of(host()).autotransfer_blacklist_items ^= vore_selected_of(host()).autotransfer_flags_list_items[toggle_addon]
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_whitelist_items_secondary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(vore_selected_of(host()).autotransfer_flags_list_items[toggle_addon]))
		return FALSE
	vore_selected_of(host()).autotransfer_secondary_whitelist_items ^= vore_selected_of(host()).autotransfer_flags_list_items[toggle_addon]
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_blacklist_items_secondary(mob/user, list/params, extra)
	var/toggle_addon = params["val"]
	if(!(vore_selected_of(host()).autotransfer_flags_list_items[toggle_addon]))
		return FALSE
	vore_selected_of(host()).autotransfer_secondary_blacklist_items ^= vore_selected_of(host()).autotransfer_flags_list_items[toggle_addon]
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_min_amount(mob/user, list/params, extra)
	var/autotransfer_min_amount_input = params["val"]
	if(!isnum(autotransfer_min_amount_input))
		return FALSE
	vore_selected_of(host()).autotransfer_min_amount = sanitize_integer(autotransfer_min_amount_input, 0, 100, initial(vore_selected_of(host()).autotransfer_min_amount))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_max_amount(mob/user, list/params, extra)
	var/autotransfer_max_amount_input = params["val"]
	if(!isnum(autotransfer_max_amount_input))
		return FALSE
	vore_selected_of(host()).autotransfer_max_amount = sanitize_integer(autotransfer_max_amount_input, 0, 100, initial(vore_selected_of(host()).autotransfer_max_amount))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_autotransfer_enabled(mob/user, list/params, extra)
	vore_selected_of(host()).autotransfer_enabled = !vore_selected_of(host()).autotransfer_enabled
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_fullscreen(mob/user, list/params, extra)
	vore_selected_of(host()).belly_fullscreen = params["val"]
	vore_selected_of(host()).update_internal_overlay()
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_disable_hud(mob/user, list/params, extra)
	vore_selected_of(host()).disable_hud = !vore_selected_of(host()).disable_hud
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_colorization_enabled(mob/user, list/params, extra)
	vore_selected_of(host()).colorization_enabled = !vore_selected_of(host()).colorization_enabled
	vore_selected_of(host()).belly_fullscreen = "dark" //This prevents you from selecting a belly that is not meant to be colored and then turning colorization on.
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_preview_belly(mob/user, list/params, extra)
	vore_selected_of(host()).vore_preview(host()) //Gives them the stomach overlay. It fades away after ~2 seconds as human/life.dm removes the overlay if not in a gut.
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_clear_preview(mob/user, list/params, extra)
	vore_selected_of(host()).clear_preview(host()) //Clears the stomach overlay. This is a failsafe but shouldn't occur.
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_fullscreen_color(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		vore_selected_of(host()).belly_fullscreen_color = newcolor
		vore_selected_of(host()).update_internal_overlay()
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_fullscreen_color2(mob/user, list/params, extra)
	var/newcolor2 = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor2)
		vore_selected_of(host()).belly_fullscreen_color2 = newcolor2
		vore_selected_of(host()).update_internal_overlay()
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_fullscreen_color3(mob/user, list/params, extra)
	var/newcolor3 = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor3)
		vore_selected_of(host()).belly_fullscreen_color3 = newcolor3
		vore_selected_of(host()).update_internal_overlay()
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_fullscreen_color4(mob/user, list/params, extra)
	var/newcolor4 = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor4)
		vore_selected_of(host()).belly_fullscreen_color4 = newcolor4
		vore_selected_of(host()).update_internal_overlay()
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_fullscreen_alpha(mob/user, list/params, extra)
	var/newalpha = params["val"]
	if(!isnum(newalpha))
		return FALSE
	vore_selected_of(host()).belly_fullscreen_alpha = newalpha
	vore_selected_of(host()).update_internal_overlay()
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_save_digest_mode(mob/user, list/params, extra)
	vore_selected_of(host()).save_digest_mode = !vore_selected_of(host()).save_digest_mode
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_del(mob/user, list/params, extra)
	var/datum/tgui/ui = extra // the window the button was pressed in
	open_request(ui, /datum/prompt/choice/vore_delete_belly, TYPE_PROC_REF(/datum/tgui, vore_delete_belly_answered), answerer = user, question = "Are you sure you want to delete your [lowertext(vore_selected_of(host()).name)]?", title = "Confirmation", choices = list("Cancel", "Delete"), buttons = TRUE)

/datum/vore_look/proc/attr_b_private_struggle(mob/user, list/params, extra)
	vore_selected_of(host()).private_struggle = !vore_selected_of(host()).private_struggle
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_absorbedrename_enabled(mob/user, list/params, extra)
	vore_selected_of(host()).absorbedrename_enabled = !vore_selected_of(host()).absorbedrename_enabled
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_absorbedrename_name(mob/user, list/params, extra)
	var/new_absorbedrename_name = sanitize(params["val"], MAX_MESSAGE_LEN, FALSE, TRUE, FALSE)
	if(new_absorbedrename_name)
		vore_selected_of(host()).absorbedrename_name = new_absorbedrename_name
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_vorespawn_blacklist(mob/user, list/params, extra)
	vore_selected_of(host()).vorespawn_blacklist = !vore_selected_of(host()).vorespawn_blacklist
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_vorespawn_whitelist(mob/user, list/params, extra)
	var/new_vorespawn_whitelist = sanitize(params["val"], MAX_MESSAGE_LEN, FALSE, TRUE, FALSE)
	if(new_vorespawn_whitelist)
		vore_selected_of(host()).vorespawn_whitelist = splittext(lowertext(new_vorespawn_whitelist),"\n")
	else
		vore_selected_of(host()).vorespawn_whitelist = list()
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_vorespawn_absorbed(mob/user, list/params, extra)
	var/current_number = params["val"]
	switch(current_number)
		if("Yes")
			vore_selected_of(host()).vorespawn_absorbed |= VS_FLAG_ABSORB_YES
		if("Prey Choice")
			vore_selected_of(host()).vorespawn_absorbed |= VS_FLAG_ABSORB_PREY
		if("No")
			vore_selected_of(host()).vorespawn_absorbed &= ~(VS_FLAG_ABSORB_YES)
			vore_selected_of(host()).vorespawn_absorbed &= ~(VS_FLAG_ABSORB_PREY)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_belly_sprite_to_affect(mob/user, list/params, extra)
	var/belly_choice = params["val"]
	if(!(belly_choice in host().vore_icon_bellies))
		return FALSE
	vore_selected_of(host()).belly_sprite_to_affect = belly_choice
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_affects_vore_sprites(mob/user, list/params, extra)
	vore_selected_of(host()).affects_vore_sprites = !vore_selected_of(host()).affects_vore_sprites
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_count_absorbed_prey_for_sprites(mob/user, list/params, extra)
	vore_selected_of(host()).count_absorbed_prey_for_sprite = !vore_selected_of(host()).count_absorbed_prey_for_sprite
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_absorbed_multiplier(mob/user, list/params, extra)
	var/absorbed_multiplier_input = params["val"]
	if(!isnum(absorbed_multiplier_input))
		return FALSE
	vore_selected_of(host()).absorbed_multiplier = CLAMP(absorbed_multiplier_input, 0.1, 3)
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_count_items_for_sprites(mob/user, list/params, extra)
	vore_selected_of(host()).count_items_for_sprite = !vore_selected_of(host()).count_items_for_sprite
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_item_multiplier(mob/user, list/params, extra)
	var/item_multiplier_input = params["val"]
	if(!isnum(item_multiplier_input))
		return FALSE
	vore_selected_of(host()).item_multiplier = CLAMP(item_multiplier_input, 0.1, 10)
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_health_impacts_size(mob/user, list/params, extra)
	vore_selected_of(host()).health_impacts_size = !vore_selected_of(host()).health_impacts_size
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_resist_animation(mob/user, list/params, extra)
	vore_selected_of(host()).resist_triggers_animation = !vore_selected_of(host()).resist_triggers_animation
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_size_factor_sprites(mob/user, list/params, extra)
	var/size_factor_input = params["val"]
	if(!isnum(size_factor_input))
		return FALSE
	vore_selected_of(host()).size_factor_for_sprite = CLAMP(size_factor_input, 0.1, 3)
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_vore_sprite_flags(mob/user, list/params, extra)
	var/toggle_vs_flag = params["val"]
	if(!(toggle_vs_flag in vore_selected_of(host()).vore_sprite_flag_list))
		return FALSE
	vore_selected_of(host()).vore_sprite_flags ^= vore_selected_of(host()).vore_sprite_flag_list[toggle_vs_flag]
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_count_liquid_for_sprites(mob/user, list/params, extra)
	vore_selected_of(host()).count_liquid_for_sprite = !vore_selected_of(host()).count_liquid_for_sprite
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_liquid_multiplier(mob/user, list/params, extra)
	var/liquid_multiplier_input = params["val"]
	if(!isnum(liquid_multiplier_input))
		return FALSE
	vore_selected_of(host()).liquid_multiplier = CLAMP(liquid_multiplier_input, 0.1, 10)
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_undergarment_choice(mob/user, list/params, extra)
	var/new_undergarment = params["val"]
	if(!(GLOB.global_underwear.categories_by_name[new_undergarment]))
		return FALSE
	vore_selected_of(host()).undergarment_chosen = new_undergarment
	PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_undergarment_if_none(mob/user, list/params, extra)
	var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories_by_name[vore_selected_of(host()).undergarment_chosen]
	var/selected_underwear = UWC.items_by_name[params["val"]]
	if(!selected_underwear) //They cancelled, no changes
		return FALSE

	vore_selected_of(host()).undergarment_if_none = selected_underwear
	PUBLISH(host(), belly_change)
	host().updateVRPanel()
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_undergarment_color(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		vore_selected_of(host()).undergarment_color = newcolor
		PUBLISH(host(), belly_change)
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_tail_to_change_to(mob/user, list/params, extra)
	var/tail_choice = params["val"]
	if(!(tail_choice in GLOB.tail_styles_list))
		return FALSE
	vore_selected_of(host()).tail_to_change_to_static = tail_choice
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_tail_color(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		vore_selected_of(host()).tail_colouration = newcolor
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_tail_color2(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		vore_selected_of(host()).tail_extra_overlay = newcolor
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_tail_color3(mob/user, list/params, extra)
	var/newcolor = sanitize_hexcolor(lowertext(params["val"]))
	if(newcolor)
		vore_selected_of(host()).tail_extra_overlay2 = newcolor
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_show_liq_fullness(mob/user, list/params, extra)
	if(!vore_selected_of(host()).show_fullness_messages)
		vore_selected_of(host()).show_fullness_messages = 1
		to_chat(user,span_warning("Your [lowertext(vore_selected_of(host()).name)] now has liquid examination options."))
	else
		vore_selected_of(host()).show_fullness_messages = 0
		to_chat(user,span_warning("Your [lowertext(vore_selected_of(host()).name)] no longer has liquid examination options."))
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_liq_msg_toggle1(mob/user, list/params, extra)
	vore_selected_of(host()).liquid_fullness1_messages = !vore_selected_of(host()).liquid_fullness1_messages
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_liq_msg_toggle2(mob/user, list/params, extra)
	vore_selected_of(host()).liquid_fullness2_messages = !vore_selected_of(host()).liquid_fullness2_messages
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_liq_msg_toggle3(mob/user, list/params, extra)
	vore_selected_of(host()).liquid_fullness3_messages = !vore_selected_of(host()).liquid_fullness3_messages
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_liq_msg_toggle4(mob/user, list/params, extra)
	vore_selected_of(host()).liquid_fullness4_messages = !vore_selected_of(host()).liquid_fullness4_messages
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

/datum/vore_look/proc/attr_b_liq_msg_toggle5(mob/user, list/params, extra)
	vore_selected_of(host()).liquid_fullness5_messages = !vore_selected_of(host()).liquid_fullness5_messages
	. = TRUE
	if(.)
		set_unsaved_changes(TRUE)

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
			vore_selected_of(panel.host()).belly_mob_mult = CLAMP(request.value, 0, 5)
		if(VORE_SIZE_MULT_ITEM)
			vore_selected_of(panel.host()).belly_item_mult = CLAMP(request.value, 0, 10)
		if(VORE_SIZE_MULT_OVERALL)
			vore_selected_of(panel.host()).belly_overall_mult = CLAMP(request.value, 0, 5)
	PUBLISH(panel.host(), belly_change)
	panel.set_unsaved_changes(TRUE)

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
		vore_selected_of(panel.host()).digest_messages_prey = vore_selected_of(panel.host()).belly_shared_list("digest_messages_prey")
		vore_selected_of(panel.host()).digest_messages_owner = vore_selected_of(panel.host()).belly_shared_list("digest_messages_owner")
		vore_selected_of(panel.host()).absorb_messages_prey = vore_selected_of(panel.host()).belly_shared_list("absorb_messages_prey")
		vore_selected_of(panel.host()).absorb_messages_owner = vore_selected_of(panel.host()).belly_shared_list("absorb_messages_owner")
		vore_selected_of(panel.host()).unabsorb_messages_prey = vore_selected_of(panel.host()).belly_shared_list("unabsorb_messages_prey")
		vore_selected_of(panel.host()).unabsorb_messages_owner = vore_selected_of(panel.host()).belly_shared_list("unabsorb_messages_owner")
		vore_selected_of(panel.host()).struggle_messages_outside = vore_selected_of(panel.host()).belly_shared_list("struggle_messages_outside")
		vore_selected_of(panel.host()).struggle_messages_inside = vore_selected_of(panel.host()).belly_shared_list("struggle_messages_inside")
		vore_selected_of(panel.host()).absorbed_struggle_messages_outside = vore_selected_of(panel.host()).belly_shared_list("absorbed_struggle_messages_outside")
		vore_selected_of(panel.host()).absorbed_struggle_messages_inside = vore_selected_of(panel.host()).belly_shared_list("absorbed_struggle_messages_inside")
		vore_selected_of(panel.host()).escape_attempt_messages_owner = vore_selected_of(panel.host()).belly_shared_list("escape_attempt_messages_owner")
		vore_selected_of(panel.host()).escape_attempt_messages_prey = vore_selected_of(panel.host()).belly_shared_list("escape_attempt_messages_prey")
		vore_selected_of(panel.host()).escape_messages_owner = vore_selected_of(panel.host()).belly_shared_list("escape_messages_owner")
		vore_selected_of(panel.host()).escape_messages_prey = vore_selected_of(panel.host()).belly_shared_list("escape_messages_prey")
		vore_selected_of(panel.host()).escape_messages_outside = vore_selected_of(panel.host()).belly_shared_list("escape_messages_outside")
		vore_selected_of(panel.host()).escape_item_messages_owner = vore_selected_of(panel.host()).belly_shared_list("escape_item_messages_owner")
		vore_selected_of(panel.host()).escape_item_messages_prey = vore_selected_of(panel.host()).belly_shared_list("escape_item_messages_prey")
		vore_selected_of(panel.host()).escape_item_messages_outside = vore_selected_of(panel.host()).belly_shared_list("escape_item_messages_outside")
		vore_selected_of(panel.host()).escape_fail_messages_owner = vore_selected_of(panel.host()).belly_shared_list("escape_fail_messages_owner")
		vore_selected_of(panel.host()).escape_fail_messages_prey = vore_selected_of(panel.host()).belly_shared_list("escape_fail_messages_prey")
		vore_selected_of(panel.host()).escape_attempt_absorbed_messages_owner = vore_selected_of(panel.host()).belly_shared_list("escape_attempt_absorbed_messages_owner")
		vore_selected_of(panel.host()).escape_attempt_absorbed_messages_prey = vore_selected_of(panel.host()).belly_shared_list("escape_attempt_absorbed_messages_prey")
		vore_selected_of(panel.host()).escape_absorbed_messages_owner = vore_selected_of(panel.host()).belly_shared_list("escape_absorbed_messages_owner")
		vore_selected_of(panel.host()).escape_absorbed_messages_prey = vore_selected_of(panel.host()).belly_shared_list("escape_absorbed_messages_prey")
		vore_selected_of(panel.host()).escape_absorbed_messages_outside = vore_selected_of(panel.host()).belly_shared_list("escape_absorbed_messages_outside")
		vore_selected_of(panel.host()).escape_fail_absorbed_messages_owner = vore_selected_of(panel.host()).belly_shared_list("escape_fail_absorbed_messages_owner")
		vore_selected_of(panel.host()).escape_fail_absorbed_messages_prey = vore_selected_of(panel.host()).belly_shared_list("escape_fail_absorbed_messages_prey")
		vore_selected_of(panel.host()).primary_transfer_messages_owner = vore_selected_of(panel.host()).belly_shared_list("primary_transfer_messages_owner")
		vore_selected_of(panel.host()).primary_transfer_messages_prey = vore_selected_of(panel.host()).belly_shared_list("primary_transfer_messages_prey")
		vore_selected_of(panel.host()).secondary_transfer_messages_owner = vore_selected_of(panel.host()).belly_shared_list("secondary_transfer_messages_owner")
		vore_selected_of(panel.host()).secondary_transfer_messages_prey = vore_selected_of(panel.host()).belly_shared_list("secondary_transfer_messages_prey")
		vore_selected_of(panel.host()).primary_autotransfer_messages_owner = vore_selected_of(panel.host()).belly_shared_list("primary_autotransfer_messages_owner")
		vore_selected_of(panel.host()).primary_autotransfer_messages_prey = vore_selected_of(panel.host()).belly_shared_list("primary_autotransfer_messages_prey")
		vore_selected_of(panel.host()).secondary_autotransfer_messages_owner = vore_selected_of(panel.host()).belly_shared_list("secondary_autotransfer_messages_owner")
		vore_selected_of(panel.host()).secondary_autotransfer_messages_prey = vore_selected_of(panel.host()).belly_shared_list("secondary_autotransfer_messages_prey")
		vore_selected_of(panel.host()).digest_chance_messages_owner = vore_selected_of(panel.host()).belly_shared_list("digest_chance_messages_owner")
		vore_selected_of(panel.host()).digest_chance_messages_prey = vore_selected_of(panel.host()).belly_shared_list("digest_chance_messages_prey")
		vore_selected_of(panel.host()).absorb_chance_messages_owner = vore_selected_of(panel.host()).belly_shared_list("absorb_chance_messages_owner")
		vore_selected_of(panel.host()).absorb_chance_messages_prey = vore_selected_of(panel.host()).belly_shared_list("absorb_chance_messages_prey")
		vore_selected_of(panel.host()).examine_messages = vore_selected_of(panel.host()).belly_shared_list("examine_messages")
		vore_selected_of(panel.host()).examine_messages_absorbed = vore_selected_of(panel.host()).belly_shared_list("examine_messages_absorbed")
		vore_selected_of(panel.host()).emote_lists = vore_selected_of(panel.host()).belly_shared_list("emote_lists")
		vore_selected_of(panel.host()).trash_eater_in = vore_selected_of(panel.host()).belly_shared_list("trash_eater_in")
		vore_selected_of(panel.host()).trash_eater_out = vore_selected_of(panel.host()).belly_shared_list("trash_eater_out")
		vore_selected_of(panel.host()).liquid_fullness1_messages = vore_selected_of(panel.host()).belly_shared_list("fullness1_messages")
		vore_selected_of(panel.host()).liquid_fullness2_messages = vore_selected_of(panel.host()).belly_shared_list("fullness2_messages")
		vore_selected_of(panel.host()).liquid_fullness3_messages = vore_selected_of(panel.host()).belly_shared_list("fullness3_messages")
		vore_selected_of(panel.host()).liquid_fullness4_messages = vore_selected_of(panel.host()).belly_shared_list("fullness4_messages")
		vore_selected_of(panel.host()).liquid_fullness5_messages = vore_selected_of(panel.host()).belly_shared_list("fullness5_messages")
		panel.set_unsaved_changes(TRUE)

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
		if(B.transferlocation == vore_selected_of(host()))
			dest_for = B.name
			failure_msg += "This is the destiantion for at least '[dest_for]' belly transfers. Remove it as the destination from any bellies before deleting it. "
			break
		if(B.transferlocation_secondary == vore_selected_of(host()))
			dest_for = B.name
			failure_msg += "This is the destiantion for at least '[dest_for]' secondary belly transfers. Remove it as the destination from any bellies before deleting it. "
			break

	if(contents_count(vore_selected_of(host())))
		failure_msg += "You cannot delete bellies with contents! " //These end with spaces, to be nice looking. Make sure you do the same.
	if(vore_selected_of(host()).immutable)
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
		panel.set_unsaved_changes(TRUE)

/datum/vore_look/proc/vore_delete_belly_apply()
	if(host().soulgem?.linked_belly() == vore_selected_of(host()))
		host().soulgem.linked_belly = null

	spent(vore_selected_of(host()), src)
	set_vore_selected(host(), host().vore_organs[1])

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
