/*	Note from Carnie:
		The way datum/mind stuff works has been changed a lot.
		Minds now represent IC characters rather than following a client around constantly.
	Guidelines for using minds properly:
	-	Never mind.transfer_to(ghost). The var/current and var/original_character of a mind must always be of type mob/living!
		ghost.mind is however used as a reference to the ghost's corpse
	-	When creating a new mob for an existing IC character (e.g. cloning a dead guy or borging a brain of a human)
		the existing mind of the old mob should be transfered to the new mob like so:
			mind.transfer_to(new_mob)
	-	You must not assign key= or ckey= after transfer_to() since the transfer_to transfers the client for you.
		By setting key or ckey explicitly after transfering the mind with transfer_to you will cause bugs like DCing
		the player.
	-	IMPORTANT NOTE 2, if you want a player to become a ghost, use mob.ghostize() It does all the hard work for you.
	-	When creating a new mob which will be a new IC character (e.g. putting a shade in a construct or randomly selecting
		a ghost to become a xeno during an event). Simply assign the key or ckey like you've always done.
			new_mob.key = key
		The Login proc will handle making a new mob for that mobtype (including setting up stuff like mind.name). Simple!
		However if you want that mind to have any special properties like being a traitor etc you will have to do that
		yourself.
*/

/datum/mind
	var/key
	var/name				//replaces mob/var/original_name
	var/mob/living/current
	var/original_character //replaces /mob/living/original
	var/active = 0

	var/memory

	var/assigned_role
	var/special_role

	var/datum/antag_holder/antag_holder

	var/role_alt_title


	var/list/datum/objective/objectives = list() // ALLOW(instance_list): d: mind objectives; many call sites index it
	var/list/special_verbs // verb paths

	var/has_been_rev = 0//Tracks if this mind has been a rev or not


	var/rev_cooldown = 0
	var/tcrystals = 0
	var/list/purchase_log
	var/used_TC = 0

	var/list/learned_recipes //List of learned recipe TYPES.

	// the world.time since the mob has been brigged, or -1 if not at all
	EXPIRY_DECLARE(brigged_since)
	brigged_since = -1

	//put this here for easier tracking ingame
	var/initial_account_handle

	//used for antag tcrystal trading, more info in code\game\objects\items\telecrystals.dm
	var/accept_tcrystals = 0

	//used for optional self-objectives that antagonists can give themselves, which are displayed at the end of the round.
	var/ambitions

	var/datum/religion/my_religion

/datum/mind/New(key)
	src.key = key
	purchase_log = list()
	antag_holder = new
	..()

/// Low level: link this mind to `new_character`. Use transfer_mind() (or
/// move_player_mind()), which logs. `share_identity` has the body wear the
/// mind's identity without syncing its vars from it (temporary control).
/datum/mind/proc/transfer_to(mob/living/new_character, force = FALSE, share_identity = FALSE)
	if(!istype(new_character))
		log_world("## DEBUG: transfer_to(): Some idiot has tried to transfer_to() a non mob/living mob. Please inform Carn")
	// The identity follows the mind: adopt the old body's if the mind has none
	// yet, else the new body's (a brand-new character).
	var/datum/character_identity/carried_identity = get_identity()
	if(!carried_identity && isliving(new_character))
		carried_identity = new_character.identity()
	identity = carried_identity
	var/datum/changeling/changeling_comp
	var/mob/living/old_character = current
	if(current)
		changeling_comp = is_changeling(current)			//remove ourself from our old body's mind variable
		if(changeling_comp)
			current.remove_changeling_powers()
			remove_verb(current, /mob/proc/EvolutionMenu)
		current.mind = null

	if(new_character.mind)		//remove any mind currently in our new body's mind variable
		new_character.mind.current = null

	current = new_character		//link ourself to our new body
	new_character.mind = src	//and link our new body to ourself
	if(isliving(new_character))
		if(share_identity)
			new_character.share_identity(identity)
		else
			new_character.bind_identity(identity)
	if(old_character)
		OM_EMIT(old_character, /datum/om/event/mob_mind_transferred_out_of, new_character)
	OM_EMIT(new_character, /datum/om/event/mob_mind_transferred_into, old_character)

	// Handle mode/antag specific respawns
	if(changeling_comp)
		new_character.make_changeling()

	if(learned_spells)
		for(var/datum/spell/spell_to_add in learned_spells)
			new_character.add_spell(spell_to_add)

	if(active || force)
		new_character.key = key		//now transfer the key to link the client to our new body

	if(new_character.client)
		new_character.client.init_verbs() // re-initialize character specific verbs

	GLOB.antag_service.update_antag_icons(src)

