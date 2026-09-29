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

	base_species = SPECIES_HUMAN
	selects_bodytype = SELECTS_BODYTYPE_SHAPESHIFTER

TYPE_TABLE(/datum/species/shapeshifter, shared_table_vars, list("assisted_langs", "unarmed_types", "cold_discomfort_strings", "heat_discomfort_strings", "has_organ", "genders", "secondary_langs", "inherent_verbs", "default_emotes", "speech_sounds", "species_component", "valid_transform_species"))

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

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 10)

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
	om_flow_start(/datum/om/flow/shapeshift_hair, src, src, hairs = valid_hairstyles, grads = valid_gradstyles, facials = valid_facialhairstyles)

/datum/om/prompt/color/shapeshift_optional
	ask_flags = ASK_CONSCIOUS
	cancel_answer = ""

/// Hair, gradient and facial hair styles in turn (each only if there are any to pick).
/datum/om/flow/shapeshift_hair
	requires = PROMPT_CONSCIOUS
	var/list/hairs
	var/list/grads
	var/list/facials
	var/hair
	var/gradient
	var/facial

/datum/om/flow/shapeshift_hair/start()
	if(!length(hairs))
		ask_gradient()
		return
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(hair_chosen), message = "Select a hairstyle.", title = "Shapeshifter Hair", choices = hairs, ask_flags = ASK_CONSCIOUS, cancel_answer = "")

/datum/om/flow/shapeshift_hair/proc/hair_chosen(datum/om/prompt/choice/ask)
	hair = ask.choice || "Bald"
	ask_gradient()

/datum/om/flow/shapeshift_hair/proc/ask_gradient()
	if(!length(grads))
		ask_facial()
		return
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(gradient_chosen), message = "Select a hair gradient style.", title = "Shapeshifter Hair", choices = grads, ask_flags = ASK_CONSCIOUS, cancel_answer = "")

/datum/om/flow/shapeshift_hair/proc/gradient_chosen(datum/om/prompt/choice/ask)
	gradient = ask.choice || "None"
	ask_facial()

/datum/om/flow/shapeshift_hair/proc/ask_facial()
	if(!length(facials))
		finish()
		return
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(facial_chosen), message = "Select a facial hair style.", title = "Shapeshifter Hair", choices = facials, ask_flags = ASK_CONSCIOUS, cancel_answer = "")

/datum/om/flow/shapeshift_hair/proc/facial_chosen(datum/om/prompt/choice/ask)
	facial = ask.choice || "Shaved"
	finish()

/datum/om/flow/shapeshift_hair/proc/finish()
	var/mob/living/carbon/human/H = actor
	H.shapeshifter_hair_chosen(hair, gradient, facial)

/// Applies the picked styles (null: that one wasn't asked).
/mob/living/carbon/human/proc/shapeshifter_hair_chosen(new_hair, new_gradient, new_facial)
	if(new_hair)
		change_hair(new_hair)
	if(new_gradient)
		change_hair_gradient(new_gradient)
	if(new_facial)
		change_facial_hair(new_facial)

/mob/living/carbon/human/proc/shapeshifter_select_gender()

	set name = "Select Gender"
	set category = "Abilities.Shapeshift"

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 50)

	om_ask(src, /datum/om/prompt/choice, PROC_REF(shapeshifter_gender_picked), message = "Please select a gender.", title = "Shapeshifter Gender", choices = list(FEMALE, MALE, NEUTER, PLURAL), ask_flags = ASK_CONSCIOUS)

/// The gender identity; carries the gender picked first.
/datum/om/prompt/choice/shapeshift_identity
	message = "Please select a gender Identity."
	title = "Shapeshifter Gender Identity"
	choices = list(FEMALE, MALE, NEUTER, PLURAL, HERM)
	ask_flags = ASK_CONSCIOUS
	var/new_gender

/mob/living/carbon/human/proc/shapeshifter_gender_picked(datum/om/prompt/choice/ask)
	om_ask(src, /datum/om/prompt/choice/shapeshift_identity, PROC_REF(shapeshifter_gender_chosen), new_gender = ask.choice)

