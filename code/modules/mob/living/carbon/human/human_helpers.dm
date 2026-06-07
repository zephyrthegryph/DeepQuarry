#define HUMAN_EATING_NO_ISSUE		0
#define HUMAN_EATING_NO_MOUTH		1
#define HUMAN_EATING_BLOCKED_MOUTH	2

/mob/living/carbon/human/can_eat(food, feedback = 1)
	var/list/status = can_eat_status()
	if(status[1] == HUMAN_EATING_NO_ISSUE)
		return 1
	if(feedback)
		if(status[1] == HUMAN_EATING_NO_MOUTH)
			balloon_alert(src, "you don't have a mouth!")
		else if(status[1] == HUMAN_EATING_BLOCKED_MOUTH)
			balloon_alert(src, "\the [status[2]] is in the way!")
	return 0

/mob/living/carbon/human/can_force_feed(feeder, food, feedback = 1)
	var/list/status = can_eat_status()
	if(status[1] == HUMAN_EATING_NO_ISSUE)
		return 1
	if(feedback)
		if(status[1] == HUMAN_EATING_NO_MOUTH)
			balloon_alert(src, "\the [src] doesn't have a mouth!")
		else if(status[1] == HUMAN_EATING_BLOCKED_MOUTH)
			balloon_alert(feeder, "\the [status[2]] is in the way!")
	return 0

/mob/living/carbon/human/proc/can_eat_status()
	if(!check_has_mouth())
		return list(HUMAN_EATING_NO_MOUTH)
	var/obj/item/blocked = check_mouth_coverage()
	if(blocked)
		return list(HUMAN_EATING_BLOCKED_MOUTH, blocked)
	return list(HUMAN_EATING_NO_ISSUE)

/mob/living/carbon/human/proc/get_coverage()
	var/list/coverage = list()
	for(var/obj/item/clothing/C in src)
		if(item_is_in_hands(C))
			continue
		if(C.body_parts_covered & HEAD)
			coverage += list(organs_by_name[BP_HEAD])
		if(C.body_parts_covered & UPPER_TORSO)
			coverage += list(organs_by_name[BP_TORSO])
		if(C.body_parts_covered & LOWER_TORSO)
			coverage += list(organs_by_name[BP_GROIN])
		if(C.body_parts_covered & LEGS)
			coverage += list(organs_by_name[BP_L_LEG], organs_by_name[BP_R_LEG])
		if(C.body_parts_covered & ARMS)
			coverage += list(organs_by_name[BP_R_ARM], organs_by_name[BP_L_ARM])
		if(C.body_parts_covered & FEET)
			coverage += list(organs_by_name[BP_L_FOOT], organs_by_name[BP_R_FOOT])
		if(C.body_parts_covered & HANDS)
			coverage += list(organs_by_name[BP_L_HAND], organs_by_name[BP_R_HAND])
	return coverage


//This is called when we want different types of 'cloaks' to stop working, e.g. when attacking.
/mob/living/carbon/human/break_cloak()
	var/datum/component/antag/changeling/comp = is_changeling(src)
	if(comp) //Changeling visible camo
		comp.cloaked = 0
	if(istype(back, /obj/item/rig)) //Ninja cloak
		var/obj/item/rig/suit = back
		for(var/obj/item/rig_module/stealth_field/cloaker in suit.installed_modules)
			if(cloaker.active)
				cloaker.deactivate()
	for(var/obj/item/deadringer/dr in src)
		dr.uncloak()

/mob/living/carbon/human/is_cloaked()
	var/datum/component/antag/changeling/comp = is_changeling(src)
	if(comp && comp.cloaked) // Ling camo.
		return TRUE
	else if(istype(back, /obj/item/rig)) //Ninja cloak
		var/obj/item/rig/suit = back
		for(var/obj/item/rig_module/stealth_field/cloaker in suit.installed_modules)
			if(cloaker.active)
				return TRUE
	for(var/obj/item/deadringer/dr in src)
		if(dr.timer > 20)
			return TRUE
	return ..()

/mob/living/carbon/human/get_ear_protection()
	var/sum = 0
	if(istype(l_ear, /obj/item/clothing/ears))
		var/obj/item/clothing/ears/L = l_ear
		sum += L.ear_protection
	if(istype(r_ear, /obj/item/clothing/ears))
		var/obj/item/clothing/ears/R = r_ear
		sum += R.ear_protection
	if(istype(head, /obj/item/clothing/head))
		var/obj/item/clothing/head/H = head
		sum += H.ear_protection
	return sum

/mob/living/carbon/human/get_gender()
	return identifying_gender ? identifying_gender : gender

