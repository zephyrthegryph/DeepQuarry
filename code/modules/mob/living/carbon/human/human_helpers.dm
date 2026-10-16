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
	for(var/obj/item/clothing/C in contents_of(src))
		if(item_is_in_hands(C))
			continue
		if(worn_of(C).covers & HEAD)
			coverage += list(organs_by_name[BP_HEAD])
		if(worn_of(C).covers & UPPER_TORSO)
			coverage += list(organs_by_name[BP_TORSO])
		if(worn_of(C).covers & LOWER_TORSO)
			coverage += list(organs_by_name[BP_GROIN])
		if(worn_of(C).covers & LEGS)
			coverage += list(organs_by_name[BP_L_LEG], organs_by_name[BP_R_LEG])
		if(worn_of(C).covers & ARMS)
			coverage += list(organs_by_name[BP_R_ARM], organs_by_name[BP_L_ARM])
		if(worn_of(C).covers & FEET)
			coverage += list(organs_by_name[BP_L_FOOT], organs_by_name[BP_R_FOOT])
		if(worn_of(C).covers & HANDS)
			coverage += list(organs_by_name[BP_L_HAND], organs_by_name[BP_R_HAND])
	return coverage


//This is called when we want different types of 'cloaks' to stop working, e.g. when attacking.
/mob/living/carbon/human/break_cloak()
	var/datum/changeling/comp = is_changeling(src)
	if(comp) //Changeling visible camo
		comp.cloaked = 0
	if(istype(get_equipped_item(SLOT_ID_BACK), /obj/item/rig)) //Ninja cloak
		var/obj/item/rig/suit = get_equipped_item(SLOT_ID_BACK)
		for(var/obj/item/rig_module/stealth_field/cloaker in suit.installed_modules)
			if(cloaker.active)
				cloaker.deactivate()
	for(var/obj/item/deadringer/dr in contents_of(src))
		dr.uncloak()

/mob/living/carbon/human/is_cloaked()
	var/datum/changeling/comp = is_changeling(src)
	if(comp && comp.cloaked) // Ling camo.
		return TRUE
	else if(istype(get_equipped_item(SLOT_ID_BACK), /obj/item/rig)) //Ninja cloak
		var/obj/item/rig/suit = get_equipped_item(SLOT_ID_BACK)
		for(var/obj/item/rig_module/stealth_field/cloaker in suit.installed_modules)
			if(cloaker.active)
				return TRUE
	for(var/obj/item/deadringer/dr in contents_of(src))
		if(dr.timer > 20)
			return TRUE
	return ..()

/mob/living/carbon/human/get_ear_protection()
	var/sum = 0
	if(istype(get_equipped_item(SLOT_ID_EAR_L), /obj/item/clothing/ears))
		var/obj/item/clothing/ears/L = get_equipped_item(SLOT_ID_EAR_L)
		sum += L.ear_protection
	if(istype(get_equipped_item(SLOT_ID_EAR_R), /obj/item/clothing/ears))
		var/obj/item/clothing/ears/R = get_equipped_item(SLOT_ID_EAR_R)
		sum += R.ear_protection
	if(istype(get_equipped_item(SLOT_ID_HEAD), /obj/item/clothing/head))
		var/obj/item/clothing/head/H = get_equipped_item(SLOT_ID_HEAD)
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

// Cosmetic chassis model (the torso manufacturer) of a full-body prosthesis,
// or null. Data for icons, blood colour and speech bubbles; NOT a biology
// question (use HAS_SYNTHETIC_BIOLOGY() / biology() for that).
/mob/living/carbon/human/proc/robolimb_model()
	return synthetic

