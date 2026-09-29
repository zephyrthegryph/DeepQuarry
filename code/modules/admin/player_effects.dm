
ADMIN_VERB_AND_CONTEXT_MENU(player_effects, R_FUN, "Player Effects", "Modify a player character with various 'special treatments' from a list.", ADMIN_CATEGORY_FUN_EVENT_KIT, mob/target in get_mob_with_client_list())
	var/datum/eventkit/player_effects/spawner = new()
	spawner.target_handle = om_handle(target)
	spawner.tgui_interact(user.mob)

/datum/eventkit/player_effects
	var/tmp/target_handle	//The target of the effects

/datum/eventkit/player_effects/New()
	. = ..()

DECLARE_UI(/datum/eventkit/player_effects, "PlayerEffects", UI_TITLE("Player Effects"))

/datum/eventkit/player_effects/tgui_static_data(mob/user)
	var/list/data = list()

	data["real_name"] = target().name;
	data["player_ckey"] = target().ckey;
	data["target_mob"] = target();

	return data

DECLARE_UI_STATE(/datum/eventkit/player_effects, ADMIN_STATE(R_ADMIN|R_EVENT|R_DEBUG))

/datum/om/prompt/text/admin_popup
	title = "Reply"
	/// key_name() of the sending admin.
	var/admin_name

/datum/eventkit/player_effects/proc/popup_replied(datum/om/prompt/text/admin_popup/ask)
	if(ask.text)
		log_and_message_admins("replied to [ask.admin_name]'s message: [ask.text].", ask.answerer)

/// Every effect is logged once (answers to its questions re-run the action with om_reentry set).
/datum/eventkit/player_effects/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!check_rights_for(user.client, R_SPAWN))
		return FALSE
	if(!GLOB.ui_rerun)
		log_and_message_admins("used player effect: [action] on [target().ckey] playing [target().name]", user)
	return TRUE

/datum/eventkit/player_effects/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	if(!check_rights_for(ui.user.client, R_SPAWN))
		return FALSE
	return TRUE

UI_ACT(/datum/eventkit/player_effects, "break_legs", ui_act_break_legs)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_break_legs)
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
		to_chat(ui.user,"[target()] didn't have any breakable legs, sorry.")

UI_ACT(/datum/eventkit/player_effects, "bluespace_artillery", ui_act_bluespace_artillery)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_bluespace_artillery)
	bluespace_artillery(target(), ui.user)

UI_ACT(/datum/eventkit/player_effects, "spont_combustion", ui_act_spont_combustion)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_spont_combustion)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.adjust_fire_stacks(10)
	Tar.ignite_mob()
	Tar.visible_message(span_danger("[target()] bursts into flames!"))

UI_ACT(/datum/eventkit/player_effects, "lightning_strike", ui_act_lightning_strike)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_lightning_strike)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/turf/T = get_step(get_step(target(), NORTH), NORTH)
	T.Beam(target(), icon_state="lightning[rand(1,12)]", time = 5)
	Tar.electrocute_act(75,def_zone = BP_HEAD)
	target().visible_message(span_danger("[target()] is struck by lightning!"))

UI_ACT(/datum/eventkit/player_effects, "shadekin_attack", ui_act_shadekin_attack)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_shadekin_attack)
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
	om_run_frame_now(shadekin, /datum/om/pipeline/life)
	//Remove when done
	spawn(10 SECONDS) // ALLOW(scheduler): admin verb (allowlist)
		if(shadekin)
			shadekin.death()

UI_ACT(/datum/eventkit/player_effects, "shadekin_vore", ui_act_shadekin_vore)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_shadekin_vore)
	var/static/list/kin_types = list(
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
		"Rivyr (Unique)" = /mob/living/simple_mob/shadekin/blue/rivyr)
	var/kin_type = act_ask(ui.user, action, params, ui, "a1", /datum/om/prompt/choice, message = "Select the type of shadekin for [target()] nomf", title = "Shadekin Type Choice", choices = kin_types)
	if(isnull(kin_type))
		return
	if(!kin_type || !target())
		return

	kin_type = kin_types[kin_type]

	var/myself = act_ask(ui.user, action, params, ui, "a2", /datum/om/prompt/choice/alert, message = "Control the shadekin yourself or delete pred and prey after?", title = "Control Shadekin?", choices = list("Control","Cancel","Delete"))
	if(isnull(myself))
		return
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

UI_ACT(/datum/eventkit/player_effects, "redspace_abduct", ui_act_redspace_abduct)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_redspace_abduct)
	redspace_abduction(target(), ui.user)