/mob/living/carbon/human/proc/shapeshifter_gender_chosen(datum/om/prompt/choice/shapeshift_identity/ask)
	visible_message(span_notice("\The [src]'s form contorts subtly."))
	change_gender(ask.new_gender)
	change_gender_identity(ask.choice)

/mob/living/carbon/human/proc/shapeshifter_select_shape()

	set name = "Select Body Shape"
	set category = "Abilities.Shapeshift"

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 50)

	om_ask(src, /datum/om/prompt/choice/shapeshifter_form, PROC_REF(shapeshifter_shape_chosen), choices = species.get_valid_shapeshifter_forms(src))

/// Picking a form. Re-checked on the answer: still conscious, and the form is still one to take.
/datum/om/prompt/choice/shapeshifter_form
	title = "Shapeshifter Body"
	message = "Please select a species to emulate."
	ask_flags = ASK_CONSCIOUS

/datum/om/prompt/choice/shapeshifter_form/valid()
	var/mob/living/carbon/human/shifter = asker
	if(!GLOB.all_species[choice] || GLOB.wrapped_species_by_ref["\ref[shifter]"] == choice || !(choice in shifter.species.get_valid_shapeshifter_forms(shifter)))
		return "not a form to take"
	return null

/mob/living/carbon/human/proc/shapeshifter_shape_chosen(datum/om/prompt/choice/shapeshifter_form/ask)
	shapeshifter_change_shape(ask.choice)

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

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 50)

	om_ask(src, /datum/om/prompt/color, PROC_REF(shapeshifter_colour_chosen), title = "Shapeshifter Colour", message = "Please select a new body color.", default = rgb(r_skin, g_skin, b_skin), ask_flags = ASK_CONSCIOUS)

/mob/living/carbon/human/proc/shapeshifter_colour_chosen(datum/om/prompt/color/ask)
	shapeshifter_set_colour(ask.picked_color)

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

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 50)

	// Each colour applies as soon as it is picked; a cancel stops there.
	om_ask(src, /datum/om/prompt/color, PROC_REF(shapeshifter_hair_color_step), message = "Please select a new hair color.", title = "Hair Colour", ask_flags = ASK_CONSCIOUS)

/mob/living/carbon/human/proc/shapeshifter_hair_color_step(datum/om/prompt/color/ask)
	shapeshifter_set_hair_color(ask.picked_color)
	om_ask(src, /datum/om/prompt/color, PROC_REF(shapeshifter_grad_color_step), message = "Please select a new hair gradient color.", title = "Hair Gradient Colour", ask_flags = ASK_CONSCIOUS)

/mob/living/carbon/human/proc/shapeshifter_grad_color_step(datum/om/prompt/color/ask)
	shapeshifter_set_grad_color(ask.picked_color)
	om_ask(src, /datum/om/prompt/color, PROC_REF(shapeshifter_hair_colors_done), message = "Please select a new facial hair color.", title = "Facial Hair Color", ask_flags = ASK_CONSCIOUS)

/mob/living/carbon/human/proc/shapeshifter_hair_colors_done(datum/om/prompt/color/ask)
	shapeshifter_set_facial_color(ask.picked_color)

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

	release_species_copy(adopt_species(GLOB.all_species[new_species]))
	species.create_organs(src)

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

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 50)

	var/current_color = rgb(r_eyes,g_eyes,b_eyes)
	om_ask(src, /datum/om/prompt/color, PROC_REF(shapeshifter_eye_colour_chosen), message = "Pick a new color for your eyes.", title = "Eye Color", default = current_color, ask_flags = ASK_CONSCIOUS)

/mob/living/carbon/human/proc/shapeshifter_eye_colour_chosen(datum/om/prompt/color/ask)
	shapeshifter_set_eye_color(ask.picked_color)

/mob/living/carbon/human/proc/shapeshifter_set_eye_color(new_eyes)

	var/list/new_color_rgb_list = hex2rgb(new_eyes)
	// First, update mob vars.
	r_eyes = new_color_rgb_list[1]
	g_eyes = new_color_rgb_list[2]
	b_eyes = new_color_rgb_list[3]
	// Now sync the organ's eye_colour list, if possible
	var/obj/item/organ/internal/eyes/eyes = organ_in(O_EYES)
	if(istype(eyes))
		eyes.update_colour()

	update_icons_body()
	update_eyes()

