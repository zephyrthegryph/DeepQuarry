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
	var/mob/living/original_character //replaces /mob/living/original (a relation view)
	var/active = 0

	var/memory

	var/assigned_role
	var/special_role

	var/datum/antag_holder/antag_holder

	var/role_alt_title


	/// Objectives this mind owns (created for it; deleted with it).
	var/list/datum/objective/objectives = list() // ALLOW(instance_list): d: mind objectives; many call sites index it
	/// An antagonist's global objectives this mind shares (owned by the antagonist; a relation view).
	var/list/datum/objective/shared_objectives
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
	var/datum/money_account/initial_account

	//used for antag tcrystal trading, more info in code\game\objects\items\telecrystals.dm
	var/accept_tcrystals = 0

	//used for optional self-objectives that antagonists can give themselves, which are displayed at the end of the round.
	var/ambitions

	var/datum/religion/my_religion

CAPABILITIES(/datum/mind)
	ref_many(nameof(shared_objectives))
	owns_one(nameof(antag_holder), /datum/antag_holder)
	owns_one(nameof(identity), /datum/character_identity)
	owns_one(nameof(my_religion), /datum/religion)
	owns_one(nameof(tgui_edit_memory_panel), /datum/edit_memory_panel)
	owns_many(nameof(objectives), /datum/objective)

/datum/mind/New(key)
	src.key = key
	purchase_log = list()
	rel_set(src, nameof(antag_holder), new /datum/antag_holder)
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
	rel_set(src, nameof(identity), carried_identity)
	var/datum/changeling/changeling_comp
	var/mob/living/old_character = current
	if(current)
		changeling_comp = is_changeling(current)			//remove ourself from our old body's mind variable
		if(changeling_comp)
			current.remove_changeling_powers()
			revoke(current, granted_verb(/mob/proc/EvolutionMenu), changeling_comp)
		rel_clear(current, nameof(current.mind))

	if(new_character.mind)		//remove any mind currently in our new body's mind variable
		rel_clear(new_character.mind, nameof(/datum/forms::current))

	rel_set(src, nameof(current), new_character) //link ourself to our new body
	rel_set(new_character, nameof(new_character.mind), src) //and link our new body to ourself
	if(isliving(new_character))
		if(share_identity)
			new_character.share_identity(identity)
		else
			new_character.bind_identity(identity)
	if(old_character)
		PUBLISH_LEGACY(old_character, /datum/notice/mob_mind_transferred_out_of, new_character)
	PUBLISH_LEGACY(new_character, /datum/notice/mob_mind_transferred_into, old_character)

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

	SSantag.update_antag_icons(src)

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
		rel_set(src, nameof(tgui_edit_memory_panel), new /datum/edit_memory_panel(src, user))
	tgui_edit_memory_panel.tgui_interact(user)

// The traitor antag panel's "set crystals" link (/datum/antagonist/traitor/get_extra_panel_options()).
TOPIC_ACTION(/datum/mind, "common=crystals", PROC_REF(topic_set_crystals), TOPIC_RIGHTS(R_FUN))

/datum/mind/proc/topic_set_crystals(mob/user, list/args)
	open_request(src, /datum/prompt/number, PROC_REF(telecrystals_set), answerer = user, question = "Amount of telecrystals for [key]", default = tcrystals, rights = R_FUN, timeout = 0)
	edit_memory(user)
	return TRUE

/// Starts the admin add-objective questions for this mind.
/datum/mind/proc/begin_objective_add(mob/user)
	var/list/choices = list("assassinate", "debrain", "protect", "prevent", "harm", "brig", "hijack", "escape", "survive", "steal", "mercenary", "capture", "absorb", "custom")
	if(QDELETED(user))
		return
	open_request(src, /datum/prompt/choice/mind_objective_edit, PROC_REF(objective_type_chosen), answerer = user, title = "Objective type", question = "Select objective type:", choices = choices)

/datum/prompt/choice/mind_objective_edit
	rights = R_ADMIN
	timeout = 0
	var/obj_type
	recheck_on_open = TRUE

/datum/prompt/number/mind_objective_edit
	rights = R_ADMIN
	timeout = 0
	var/obj_type
	min_value = 0
	max_value = INFINITY
	step = 1
	recheck_on_open = TRUE