UI_ACT(/datum/eventkit/player_effects, "autosave", ui_act_autosave)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_autosave)
	fake_autosave(target(), ui.user)

UI_ACT(/datum/eventkit/player_effects, "autosave2", ui_act_autosave2)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_autosave2)
	fake_autosave(target(), ui.user, TRUE)

UI_ACT(/datum/eventkit/player_effects, "adspam", ui_act_adspam)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_adspam)
	if(target().client)
		target().client.create_fake_ad_popup_multiple(/atom/movable/screen/popup/default, 15)

UI_ACT(/datum/eventkit/player_effects, "peppernade", ui_act_peppernade)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_peppernade)
	var/obj/item/grenade/chem_grenade/teargas/grenade = new /obj/item/grenade/chem_grenade/teargas
	grenade.forceMove(target().loc)
	to_chat(target(),span_warning("GRENADE?!"))
	grenade.detonate()

UI_ACT(/datum/eventkit/player_effects, "spicerequest", ui_act_spicerequest)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_spicerequest)
	var/obj/item/reagent_containers/food/condiment/spacespice/spice = new /obj/item/reagent_containers/food/condiment/spacespice
	spice.forceMove(target().loc)
	to_chat(target(),"A bottle of spices appears at your feet... be careful what you wish for!")

UI_ACT(/datum/eventkit/player_effects, "terror", ui_act_terror)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_terror)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.fear = 200

UI_ACT(/datum/eventkit/player_effects, "terror_aoe", ui_act_terror_aoe)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_terror_aoe)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	for(var/mob/living/carbon/human/L in orange(Tar.client.view, Tar))
		L.fear = 200
	Tar.fear = 200

UI_ACT(/datum/eventkit/player_effects, "spin", ui_act_spin)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_spin)
	var/speed = act_ask(ui.user, action, params, ui, "a3", /datum/om/prompt/number, message = "Spin speed (minimum 0.1):", title = "Speed")
	if(isnull(speed))
		return
	if(speed < 0.1)
		return
	var/loops = act_ask(ui.user, action, params, ui, "a4", /datum/om/prompt/number, message = "Number of loops (-1 for infinite):", title = "Loops")
	if(isnull(loops))
		return
	var/direction_ask = act_ask(ui.user, action, params, ui, "a5", /datum/om/prompt/choice/alert, message = "Clockwise or Anti-Clockwise", title = "Direction", choices = list("Clockwise", "Anti-Clockwise", "Cancel"))
	if(isnull(direction_ask))
		return
	var/direction
	if(direction_ask == "Clockwise")
		direction = 1
	if(direction_ask == "Anti-Clockwise")
		direction = 0
	if(direction_ask == "Cancel")
		return
	target().SpinAnimation(speed, loops, direction)

UI_ACT(/datum/eventkit/player_effects, "squish", ui_act_squish)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_squish)
	var/is_squished = target().tf_scale_x || target().tf_scale_y
	play_sfx(target(), SFX_ITEMS_HOOH)
	if(!is_squished)
		target().SetTransform(null, (target().size_multiplier * 1.2), (target().size_multiplier * 0.5))
	else
		target().ClearTransform()
		target().update_transform()

UI_ACT(/datum/eventkit/player_effects, "pie_splat", ui_act_pie_splat)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_pie_splat)
	new/obj/effect/decal/cleanable/pie_smudge(get_turf(target()))
	play_sfx(target(), SFX_EFFECTS_SLIME_SQUISH, 2, extrarange = get_rand_frequency(), falloff = 5)
	target().status_at_least(EFFECT_WEAKENED, 1)
	target().visible_message(span_danger("[target()] is struck by pie!"))

UI_ACT(/datum/eventkit/player_effects, "spicy_air", ui_act_spicy_air)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_spicy_air)
	to_chat(target(), span_warning("Spice spice baby!"))
	target().status_at_least(EFFECT_BLURRY, 25)
	target().status_at_least(EFFECT_BLINDED, 10)
	target().status_at_least(EFFECT_STUNNED, 5)
	target().status_at_least(EFFECT_WEAKENED, 5)
	play_sfx(target(), SFX_EFFECTS_SPRAY2, extrarange = get_rand_frequency(), falloff = 5)

UI_ACT(/datum/eventkit/player_effects, "hot_dog", ui_act_hot_dog)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_hot_dog)
	hotdog_smite(target())