/datum/mind/proc/store_memory(new_text)
	memory += "[new_text]<BR>"

// show_memory body relocated to code/modules/admin/misc_admin_panels.dm (structured TGUI). Stub here keeps the proc declaration parseable.
/datum/mind/proc/show_memory(mob/recipient)
	return  // body provided by modular override

/datum/mind/proc/edit_memory(mob/user)
	if(!SSticker || !SSticker.mode)
		tgui_alert_async(user, "Not before round-start!", "Alert")
		return
	// fully structured TGUI panel; see
	// code/modules/admin/edit_memory_panel.dm.
	if(!tgui_edit_memory_panel)
		tgui_edit_memory_panel = new(src, user)
	tgui_edit_memory_panel.tgui_interact(user)

/datum/mind/Topic(href, href_list)
	if(!check_rights(R_ADMIN|R_FUN|R_EVENT))
		return

	if(href_list["add_antagonist"])
		var/datum/antagonist/antag = GLOB.antag_service.all_antag_types[href_list["add_antagonist"]]
		if(antag)
			if(antag.add_antagonist(src, 1, 1, 0, 1, 1)) // Ignore equipment and role type for this.
				log_admin("[key_name_admin(usr)] made [key_name(src)] into a [antag.role_text].")
			else
				to_chat(usr, span_warning("[src] could not be made into a [antag.role_text]!"))

	else if(href_list["remove_antagonist"])
		var/datum/antagonist/antag = GLOB.antag_service.all_antag_types[href_list["remove_antagonist"]]
		if(antag) antag.remove_antagonist(src)

	else if(href_list["equip_antagonist"])
		var/datum/antagonist/antag = GLOB.antag_service.all_antag_types[href_list["equip_antagonist"]]
		if(antag) antag.equip(src.current)

	else if(href_list["unequip_antagonist"])
		var/datum/antagonist/antag = GLOB.antag_service.all_antag_types[href_list["unequip_antagonist"]]
		if(antag) antag.unequip(src.current)

	else if(href_list["move_antag_to_spawn"])
		var/datum/antagonist/antag = GLOB.antag_service.all_antag_types[href_list["move_antag_to_spawn"]]
		if(antag) antag.place_mob(src.current)

	else if (href_list["role_edit"])
		om_ask(usr, /datum/om/prompt/choice, PROC_REF(role_edited), title = "Assigned role", message = "Select new role", default = assigned_role, choices = SSjob.occupations_by_name, requires = PROMPT_ADMIN(R_ADMIN))

	else if (href_list["memory_edit"])
		om_ask(usr, /datum/om/prompt/text/mind_edit, PROC_REF(memory_edited), message = "Write new memory", default = memory)


	else if (href_list["amb_edit"])
		var/datum/mind/mind = locate(href_list["amb_edit"])
		if(!mind)
			return
		om_ask(usr, /datum/om/prompt/text/mind_edit, PROC_REF(ambition_edited), message = "Enter a new ambition", default = mind.ambitions, edited = mind)

	else if (href_list["obj_edit"] || href_list["obj_add"])
		var/datum/objective/objective
		var/objective_pos
		var/def_value

		if (href_list["obj_edit"])
			objective = locate(href_list["obj_edit"])
			if (!objective) return
			objective_pos = objectives.Find(objective)

			//Text strings are easy to manipulate. Revised for simplicity.
			var/temp_obj_type = "[objective.type]"//Convert path into a text string.
			def_value = copytext(temp_obj_type, 19)//Convert last part of path into an objective keyword.
			if(!def_value)//If it's a custom objective, it will be an empty string.
				def_value = "custom"

		var/list/choices = list("assassinate", "debrain", "protect", "prevent", "harm", "brig", "hijack", "escape", "survive", "steal", "mercenary", "capture", "absorb", "custom")
		om_flow_start(/datum/om/flow/mind_objective_edit, usr, null, mind = src, objective = objective, pos = objective_pos, choices = choices, def_value = def_value)

	else if (href_list["obj_delete"])
		var/datum/objective/objective = locate(href_list["obj_delete"])
		if(!istype(objective))	return
		objectives -= objective

	else if(href_list["obj_completed"])
		var/datum/objective/objective = locate(href_list["obj_completed"])
		if(!istype(objective))	return
		objective.completed = !objective.completed

	else if(href_list["implant"])
		var/mob/living/carbon/human/H = current

		BITSET(H.hud_updateflag, IMPLOYAL_HUD)   // updates that players HUD images so secHUD's pick up they are implanted or not.

		switch(href_list["implant"])
			if("remove")
				for(var/obj/item/implant/loyalty/I in contents_of(H))
					for(var/obj/item/organ/external/organs in H.organs)
						if(I in organs.implants)
							qdel(I)
							break
				to_chat(H, span_notice(span_large(span_bold("Your loyalty implant has been deactivated."))))
				log_admin("[key_name_admin(usr)] has de-loyalty implanted [current].")
			if("add")
				to_chat(H, span_danger(span_large("You somehow have become the recepient of a loyalty transplant, and it just activated!")))
				H.implant_loyalty(TRUE)
				log_admin("[key_name_admin(usr)] has loyalty implanted [current].")

	else if (href_list["silicon"])
		BITSET(current.hud_updateflag, SPECIALROLE_HUD)
		switch(href_list["silicon"])

			if("unemag")
				var/mob/living/silicon/robot/R = current
				if (istype(R))
					R.emagged = 0
					if (R.activated(R.module.emag))
						R.module_active = null
					var/emag_slot = R.module_slot_of(R.module.emag)
					if(emag_slot)
						R.clear_module_slot(emag_slot)
					log_admin("[key_name_admin(usr)] has unemag'ed [R].")

			if("unemagcyborgs")
				if (isAI(current))
					var/mob/living/silicon/ai/ai = current
					for (var/mob/living/silicon/robot/R in ai.connected_robots)
						R.emagged = 0
						if (R.module)
							if (R.activated(R.module.emag))
								R.module_active = null
							var/emag_slot = R.module_slot_of(R.module.emag)
							if(emag_slot)
								R.clear_module_slot(emag_slot)
					log_admin("[key_name_admin(usr)] has unemag'ed [ai]'s Cyborgs.")

	else if (href_list["common"])
		switch(href_list["common"])
			if("undress")
				for(var/obj/item/W in current)
					current.drop_from_inventory(W)
			if("takeuplink")
				take_uplink()
				memory = null//Remove any memory they may have had.
			if("crystals")
				if (check_rights_for(usr.client, R_FUN))
					om_ask(usr, /datum/om/prompt/number, PROC_REF(telecrystals_set), message = "Amount of telecrystals for [key]", default = tcrystals, requires = PROMPT_ADMIN(R_FUN))

	else if (href_list["obj_announce"])
		var/obj_count = 1
		to_chat(current, span_blue("Your current objectives:"))
		for(var/datum/objective/objective in objectives)
			to_chat(current, span_bold("Objective #[obj_count]") + ": [objective.explanation_text]")
			obj_count++
	edit_memory(usr)

