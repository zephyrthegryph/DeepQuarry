// This is something of an intermediary species used for species that
// need to emulate the appearance of another race. Currently it is only
// used for slimes but it may be useful for changelings later.
GLOBAL_LIST_EMPTY(wrapped_species_by_ref)

/datum/species/shapeshifter

	inherent_verbs = list(
		/mob/living/carbon/human/proc/shapeshifter_select_shape,
		/mob/living/carbon/human/proc/shapeshifter_select_hair,
		/mob/living/carbon/human/proc/shapeshifter_select_gender
		)

	var/list/valid_transform_species
	// var/default_form = SPECIES_HUMAN //

	base_species = SPECIES_HUMAN
	selects_bodytype = SELECTS_BODYTYPE_SHAPESHIFTER

/datum/species/shapeshifter/shared_table_vars()
	return ..() + "valid_transform_species"

/datum/species/shapeshifter/get_valid_shapeshifter_forms(mob/living/carbon/human/H)
	return list(vanity_base_fit)|valid_transform_species

/datum/species/shapeshifter/get_icobase(mob/living/carbon/human/H, get_deform)
	if(!H) return ..(null, get_deform)
	var/datum/species/S = GLOB.all_species[GLOB.wrapped_species_by_ref["\ref[H]"]]
	return S.get_icobase(H, get_deform)

/datum/species/shapeshifter/get_race_key(mob/living/carbon/human/H)
	return "[..()]-[GLOB.wrapped_species_by_ref["\ref[H]"]]"

/datum/species/shapeshifter/get_bodytype(mob/living/carbon/human/H)
	if(!H) return ..()
	var/datum/species/S = GLOB.all_species[GLOB.wrapped_species_by_ref["\ref[H]"]]
	return S.get_bodytype(H)

/datum/species/shapeshifter/get_blood_mask(mob/living/carbon/human/H)
	if(!H) return ..()
	var/datum/species/S = GLOB.all_species[GLOB.wrapped_species_by_ref["\ref[H]"]]
	return S.get_blood_mask(H)

/datum/species/shapeshifter/get_damage_mask(mob/living/carbon/human/H)
	if(!H) return ..()
	var/datum/species/S = GLOB.all_species[GLOB.wrapped_species_by_ref["\ref[H]"]]
	return S.get_damage_mask(H)

/datum/species/shapeshifter/get_damage_overlays(mob/living/carbon/human/H)
	if(!H) return ..()
	var/datum/species/S = GLOB.all_species[GLOB.wrapped_species_by_ref["\ref[H]"]]
	return S.get_damage_overlays(H)

/datum/species/shapeshifter/get_tail(mob/living/carbon/human/H)
	if(!H) return ..()
	var/datum/species/S = GLOB.all_species[GLOB.wrapped_species_by_ref["\ref[H]"]]
	return S.get_tail(H)

/datum/species/shapeshifter/get_tail_animation(mob/living/carbon/human/H)
	if(!H) return ..()
	var/datum/species/S = GLOB.all_species[GLOB.wrapped_species_by_ref["\ref[H]"]]
	return S.get_tail_animation(H)

/datum/species/shapeshifter/get_tail_hair(mob/living/carbon/human/H)
	if(!H) return ..()
	var/datum/species/S = GLOB.all_species[GLOB.wrapped_species_by_ref["\ref[H]"]]
	return S.get_tail_hair(H)

/datum/species/shapeshifter/handle_post_spawn(mob/living/carbon/human/H)
	..()
	GLOB.wrapped_species_by_ref["\ref[H]"] = base_species

	for(var/obj/item/organ/external/E in H.organs)
		E.sync_colour_to_human(H)