UI_ACT(/datum/eventkit/player_effects, "mob_tf", ui_act_mob_tf)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_mob_tf)
	var/mob/living/M = target()

	if(!istype(M))
		return

	var/list/types = typesof(/mob/living)
	var/chosen_beast = act_ask(ui.user, action, params, ui, "a6", /datum/om/prompt/choice, message = "Which form would you like to take?", title = "Choose Beast Form", choices = types)
	if(isnull(chosen_beast))
		return

	if(!chosen_beast)
		return

	var/mob/living/new_mob = new chosen_beast(get_turf(M))

	M.tf_into(new_mob)

UI_ACT(/datum/eventkit/player_effects, "item_tf", ui_act_item_tf)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_item_tf)
	var/mob/living/M = target()

	if(!istype(M))
		return

	if(!M.ckey)
		return

	var/obj/item/spawning = act_ask(ui.user, action, params, ui, "item_path", /datum/om/prompt/typepath, message = "Enter full or partial typepath.", title = "Typepath")
	if(isnull(spawning))
		return

	to_chat(ui.user,span_warning("spawning is: [spawning]"))

	if(!ispath(spawning, /obj/item/))
		to_chat(ui.user,span_warning("Can only spawn items."))
		return

	var/obj/item/spawned_obj = new spawning(M.loc)
	var/obj/item/original_name = spawned_obj.name

	M.tf_into(spawned_obj, TRUE, original_name)

UI_ACT(/datum/eventkit/player_effects, "elder_smite", ui_act_elder_smite)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_elder_smite)
	if(!target().ckey)
		return
	target().overlay_fullscreen("scrolls", /atom/movable/screen/fullscreen/scrolls, 1)
	om_after(target(), 20 SECONDS, TYPE_PROC_REF(/mob, clear_fullscreen), "scrolls")

UI_ACT(/datum/eventkit/player_effects, "wet_floors", ui_act_wet_floors)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_wet_floors)
	var/chem
	var/reagent_choice = act_ask(ui.user, action, params, ui, "a7", /datum/om/prompt/choice/alert, message = "Which reagent do you want to place on the floors around them?", title = "Reagent", choices = list("Water", "Space Lube", "Other", "Cancel"))
	if(isnull(reagent_choice))
		return
	if(!reagent_choice || (reagent_choice == "Cancel"))
		return
	if(reagent_choice ==  "Water")
		chem = REAGENT_ID_WATER
	if(reagent_choice == "Space Lube")
		chem = REAGENT_ID_LUBE
	if(reagent_choice == "Other")
		var/list/chem_list = typesof(/datum/reagent)
		var/datum/reagent/chemical = act_ask(ui.user, action, params, ui, "a8", /datum/om/prompt/choice, message = "Which chemical would you like to use?", title = "Chemicals", choices = chem_list)
		if(isnull(chemical))
			return
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
		qdel(our_chem)

////////MEDICAL//////////////

UI_ACT(/datum/eventkit/player_effects, "health_scan", ui_act_health_scan)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_health_scan)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	var/datum/diagnosis/D = Tar.diagnose(/datum/diagnostic_profile/admin)
	if(D)
		to_chat(ui.user, D.render_chat())
		qdel(D)

UI_ACT(/datum/eventkit/player_effects, "appendicitis", ui_act_appendicitis)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_appendicitis)
	var/mob/living/carbon/human/Tar = target()
	if(istype(Tar))
		Tar.appendicitis()

UI_ACT(/datum/eventkit/player_effects, "damage_organ", ui_act_damage_organ)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_damage_organ)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/list/organs = list()
	for(var/obj/item/organ/I in Tar.organs)
		organs |= I
	for(var/obj/item/organ/I in Tar.internal_organ_list())
		organs |= I
	var/obj/item/organ/our_organ = act_ask(ui.user, action, params, ui, "a9", /datum/om/prompt/choice, message = "Choose an organ to damage:", title = "Organs", choices = organs)
	if(isnull(our_organ))
		return
	if(!our_organ)
		return
	var/effect = act_ask(ui.user, action, params, ui, "a10", /datum/om/prompt/choice/alert, message = "What do you want to do to the Organ", title = "Effect", choices = list("Damage", "Kill", "Bruise", "Cancel"))
	if(isnull(effect))
		return
	if(effect == "Cancel")
		return
	if(effect == "Damage")
		var/organ_damage = act_ask(ui.user, action, params, ui, "a11", /datum/om/prompt/number, message = "Add how much damage? It is currently at [our_organ.damage].", title = "Damage")
		if(isnull(organ_damage))
			return
		if(organ_damage > 0 && our_organ.owner == Tar)
			Tar.injure(INJURY_BLUNT, organ_damage, our_organ, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	if(effect == "Kill")
		our_organ.die()
	if(effect == "Bruise")
		our_organ.bruise()

UI_ACT(/datum/eventkit/player_effects, "assist_organ", ui_act_assist_organ)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_assist_organ)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/list/organs = list()
	for(var/obj/item/organ/I in Tar.organs)
		organs |= I
	for(var/obj/item/organ/I in Tar.internal_organ_list())
		organs |= I
	var/obj/item/organ/our_organ = act_ask(ui.user, action, params, ui, "a12", /datum/om/prompt/choice, message = "Choose an organ to become assisted:", title = "Organs", choices = organs)
	if(isnull(our_organ))
		return
	if(!our_organ)
		return
	our_organ.mechassist()