// Would an onlooker know this person is synthetic?
// Based on sort of logical reasoning, 'Look at head, look at torso'
/mob/living/carbon/human/proc/looksSynthetic()
	var/obj/item/organ/external/T = organs_by_name[BP_TORSO]
	var/obj/item/organ/external/H = organs_by_name[BP_HEAD]

	//Look at their head
	if(!get_equipped_item(SLOT_ID_HEAD) || !(get_equipped_item(SLOT_ID_HEAD) && (worn_of(get_equipped_item(SLOT_ID_HEAD)).hides & HIDEFACE)))
		if(H && H.robotic == ORGAN_ROBOT) //Exactly robotic, not higher as lifelike is higher
			return 1

	//Look at their torso
	if(!get_equipped_item(SLOT_ID_SUIT) || (get_equipped_item(SLOT_ID_SUIT) && !(worn_of(get_equipped_item(SLOT_ID_SUIT)).hides & HIDEJUMPSUIT)))
		if(!get_equipped_item(SLOT_ID_UNIFORM) || (get_equipped_item(SLOT_ID_UNIFORM) && !(worn_of(get_equipped_item(SLOT_ID_UNIFORM)).covers & UPPER_TORSO)))
			if(T && T.robotic == ORGAN_ROBOT)
				return 1

	return 0

// Returns a string based on what kind of brain the FBP has.
/mob/living/carbon/human/proc/get_FBP_type()
	if(!HAS_SYNTHETIC_BIOLOGY(src))
		return FBP_NONE
	var/obj/item/organ/internal/brain/B
	B = organ_in(O_BRAIN)
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
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud_med, src, "100", plane = PLANE_CH_HEALTH), HEALTH_HUD)
	if(HAS_SYNTHETIC_BIOLOGY(src))
		rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudrobo", plane = PLANE_CH_STATUS), STATUS_HUD)
		rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudrobo", plane = PLANE_CH_LIFE), LIFE_HUD)
	else
		rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudhealthy", plane = PLANE_CH_STATUS), STATUS_HUD)
		rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudhealthy", plane = PLANE_CH_LIFE), LIFE_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(using_map.id_hud_icons, src, "hudunknown", plane = PLANE_CH_ID), ID_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_WANTED), WANTED_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_IMPLOYAL), IMPLOYAL_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_IMPCHEM), IMPCHEM_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_IMPTRACK), IMPTRACK_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudblank", plane = PLANE_CH_SPECIAL), SPECIALROLE_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud, src, "hudhealthy", plane = PLANE_CH_STATUS_OOC), STATUS_HUD_OOC)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud_med_vr, src, "100", plane = PLANE_CH_HEALTH_VR), HEALTH_VR_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud_vr, src, "hudblank", plane = PLANE_CH_STATUS_R), STATUS_R_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud_vr, src, "hudblank", plane = PLANE_CH_BACKUP), BACKUP_HUD)
	rel_add(src, nameof(hud_list), gen_hud_image(GLOB.ingame_hud_vr, src, "hudblank", plane = PLANE_CH_VANTAG), VANTAG_HUD)
	add_overlay(hud_list)

/mob/living/carbon/human/recalculate_vis()
	PUBLISH_CHANGE(src, MOB_KEY_VIEW) // vision gear toggled: the sight and HUD reactions re-read it
	if(!hud_used?.vis_enabled || !hud_used?.plane_holder)
		return

	//These things are allowed to add vision flags.
	//If you code some crazy item that goes on your feet that lets you see ghosts, you need to add a slot here.
	var/static/list/slots = list(SLOT_ID_EYES,SLOT_ID_HEAD)
	var/list/compiled_vis = list()

	if(factor(BF_DARKSIGHT)) //Putting this near the beginning so it can be overwritten by equipment
		compiled_vis += VIS_FULLBRIGHT

	for(var/slot in slots)
		var/obj/item/clothing/O = get_equipped_item(slot) //Change this type if you move the vision stuff to item or something.
		if(istype(O) && O.enables_planes && (slot in O.plane_slots))
			compiled_vis |= O.enables_planes

	//Check to see if we have a rig (ugh, blame rigs, desnowflake this)
	var/obj/item/rig/rig = get_rig()
	if(istype(rig) && rig.visor)
		if(!rig.helmet || (get_equipped_item(SLOT_ID_HEAD) && rig.helmet == get_equipped_item(SLOT_ID_HEAD)))
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

	if(!compiled_vis.len && !hud_used?.vis_enabled?.len)
		return //Nothin' doin'.

	var/list/oddities = hud_used?.vis_enabled ^ compiled_vis
	if(!oddities.len)
		return //Same thing in both lists!

	var/list/to_enable = oddities - hud_used?.vis_enabled
	var/list/to_disable = oddities - compiled_vis

	for(var/vis in to_enable)
		hud_used?.plane_holder?.set_vis(vis,TRUE)
		hud_used?.vis_enabled += vis
	for(var/vis in to_disable)
		hud_used?.plane_holder?.set_vis(vis,FALSE)
		hud_used?.vis_enabled -= vis

