// Behaviour-preservation tests for the service bots (hc-mobs): the control windows of the floorbot, cleanbot, farmbot, medbot, secbot and mulebot and what
// their buttons do. A button is pressed as a player's would be (hc_bot_press): through the op engine when the bot has an op for the action, else
// through today's tgui_act(); the window's data is read with tgui_data(). The same file passes before and after the bots move to interface() and
// op(ui_act()); only the adapter below names today's call.
//
// Nothing here depends on message text, on an op key or on a result being non-null.

/// Presses a window button as `actor` on `bot`.
/proc/hc_bot_press(mob/actor, mob/living/bot/bot, window, action, list/args)
	var/datum/op_result/result = test_ui(actor, bot, action, args)
	if(result)
		return result
	var/datum/tgui/ui = new(actor, bot, window)
	ui.status = STATUS_INTERACTIVE
	. = bot.tgui_act(action, args || list(), ui)
	qdel(ui)

/// The window data the bot shows `viewer`.
/proc/hc_bot_data(mob/viewer, mob/living/bot/bot)
	return bot.tgui_data(viewer)

/datum/unit_test/dq_hc_bots
	abstract_type = /datum/unit_test/dq_hc_bots
	/// A cyborg: a silicon always gets past the control lock.
	var/mob/living/silicon/robot/borg
	/// A person with no access: the lock keeps them out.
	var/mob/living/carbon/human/crew

/datum/unit_test/dq_hc_bots/proc/set_up_actors()
	borg = allocate(/mob/living/silicon/robot, test_floor())
	crew = allocate(/mob/living/carbon/human, test_floor())

/// A toggle button: `var_name` flips for a silicon, flips for anyone when the bot is unlocked, and stays for an ordinary person when it is locked.
/datum/unit_test/dq_hc_bots/proc/check_locked_toggle(mob/living/bot/bot, window, action, var_name)
	bot.locked = TRUE
	var/start = bot.vars[var_name]
	hc_bot_press(crew, bot, window, action)
	TEST_ASSERT_EQUAL(bot.vars[var_name], start, "[action]: a locked panel keeps an ordinary person out of [var_name]")
	hc_bot_press(borg, bot, window, action)
	TEST_ASSERT_NOTEQUAL(bot.vars[var_name], start, "[action]: a silicon works [var_name] through the lock")
	hc_bot_press(borg, bot, window, action)
	TEST_ASSERT_EQUAL(bot.vars[var_name], start, "[action]: pressing again puts [var_name] back")
	bot.locked = FALSE
	hc_bot_press(crew, bot, window, action)
	TEST_ASSERT_NOTEQUAL(bot.vars[var_name], start, "[action]: an unlocked panel is open to anyone")
	return null

/// A toggle button with no lock check.
/datum/unit_test/dq_hc_bots/proc/check_free_toggle(mob/living/bot/bot, window, action, var_name)
	var/start = bot.vars[var_name]
	hc_bot_press(crew, bot, window, action)
	TEST_ASSERT_NOTEQUAL(bot.vars[var_name], start, "[action]: anyone toggles [var_name]")
	hc_bot_press(crew, bot, window, action)
	TEST_ASSERT_EQUAL(bot.vars[var_name], start, "[action]: pressing again puts [var_name] back")
	return null

// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_hc_bots/floorbot_buttons
/datum/unit_test/dq_hc_bots/floorbot_buttons/Run()
	set_up_actors()
	var/mob/living/bot/floorbot/F = allocate(/mob/living/bot/floorbot, test_floor())
	var/was_on = F.on
	hc_bot_press(crew, F, "Floorbot", "start")
	TEST_ASSERT_NOTEQUAL(F.on, was_on, "the power button works for anyone")
	hc_bot_press(crew, F, "Floorbot", "start")
	TEST_ASSERT_EQUAL(F.on, was_on, "and back")
	var/failure = check_locked_toggle(F, "Floorbot", "vocal", "vocal")
	if(failure)
		return failure
	failure = check_locked_toggle(F, "Floorbot", "improve", "improvefloors")
	if(failure)
		return failure
	failure = check_locked_toggle(F, "Floorbot", "tiles", "eattiles")
	if(failure)
		return failure
	failure = check_locked_toggle(F, "Floorbot", "make", "maketiles")
	if(failure)
		return failure
	F.locked = TRUE
	hc_bot_press(crew, F, "Floorbot", "bridgemode", list("dir" = "NORTH"))
	TEST_ASSERT_NULL(F.targetdirection, "a locked panel keeps an ordinary person out of the bridge mode")
	hc_bot_press(borg, F, "Floorbot", "bridgemode", list("dir" = "NORTH"))
	TEST_ASSERT_EQUAL(F.targetdirection, NORTH, "a silicon sets the bridge direction")