/datum/om/prompt/text/mind_edit
	title = "Memory"
	multiline = TRUE
	requires = PROMPT_ADMIN(R_ADMIN)
	/// The mind whose ambitions are edited.
	var/datum/mind/edited

/datum/mind/proc/role_edited(datum/om/prompt/choice/ask)
	assigned_role = ask.choice
	edit_memory(ask.answerer)

/datum/mind/proc/memory_edited(datum/om/prompt/text/mind_edit/ask)
	memory = ask.text
	edit_memory(ask.answerer)

/datum/mind/proc/ambition_edited(datum/om/prompt/text/mind_edit/ask)
	var/datum/mind/mind = ask.edited
	mind.ambitions = ask.text
	to_chat(mind.current, span_warning("Your ambitions have been changed by higher powers, they are now: [mind.ambitions]"))
	log_and_message_admins("made [key_name(mind.current)]'s ambitions be '[mind.ambitions]'.")

/// The admin objective editor: the type, then a detail that depends on it (a target, a number,
/// a text, an item to steal; a custom steal asks its type and name too), then the edit.
/datum/om/flow/mind_objective_edit
	requires = PROMPT_ADMIN(R_ADMIN)
	var/datum/mind/mind
	var/datum/objective/objective
	var/pos
	var/list/choices
	var/def_value
	var/obj_type
	var/detail
	var/steal_type
	var/steal_name