/datum/prompt/text/mind_objective_edit
	rights = R_ADMIN
	timeout = 0
	var/obj_type
	var/steal_type
	recheck_on_open = TRUE

/// The second question depends on the chosen objective type.
/datum/mind/proc/objective_type_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/obj_type = A.answer.value
	switch(obj_type)
		if("assassinate","protect","debrain", "harm", "brig")
			var/list/possible_targets = list("Free objective")
			for(var/datum/mind/possible_target in SSticker.minds)
				if ((possible_target != src) && ishuman(possible_target.current))
					possible_targets += possible_target.current
			open_request(src, /datum/prompt/choice/mind_objective_edit, PROC_REF(objective_detail_chosen), answerer = user, title = "Objective target", question = "Select target:", choices = possible_targets, obj_type = obj_type)
		if("capture","absorb", "vore")
			open_request(src, /datum/prompt/number/mind_objective_edit, PROC_REF(objective_detail_entered), answerer = user, title = "Objective", question = "Input target number:", obj_type = obj_type)
		if("custom")
			open_request(src, /datum/prompt/text/mind_objective_edit, PROC_REF(objective_detail_written), answerer = user, title = "Objective", question = "Custom objective:", default = "", obj_type = obj_type)
		if("steal")
			var/datum/objective/steal/S = new
			var/list/possible_items_all = S.possible_items + S.possible_items_special + "custom"
			spent(S)
			open_request(src, /datum/prompt/choice/mind_objective_edit, PROC_REF(objective_detail_chosen), answerer = user, title = "Objective target", question = "Select target:", choices = possible_items_all, obj_type = obj_type)
		else
			objective_edit_finished(user, obj_type)

/datum/mind/proc/objective_detail_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/mind_objective_edit/ask = A.answer
	var/detail = ask.value
	if(isdatum(detail))
		var/datum/selected = detail
		if(QDELETED(selected))
			return
	if(ask.obj_type == "steal" && detail == "custom")
		open_request(src, /datum/prompt/choice/mind_objective_edit, PROC_REF(objective_steal_type_chosen), answerer = ask.answerer, title = "Type", question = "Select type:", choices = typesof(/obj/item), obj_type = ask.obj_type)
		return
	objective_edit_finished(ask.answerer, ask.obj_type, detail)

/datum/mind/proc/objective_detail_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/mind_objective_edit/ask = A.answer
	objective_edit_finished(ask.answerer, ask.obj_type, ask.value)

