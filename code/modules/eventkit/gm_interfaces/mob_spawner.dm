/datum/eventkit/mob_spawner
	// The path of the mob to be spawned
	var/path

	//The ai type path to be assigned to the mob
	var/use_custom_ai = FALSE
	var/ai_type = ""
	var/faction = ""
	var/intent = ""
	var/new_path = TRUE	//Sets default ai vars based on path. Tracked explicitly because tgui_act wouldn't make it work, used in tgui_data thusly

	// Defines if the location of the spawned mob should be bound of the users position
	var/loc_lock = FALSE

/datum/eventkit/mob_spawner/New()
	. = ..()

/datum/eventkit/mob_spawner/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "MobSpawner", "EventKit - Mob Spawner")
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/eventkit/mob_spawner/tgui_state(mob/user)
	return ADMIN_STATE(R_ADMIN|R_EVENT|R_DEBUG)

/datum/eventkit/mob_spawner/tgui_static_data(mob/user)
	var/list/data = list()

	data["initial_x"] = user.x;
	data["initial_y"] = user.y;
	data["initial_z"] = user.z;

	return data

/datum/eventkit/mob_spawner/tgui_data(mob/user)
	var/list/data = list()

	data["loc_lock"] = loc_lock
	if(loc_lock)
		data["loc_x"] = user.x
		data["loc_y"] = user.y
		data["loc_z"] = user.z

	data["use_custom_ai"] = use_custom_ai
	if(new_path)
		data["path"] = path;
		if(path)
			var/mob/M = new path()
			if(M)
				data["path_name"] = M.name
				data["desc"] = M.desc
				data["flavor_text"] = M.flavor_text
				if(isliving(M))
					var/mob/living/L = M

					//legacy ai_holder_type removed; modern brain has no
					// equivalent of swapping AI subtype at runtime.
					ai_type = null
					faction = (L.faction ? L.faction : "neutral")
					intent  = L.use_stance()
					new_path = FALSE

					// "max_health" is the mob's endurance; "health" is how
					// much of it the spawned mob starts with.
					data["max_health"] = L.get_endurance()
					data["health"] = L.get_endurance()
					if(isanimal(L))
						var/mob/living/simple_mob/S = L
						data["melee_damage_lower"] = S.melee_damage_lower ? S.melee_damage_lower : 0
						data["melee_damage_upper"] = S.melee_damage_upper ? S.melee_damage_upper : 0
						qdel(S)
					qdel(L)
			qdel(M)
	data["ai_type"] = ai_type
	data["faction"] = faction
	data["intent"]	= intent

	return data

/datum/eventkit/mob_spawner/tgui_act(action, list/params, datum/tgui/ui)
	. = ..()
	if(.)
		return
	if(!check_rights_for(ui.user.client, R_SPAWN))
		return
	switch(action)
		if("select_path")
			var/list/choices = typesof(/mob)
			var/newPath = act_prompt(ui.user, action, params, ui, "a1", list("kind" = "list", "message" = "Please select the new path of the mob you want to spawn.", "choices" = choices))
			if(isnull(newPath))
				return

			path = newPath
			new_path = TRUE
			return TRUE
		if("toggle_custom_ai")
			use_custom_ai = !use_custom_ai
			return TRUE
		if("set_faction")
			var/_answer_a2 = act_prompt(ui.user, action, params, ui, "a2", list("kind" = "text", "message" = "Please input your mobs' faction", "title" = "Faction", "default" = (faction ? faction : "neutral"), "max_length" = MAX_MESSAGE_LEN))
			if(isnull(_answer_a2))
				return
			faction = _answer_a2
			return TRUE
		if("set_intent")
			var/_answer_a3 = act_prompt(ui.user, action, params, ui, "a3", list("kind" = "list", "message" = "Please select preferred intent", "title" = "Select Intent", "choices" = list(I_HELP, I_HURT), "default" = (intent ? intent : I_HELP)))
			if(isnull(_answer_a3))
				return
			intent = _answer_a3
			return TRUE
		if("set_ai_path")
			//modern brain has no equivalent of "swap AI subtype at runtime";
			// behaviors are declared per mob subtype via get_ai_behaviors().
			to_chat(ui.user, span_warning("AI path selection no longer available; mob behaviors are per-subtype."))
			return TRUE
		if("loc_lock")
			loc_lock = !loc_lock
			return TRUE
		if("start_spawn")
			var/confirm = act_prompt(ui.user, action, params, ui, "a4", list("message" = "Are you sure that you want to start spawning your custom mobs?", "title" = "Confirmation", "choices" = list("Yes", "Cancel")))
			if(isnull(confirm))
				return

			if(confirm != "Yes")
				return FALSE

			var/amount = params["amount"]
			var/name = params["name"]
			var/x = params["x"]
			var/y = params["y"]
			var/z = params["z"]

			if(!name)
				to_chat(ui.user, span_warning("Name cannot be empty."))
				return FALSE

			var/turf/T = locate(x, y, z)
			if(!T)
				to_chat(ui.user, span_warning("Those coordinates are outside the boundaries of the map."))
				return FALSE

			for(var/i = 0, i < amount, i++)
				if(ispath(path,/turf))
					var/turf/TU = get_turf(locate(x, y, z))
					TU.ChangeTurf(path)
				else
					var/mob/M = new path(ui.user.loc)

					M.name = sanitize(name)
					M.desc = sanitize(params["desc"])
					M.flavor_text = sanitize(params["flavor_text"])
					if(isliving(M))
						var/mob/living/L = M
						if(isnum(params["max_health"]) && params["max_health"] > 0)
							L.endurance = params["max_health"]
						if(isnum(params["health"]))
							var/starting_injury = L.get_endurance() - params["health"]
							if(starting_injury > 0)
								L.injure(INJURY_BLUNT, starting_injury, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
						if(isanimal(M))
							var/mob/living/simple_mob/S = L
							if(isnum(params["melee_damage_lower"]))
								S.melee_damage_lower = params["melee_damage_lower"]
							if(isnum(params["melee_damage_upper"]))
								S.melee_damage_upper = params["melee_damage_upper"]
						if(use_custom_ai)
							L.faction = faction
							L.set_use_stance(intent)
							L.initialize_ai_brain()
							L.status_adjust(EFFECT_SLEEPING, -100)
						else
							to_chat(ui.user, span_notice("You can only set AI for subtypes of mob/living!"))

					var/size_mul = params["size_multiplier"]
					if(isnum(size_mul))
						if(isliving(M))
							var/mob/living/L = M
							L.resize(size_mul, animate = FALSE, uncapped = TRUE, ignore_prefs = TRUE)
						else
							M.size_multiplier = size_mul
						M.update_icon()
					else
						to_chat(ui.user, span_warning("Size Multiplier not applied: ([size_mul]) is not a valid input."))

					M.forceMove(T)

			log_and_message_admins("spawned [path] ([name]) at ([x],[y],[z]) [amount] times.")

			return TRUE

/datum/eventkit/mob_spawner/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		qdel(src)

ADMIN_VERB(eventkit_open_mob_spawner, R_SPAWN, "Open Mob Spawner", "Opens an advanced version of the mob spawner.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/datum/eventkit/mob_spawner/spawner = new()
	spawner.tgui_interact(user.mob)