/mob/living/carbon/human/get_restraining_bolt()
	var/obj/item/implant/restrainingbolt/RB

	for(var/obj/item/organ/external/EX in organs)
		RB = locate_in_list(EX, /obj/item/implant/restrainingbolt)
		if(istype(RB) && !(RB.malfunction))
			break

	if(RB)
		if(!RB.malfunction)
			return TRUE

	return FALSE

#undef HUMAN_EATING_NO_ISSUE
#undef HUMAN_EATING_NO_MOUTH
#undef HUMAN_EATING_BLOCKED_MOUTH


GLOBAL_DATUM_INIT(ingame_hud_vr, /icon, icon('icons/mob/hud_vr.dmi'))
GLOBAL_DATUM_INIT(ingame_hud_med_vr, /icon, icon('icons/mob/hud_med_vr.dmi'))

/mob/living/carbon/human/proc/remove_marking(datum/sprite_accessory/marking/mark_datum)
	if (!mark_datum)
		return FALSE
	var/successful = FALSE
	for(var/BP in mark_datum.body_parts)
		var/obj/item/organ/external/O = organs_by_name[BP]
		if(O && (mark_datum.name in O.markings))
			O.remove_markings(mark_datum.name)
			successful = TRUE
	if (successful)
		markings_len -= 1
		update_dna()
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
			O.set_markings_at(mark_datum.name, list("color" = mark_color, "datum" = mark_datum, "priority" = markings_len + 1, "on" = TRUE))
	if (success)
		markings_len += 1
		update_dna()
	return success

/mob/living/carbon/human/proc/change_priority_of_marking(datum/sprite_accessory/marking/mark_datum, move_down, swap = TRUE) //move_down should be true/false
	if (!mark_datum)
		return FALSE
	var/change = move_down ? 1 : -1
	var/success = FALSE
	for(var/BP in mark_datum.body_parts)
		var/obj/item/organ/external/O = organs_by_name[BP]
		if(O)
			var/index = LAZYFIND(O.markings, mark_datum.name)
			if (!index)
				continue
			var/change_from = O.markings[mark_datum.name]["priority"]
			if (change_from == clamp(change_from + change, 1, markings_len))
				continue
			if (!success)
				success = TRUE
				change_priority_marking_to_priority(change_from + change, change_from)
			O.markings[mark_datum.name]["priority"] = clamp(change_from + change, 1, markings_len)
			tracked_changed(O, nameof(O.markings))
			if ((move_down && index == O.markings.len) || (!move_down && index == 1))
				continue
			if (O.markings[O.markings[index + change]]["priority"] == change_from)
				moveElement(O.markings, index, index+(move_down ? 2 : -1))
				tracked_changed(O, nameof(O.markings))
	if (success)
		update_dna()
	return TRUE

/mob/living/carbon/human/proc/change_priority_marking_to_priority(priority, to_priority)
	for (var/obj/item/organ/external/O in organs)
		for (var/marking in O.markings)
			if (O.markings[marking]["priority"] == priority)
				O.markings[marking]["priority"] = to_priority
				tracked_changed(O, nameof(O.markings))