/datum/mind/proc/objective_detail_written(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/mind_objective_edit/ask = A.answer
	objective_edit_finished(ask.answerer, ask.obj_type, ask.value)

/datum/mind/proc/objective_steal_type_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/mind_objective_edit/ask = A.answer
	var/steal_type = ask.value
	var/obj/item/custom_target = steal_type
	if(!custom_target)
		objective_edit_finished(ask.answerer, ask.obj_type, "custom", steal_type)
		return
	open_request(src, /datum/prompt/text/mind_objective_edit, PROC_REF(objective_steal_name_entered), answerer = ask.answerer, title = "Objective target", question = "Enter target name:", default = initial(custom_target.name), obj_type = ask.obj_type, steal_type = steal_type)

/datum/mind/proc/objective_steal_name_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/mind_objective_edit/ask = A.answer
	objective_edit_finished(ask.answerer, ask.obj_type, "custom", ask.steal_type, ask.value)

/datum/mind/proc/objective_edit_finished(mob/user, obj_type, detail = null, steal_type = null, steal_name = null)
	objective_edit_apply(user, obj_type, detail, steal_type, steal_name)
	edit_memory(user)

/datum/mind/proc/objective_edit_apply(mob/user, new_obj_type, detail = null, steal_type = null, steal_name = null, datum/objective/objective = null)
	var/datum/objective/new_objective = null

	switch (new_obj_type)
		if ("assassinate","protect","debrain", "harm", "brig")
			//To determine what to name the objective in explanation text.
			var/objective_type_capital = uppertext(copytext(new_obj_type, 1,2))//Capitalize first letter.
			var/objective_type_text = copytext(new_obj_type, 2)//Leave the rest of the text.
			var/objective_type = "[objective_type_capital][objective_type_text]"//Add them together into a text string.

			var/new_target = detail
			if (!new_target) return

			var/objective_path = text2path("/datum/objective/[new_obj_type]")
			var/mob/living/M = new_target
			if (!istype(M) || !M.mind || new_target == "Free objective")
				new_objective = new objective_path
				rel_set(new_objective, nameof(new_objective.owner), src)
				new_objective:target = null
				new_objective.explanation_text = "Free objective"
			else
				new_objective = new objective_path
				rel_set(new_objective, nameof(new_objective.owner), src)
				new_objective:target = M.mind
				new_objective.explanation_text = "[objective_type] [M.real_name], the [M.mind.special_role ? M.mind:special_role : M.mind:assigned_role]."

		if ("prevent")
			new_objective = new /datum/objective/block
			rel_set(new_objective, nameof(new_objective.owner), src)

		if ("hijack")
			new_objective = new /datum/objective/hijack
			rel_set(new_objective, nameof(new_objective.owner), src)

		if ("escape")
			new_objective = new /datum/objective/escape
			rel_set(new_objective, nameof(new_objective.owner), src)

		if ("survive")
			new_objective = new /datum/objective/survive
			rel_set(new_objective, nameof(new_objective.owner), src)

		if ("mercenary")
			new_objective = new /datum/objective/nuclear
			rel_set(new_objective, nameof(new_objective.owner), src)

		if ("steal")
			if (!istype(objective, /datum/objective/steal))
				new_objective = new /datum/objective/steal
				rel_set(new_objective, nameof(new_objective.owner), src)
			else
				new_objective = objective
			var/datum/objective/steal/steal = new_objective
			if (!steal.apply_steal_choice(detail, steal_type, steal_name))
				return

		if("capture","absorb", "vore")
			var/target_number = detail
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
			rel_set(new_objective, nameof(new_objective.owner), src)
			new_objective.target_amount = target_number

		if ("custom")
			var/expl = detail
			if (!expl) return
			new_objective = new /datum/objective
			rel_set(new_objective, nameof(new_objective.owner), src)
			new_objective.explanation_text = expl

	if (!new_objective) return

	// An edit replaces the old objective (deleted) with the new one at the end of the list.
	if (objective)
		rel_remove(src, nameof(objectives), objective)
	rel_add(src, nameof(objectives), new_objective)

/datum/mind/proc/telecrystals_set(datum/act/request/A)
	if(!A.answer)
		return
	tcrystals = A.answer.value
	edit_memory(A.request.answerer)

/datum/mind/proc/find_syndicate_uplink()
	var/list/L = current.get_contents()
	for (var/obj/item/I in L)
		if (item_hidden_uplink(I))
			return item_hidden_uplink(I)
	return null

/datum/mind/proc/take_uplink()
	var/obj/item/uplink/hidden/H = find_syndicate_uplink()
	if(H)
		spent(H)

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
	rel_clear(src, nameof(initial_account))
	rel_clear(src, nameof(objectives))
	rel_clear(src, nameof(shared_objectives))
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
		rel_set(src, nameof(mind), new /datum/mind(key))
		rel_set(mind, nameof(mind.original_character), src)
		if(SSticker)
			SSticker.minds += mind // ALLOW(ownership): the ticker's roster of minds, appended where the mind is created; no registry for minds yet
		else
			log_world("## DEBUG: mind_initialize(): No ticker ready yet! Please inform Carn")
	if(!mind.name)	mind.name = real_name
	rel_set(mind, nameof(mind.current), src)
	if(mind.identity)
		bind_identity(mind.identity)
	else
		rel_set(mind, nameof(mind.identity), identity())
	if(SSantag.player_is_antag(mind))
		grant(src.client, granted_verb(/client/proc/aooc), mind) // the mind grants its player aooc while it is an antag
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


/// The character's bank account (a relation view).
/datum/mind/proc/initial_account() as /datum/money_account
	return initial_account

/// Adopts `O` as one of this mind's objectives and points its owner view back here.
/datum/mind/proc/add_objective(datum/objective/O)
	rel_set(O, nameof(O.owner), src)
	return rel_add(src, nameof(objectives), O)

/// Every objective this mind pursues: its own, then the antagonist-wide ones it shares.
/datum/mind/proc/all_objectives()
	. = list()
	if(objectives)
		. += objectives
	if(shared_objectives)
		. += shared_objectives
