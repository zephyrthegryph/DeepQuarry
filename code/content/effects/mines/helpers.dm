/////////////////////////////////////////////
// The held item version of the above mines
/////////////////////////////////////////////
/obj/item/mine
	name = "mine"
	desc = "A small explosive mine with 'HE' and a grenade symbol on the side."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "landmine"
	var/countdown = 10
	var/minetype = /obj/effect/mine		//This MUST be an /obj/effect/mine type, or it'll runtime.

	var/obj/item/trap = null

	var/list/allowed_gadgets = null

MSG_DEF(mine/priming, span_infoplain("You start priming %T%. Hold still!"), "%U% starts priming %T%.")

/// The start of priming: the admin log line, the fingerprint and what is said (a start hook that answers its message).
/obj/item/mine/proc/priming_begins(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	msg_admin_attack("[key_name_admin(user)] primed \a [src]")
	return /datum/msg/mine/priming

/obj/item/mine/proc/primed(datum/act/op/A)
	play_sfx(src, SFX_WEAPONS_ARMBOMB)
	prime(A.actor)

/obj/item/mine/proc/priming_failed(datum/act/op/A)
	var/mob/user = A.actor
	act_message(user, null, others = "%U% triggers \the [src.name]!", blind = "You accidentally trigger \the [src.name]!")
	prime(user, TRUE)

/// Old attackby.
/obj/item/mine/proc/interaction_item(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(LAZYLEN(allowed_gadgets) && !trap)
		var/allowed = FALSE

		for(var/path in allowed_gadgets)
			if(istype(W, path))
				allowed = TRUE
				break

		if(allowed)
			move_into(src, nameof(src.trap), W, user)

	return OP_DECLINE

/obj/item/mine/proc/prime(mob/user as mob, explode_now = FALSE)
	visible_message("\The [src.name] beeps as the priming sequence completes.")
	var/obj/effect/mine/R = new minetype(get_turf(src))
	src.transfer_fingerprints_to(R)
	R.add_fingerprint(user)
	if(trap)
		rel_move(src, nameof(src.trap), R, nameof(R.trap)) // CONTAINED on the mine: the transfer moves it in
	if(explode_now)
		R.explode(user)
	consume(src)

/obj/item/mine/dnascramble
	name = "radiation mine"
	desc = "A small explosive mine with a radiation symbol on the side."
	minetype = /obj/effect/mine/dnascramble

/obj/item/mine/phoron
	name = "incendiary mine"
	desc = "A small explosive mine with a fire symbol on the side."
	minetype = /obj/effect/mine/phoron

/obj/item/mine/kick
	name = "kick mine"
	desc = "Concentrated war crimes. Handle with care."
	minetype = /obj/effect/mine/kick

/obj/item/mine/n2o
	name = "nitrous oxide mine"
	desc = "A small explosive mine with three Z's on the side."
	minetype = /obj/effect/mine/n2o

/obj/item/mine/stun
	name = "stun mine"
	desc = "A small explosive mine with a lightning bolt symbol on the side."
	minetype = /obj/effect/mine/stun

/obj/item/mine/frag
	name = "fragmentation mine"
	desc = "A small explosive mine with 'FRAG' and a grenade symbol on the side."
	minetype = /obj/effect/mine/frag

/obj/item/mine/training
	name = "training mine"
	desc = "A mine with its payload removed, for EOD training and demonstrations."
	minetype = /obj/effect/mine/training

/obj/item/mine/emp
	name = "emp mine"
	desc = "A small explosive mine with a lightning bolt symbol on the side."
	minetype = /obj/effect/mine/emp

/obj/item/mine/incendiary
	name = "incendiary mine"
	desc = "A small explosive mine with a fire symbol on the side."
	minetype = /obj/effect/mine/incendiary

/obj/item/mine/stripping
	name = "strip mine"
	desc = "A small bluespace mine with a symbol of clothing with a slash through it.."
	minetype = /obj/effect/mine/stripping

/obj/item/mine/gadget
	name = "gadget mine"
	desc = "A small pressure-triggered device. If no component is added, the internal release bolts will detonate in unison when triggered."

	allowed_gadgets = list(/obj/item/grenade, /obj/item/transfer_valve)

// This tells AI mobs to not be dumb and step on mines willingly.
/obj/item/mine/is_safe_to_step(mob/living/L)
	if(!(dq_get_hovering(L) || L.flying || L.is_incorporeal() || L.mob_size <= MOB_TINY))
		return FALSE
	return ..()

CAPABILITIES(/obj/item/mine)
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), wait(10 SECONDS), needs(req(PROC_REF(has_trap), silent = TRUE)), begins(MSG(mine/removing_trap)), then(PROC_REF(screwdriver_act_done)))
	op("self", in_hand(), label("Use"), begins(PROC_REF(priming_begins)), wait(10 SECONDS), on_interrupt(PROC_REF(priming_failed)), then(PROC_REF(primed)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	owns_one(nameof(trap), on_destroy = ON_DESTROY_CONTAINED)

MSG_DEF_SELF(mine/removing_trap, span_notice("You begin removing the trap from %T%."))

/obj/item/mine/proc/has_trap(datum/act/op/A)
	return (!!trap) ? null : MSG(req_failed)

/obj/item/mine/proc/screwdriver_act_done(datum/act/op/A)
	var/mob/user = A.actor
	if(!(trap))
		return
	to_chat(user, span_notice("You finish disconnecting the mine's trigger."))
	trap.forceMove(get_turf(src))
	rel_take(src, nameof(trap))

/obj/item/mine/lasertag
	name = "lasertag mine"
	desc = "A small mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag

/obj/item/mine/lasertag/red
	name = "red lasertag mine"
	desc = "A small red mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag/red

/obj/item/mine/lasertag/blue
	name = "blue lasertag mine"
	desc = "A small blue mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag/blue

/obj/item/mine/lasertag/omni
	name = "purple lasertag mine"
	desc = "A small purple mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag/omni

/obj/item/mine/lasertag/all
	name = "chaos lasertag mine"
	desc = "A small grey mine with 'BOOM' written on top, and an optical hazard warning on the side."
	minetype = /obj/effect/mine/lasertag/all
