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

CAPABILITIES(/datum/eventkit/mob_spawner)
	interface("MobSpawner", title = "EventKit - Mob Spawner", rights = R_ADMIN|R_EVENT|R_DEBUG)
	op("select_path", ui_act("select_path"), asks(/datum/prompt/choice/mob_spawner_setting/path, fields = list("choices" = computed(PROC_REF(mob_paths))), step = "value"), then(PROC_REF(ui_act_select_path)))
	op("toggle_custom_ai", ui_act("toggle_custom_ai"), then(PROC_REF(ui_act_toggle_custom_ai)))
	op("set_faction", ui_act("set_faction"), asks(/datum/prompt/text/mob_spawner_faction, fields = list("default" = computed(PROC_REF(faction_default))), step = "value"), then(PROC_REF(ui_act_set_faction)))
	op("set_intent", ui_act("set_intent"), asks(/datum/prompt/choice/mob_spawner_setting/intent, fields = list("default" = computed(PROC_REF(intent_default))), step = "value"), then(PROC_REF(ui_act_set_intent)))
	op("set_ai_path", ui_act("set_ai_path"), then(PROC_REF(ui_act_set_ai_path)))
	op("loc_lock", ui_act("loc_lock"), then(PROC_REF(ui_act_loc_lock)))
	op("start_spawn", ui_act("start_spawn", arg("amount", num()), arg("desc", schema_text(4096)), arg("flavor_text", schema_text(4096)), arg("health", num()), arg("max_health", num()), arg("melee_damage_lower", num()), arg("melee_damage_upper", num()), arg("name", schema_text(4096)), arg("size_multiplier", num()), arg("x", schema_text(4096)), arg("y", schema_text(4096)), arg("z", schema_text(4096))), asks(/datum/prompt/choice/mob_spawner_spawn, step = "confirm"), then(PROC_REF(ui_act_start_spawn)))

/datum/eventkit/mob_spawner/tgui_static_data(mob/user)
	var/list/data = list()

	data["initial_x"] = user.x;
	data["initial_y"] = user.y;
	data["initial_z"] = user.z;

	return data