/mob/living/carbon/human/proc/change_marking_color(datum/sprite_accessory/marking/mark_datum, mark_color = "#000000")
	if (!mark_datum)
		return FALSE
	var/success = FALSE
	for(var/BP in mark_datum.body_parts)
		var/obj/item/organ/external/O = organs_by_name[BP]
		if(O && LAZYACCESS(O.markings, mark_datum.name) && O.markings[mark_datum.name]["color"] != mark_color)
			success = TRUE
			O.markings[mark_datum.name]["color"] = mark_color
			tracked_changed(O, nameof(O.markings))
	if (success)
		update_dna()
	return success

/mob/living/carbon/human/proc/get_prioritised_markings()
	var/list/markings = list()
	var/list/priorities = list()
	for(var/obj/item/organ/external/O in organs)
		var/limb_tag = O.organ_tag
		if(O.markings?.len)
			for (var/marking in O.markings)
				var/priority = num2text(O.markings[marking]["priority"])
				if (markings[priority])
					if (markings[priority][marking])
						markings[priority][marking] |= list(limb_tag = list("on" = O.markings[marking]["on"], "color" = O.markings[marking]["color"]))
					else
						markings[priority] |= list("[marking]" = list(limb_tag = list("on" = O.markings[marking]["on"], "color" = O.markings[marking]["color"]))) //yes I know technically you could have a limb that was attached that has the same marking as another limb with a different color but I'm too tired
				else
					priorities |= O.markings[marking]["priority"]
					markings[priority] = list("[marking]" = list(limb_tag = list("on" = O.markings[marking]["on"], "color" = O.markings[marking]["color"])))
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
	markings_len = sorted.len
	//todo - add an autofixing thing for having markings with the same priorities as another, and for having markings that should have the same priorities across bodyparts, but don't
	//does not really need to happen, that kinda thing will only happen when putting another person's limb onto your own body
	return sorted

/// What transform_into_other_human() copies besides appearance (P2-F6).
/datum/human_transform_options
	/// Take the target's name and nickname.
	var/copy_name = FALSE
	/// Take the target's flavour text.
	var/copy_flavour = TRUE
	/// Rebuild our limbs as prostheses matching the target (proteans).
	var/convert_to_prosthetics = FALSE
	/// Take the target's blood type. An incompatible type kills on transfusion.
	var/apply_bloodtype = TRUE

/datum/human_transform_options/New(copy_name = FALSE, copy_flavour = TRUE, convert_to_prosthetics = FALSE, apply_bloodtype = TRUE)
	..()
	src.copy_name = copy_name
	src.copy_flavour = copy_flavour
	src.convert_to_prosthetics = convert_to_prosthetics
	src.apply_bloodtype = apply_bloodtype

/// Take `character`'s appearance: identity, colours, appendages, markings, physique and
/// custom species text. `options` (a /datum/human_transform_options, default when null)
/// says what else is copied.
/mob/living/carbon/human/proc/transform_into_other_human(mob/living/carbon/human/character, datum/human_transform_options/options)
	if(!options)
		options = new /datum/human_transform_options
	if(options.copy_name)
		name = character.name
		bio.nickname = character.bio.nickname
	set_gender(character.gender)
	set_identifying_gender(character.identifying_gender)

	record_copy(looks, character.looks)
	if(options.apply_bloodtype)
		dna?.b_type = character.dna ? character.dna.b_type : DEFAULT_BLOOD_TYPE
	copy_appendages_from(character)

	var/bodytype = character.species?.get_bodytype()
	if(options.convert_to_prosthetics)
		convert_limbs_to_prosthetics_like(character, bodytype)

	for(var/N in character.organs_by_name)
		var/obj/item/organ/external/O = organs_by_name[N]
		var/obj/item/organ/external/I = character.organs_by_name[N]
		O.set_markings(I.markings?.Copy())
	markings_len = character.markings_len

	if(options.copy_flavour)
		bio.flavor_texts = character.bio.flavor_texts?.Copy()

	copy_physique_from(character)
	if(species)
		rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
	species?.blood_color = character.species?.blood_color

	dna?.base_species = bodytype
	species?.set_base_species(bodytype)
	species?.vanity_base_fit = bodytype
	if(istype(species, /datum/species/shapeshifter))
		set_wrapped_bodytype(bodytype)

	custom_species	= character.custom_species
	bio.custom_say = character.bio.custom_say
	bio.custom_ask = character.bio.custom_ask
	bio.custom_whisper = character.bio.custom_whisper
	bio.custom_exclaim = character.bio.custom_exclaim

	dna?.ResetUIFrom(src)
	force_update_limbs()