UI_ACT(/datum/eventkit/player_effects, "robot_organ", ui_act_robot_organ)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_robot_organ)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/list/organs = list()
	for(var/obj/item/organ/I in Tar.organs)
		organs |= I
	for(var/obj/item/organ/I in Tar.internal_organ_list())
		organs |= I
	var/obj/item/organ/our_organ = act_ask(ui.user, action, params, ui, "a13", /datum/om/prompt/choice, message = "Choose an organ to become robotic:", title = "Organs", choices = organs)
	if(isnull(our_organ))
		return
	if(!our_organ)
		return
	our_organ.robotize()

UI_ACT(/datum/eventkit/player_effects, "repair_organ", ui_act_repair_organ)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_repair_organ)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/list/organs = list()
	for(var/obj/item/organ/I in Tar.organs)
		organs |= I
	for(var/obj/item/organ/I in Tar.internal_organ_list())
		organs |= I
	var/obj/item/organ/our_organ = act_ask(ui.user, action, params, ui, "a14", /datum/om/prompt/choice, message = "Choose an organ to heal:", title = "Organs", choices = organs)
	if(isnull(our_organ))
		return
	if(!our_organ)
		return
	var/effect = act_ask(ui.user, action, params, ui, "a15", /datum/om/prompt/choice/alert, message = "What do you want to do to the Organ", title = "Effect", choices = list("Heal", "Rejuvenate", "Cancel"))
	if(isnull(effect))
		return
	if(effect == "Cancel")
		return
	if(effect == "Heal")
		var/organ_damage = act_ask(ui.user, action, params, ui, "a16", /datum/om/prompt/number, message = "Add how much damage? It is currently at [our_organ.damage].", title = "Damage")
		if(isnull(organ_damage))
			return
		if(organ_damage > 0 && our_organ.owner == Tar)
			Tar.mend(TREAT_RESTORATION, organ_damage, our_organ)
	if(effect == "Rejuvenate")
		our_organ.rejuvenate()

UI_ACT(/datum/eventkit/player_effects, "drop_organ", ui_act_drop_organ)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_drop_organ)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/list/organs = list()
	for(var/obj/item/organ/I in Tar.organs)
		organs |= I
	for(var/obj/item/organ/I in Tar.internal_organ_list())
		organs |= I
	var/obj/item/organ/our_organ = act_ask(ui.user, action, params, ui, "a17", /datum/om/prompt/choice, message = "Choose an organ to damage:", title = "Organs", choices = organs)
	if(isnull(our_organ))
		return
	if(!our_organ)
		return
	our_organ.removed()

UI_ACT(/datum/eventkit/player_effects, "break_bone", ui_act_break_bone)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_break_bone)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/list/organs = list()
	for(var/obj/item/organ/external/E in Tar.organs)
		organs |= E
	var/obj/item/organ/external/our_organ = act_ask(ui.user, action, params, ui, "a18", /datum/om/prompt/choice, message = "Choose an bone to break:", title = "Organs", choices = organs)
	if(isnull(our_organ))
		return
	if(!our_organ)
		return
	our_organ.fracture()

UI_ACT(/datum/eventkit/player_effects, "stasis", ui_act_stasis)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_stasis)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	if(Tar.has_stasis_from(null))
		Tar.set_stasis(null, null)
	else
		Tar.set_stasis(/datum/body_effect/stasis/total, null)