/datum/eventkit/mob_spawner/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["loc_lock"] = loc_lock
	data["use_custom_ai"] = use_custom_ai
	data["ai_type"] = ai_type
	data["faction"] = faction
	data["intent"] = intent
	var/list/merged_1 = ui_data_datum_eventkit_mob_spawner(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /datum/eventkit/mob_spawner's window data.
/datum/eventkit/mob_spawner/proc/ui_data_datum_eventkit_mob_spawner(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	if(loc_lock)
		data["loc_x"] = user.x
		data["loc_y"] = user.y
		data["loc_z"] = user.z

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
					intent  = L.combat_mode ? I_HURT : I_HELP // the prototype's default posture (state; a fresh mob holds no variant)
					new_path = FALSE

					// "max_health" is the mob's endurance; "health" is how
					// much of it the spawned mob starts with.
					data["max_health"] = L.get_endurance()
					data["health"] = L.get_endurance()
					if(isanimal(L))
						var/mob/living/simple_mob/S = L
						data["melee_damage_lower"] = S.melee_damage_lower ? S.melee_damage_lower : 0
						data["melee_damage_upper"] = S.melee_damage_upper ? S.melee_damage_upper : 0
						spent(S, user)
					spent(L, user)
			spent(M, user)

	return data

/datum/eventkit/mob_spawner/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!check_rights_for(user.client, R_SPAWN))
		return FALSE
	return TRUE

/datum/eventkit/mob_spawner/proc/ui_act_select_path(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	apply_spawner_setting("select_path", A.step_value("value"))
	return TRUE

/datum/eventkit/mob_spawner/proc/ui_act_toggle_custom_ai(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	use_custom_ai = !use_custom_ai
	return TRUE

/datum/eventkit/mob_spawner/proc/ui_act_set_faction(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	apply_spawner_setting("set_faction", A.step_value("value"))
	return TRUE

/datum/eventkit/mob_spawner/proc/ui_act_set_intent(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	apply_spawner_setting("set_intent", A.step_value("value"))
	return TRUE

/datum/eventkit/mob_spawner/proc/ui_act_set_ai_path(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	//modern brain has no equivalent of "swap AI subtype at runtime";
	// behaviors are declared per mob subtype via the get_ai_behaviors type table.
	to_chat(user, span_warning("AI path selection no longer available; mob behaviors are per-subtype."))
	return TRUE

/datum/eventkit/mob_spawner/proc/ui_act_loc_lock(datum/act/op/A)
	if(!ui_gate(A))
		return FALSE
	loc_lock = !loc_lock
	return TRUE

/datum/eventkit/mob_spawner/proc/ui_act_start_spawn(datum/act/op/A, amount, desc, flavor_text, health, max_health, melee_damage_lower, melee_damage_upper, name, size_multiplier, x, y, z)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(A.step_value("confirm") != "Yes")
		return TRUE
	return apply_spawn_choice(user, amount, desc, flavor_text, health, max_health, melee_damage_lower, melee_damage_upper, name, size_multiplier, x, y, z)

/datum/eventkit/mob_spawner/proc/apply_spawn_choice(mob/original_actor, spawn_amount, spawn_desc, spawn_flavor_text, spawn_health, spawn_max_health, spawn_melee_damage_lower, spawn_melee_damage_upper, spawn_name, spawn_size_multiplier, spawn_x, spawn_y, spawn_z)
	var/amount = spawn_amount
	var/name = spawn_name
	var/x = spawn_x
	var/y = spawn_y
	var/z = spawn_z

	if(!name)
		to_chat(original_actor, span_warning("Name cannot be empty."))
		return FALSE

	var/turf/T = locate(x, y, z)
	if(!T)
		to_chat(original_actor, span_warning("Those coordinates are outside the boundaries of the map."))
		return FALSE

	for(var/i = 0, i < amount, i++)
		if(ispath(path,/turf))
			var/turf/TU = get_turf(locate(x, y, z))
			TU.ChangeTurf(path)
		else
			var/mob/M = new path(original_actor.loc)

			M.name = sanitize(name)
			M.desc = sanitize(spawn_desc)
			M.flavor_text = sanitize(spawn_flavor_text)
			if(isliving(M))
				var/mob/living/L = M
				if(isnum(spawn_max_health) && spawn_max_health > 0)
					L.endurance = spawn_max_health
				if(isnum(spawn_health))
					var/starting_injury = L.get_endurance() - spawn_health
					if(starting_injury > 0)
						L.injure(INJURY_BLUNT, starting_injury, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
				if(isanimal(M))
					var/mob/living/simple_mob/S = L
					if(isnum(spawn_melee_damage_lower))
						S.melee_damage_lower = spawn_melee_damage_lower
					if(isnum(spawn_melee_damage_upper))
						S.melee_damage_upper = spawn_melee_damage_upper
				if(use_custom_ai)
					L.faction = faction
					L.set_use_stance(intent)
					L.initialize_ai_brain()
					L.status_adjust(STAT_SLEEPING, -100)
				else
					to_chat(original_actor, span_notice("You can only set AI for subtypes of mob/living!"))

			var/size_mul = spawn_size_multiplier
			if(isnum(size_mul))
				if(isliving(M))
					var/mob/living/L = M
					L.resize(size_mul, animate = FALSE, uncapped = TRUE, ignore_prefs = TRUE)
				else
					M.size_multiplier = size_mul
			else
				to_chat(original_actor, span_warning("Size Multiplier not applied: ([size_mul]) is not a valid input."))

			M.forceMove(T)

	log_and_message_admins("spawned [path] ([name]) at ([x],[y],[z]) [amount] times.", original_actor)

	return TRUE

/datum/eventkit/mob_spawner/tgui_close(mob/user)
	. = ..()
	if(!QDELETED(src))
		spent(src, user)

ADMIN_VERB(eventkit_open_mob_spawner, R_SPAWN, "Open Mob Spawner", "Opens an advanced version of the mob spawner.", ADMIN_CATEGORY_FUN_EVENT_KIT)
	var/datum/eventkit/mob_spawner/spawner = new()
	spawner.tgui_interact(user.mob)

/datum/eventkit/mob_spawner/proc/mob_paths(datum/act/op/A)
	return typesof(/mob)

/datum/eventkit/mob_spawner/proc/faction_default(datum/act/op/A)
	return faction ? faction : "neutral"

/datum/eventkit/mob_spawner/proc/intent_default(datum/act/op/A)
	return intent ? intent : I_HELP

/datum/eventkit/mob_spawner/proc/apply_spawner_setting(setting_action, value)
	switch(setting_action)
		if("select_path")
			path = value
			new_path = TRUE
		if("set_faction")
			faction = value
		if("set_intent")
			intent = value

/datum/prompt/choice/mob_spawner_setting
	timeout = 0

/datum/prompt/choice/mob_spawner_setting/path
	question = "Please select the new path of the mob you want to spawn."

/datum/prompt/choice/mob_spawner_setting/intent
	question = "Please select preferred intent"
	title = "Select Intent"
	choices = list(I_HELP, I_HURT)

/datum/prompt/text/mob_spawner_faction
	question = "Please input your mobs' faction"
	title = "Faction"
	timeout = 0

/datum/prompt/text/mob_spawner_faction/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/mob_spawner_spawn
	question = "Are you sure that you want to start spawning your custom mobs?"
	title = "Confirmation"
	choices = list("Yes", "Cancel")
	buttons = TRUE
	timeout = 0