/mob/living/carbon/human/proc/shapeshifter_select_ears()
	set name = "Select Ears"
	set category = "Abilities.Shapeshift"

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 10)
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
	om_flow_start(/datum/om/flow/shapeshift_accessory, src, src, kind = kind, pretty_styles = pretty_styles, info = I)

/// An accessory style, then its colours (secondary and tertiary only after a primary) and alpha;
/// each colour and the alpha can be skipped.
/datum/om/flow/shapeshift_accessory
	requires = PROMPT_CONSCIOUS
	var/kind
	var/list/pretty_styles
	/// shapeshifter_accessory_info(kind).
	var/list/info
	var/style_name
	var/c1
	var/c2
	var/c3
	var/alpha

/datum/om/flow/shapeshift_accessory/start()
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(style_chosen), message = info["pick"], title = "Character Preference", choices = pretty_styles, ask_flags = ASK_CONSCIOUS)

/// rgb() of the human's colour vars for this accessory and `suffix` ("", "2", "3").
/datum/om/flow/shapeshift_accessory/proc/current_color(suffix)
	var/mob/living/carbon/human/H = actor
	var/p = info["prefix"]
	return rgb(H.vars["r_[p][suffix]"], H.vars["g_[p][suffix]"], H.vars["b_[p][suffix]"])

/datum/om/flow/shapeshift_accessory/proc/style_chosen(datum/om/prompt/choice/ask)
	style_name = ask.choice
	om_ask(actor, /datum/om/prompt/color/shapeshift_optional, PROC_REF(c1_chosen), message = "Pick primary [info["noun"]] color:", title = "[info["title"]] Color (Pri)", default = current_color(""))

/datum/om/flow/shapeshift_accessory/proc/c1_chosen(datum/om/prompt/color/ask)
	c1 = ask.picked_color
	if(!c1) //don't bother if they clicked cancel on the primary colour
		ask_alpha()
		return
	om_ask(actor, /datum/om/prompt/color/shapeshift_optional, PROC_REF(c2_chosen), message = "Pick secondary [info["noun"]] color (only applies to some [info["noun"]]s):", title = "[info["title"]] Color (sec)", default = current_color("2"))

/datum/om/flow/shapeshift_accessory/proc/c2_chosen(datum/om/prompt/color/ask)
	c2 = ask.picked_color
	om_ask(actor, /datum/om/prompt/color/shapeshift_optional, PROC_REF(c3_chosen), message = "Pick tertiary [info["noun"]] color (only applies to some [info["noun"]]s):", title = "[info["title"]] Color (ter)", default = current_color("3"))

/datum/om/flow/shapeshift_accessory/proc/c3_chosen(datum/om/prompt/color/ask)
	c3 = ask.picked_color
	ask_alpha()

/datum/om/flow/shapeshift_accessory/proc/ask_alpha()
	var/mob/living/carbon/human/H = actor
	om_ask(actor, /datum/om/prompt/number, PROC_REF(alpha_chosen), message = "Set [info["noun"]] alpha (0-255):", title = "[info["title"]] Alpha", default = H.vars["a_[info["prefix"]]"], ask_flags = ASK_CONSCIOUS, cancel_answer = "", min = 0, max = 255)

/datum/om/flow/shapeshift_accessory/proc/alpha_chosen(datum/om/prompt/number/ask)
	var/mob/living/carbon/human/H = actor
	H.shapeshifter_accessory_chosen(kind, pretty_styles[style_name], list("c1" = c1, "c2" = c2, "c3" = c3), ask.number)

