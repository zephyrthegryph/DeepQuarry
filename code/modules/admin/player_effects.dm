
ADMIN_VERB_AND_CONTEXT_MENU(player_effects, R_FUN, "Player Effects", "Modify a player character with various 'special treatments' from a list.", ADMIN_CATEGORY_FUN_EVENT_KIT, mob/target in get_mob_with_client_list())
	var/datum/eventkit/player_effects/spawner = new()
	rel_set(spawner, nameof(/datum/accessory_stat_modifier::target), target)
	spawner.tgui_interact(user.mob)

/datum/eventkit/player_effects
	var/tmp/mob/target	//The target of the effects

/datum/eventkit/player_effects/New()
	. = ..()

CAPABILITIES(/datum/eventkit/player_effects)
	interface("PlayerEffects", title = "Player Effects", rights = R_ADMIN|R_EVENT|R_DEBUG)
	ref_one(nameof(target), /mob)
	extend(TAG_UI, needs(req_rights(R_SPAWN)))
	extend(TAG_UI, then(PROC_REF(ui_log_use), early = TRUE))

	section(smites, "The pranks and smites of the Player Effects panel")
	op("break_legs", ui_act("break_legs"), then(PROC_REF(ui_act_break_legs)))
	op("bluespace_artillery", ui_act("bluespace_artillery"), then(PROC_REF(ui_act_bluespace_artillery)))
	op("spont_combustion", ui_act("spont_combustion"), then(PROC_REF(ui_act_spont_combustion)))
	op("lightning_strike", ui_act("lightning_strike"), then(PROC_REF(ui_act_lightning_strike)))
	op("shadekin_attack", ui_act("shadekin_attack"), then(PROC_REF(ui_act_shadekin_attack)))
	op("shadekin_vore", ui_act("shadekin_vore"), asks(/datum/prompt/choice, fields = list("title" = "Shadekin Type Choice", "question" = computed(PROC_REF(kin_question)), "choices" = computed(PROC_REF(kin_names))), step = "kin"), asks(/datum/prompt/choice, fields = list("title" = "Control Shadekin?", "question" = "Control the shadekin yourself or delete pred and prey after?", "choices" = list("Control", "Cancel", "Delete")), step = "control"), then(PROC_REF(ui_act_shadekin_vore)))
	op("redspace_abduct", ui_act("redspace_abduct"), then(PROC_REF(ui_act_redspace_abduct)))
	op("autosave", ui_act("autosave"), then(PROC_REF(ui_act_autosave)))
	op("autosave2", ui_act("autosave2"), then(PROC_REF(ui_act_autosave2)))
	op("adspam", ui_act("adspam"), then(PROC_REF(ui_act_adspam)))
	op("peppernade", ui_act("peppernade"), then(PROC_REF(ui_act_peppernade)))
	op("spicerequest", ui_act("spicerequest"), then(PROC_REF(ui_act_spicerequest)))
	op("terror", ui_act("terror"), then(PROC_REF(ui_act_terror)))
	op("terror_aoe", ui_act("terror_aoe"), then(PROC_REF(ui_act_terror_aoe)))
	op("spin", ui_act("spin"), asks(/datum/prompt/number, fields = list("title" = "Speed", "question" = "Spin speed (minimum 0.1):"), step = "speed"), asks(/datum/prompt/number, fields = list("title" = "Loops", "question" = "Number of loops (-1 for infinite):"), step = "loops", when = PROC_REF(spin_speed_ok)), asks(/datum/prompt/choice, fields = list("title" = "Direction", "question" = "Clockwise or Anti-Clockwise", "choices" = list("Clockwise", "Anti-Clockwise", "Cancel")), step = "direction", when = PROC_REF(spin_speed_ok)), then(PROC_REF(ui_act_spin)))
	op("squish", ui_act("squish"), then(PROC_REF(ui_act_squish)))
	op("pie_splat", ui_act("pie_splat"), then(PROC_REF(ui_act_pie_splat)))
	op("spicy_air", ui_act("spicy_air"), then(PROC_REF(ui_act_spicy_air)))
	op("hot_dog", ui_act("hot_dog"), then(PROC_REF(ui_act_hot_dog)))
	op("mob_tf", ui_act("mob_tf"), asks(/datum/prompt/choice, fields = list("title" = "Choose Beast Form", "question" = "Which form would you like to take?", "choices" = computed(PROC_REF(living_types)))), then(PROC_REF(ui_act_mob_tf)))
	op("item_tf", ui_act("item_tf"), needs(req(PROC_REF(item_tf_ready), silent = TRUE)), asks(/datum/prompt/text, fields = list("title" = "Typepath", "question" = "Enter full or partial typepath.", "max_len" = MAX_TGUI_INPUT), step = "path"), asks(/datum/prompt/choice, fields = list("title" = "Typepath", "question" = "Which one?", "choices" = computed(PROC_REF(typepath_matches))), step = "pick", when = PROC_REF(typepath_ambiguous)), then(PROC_REF(ui_act_item_tf)))
	op("elder_smite", ui_act("elder_smite"), then(PROC_REF(ui_act_elder_smite)))
	op("wet_floors", ui_act("wet_floors"), asks(/datum/prompt/choice, fields = list("title" = "Reagent", "question" = "Which reagent do you want to place on the floors around them?", "choices" = list("Water", "Space Lube", "Other", "Cancel")), step = "reagent"), asks(/datum/prompt/choice, fields = list("title" = "Chemicals", "question" = "Which chemical would you like to use?", "choices" = computed(PROC_REF(reagent_types))), step = "chem", when = PROC_REF(wet_floors_other)), then(PROC_REF(ui_act_wet_floors)))

	section(body, "What the Player Effects panel does to a body: scans, organs, bones, chemicals, medical issues")
	op("health_scan", ui_act("health_scan"), then(PROC_REF(ui_act_health_scan)))
	op("appendicitis", ui_act("appendicitis"), then(PROC_REF(ui_act_appendicitis)))
	op("damage_organ", ui_act("damage_organ"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Organs", "question" = "Choose an organ to damage:", "choices" = computed(PROC_REF(organ_choices))), step = "organ"), asks(/datum/prompt/choice, fields = list("title" = "Effect", "question" = "What do you want to do to the Organ", "choices" = list("Damage", "Kill", "Bruise", "Cancel")), step = "effect", when = PROC_REF(organ_chosen)), asks(/datum/prompt/number, fields = list("title" = "Damage", "question" = computed(PROC_REF(organ_damage_question))), step = "amount", when = PROC_REF(effect_is_damage)), then(PROC_REF(ui_act_damage_organ)))
	op("assist_organ", ui_act("assist_organ"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Organs", "question" = "Choose an organ to become assisted:", "choices" = computed(PROC_REF(organ_choices)))), then(PROC_REF(ui_act_assist_organ)))
	op("robot_organ", ui_act("robot_organ"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Organs", "question" = "Choose an organ to become robotic:", "choices" = computed(PROC_REF(organ_choices)))), then(PROC_REF(ui_act_robot_organ)))
	op("repair_organ", ui_act("repair_organ"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Organs", "question" = "Choose an organ to heal:", "choices" = computed(PROC_REF(organ_choices))), step = "organ"), asks(/datum/prompt/choice, fields = list("title" = "Effect", "question" = "What do you want to do to the Organ", "choices" = list("Heal", "Rejuvenate", "Cancel")), step = "effect", when = PROC_REF(organ_chosen)), asks(/datum/prompt/number, fields = list("title" = "Damage", "question" = computed(PROC_REF(organ_damage_question))), step = "amount", when = PROC_REF(effect_is_heal)), then(PROC_REF(ui_act_repair_organ)))
	op("drop_organ", ui_act("drop_organ"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Organs", "question" = "Choose an organ to damage:", "choices" = computed(PROC_REF(organ_choices)))), then(PROC_REF(ui_act_drop_organ)))
	op("break_bone", ui_act("break_bone"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Organs", "question" = "Choose an bone to break:", "choices" = computed(PROC_REF(bone_choices)))), then(PROC_REF(ui_act_break_bone)))
	op("stasis", ui_act("stasis"), then(PROC_REF(ui_act_stasis)))
	op("give_chem", ui_act("give_chem"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Chemicals", "question" = "Which chemical would you like to add?", "choices" = computed(PROC_REF(reagent_types))), step = "chem"), asks(/datum/prompt/number, fields = list("title" = "Amount", "question" = "How much of the chemical would you like to add?", "default" = 5), step = "amount", when = PROC_REF(chem_chosen)), asks(/datum/prompt/choice, fields = list("title" = "Location", "question" = "Where do you want to add the chemical?", "choices" = list("Blood", "Stomach", "Skin", "Cancel")), step = "location", when = PROC_REF(chem_chosen)), then(PROC_REF(ui_act_give_chem)))
	op("purge", ui_act("purge"), then(PROC_REF(ui_act_purge)))
	op("medical_issue", ui_act("medical_issue"), then(PROC_REF(ui_act_medical_issue)))
	op("clear_issue", ui_act("clear_issue"), then(PROC_REF(ui_act_clear_issue)))
	op("vent_crawl", ui_act("vent_crawl"), then(PROC_REF(ui_act_vent_crawl)))
	op("darksight", ui_act("darksight"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/number, fields = list("title" = "Darksight", "question" = computed(PROC_REF(darksight_question)))), then(PROC_REF(ui_act_darksight)))

	section(traits, "The abilities and traits the Player Effects panel toggles")
	op("cocoon", ui_act("cocoon"), then(PROC_REF(ui_act_cocoon)))
	op("transformation", ui_act("transformation"), then(PROC_REF(ui_act_transformation)))
	op("set_size", ui_act("set_size"), then(PROC_REF(ui_act_set_size)))
	op("lleill_energy", ui_act("lleill_energy"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/number, fields = list("title" = "Max energy", "question" = computed(PROC_REF(lleill_max_question))), step = "max"), asks(/datum/prompt/number, fields = list("title" = "Max energy", "question" = computed(PROC_REF(lleill_now_question))), step = "now"), then(PROC_REF(ui_act_lleill_energy)))
	op("lleill_invisibility", ui_act("lleill_invisibility"), then(PROC_REF(ui_act_lleill_invisibility)))
	op("beast_form", ui_act("beast_form"), then(PROC_REF(ui_act_beast_form)))
	op("lleill_transmute", ui_act("lleill_transmute"), then(PROC_REF(ui_act_lleill_transmute)))
	op("lleill_alchemy", ui_act("lleill_alchemy"), then(PROC_REF(ui_act_lleill_alchemy)))
	op("lleill_drain", ui_act("lleill_drain"), then(PROC_REF(ui_act_lleill_drain)))
	op("brutal_pred", ui_act("brutal_pred"), then(PROC_REF(ui_act_brutal_pred)))
	op("trash_eater", ui_act("trash_eater"), then(PROC_REF(ui_act_trash_eater)))
	op("active_cloaking", ui_act("active_cloaking"), then(PROC_REF(ui_act_active_cloaking)))
	op("colormate", ui_act("colormate"), then(PROC_REF(ui_act_colormate)))
	op("be_event_invis", ui_act("be_event_invis"), then(PROC_REF(ui_act_be_event_invis)))
	op("see_event_invis", ui_act("see_event_invis"), then(PROC_REF(ui_act_see_event_invis)))

	section(inventory, "The Player Effects panel's inventory tools: drop, list, give and equip items, a quick NIF")
	op("drop_all", ui_act("drop_all"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/yes_no, fields = list("title" = "Message", "question" = computed(PROC_REF(drop_all_question)))), then(PROC_REF(ui_act_drop_all)))
	op("drop_specific", ui_act("drop_specific"), needs(req(PROC_REF(target_human), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Drop Specific Item", "question" = "Choose item to force drop:", "choices" = computed(PROC_REF(equipped_choices)))), then(PROC_REF(ui_act_drop_specific)))
	op("drop_held", ui_act("drop_held"), then(PROC_REF(ui_act_drop_held)))
	op("list_all", ui_act("list_all"), then(PROC_REF(ui_act_list_all)))
	op("give_item", ui_act("give_item"), then(PROC_REF(ui_act_give_item)))
	op("equip_item", ui_act("equip_item"), then(PROC_REF(ui_act_equip_item)))
	op("quick_nif", ui_act("quick_nif"), needs(req(PROC_REF(nif_target_ok), because = PROC_REF(nif_target_refusal))), asks(/datum/prompt/choice, fields = list("title" = "Quick NIF", "question" = "Pick the NIF type", "choices" = computed(PROC_REF(nif_choices))), when = PROC_REF(nif_needs_pick)), then(PROC_REF(ui_act_quick_nif)))

	section(admin, "The admin tools of the Player Effects panel: size, teleport, gib, narrate, AI control, quests, orbits")
	op("resize", ui_act("resize"), then(PROC_REF(ui_act_resize)))
	op("teleport", ui_act("teleport"), asks(/datum/prompt/choice, fields = list("title" = "Where?", "question" = "Where to teleport?", "choices" = list("To Me", "To Mob", "To Area", "Cancel")), step = "where"), asks(/datum/prompt/choice, fields = list("title" = "Jump to mob", "question" = computed(PROC_REF(teleport_mob_question)), "choices" = computed(PROC_REF(teleport_mobs))), step = "mob", when = PROC_REF(teleport_to_mob)), asks(/datum/prompt/choice, fields = list("title" = "Jump to Area", "question" = computed(PROC_REF(teleport_area_question)), "choices" = computed(PROC_REF(teleport_areas))), step = "area", when = PROC_REF(teleport_to_area)), then(PROC_REF(ui_act_teleport)))
	op("gib", ui_act("gib"), then(PROC_REF(ui_act_gib)))
	op("dust", ui_act("dust"), then(PROC_REF(ui_act_dust)))
	op("paralyse", ui_act("paralyse"), then(PROC_REF(ui_act_paralyse)))
	op("subtle_message", ui_act("subtle_message"), then(PROC_REF(ui_act_subtle_message)))
	op("direct_narrate", ui_act("direct_narrate"), then(PROC_REF(ui_act_direct_narrate)))
	op("player_panel", ui_act("player_panel"), then(PROC_REF(ui_act_player_panel)))
	op("view_variables", ui_act("view_variables"), then(PROC_REF(ui_act_view_variables)))
	op("orbit", ui_act("orbit"), then(PROC_REF(ui_act_orbit)))
	op("ai", ui_act("ai"), needs(req(PROC_REF(ai_target_ok), because = PROC_REF(ai_target_refusal))), asks(/datum/prompt/text, fields = list("title" = "AI faction", "question" = "Please input AI faction", "default" = "neutral"), step = "faction"), asks(/datum/prompt/choice, fields = list("title" = "AI combat mode", "question" = "Please choose AI combat mode", "choices" = list(I_HURT, I_HELP)), step = "stance"), asks(/datum/prompt/yes_no, fields = list("title" = "Wake mob?", "question" = "Make mob wake up? This is needed for carbon mobs."), step = "wake"), then(PROC_REF(ui_act_ai)))
	op("cloaking", ui_act("cloaking"), then(PROC_REF(ui_act_cloaking)))
	op("give_quest", ui_act("give_quest"), needs(req(PROC_REF(has_target), silent = TRUE)), asks(/datum/prompt/choice, fields = list("title" = "Quest!", "question" = "Do you want to give a random quest or a personalised one?", "choices" = list("Random", "Personalised", "Cancel")), step = "kind"), asks(/datum/prompt/text, fields = list("title" = "Quest!!!", "question" = "What is their quest?"), step = "quest", when = PROC_REF(quest_personalised)), then(PROC_REF(ui_act_give_quest)))
	op("rejuvenate", ui_act("rejuvenate"), then(PROC_REF(ui_act_rejuvenate)))
	op("popup-box", ui_act("popup-box"), then(PROC_REF(ui_act_popup_box)))
	op("stop-orbits", ui_act("stop-orbits"), then(PROC_REF(ui_act_stop_orbits)))
	op("revert-mob-tf", ui_act("revert-mob-tf"), then(PROC_REF(ui_act_revert_mob_tf)))

/datum/eventkit/player_effects/tgui_static_data(mob/user)
	var/list/data = list()

	data["real_name"] = target().name;
	data["player_ckey"] = target().ckey;
	data["target_mob"] = target();

	return data

/datum/prompt/text/admin_popup
	title = "Reply"
	timeout = 0
	/// key_name() of the sending admin.
	var/admin_name

/datum/eventkit/player_effects/proc/popup_replied(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/datum/prompt/text/admin_popup/request = A.request
	log_and_message_admins("replied to [request.admin_name]'s message: [A.answer.value].", request.answerer)

/// Only somebody with the spawn right works a button, and every effect is logged once, as it is pressed.
/datum/eventkit/player_effects/proc/ui_log_use(datum/act/op/A)
	var/mob/user = A.actor
	log_and_message_admins("used player effect: [A.oplan.key] on [target().ckey] playing [target().name]", user)
	return OP_OK

/datum/eventkit/player_effects/proc/ui_act_break_legs(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/broken_legs = 0
	var/obj/item/organ/external/left_leg = Tar.get_organ(BP_L_LEG)
	if(left_leg && left_leg.fracture())
		broken_legs++
	var/obj/item/organ/external/right_leg = Tar.get_organ(BP_R_LEG)
	if(right_leg && right_leg.fracture())
		broken_legs++
	if(!broken_legs)
		to_chat(user,"[target()] didn't have any breakable legs, sorry.")

/datum/eventkit/player_effects/proc/ui_act_bluespace_artillery(datum/act/op/A)
	var/mob/user = A.actor
	bluespace_artillery(target(), user)

/datum/eventkit/player_effects/proc/ui_act_spont_combustion(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.adjust_fire_stacks(10)
	Tar.ignite_mob()
	Tar.visible_message(span_danger("[target()] bursts into flames!"))

/datum/eventkit/player_effects/proc/ui_act_lightning_strike(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/turf/T = get_step(get_step(target(), NORTH), NORTH)
	T.Beam(target(), icon_state="lightning[rand(1,12)]", time = 5)
	Tar.electrocute_act(75,def_zone = BP_HEAD)
	target().visible_message(span_danger("[target()] is struck by lightning!"))

/datum/eventkit/player_effects/proc/ui_act_shadekin_attack(datum/act/op/A)
	var/turf/Tt = get_turf(target()) //Turf for target

	if(target().loc != Tt)
		return //Too hard to attack someone in something

	var/turf/Ts //Turf for shadekin

	//Try to find nondense turf
	for(var/direction in GLOB.cardinal)
		var/turf/T = get_step(target(),direction)
		if(T && !T.density)
			Ts = T //Found shadekin spawn turf
	if(!Ts)
		return //Didn't find shadekin spawn turf

	var/mob/living/simple_mob/shadekin/red/shadekin = new(Ts)
	//Abuse of shadekin
	shadekin.real_name = shadekin.name
	shadekin.init_vore(TRUE)
	shadekin.ability_flags |= 0x1
	shadekin.phase_out(get_turf(shadekin))
	shadekin.ai_brain?.give_target(target(), TRUE)
	shadekin.ai_brain?.set_hostile(FALSE)
	if(shadekin.ai_brain)
		shadekin.ai_brain.mauling = TRUE
	seq_run_frame_now(shadekin, /datum/sequence/life)
	//Remove when done
	after(shadekin, 10 SECONDS, TYPE_PROC_REF(/mob, death))

/// The kinds of shadekin the smite can make, by the name the question shows.
GLOBAL_LIST_INIT(shadekin_smite_types, list(
		"Red Eyes (Dark)" =	/mob/living/simple_mob/shadekin/red/dark,
		"Red Eyes (Light)" = /mob/living/simple_mob/shadekin/red/white,
		"Red Eyes (Brown)" = /mob/living/simple_mob/shadekin/red/brown,
		"Blue Eyes (Dark)" = /mob/living/simple_mob/shadekin/blue/dark,
		"Blue Eyes (Light)" = /mob/living/simple_mob/shadekin/blue/white,
		"Blue Eyes (Brown)" = /mob/living/simple_mob/shadekin/blue/brown,
		"Purple Eyes (Dark)" = /mob/living/simple_mob/shadekin/purple/dark,
		"Purple Eyes (Light)" = /mob/living/simple_mob/shadekin/purple/white,
		"Purple Eyes (Brown)" = /mob/living/simple_mob/shadekin/purple/brown,
		"Yellow Eyes (Dark)" = /mob/living/simple_mob/shadekin/yellow/dark,
		"Yellow Eyes (Light)" = /mob/living/simple_mob/shadekin/yellow/white,
		"Yellow Eyes (Brown)" = /mob/living/simple_mob/shadekin/yellow/brown,
		"Green Eyes (Dark)" = /mob/living/simple_mob/shadekin/green/dark,
		"Green Eyes (Light)" = /mob/living/simple_mob/shadekin/green/white,
		"Green Eyes (Brown)" = /mob/living/simple_mob/shadekin/green/brown,
		"Orange Eyes (Dark)" = /mob/living/simple_mob/shadekin/orange/dark,
		"Orange Eyes (Light)" = /mob/living/simple_mob/shadekin/orange/white,
		"Orange Eyes (Brown)" = /mob/living/simple_mob/shadekin/orange/brown,
		"Rivyr (Unique)" = /mob/living/simple_mob/shadekin/blue/rivyr))

/datum/eventkit/player_effects/proc/kin_types()
	return GLOB.shadekin_smite_types

/datum/eventkit/player_effects/proc/kin_names(datum/act/op/A)
	var/list/names = list()
	for(var/name in kin_types())
		names += name
	return names

/datum/eventkit/player_effects/proc/kin_question(datum/act/op/A)
	return "Select the type of shadekin for [target()] nomf"

/datum/eventkit/player_effects/proc/ui_act_shadekin_vore(datum/act/op/A)
	var/kin_name = answer_of(A, "kin")
	if(!kin_name || !target())
		return
	var/kin_type = kin_types()[kin_name]
	var/myself = answer_of(A, "control")
	if(!myself || myself == "Cancel" || !target())
		return

	var/turf/Tt = get_turf(target())

	if(target().loc != Tt)
		return //Can't nom when not exposed

	//Begin abuse
	target().transforming = TRUE //Cheap hack to stop them from moving
	var/mob/living/simple_mob/shadekin/shadekin = new kin_type(Tt)
	shadekin.real_name = shadekin.name
	shadekin.init_vore(TRUE)
	shadekin.can_be_drop_pred = TRUE
	shadekin.dir = SOUTH
	shadekin.ability_flags |= 0x1
	shadekin.phase_out(get_turf(shadekin)) //Homf
	var/datum/shadekin/smite_SK = shadekin.get_shadekin_state()
	if(smite_SK)
		smite_SK.dark_energy = initial(smite_SK.dark_energy)
	//For fun: a timed sequence (shadekin_smite_step), nothing sleeps.
	shadekin_smite_step(shadekin, target(), myself == "Control" ? target().ckey : null, 1)

/datum/eventkit/player_effects/proc/ui_act_redspace_abduct(datum/act/op/A)
	var/mob/user = A.actor
	redspace_abduction(target(), user)

/datum/eventkit/player_effects/proc/ui_act_autosave(datum/act/op/A)
	var/mob/user = A.actor
	fake_autosave(target(), user)

/datum/eventkit/player_effects/proc/ui_act_autosave2(datum/act/op/A)
	var/mob/user = A.actor
	fake_autosave(target(), user, TRUE)

/datum/eventkit/player_effects/proc/ui_act_adspam(datum/act/op/A)
	if(target().client)
		target().client.create_fake_ad_popup_multiple(/atom/movable/screen/popup/default, 15)

/datum/eventkit/player_effects/proc/ui_act_peppernade(datum/act/op/A)
	var/obj/item/grenade/chem_grenade/teargas/grenade = new /obj/item/grenade/chem_grenade/teargas
	grenade.forceMove(target().loc)
	to_chat(target(),span_warning("GRENADE?!"))
	grenade.detonate()

/datum/eventkit/player_effects/proc/ui_act_spicerequest(datum/act/op/A)
	var/obj/item/reagent_containers/food/condiment/spacespice/spice = new /obj/item/reagent_containers/food/condiment/spacespice
	spice.forceMove(target().loc)
	to_chat(target(),"A bottle of spices appears at your feet... be careful what you wish for!")

/datum/eventkit/player_effects/proc/ui_act_terror(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.set_fear(200)

/datum/eventkit/player_effects/proc/ui_act_terror_aoe(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	for(var/mob/living/carbon/human/L in orange(Tar.client.view, Tar))
		L.set_fear(200)
	Tar.set_fear(200)

/// The loops and direction are asked only for a speed that spins.
/datum/eventkit/player_effects/proc/spin_speed_ok(datum/act/op/A)
	var/speed = answer_of(A, "speed")
	return isnum(speed) && speed >= 0.1

/datum/eventkit/player_effects/proc/ui_act_spin(datum/act/op/A)
	var/speed = answer_of(A, "speed")
	if(!spin_speed_ok(A))
		return
	var/loops = answer_of(A, "loops")
	var/direction_ask = answer_of(A, "direction")
	var/direction
	if(direction_ask == "Clockwise")
		direction = 1
	if(direction_ask == "Anti-Clockwise")
		direction = 0
	if(direction_ask == "Cancel" || isnull(direction))
		return
	target().SpinAnimation(speed, loops, direction)

/datum/eventkit/player_effects/proc/ui_act_squish(datum/act/op/A)
	var/is_squished = target().tf_scale_x || target().tf_scale_y
	play_sfx(target(), SFX_ITEMS_HOOH)
	if(!is_squished)
		target().SetTransform(null, (target().size_multiplier * 1.2), (target().size_multiplier * 0.5))
	else
		target().ClearTransform()
		target().update_transform()

/datum/eventkit/player_effects/proc/ui_act_pie_splat(datum/act/op/A)
	new/obj/effect/decal/cleanable/pie_smudge(get_turf(target()))
	play_sfx(target(), SFX_EFFECTS_SLIME_SQUISH, 2, extrarange = get_rand_frequency(), falloff = 5)
	target().status_at_least(STAT_WEAKENED, 1)
	target().visible_message(span_danger("[target()] is struck by pie!"))

/datum/eventkit/player_effects/proc/ui_act_spicy_air(datum/act/op/A)
	to_chat(target(), span_warning("Spice spice baby!"))
	target().status_at_least(STAT_BLURRY, 25)
	target().status_at_least(STAT_BLINDED, 10)
	target().status_at_least(STAT_STUNNED, 5)
	target().status_at_least(STAT_WEAKENED, 5)
	play_sfx(target(), SFX_EFFECTS_SPRAY2, extrarange = get_rand_frequency(), falloff = 5)

/datum/eventkit/player_effects/proc/ui_act_hot_dog(datum/act/op/A)
	hotdog_smite(target())

/datum/eventkit/player_effects/proc/living_types(datum/act/op/A)
	return typesof(/mob/living)

/datum/eventkit/player_effects/proc/ui_act_mob_tf(datum/act/op/A)
	var/mob/living/M = target()

	if(!istype(M))
		return

	var/datum/prompt/P = A.answer
	var/chosen_beast = P?.value
	if(!chosen_beast)
		return

	var/mob/living/new_mob = new chosen_beast(get_turf(M))

	M.tf_into(new_mob)

/datum/eventkit/player_effects/proc/item_tf_ready(datum/act/op/A)
	var/mob/living/M = target()
	return istype(M) && M.ckey

/// The types whose path contains the text of the first question.
/datum/eventkit/player_effects/proc/typepath_matches(datum/act/op/A)
	var/typed = answer_of(A, "path")
	return istext(typed) ? typepaths_matching(typed, /atom) : list()

/datum/eventkit/player_effects/proc/typepath_ambiguous(datum/act/op/A)
	return length(typepath_matches(A)) > 1

/datum/eventkit/player_effects/proc/ui_act_item_tf(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/M = target()

	if(!istype(M))
		return

	if(!M.ckey)
		return

	var/list/matches = typepath_matches(A)
	var/spawning = length(matches) == 1 ? matches[1] : answer_of(A, "pick")
	if(!spawning)
		return

	to_chat(user,span_warning("spawning is: [spawning]"))

	if(!ispath(spawning, /obj/item/))
		to_chat(user,span_warning("Can only spawn items."))
		return

	var/obj/item/spawned_obj = new spawning(M.loc)
	var/obj/item/original_name = spawned_obj.name

	M.tf_into(spawned_obj, TRUE, original_name)

/datum/eventkit/player_effects/proc/ui_act_elder_smite(datum/act/op/A)
	if(!target().ckey)
		return
	target().overlay_fullscreen("scrolls", /atom/movable/screen/fullscreen/scrolls, 1)
	after(target(), 20 SECONDS, TYPE_PROC_REF(/mob, clear_fullscreen), with = list("scrolls"))

/datum/eventkit/player_effects/proc/wet_floors_other(datum/act/op/A)
	return answer_of(A, "reagent") == "Other"

/datum/eventkit/player_effects/proc/ui_act_wet_floors(datum/act/op/A)
	var/chem
	var/reagent_choice = answer_of(A, "reagent")
	if(!reagent_choice || (reagent_choice == "Cancel"))
		return
	if(reagent_choice ==  "Water")
		chem = REAGENT_ID_WATER
	if(reagent_choice == "Space Lube")
		chem = REAGENT_ID_LUBE
	if(reagent_choice == "Other")
		var/datum/reagent/chemical = answer_of(A, "chem")
		if(!chemical)
			return
		chem = chemical.id

	if(!target())
		return //Check target still exists after choices were made
	var/turf/target_turf = get_turf(target())
	for(var/turf/simulated/floor/surroundings in orange(1,target()))
		if(target_turf == surroundings) //Don't put it directly on our turf, just neighbouring ones
			continue
		var/datum/reagents/our_chem = new /datum/reagents(30) //Create some reagents, move them over, and clean up the datum afterwards
		our_chem.add_reagent(chem, 30)
		our_chem.trans_to_turf(surroundings,30)
		spent(our_chem)

////////MEDICAL//////////////

/datum/eventkit/player_effects/proc/ui_act_health_scan(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	var/datum/diagnosis/D = Tar.diagnose(/datum/diagnostic_profile/admin)
	if(D)
		to_chat(user, D.render_chat())
		spent(D)

/datum/eventkit/player_effects/proc/ui_act_appendicitis(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(istype(Tar))
		Tar.appendicitis()

/datum/eventkit/player_effects/proc/organ_chosen(datum/act/op/A)
	return !!answer_of(A, "organ")

/datum/eventkit/player_effects/proc/effect_is_damage(datum/act/op/A)
	return answer_of(A, "effect") == "Damage"

/datum/eventkit/player_effects/proc/effect_is_heal(datum/act/op/A)
	return answer_of(A, "effect") == "Heal"

/datum/eventkit/player_effects/proc/organ_damage_question(datum/act/op/A)
	var/obj/item/organ/our_organ = answer_of(A, "organ")
	return "Add how much damage? It is currently at [our_organ?.damage]."

/datum/eventkit/player_effects/proc/ui_act_damage_organ(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/obj/item/organ/our_organ = answer_of(A, "organ")
	if(!our_organ)
		return
	var/effect = answer_of(A, "effect")
	if(effect == "Cancel")
		return
	if(effect == "Damage")
		var/organ_damage = answer_of(A, "amount")
		if(isnull(organ_damage))
			return
		if(organ_damage > 0 && our_organ.owner == Tar)
			Tar.injure(INJURY_BLUNT, organ_damage, our_organ, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	if(effect == "Kill")
		our_organ.die()
	if(effect == "Bruise")
		our_organ.bruise()

/datum/eventkit/player_effects/proc/ui_act_assist_organ(datum/act/op/A)
	var/obj/item/organ/our_organ = answer_of(A, "choice")
	if(!our_organ)
		return
	our_organ.mechassist()

/datum/eventkit/player_effects/proc/ui_act_robot_organ(datum/act/op/A)
	var/obj/item/organ/our_organ = answer_of(A, "choice")
	if(!our_organ)
		return
	our_organ.robotize()

/datum/eventkit/player_effects/proc/ui_act_repair_organ(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/obj/item/organ/our_organ = answer_of(A, "organ")
	if(!our_organ)
		return
	var/effect = answer_of(A, "effect")
	if(effect == "Cancel")
		return
	if(effect == "Heal")
		var/organ_damage = answer_of(A, "amount")
		if(isnull(organ_damage))
			return
		if(organ_damage > 0 && our_organ.owner == Tar)
			Tar.mend(TREAT_RESTORATION, organ_damage, our_organ)
	if(effect == "Rejuvenate")
		our_organ.rejuvenate()

/datum/eventkit/player_effects/proc/ui_act_drop_organ(datum/act/op/A)
	var/obj/item/organ/our_organ = answer_of(A, "choice")
	if(!our_organ)
		return
	our_organ.removed()

/datum/eventkit/player_effects/proc/ui_act_break_bone(datum/act/op/A)
	var/obj/item/organ/external/our_organ = answer_of(A, "choice")
	if(!our_organ)
		return
	our_organ.fracture()

/datum/eventkit/player_effects/proc/ui_act_stasis(datum/act/op/A)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	if(Tar.has_stasis_from(null))
		Tar.set_stasis(null, null)
	else
		Tar.set_stasis(/datum/body_effect/stasis/total, null)

/datum/eventkit/player_effects/proc/chem_chosen(datum/act/op/A)
	return !!answer_of(A, "chem")

/datum/eventkit/player_effects/proc/ui_act_give_chem(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/datum/reagent/chemical = answer_of(A, "chem")
	if(!chemical)
		return
	var/chem = chemical.id
	var/amount = answer_of(A, "amount")
	if(!amount)
		return
	var/location = answer_of(A, "location")
	if(!location || location == "Cancel")
		return
	if(location == "Blood")
		Tar.bloodstr.add_reagent(chem, amount)
	if(location == "Stomach")
		Tar.ingested.add_reagent(chem, amount)
	if(location == "Skin")
		Tar.touching.add_reagent(chem, amount)

/datum/eventkit/player_effects/proc/ui_act_purge(datum/act/op/A)
	var/mob/living/carbon/Tar = target()
	if(!istype(Tar))
		return
	Tar.bloodstr.clear_reagents()
	Tar.ingested.clear_reagents()
	Tar.touching.clear_reagents()

/datum/eventkit/player_effects/proc/ui_act_medical_issue(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.custom_medical_issue(user)

/datum/eventkit/player_effects/proc/ui_act_clear_issue(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.clear_medical_issue(user)

////////ABILITIES//////////////

// Admin-given powers have no natural source datum: the target mob is its own source (a
// permanent self-grant, as if the power came with what it is).
/datum/eventkit/player_effects/proc/ui_act_vent_crawl(datum/act/op/A)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/proc/ventcrawl), Tar)

/datum/eventkit/player_effects/proc/darksight_question(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	return "What level do you wish to set their darksight to? It is currently [Tar?.species?.darksight]."

/datum/eventkit/player_effects/proc/ui_act_darksight(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/change_sight = answer_of(A, "number")
	if(change_sight)
		var/datum/species/own_species = proto_private(Tar, nameof(/datum/dna::species)) // PROTO: private copy
		own_species.darksight = change_sight

/datum/eventkit/player_effects/proc/ui_act_cocoon(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/enter_cocoon), Tar)

/datum/eventkit/player_effects/proc/ui_act_transformation(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_hair), Tar)
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_hair_colors), Tar)
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_gender), Tar)
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_wings), Tar)
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_tail), Tar)
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/shapeshifter_select_ears), Tar)
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/lleill_select_shape), Tar) //designed for non-shapeshifter mobs
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/lleill_select_colour), Tar)

/datum/eventkit/player_effects/proc/ui_act_set_size(datum/act/op/A)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/proc/set_size), Tar)

/datum/eventkit/player_effects/proc/lleill_max_question(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	return "What should their max lleill energy be set to? It is currently [Tar?.species?.lleill_energy_max]."

/datum/eventkit/player_effects/proc/lleill_now_question(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	return "What should their current lleill energy be set to? It is currently [Tar?.species?.lleill_energy]."

/datum/eventkit/player_effects/proc/ui_act_lleill_energy(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/energy_max = answer_of(A, "max")
	var/energy_new = answer_of(A, "now")
	if(isnull(energy_max) || isnull(energy_new))
		return
	var/datum/species/own_species = proto_private(Tar, nameof(/datum/dna::species)) // PROTO: private copy
	own_species.lleill_energy_max = energy_max
	own_species = proto_private(Tar, nameof(/datum/dna::species))
	own_species.lleill_energy = energy_new

/datum/eventkit/player_effects/proc/ui_act_lleill_invisibility(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/lleill_invisibility), Tar)

/datum/eventkit/player_effects/proc/ui_act_beast_form(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/lleill_beast_form), Tar)

/datum/eventkit/player_effects/proc/ui_act_lleill_transmute(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/lleill_transmute), Tar)

/datum/eventkit/player_effects/proc/ui_act_lleill_alchemy(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/lleill_alchemy), Tar)

/datum/eventkit/player_effects/proc/ui_act_lleill_drain(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/carbon/human/proc/lleill_contact), Tar)

/datum/eventkit/player_effects/proc/ui_act_brutal_pred(datum/act/op/A)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/proc/shred_limb), Tar)

/datum/eventkit/player_effects/proc/ui_act_trash_eater(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/proc/eat_trash), Tar)
	grant(Tar, granted_verb(/mob/living/proc/toggle_trash_catching), Tar)

/datum/eventkit/player_effects/proc/ui_act_active_cloaking(datum/act/op/A)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	grant(Tar, granted_verb(/mob/living/proc/toggle_active_cloaking), Tar)

/datum/eventkit/player_effects/proc/ui_act_colormate(datum/act/op/A)
	if(istype(target(),/mob/living/simple_mob))
		var/mob/living/simple_mob/Tar = target()
		grant(Tar, granted_verb(/mob/living/simple_mob/proc/ColorMate), Tar)
	if(istype(target(),/mob/living/silicon/robot))
		var/mob/living/silicon/robot/Tar = target()
		Tar.grant_ability(ABILITY_ID_ROBOT_RECOLOUR, Tar)

/datum/eventkit/player_effects/proc/ui_act_be_event_invis(datum/act/op/A)
	var/mob/living/Tar = target()
	if(!istype(Tar)) //Technically does not need this restriction, but prevents ghosts accidentally being placed in mob layer
		return
	if(Tar.plane != PLANE_INVIS_EVENT)
		Tar.plane = PLANE_INVIS_EVENT
		if(!(VIS_EVENT_INVIS in Tar.vis_enabled))
			Tar.plane_holder.set_vis(VIS_EVENT_INVIS,TRUE)
			Tar.vis_enabled += VIS_EVENT_INVIS
	else
		Tar.plane = MOB_LAYER
		if(VIS_EVENT_INVIS in Tar.vis_enabled)
			Tar.plane_holder.set_vis(VIS_EVENT_INVIS,FALSE)
			Tar.vis_enabled -= VIS_EVENT_INVIS

/datum/eventkit/player_effects/proc/ui_act_see_event_invis(datum/act/op/A)
	if(!(VIS_EVENT_INVIS in target().vis_enabled))
		target().plane_holder.set_vis(VIS_EVENT_INVIS,TRUE)
		target().vis_enabled += VIS_EVENT_INVIS
	else if(VIS_EVENT_INVIS in target().vis_enabled)
		target().plane_holder.set_vis(VIS_EVENT_INVIS,FALSE)
		target().vis_enabled -= VIS_EVENT_INVIS

////////INVENTORY//////////////

/datum/eventkit/player_effects/proc/drop_all_question(datum/act/op/A)
	return "Make [target()] drop everything?"

/datum/eventkit/player_effects/proc/ui_act_drop_all(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	if(!answer_of(A, "yes_no"))
		return

	for(var/obj/item/W in Tar)
		if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif)) // There's basically no reason to remove either of these
			continue
		Tar.drop_from_inventory(W)

/datum/eventkit/player_effects/proc/equipped_choices(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	return istype(Tar) ? Tar.get_equipped_items() : list()

/datum/eventkit/player_effects/proc/ui_act_drop_specific(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/item_to_drop = answer_of(A, "choice")
	if(item_to_drop)
		Tar.drop_from_inventory(item_to_drop)

/datum/eventkit/player_effects/proc/ui_act_drop_held(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.drop_l_hand()
	Tar.drop_r_hand()

/datum/eventkit/player_effects/proc/ui_act_list_all(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.get_equipped_items()

/datum/eventkit/player_effects/proc/ui_act_give_item(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	if(!check_rights_for(user.client, R_HOLDER))
		return
	var/obj/item/X = user.client.admin_datum().marked_datum()
	if(!istype(X))
		return
	Tar.put_in_hands(X)

/datum/eventkit/player_effects/proc/ui_act_equip_item(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	if(!check_rights_for(user.client, R_HOLDER))
		return
	var/obj/item/X = user.client.admin_datum().marked_datum()
	if(!istype(X))
		return
	if(Tar.equip_to_appropriate_slot(X))
		return
	else
		Tar.equip_to_storage(X)

////////ADMIN//////////////

/// The target can take a NIF: a head, and none yet.
/datum/eventkit/player_effects/proc/nif_target_ok(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	return istype(Tar) && Tar.get_organ(BP_HEAD) && !Tar.nif

/datum/eventkit/player_effects/proc/nif_target_refusal(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	if(istype(Tar) && Tar.get_organ(BP_HEAD))
		return /datum/msg/player_effects/nif_present
	return /datum/msg/player_effects/nif_unsuitable

MSG_DEF_SELF(player_effects/nif_unsuitable, "Target is unsuitable.")
MSG_DEF_SELF(player_effects/nif_present, "Target already has a NIF.")

/// A target without DNA gets the bioadaptive NIF without a question.
/datum/eventkit/player_effects/proc/nif_needs_pick(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	return istype(Tar) && !(Tar.species.flags & NO_DNA)

/// The NIF types by capitalised name, sorted.
/datum/eventkit/player_effects/proc/nif_types()
	var/list/NIFs = list()
	for(var/NIF_type in typesof(/obj/item/nif))
		var/obj/item/nif/S = NIF_type
		NIFs[capitalize(initial(S.name))] = NIF_type
	return sortList(NIFs)

/datum/eventkit/player_effects/proc/nif_choices(datum/act/op/A)
	var/list/names = list()
	for(var/name in nif_types())
		names += name
	return names

/datum/eventkit/player_effects/proc/ui_act_quick_nif(datum/act/op/A)
	var/mob/user = A.actor
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/input_NIF
	if(!Tar.get_organ(BP_HEAD))
		to_chat(user,span_warning("Target is unsuitable."))
		return
	if(Tar.nif)
		to_chat(user,span_warning("Target already has a NIF."))
		return
	if(Tar.species.flags & NO_DNA)
		var/obj/item/nif/S = /obj/item/nif/bioadap
		input_NIF = initial(S.name)
		new /obj/item/nif/bioadap(Tar)
	else
		input_NIF = answer_of(A, "choice")
		if(!input_NIF)
			return
		var/chosen_NIF = nif_types()[capitalize(input_NIF)]

		if(chosen_NIF)
			new chosen_NIF(Tar)
		else
			new /obj/item/nif(Tar)
	log_and_message_admins("Quick NIF'd [Tar.real_name] with a [input_NIF].", user)

/datum/eventkit/player_effects/proc/ui_act_resize(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/resize, target())

/datum/eventkit/player_effects/proc/teleport_to_mob(datum/act/op/A)
	return answer_of(A, "where") == "To Mob"

/datum/eventkit/player_effects/proc/teleport_to_area(datum/act/op/A)
	return answer_of(A, "where") == "To Area"

/datum/eventkit/player_effects/proc/teleport_mob_question(datum/act/op/A)
	return "Select a mob to jump [target()] to:"

/datum/eventkit/player_effects/proc/teleport_area_question(datum/act/op/A)
	return "Pick an area to teleport [target()] to:"

/datum/eventkit/player_effects/proc/teleport_mobs(datum/act/op/A)
	return REGISTRY_MEMBERS(REGISTRY_MOBS)

/datum/eventkit/player_effects/proc/teleport_areas(datum/act/op/A)
	return return_sorted_areas()

/datum/eventkit/player_effects/proc/ui_act_teleport(datum/act/op/A)
	var/mob/user = A.actor
	var/where = answer_of(A, "where")
	if(!where || where == "Cancel")
		return
	if(where == "To Me")
		SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/Getmob, target())
	if(where == "To Mob")
		var/mob/selection = answer_of(A, "mob")
		if(!selection)
			return
		target().on_mob_jump()
		target().forceMove(get_turf(selection))
		log_admin("[key_name(user)] jumped [target()] to [selection]")
	if(where == "To Area")
		var/area/where_to = answer_of(A, "area")
		if(!where_to)
			return
		target().on_mob_jump()
		target().forceMove(pick(get_area_turfs(where_to)))
		log_admin("[key_name(user)] jumped [target()] to [where_to]")

/datum/eventkit/player_effects/proc/ui_act_gib(datum/act/op/A)
	open_request(src, /datum/prompt/choice, PROC_REF(gib_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Are you sure you want to destroy [target()]?", title = "Gib?", choices = list("KILL", "Cancel"), timeout = 0)

/datum/eventkit/player_effects/proc/gib_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/death = A.answer.value
	if(death == "KILL")
		target().gib()

/datum/eventkit/player_effects/proc/ui_act_dust(datum/act/op/A)
	open_request(src, /datum/prompt/choice, PROC_REF(dust_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Are you sure you want to destroy [target()]?", title = "Dust?", choices = list("KILL", "Cancel"), timeout = 0)

/datum/eventkit/player_effects/proc/dust_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/death = A.answer.value
	if(death == "KILL")
		target().dust()

/datum/eventkit/player_effects/proc/ui_act_paralyse(datum/act/op/A)
	var/mob/user = A.actor
	if(!isliving(target()))
		return
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/paralyze_mob, target())

/datum/eventkit/player_effects/proc/ui_act_subtle_message(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_subtle_message, target())

/datum/eventkit/player_effects/proc/ui_act_direct_narrate(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/cmd_admin_direct_narrate, target())

/datum/eventkit/player_effects/proc/ui_act_player_panel(datum/act/op/A)
	var/mob/user = A.actor
	SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/show_player_panel, target())

/datum/eventkit/player_effects/proc/ui_act_view_variables(datum/act/op/A)
	var/mob/user = A.actor
	user.client.debug_variables(target())

/datum/eventkit/player_effects/proc/ui_act_orbit(datum/act/op/A)
	var/mob/user = A.actor
	if(!user.client.admin_datum().marked_datum())
		return
	var/atom/movable/X = user.client.admin_datum().marked_datum()
	X.orbit(target())

/// A living mob nobody plays.
/datum/eventkit/player_effects/proc/ai_target_ok(datum/act/op/A)
	var/mob/living/L = target()
	return istype(L) && !L.client && !L.teleop

/datum/eventkit/player_effects/proc/ai_target_refusal(datum/act/op/A)
	return isliving(target()) ? /datum/msg/player_effects/ai_player : /datum/msg/player_effects/ai_not_living

MSG_DEF_SELF(player_effects/ai_not_living, "This can only be used on instances of type /mob/living")
MSG_DEF_SELF(player_effects/ai_player, "This cannot be used on player mobs!")

/datum/eventkit/player_effects/proc/ui_act_ai(datum/act/op/A)
	var/mob/living/L = target()
	if(!istype(L))
		return
	// Everything is asked first, so nothing changes until the last answer.
	var/faction = answer_of(A, "faction")
	if(isnull(faction))
		return
	var/stance = answer_of(A, "stance")
	if(L.ai_brain)	//Cleaning up the original ai
		own_clear(L, nameof(/mob/living::ai_brain), OWN_DELETE)	//Only way I could make #TESTING - Unable to be GC'd to stop. del() logs show it works.
	L.initialize_ai_brain()
	L.faction = faction
	if(stance)
		L.set_use_stance(stance)
	if(answer_of(A, "wake"))
		L.status_adjust(STAT_SLEEPING, -100)

/datum/eventkit/player_effects/proc/ui_act_cloaking(datum/act/op/A)
	if(dq_get_cloaked(target()))
		target().uncloak()
	else if(!dq_get_cloaked(target()))
		target().cloak()

/datum/eventkit/player_effects/proc/has_target(datum/act/op/A)
	return !!target()

/datum/eventkit/player_effects/proc/quest_personalised(datum/act/op/A)
	return answer_of(A, "kind") == "Personalised"

/datum/eventkit/player_effects/proc/ui_act_give_quest(datum/act/op/A)
	if(!target())
		return
	var/admin_quest = answer_of(A, "kind")
	if(!admin_quest || (admin_quest == "Cancel"))
		return
	if(admin_quest == "Personalised")
		var/specific_quest = answer_of(A, "quest")
		if(!specific_quest)
			return
		quest_from_above(target(), specific_quest)
	else
		quest_from_above(target())

////////FIXES//////////////

/datum/eventkit/player_effects/proc/ui_act_rejuvenate(datum/act/op/A)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	Tar.rejuvenate()

/datum/eventkit/player_effects/proc/ui_act_popup_box(datum/act/op/A)
	open_request(src, /datum/prompt/text, PROC_REF(popup_box_answered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Write a message to send to the user with a space for them to reply without using the text box:", title = "Message", timeout = 0)

/datum/eventkit/player_effects/proc/popup_box_answered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/message = A.answer.value
	if(!message)
		return
	log_admin("[key_name(user)] sent message to [target()]: [message]")
	// The player answers in their own time; the reply doesn't need this panel open.
	open_request(src, /datum/prompt/text/admin_popup, PROC_REF(popup_replied), answerer = target(), question = "An admin has sent you a message: [message]", admin_name = key_name(user))

/datum/eventkit/player_effects/proc/ui_act_stop_orbits(datum/act/op/A)
	target().stop_orbiters()

/datum/eventkit/player_effects/proc/ui_act_revert_mob_tf(datum/act/op/A)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	Tar.revert_mob_tf()

/// The target of the effects (a relation view: null once that is deleted).
/// The target's organs (every organ a player effect may pick), for the organ questions.
/// The answer to a question a button asked still counts (its window is still open and interactive for the one who answers).
/datum/eventkit/player_effects/proc/request_usable(datum/request/R)
	return window_request_usable(src, R)

/datum/eventkit/player_effects/proc/organ_choices(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	var/list/organs = list()
	if(!istype(Tar))
		return organs
	for(var/obj/item/organ/I in Tar.organs)
		organs |= I
	for(var/obj/item/organ/I in Tar.internal_organ_list())
		organs |= I
	return organs

/// The target's external organs (the bones), for the bone question.
/datum/eventkit/player_effects/proc/bone_choices(datum/act/op/A)
	var/mob/living/carbon/human/Tar = target()
	var/list/organs = list()
	if(!istype(Tar))
		return organs
	for(var/obj/item/organ/external/E in Tar.organs)
		organs |= E
	return organs

/datum/eventkit/player_effects/proc/reagent_types(datum/act/op/A)
	return typesof(/datum/reagent)

/// The step `name` of the op as the answer given, or null.
/datum/eventkit/player_effects/proc/answer_of(datum/act/op/A, name)
	var/datum/prompt/P = A.step_answer(name)
	return P?.value

/datum/eventkit/player_effects/proc/target_human(datum/act/op/A)
	return istype(target(), /mob/living/carbon/human)

/datum/eventkit/player_effects/proc/target_living(datum/act/op/A)
	return istype(target(), /mob/living)

/datum/eventkit/player_effects/proc/target() as /mob
	return target
