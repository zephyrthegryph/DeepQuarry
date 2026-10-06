// Orion Trail arcade game — structured TGUI.
//
// State machine has four screens: game-over, event-in-progress,
// normal-stop, and pre-game. Each ships typed tgui_data; React picks
// the screen based on `screen` and renders the appropriate
// components. Events still embed their own HTML for now (the
// per-event handlers each emit ad-hoc buttons that haven't been
// unpacked); HtmlRenderer + forwardTopic relays their links to the
// arcade's TOPIC_ACTION rows. The typed buttons call orion_* procs.

// arcade.dm #undefs the ORION_STATUS_* macros at end-of-file, so
// re-shadow the integer values here for use in our panel.
#define ORION_STATUS_START      1
#define ORION_STATUS_NORMAL     2
#define ORION_STATUS_GAMEOVER   3

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
		gameStatus = ORION_STATUS_GAMEOVER
		event = null
	user.set_machine(src)

	if(gameStatus == ORION_STATUS_GAMEOVER)
		play_sfx(src, SFX_ARCADE_ORI_FAIL, ignore_walls = FALSE)
		if(emagged)
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
			gameStatus = ORION_STATUS_START
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
		data["event_html"] = eventdat
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
	op("menu", ui_act(), then(PROC_REF(native_orion_ui_menu)))
	op("new_game", ui_act(), then(PROC_REF(native_orion_ui_new_game)))
	op("continue", ui_act(), then(PROC_REF(native_orion_ui_continue)))
	op("blackhole_continue", ui_act(), then(PROC_REF(native_orion_ui_blackhole_continue)))
	op("blackhole_around", ui_act(), then(PROC_REF(native_orion_ui_blackhole_around)))
	op("killcrew", ui_act(), then(PROC_REF(native_orion_ui_killcrew)))
	op("close", ui_act(), then(PROC_REF(native_orion_ui_close)))
	interface("OrionTrail", title = "The Orion Trail", state = nameof(GLOB.tgui_default_state))
	without("ui_open")
	ui_shape(screen = schema_text(), reasons = list_of(), event_html = any, turn = num(), stop_name = any, stop_blurb = any, crew = list_of(), food = num(), fuel = num(), engine = num(), hull = num(), electronics = num(), at_blackhole = bool())
	op("use", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_menu(datum/act/op/A)
	orion_menu(A.actor)
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_new_game(datum/act/op/A)
	orion_newgame(A.actor)
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_continue(datum/act/op/A)
	orion_continue(A.actor)
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_blackhole_continue(datum/act/op/A)
	orion_blackhole(A.actor)
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_blackhole_around(datum/act/op/A)
	orion_pastblack(A.actor)
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_killcrew(datum/act/op/A)
	orion_killcrew(A.actor)
	SStgui.update_uis(src)
	return OP_OK

/obj/machinery/computer/arcade/orion_trail/proc/native_orion_ui_close(datum/act/op/A)
	A.actor?.unset_machine()
	SStgui.close_uis(src)
	return OP_OK


#undef ORION_STATUS_START
#undef ORION_STATUS_NORMAL
#undef ORION_STATUS_GAMEOVER
#undef ORION_SCREEN_START
#undef ORION_SCREEN_NORMAL
#undef ORION_SCREEN_EVENT
#undef ORION_SCREEN_GAMEOVER
