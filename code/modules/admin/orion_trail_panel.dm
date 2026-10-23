// Orion Trail arcade game — structured TGUI.
//
// State machine has four screens: game-over, event-in-progress,
// normal-stop, and pre-game. Each ships typed tgui_data; React picks
// the screen based on `screen` and renders the appropriate
// components. An event ships its title, story lines and choices as data;
// every choice is an op (ui_act) that calls the orion_* procs.

#define ORION_SCREEN_START      "start"
#define ORION_SCREEN_NORMAL     "normal"
#define ORION_SCREEN_EVENT      "event"
#define ORION_SCREEN_GAMEOVER   "gameover"


// structured TGUI Orion Trail; the upstream attack_hand's
// game-over side effects (death, ignite_mob etc. when emagged) still
// run here, then the panel opens.
/obj/machinery/computer/arcade/orion_trail/proc/interaction_use(datum/act/op/A)
	var/mob/living/user = A.actor
	if(fuel <= 0 || food <= 0 || settlers.len == 0)
		set_gameStatus(ORION_STATUS_GAMEOVER)
		set_event(null)
	user.set_machine(src)

	if(gameStatus == ORION_STATUS_GAMEOVER)
		play_sfx(src, SFX_ARCADE_ORI_FAIL, ignore_walls = FALSE)
		if(emagged())
			if(food <= 0)
				user.set_nutrition(0)
				to_chat(user, span_danger(span_large("Your body instantly contracts to that of one who has not eaten in months. Agonizing cramps seize you as you fall to the floor.")))
			if(fuel <= 0)
				user.adjust_fire_stacks(5)
				user.ignite_mob()
				to_chat(user, span_danger(span_large("You feel an immense wave of heat emanate from \the [src]. Your skin bursts into flames.")))
			to_chat(user, span_danger(span_large("You're never going to make it to Orion...")))
			user.death()
			set_emagged(0)
			set_gameStatus(ORION_STATUS_START)
			name = "The Orion Trail"
			desc = "Learn how our ancestors got to Orion, and have fun in the process!"

	tgui_interact(user)
	return TRUE

/// /obj/machinery/computer/arcade/orion_trail's window data.
/obj/machinery/computer/arcade/orion_trail/ui_data(datum/act/eval/A)
	var/list/data = list()
	if(gameStatus == ORION_STATUS_GAMEOVER)
		data["screen"] = ORION_SCREEN_GAMEOVER
		data["reasons"] = list()
		if(settlers.len == 0)
			data["reasons"] += "Your entire crew died, and your ship joins the fleet of ghost-ships littering the galaxy."
		else
			if(food <= 0)
				data["reasons"] += "You ran out of food and starved."
			if(fuel <= 0)
				data["reasons"] += "You ran out of fuel, and drift, slowly, into a star."
		return data
	if(event)
		data["screen"] = ORION_SCREEN_EVENT
		data["event_title"] = event
		data["event_lines"] = eventlines ? eventlines.Copy() : list()
		data["event_actions"] = orion_event_actions()
		return data
	if(gameStatus == ORION_STATUS_NORMAL)
		data["screen"] = ORION_SCREEN_NORMAL
		data["turn"] = turns
		data["stop_name"] = LAZYACCESS(stops, turns)
		data["stop_blurb"] = LAZYACCESS(stopblurbs, turns)
		data["crew"] = settlers.Copy()
		data["food"] = food
		data["fuel"] = fuel
		data["engine"] = engine
		data["hull"] = hull
		data["electronics"] = electronics
		data["at_blackhole"] = turns == 7
		return data
	data["screen"] = ORION_SCREEN_START
	return data