/mob/living/carbon/human/name_gender() /// Returns proper names for gender identites
	if(identifying_gender == "plural")
		return "other"
	if(identifying_gender == "neuter")
		return "none"
	else
		return get_gender()

// This is the 'mechanical' check for synthetic-ness, not appearance
// Returns the company that made the synthetic
/mob/living/carbon/human/isSynthetic()
	return synthetic

// Would an onlooker know this person is synthetic?
// Based on sort of logical reasoning, 'Look at head, look at torso'
/mob/living/carbon/human/proc/looksSynthetic()
	var/obj/item/organ/external/T = organs_by_name[BP_TORSO]
	var/obj/item/organ/external/H = organs_by_name[BP_HEAD]

	//Look at their head
	if(!head || !(head && (head.flags_inv & HIDEFACE)))
		if(H && H.robotic == ORGAN_ROBOT) //Exactly robotic, not higher as lifelike is higher
			return 1

	//Look at their torso
	if(!wear_suit || (wear_suit && !(wear_suit.flags_inv & HIDEJUMPSUIT)))
		if(!w_uniform || (w_uniform && !(w_uniform.body_parts_covered & UPPER_TORSO)))
			if(T && T.robotic == ORGAN_ROBOT)
				return 1

	return 0

// Returns a string based on what kind of brain the FBP has.
/mob/living/carbon/human/proc/get_FBP_type()
	if(!isSynthetic())
		return FBP_NONE
	var/obj/item/organ/internal/brain/B
	B = internal_organs_by_name[O_BRAIN]
	if(B) // Incase we lost our brain for some reason, like if we got decapped.
		if(istype(B, /obj/item/organ/internal/mmi_holder))
			var/obj/item/organ/internal/mmi_holder/mmi_holder = B
			if(istype(mmi_holder.stored_mmi, /obj/item/mmi/digital/posibrain))
				return FBP_POSI
			else if(istype(mmi_holder.stored_mmi, /obj/item/mmi/digital/robot))
				return FBP_DRONE
			else if(istype(mmi_holder.stored_mmi, /obj/item/mmi)) // This needs to come last because inheritence.
				return FBP_CYBORG

	return FBP_NONE

/mob/living/carbon/human/make_hud_overlays()
	hud_list[HEALTH_HUD]      = gen_hud_image(GLOB.ingame_hud_med, src, "100", plane = PLANE_CH_HEALTH)
	if(isSynthetic())
		hud_list[STATUS_HUD]  = gen_hud_image(GLOB.ingame_hud, src, "hudrobo", plane = PLANE_CH_STATUS)
		hud_list[LIFE_HUD]	  = gen_hud_image(GLOB.ingame_hud, src, "hudrobo", plane = PLANE_CH_LIFE)
	else
		hud_list[STATUS_HUD]  = gen_hud_image(GLOB.ingame_hud, src, "hudhealthy", plane = PLANE_CH_STATUS)
		hud_list[LIFE_HUD]    = gen_hud_image(GLOB.ingame_hud, src, "hudhealthy", plane = PLANE_CH_LIFE)
	hud_list[ID_HUD]          = gen_hud_image(using_map.id_hud_icons, src, "hudunknown", plane = PLANE_CH_ID)
	hud_list[WANTED_HUD]      = gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_WANTED)
	hud_list[IMPLOYAL_HUD]    = gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_IMPLOYAL)
	hud_list[IMPCHEM_HUD]     = gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_IMPCHEM)
	hud_list[IMPTRACK_HUD]    = gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_IMPTRACK)
	hud_list[SPECIALROLE_HUD] = gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_SPECIAL)
	hud_list[STATUS_HUD_OOC]  = gen_hud_image(GLOB.ingame_hud, src, "hudhealthy", plane = PLANE_CH_STATUS_OOC)
	hud_list[HEALTH_VR_HUD]   = gen_hud_image(GLOB.ingame_hud_med_vr, src, "100", plane = PLANE_CH_HEALTH_VR)
	hud_list[STATUS_R_HUD]    = gen_hud_image(GLOB.ingame_hud_vr, src, "hudblank", plane = PLANE_CH_STATUS_R)
	hud_list[BACKUP_HUD]      = gen_hud_image(GLOB.ingame_hud_vr, src, "hudblank", plane = PLANE_CH_BACKUP)
	hud_list[VANTAG_HUD]      = gen_hud_image(GLOB.ingame_hud_vr, src, "hudblank", plane = PLANE_CH_VANTAG)
	add_overlay(hud_list)