/datum/om/flow/mind_objective_edit/start()
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(type_chosen), title = "Objective type", message = "Select objective type:", choices = choices, default = def_value)

/// The second question, which depends on the objective type.
/datum/om/flow/mind_objective_edit/proc/type_chosen(datum/om/prompt/choice/ask)
	obj_type = ask.choice
	switch(obj_type)
		if("assassinate","protect","debrain", "harm", "brig")
			var/list/possible_targets = list("Free objective")
			for(var/datum/mind/possible_target in SSticker.minds)
				if ((possible_target != mind) && ishuman(possible_target.current))
					possible_targets += possible_target.current
			var/mob/def_target = null
			var/objective_list[] = list(/datum/objective/assassinate, /datum/objective/protect, /datum/objective/debrain)
			if (objective&&(objective.type in objective_list) && objective.target)
				def_target = objective.target.current
			om_ask(actor, /datum/om/prompt/choice, PROC_REF(detail_chosen), title = "Objective target", message = "Select target:", choices = possible_targets, default = def_target)
		if("capture","absorb", "vore")
			var/def_num
			if(objective&&objective.type==text2path("/datum/objective/[obj_type]"))
				def_num = objective.target_amount
			om_ask(actor, /datum/om/prompt/number, PROC_REF(detail_entered), title = "Objective", message = "Input target number:", default = def_num)
		if("custom")
			om_ask(actor, /datum/om/prompt/text, PROC_REF(detail_written), title = "Objective", message = "Custom objective:", default = objective ? objective.explanation_text : "")
		if("steal")
			var/datum/objective/steal/S = new
			var/list/possible_items_all = S.possible_items + S.possible_items_special + "custom"
			qdel(S)
			om_ask(actor, /datum/om/prompt/choice, PROC_REF(detail_chosen), title = "Objective target", message = "Select target:", choices = possible_items_all)
		else
			finish()

/datum/om/flow/mind_objective_edit/proc/detail_chosen(datum/om/prompt/choice/ask)
	detail = ask.choice
	if(obj_type == "steal" && detail == "custom")
		om_ask(actor, /datum/om/prompt/choice, PROC_REF(steal_type_chosen), title = "Type", message = "Select type:", choices = typesof(/obj/item))
		return
	finish()

/datum/om/flow/mind_objective_edit/proc/detail_entered(datum/om/prompt/number/ask)
	detail = ask.number
	finish()

/datum/om/flow/mind_objective_edit/proc/detail_written(datum/om/prompt/text/ask)
	detail = ask.text
	finish()

/datum/om/flow/mind_objective_edit/proc/steal_type_chosen(datum/om/prompt/choice/ask)
	steal_type = ask.choice
	var/obj/item/custom_target = steal_type
	if(!custom_target)
		finish()
		return
	om_ask(actor, /datum/om/prompt/text, PROC_REF(steal_name_entered), title = "Objective target", message = "Enter target name:", default = initial(custom_target.name))

/datum/om/flow/mind_objective_edit/proc/steal_name_entered(datum/om/prompt/text/ask)
	steal_name = ask.text
	finish()

/datum/om/flow/mind_objective_edit/proc/finish()
	mind.objective_edit_apply(actor, src)
	mind.edit_memory(actor)