// Verbs follow.
/mob/living/carbon/human/proc/shapeshifter_select_hair()

	set name = "Select Hair"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 10

	var/list/valid_hairstyles = list()
	var/list/valid_facialhairstyles = list()
	var/list/valid_gradstyles = GLOB.hair_gradients
	for(var/hairstyle in GLOB.hair_styles_list)
		var/datum/sprite_accessory/S = GLOB.hair_styles_list[hairstyle]
		if(S.name == DEVELOPER_WARNING_NAME)
			continue
		if(gender == MALE && S.gender == FEMALE)
			continue
		if(gender == FEMALE && S.gender == MALE)
			continue
		if(!(species.get_bodytype(src) in S.species_allowed))
			continue
		if(!S.can_be_selected && (!client || !check_rights_for(client, R_HOLDER)))
			continue
		valid_hairstyles += hairstyle
	for(var/facialhairstyle in GLOB.facial_hair_styles_list)
		var/datum/sprite_accessory/S = GLOB.facial_hair_styles_list[facialhairstyle]
		if(S.name == DEVELOPER_WARNING_NAME)
			continue
		if(gender == MALE && S.gender == FEMALE)
			continue
		if(gender == FEMALE && S.gender == MALE)
			continue
		if(!(species.get_bodytype(src) in S.species_allowed))
			continue
		if(!S.can_be_selected && (!client || !check_rights_for(client, R_HOLDER)))
			continue
		valid_facialhairstyles += facialhairstyle


	visible_message(span_notice("\The [src]'s form contorts subtly."))
	// A cancel picks none (bald, no gradient, shaved).
	om_prompt_sequence(src, src, list(
		valid_hairstyles.len ? list("key" = "hair", "kind" = "list", "message" = "Select a hairstyle.", "title" = "Shapeshifter Hair", "choices" = valid_hairstyles, "optional" = TRUE) : null,
		valid_gradstyles.len ? list("key" = "gradient", "kind" = "list", "message" = "Select a hair gradient style.", "title" = "Shapeshifter Hair", "choices" = valid_gradstyles, "optional" = TRUE) : null,
		valid_facialhairstyles.len ? list("key" = "facial", "kind" = "list", "message" = "Select a facial hair style.", "title" = "Shapeshifter Hair", "choices" = valid_facialhairstyles, "optional" = TRUE) : null,
	), PROC_REF(shapeshifter_hair_chosen), list("requires" = PROMPT_CONSCIOUS, "data" = list("has_hair" = valid_hairstyles.len, "has_gradient" = valid_gradstyles.len, "has_facial" = valid_facialhairstyles.len)))

/mob/living/carbon/human/proc/shapeshifter_hair_chosen(mob/user, datum/om/prompt/ask)
	if(ask.get("has_hair"))
		change_hair(ask.get("hair") || "Bald")
	if(ask.get("has_gradient"))
		change_hair_gradient(ask.get("gradient") || "None")
	if(ask.get("has_facial"))
		change_facial_hair(ask.get("facial") || "Shaved")

/mob/living/carbon/human/proc/shapeshifter_select_gender()

	set name = "Select Gender"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 50

	om_prompt_sequence(src, src, list(
		list("key" = "gender", "kind" = "list", "message" = "Please select a gender.", "title" = "Shapeshifter Gender", "choices" = list(FEMALE, MALE, NEUTER, PLURAL)),
		list("key" = "identity", "kind" = "list", "message" = "Please select a gender Identity.", "title" = "Shapeshifter Gender Identity", "choices" = list(FEMALE, MALE, NEUTER, PLURAL, HERM)),
	), PROC_REF(shapeshifter_gender_chosen), list("requires" = PROMPT_CONSCIOUS))

/mob/living/carbon/human/proc/shapeshifter_gender_chosen(mob/user, datum/om/prompt/ask)
	visible_message(span_notice("\The [src]'s form contorts subtly."))
	change_gender(ask.get("gender"))
	change_gender_identity(ask.get("identity"))

/mob/living/carbon/human/proc/shapeshifter_select_shape()

	set name = "Select Body Shape"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 50

	om_prompt(src, src, list("kind" = "list", "message" = "Please select a species to emulate.", "title" = "Shapeshifter Body", "choices" = species.get_valid_shapeshifter_forms(src), "requires" = PROMPT_CONSCIOUS), PROC_REF(shapeshifter_shape_chosen))