/mob/living/carbon/human/recalculate_vis()
	if(!vis_enabled || !plane_holder)
		return

	//These things are allowed to add vision flags.
	//If you code some crazy item that goes on your feet that lets you see ghosts, you need to add a slot here.
	var/list/slots = list(slot_glasses,slot_head)
	var/list/compiled_vis = list()

	if(CE_DARKSIGHT in chem_effects) //Putting this near the beginning so it can be overwritten by equipment
		compiled_vis += VIS_FULLBRIGHT

	for(var/slot in slots)
		var/obj/item/clothing/O = get_equipped_item(slot) //Change this type if you move the vision stuff to item or something.
		if(istype(O) && O.enables_planes && (slot in O.plane_slots))
			compiled_vis |= O.enables_planes

	//Check to see if we have a rig (ugh, blame rigs, desnowflake this)
	var/obj/item/rig/rig = get_rig()
	if(istype(rig) && rig.visor)
		if(!rig.helmet || (head && rig.helmet == head))
			if(rig.visor && rig.visor.vision && rig.visor.active && rig.visor.vision.glasses)
				var/obj/item/clothing/glasses/V = rig.visor.vision.glasses
				compiled_vis |= V.enables_planes

	if(nif)
		compiled_vis |= nif.planes_visible()
	//event hud
	if(vantag_hud)
		compiled_vis |= VIS_CH_VANTAG

	if(client?.prefs?.read_preference(/datum/preference/toggle/tummy_sprites))
		compiled_vis += VIS_CH_STOMACH

	if(soulgem?.flag_check(SOULGEM_SEE_SR_SOULS))
		compiled_vis += VIS_SOULCATCHER

	if(!compiled_vis.len && !vis_enabled.len)
		return //Nothin' doin'.

	var/list/oddities = vis_enabled ^ compiled_vis
	if(!oddities.len)
		return //Same thing in both lists!

	var/list/to_enable = oddities - vis_enabled
	var/list/to_disable = oddities - compiled_vis

	for(var/vis in to_enable)
		plane_holder.set_vis(vis,TRUE)
		vis_enabled += vis
	for(var/vis in to_disable)
		plane_holder.set_vis(vis,FALSE)
		vis_enabled -= vis

/mob/living/carbon/human/get_restraining_bolt()
	var/obj/item/implant/restrainingbolt/RB

	for(var/obj/item/organ/external/EX in organs)
		RB = locate() in EX
		if(istype(RB) && !(RB.malfunction))
			break

	if(RB)
		if(!RB.malfunction)
			return TRUE

	return FALSE

#undef HUMAN_EATING_NO_ISSUE
#undef HUMAN_EATING_NO_MOUTH
#undef HUMAN_EATING_BLOCKED_MOUTH


// === merged from human_helpers_vr.dm during hard-fork de-suffix (verified no override-order change) ===
GLOBAL_DATUM_INIT(ingame_hud_vr, /icon, icon('icons/mob/hud_vr.dmi'))
GLOBAL_DATUM_INIT(ingame_hud_med_vr, /icon, icon('icons/mob/hud_med_vr.dmi'))

/mob/living/carbon/human/proc/remove_marking(datum/sprite_accessory/marking/mark_datum)
	if (!mark_datum)
		return FALSE
	var/successful = FALSE
	for(var/BP in mark_datum.body_parts)
		var/obj/item/organ/external/O = organs_by_name[BP]
		if(O)
			successful = O.markings.Remove(mark_datum.name) || successful
	if (successful)
		markings_len -= 1
		update_dna()
		update_icons_body()
		return TRUE
	return FALSE

/mob/living/carbon/human/proc/add_marking(datum/sprite_accessory/marking/mark_datum, mark_color = "#000000")
	if (!mark_datum)
		return FALSE
	var/success = FALSE
	for(var/BP in mark_datum.body_parts)
		var/obj/item/organ/external/O = organs_by_name[BP]
		if(O)
			success = TRUE
			O.markings[mark_datum.name] = list("color" = mark_color, "datum" = mark_datum, "priority" = markings_len + 1, "on" = TRUE)
	if (success)
		markings_len += 1
		update_dna()
		update_icons_body()
	return success