/datum/mind/proc/objective_edit_apply(mob/user, datum/om/flow/mind_objective_edit/edit)
	var/datum/objective/objective = edit.objective
	var/objective_pos = edit.pos
	var/new_obj_type = edit.obj_type
	var/datum/objective/new_objective = null

	switch (new_obj_type)
		if ("assassinate","protect","debrain", "harm", "brig")
			//To determine what to name the objective in explanation text.
			var/objective_type_capital = uppertext(copytext(new_obj_type, 1,2))//Capitalize first letter.
			var/objective_type_text = copytext(new_obj_type, 2)//Leave the rest of the text.
			var/objective_type = "[objective_type_capital][objective_type_text]"//Add them together into a text string.

			var/new_target = edit.detail
			if (!new_target) return

			var/objective_path = text2path("/datum/objective/[new_obj_type]")
			var/mob/living/M = new_target
			if (!istype(M) || !M.mind || new_target == "Free objective")
				new_objective = new objective_path
				new_objective.owner = src
				new_objective:target = null
				new_objective.explanation_text = "Free objective"
			else
				new_objective = new objective_path
				new_objective.owner = src
				new_objective:target = M.mind
				new_objective.explanation_text = "[objective_type] [M.real_name], the [M.mind.special_role ? M.mind:special_role : M.mind:assigned_role]."

		if ("prevent")
			new_objective = new /datum/objective/block
			new_objective.owner = src

		if ("hijack")
			new_objective = new /datum/objective/hijack
			new_objective.owner = src

		if ("escape")
			new_objective = new /datum/objective/escape
			new_objective.owner = src

		if ("survive")
			new_objective = new /datum/objective/survive
			new_objective.owner = src

		if ("mercenary")
			new_objective = new /datum/objective/nuclear
			new_objective.owner = src

		if ("steal")
			if (!istype(objective, /datum/objective/steal))
				new_objective = new /datum/objective/steal
				new_objective.owner = src
			else
				new_objective = objective
			var/datum/objective/steal/steal = new_objective
			if (!steal.apply_steal_choice(edit.detail, edit.steal_type, edit.steal_name))
				return

		if("capture","absorb", "vore")
			var/target_number = edit.detail
			if (isnull(target_number))//Ordinarily, you wouldn't need isnull. In this case, the value may already exist.
				return

			switch(new_obj_type)
				if("capture")
					new_objective = new /datum/objective/capture
					new_objective.explanation_text = "Accumulate [target_number] capture points."
				if("absorb")
					new_objective = new /datum/objective/absorb
					new_objective.explanation_text = "Absorb [target_number] compatible genomes."
				if("vore")
					new_objective = new /datum/objective/vore
					new_objective.explanation_text = "Devour [target_number] [target_number == 1 ? "person" : "people"]. What happens to them after you do that is irrelevant."
			new_objective.owner = src
			new_objective.target_amount = target_number

		if ("custom")
			var/expl = edit.detail
			if (!expl) return
			new_objective = new /datum/objective
			new_objective.owner = src
			new_objective.explanation_text = expl

	if (!new_objective) return

	if (objective)
		objectives -= objective
		objectives.Insert(objective_pos, new_objective)
	else
		objectives += new_objective

/datum/mind/proc/telecrystals_set(datum/om/prompt/number/ask)
	tcrystals = ask.number
	edit_memory(ask.answerer)

/datum/mind/proc/find_syndicate_uplink()
	var/list/L = current.get_contents()
	for (var/obj/item/I in L)
		if (item_hidden_uplink(I))
			return item_hidden_uplink(I)
	return null

/datum/mind/proc/take_uplink()
	var/obj/item/uplink/hidden/H = find_syndicate_uplink()
	if(H)
		qdel(H)

// check whether this mind's mob has been brigged for the given duration
// have to call this periodically for the duration to work properly
/datum/mind/proc/is_brigged(duration)
	var/turf/T = current.loc
	if(!istype(T))
		brigged_since = -1
		return 0
	var/is_currently_brigged = 0
	if(istype(T.loc,/area/security/brig))
		is_currently_brigged = 1
		for(var/obj/item/card/id/card in current)
			is_currently_brigged = 0
			break // if they still have ID they're not brigged
		for(var/obj/item/pda/P in current)
			if(P.id)
				is_currently_brigged = 0
				break // if they still have ID they're not brigged

	if(!is_currently_brigged)
		brigged_since = -1
		return 0

	if(brigged_since == -1)
		EXPIRY_STAMP(src, brigged_since, CLOCK_WORLD)

	return (duration <= ELAPSED(src, brigged_since, CLOCK_WORLD))

/datum/mind/proc/reset()
	assigned_role =   null
	special_role =    null
	role_alt_title =  null
	//changeling =    null //TODO: Figure out where this is all used and move it from mind to mob.
	initial_account_handle = null
	objectives =      list()
	special_verbs =   list()
	has_been_rev =    0
	rev_cooldown =    0
	brigged_since =   -1

//Antagonist role check
/mob/living/proc/check_special_role(role)
	if(mind)
		if(!role)
			return mind.special_role
		else
			return (mind.special_role == role) ? 1 : 0
	else
		return 0

