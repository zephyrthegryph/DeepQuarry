/**********************Mint**************************/
/obj/machinery/mineral/mint
	name = "coin press"
	desc = "A relatively crude hand-operated coin press that turns sheets (or ingots, as the case may be) of materials into fresh coins. They're <i>probably</i> not going to be considered legal tender in most polities, but you might fool a vending machine with one..?"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "coinpress0"
	density = TRUE
	anchored = TRUE
	var/coinsToProduce = 6	//how many coins do we make per sheet? a sheet is 2000 units whilst a coin is 250, and some material should be lost in the process

CAPABILITIES(/obj/machinery/mineral/mint)
	// One sheet every 2 seconds until the stack runs out: a lap per sheet. The stack is cleaned up when the last one is pressed.
	op("press", item(/obj/item/stack/material), priority(OP_PRIORITY_DEFAULT - 1), label("Press coins"), needs(req_is(nameof(anchored), TRUE, because = MSG(mint/unanchored)), req(PROC_REF(sheet_makes_coins), because = MSG(mint/no_coins))),
		starts(PROC_REF(press_started)), wait(2 SECONDS, repeats = PROC_REF(press_more), after_step = PROC_REF(press_sheet)), on_interrupt(PROC_REF(press_interrupted)), then(PROC_REF(press_finished)))

MSG_DEF_SELF(mint/unanchored, "it must be properly secured to operate")
MSG_DEF_SELF(mint/no_coins, "You can't make coins out of that.")

/obj/machinery/mineral/mint/proc/sheet_makes_coins(datum/act/op/A)
	var/obj/item/stack/material/M = A.held
	return (istype(M) && M.coin_type) ? null : MSG(mint/no_coins)

/obj/machinery/mineral/mint/proc/press_started(datum/act/op/A)
	var/obj/item/stack/material/M = A.held
	act_message(A.actor, src, others = "%U% starts to feed a sheet of [M.default_type] into %T%.")
	icon_state = "coinpress1"

/// Another sheet follows while the stack has any left.
/obj/machinery/mineral/mint/proc/press_more(datum/act/op/A)
	var/obj/item/stack/material/M = A.held
	return M.amount > 0

/obj/machinery/mineral/mint/proc/press_interrupted(datum/act/op/A)
	to_chat(A.actor, span_warning("\The [src] is hand-operated and requires your full attention!"))
	icon_state = "coinpress0"

/// One sheet pressed.
/obj/machinery/mineral/mint/proc/press_sheet(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/material/M = A.held
	M.set_amount(M.amount - 1, TRUE)
	while(coinsToProduce-- > 0)
		new M.coin_type(user.loc)
	src.visible_message(span_notice("\The [src] rattles and dispenses several [M.default_type] coins!"))
	coinsToProduce = initial(coinsToProduce)

/// The stack ran out.
/obj/machinery/mineral/mint/proc/press_finished(datum/act/op/A)
	var/obj/item/stack/material/M = A.held
	icon_state = "coinpress0"
	spent(M)	//clean it up just to be sure
	src.visible_message(span_notice("\The [src] has run out of usable materials."))