/// Applies an accessory pick: `style_path` (null: none), `colors` ("c1"/"c2"/"c3" -> "#rrggbb" or
/// empty to keep) and `alpha` (empty to keep).
/mob/living/carbon/human/proc/shapeshifter_accessory_chosen(kind, style_path, list/colors, alpha)
	var/list/source = shapeshifter_accessory_styles(kind)
	var/datum/sprite_accessory/style = source[style_path]
	switch(kind)
		if("ears")
			ear_style = style
		if("tail")
			tail_style = style
		if("wings")
			wing_style = style
	var/static/list/suffixes = list("c1" = "", "c2" = "2", "c3" = "3")
	for(var/key in suffixes)
		var/new_color = colors[key]
		if(!new_color)
			continue
		set_accessory_color(kind, suffixes[key], hex2rgb(new_color))
	if(alpha)
		set_accessory_alpha(kind, clamp(alpha, 0, 255))
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

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return
	COOLDOWN_START(src, last_special, 1 SECONDS)

	// Construct the list of names allowed for this user.
	var/list/pretty_ear_styles = list("Normal" = null)
	for(var/path in GLOB.ear_styles_list)
		var/datum/sprite_accessory/ears/instance = GLOB.ear_styles_list[path]
		if((!instance.ckeys_allowed) || (ckey in instance.ckeys_allowed))
			pretty_ear_styles[instance.name] = path

	// Handle style pick
	om_ask(src, /datum/om/prompt/choice, PROC_REF(shapeshifter_secondary_ears_chosen), title = "Character Preference", message = "Pick some ears!", choices = pretty_ear_styles, ask_flags = ASK_CONSCIOUS)

/// Sets the style, then asks one colour per channel of it (a cancel keeps that channel) and the alpha.
/mob/living/carbon/human/proc/shapeshifter_secondary_ears_chosen(datum/om/prompt/choice/ask)
	ear_secondary_style = GLOB.ear_styles_list[ask.choices[ask.choice]]
	var/list/defaults = list()
	if(ear_secondary_style)
		for(var/channel in 1 to ear_secondary_style.get_color_channel_count())
			defaults += LAZYACCESS(ear_secondary_colors, channel) || "#ffffff"
	om_flow_start(/datum/om/flow/shapeshift_ear_colors, src, src, defaults = defaults)

/// One colour per channel of the secondary ears (a cancel keeps that channel), then the alpha.
/datum/om/flow/shapeshift_ear_colors
	requires = PROMPT_CONSCIOUS
	var/list/defaults
	var/list/new_colors
	var/channel = 0

/datum/om/flow/shapeshift_ear_colors/start()
	new_colors = list()
	next_channel()

/datum/om/flow/shapeshift_ear_colors/proc/next_channel()
	channel++
	if(channel > length(defaults))
		var/mob/living/carbon/human/H = actor
		om_ask(actor, /datum/om/prompt/number, PROC_REF(alpha_chosen), message = "Set ear alpha (0-255):", title = "Ear Alpha", default = H.a_ears2, ask_flags = ASK_CONSCIOUS, cancel_answer = "", min = 0, max = 255)
		return
	var/channel_name = GLOB.fancy_sprite_accessory_color_channel_names[channel]
	om_ask(actor, /datum/om/prompt/color/shapeshift_optional, PROC_REF(channel_chosen), message = "Pick [channel_name]", title = "Ear Color ([channel_name])", default = defaults[channel])

/datum/om/flow/shapeshift_ear_colors/proc/channel_chosen(datum/om/prompt/color/ask)
	new_colors += ask.picked_color || defaults[channel]
	next_channel()

/datum/om/flow/shapeshift_ear_colors/proc/alpha_chosen(datum/om/prompt/number/ask)
	var/mob/living/carbon/human/H = actor
	H.shapeshifter_secondary_ear_colors_chosen(new_colors, ask.number)

/mob/living/carbon/human/proc/shapeshifter_secondary_ear_colors_chosen(list/new_colors, alpha)
	if(length(new_colors))
		ear_secondary_colors = new_colors
	if(alpha)
		a_ears2 = clamp(alpha, 0, 255)
	update_hair()

/mob/living/carbon/human/proc/shapeshifter_select_tail()
	set name = "Select Tail"
	set category = "Abilities.Shapeshift"

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 10)
	shapeshifter_select_accessory("tail")

/mob/living/carbon/human/proc/shapeshifter_select_wings()
	set name = "Select Wings"
	set category = "Abilities.Shapeshift"

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 10)
	shapeshifter_select_accessory("wings")

