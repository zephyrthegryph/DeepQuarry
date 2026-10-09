/obj/item/chainsaw
	name = "chainsaw"
	desc = "Vroom vroom."
	icon_state = "chainsaw0"
	item_state = "chainsaw0"
	var/max_fuel = 100
	w_class = ITEMSIZE_LARGE
	slot_flags = SLOT_BACK
	w_class = ITEMSIZE_LARGE
	slot_flags = SLOT_BACK
	var/active_force = 55
	var/inactive_force = 10

/obj/item/chainsaw/var/on = FALSE
TRACKED(/obj/item/chainsaw, on)

/obj/item/chainsaw/Initialize(mapload)
	var/datum/reagents/R = new/datum/reagents(max_fuel)
	rel_set(src, nameof(reagents), R)
	rel_set(R, nameof(R.my_atom), src)
	R.add_reagent(REAGENT_ID_FUEL, max_fuel)
	. = ..()

/obj/item/chainsaw/proc/turnOff(mob/user as mob)
	if(!on) return
	to_chat(user, "You switch the gas nozzle on the chainsaw, turning it off.")
	attack_verb = list("bluntly hit", "beat", "knocked")
	play_sfx(src, SFX_WEAPONS_CHAINSAW_TURNOFF)
	force = inactive_force
	edge = FALSE
	sharp = FALSE
	set_on(FALSE)

MSG_DEF(chainsaw/pulling, "You start pulling the string on %T%.", "%U% starts pulling the string on %T%.")
MSG_DEF_SELF(chainsaw/refilling, span_notice("You begin filling the tank on the chainsaw."))

CAPABILITIES(/obj/item/chainsaw)
	op("self", in_hand(), when(PROC_REF(stopped)), begins(MSG(chainsaw/pulling)), wait(1.5 SECONDS), then(PROC_REF(started)), on_interrupt(PROC_REF(string_fumbled)))
	op("off", in_hand(), when(PROC_REF(running)), priority(OP_PRIORITY_TAKE_OUT), then(PROC_REF(switched_off)))
	op("refuel", at_target(/obj/structure/reagent_dispensers/fueltank), begins(MSG(chainsaw/refilling)), wait(1.5 SECONDS), then(PROC_REF(refueled)), on_interrupt(PROC_REF(refuel_abandoned)))
	/// Burns fuel every 2 s while running.
	every(2 SECONDS, then(PROC_REF(chainsaw_step)), when = nameof(on))

/obj/item/chainsaw/proc/stopped(datum/act/op/A)
	return !on

/obj/item/chainsaw/proc/running(datum/act/op/A)
	return on

/obj/item/chainsaw/proc/switched_off(datum/act/op/A)
	turnOff(A.actor)
	return OP_OK

/// The string pull finished: with no fuel tank at all it will not start.
/obj/item/chainsaw/proc/started(datum/act/op/A)
	var/mob/user = A.actor
	if(max_fuel <= 0)
		to_chat(user, "\The [src] won't start!")
		return OP_OK
	act_message(user, src, MSG_SELF("You start %T% up with a loud grinding!"), MSG_OTHERS("%U% starts %T% up with a loud grinding!"))
	attack_verb = list("shredded", "ripped", "torn")
	play_sfx(src, SFX_WEAPONS_CHAINSAW_STARTUP, 4, vary = TRUE)
	force = active_force
	edge = TRUE
	sharp = TRUE
	set_on(TRUE)
	return OP_OK

/obj/item/chainsaw/proc/string_fumbled(datum/act/op/A)
	to_chat(A.actor, "You fumble with the string.")

/obj/item/chainsaw/afterattack(atom/A as mob|obj|turf|area, mob/user as mob, proximity)
	if(!proximity) return
	..()
	if(on)
		play_sfx(src, SFX_WEAPONS_CHAINSAW_ATTACK)
	if(A && on)
		if(get_fuel() > 0)
			reagents.remove_reagent(REAGENT_ID_FUEL, 1)
		if(istype(A,/obj/structure/window))
			var/obj/structure/window/W = A
			W.shatter()
		else if(istype(A,/obj/structure/grille))
			new /obj/structure/grille/broken(A.loc)
			replace_with(A, /obj/item/stack/rods)
		else if(istype(A,/obj/effect/plant))
			var/obj/effect/plant/P = A
			consumed(P, src) //Plant isn't surviving that. At all
		else if(istype(A,/obj/machinery/portable_atmospherics/hydroponics))
			var/obj/machinery/portable_atmospherics/hydroponics/Hyd = A
			if(Hyd.seed && !Hyd.dead)
				to_chat(user, span_notice("You shred the plant."))
				Hyd.die()

/obj/item/chainsaw/proc/refueled(datum/act/op/A)
	var/atom/tank = A.target
	tank.reagents.trans_to_obj(src, max_fuel)
	play_sfx(src, SFX_EFFECTS_REFILL)
	to_chat(A.actor, span_notice("Chainsaw succesfully refueled."))
	return OP_OK

/obj/item/chainsaw/proc/refuel_abandoned(datum/act/op/A)
	to_chat(A.actor, span_notice("Don't move while you're refilling the chainsaw."))

/// Burns fuel every 2 s while running (declared above); off, it sleeps.
/obj/item/chainsaw/proc/chainsaw_step(datum/act/timer/A)
	if(get_fuel() > 0)
		reagents.remove_reagent(REAGENT_ID_FUEL, 1)
		play_sfx(src, SFX_WEAPONS_CHAINSAW_TURNOFF, volume = 15)
	if(get_fuel() <= 0)
		visible_message("\The [src] sputters to a stop!")
		turnOff()

/obj/item/chainsaw/proc/get_fuel()
	return reagents.get_reagent_amount(REAGENT_ID_FUEL)

/obj/item/chainsaw/examine(mob/user)
	. = ..()
	if(max_fuel && get_dist(user, src) == 0)
		. += span_notice("The [src] feels like it contains roughtly [get_fuel()] units of fuel left.")

/obj/item/chainsaw/draw(datum/look/look)
	..()
	if(on)
		look.state("chainsaw1")
		look.held_state("chainsaw1")
	else
		look.state("chainsaw0")
		look.held_state("chainsaw0")
