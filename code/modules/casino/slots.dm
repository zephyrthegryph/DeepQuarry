
//Original Casino Code created by Shadowfire117#1269 - Ported from CHOMPstation
//Modified by GhostActual#2055 for use with VOREstation

/*
 * Slot Machine
 */

/obj/machinery/slot_machine
	name = "slot machine"
	desc = "A gambling machine designed to give you false hope and rob you of your wealth, hence why it's often called a one armed bandit."
	icon = 'icons/obj/casino_ch.dmi'
	icon_state = "slotmachine"
	anchored = 1
	density = 1
	power_channel = EQUIP
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 100
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 2 SECONDS
	light_power = 0.9
	light_range = 2
	light_color = "#B1FBBFF"
	var/isbroken = 0  //1 if someone banged it with something heavy
	var/ispowered = 1 //starts powered, changes with power_change()
	var/symbol1 = null
	var/symbol2 = null
	var/symbol3 = null

	var/datum/effect/effect/system/confetti_spread
	var/confetti_strength = 8

CAPABILITIES(/obj/machinery/slot_machine)
	owns_one(nameof(confetti_spread), /datum/effect/effect/system)
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("attackby", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Insert chip"), needs(req_bool(PROC_REF(not_running_holds), because = PROC_REF(not_running_refusal)), req_is(nameof(anchored), TRUE, because = MSG(slot_machine/unanchored))), then(PROC_REF(interaction_attackby)))

DECLARE_APPEARANCE_PROC(/obj/machinery/slot_machine, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/slot_machine/appearance_overlays()
	. = list()
	if(!ispowered || isbroken)
		icon_state = "slotmachine_off"
		if(isbroken) //If the thing is smashed, add crack overlay on top of the unpowered sprite.
			. += "slotmachine_broken"
		set_light(0)
		set_light_on(FALSE)
		return .

	icon_state = "slotmachine"
	set_light(2)
	set_light_on(TRUE)
	return .

/obj/machinery/slot_machine/power_change()
	if(isbroken) //Broken shit can't be powered.
		return
	. = ..()
	if(!power_lost())
		ispowered = 1
	else
		after(src, rand(0 SECONDS, 1.5 SECONDS), PROC_REF(lose_power))

/obj/machinery/slot_machine/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	if(work_busy(src))
		to_chat(user, span_notice("The slot machine is currently running."))
		return OP_OK
	return OP_DECLINE

/// Requirement (was REQ_* not_running): the legacy check answers TRUE to pass.
/obj/machinery/slot_machine/proc/not_running_holds(datum/act/op/A)
	var/answer = not_running(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why not_running_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/slot_machine/proc/not_running_refusal(datum/act/op/A)
	var/answer = not_running(A.actor, src, A.held)
	return istext(answer) ? answer : "the slot machine is currently running"

MSG_DEF_SELF(slot_machine/unanchored, "the slot machine isn't secured")

/// Requirement: the reels aren't spinning.
/obj/machinery/slot_machine/proc/not_running(mob/user, atom/target, obj/item/held)
	return !work_busy(src)

/obj/machinery/slot_machine/proc/interaction_attackby(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(istype(held, /obj/item/spacecasinocash))
		var/obj/item/spacecasinocash/C = held
		var/paid = insert_chip(C, user)
		if(paid)
			return OP_OK
		SStgui.update_uis(src)
		return OP_OK // don't smack that machine with your 2 chips

	return OP_OK

/obj/machinery/slot_machine/proc/insert_chip(obj/item/spacecasinocash/cashmoney, mob/user)
	if (ispowered == 0)
		return
	if (isbroken)
		return
	if (work_busy(src))
		to_chat(user,span_notice("The slot machine is currently rolling."))
		return
	if(cashmoney.worth < 5)
		to_chat(user,span_notice("You dont have enough chips to gamble!"))
		return

	to_chat(user,span_notice("You puts 5 credits in the slot machine and presses start."))
	cashmoney.worth -= 5
	cashmoney.update_icon()
	changed(cashmoney)

	if(cashmoney.worth <= 0)
		consume(cashmoney, user)

	hold_busy(src, 5 SECONDS) // spinning: a hold claims the machine until the result
	icon_state = "slotmachine_rolling"
	play_sfx(src.loc, SFX_MACHINES_SLOTMACHINE_PULL)

	var/slot1 = rand(0,9)
	switch(slot1)
		if(0 to 3) symbol1 = "cherry"
		if(4 to 4) symbol1 = "lemon"
		if(5 to 5) symbol1 = "bell"
		if(6 to 6) symbol1 = "four leaf clover"
		if(7 to 7) symbol1 = "seven"
		if(8 to 8) symbol1 = "diamond"
		if(9 to 9) symbol1 = "platinum coin"

	var/slot2 = rand(0,16)
	switch(slot2)
		if(0 to 5) symbol2 = "cherry"
		if(6 to 7) symbol2 = "lemon"
		if(8 to 9) symbol2 = "bell"
		if(10 to 11) symbol2 = "four leaf clover"
		if(12 to 13) symbol2 = "seven"
		if(14 to 15) symbol2 = "diamond"
		if(16) symbol2 = "platinum coin"

	var/slot3 = rand(0,9)
	switch(slot3)
		if(0 to 3) symbol3 = "cherry"
		if(4 to 4) symbol3 = "lemon"
		if(5 to 5) symbol3 = "bell"
		if(6 to 6) symbol3 = "four leaf clover"
		if(7 to 7) symbol3 = "seven"
		if(8 to 8) symbol3 = "diamond"
		if(9 to 9) symbol3 = "platinum coin"

	after(src, 5 SECONDS, PROC_REF(show_result), with = list(user, symbol1, symbol2, symbol3))

/*
 * Station Slot Machine (takes space cash instead of chips)
 */

/obj/machinery/station_slot_machine
	maintenance_flags = MACHINE_MAINT_WRENCH
	maintenance_wrench_time = 2 SECONDS
	name = "station slot machine"
	desc = "A gambling machine owned by NanoTrasen, designed to take Thalers as opposed to casino chips."
	icon = 'icons/obj/casino.dmi'
	icon_state = "ntslotmachine"
	anchored = 1
	density = 1
	power_channel = EQUIP
	use_power = USE_POWER_IDLE
	idle_power_usage = 10
	active_power_usage = 100
	light_power = 0.9
	light_range = 2
	light_color = "#B1FBBFF"
	var/isbroken = 0  //1 if someone banged it with something heavy
	var/ispowered = 1 //starts powered, changes with power_change()
	var/symbol1 = null
	var/symbol2 = null
	var/symbol3 = null

	var/datum/effect/effect/system/confetti_spread
	var/confetti_strength = 8

CAPABILITIES(/obj/machinery/station_slot_machine)
	owns_one(nameof(confetti_spread), /datum/effect/effect/system)
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("attackby", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Insert cash"), needs(req_bool(PROC_REF(not_running_holds), because = PROC_REF(not_running_refusal)), req_is(nameof(anchored), TRUE, because = MSG(station_slot_machine/unanchored))), then(PROC_REF(interaction_attackby)))

DECLARE_APPEARANCE_PROC(/obj/machinery/station_slot_machine, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/station_slot_machine/appearance_overlays()
	. = list()
	if(!ispowered || isbroken)
		icon_state = "ntslotmachine_off"
		if(isbroken) //If the thing is smashed, add crack overlay on top of the unpowered sprite.
			. += "ntslotmachine_broken"
		set_light(0)
		set_light_on(FALSE)
		return .

	icon_state = "ntslotmachine"
	set_light(2)
	set_light_on(TRUE)
	return .

/obj/machinery/station_slot_machine/power_change()
	if(isbroken) //Broken shit can't be powered.
		return
	. = ..()
	if(!power_lost())
		ispowered = 1
	else
		after(src, rand(0 SECONDS, 1.5 SECONDS), PROC_REF(lose_power))

/obj/machinery/station_slot_machine/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	if(work_busy(src))
		to_chat(user, span_notice("The slot machine is currently running."))
		return OP_OK
	return OP_DECLINE

/// Requirement (was REQ_* not_running): the legacy check answers TRUE to pass.
/obj/machinery/station_slot_machine/proc/not_running_holds(datum/act/op/A)
	var/answer = not_running(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why not_running_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/station_slot_machine/proc/not_running_refusal(datum/act/op/A)
	var/answer = not_running(A.actor, src, A.held)
	return istext(answer) ? answer : "the slot machine is currently running"

MSG_DEF_SELF(station_slot_machine/unanchored, "the slot machine isn't secured")

/// Requirement: the reels aren't spinning.
/obj/machinery/station_slot_machine/proc/not_running(mob/user, atom/target, obj/item/held)
	return !work_busy(src)

/obj/machinery/station_slot_machine/proc/interaction_attackby(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(istype(held, /obj/item/spacecash))
		var/obj/item/spacecash/C = held
		var/paid = insert_cash(C, user)
		if(paid)
			return OP_OK
		SStgui.update_uis(src)
		return OP_OK // don't smack that machine with your 2 chips

	return OP_OK

/obj/machinery/station_slot_machine/proc/insert_cash(obj/item/spacecash/cashmoney, mob/user)
	if (ispowered == 0)
		return
	if (isbroken)
		return
	if (work_busy(src))
		to_chat(user,span_notice("The slot machine is currently rolling."))
		return
	if(cashmoney.worth < 5)
		to_chat(user,span_notice("You dont have enough Thalers to gamble!"))
		return

	to_chat(user,span_notice("You puts 5 Thalers in the slot machine and presses start."))
	cashmoney.worth -= 5
	cashmoney.update_icon()

	if(cashmoney.worth <= 0)
		consume(cashmoney, user)

	hold_busy(src, 5 SECONDS) // spinning: a hold claims the machine until the result
	icon_state = "ntslotmachine_rolling"
	play_sfx(src.loc, SFX_MACHINES_SLOTMACHINE_PULL)

	var/slot1 = rand(0,9)
	switch(slot1)
		if(0 to 3) symbol1 = "cherry"
		if(4 to 4) symbol1 = "lemon"
		if(5 to 5) symbol1 = "bell"
		if(6 to 6) symbol1 = "four leaf clover"
		if(7 to 7) symbol1 = "seven"
		if(8 to 8) symbol1 = "diamond"
		if(9 to 9) symbol1 = "platinum coin"

	var/slot2 = rand(0,16)
	switch(slot2)
		if(0 to 5) symbol2 = "cherry"
		if(6 to 7) symbol2 = "lemon"
		if(8 to 9) symbol2 = "bell"
		if(10 to 11) symbol2 = "four leaf clover"
		if(12 to 13) symbol2 = "seven"
		if(14 to 15) symbol2 = "diamond"
		if(16) symbol2 = "platinum coin"

	var/slot3 = rand(0,9)
	switch(slot3)
		if(0 to 3) symbol3 = "cherry"
		if(4 to 4) symbol3 = "lemon"
		if(5 to 5) symbol3 = "bell"
		if(6 to 6) symbol3 = "four leaf clover"
		if(7 to 7) symbol3 = "seven"
		if(8 to 8) symbol3 = "diamond"
		if(9 to 9) symbol3 = "platinum coin"

	after(src, 5 SECONDS, PROC_REF(show_result), with = list(user, symbol1, symbol2, symbol3))

/obj/machinery/slot_machine/proc/show_result(mob/user, symbol1, symbol2, symbol3)
	var/output //Output variable to send out in chat after the large if statement.
	var/winnings = 0 //How much money will be given if any.
	var/celebrate = 0
	var/delaytime = 5 SECONDS

	to_chat(user,span_notice("The slot machine flashes with bright colours as the slots lights up with a [symbol1], a [symbol2] and a [symbol3]!"))

	if (symbol1 == "cherry" && symbol2 == "cherry" && symbol3 == "cherry")
		output = span_notice("Three cherries! The slot machine deposits chips worth 25 credits!")
		winnings = 25

	if ((symbol1 != "cherry" && symbol2 == "cherry" && symbol3 == "cherry") || (symbol1 == "cherry" && symbol2 != "cherry" && symbol3 == "cherry") ||(symbol1 == "cherry" && symbol2 == "cherry" && symbol3 != "cherry"))
		output = span_notice("Two cherries! The slot machine deposits a 10 credit chip!")
		winnings = 10

	if (symbol1 == "lemon" && symbol2 == "lemon" && symbol3 == "lemon")
		output = span_notice("Three lemons! The slot machine deposits a 50 credit chip!")
		winnings = 50

	if (symbol1 == "bell" && symbol2 == "bell" && symbol3 == "bell")
		output = span_notice("Three bells! The slot machine deposits chips a 100 credit chip!")
		winnings = 100

	if (symbol1 == "four leaf clover" && symbol2 == "four leaf clover" && symbol3 == "four leaf clover")
		output = span_notice("Three four leaf clovers! The slot machine deposits a 200 credit chip!")
		winnings = 200

	if (symbol1 == "seven" && symbol2 == "seven" && symbol3 == "seven")
		output = span_notice("Three sevens! The slot machine deposits a 300 credit chip!")
		winnings = 300
		celebrate = 1

	if (symbol1 == "diamond" && symbol2 == "diamond" && symbol3 == "diamond")
		output = span_notice("Three diamonds! The slot machine deposits a 500 credit chip!")
		winnings = 500
		celebrate = 1

	if (symbol1 == "platinum coin" && symbol2 == "platinum coin" && symbol3 == "platinum coin")
		output = span_notice("Three platinum coins! The slot machine deposits a 1000 credit chip!")
		winnings = 1000
		celebrate = 1

	icon_state = initial(icon_state) // Set it back to the original iconstate.

	if(!output) // Is there anything to output? If not, consider it a loss.
		to_chat(user,"Better luck next time!")
		return

	to_chat(user,output) //Output message

	if(winnings) //Did the person win?
		icon_state = "slotmachine_winning"
		play_sfx(src.loc, SFX_MACHINES_SLOTMACHINE)
		after(src, delaytime, PROC_REF(pay_out), with = list(winnings))

	if(celebrate) // Happy celebrations!
		rel_set(src, nameof(confetti_spread), new /datum/effect/effect/system/confetti_spread())
		src.confetti_spread.attach(src) //If somehow people start dragging slot machine
		confetti_spread.start_repeatedly(confetti_strength, 1 SECOND)

/obj/machinery/slot_machine/proc/pay_out(winnings)
	spawn_casinochips(winnings, src.loc)
	icon_state = "slotmachine"

/obj/machinery/station_slot_machine/proc/show_result(mob/user, symbol1, symbol2, symbol3)
	var/output //Output variable to send out in chat after the large if statement.
	var/winnings = 0 //How much money will be given if any.
	var/platinumwin = 0 // If you win the platinum chip or not
	var/celebrate = 0
	var/delaytime = 5 SECONDS

	to_chat(user,span_notice("The slot machine flashes with bright colours as the slots lights up with a [symbol1], a [symbol2] and a [symbol3]!"))

	if (symbol1 == "cherry" && symbol2 == "cherry" && symbol3 == "cherry")
		output = span_notice("Three cherries! The slot machine deposits 25 Thalers!")
		winnings = 25

	if ((symbol1 != "cherry" && symbol2 == "cherry" && symbol3 == "cherry") || (symbol1 == "cherry" && symbol2 != "cherry" && symbol3 == "cherry") ||(symbol1 == "cherry" && symbol2 == "cherry" && symbol3 != "cherry"))
		output = span_notice("Two cherries! The slot machine deposits 10 Thalers!")
		winnings = 10

	if (symbol1 == "lemon" && symbol2 == "lemon" && symbol3 == "lemon")
		output = span_notice("Three lemons! The slot machine deposits 50 Thalers!")
		winnings = 50

	if (symbol1 == "bell" && symbol2 == "bell" && symbol3 == "bell")
		output = span_notice("Three bells! The slot machine deposits 100 Thalers!")
		winnings = 100

	if (symbol1 == "four leaf clover" && symbol2 == "four leaf clover" && symbol3 == "four leaf clover")
		output = span_notice("Three four leaf clovers! The slot machine deposits 200 Thalers!")
		winnings = 200

	if (symbol1 == "seven" && symbol2 == "seven" && symbol3 == "seven")
		output = span_notice("Three sevens! The slot machine deposits 500 Thalers!")
		winnings = 500
		celebrate = 1

	if (symbol1 == "diamond" && symbol2 == "diamond" && symbol3 == "diamond")
		output = span_notice("Three diamonds! The slot machine deposits 1000 Thalers!")
		winnings = 1000
		celebrate = 1

	if (symbol1 == "platinum coin" && symbol2 == "platinum coin" && symbol3 == "platinum coin")
		output = span_notice("Three platinum coins! The slot machine deposits a platinum chip!")
		platinumwin = TRUE;
		celebrate = 1

	icon_state = initial(icon_state) // Set it back to the original iconstate.

	if(!output) // Is there anything to output? If not, consider it a loss.
		to_chat(user,"Better luck next time!")
		return

	to_chat(user,output) //Output message

	if(platinumwin) // Did they win the platinum chip?
		new /obj/item/casino_platinum_chip(src.loc)
		play_sfx(src.loc, SFX_MACHINES_SLOTMACHINE)

	if(winnings) //Did the person win?
		icon_state = "ntslotmachine_winning"
		play_sfx(src.loc, SFX_MACHINES_SLOTMACHINE)
		after(src, delaytime, PROC_REF(pay_out), with = list(winnings))

	if(celebrate) // Happy celebrations!
		rel_set(src, nameof(confetti_spread), new /datum/effect/effect/system/confetti_spread())
		src.confetti_spread.attach(src) //If somehow people start dragging slot machine
		confetti_spread.start_repeatedly(confetti_strength, 1 SECOND)

/obj/machinery/station_slot_machine/proc/pay_out(winnings)
	spawn_money(winnings, src.loc)
	icon_state = "ntslotmachine"

/obj/machinery/slot_machine/proc/lose_power()
	ispowered = 0
	update_icon()

/obj/machinery/station_slot_machine/proc/lose_power()
	ispowered = 0
	update_icon()