/mob/living/carbon/human/proc/promethean_select_opaqueness()

	set name = "Toggle Transparency"
	set category = "Abilities.Shapeshift"

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 50)

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
	om_flow_start(/datum/om/flow/shapeshift_reform, src, src, confirm_title = "Reformation", confirm_message = "Do you want to copy the appearance data of your currently loaded save slot?", confirm_yes = "Reform", finish_proc = PROC_REF(shapeshifter_regenerate_answered))

/// "Are you sure?", then whether to include flavour text and OOC notes; finish_proc runs on the
/// actor with (flavour, oocnotes).
/datum/om/flow/shapeshift_reform
	requires = PROMPT_CONSCIOUS
	var/confirm_title
	var/confirm_message
	var/confirm_yes
	var/finish_proc
	var/flavour

/datum/om/flow/shapeshift_reform/start()
	om_ask(actor, /datum/om/prompt/confirm, PROC_REF(confirmed), title = confirm_title, message = confirm_message, yes_text = confirm_yes, no_text = "Cancel", ask_flags = ASK_CONSCIOUS)

/datum/om/flow/shapeshift_reform/proc/confirmed(datum/om/prompt/confirm/ask)
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(flavour_chosen), message = "Include Flavourtext?", title = "Reformation", choices = list("Yes","No","Cancel"), buttons = TRUE, ask_flags = ASK_CONSCIOUS)

/datum/om/flow/shapeshift_reform/proc/flavour_chosen(datum/om/prompt/choice/ask)
	if(ask.choice == "Cancel")
		return
	flavour = (ask.choice == "Yes")
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(ooc_chosen), message = "Include OOC notes?", title = "Reformation", choices = list("Yes","No","Cancel"), buttons = TRUE, ask_flags = ASK_CONSCIOUS)

/datum/om/flow/shapeshift_reform/proc/ooc_chosen(datum/om/prompt/choice/ask)
	if(ask.choice == "Cancel")
		return
	call(actor, finish_proc)(flavour, ask.choice == "Yes")

/mob/living/carbon/human/proc/shapeshifter_regenerate_answered(flavour, oocnotes)
	to_chat(src, span_notify("You begin to reform. You will need to remain still."))
	visible_message(span_notify("[src] rapidly contorts and shifts!"), span_danger("You begin to reform."))
	om_task_start(/datum/om/task/timed/human_shapeshifter_regenerate_human, src, src, receiver = src, flavour = flavour, oocnotes = oocnotes)

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
	om_flow_start(/datum/om/flow/copy_body, src, victim)

/// The victim consents, then we choose whether to copy their flavour text. Re-checked before
/// each step: we still hold them in an aggressive grab.
/datum/om/flow/copy_body
	var/consented = FALSE

/datum/om/flow/copy_body/valid()
	var/mob/living/carbon/human/H = actor
	return H.copy_body_gripping(target) ? null : "lost grip"

/datum/om/flow/copy_body/ended(reason)
	if(!actor)
		return
	if(reason == "lost grip")
		to_chat(actor, span_warning("You lost your grip on [target]!"))
	else if(!consented && (reason == "declined" || reason == "cancelled"))
		to_chat(actor, span_notice("They declined your request."))

/datum/om/prompt/confirm/copy_body_consent
	title = "Consent"

/datum/om/prompt/confirm/copy_body_consent/prepare()
	message = "Allow [asker] to copy what you look like?"
	return TRUE

/datum/om/flow/copy_body/start()
	om_ask(target, /datum/om/prompt/confirm/copy_body_consent, PROC_REF(consent_given))

/datum/om/flow/copy_body/proc/consent_given(datum/om/prompt/confirm/ask)
	consented = TRUE
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(flavour_chosen), message = "Copy [target]'s flavourtext?", title = "Copy Form", choices = list("Yes","No","Cancel"), buttons = TRUE, ask_flags = ASK_CONSCIOUS)

/datum/om/flow/copy_body/proc/flavour_chosen(datum/om/prompt/choice/ask)
	var/mob/living/carbon/human/H = actor
	H.copy_body_flavour_chosen(target, ask.choice)

