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
	op("press", item(/obj/item/stack/material), priority(OP_PRIORITY_DEFAULT - 1), label("Press coins"), needs(req_is(nameof(anchored), TRUE, because = MSG(mint/unanchored))), then(PROC_REF(interaction_press)))

MSG_DEF_SELF(mint/unanchored, "it must be properly secured to operate")

/obj/machinery/mineral/mint/proc/interaction_press(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/material/M = A.held
	if(!M.coin_type)
		user.visible_message(span_notice("You can't make coins out of that."))
		return OP_OK
	else if(M.coin_type)
		act_message(user, src, others = "%U% starts to feed a sheet of [M.default_type] into %T%.")
		press_next(user, M)
	return OP_OK

/// One sheet every 2 seconds (a timed action each) until the stack runs out.
/obj/machinery/mineral/mint/proc/press_next(mob/user, obj/item/stack/material/M)
	if(M.amount <= 0)
		return
	icon_state = "coinpress1"
	task_start(/datum/task/timed/mint_press_sheet, user, src, M = M)

/obj/machinery/mineral/mint/proc/press_interrupted(datum/task/timed/mint_press_sheet/task)
	var/mob/user = task.actor
	to_chat(user,span_warning("\The [src] is hand-operated and requires your full attention!"))
	icon_state = "coinpress0"

/datum/task/timed/mint_press_sheet
	duration = 2 SECONDS
	complete_proc = /obj/machinery/mineral/mint/proc/press_sheet
	cancel_proc = /obj/machinery/mineral/mint/proc/press_interrupted
	var/obj/item/stack/material/M

/obj/machinery/mineral/mint/proc/press_sheet(datum/task/timed/mint_press_sheet/task)
	var/mob/user = task.actor
	var/obj/item/stack/material/M = task.M
	M.set_amount(M.amount - 1, TRUE)
	while(coinsToProduce-- > 0)
		new M.coin_type(user.loc)
	src.visible_message(span_notice("\The [src] rattles and dispenses several [M.default_type] coins!"))
	coinsToProduce = initial(coinsToProduce)
	if(M.amount == 0)
		icon_state = "coinpress0"
		spent(M)	//clean it up just to be sure
		src.visible_message(span_notice("\The [src] has run out of usable materials."))
		return
	press_next(user, M)