/mob/living/carbon/human/proc/change_priority_of_marking(datum/sprite_accessory/marking/mark_datum, move_down, swap = TRUE) //move_down should be true/false
	if (!mark_datum)
		return FALSE
	var/change = move_down ? 1 : -1
	var/success = FALSE
	for(var/BP in mark_datum.body_parts)
		var/obj/item/organ/external/O = organs_by_name[BP]
		if(O)
			var/index = O.markings.Find(mark_datum.name)
			if (!index)
				continue
			var/change_from = O.markings[mark_datum.name]["priority"]
			if (change_from == clamp(change_from + change, 1, markings_len))
				continue
			if (!success)
				success = TRUE
				change_priority_marking_to_priority(change_from + change, change_from)
			O.markings[mark_datum.name]["priority"] = clamp(change_from + change, 1, markings_len)
			if ((move_down && index == O.markings.len) || (!move_down && index == 1))
				continue
			if (O.markings[O.markings[index + change]]["priority"] == change_from)
				moveElement(O.markings, index, index+(move_down ? 2 : -1))
	if (success)
		update_dna()
		update_icons_body()
	return TRUE

/mob/living/carbon/human/proc/change_priority_marking_to_priority(priority, to_priority)
	for (var/obj/item/organ/external/O in organs)
		for (var/marking in O.markings)
			if (O.markings[marking]["priority"] == priority)
				O.markings[marking]["priority"] = to_priority

/mob/living/carbon/human/proc/change_marking_color(datum/sprite_accessory/marking/mark_datum, mark_color = "#000000")
	if (!mark_datum)
		return FALSE
	var/success = FALSE
	for(var/BP in mark_datum.body_parts)
		var/obj/item/organ/external/O = organs_by_name[BP]
		if(O && O.markings[mark_datum.name] && O.markings[mark_datum.name]["color"] != mark_color)
			success = TRUE
			O.markings[mark_datum.name]["color"] = mark_color
	if (success)
		update_dna()
		update_icons_body()
	return success

/mob/living/carbon/human/proc/get_prioritised_markings()
	var/list/markings = list()
	var/list/priorities = list()
	for(var/obj/item/organ/external/O in organs)
		if(O.markings?.len)
			for (var/marking in O.markings)
				var/priority = num2text(O.markings[marking]["priority"])
				if (markings[priority])
					if (markings[priority][marking])
						markings[priority][marking] |= list(O.organ_tag = list("on" = O.markings[marking]["on"], "color" = O.markings[marking]["color"]))
					else
						markings[priority] |= list("[marking]" = list(O.organ_tag = list("on" = O.markings[marking]["on"], "color" = O.markings[marking]["color"]))) //yes I know technically you could have a limb that was attached that has the same marking as another limb with a different color but I'm too tired
				else
					priorities |= O.markings[marking]["priority"]
					markings[priority] = list("[marking]" = list(O.organ_tag = list("on" = O.markings[marking]["on"], "color" = O.markings[marking]["color"])))
	var/list/sorted = list()
	while (priorities.len > 0)
		var/priority = min(priorities)
		priorities.Remove(priority)
		priority = num2text(priority)
		for (var/marking in markings[priority])
			if (isnull(sorted[marking]))
				sorted[marking] = markings[priority][marking]
			else
				sorted[marking] |= markings[priority][marking]
	for (var/marking in sorted)
		var/should_add_color = TRUE
		var/last_color = null
		for (var/bp in sorted[marking])
			if (!isnull(last_color) && sorted[marking][bp]["color"] != last_color)
				should_add_color = FALSE
			last_color = sorted[marking][bp]["color"]
		if (should_add_color)
			sorted[marking]["color"] = last_color||"#000000"
	del(markings)
	del(priorities)
	markings_len = sorted.len
	//todo - add an autofixing thing for having markings with the same priorities as another, and for having markings that should have the same priorities across bodyparts, but don't
	//does not really need to happen, that kinda thing will only happen when putting another person's limb onto your own body
	return sorted

