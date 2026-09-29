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


/obj/machinery/computer/arcade/orion_trail/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/orion_trail_use,
	)
	..()

// structured TGUI Orion Trail; the upstream attack_hand's
// game-over side effects (death, ignite_mob etc. when emagged) still
// run here, then the panel opens.
/datum/interaction/machine_hand/orion_trail_use
	id = "orion_trail_use"
	name = "Use"
	effect = /obj/machinery/computer/arcade/orion_trail/proc/interaction_use

/obj/machinery/computer/arcade/orion_trail/proc/interaction_use(mob/living/user, obj/item/held, datum/interaction/interaction)
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

DECLARE_UI_STATE(/obj/machinery/computer/arcade/orion_trail, GLOB.tgui_default_state)

DECLARE_UI(/obj/machinery/computer/arcade/orion_trail, "OrionTrail", UI_TITLE("The Orion Trail"))

UI_DATA_REPLACE(/obj/machinery/computer/arcade/orion_trail, "merge:ui_data_obj_machinery_computer_arcade_orion_trail{screen:text,reasons:list,event_html:unknown,turn:num,stop_name:unknown,stop_blurb:unknown,crew:list,food:num,fuel:num,engine:num,hull:num,electronics:num,at_blackhole:bool}")

/// The computed part of /obj/machinery/computer/arcade/orion_trail's window data (declared on its UI_DATA row).
/obj/machinery/computer/arcade/orion_trail/proc/ui_data_obj_machinery_computer_arcade_orion_trail(mob/user, datum/tgui/ui, datum/tgui_state/state)
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

UI_ACT(/obj/machinery/computer/arcade/orion_trail, "menu", ui_act_menu)
UI_ACT_PROC(/obj/machinery/computer/arcade/orion_trail, ui_act_menu)
	orion_menu(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/arcade/orion_trail, "new_game", ui_act_new_game)
UI_ACT_PROC(/obj/machinery/computer/arcade/orion_trail, ui_act_new_game)
	orion_newgame(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/arcade/orion_trail, "continue", ui_act_continue)
UI_ACT_PROC(/obj/machinery/computer/arcade/orion_trail, ui_act_continue)
	orion_continue(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/arcade/orion_trail, "blackhole_continue", ui_act_blackhole_continue)
UI_ACT_PROC(/obj/machinery/computer/arcade/orion_trail, ui_act_blackhole_continue)
	orion_blackhole(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/arcade/orion_trail, "blackhole_around", ui_act_blackhole_around)
UI_ACT_PROC(/obj/machinery/computer/arcade/orion_trail, ui_act_blackhole_around)
	orion_pastblack(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/arcade/orion_trail, "killcrew", ui_act_killcrew)
UI_ACT_PROC(/obj/machinery/computer/arcade/orion_trail, ui_act_killcrew)
	orion_killcrew(ui.user)
	SStgui.update_uis(src)
	return TRUE

UI_ACT(/obj/machinery/computer/arcade/orion_trail, "close", ui_act_close)
UI_ACT_PROC(/obj/machinery/computer/arcade/orion_trail, ui_act_close)
	ui.user?.unset_machine()
	SStgui.close_uis(src)
	return TRUE


#undef ORION_STATUS_START
#undef ORION_STATUS_NORMAL
#undef ORION_STATUS_GAMEOVER
#undef ORION_SCREEN_START
#undef ORION_SCREEN_NORMAL
#undef ORION_SCREEN_EVENT
#undef ORION_SCREEN_GAMEOVER