/datum/unit_test/dq_hc_bots/floorbot_window_data
/datum/unit_test/dq_hc_bots/floorbot_window_data/Run()
	set_up_actors()
	var/mob/living/bot/floorbot/F = allocate(/mob/living/bot/floorbot, test_floor())
	F.locked = TRUE
	F.improvefloors = TRUE
	var/list/hidden = hc_bot_data(crew, F)
	TEST_ASSERT_NULL(hidden["improvefloors"], "a locked panel hides the settings from an ordinary person")
	TEST_ASSERT_EQUAL(hidden["amount"], F.amount, "the tile count is always shown")
	TEST_ASSERT_EQUAL(hidden["locked"], F.locked, "so is the lock")
	TEST_ASSERT(islist(hidden["possible_bmode"]), "the bridge directions are listed")
	var/list/shown = hc_bot_data(borg, F)
	TEST_ASSERT_EQUAL(shown["improvefloors"], F.improvefloors, "a silicon sees the settings")
	F.locked = FALSE
	TEST_ASSERT_EQUAL(hc_bot_data(crew, F)["improvefloors"], F.improvefloors, "an unlocked panel shows them to anyone")

/datum/unit_test/dq_hc_bots/cleanbot_buttons
/datum/unit_test/dq_hc_bots/cleanbot_buttons/Run()
	set_up_actors()
	var/mob/living/bot/cleanbot/C = allocate(/mob/living/bot/cleanbot, test_floor())
	var/was_on = C.on
	hc_bot_press(crew, C, "Cleanbot", "start")
	TEST_ASSERT_NOTEQUAL(C.on, was_on, "the power button works for anyone")
	hc_bot_press(crew, C, "Cleanbot", "start")
	TEST_ASSERT_EQUAL(C.on, was_on, "and back")
	var/failure = check_free_toggle(C, "Cleanbot", "blood", "blood")
	if(failure)
		return failure
	failure = check_free_toggle(C, "Cleanbot", "vocal", "vocal")
	if(failure)
		return failure
	failure = check_free_toggle(C, "Cleanbot", "wet_floors", "wet_floors")
	if(failure)
		return failure
	failure = check_free_toggle(C, "Cleanbot", "spray_blood", "spray_blood")
	if(failure)
		return failure
	C.patrol_path = list(1, 2)
	var/patrolling = C.will_patrol
	hc_bot_press(crew, C, "Cleanbot", "patrol")
	TEST_ASSERT_NOTEQUAL(C.will_patrol, patrolling, "the patrol button flips patrolling")
	TEST_ASSERT_NULL(C.patrol_path, "and drops the old route")
	var/list/data = hc_bot_data(crew, C)
	TEST_ASSERT_EQUAL(data["version"], "v2.0", "the window shows the version")
	TEST_ASSERT_EQUAL(data["patrol"], C.will_patrol, "the patrol field is the patrol setting")

/datum/unit_test/dq_hc_bots/farmbot_buttons
/datum/unit_test/dq_hc_bots/farmbot_buttons/Run()
	set_up_actors()
	var/mob/living/bot/farmbot/B = allocate(/mob/living/bot/farmbot, test_floor())
	var/was_on = B.on
	hc_bot_press(crew, B, "Farmbot", "power")
	TEST_ASSERT_EQUAL(B.on, was_on, "a person with no access cannot switch it")
	hc_bot_press(borg, B, "Farmbot", "power")
	TEST_ASSERT_NOTEQUAL(B.on, was_on, "a silicon can")
	B.locked = TRUE
	for(var/list/row in list(list("water", "waters_trays"), list("refill", "refills_water"), list("weed", "uproots_weeds"), list("replacenutri", "replaces_nutriment")))
		var/start = B.vars[row[2]]
		hc_bot_press(borg, B, "Farmbot", row[1])
		TEST_ASSERT_EQUAL(B.vars[row[2]], start, "[row[1]]: a locked panel keeps even a silicon out")
	B.locked = FALSE
	for(var/list/row in list(list("water", "waters_trays"), list("refill", "refills_water"), list("weed", "uproots_weeds"), list("replacenutri", "replaces_nutriment")))
		var/start = B.vars[row[2]]
		hc_bot_press(crew, B, "Farmbot", row[1])
		TEST_ASSERT_NOTEQUAL(B.vars[row[2]], start, "[row[1]]: an unlocked panel toggles [row[2]]")
	var/list/data = hc_bot_data(crew, B)
	TEST_ASSERT(data["tank"], "the window says there is a tank")
	TEST_ASSERT_EQUAL(data["tankMaxVolume"], B.tank.reagents.maximum_volume, "and how big it is")
	TEST_ASSERT_EQUAL(data["waters_trays"], B.waters_trays, "an unlocked panel shows the settings")
	B.locked = TRUE
	TEST_ASSERT_NULL(hc_bot_data(crew, B)["waters_trays"], "a locked one hides them")