UI_ACT(/datum/eventkit/player_effects, "give_chem", ui_act_give_chem)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_give_chem)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/list/chem_list = typesof(/datum/reagent)
	var/datum/reagent/chemical = act_ask(ui.user, action, params, ui, "a19", /datum/om/prompt/choice, message = "Which chemical would you like to add?", title = "Chemicals", choices = chem_list)
	if(isnull(chemical))
		return

	if(!chemical)
		return

	var/chem = chemical.id

	var/amount = act_ask(ui.user, action, params, ui, "a20", /datum/om/prompt/number, message = "How much of the chemical would you like to add?", title = "Amount", default = 5)
	if(isnull(amount))
		return
	if(!amount)
		return

	var/location = act_ask(ui.user, action, params, ui, "a21", /datum/om/prompt/choice/alert, message = "Where do you want to add the chemical?", title = "Location", choices = list("Blood", "Stomach", "Skin", "Cancel"))
	if(isnull(location))
		return

	if(!location || location == "Cancel")
		return
	if(location == "Blood")
		Tar.bloodstr.add_reagent(chem, amount)
	if(location == "Stomach")
		Tar.ingested.add_reagent(chem, amount)
	if(location == "Skin")
		Tar.touching.add_reagent(chem, amount)

UI_ACT(/datum/eventkit/player_effects, "purge", ui_act_purge)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_purge)
	var/mob/living/carbon/Tar = target()
	if(!istype(Tar))
		return
	Tar.bloodstr.clear_reagents()
	Tar.ingested.clear_reagents()
	Tar.touching.clear_reagents()

UI_ACT(/datum/eventkit/player_effects, "medical_issue", ui_act_medical_issue)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_medical_issue)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.custom_medical_issue(ui.user)

UI_ACT(/datum/eventkit/player_effects, "clear_issue", ui_act_clear_issue)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_clear_issue)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.clear_medical_issue(ui.user)

////////ABILITIES//////////////

UI_ACT(/datum/eventkit/player_effects, "vent_crawl", ui_act_vent_crawl)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_vent_crawl)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/proc/ventcrawl)

UI_ACT(/datum/eventkit/player_effects, "darksight", ui_act_darksight)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_darksight)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/current_darksight = Tar.species.darksight
	var/change_sight = act_ask(ui.user, action, params, ui, "a22", /datum/om/prompt/number, message = "What level do you wish to set their darksight to? It is currently [current_darksight].", title = "Darksight")
	if(isnull(change_sight))
		return
	if(change_sight)
		Tar.species.darksight = change_sight

UI_ACT(/datum/eventkit/player_effects, "cocoon", ui_act_cocoon)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_cocoon)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/carbon/human/proc/enter_cocoon)

UI_ACT(/datum/eventkit/player_effects, "transformation", ui_act_transformation)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_transformation)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/carbon/human/proc/shapeshifter_select_hair)
	add_verb(Tar, /mob/living/carbon/human/proc/shapeshifter_select_hair_colors)
	add_verb(Tar, /mob/living/carbon/human/proc/shapeshifter_select_gender)
	add_verb(Tar, /mob/living/carbon/human/proc/shapeshifter_select_wings)
	add_verb(Tar, /mob/living/carbon/human/proc/shapeshifter_select_tail)
	add_verb(Tar, /mob/living/carbon/human/proc/shapeshifter_select_ears)
	add_verb(Tar, /mob/living/carbon/human/proc/lleill_select_shape) //designed for non-shapeshifter mobs
	add_verb(Tar, /mob/living/carbon/human/proc/lleill_select_colour)

UI_ACT(/datum/eventkit/player_effects, "set_size", ui_act_set_size)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_set_size)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/proc/set_size)

UI_ACT(/datum/eventkit/player_effects, "lleill_energy", ui_act_lleill_energy)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_lleill_energy)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/energy_max = act_ask(ui.user, action, params, ui, "a23", /datum/om/prompt/number, message = "What should their max lleill energy be set to? It is currently [Tar.species.lleill_energy_max].", title = "Max energy")
	if(isnull(energy_max))
		return
	Tar.species.lleill_energy_max = energy_max
	var/energy_new = act_ask(ui.user, action, params, ui, "a24", /datum/om/prompt/number, message = "What should their current lleill energy be set to? It is currently [Tar.species.lleill_energy].", title = "Max energy")
	if(isnull(energy_new))
		return
	Tar.species.lleill_energy = energy_new

UI_ACT(/datum/eventkit/player_effects, "lleill_invisibility", ui_act_lleill_invisibility)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_lleill_invisibility)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/carbon/human/proc/lleill_invisibility)

UI_ACT(/datum/eventkit/player_effects, "beast_form", ui_act_beast_form)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_beast_form)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/carbon/human/proc/lleill_beast_form)

UI_ACT(/datum/eventkit/player_effects, "lleill_transmute", ui_act_lleill_transmute)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_lleill_transmute)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/carbon/human/proc/lleill_transmute)