/mob/living/carbon/human/proc/shapeshifter_shape_chosen(mob/user, new_species, datum/om/prompt/ask)
	if(!GLOB.all_species[new_species] || GLOB.wrapped_species_by_ref["\ref[src]"] == new_species || !(new_species in species.get_valid_shapeshifter_forms(src)))
		return
	shapeshifter_change_shape(new_species)

/* moved to species_shapeshift_vr.dm
/mob/living/carbon/human/proc/shapeshifter_change_shape(new_species = null)
	if(!new_species)
		return

	GLOB.wrapped_species_by_ref["\ref[src]"] = new_species
	visible_message(span_infoplain(span_bold("\The [src]") + " shifts and contorts, taking the form of \a [new_species]!"))
	regenerate_icons()
*/

/mob/living/carbon/human/proc/shapeshifter_select_colour()

	set name = "Select Body Colour"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 50

	om_prompt(src, src, list("kind" = "color", "message" = "Please select a new body color.", "title" = "Shapeshifter Colour", "default" = rgb(r_skin, g_skin, b_skin), "requires" = PROMPT_CONSCIOUS), PROC_REF(shapeshifter_colour_chosen))

/mob/living/carbon/human/proc/shapeshifter_colour_chosen(mob/user, new_skin, datum/om/prompt/ask)
	shapeshifter_set_colour(new_skin)

/mob/living/carbon/human/proc/shapeshifter_set_colour(new_skin)

	r_skin =   hex2num(copytext(new_skin, 2, 4))
	g_skin =   hex2num(copytext(new_skin, 4, 6))
	b_skin =   hex2num(copytext(new_skin, 6, 8))
	r_synth = r_skin
	g_synth = g_skin
	b_synth = b_skin


	for(var/obj/item/organ/external/E in organs)
		E.sync_colour_to_human(src)

	regenerate_icons()

/mob/living/carbon/human/proc/shapeshifter_select_hair_colors()

	set name = "Select Hair Colors"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 50

	// Each colour applies as soon as it is picked; a cancel stops there.
	om_prompt_sequence(src, src, list(
		list("key" = "hair", "kind" = "color", "message" = "Please select a new hair color.", "title" = "Hair Colour"),
		PROC_REF(shapeshifter_hair_color_step),
		PROC_REF(shapeshifter_grad_color_step),
	), PROC_REF(shapeshifter_hair_colors_done), list("requires" = PROMPT_CONSCIOUS))

/mob/living/carbon/human/proc/shapeshifter_hair_color_step(mob/user, datum/om/prompt/ask)
	shapeshifter_set_hair_color(ask.get("hair"))
	return list("key" = "grad", "kind" = "color", "message" = "Please select a new hair gradient color.", "title" = "Hair Gradient Colour")

/mob/living/carbon/human/proc/shapeshifter_grad_color_step(mob/user, datum/om/prompt/ask)
	shapeshifter_set_grad_color(ask.get("grad"))
	return list("key" = "facial", "kind" = "color", "message" = "Please select a new facial hair color.", "title" = "Facial Hair Color")

/mob/living/carbon/human/proc/shapeshifter_hair_colors_done(mob/user, datum/om/prompt/ask)
	shapeshifter_set_facial_color(ask.get("facial"))

/mob/living/carbon/human/proc/shapeshifter_set_hair_color(new_hair)

	change_hair_color(hex2num(copytext(new_hair, 2, 4)), hex2num(copytext(new_hair, 4, 6)), hex2num(copytext(new_hair, 6, 8)))

/mob/living/carbon/human/proc/shapeshifter_set_grad_color(new_grad)

	change_grad_color(hex2num(copytext(new_grad, 2, 4)), hex2num(copytext(new_grad, 4, 6)), hex2num(copytext(new_grad, 6, 8)))

/mob/living/carbon/human/proc/shapeshifter_set_facial_color(new_fhair)

	change_facial_hair_color(hex2num(copytext(new_fhair, 2, 4)), hex2num(copytext(new_fhair, 4, 6)), hex2num(copytext(new_fhair, 6, 8)))