/// TRUE while we still hold `victim` in at least an aggressive grab.
/mob/living/carbon/human/proc/copy_body_gripping(mob/living/carbon/human/victim)
	for(var/obj/item/grab/G in contents_of(src))
		if(G?.grab_target() == victim && G.state >= GRAB_AGGRESSIVE)
			return TRUE
	return FALSE

/mob/living/carbon/human/proc/copy_body_flavour_chosen(mob/living/carbon/human/victim, input)
	if(input == "Cancel")
		return
	var/flavour = input == "Yes"

	to_chat(src, span_notify("You begin to reassemble into [victim]. You will need to remain still."))
	visible_message(span_notify("[src] rapidly contorts and shifts!"), span_danger("You begin to reassemble into [victim]."))
	om_task_timed(src, 4 SECONDS, target = victim, receiver = src, on_done = PROC_REF(copy_body_done), done_args = list(victim, flavour))

/mob/living/carbon/human/proc/copy_body_done(mob/living/carbon/human/victim, flavour)
	if (!copy_body_gripping(victim))
		to_chat(src, span_warning("You lost your grip on [victim]!"))
		return
	if(client)	//Make sure we didn't d/c
		transform_into_other_human(victim, new /datum/human_transform_options(copy_flavour = flavour, apply_bloodtype = FALSE))
		visible_message(span_notify("[src] adopts the form of [victim]!"), span_danger("You have reassembled into [victim]."))


/mob/living/carbon/human/proc/shapeshifter_reassemble()

	set name = "Complete Reform"
	set category = "Abilities.Shapeshift"

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 50)

	om_flow_start(/datum/om/flow/shapeshift_reform, src, src, confirm_title = "Reform", confirm_message = "Are you sure you want to reform yourself? This will reset you to what you look like in your current preferences slot.", confirm_yes = "Yes", finish_proc = PROC_REF(shapeshifter_reassemble_answered))

/mob/living/carbon/human/proc/shapeshifter_reassemble_answered(flavour, oocnotes)
	to_chat(src, span_notify("You begin to reform. You will need to remain still."))
	visible_message(span_notify("[src] rapidly contorts and shifts!"), span_danger("You begin to reform."))
	om_task_timed(src, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(shapeshifter_reassemble_human_done), done_args = list(flavour, oocnotes))

/mob/living/carbon/human/proc/shapeshifter_reassemble_human_done(flavour, oocnotes)
	if (client?.prefs)
		client.prefs.vanity_copy_to(src, FALSE, flavour, oocnotes, FALSE)
		visible_message(span_notify("[src] adopts a new form!"), span_danger("You have reformed."))

/// Sets one colour channel set of an ears/tail/wings accessory. `slot` is "" / "2" / "3"; `rgb` is a hex2rgb() list.
/mob/living/carbon/human/proc/set_accessory_color(kind, slot, list/rgb)
	var/r = rgb[1]
	var/g = rgb[2]
	var/b = rgb[3]
	switch("[kind][slot]")
		if("ears")
			r_ears = r; g_ears = g; b_ears = b
		if("ears2")
			r_ears2 = r; g_ears2 = g; b_ears2 = b
		if("ears3")
			r_ears3 = r; g_ears3 = g; b_ears3 = b
		if("tail")
			r_tail = r; g_tail = g; b_tail = b
		if("tail2")
			r_tail2 = r; g_tail2 = g; b_tail2 = b
		if("tail3")
			r_tail3 = r; g_tail3 = g; b_tail3 = b
		if("wings")
			r_wing = r; g_wing = g; b_wing = b
		if("wings2")
			r_wing2 = r; g_wing2 = g; b_wing2 = b
		if("wings3")
			r_wing3 = r; g_wing3 = g; b_wing3 = b

/// Sets an ears/tail/wings accessory's alpha.
/mob/living/carbon/human/proc/set_accessory_alpha(kind, alpha)
	switch(kind)
		if("ears")
			a_ears = alpha
		if("tail")
			a_tail = alpha
		if("wings")
			a_wing = alpha