/// The medbot limits (code/__defines/medbot.dm: urgency 1 to 4, injection up to 15) are written out as numbers.
/datum/unit_test/dq_hc_bots/medbot_buttons
/datum/unit_test/dq_hc_bots/medbot_buttons/Run()
	set_up_actors()
	var/mob/living/bot/medbot/M = allocate(/mob/living/bot/medbot, test_floor())
	var/was_on = M.on
	hc_bot_press(crew, M, "Medbot", "power")
	TEST_ASSERT_EQUAL(M.on, was_on, "a person with no access cannot switch it")
	hc_bot_press(borg, M, "Medbot", "power")
	TEST_ASSERT_NOTEQUAL(M.on, was_on, "a silicon can")
	var/failure = check_locked_toggle(M, "Medbot", "use_beaker", "use_beaker")
	if(failure)
		return failure
	failure = check_locked_toggle(M, "Medbot", "togglevoice", "vocal")
	if(failure)
		return failure
	failure = check_locked_toggle(M, "Medbot", "declaretreatment", "declare_treatment")
	if(failure)
		return failure
	M.locked = TRUE
	var/urgency = M.min_urgency
	hc_bot_press(crew, M, "Medbot", "adj_urgency", list("val" = 4))
	TEST_ASSERT_EQUAL(M.min_urgency, urgency, "a locked panel keeps an ordinary person out of the urgency")
	hc_bot_press(borg, M, "Medbot", "adj_urgency", list("val" = 4 + 5))
	TEST_ASSERT_EQUAL(M.min_urgency, 4, "a silicon sets it, and it is clamped to the top")
	hc_bot_press(borg, M, "Medbot", "adj_urgency", list("val" = 1 - 5))
	TEST_ASSERT_EQUAL(M.min_urgency, 1, "and to the bottom")
	hc_bot_press(borg, M, "Medbot", "adj_inject", list("val" = 15))
	TEST_ASSERT_EQUAL(M.injection_amount, 15, "a silicon sets the injection amount")
	hc_bot_press(borg, M, "Medbot", "adj_inject", list("val" = 15 + 100))
	TEST_ASSERT(M.injection_amount <= 15, "an amount above the maximum is not accepted as given")
	var/list/data = hc_bot_data(borg, M)
	TEST_ASSERT_EQUAL(data["injection_amount_max"], 15, "the window shows the limits")
	TEST_ASSERT_NULL(hc_bot_data(crew, M)["use_beaker"], "a locked panel hides the settings from an ordinary person")

/datum/unit_test/dq_hc_bots/secbot_buttons
/datum/unit_test/dq_hc_bots/secbot_buttons/Run()
	set_up_actors()
	var/mob/living/bot/secbot/S = allocate(/mob/living/bot/secbot, test_floor())
	var/was_on = S.on
	hc_bot_press(crew, S, "Secbot", "power")
	TEST_ASSERT_EQUAL(S.on, was_on, "a person with no access cannot switch it")
	hc_bot_press(borg, S, "Secbot", "power")
	TEST_ASSERT_NOTEQUAL(S.on, was_on, "a silicon can")
	var/failure = check_locked_toggle(S, "Secbot", "idcheck", "idcheck")
	if(failure)
		return failure
	failure = check_locked_toggle(S, "Secbot", "ignorerec", "check_records")
	if(failure)
		return failure
	failure = check_locked_toggle(S, "Secbot", "ignorearr", "check_arrest")
	if(failure)
		return failure
	failure = check_locked_toggle(S, "Secbot", "switchmode", "arrest_type")
	if(failure)
		return failure
	failure = check_locked_toggle(S, "Secbot", "patrol", "will_patrol")
	if(failure)
		return failure
	failure = check_locked_toggle(S, "Secbot", "declarearrests", "declare_arrests")
	if(failure)
		return failure
	S.locked = TRUE
	TEST_ASSERT_NULL(hc_bot_data(crew, S)["idcheck"], "a locked panel hides the settings from an ordinary person")
	TEST_ASSERT_EQUAL(hc_bot_data(borg, S)["idcheck"], S.idcheck, "a silicon sees them")

/datum/unit_test/dq_hc_bots/mulebot_buttons
/datum/unit_test/dq_hc_bots/mulebot_buttons/Run()
	set_up_actors()
	var/mob/living/bot/mulebot/M = allocate(/mob/living/bot/mulebot, test_floor())
	var/was_on = M.on
	hc_bot_press(crew, M, "MuleBot", "power")
	TEST_ASSERT_NOTEQUAL(M.on, was_on, "the power button works")
	hc_bot_press(crew, M, "MuleBot", "stop")
	TEST_ASSERT(M.paused, "stop pauses it")
	hc_bot_press(crew, M, "MuleBot", "go")
	TEST_ASSERT(!M.paused, "go lets it run")
	var/failure = check_free_toggle(M, "MuleBot", "autoret", "auto_return")
	if(failure)
		return failure
	failure = check_free_toggle(M, "MuleBot", "cargotypes", "crates_only")
	if(failure)
		return failure
	failure = check_free_toggle(M, "MuleBot", "safety", "safety")
	if(failure)
		return failure
	var/list/data = hc_bot_data(borg, M)
	TEST_ASSERT(data["issillicon"], "the window knows a silicon is looking")
	TEST_ASSERT(!hc_bot_data(crew, M)["issillicon"], "and an ordinary person is not")
	TEST_ASSERT_EQUAL(data["power"], M.on, "the power field is the power state")
	TEST_ASSERT_EQUAL(data["hatch"], M.open, "the hatch field is the hatch state")