// Replaces limbs and copies wounds
/mob/living/carbon/human/proc/shapeshifter_change_species(new_species)
	if(!species)
		return

	dna.species = new_species

	var/list/limb_exists = list(
		BP_TORSO =  0,
		BP_GROIN =  0,
		BP_HEAD =   0,
		BP_L_ARM =  0,
		BP_R_ARM =  0,
		BP_L_LEG =  0,
		BP_R_LEG =  0,
		BP_L_HAND = 0,
		BP_R_HAND = 0,
		BP_L_FOOT = 0,
		BP_R_FOOT = 0
		)
	// Remember which limbs exist (wound afflictions travel with the limb itself).
	for(var/limb in organs_by_name)
		var/obj/item/organ/external/O = organs_by_name[limb]
		limb_exists[O.organ_tag] = 1

	species = GLOB.all_species[new_species]
	species.create_organs(src)
//	species.handle_post_spawn(src)

	// A copy: deleting a limb that was missing before takes it out of the cache.
	for(var/limb in organs_by_name.Copy())
		var/obj/item/organ/external/O = organs_by_name[limb]
		if(QDELETED(O))
			continue // went with a deleted parent
		if(limb_exists[O.organ_tag])
			O.data.setup_from_species(GLOB.all_species[new_species])
			// sync the organ's damage with its wounds
			O.update_damages()
		else
			qdel(O)

	regenerate_icons()
/* Our own trait system, sorry.
	if(species && mind)
		apply_traits()
*/
	return

/mob/living/carbon/human/proc/shapeshifter_select_eye_colour()

	set name = "Select Eye Color"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 50

	var/current_color = rgb(r_eyes,g_eyes,b_eyes)
	om_prompt(src, src, list("kind" = "color", "message" = "Pick a new color for your eyes.", "title" = "Eye Color", "default" = current_color, "requires" = PROMPT_CONSCIOUS), PROC_REF(shapeshifter_eye_colour_chosen))

/mob/living/carbon/human/proc/shapeshifter_eye_colour_chosen(mob/user, new_eyes, datum/om/prompt/ask)
	shapeshifter_set_eye_color(new_eyes)

/mob/living/carbon/human/proc/shapeshifter_set_eye_color(new_eyes)

	var/list/new_color_rgb_list = hex2rgb(new_eyes)
	// First, update mob vars.
	r_eyes = new_color_rgb_list[1]
	g_eyes = new_color_rgb_list[2]
	b_eyes = new_color_rgb_list[3]
	// Now sync the organ's eye_colour list, if possible
	var/obj/item/organ/internal/eyes/eyes = internal_organs_by_name[O_EYES]
	if(istype(eyes))
		eyes.update_colour()

	update_icons_body()
	update_eyes()

/mob/living/carbon/human/proc/shapeshifter_select_ears()
	set name = "Select Ears"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 10
	shapeshifter_select_accessory("ears")

// Ears, tail and wings share one flow: a style, up to three colours (the second and third only
// when the first was picked) and an alpha. Each kind's vars are r_<p>, r_<p>2, r_<p>3 and a_<p>.
/mob/living/carbon/human/proc/shapeshifter_accessory_info(kind)
	var/static/list/info = list(
		"ears" = list("prefix" = "ears", "none" = "Normal", "pick" = "Pick some ears!", "noun" = "ear", "title" = "Ear"),
		"tail" = list("prefix" = "tail", "none" = "Normal", "pick" = "Pick a tail!", "noun" = "tail", "title" = "Tail"),
		"wings" = list("prefix" = "wing", "none" = "None", "pick" = "Pick some wings!", "noun" = "wing", "title" = "Wing"),
	)
	return info[kind]

/mob/living/carbon/human/proc/shapeshifter_accessory_styles(kind)
	var/list/source
	switch(kind)
		if("ears")
			source = GLOB.ear_styles_list
		if("tail")
			source = GLOB.tail_styles_list
		if("wings")
			source = GLOB.wing_styles_list
	return source

