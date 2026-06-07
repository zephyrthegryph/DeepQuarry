// Orion Trail arcade game — structured TGUI.
//
// State machine has four screens: game-over, event-in-progress,
// normal-stop, and pre-game. Each ships typed tgui_data; React picks
// the screen based on `screen` and renders the appropriate
// components. Events still embed their own HTML for now (the
// per-event handlers each emit ad-hoc buttons that haven't been
// unpacked); HtmlRenderer + forwardTopic relays clicks back to the
// arcade's Topic handler the same way they did before.

// arcade.dm #undefs the ORION_STATUS_* macros at end-of-file, so
// re-shadow the integer values here for use in our panel.
#define ORION_STATUS_START      1
#define ORION_STATUS_NORMAL     2
#define ORION_STATUS_GAMEOVER   3

#define ORION_SCREEN_START      "start"
#define ORION_SCREEN_NORMAL     "normal"
#define ORION_SCREEN_EVENT      "event"
#define ORION_SCREEN_GAMEOVER   "gameover"


/obj/machinery/computer/arcade/orion_trail/attack_hand(mob/living/user)
	// DQEdit — structured TGUI Orion Trail; the upstream attack_hand's
	// game-over side effects (death, ignite_mob etc. when emagged) still
	// run here, then the panel opens.
	if(..())
		return
	if(fuel <= 0 || food <= 0 || settlers.len == 0)
		gameStatus = ORION_STATUS_GAMEOVER
		event = null
	user.set_machine(src)

	if(gameStatus == ORION_STATUS_GAMEOVER)
		playsound(src, 'sound/arcade/ori_fail.ogg', 50, 1, extrarange = -3, falloff = 0.1, ignore_walls = FALSE)
		if(emagged)
			if(food <= 0)
				user.nutrition = 0
				to_chat(user, span_danger(span_large("Your body instantly contracts to that of one who has not eaten in months. Agonizing cramps seize you as you fall to the floor.")))
			if(fuel <= 0)
				user.adjust_fire_stacks(5)
				user.ignite_mob()
				to_chat(user, span_danger(span_large("You feel an immense wave of heat emanate from \the [src]. Your skin bursts into flames.")))
			to_chat(user, span_danger(span_large("You're never going to make it to Orion...")))
			user.death()
			emagged = 0
			gameStatus = ORION_STATUS_START
			name = "The Orion Trail"
			desc = "Learn how our ancestors got to Orion, and have fun in the process!"

	tgui_interact(user)

/obj/machinery/computer/arcade/orion_trail/tgui_state(mob/user)
	return GLOB.tgui_default_state

/obj/machinery/computer/arcade/orion_trail/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "OrionTrail", "The Orion Trail")
		ui.open()

/obj/machinery/computer/arcade/orion_trail/tgui_data(mob/user)
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
		data["stop_name"] = stops[turns]
		data["stop_blurb"] = stopblurbs[turns]
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

/obj/machinery/computer/arcade/orion_trail/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	switch(action)
		if("menu")
			Topic("menu=1", list("menu" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("new_game")
			Topic("newgame=1", list("newgame" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("continue")
			Topic("continue=1", list("continue" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("blackhole_continue")
			Topic("blackhole=1", list("blackhole" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("blackhole_around")
			Topic("pastblack=1", list("pastblack" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("killcrew")
			Topic("killcrew=1", list("killcrew" = "1"))
			SStgui.update_uis(src)
			return TRUE
		if("close")
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