CAPABILITIES(/obj/machinery/computer/arcade/orion_trail)
	per_type(nameof(stops), PROC_REF(build_stops))
	per_type(nameof(stopblurbs), PROC_REF(build_stopblurbs))
	op("slow", ui_act(), then(PROC_REF(ui_orion_slow)))
	op("useengine", ui_act(), then(PROC_REF(ui_orion_useengine)))
	op("useelec", ui_act(), then(PROC_REF(ui_orion_useelec)))
	op("usehull", ui_act(), then(PROC_REF(ui_orion_usehull)))
	op("wait", ui_act(), then(PROC_REF(ui_orion_wait)))
	op("keepspeed", ui_act(), then(PROC_REF(ui_orion_keepspeed)))
	op("holedeath", ui_act(), then(PROC_REF(ui_orion_holedeath)))
	op("eventclose", ui_act(), then(PROC_REF(ui_orion_eventclose)))
	op("buycrew", ui_act(), then(PROC_REF(ui_orion_buycrew)))
	op("sellcrew", ui_act(), then(PROC_REF(ui_orion_sellcrew)))
	op("leave_spaceport", ui_act(), then(PROC_REF(ui_orion_leave_spaceport)))
	op("raid_spaceport", ui_act(), then(PROC_REF(ui_orion_raid_spaceport)))
	op("buyparts", ui_act("buyparts", arg("part", int(1, 3))), then(PROC_REF(ui_orion_buyparts)))
	op("trade", ui_act("trade", arg("kind", int(1, 2))), then(PROC_REF(ui_orion_trade)))
	emag(then(PROC_REF(on_emag)), powered = FALSE)
	op("menu", ui_act(), then(PROC_REF(native_orion_ui_menu)))
	op("new_game", ui_act(), then(PROC_REF(native_orion_ui_new_game)))
	op("continue", ui_act(), then(PROC_REF(native_orion_ui_continue)))
	op("blackhole_continue", ui_act(), then(PROC_REF(native_orion_ui_blackhole_continue)))
	op("blackhole_around", ui_act(), then(PROC_REF(native_orion_ui_blackhole_around)))
	op("killcrew", ui_act(), then(PROC_REF(native_orion_ui_killcrew)))
	op("close", ui_act(), then(PROC_REF(native_orion_ui_close)))
	interface("OrionTrail", title = "The Orion Trail", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	ui_shape(screen = schema_text(), reasons = list_of(), event_title = schema_text(), event_lines = list_of(), event_actions = list_of(), turn = num(), stop_name = any, stop_blurb = any, crew = list_of(), food = num(), fuel = num(), engine = num(), hull = num(), electronics = num(), at_blackhole = bool())
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_menu(datum/act/op/A)
	orion_menu(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_new_game(datum/act/op/A)
	orion_newgame(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_continue(datum/act/op/A)
	orion_continue(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_blackhole_continue(datum/act/op/A)
	orion_blackhole(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_blackhole_around(datum/act/op/A)
	orion_pastblack(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_killcrew(datum/act/op/A)
	orion_killcrew(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_close(datum/act/op/A)
	A.actor?.unset_machine()
	SStgui.close_uis(src)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_slow(datum/act/op/A)
	orion_slow(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_useengine(datum/act/op/A)
	orion_useengine(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_useelec(datum/act/op/A)
	orion_useelec(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_usehull(datum/act/op/A)
	orion_usehull(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_wait(datum/act/op/A)
	orion_wait(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_keepspeed(datum/act/op/A)
	orion_keepspeed(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_holedeath(datum/act/op/A)
	orion_holedeath(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_eventclose(datum/act/op/A)
	orion_eventclose(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_buycrew(datum/act/op/A)
	orion_buycrew(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_sellcrew(datum/act/op/A)
	orion_sellcrew(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_leave_spaceport(datum/act/op/A)
	orion_leave_spaceport(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_raid_spaceport(datum/act/op/A)
	orion_raid_spaceport(A.actor)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_buyparts(datum/act/op/A, part)
	orion_buyparts(A.actor, part)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/ui_orion_trade(datum/act/op/A, kind)
	orion_trade(A.actor, kind)
	return OP_OK


#undef ORION_SCREEN_START
#undef ORION_SCREEN_NORMAL
#undef ORION_SCREEN_EVENT
#undef ORION_SCREEN_GAMEOVER