/mob/living/carbon/human/proc/shapeshifter_select_accessory(kind)
	var/list/I = shapeshifter_accessory_info(kind)
	var/list/source = shapeshifter_accessory_styles(kind)
	// Construct the list of names allowed for this user.
	var/list/pretty_styles = list()
	pretty_styles[I["none"]] = null
	for(var/path in source)
		var/datum/sprite_accessory/instance = source[path]
		if((!instance.ckeys_allowed) || (ckey in instance.ckeys_allowed))
			pretty_styles[instance.name] = path
	var/p = I["prefix"]
	var/noun = I["noun"]
	var/title = I["title"]
	om_prompt_sequence(src, src, list(
		list("key" = "style", "kind" = "list", "message" = I["pick"], "title" = "Character Preference", "choices" = pretty_styles),
		list("key" = "c1", "kind" = "color", "message" = "Pick primary [noun] color:", "title" = "[title] Color (Pri)", "default" = rgb(vars["r_[p]"], vars["g_[p]"], vars["b_[p]"]), "optional" = TRUE),
		PROC_REF(shapeshifter_accessory_c2),
		PROC_REF(shapeshifter_accessory_c3),
		list("key" = "alpha", "kind" = "number", "message" = "Set [noun] alpha (0-255):", "title" = "[title] Alpha", "default" = vars["a_[p]"], "max" = 255, "min" = 0, "optional" = TRUE),
	), PROC_REF(shapeshifter_accessory_chosen), list("requires" = PROMPT_CONSCIOUS, "data" = list("kind" = kind, "styles" = pretty_styles)))

/mob/living/carbon/human/proc/shapeshifter_accessory_c2(mob/user, datum/om/prompt/ask)
	if(!ask.get("c1")) //don't bother if they clicked cancel on the primary colour
		return
	var/list/I = shapeshifter_accessory_info(ask.get("kind"))
	var/p = I["prefix"]
	return list("key" = "c2", "kind" = "color", "message" = "Pick secondary [I["noun"]] color (only applies to some [I["noun"]]s):", "title" = "[I["title"]] Color (sec)", "default" = rgb(vars["r_[p]2"], vars["g_[p]2"], vars["b_[p]2"]), "optional" = TRUE)

/mob/living/carbon/human/proc/shapeshifter_accessory_c3(mob/user, datum/om/prompt/ask)
	if(!ask.get("c1"))
		return
	var/list/I = shapeshifter_accessory_info(ask.get("kind"))
	var/p = I["prefix"]
	return list("key" = "c3", "kind" = "color", "message" = "Pick tertiary [I["noun"]] color (only applies to some [I["noun"]]s):", "title" = "[I["title"]] Color (ter)", "default" = rgb(vars["r_[p]3"], vars["g_[p]3"], vars["b_[p]3"]), "optional" = TRUE)

/mob/living/carbon/human/proc/shapeshifter_accessory_chosen(mob/user, datum/om/prompt/ask)
	var/kind = ask.get("kind")
	var/list/I = shapeshifter_accessory_info(kind)
	var/list/source = shapeshifter_accessory_styles(kind)
	var/list/pretty_styles = ask.get("styles")
	var/datum/sprite_accessory/style = source[pretty_styles[ask.get("style")]]
	switch(kind)
		if("ears")
			ear_style = style
		if("tail")
			tail_style = style
		if("wings")
			wing_style = style
	var/p = I["prefix"]
	var/list/suffixes = list("c1" = "", "c2" = "2", "c3" = "3")
	for(var/key in suffixes)
		var/new_color = ask.get(key)
		if(!new_color)
			continue
		var/list/new_color_rgb_list = hex2rgb(new_color)
		var/suffix = suffixes[key]
		vars["r_[p][suffix]"] = new_color_rgb_list[1]
		vars["g_[p][suffix]"] = new_color_rgb_list[2]
		vars["b_[p][suffix]"] = new_color_rgb_list[3]
	if(ask.get("alpha"))
		vars["a_[p]"] = clamp(ask.get("alpha"), 0, 255)
	switch(kind)
		if("ears")
			update_hair() //Includes Virgo ears
		if("tail")
			update_tail_showing()
		if("wings")
			update_wing_showing()