/mob/living/carbon/human/proc/transform_into_other_human(mob/living/carbon/human/character, copy_name, copy_flavour = TRUE, convert_to_prosthetics = FALSE, apply_bloodtype = TRUE)
	/*
	name, nickname, flavour, OOC notes
	gender, sex
	custom species name, custom bodytype, weight, scale, scaling center, sound type, sound freq
	custom say verbs
	ears, wings, tail, hair, facial hair
	ears colors, wings colors, tail colors
	body color, prosthetics (if they're a protean) (convert to DSI if protean and not prosthetic), eye color, hair color etc
	markings
	custom synth markings toggle, custom synth color toggle
	digitigrade
	blood color
	*/
	if (copy_name)
		name = character.name
		nickname = character.nickname
	gender = character.gender
	identifying_gender = character.identifying_gender

	r_eyes = character.r_eyes
	g_eyes = character.g_eyes
	b_eyes = character.b_eyes
	h_style = character.h_style
	r_hair = character.r_hair
	g_hair = character.g_hair
	b_hair = character.b_hair
	r_grad = character.r_grad
	g_grad = character.g_grad
	b_grad = character.b_grad
	f_style = character.f_style
	r_facial = character.r_facial
	g_facial = character.g_facial
	b_facial = character.b_facial
	r_skin = character.r_skin
	g_skin = character.g_skin
	b_skin = character.b_skin
	s_tone = character.s_tone
	h_style = character.h_style
	grad_style = character.grad_style
	f_style = character.f_style
	grad_style = character.grad_style
	if(apply_bloodtype)
		dna?.b_type = character.dna ? character.dna.b_type : DEFAULT_BLOOD_TYPE //This actually just straight up kills whoever uses it if the blood types aren't compatible on TF
	synth_color = character.synth_color
	r_synth = character.r_synth
	g_synth = character.g_synth
	b_synth = character.b_synth
	synth_markings = character.synth_markings

	ear_style = character.ear_style
	r_ears = character.r_ears
	b_ears = character.b_ears
	g_ears = character.g_ears
	r_ears2 = character.r_ears2
	b_ears2 = character.b_ears2
	g_ears2 = character.g_ears2
	r_ears3 = character.r_ears3
	b_ears3 = character.b_ears3
	g_ears3 = character.g_ears3
	a_ears = character.a_ears

	ear_secondary_style = character.ear_secondary_style
	ear_secondary_colors = character.ear_secondary_colors

	tail_style = character.tail_style
	r_tail = character.r_tail
	b_tail = character.b_tail
	g_tail = character.g_tail
	r_tail2 = character.r_tail2
	b_tail2 = character.b_tail2
	g_tail2 = character.g_tail2
	r_tail3 = character.r_tail3
	b_tail3 = character.b_tail3
	g_tail3 = character.g_tail3
	a_tail = character.a_tail

	wing_style = character.wing_style
	r_wing = character.r_wing
	b_wing = character.b_wing
	g_wing = character.g_wing
	r_wing2 = character.r_wing2
	b_wing2 = character.b_wing2
	g_wing2 = character.g_wing2
	r_wing3 = character.r_wing3
	b_wing3 = character.b_wing3
	g_wing3 = character.g_wing3
	a_wing = character.a_wing


	var/bodytype = character.species?.get_bodytype()

	if (convert_to_prosthetics) //should only really be run for proteans
		var/list/organs_to_edit = list()
		for (var/name in list(BP_TORSO, BP_HEAD, BP_GROIN, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT))
			var/obj/item/organ/external/O = character.organs_by_name[name]
			if (O)
				var/x = organs_to_edit.Find(O.parent_organ)
				if (x == 0)
					organs_to_edit += name
				else
					organs_to_edit.Insert(x+(O.robotic == ORGAN_NANOFORM ? 1 : 0), name)
		for(var/name in organs_to_edit)
			var/obj/item/organ/external/I = character.organs_by_name[name]
			var/obj/item/organ/external/O = organs_by_name[name]
			if(O)
				if(I.robotic >= ORGAN_ROBOT)
					O.robotize(I.model)
				else
					var/dsi_company = GLOB.dsi_to_species[bodytype]
					if (!dsi_company)
						dsi_company = "DSI - Adaptive"
					O.robotize(dsi_company)

	for(var/N in character.organs_by_name)
		var/obj/item/organ/external/O = organs_by_name[N]
		var/obj/item/organ/external/I = character.organs_by_name[N]
		O.markings = I.markings.Copy()

	markings_len = character.markings_len

	if (copy_flavour)
		flavor_texts = character.flavor_texts?.Copy()

	weight			= character.weight
	weight_gain		= character.weight_gain
	weight_loss		= character.weight_loss
	fuzzy				= character.fuzzy
	offset_override	= character.offset_override
	voice_freq		= character.voice_freq
	if (species && character.species)
		species.micro_size_mod = character.species.micro_size_mod
		species.icon_scale_x = character.species.icon_scale_x
		species.icon_scale_y = character.species.icon_scale_y
		update_transform()
	resize(character.size_multiplier, animate = TRUE, ignore_prefs = TRUE)
	voice_sounds_list = character.voice_sounds_list

	species?.blood_color = character.species?.blood_color

	dna?.base_species = bodytype
	species?.base_species = bodytype
	species?.vanity_base_fit = bodytype
	if (istype(species, /datum/species/shapeshifter))
		GLOB.wrapped_species_by_ref["\ref[src]"] = bodytype

	custom_species	= character.custom_species
	custom_say		= character.custom_say
	custom_ask		= character.custom_ask
	custom_whisper	= character.custom_whisper
	custom_exclaim	= character.custom_exclaim

	digitigrade = character.digitigrade

	dna?.ResetUIFrom(src)
	force_update_limbs()
	regenerate_icons()