/datum/mind/proc/get_ghost(even_if_they_cant_reenter)
	for(var/mob/observer/dead/G in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(G.mind == src)
			if(G.can_reenter_corpse || even_if_they_cant_reenter)
				return G
			break

///Proc that FORCIBLY grabs a client no matter where they are and returns their currently inhabited mob.
/datum/mind/proc/forcibly_grab_client()
	for(var/mob/mob_to_grab in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(mob_to_grab.ckey == loaded_from_ckey)
			return mob_to_grab

/datum/mind/proc/grab_ghost(force)
	var/mob/observer/dead/G = get_ghost(even_if_they_cant_reenter = force)
	. = G
	if(G)
		G.reenter_corpse()

//Initialisation procs
/mob/living/proc/mind_initialize()
	if(mind)
		mind.key = key
	else
		mind = new /datum/mind(key)
		mind.original_character = om_handle(src)
		if(SSticker)
			SSticker.minds += mind
		else
			log_world("## DEBUG: mind_initialize(): No ticker ready yet! Please inform Carn")
	if(!mind.name)	mind.name = real_name
	mind.current = src
	if(mind.identity)
		bind_identity(mind.identity)
	else
		mind.identity = identity()
	if(GLOB.antag_service.player_is_antag(mind))
		add_verb(src.client, /client/proc/aooc)
	if (client?.prefs)
		// directory tags migrated from legacy /datum/preferences vars
		// to /datum/preference subtypes.
		mind.show_in_directory = client.prefs.read_preference(/datum/preference/toggle/human/show_in_directory)
		mind.directory_tag = client.prefs.read_preference(/datum/preference/choiced/human/directory_tag)
		mind.directory_erptag = client.prefs.read_preference(/datum/preference/choiced/human/directory_erptag)
		mind.directory_ad = client.prefs.read_preference(/datum/preference/text/human/directory_ad)
		mind.vantag_preference = client.prefs.read_preference(/datum/preference/choiced/human/vantag_preference)
		mind.directory_gendertag = client.prefs.read_preference(/datum/preference/choiced/human/directory_gendertag)
		mind.directory_sexualitytag = client.prefs.read_preference(/datum/preference/choiced/human/directory_sexualitytag)

//HUMAN
/mob/living/carbon/human/mind_initialize()
	. = ..()
	if(!mind.assigned_role)
		mind.assigned_role = JOB_ALT_VISITOR // defualt // Visitor not Assistant

//slime
/mob/living/simple_mob/slime/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_SLIME

/mob/living/carbon/alien/larva/mind_initialize()
	. = ..()
	mind.special_role = JOB_LARVA

//AI
/mob/living/silicon/ai/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_AI

//BORG
/mob/living/silicon/robot/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_CYBORG

//PAI
/mob/living/silicon/pai/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_PAI
	mind.special_role = ""

//Animals
/mob/living/simple_mob/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_SIMPLE_MOB

/mob/living/simple_mob/animal/passive/dog/corgi/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_CORGI

/mob/living/simple_mob/construct/shade/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_SHADE
	mind.special_role = JOB_CULTIST

/mob/living/simple_mob/construct/artificer/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_ARTIFICER
	mind.special_role = JOB_CULTIST

/mob/living/simple_mob/construct/wraith/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_WRAITH
	mind.special_role = JOB_CULTIST

/mob/living/simple_mob/construct/juggernaut/mind_initialize()
	. = ..()
	mind.assigned_role = JOB_JUGGERNAUT
	mind.special_role = JOB_CULTIST

/datum/mind
	var/vore_death = FALSE	// Was our last gasp a gurgle?
	var/show_in_directory
	var/directory_tag
	var/directory_erptag
	var/directory_ad
	var/vore_prey_eaten = 0
	var/vantag_preference = VANTAG_NONE
	var/directory_gendertag
	var/directory_sexualitytag


/// LC-refs: the character's bank account -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/mind/proc/initial_account() as /datum/money_account
	return om_resolve(initial_account_handle)

DECLARE_REF(/datum/mind, "antag_holder", OWNED, null)
DECLARE_REF(/datum/mind, "my_religion", OWNED, null)

DECLARE_REF(/datum/mind, "objectives", OWNED_LIST, null)

DECLARE_REF(/datum/mind, "current", BACK, "mind")