/mob/living/carbon/human/proc/shapeshifter_select_secondary_ears()
	set name = "Select Secondary Ears"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return
	last_special = world.time + 1 SECONDS

	// Construct the list of names allowed for this user.
	var/list/pretty_ear_styles = list("Normal" = null)
	for(var/path in GLOB.ear_styles_list)
		var/datum/sprite_accessory/ears/instance = GLOB.ear_styles_list[path]
		if((!instance.ckeys_allowed) || (ckey in instance.ckeys_allowed))
			pretty_ear_styles[instance.name] = path

	// Handle style pick
	om_prompt(src, src, list("kind" = "list", "message" = "Pick some ears!", "title" = "Character Preference", "choices" = pretty_ear_styles, "requires" = PROMPT_CONSCIOUS, "data" = list("styles" = pretty_ear_styles)), PROC_REF(shapeshifter_secondary_ears_chosen))

/// Sets the style, then asks one colour per channel of it (a cancel keeps that channel) and the alpha.
/mob/living/carbon/human/proc/shapeshifter_secondary_ears_chosen(mob/user, new_ear_style, datum/om/prompt/ask)
	var/list/pretty_ear_styles = ask.get("styles")
	ear_secondary_style = GLOB.ear_styles_list[pretty_ear_styles[new_ear_style]]
	var/list/steps = list()
	var/list/defaults = list()
	if(ear_secondary_style)
		for(var/channel in 1 to ear_secondary_style.get_color_channel_count())
			var/channel_name = GLOB.fancy_sprite_accessory_color_channel_names[channel]
			var/default = LAZYACCESS(ear_secondary_colors, channel) || "#ffffff"
			defaults += default
			steps += list(list("key" = "channel[channel]", "kind" = "color", "message" = "Pick [channel_name]", "title" = "Ear Color ([channel_name])", "default" = default, "optional" = TRUE))
	steps += list(list("key" = "alpha", "kind" = "number", "message" = "Set ear alpha (0-255):", "title" = "Ear Alpha", "default" = a_ears2, "max" = 255, "min" = 0, "optional" = TRUE))
	om_prompt_sequence(src, src, steps, PROC_REF(shapeshifter_secondary_ear_colors_chosen), list("requires" = PROMPT_CONSCIOUS, "data" = list("defaults" = defaults)))

/mob/living/carbon/human/proc/shapeshifter_secondary_ear_colors_chosen(mob/user, datum/om/prompt/ask)
	var/list/defaults = ask.get("defaults")
	if(length(defaults))
		var/list/new_colors = list()
		for(var/channel in 1 to length(defaults))
			new_colors += ask.get("channel[channel]") || defaults[channel]
		ear_secondary_colors = new_colors
	if(ask.get("alpha"))
		a_ears2 = clamp(ask.get("alpha"), 0, 255)
	update_hair()

/mob/living/carbon/human/proc/shapeshifter_select_tail()
	set name = "Select Tail"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 10
	shapeshifter_select_accessory("tail")

/mob/living/carbon/human/proc/shapeshifter_select_wings()
	set name = "Select Wings"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 10
	shapeshifter_select_accessory("wings")

/mob/living/carbon/human/proc/promethean_select_opaqueness()

	set name = "Toggle Transparency"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 50

	for(var/obj/item/organ/external/L as anything in src.organs)
		L.transparent = !L.transparent
	visible_message(span_notice("\The [src]'s internal composition seems to change."))
	update_icons_body()
	update_hair()

/mob/living/carbon/human/proc/shapeshifter_change_shape(new_species = null, visible = TRUE) //not sure if this needs to be moved to a separate file but
	if(!new_species)
		return

	dna.base_species = new_species
	species.base_species = new_species
	GLOB.wrapped_species_by_ref["\ref[src]"] = new_species
	if (visible)
		visible_message(span_filter_notice(span_bold("\The [src]") + " shifts and contorts, taking the form of \a [new_species]!"))
		regenerate_icons()