UI_ACT(/datum/eventkit/player_effects, "lleill_alchemy", ui_act_lleill_alchemy)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_lleill_alchemy)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/carbon/human/proc/lleill_alchemy)

UI_ACT(/datum/eventkit/player_effects, "lleill_drain", ui_act_lleill_drain)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_lleill_drain)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/carbon/human/proc/lleill_contact)

UI_ACT(/datum/eventkit/player_effects, "brutal_pred", ui_act_brutal_pred)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_brutal_pred)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/proc/shred_limb)

UI_ACT(/datum/eventkit/player_effects, "trash_eater", ui_act_trash_eater)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_trash_eater)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/proc/eat_trash)
	add_verb(Tar, /mob/living/proc/toggle_trash_catching)

UI_ACT(/datum/eventkit/player_effects, "active_cloaking", ui_act_active_cloaking)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_active_cloaking)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	add_verb(Tar, /mob/living/proc/toggle_active_cloaking)

UI_ACT(/datum/eventkit/player_effects, "colormate", ui_act_colormate)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_colormate)
	if(istype(target(),/mob/living/simple_mob))
		var/mob/living/simple_mob/Tar = target()
		add_verb(Tar, /mob/living/simple_mob/proc/ColorMate)
	if(istype(target(),/mob/living/silicon/robot))
		var/mob/living/silicon/robot/Tar = target()
		Tar.grant_ability(ABILITY_ID_ROBOT_RECOLOUR, Tar)

UI_ACT(/datum/eventkit/player_effects, "be_event_invis", ui_act_be_event_invis)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_be_event_invis)
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

UI_ACT(/datum/eventkit/player_effects, "see_event_invis", ui_act_see_event_invis)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_see_event_invis)
	if(!(VIS_EVENT_INVIS in target().vis_enabled))
		target().plane_holder.set_vis(VIS_EVENT_INVIS,TRUE)
		target().vis_enabled += VIS_EVENT_INVIS
	else if(VIS_EVENT_INVIS in target().vis_enabled)
		target().plane_holder.set_vis(VIS_EVENT_INVIS,FALSE)
		target().vis_enabled -= VIS_EVENT_INVIS

////////INVENTORY//////////////

UI_ACT(/datum/eventkit/player_effects, "drop_all", ui_act_drop_all)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_drop_all)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/confirm = act_ask(ui.user, action, params, ui, "a25", /datum/om/prompt/choice/alert, message = "Make [Tar] drop everything?", title = "Message", choices = list("Yes", "No"))
	if(isnull(confirm))
		return
	if(confirm != "Yes")
		return

	for(var/obj/item/W in Tar)
		if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif)) // There's basically no reason to remove either of these
			continue
		Tar.drop_from_inventory(W)

UI_ACT(/datum/eventkit/player_effects, "drop_specific", ui_act_drop_specific)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_drop_specific)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return

	var/list/items = Tar.get_equipped_items()
	var/item_to_drop = act_ask(ui.user, action, params, ui, "a26", /datum/om/prompt/choice, message = "Choose item to force drop:", title = "Drop Specific Item", choices = items)
	if(isnull(item_to_drop))
		return
	if(item_to_drop)
		Tar.drop_from_inventory(item_to_drop)

UI_ACT(/datum/eventkit/player_effects, "drop_held", ui_act_drop_held)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_drop_held)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.drop_l_hand()
	Tar.drop_r_hand()

UI_ACT(/datum/eventkit/player_effects, "list_all", ui_act_list_all)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_list_all)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	Tar.get_equipped_items()

UI_ACT(/datum/eventkit/player_effects, "give_item", ui_act_give_item)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_give_item)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	if(!check_rights_for(ui.user.client, R_HOLDER))
		return
	var/obj/item/X = ui.user.client.holder.marked_datum()
	if(!istype(X))
		return
	Tar.put_in_hands(X)

UI_ACT(/datum/eventkit/player_effects, "equip_item", ui_act_equip_item)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_equip_item)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	if(!check_rights_for(ui.user.client, R_HOLDER))
		return
	var/obj/item/X = ui.user.client.holder.marked_datum()
	if(!istype(X))
		return
	if(Tar.equip_to_appropriate_slot(X))
		return
	else
		Tar.equip_to_storage(X)

////////ADMIN//////////////

