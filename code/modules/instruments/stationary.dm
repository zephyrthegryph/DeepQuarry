/obj/structure/musician
	name = "Not A Piano"
	desc = "Something broke, contact coderbus."
	/// IF FALSE music stops when the piano is unanchored.
	var/can_play_unanchored = FALSE
	/// Our allowed list of instrument ids. This is nulled on initialize.
	var/list/allowed_instrument_ids = list("r3grand","r3harpsi","crharpsi","crgrand1","crbright1", "crichugan", "crihamgan","piano") // ALLOW(instance_list): d: replaced per instance at runtime (2 assignments)
	/// Our song datum.
	var/datum/song/stationary/song

CAPABILITIES(/obj/structure/musician)
	owns_one(nameof(song), /datum/song/stationary)
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("use_wrench", tool(TOOL_WRENCH), wait(0), then(PROC_REF(wrench_used)))

/obj/structure/musician/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(song), new /datum/song/stationary(src, allowed_instrument_ids))
	allowed_instrument_ids = null


/obj/structure/musician/proc/can_play(atom/music_player)
	if(!anchored && !can_play_unanchored)
		return FALSE
	if(!ismob(music_player))
		return FALSE
	var/mob/user = music_player
	if(!user.IsAdvancedToolUser())
		return FALSE
	if(user.incapacitated())
		return FALSE
	if(!Adjacent(user))
		return FALSE
	return TRUE

/// Old attack_hand.
/obj/structure/musician/proc/interaction_hand(datum/act/op/A)
	var/mob/M = A.actor
	if(!M.IsAdvancedToolUser())
		return TRUE

	tgui_interact(M)
	return TRUE

/obj/structure/musician/ui_redirect(mob/user)
	return song

/obj/structure/musician/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/structure/musician/piano
	name = "space piano"
	desc = "This is a space piano, like a regular piano, but always in tune! Even if the musician isn't."
	icon = 'icons/obj/musician.dmi'
	icon_state = "minimoog"
	anchored = TRUE
	density = TRUE
	broken_icon_state = "pianobroken"
	integrity_failure = 0.25

CAPABILITIES(/obj/structure/musician/piano)
	climb()

/obj/structure/musician/piano/unanchored
	anchored = FALSE

/obj/structure/musician/piano/minimoog
	name = "space minimoog"
	desc = "This is a minimoog, like a space piano, but more spacey!"
	icon_state = "minimoog"
	broken_icon_state = "minimoogbroken"

/obj/structure/musician/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	use_tool(user, tool, src, delay = 2 SECONDS, volume = 100, start_self = "You start [anchored ? "un" : ""]securing \the [src] from the floor.", start_others = "[user] begins [anchored ? "un" : ""]securing \the [src] from the floor.", receiver = src, on_done = PROC_REF(wrench_act_tool_done), done_args = list(user))
	return OP_OK

/obj/structure/musician/proc/wrench_act_tool_done(mob/user)
	to_chat(user, span_notice("You [anchored ? "un" : ""]secured \the [src]!"))
	set_anchored(!anchored)
	return ITEM_INTERACT_SUCCESS