//////////////////// Shapeshifter copy-body powers
/// Copied from the protean version, but with some tweaks to match non-protean shapeshifters such as lleill, hanner and replicants

/mob/living/carbon/human/proc/shapeshifter_regenerate()
	set name = "Fully Reform"
	set desc = "Reload your appearance from whatever character slot you have loaded."
	set category = "Abilities.Shapeshift"
	om_prompt_sequence(src, src, list(
		list("key" = "reform", "message" = "Do you want to copy the appearance data of your currently loaded save slot?", "title" = "Reformation", "choices" = list("Reform","Cancel"), "confirm" = "Reform"),
		list("key" = "flavour", "message" = "Include Flavourtext?", "title" = "Reformation", "choices" = list("Yes","No","Cancel"), "abort" = "Cancel"),
		list("key" = "ooc", "message" = "Include OOC notes?", "title" = "Reformation", "choices" = list("Yes","No","Cancel"), "abort" = "Cancel"),
	), PROC_REF(shapeshifter_regenerate_answered), list("requires" = PROMPT_CONSCIOUS))

/mob/living/carbon/human/proc/shapeshifter_regenerate_answered(mob/user, datum/om/prompt/ask)
	var/flavour = ask.get("flavour") == "Yes"
	var/oocnotes = ask.get("ooc") == "Yes"
	to_chat(src, span_notify("You begin to reform. You will need to remain still."))
	visible_message(span_notify("[src] rapidly contorts and shifts!"), span_danger("You begin to reform."))
	om_task_start(/datum/om/task/timed/human_shapeshifter_regenerate_human, src, src, list("receiver" = src, "flavour" = flavour, "oocnotes" = oocnotes))

/datum/om/task/timed/human_shapeshifter_regenerate_human
	duration = 4 SECONDS
	complete_proc = /mob/living/carbon/human/proc/shapeshifter_regenerate_human_done
	var/flavour
	var/oocnotes

/mob/living/carbon/human/proc/shapeshifter_regenerate_human_done(datum/om/task/timed/human_shapeshifter_regenerate_human/task)
	var/mob/living/character = task.actor
	var/flavour = task.flavour
	var/oocnotes = task.oocnotes
	if(character.client.prefs)	//Make sure we didn't d/c
		character.client.prefs.vanity_copy_to(src, FALSE, flavour, oocnotes, FALSE, FALSE)
		character.visible_message(span_notify("[character] adopts a new form!"), span_danger("You have reformed."))

/mob/living/carbon/human/proc/shapeshifter_copy_body()
	set name = "Copy Form"
	set desc = "If you are aggressively grabbing someone, with their consent, you can turn into a copy of them. (Without their name)."
	set category = "Abilities.Shapeshift"
	var/mob/living/character = src

	var/grabbing_but_not_enough
	var/mob/living/carbon/human/victim = null
	for(var/obj/item/grab/G in character)
		if(G.state < GRAB_AGGRESSIVE)
			grabbing_but_not_enough = TRUE
			return
		else
			victim = G?.grab_target()
	if (!victim)
		if (grabbing_but_not_enough)
			to_chat(character, span_warning("You need a better grip to do that!"))
		else
			to_chat(character, span_notice("You need to be aggressively grabbing someone before you can copy their form."))
		return
	if (!ishuman(victim))
		to_chat(character, span_warning("You can only perform this on human mobs!"))
		return
	if (!victim.client)
		to_chat(character, span_notice("The person you try this on must have a client!"))
		return


	to_chat(character, span_notice("Waiting for other person's consent."))
	// The victim is asked; the answer runs on us with the victim as its user.
	om_prompt(src, victim, list("message" = "Allow [src] to copy what you look like?", "title" = "Consent", "choices" = list("Yes", "No"), "on_cancel" = PROC_REF(copy_body_declined)), PROC_REF(copy_body_consented))

/mob/living/carbon/human/proc/copy_body_declined(mob/living/carbon/human/victim, datum/om/prompt/ask)
	to_chat(src, span_notice("They declined your request."))