UI_ACT(/datum/eventkit/player_effects, "quick_nif", ui_act_quick_nif)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_quick_nif)
	var/mob/living/carbon/human/Tar = target()
	if(!istype(Tar))
		return
	var/input_NIF
	if(!Tar.get_organ(BP_HEAD))
		to_chat(ui.user,span_warning("Target is unsuitable."))
		return
	if(Tar.nif)
		to_chat(ui.user,span_warning("Target already has a NIF."))
		return
	if(Tar.species.flags & NO_DNA)
		var/obj/item/nif/S = /obj/item/nif/bioadap
		input_NIF = initial(S.name)
		new /obj/item/nif/bioadap(Tar)
	else
		var/list/NIF_types = typesof(/obj/item/nif)
		var/list/NIFs = list()

		for(var/NIF_type in NIF_types)
			var/obj/item/nif/S = NIF_type
			NIFs[capitalize(initial(S.name))] = NIF_type

		var/list/show_NIFs = sortList(NIFs) // the list that will be shown to the user to pick from

		var/_answer_a27 = act_ask(ui.user, action, params, ui, "a27", /datum/om/prompt/choice, message = "Pick the NIF type", title = "Quick NIF", choices = show_NIFs)
		if(isnull(_answer_a27))
			return
		input_NIF = _answer_a27
		var/chosen_NIF = NIFs[capitalize(input_NIF)]

		if(chosen_NIF)
			new chosen_NIF(Tar)
		else
			new /obj/item/nif(Tar)
	log_and_message_admins("Quick NIF'd [Tar.real_name] with a [input_NIF].", ui.user)

UI_ACT(/datum/eventkit/player_effects, "resize", ui_act_resize)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_resize)
	SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/resize, target())

UI_ACT(/datum/eventkit/player_effects, "teleport", ui_act_teleport)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_teleport)
	var/where = act_ask(ui.user, action, params, ui, "a28", /datum/om/prompt/choice/alert, message = "Where to teleport?", title = "Where?", choices = list("To Me", "To Mob", "To Area", "Cancel"))
	if(isnull(where))
		return
	if(where == "Cancel")
		return
	if(where == "To Me")
		SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/Getmob, target())
	if(where == "To Mob")
		var/mob/selection = act_ask(ui.user, action, params, ui, "a29", /datum/om/prompt/choice, message = "Select a mob to jump [target()] to:", title = "Jump to mob", choices = REGISTRY_MEMBERS(REGISTRY_MOBS))
		if(isnull(selection))
			return
		target().on_mob_jump()
		target().forceMove(get_turf(selection))
		log_admin("[key_name(ui.user)] jumped [target()] to [selection]")
	if(where == "To Area")
		var/area/A
		var/_answer_a30 = act_ask(ui.user, action, params, ui, "a30", /datum/om/prompt/choice, message = "Pick an area to teleport [target()] to:", title = "Jump to Area", choices = return_sorted_areas())
		if(isnull(_answer_a30))
			return
		A = _answer_a30
		target().on_mob_jump()
		target().forceMove(pick(get_area_turfs(A)))
		log_admin("[key_name(ui.user)] jumped [target()] to [A]")

UI_ACT(/datum/eventkit/player_effects, "gib", ui_act_gib)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_gib)
	var/death = act_ask(ui.user, action, params, ui, "a31", /datum/om/prompt/choice/alert, message = "Are you sure you want to destroy [target()]?", title = "Gib?", choices = list("KILL", "Cancel"))
	if(isnull(death))
		return
	if(death == "KILL")
		target().gib()

UI_ACT(/datum/eventkit/player_effects, "dust", ui_act_dust)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_dust)
	var/death = act_ask(ui.user, action, params, ui, "a32", /datum/om/prompt/choice/alert, message = "Are you sure you want to destroy [target()]?", title = "Dust?", choices = list("KILL", "Cancel"))
	if(isnull(death))
		return
	if(death == "KILL")
		target().dust()

UI_ACT(/datum/eventkit/player_effects, "paralyse", ui_act_paralyse)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_paralyse)
	if(!isliving(target()))
		return
	SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/paralyze_mob, target())

UI_ACT(/datum/eventkit/player_effects, "subtle_message", ui_act_subtle_message)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_subtle_message)
	SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/cmd_admin_subtle_message, target())

UI_ACT(/datum/eventkit/player_effects, "direct_narrate", ui_act_direct_narrate)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_direct_narrate)
	SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/cmd_admin_direct_narrate, target())

UI_ACT(/datum/eventkit/player_effects, "player_panel", ui_act_player_panel)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_player_panel)
	SSadmin_verbs.dynamic_invoke_verb(ui.user.client, /datum/admin_verb/show_player_panel, target())

UI_ACT(/datum/eventkit/player_effects, "view_variables", ui_act_view_variables)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_view_variables)
	ui.user.client.debug_variables(target())

