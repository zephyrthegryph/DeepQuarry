/obj/effect/decal/writing
	name = "hand graffiti"
	icon_state = "writing1"
	icon = 'icons/effects/writing.dmi'
	desc = "It looks like someone has scratched something here."
	plane = DIRTY_PLANE
	layer = DIRTY_LAYER
	gender = PLURAL
	blend_mode = BLEND_MULTIPLY
	color = "#000000"
	alpha = 120
	anchored = TRUE

	var/message
	var/graffiti_age = 0
	var/author = "unknown"

CAPABILITIES(/obj/effect/decal/writing)
	param(nameof(graffiti_age), pos = 1)
	param(nameof(message), pos = 2)
	param(nameof(author), pos = 3)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))
	op("engrave_graffiti", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Engrave"), then(PROC_REF(interaction_engrave_graffiti)))
	op("clear_graffiti", lit_welder(fuel = 0), wait(0.5 SECONDS), then(PROC_REF(clear_done)))

// ALLOW(init/INSTANCE_STATE): graffiti not loaded with the map is tracked for persistence
/obj/effect/decal/writing/Initialize(mapload)
	if(!mapload || !CONFIG_GET(flag/persistence_ignore_mapload))
		SSpersistence.track_value(src, /datum/persistent/graffiti)
	. = ..()

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): a scrawl unlike the others on its turf.
/obj/effect/decal/writing/proc/roll_icon_state(datum/roller/R)
	var/list/random_icon_states = icon_states_fast(icon)
	for(var/obj/effect/decal/writing/writing in contents_of(loc))
		random_icon_states.Remove(writing.icon_state)
	return length(random_icon_states) ? R.choose(random_icon_states) : icon_state

// persistent graffiti forgets it.
/obj/effect/decal/writing/lifecycle_dematerialize()
	..()
	SSpersistence.forget_value(src, /datum/persistent/graffiti)

/obj/effect/decal/writing/examine(mob/user)
	. = ..()
	. += "\n It reads \"[message]\"."

/// Requirement: persistent graffiti is refused to the jobbanned; other items fall through in the effect.
/obj/effect/decal/writing/proc/can_engrave(mob/user, atom/target, obj/item/held)
	if(held?.sharp && jobban_isbanned(user, JOB_GRAFFITI))
		return "you are banned from leaving persistent information across rounds"
	return TRUE

/// Old attackby: a sharp item carves more into the graffiti.
/obj/effect/decal/writing/proc/interaction_engrave_graffiti(datum/act/op/A)
	var/refusal = can_engrave(A.actor, src, A.held)
	if(refusal != TRUE)
		if(istext(refusal))
			to_chat(A.actor, span_warning(refusal))
		return OP_DECLINE
	var/mob/user = A.actor
	var/obj/item/held = A.held
	var/obj/item/thing = held
	if(!thing.sharp)
		return OP_DECLINE

	var/_message = rerun_ask(user, "k49", PROC_REF(interaction_engrave_graffiti), args, /datum/prompt/text, question = "Enter an additional message to engrave.", title = "Graffiti", max_len = MAX_MESSAGE_LEN, name_text = ((MAX_MESSAGE_LEN) <= MAX_NAME_LEN))
	if(isnull(_message))
		return OP_OK
	if(_message && loc && user && !user.incapacitated() && user.Adjacent(loc) && thing.loc == user)
		act_message(user, null, others = span_warning("%U% begins carving something into \the [loc]."))
		task_timed(user, max(2 SECONDS, length(_message)), src, src, PROC_REF(carve_done), list(user, _message))
	return OP_PASS

/obj/effect/decal/writing/proc/carve_done(mob/user, _message)
	if(!loc)
		return
	act_message(user, null, others = span_danger("%U% carves some graffiti into \the [loc]."))
	message = "[message] [_message]"
	author = user.ckey
	if(lowertext(message) == "elbereth")
		to_chat(user, span_notice("You feel much safer."))

/obj/effect/decal/writing/proc/clear_done(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/weldingtool/welder = A.held.get_welder()
	playsound(loc, welder.usesound, 50, 1)
	act_message(user, null, others = span_infoplain(span_bold("%U%") + " clears away some graffiti."))
	spent(src, user)