/mob/living/carbon/human/proc/copy_body_consented(mob/living/carbon/human/victim, consent, datum/om/prompt/ask)
	if (consent != "Yes")
		copy_body_declined(victim, ask)
		return
	om_prompt(src, src, list("message" = "Copy [victim]'s flavourtext?", "title" = "Copy Form", "choices" = list("Yes","No","Cancel"), "requires" = PROMPT_CONSCIOUS, "data" = list("victim" = victim)), PROC_REF(copy_body_flavour_chosen))

/// TRUE while we still hold `victim` in at least an aggressive grab.
/mob/living/carbon/human/proc/copy_body_gripping(mob/living/carbon/human/victim)
	for(var/obj/item/grab/G in src)
		if(G?.grab_target() == victim && G.state >= GRAB_AGGRESSIVE)
			return TRUE
	return FALSE

/mob/living/carbon/human/proc/copy_body_flavour_chosen(mob/user, input, datum/om/prompt/ask)
	if(input == "Cancel")
		return
	var/mob/living/carbon/human/victim = ask.get("victim")
	var/flavour = input == "Yes"
	if (!copy_body_gripping(victim))
		to_chat(src, span_warning("You lost your grip on [victim]!"))
		return

	to_chat(src, span_notify("You begin to reassemble into [victim]. You will need to remain still."))
	visible_message(span_notify("[src] rapidly contorts and shifts!"), span_danger("You begin to reassemble into [victim]."))
	om_do_after(src, 4 SECONDS, target = victim, receiver = src, on_done = PROC_REF(copy_body_done), done_args = list(victim, flavour))

/mob/living/carbon/human/proc/copy_body_done(mob/living/carbon/human/victim, flavour)
	var/checking = FALSE
	for(var/obj/item/grab/G in src)
		if(G?.grab_target() == victim && G.state >= GRAB_AGGRESSIVE)
			checking = TRUE
	if (!checking)
		to_chat(src, span_warning("You lost your grip on [victim]!"))
		return
	if(client)	//Make sure we didn't d/c
		transform_into_other_human(victim, FALSE, flavour, FALSE, FALSE)
		visible_message(span_notify("[src] adopts the form of [victim]!"), span_danger("You have reassembled into [victim]."))


/mob/living/carbon/human/proc/shapeshifter_reassemble()

	set name = "Complete Reform"
	set category = "Abilities.Shapeshift"

	if(stat || world.time < last_special)
		return

	last_special = world.time + 50

	om_prompt_sequence(src, src, list(
		list("key" = "sure", "message" = "Are you sure you want to reform yourself? This will reset you to what you look like in your current preferences slot.", "title" = "Reform", "choices" = list("Yes","Cancel"), "confirm" = "Yes"),
		list("key" = "flavour", "message" = "Include Flavourtext?", "title" = "Reformation", "choices" = list("Yes","No","Cancel"), "abort" = "Cancel"),
		list("key" = "ooc", "message" = "Include OOC notes?", "title" = "Reformation", "choices" = list("Yes","No","Cancel"), "abort" = "Cancel"),
	), PROC_REF(shapeshifter_reassemble_answered), list("requires" = PROMPT_CONSCIOUS))

/mob/living/carbon/human/proc/shapeshifter_reassemble_answered(mob/user, datum/om/prompt/ask)
	var/flavour = ask.get("flavour") == "Yes"
	var/oocnotes = ask.get("ooc") == "Yes"
	to_chat(src, span_notify("You begin to reform. You will need to remain still."))
	visible_message(span_notify("[src] rapidly contorts and shifts!"), span_danger("You begin to reform."))
	om_do_after(src, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(shapeshifter_reassemble_human_done), done_args = list(flavour, oocnotes))

/mob/living/carbon/human/proc/shapeshifter_reassemble_human_done(flavour, oocnotes)
	if (client?.prefs)
		client.prefs.vanity_copy_to(src, FALSE, flavour, oocnotes, FALSE)
		visible_message(span_notify("[src] adopts a new form!"), span_danger("You have reformed."))