/// Ears, tail and wings with their colours.
/mob/living/carbon/human/proc/copy_appendages_from(mob/living/carbon/human/character)
	rel_set(src, nameof(ear_style), character.ear_style)
	looks.set_ears_color(character.looks.ears_color)
	looks.set_ears_color2(character.looks.ears_color2)
	looks.set_ears_color3(character.looks.ears_color3)
	looks.set_ears_alpha(character.looks.ears_alpha)

	rel_set(src, nameof(ear_secondary_style), character.ear_secondary_style)
	set_ear_secondary_colors(character.ear_secondary_colors)

	rel_set(src, nameof(tail_style), character.tail_style)
	looks.set_tail_color(character.looks.tail_color)
	looks.set_tail_color2(character.looks.tail_color2)
	looks.set_tail_color3(character.looks.tail_color3)
	looks.set_tail_alpha(character.looks.tail_alpha)

	rel_set(src, nameof(wing_style), character.wing_style)
	looks.set_wing_color(character.looks.wing_color)
	looks.set_wing_color2(character.looks.wing_color2)
	looks.set_wing_color3(character.looks.wing_color3)
	looks.set_wing_alpha(character.looks.wing_alpha)

/// Robotize our limbs to match `character`'s: its prosthetic models, else the DSI body for
/// `bodytype`. Parents go before children so a limb is never robotized under an organic parent.
/mob/living/carbon/human/proc/convert_limbs_to_prosthetics_like(mob/living/carbon/human/character, bodytype)
	var/list/organs_to_edit = list()
	for (var/name in list(BP_TORSO, BP_HEAD, BP_GROIN, BP_L_ARM, BP_R_ARM, BP_L_HAND, BP_R_HAND, BP_L_LEG, BP_R_LEG, BP_L_FOOT, BP_R_FOOT))
		var/obj/item/organ/external/O = character.organs_by_name[name]
		if (O)
			var/x = organs_to_edit.Find(O.parent_organ)
			if (x == 0)
				organs_to_edit += name
			else
				organs_to_edit.Insert(x+(O.is_nanoform() ? 1 : 0), name)
	for(var/name in organs_to_edit)
		var/obj/item/organ/external/I = character.organs_by_name[name]
		var/obj/item/organ/external/O = organs_by_name[name]
		if(O)
			if(I.is_robotic())
				O.robotize(I.model)
			else
				var/dsi_company = GLOB.dsi_to_species[bodytype]
				if (!dsi_company)
					dsi_company = "DSI - Adaptive"
				O.robotize(dsi_company)

/// Weight, size, voice and sprite offsets.
/mob/living/carbon/human/proc/copy_physique_from(mob/living/carbon/human/character)
	weight			= character.weight
	vore_options.set_weight_gain(character.vore_options.weight_gain)
	vore_options.set_weight_loss(character.vore_options.weight_loss)
	set_fuzzy(character.fuzzy)
	set_offset_override(character.offset_override)
	vore_options.set_voice_freq(character.vore_options.voice_freq)
	if (species && character.species)
		rel_private(src, nameof(species)) // per-mob change: never mutate the shared species
		species.micro_size_mod = character.species.micro_size_mod
		species.icon_scale_x = character.species.icon_scale_x
		species.icon_scale_y = character.species.icon_scale_y
		update_transform()
	resize(character.size_multiplier, animate = TRUE, ignore_prefs = TRUE)
	vore_options.set_voice_sounds_list(character.vore_options.voice_sounds_list)
