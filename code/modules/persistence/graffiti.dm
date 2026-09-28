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

/obj/effect/decal/writing/Initialize(mapload, _age, _message, _author)
	var/list/random_icon_states = icon_states_fast(icon)
	for(var/obj/effect/decal/writing/writing in contents_of(loc))
		random_icon_states.Remove(writing.icon_state)
	if(length(random_icon_states))
		icon_state = pick(random_icon_states)
	if(!mapload || !CONFIG_GET(flag/persistence_ignore_mapload))
		SSpersistence.track_value(src, /datum/persistent/graffiti)
	. = ..()
	if(!isnull(_age))
		graffiti_age = _age
	if(!isnull(_message))
		message = _message
	if(!isnull(author))
		author = _author

// ALLOW(lifecycle): persistent graffiti forgets it.
/obj/effect/decal/writing/Destroy()
	SSpersistence.forget_value(src, /datum/persistent/graffiti)
	. = ..()

/obj/effect/decal/writing/examine(mob/user)
	. = ..()
	. += "\n It reads \"[message]\"."

EXTEND_INTERACTIONS(/obj/effect/decal/writing, \
	INTERACT_ITEM("Engrave", PROC_REF(interaction_engrave_graffiti)), \
)

/// Old attackby: a sharp item carves more into the graffiti.
/obj/effect/decal/writing/proc/interaction_engrave_graffiti(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/item/thing = held
	if(!thing.sharp)
		return FALSE

	if(jobban_isbanned(user, JOB_GRAFFITI))
		to_chat(user, span_warning("You are banned from leaving persistent information across rounds."))
		return INTERACTION_HANDLED_PASS

	var/_message = rerun_ask(user, "k49", PROC_REF(interaction_engrave_graffiti), args, /datum/om/prompt/text, message = "Enter an additional message to engrave.", title = "Graffiti", max_length = MAX_MESSAGE_LEN)
	if(isnull(_message))
		return TRUE
	if(_message && loc && user && !user.incapacitated() && user.Adjacent(loc) && thing.loc == user)
		user.visible_message(span_warning("\The [user] begins carving something into \the [loc]."))
		om_do_after(user, max(2 SECONDS, length(_message)), src, src, PROC_REF(carve_done), list(user, _message))
	return INTERACTION_HANDLED_PASS

/obj/effect/decal/writing/proc/carve_done(mob/user, _message)
	if(!loc)
		return
	user.visible_message(span_danger("\The [user] carves some graffiti into \the [loc]."))
	message = "[message] [_message]"
	author = user.ckey
	if(lowertext(message) == "elbereth")
		to_chat(user, span_notice("You feel much safer."))

/obj/effect/decal/writing/welder_act(mob/user, obj/item/tool)
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.isOn() || !welder.remove_fuel(0, user))
		return ITEM_INTERACT_BLOCKING
	om_do_after(user, 0.5 SECONDS, src, src, PROC_REF(clear_done), list(user, welder))
	return ITEM_INTERACT_SUCCESS

/obj/effect/decal/writing/proc/clear_done(mob/user, obj/item/weldingtool/welder)
	playsound(loc, welder.usesound, 50, 1)
	user.visible_message(span_infoplain(span_bold("\The [user]") + " clears away some graffiti."))
	qdel(src)