UI_ACT(/datum/eventkit/player_effects, "orbit", ui_act_orbit)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_orbit)
	if(!ui.user.client.holder.marked_datum())
		return
	var/atom/movable/X = ui.user.client.holder.marked_datum()
	X.orbit(target())

UI_ACT(/datum/eventkit/player_effects, "ai", ui_act_ai)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_ai)
	if(!isliving(target()))
		to_chat(ui.user, span_notice("This can only be used on instances of type /mob/living"))
		return
	var/mob/living/L = target()
	if(L.client || L.teleop)
		to_chat(ui.user, span_warning("This cannot be used on player mobs!"))
		return

	// Everything is asked first: the answers re-run this action, so nothing changes until the last one.
	var/faction = act_ask(ui.user, action, params, ui, "a33", /datum/om/prompt/text, message = "Please input AI faction", title = "AI faction", default = "neutral")
	if(isnull(faction))
		return
	var/stance = act_ask(ui.user, action, params, ui, "a34", /datum/om/prompt/choice, message = "Please choose AI combat mode", title = "AI combat mode", choices = list(I_HURT, I_HELP))
	if(isnull(stance))
		return
	var/wake = act_ask(ui.user, action, params, ui, "a35", /datum/om/prompt/choice/alert, message = "Make mob wake up? This is needed for carbon mobs.", title = "Wake mob?", choices = list("Yes", "No"))
	if(isnull(wake))
		return
	if(L.ai_brain)	//Cleaning up the original ai
		var/datum/ai_brain/old_brain = L.ai_brain
		L.ai_brain = null
		qdel(old_brain)	//Only way I could make #TESTING - Unable to be GC'd to stop. del() logs show it works.
	L.initialize_ai_brain()
	L.faction = faction
	if(stance)
		L.set_use_stance(stance)
	if(wake == "Yes")
		L.status_adjust(EFFECT_SLEEPING, -100)

UI_ACT(/datum/eventkit/player_effects, "cloaking", ui_act_cloaking)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_cloaking)
	if(dq_get_cloaked(target()))
		target().uncloak()
	else if(!dq_get_cloaked(target()))
		target().cloak()

UI_ACT(/datum/eventkit/player_effects, "give_quest", ui_act_give_quest)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_give_quest)
	if(!target())
		return
	var/admin_quest =  act_ask(ui.user, action, params, ui, "a36", /datum/om/prompt/choice/alert, message = "Do you want to give a random quest or a personalised one?", title = "Quest!", choices = list("Random", "Personalised", "Cancel"))
	if(isnull(admin_quest))
		return
	if(!admin_quest || (admin_quest == "Cancel"))
		return
	if(admin_quest == "Personalised")
		var/specific_quest = act_ask(ui.user, action, params, ui, "a37", /datum/om/prompt/text, message = "What is their quest?", title = "Quest!!!")
		if(isnull(specific_quest))
			return
		if(!specific_quest)
			return
		quest_from_above(target(), specific_quest)
	else
		quest_from_above(target())

////////FIXES//////////////

UI_ACT(/datum/eventkit/player_effects, "rejuvenate", ui_act_rejuvenate)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_rejuvenate)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	Tar.rejuvenate()

UI_ACT(/datum/eventkit/player_effects, "popup-box", ui_act_popup_box)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_popup_box)
	var/message = act_ask(ui.user, action, params, ui, "a38", /datum/om/prompt/text, message = "Write a message to send to the user with a space for them to reply without using the text box:", title = "Message")
	if(isnull(message))
		return
	if(!message)
		return
	log_admin("[key_name(ui.user)] sent message to [target()]: [message]")
	// The player answers in their own time; the reply doesn't need this panel open.
	om_ask(target(), /datum/om/prompt/text/admin_popup, PROC_REF(popup_replied), message = "An admin has sent you a message: [message]", admin_name = key_name(ui.user))

UI_ACT(/datum/eventkit/player_effects, "stop-orbits", ui_act_stop_orbits)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_stop_orbits)
	target().stop_orbiters()

UI_ACT(/datum/eventkit/player_effects, "revert-mob-tf", ui_act_revert_mob_tf)
UI_ACT_PROC(/datum/eventkit/player_effects, ui_act_revert_mob_tf)
	var/mob/living/Tar = target()
	if(!istype(Tar))
		return
	Tar.revert_mob_tf()

/// LC-refs: The target of the effects -- an OM handle (om_handle()), so it reads null once that is deleted.
/datum/eventkit/player_effects/proc/target() as /mob
	return om_resolve(target_handle)
