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
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 1 SECONDS)

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


	act_message(src, null, others = span_notice("%U%'s form contorts subtly."))
	// A cancel picks none (bald, no gradient, shaved).
	shapeshifter_ask_hair(valid_hairstyles, valid_gradstyles, valid_facialhairstyles)

/// Hair, gradient and facial hair styles in turn (each only if there are any to pick).
/datum/prompt/choice/shapeshift_hair
	title = "Shapeshifter Hair"
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/list/grads
	var/list/facials
	var/hair
	var/gradient
	recheck_on_open = TRUE

/mob/living/carbon/human/proc/shapeshifter_ask_hair(list/hairs, list/grads, list/facials)
	if(!length(hairs))
		shapeshifter_ask_gradient(grads, facials)
		return
	open_request(src, /datum/prompt/choice/shapeshift_hair, PROC_REF(shapeshifter_hair_style_picked), answerer = src, question = "Select a hairstyle.", choices = hairs, grads = grads, facials = facials)

/mob/living/carbon/human/proc/shapeshifter_hair_style_picked(datum/act/request/A)
	var/datum/prompt/choice/shapeshift_hair/ask = A.request
	if(!A.answer)
		if(ask.outcome != REQ_CANCELLED || !isnull(ask.value) || request_recheck(ask))
			return
	var/hair = A.answer ? ask.value || "Bald" : "Bald"
	shapeshifter_ask_gradient(ask.grads, ask.facials, hair)

/mob/living/carbon/human/proc/shapeshifter_ask_gradient(list/grads, list/facials, hair)
	if(!length(grads))
		shapeshifter_ask_facial(facials, hair)
		return
	open_request(src, /datum/prompt/choice/shapeshift_hair, PROC_REF(shapeshifter_gradient_style_picked), answerer = src, question = "Select a hair gradient style.", choices = grads, facials = facials, hair = hair)

/mob/living/carbon/human/proc/shapeshifter_gradient_style_picked(datum/act/request/A)
	var/datum/prompt/choice/shapeshift_hair/ask = A.request
	if(!A.answer)
		if(ask.outcome != REQ_CANCELLED || !isnull(ask.value) || request_recheck(ask))
			return
	var/gradient = A.answer ? ask.value || "None" : "None"
	shapeshifter_ask_facial(ask.facials, ask.hair, gradient)

/mob/living/carbon/human/proc/shapeshifter_ask_facial(list/facials, hair, gradient)
	if(!length(facials))
		shapeshifter_hair_chosen(hair, gradient, null)
		return
	open_request(src, /datum/prompt/choice/shapeshift_hair, PROC_REF(shapeshifter_facial_style_picked), answerer = src, question = "Select a facial hair style.", choices = facials, hair = hair, gradient = gradient)

/mob/living/carbon/human/proc/shapeshifter_facial_style_picked(datum/act/request/A)
	var/datum/prompt/choice/shapeshift_hair/ask = A.request
	if(!A.answer)
		if(ask.outcome != REQ_CANCELLED || !isnull(ask.value) || request_recheck(ask))
			return
	var/facial = A.answer ? ask.value || "Shaved" : "Shaved"
	shapeshifter_hair_chosen(ask.hair, ask.gradient, facial)

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
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	open_request(src, /datum/prompt/choice, PROC_REF(shapeshifter_gender_picked), answerer = src, title = "Shapeshifter Gender", question = "Please select a gender.", choices = list(FEMALE, MALE, NEUTER, PLURAL), ask_flags = ASK_CONSCIOUS, timeout = 0)

/// The gender identity; carries the gender picked first.
/datum/prompt/choice/shapeshift_identity
	timeout = 0
	question = "Please select a gender Identity."
	title = "Shapeshifter Gender Identity"
	choices = list(FEMALE, MALE, NEUTER, PLURAL, HERM)
	ask_flags = ASK_CONSCIOUS
	var/new_gender

/mob/living/carbon/human/proc/shapeshifter_gender_picked(datum/act/request/A)
	if(!A.answer)
		return
	open_request(src, /datum/prompt/choice/shapeshift_identity, PROC_REF(shapeshifter_gender_chosen), answerer = src, new_gender = A.answer.value)

/mob/living/carbon/human/proc/shapeshifter_gender_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/shapeshift_identity/ask = A.request
	act_message(src, null, others = span_notice("%U%'s form contorts subtly."))
	change_gender(ask.new_gender)
	change_gender_identity(A.answer.value)

/mob/living/carbon/human/proc/shapeshifter_select_shape()

	set name = "Select Body Shape"
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	open_request(src, /datum/prompt/choice/shapeshifter_form, PROC_REF(shapeshifter_shape_chosen), answerer = src, choices = species.get_valid_shapeshifter_forms(src))

/// Picking a form. Re-checked on the answer: still conscious, and the form is still one to take.
/datum/prompt/choice/shapeshifter_form
	timeout = 0
	title = "Shapeshifter Body"
	question = "Please select a species to emulate."
	ask_flags = ASK_CONSCIOUS

/datum/prompt/choice/shapeshifter_form/recheck_extra()
	. = ..()
	if(.)
		return
	var/mob/living/carbon/human/shifter = asker || answerer
	var/choice = value
	if(!GLOB.all_species[choice] || GLOB.wrapped_species_by_ref["\ref[shifter]"] == choice || !(choice in shifter.species.get_valid_shapeshifter_forms(shifter)))
		return "not a form to take"
	return null

/mob/living/carbon/human/proc/shapeshifter_shape_chosen(datum/act/request/A)
	if(!A.answer)
		return
	shapeshifter_change_shape(A.answer.value)

/*
/mob/living/carbon/human/proc/shapeshifter_change_shape(new_species = null)
	if(!new_species)
		return

	GLOB.wrapped_species_by_ref["\ref[src]"] = new_species
	act_message(src, null, others = span_infoplain(span_bold("%U%") + " shifts and contorts, taking the form of \a [new_species]!"))
	regenerate_icons()
*/

/mob/living/carbon/human/proc/shapeshifter_select_colour()

	set name = "Select Body Colour"
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	open_request(src, /datum/prompt/color, PROC_REF(shapeshifter_colour_chosen), answerer = src, title = "Shapeshifter Colour", question = "Please select a new body color.", default = rgb(r_skin, g_skin, b_skin), ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/shapeshifter_colour_chosen(datum/act/request/A)
	if(!A.answer)
		return
	shapeshifter_set_colour(A.answer.value)

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
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	// Each colour applies as soon as it is picked; a cancel stops there.
	open_request(src, /datum/prompt/color, PROC_REF(shapeshifter_hair_color_step), answerer = src, title = "Hair Colour", question = "Please select a new hair color.", ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/shapeshifter_hair_color_step(datum/act/request/A)
	if(!A.answer)
		return
	shapeshifter_set_hair_color(A.answer.value)
	open_request(src, /datum/prompt/color, PROC_REF(shapeshifter_grad_color_step), answerer = src, title = "Hair Gradient Colour", question = "Please select a new hair gradient color.", ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/shapeshifter_grad_color_step(datum/act/request/A)
	if(!A.answer)
		return
	shapeshifter_set_grad_color(A.answer.value)
	open_request(src, /datum/prompt/color, PROC_REF(shapeshifter_hair_colors_done), answerer = src, title = "Facial Hair Color", question = "Please select a new facial hair color.", ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/shapeshifter_hair_colors_done(datum/act/request/A)
	if(!A.answer)
		return
	shapeshifter_set_facial_color(A.answer.value)

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

	proto_set(src, nameof(species), GLOB.all_species[new_species])
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
			spent(O)

	regenerate_icons()
/* Our own trait system, sorry.
	if(species && mind)
		apply_traits()
*/
	return

/mob/living/carbon/human/proc/shapeshifter_select_eye_colour()

	set name = "Select Eye Color"
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	var/current_color = rgb(r_eyes,g_eyes,b_eyes)
	open_request(src, /datum/prompt/color, PROC_REF(shapeshifter_eye_colour_chosen), answerer = src, title = "Eye Color", question = "Pick a new color for your eyes.", default = current_color, ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/shapeshifter_eye_colour_chosen(datum/act/request/A)
	if(!A.answer)
		return
	shapeshifter_set_eye_color(A.answer.value)

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
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 1 SECONDS)
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
	open_request(src, /datum/prompt/choice/shapeshift_accessory, PROC_REF(shapeshifter_accessory_style_picked), answerer = src, question = I["pick"], title = "Character Preference", choices = pretty_styles, kind = kind)

/// An accessory style, then its colours and alpha; each colour and the alpha can be skipped.
/datum/prompt/choice/shapeshift_accessory
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/kind
	recheck_on_open = TRUE

/datum/prompt/color/shapeshift_accessory
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/kind
	var/style_path
	var/channel
	var/c1
	var/c2

/datum/prompt/number/shapeshift_accessory
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	min_value = 0
	max_value = 255
	step = 1
	var/kind
	var/style_path
	var/c1
	var/c2
	var/c3

/mob/living/carbon/human/proc/shapeshifter_accessory_style_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/shapeshift_accessory/ask = A.request
	shapeshifter_ask_accessory_color(ask.kind, ask.choices[ask.value], 1)

/// The live colour at the opening of each channel's prompt.
/mob/living/carbon/human/proc/shapeshifter_accessory_current_color(kind, suffix)
	switch("[kind][suffix]")
		if("ears")
			return rgb(r_ears, g_ears, b_ears)
		if("ears2")
			return rgb(r_ears2, g_ears2, b_ears2)
		if("ears3")
			return rgb(r_ears3, g_ears3, b_ears3)
		if("tail")
			return rgb(r_tail, g_tail, b_tail)
		if("tail2")
			return rgb(r_tail2, g_tail2, b_tail2)
		if("tail3")
			return rgb(r_tail3, g_tail3, b_tail3)
		if("wings")
			return rgb(r_wing, g_wing, b_wing)
		if("wings2")
			return rgb(r_wing2, g_wing2, b_wing2)
		if("wings3")
			return rgb(r_wing3, g_wing3, b_wing3)

/mob/living/carbon/human/proc/shapeshifter_ask_accessory_color(kind, style_path, channel, c1, c2)
	var/list/info = shapeshifter_accessory_info(kind)
	var/question
	var/title
	var/suffix
	switch(channel)
		if(1)
			question = "Pick primary [info["noun"]] color:"
			title = "[info["title"]] Color (Pri)"
			suffix = ""
		if(2)
			question = "Pick secondary [info["noun"]] color (only applies to some [info["noun"]]s):"
			title = "[info["title"]] Color (sec)"
			suffix = "2"
		if(3)
			question = "Pick tertiary [info["noun"]] color (only applies to some [info["noun"]]s):"
			title = "[info["title"]] Color (ter)"
			suffix = "3"
	open_request(src, /datum/prompt/color/shapeshift_accessory, PROC_REF(shapeshifter_accessory_color_picked), answerer = src, title = title, question = question, default = shapeshifter_accessory_current_color(kind, suffix), kind = kind, style_path = style_path, channel = channel, c1 = c1, c2 = c2)

/mob/living/carbon/human/proc/shapeshifter_accessory_color_picked(datum/act/request/A)
	var/datum/prompt/color/shapeshift_accessory/ask = A.request
	if(!A.answer)
		if(ask.outcome != REQ_CANCELLED || !isnull(ask.value) || request_recheck(ask))
			return
	var/color = A.answer ? ask.value : ""
	switch(ask.channel)
		if(1)
			if(!color)
				shapeshifter_ask_accessory_alpha(ask.kind, ask.style_path, color)
				return
			shapeshifter_ask_accessory_color(ask.kind, ask.style_path, 2, color)
		if(2)
			shapeshifter_ask_accessory_color(ask.kind, ask.style_path, 3, ask.c1, color)
		if(3)
			shapeshifter_ask_accessory_alpha(ask.kind, ask.style_path, ask.c1, ask.c2, color)

/mob/living/carbon/human/proc/shapeshifter_ask_accessory_alpha(kind, style_path, c1, c2, c3)
	var/list/info = shapeshifter_accessory_info(kind)
	var/current_alpha
	switch(kind)
		if("ears")
			current_alpha = a_ears
		if("tail")
			current_alpha = a_tail
		if("wings")
			current_alpha = a_wing
	open_request(src, /datum/prompt/number/shapeshift_accessory, PROC_REF(shapeshifter_accessory_alpha_picked), answerer = src, title = "[info["title"]] Alpha", question = "Set [info["noun"]] alpha (0-255):", default = current_alpha, kind = kind, style_path = style_path, c1 = c1, c2 = c2, c3 = c3)

/mob/living/carbon/human/proc/shapeshifter_accessory_alpha_picked(datum/act/request/A)
	var/datum/prompt/number/shapeshift_accessory/ask = A.request
	if(!A.answer)
		if(ask.outcome != REQ_CANCELLED || !isnull(ask.value) || request_recheck(ask))
			return
	shapeshifter_accessory_chosen(ask.kind, ask.style_path, list("c1" = ask.c1, "c2" = ask.c2, "c3" = ask.c3), A.answer ? ask.value : "")

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
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

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
	open_request(src, /datum/prompt/choice, PROC_REF(shapeshifter_secondary_ears_chosen), answerer = src, title = "Character Preference", question = "Pick some ears!", choices = pretty_ear_styles, ask_flags = ASK_CONSCIOUS, timeout = 0)

/// Sets the style, then asks one colour per channel of it (a cancel keeps that channel) and the alpha.
/mob/living/carbon/human/proc/shapeshifter_secondary_ears_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/ask = A.request
	ear_secondary_style = GLOB.ear_styles_list[ask.choices[ask.value]]
	var/list/defaults = list()
	if(ear_secondary_style)
		for(var/channel in 1 to ear_secondary_style.get_color_channel_count())
			defaults += LAZYACCESS(ear_secondary_colors, channel) || "#ffffff"
	shapeshifter_next_secondary_ear_channel(defaults, list(), 0)

/datum/prompt/color/shapeshift_secondary_ears
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	var/list/defaults
	var/list/new_colors
	var/channel
	recheck_on_open = TRUE

/datum/prompt/number/shapeshift_secondary_ears
	timeout = 0
	ask_flags = ASK_CONSCIOUS
	min_value = 0
	max_value = 255
	step = 1
	var/list/new_colors
	recheck_on_open = TRUE

/mob/living/carbon/human/proc/shapeshifter_next_secondary_ear_channel(list/defaults, list/new_colors, channel)
	channel++
	if(channel > length(defaults))
		open_request(src, /datum/prompt/number/shapeshift_secondary_ears, PROC_REF(shapeshifter_secondary_ear_alpha_picked), answerer = src, question = "Set ear alpha (0-255):", title = "Ear Alpha", default = a_ears2, new_colors = new_colors)
		return
	var/channel_name = GLOB.fancy_sprite_accessory_color_channel_names[channel]
	open_request(src, /datum/prompt/color/shapeshift_secondary_ears, PROC_REF(shapeshifter_secondary_ear_channel_picked), answerer = src, question = "Pick [channel_name]", title = "Ear Color ([channel_name])", default = defaults[channel], defaults = defaults, new_colors = new_colors, channel = channel)

/mob/living/carbon/human/proc/shapeshifter_secondary_ear_channel_picked(datum/act/request/A)
	var/datum/prompt/color/shapeshift_secondary_ears/ask = A.request
	if(!A.answer)
		if(ask.outcome != REQ_CANCELLED || !isnull(ask.value) || request_recheck(ask))
			return
	var/color = A.answer ? ask.value : ""
	var/list/new_colors = ask.new_colors
	new_colors += color || ask.defaults[ask.channel]
	shapeshifter_next_secondary_ear_channel(ask.defaults, new_colors, ask.channel)

/mob/living/carbon/human/proc/shapeshifter_secondary_ear_alpha_picked(datum/act/request/A)
	var/datum/prompt/number/shapeshift_secondary_ears/ask = A.request
	if(!A.answer)
		if(ask.outcome != REQ_CANCELLED || !isnull(ask.value) || request_recheck(ask))
			return
	shapeshifter_secondary_ear_colors_chosen(ask.new_colors, A.answer ? ask.value : "")

/mob/living/carbon/human/proc/shapeshifter_secondary_ear_colors_chosen(list/new_colors, alpha)
	if(length(new_colors))
		ear_secondary_colors = new_colors
	if(alpha)
		a_ears2 = clamp(alpha, 0, 255)
	update_hair()

/mob/living/carbon/human/proc/shapeshifter_select_tail()
	set name = "Select Tail"
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 1 SECONDS)
	shapeshifter_select_accessory("tail")

/mob/living/carbon/human/proc/shapeshifter_select_wings()
	set name = "Select Wings"
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 1 SECONDS)
	shapeshifter_select_accessory("wings")

/mob/living/carbon/human/proc/promethean_select_opaqueness()

	set name = "Toggle Transparency"
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	for(var/obj/item/organ/external/L as anything in src.organs)
		L.transparent = !L.transparent
	act_message(src, null, others = span_notice("%U%'s internal composition seems to change."))
	update_icons_body()
	update_hair()

/mob/living/carbon/human/proc/shapeshifter_change_shape(new_species = null, visible = TRUE) //not sure if this needs to be moved to a separate file but
	if(!new_species)
		return

	dna.base_species = new_species
	var/datum/species/own_species = rel_private(src, nameof(species)) // never write through to a registered species
	own_species.base_species = new_species
	GLOB.wrapped_species_by_ref["\ref[src]"] = new_species
	if (visible)
		act_message(src, null, others = span_filter_notice(span_bold("%U%") + " shifts and contorts, taking the form of \a [new_species]!"))
		regenerate_icons()


//////////////////// Shapeshifter copy-body powers
/// Copied from the protean version, but with some tweaks to match non-protean shapeshifters such as lleill, hanner and replicants

/mob/living/carbon/human/proc/shapeshifter_regenerate()
	set name = "Fully Reform"
	set desc = "Reload your appearance from whatever character slot you have loaded."
	set category = VERB_CAT_ABILITIES_SHAPESHIFT
	open_request(src, /datum/prompt/choice/shapeshift_reform, PROC_REF(shapeshifter_reform_confirmed), answerer = src, title = "Reformation", question = "Do you want to copy the appearance data of your currently loaded save slot?", choices = list("Reform", "Cancel"), finish_proc = PROC_REF(shapeshifter_regenerate_answered))

/// "Are you sure?", then whether to include flavour text and OOC notes.
/datum/prompt/choice/shapeshift_reform
	timeout = 0
	buttons = TRUE
	ask_flags = ASK_CONSCIOUS
	var/finish_proc
	var/flavour
	recheck_on_open = TRUE

/mob/living/carbon/human/proc/shapeshifter_reform_confirmed(datum/act/request/A)
	if(!A.answer || A.request.value == "Cancel")
		return
	var/datum/prompt/choice/shapeshift_reform/ask = A.request
	open_request(src, /datum/prompt/choice/shapeshift_reform, PROC_REF(shapeshifter_reform_flavour_picked), answerer = src, question = "Include Flavourtext?", title = "Reformation", choices = list("Yes", "No", "Cancel"), finish_proc = ask.finish_proc)

/mob/living/carbon/human/proc/shapeshifter_reform_flavour_picked(datum/act/request/A)
	if(!A.answer || A.request.value == "Cancel")
		return
	var/datum/prompt/choice/shapeshift_reform/ask = A.request
	open_request(src, /datum/prompt/choice/shapeshift_reform, PROC_REF(shapeshifter_reform_ooc_picked), answerer = src, question = "Include OOC notes?", title = "Reformation", choices = list("Yes", "No", "Cancel"), finish_proc = ask.finish_proc, flavour = ask.value == "Yes")

/mob/living/carbon/human/proc/shapeshifter_reform_ooc_picked(datum/act/request/A)
	if(!A.answer || A.request.value == "Cancel")
		return
	var/datum/prompt/choice/shapeshift_reform/ask = A.request
	call(src, ask.finish_proc)(ask.flavour, ask.value == "Yes")

/mob/living/carbon/human/proc/shapeshifter_regenerate_answered(flavour, oocnotes)
	to_chat(src, span_notify("You begin to reform. You will need to remain still."))
	act_message(src, null, MSG_SELF(span_danger("You begin to reform.")), MSG_OTHERS(span_notify("%U% rapidly contorts and shifts!")))
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
		act_message(character, null, MSG_SELF(span_danger("You have reformed.")), MSG_OTHERS(span_notify("%U% adopts a new form!")))

/mob/living/carbon/human/proc/shapeshifter_copy_body()
	set name = "Copy Form"
	set desc = "If you are aggressively grabbing someone, with their consent, you can turn into a copy of them. (Without their name)."
	set category = VERB_CAT_ABILITIES_SHAPESHIFT
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
	open_request(src, /datum/prompt/yes_no/copy_body_consent, PROC_REF(shapeshifter_copy_consent_given), answerer = victim, question = "Allow [src] to copy what you look like?", victim = victim)

/// The victim consents, then we choose whether to copy their flavour text.
/datum/prompt/yes_no/copy_body_consent
	title = "Consent"
	timeout = 0
	var/mob/living/carbon/human/victim
	var/initial_refusal

CAPABILITIES(/datum/prompt/yes_no/copy_body_consent)
	ref_one(nameof(victim), /mob/living/carbon/human)

/datum/prompt/yes_no/copy_body_consent/begin()
	initial_refusal = request_recheck(src)
	if(!initial_refusal)
		var/mob/living/carbon/human/H = owner
		initial_refusal = H.copy_body_gripping(victim) ? null : "lost grip"
	if(initial_refusal)
		request_end(src, REQ_CANCELLED, null)
		return
	return ..()

/datum/prompt/yes_no/copy_body_consent/prepare(datum/act/context)
	. = ..()
	var/mob/living/carbon/human/captured = victim
	rel_clear(src, nameof(victim))
	rel_set(src, nameof(victim), captured)

/datum/prompt/yes_no/copy_body_consent/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(victim))
		return "gone"
	if(value)
		var/mob/living/carbon/human/H = owner
		return H.copy_body_gripping(victim) ? null : "lost grip"
	return null

/datum/prompt/choice/copy_body_flavour
	title = "Copy Form"
	timeout = 0
	buttons = TRUE
	ask_flags = ASK_CONSCIOUS
	var/mob/living/carbon/human/victim

CAPABILITIES(/datum/prompt/choice/copy_body_flavour)
	ref_one(nameof(victim), /mob/living/carbon/human)

/datum/prompt/choice/copy_body_flavour/prepare(datum/act/context)
	. = ..()
	var/mob/living/carbon/human/captured = victim
	rel_clear(src, nameof(victim))
	rel_set(src, nameof(victim), captured)

/datum/prompt/choice/copy_body_flavour/recheck_extra()
	. = ..()
	if(.)
		return
	if(QDELETED(victim))
		return "gone"
	if(!isnull(value))
		var/mob/living/carbon/human/H = owner
		return H.copy_body_gripping(victim) ? null : "lost grip"
	return null

/mob/living/carbon/human/proc/shapeshifter_copy_consent_given(datum/act/request/A)
	shapeshifter_copy_consent_step(A)

/mob/living/carbon/human/proc/shapeshifter_copy_consent_step(datum/act/request/A)
	var/datum/prompt/yes_no/copy_body_consent/ask = A.request
	if(ask.initial_refusal || QDELETED(ask.victim))
		return
	if(!A.answer)
		if(!isnull(ask.value) && ask.last_error == "lost grip")
			to_chat(src, span_warning("You lost your grip on [ask.victim]!"))
		else if(ask.outcome == REQ_CANCELLED && isnull(ask.value))
			to_chat(src, span_notice("They declined your request."))
		return
	if(!ask.value)
		to_chat(src, span_notice("They declined your request."))
		return
	open_request(src, /datum/prompt/choice/copy_body_flavour, PROC_REF(shapeshifter_copy_flavour_picked), answerer = src, question = "Copy [ask.victim]'s flavourtext?", choices = list("Yes", "No", "Cancel"), victim = ask.victim)

/mob/living/carbon/human/proc/shapeshifter_copy_flavour_picked(datum/act/request/A)
	shapeshifter_copy_flavour_step(A)

/mob/living/carbon/human/proc/shapeshifter_copy_flavour_step(datum/act/request/A)
	var/datum/prompt/choice/copy_body_flavour/ask = A.request
	if(QDELETED(ask.victim))
		return
	if(!A.answer)
		if(!isnull(ask.value) && ask.last_error == "lost grip")
			to_chat(src, span_warning("You lost your grip on [ask.victim]!"))
		return
	copy_body_flavour_chosen(ask.victim, ask.value)

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
	act_message(src, victim, MSG_SELF(span_danger("You begin to reassemble into %T%.")), MSG_OTHERS(span_notify("%U% rapidly contorts and shifts!")))
	om_task_timed(src, 4 SECONDS, target = victim, receiver = src, on_done = PROC_REF(copy_body_done), done_args = list(victim, flavour))

/mob/living/carbon/human/proc/copy_body_done(mob/living/carbon/human/victim, flavour)
	if (!copy_body_gripping(victim))
		to_chat(src, span_warning("You lost your grip on [victim]!"))
		return
	if(client)	//Make sure we didn't d/c
		transform_into_other_human(victim, new /datum/human_transform_options(copy_flavour = flavour, apply_bloodtype = FALSE))
		act_message(src, victim, MSG_SELF(span_danger("You have reassembled into %T%.")), MSG_OTHERS(span_notify("%U% adopts the form of %T%!")))


/mob/living/carbon/human/proc/shapeshifter_reassemble()

	set name = "Complete Reform"
	set category = VERB_CAT_ABILITIES_SHAPESHIFT

	if(stat || !COOLDOWN_FINISHED(src, last_special))
		return

	COOLDOWN_START(src, last_special, 5 SECONDS)

	open_request(src, /datum/prompt/choice/shapeshift_reform, PROC_REF(shapeshifter_reform_confirmed), answerer = src, title = "Reform", question = "Are you sure you want to reform yourself? This will reset you to what you look like in your current preferences slot.", choices = list("Yes", "Cancel"), finish_proc = PROC_REF(shapeshifter_reassemble_answered))

/mob/living/carbon/human/proc/shapeshifter_reassemble_answered(flavour, oocnotes)
	to_chat(src, span_notify("You begin to reform. You will need to remain still."))
	act_message(src, null, MSG_SELF(span_danger("You begin to reform.")), MSG_OTHERS(span_notify("%U% rapidly contorts and shifts!")))
	om_task_timed(src, 4 SECONDS, target = src, receiver = src, on_done = PROC_REF(shapeshifter_reassemble_human_done), done_args = list(flavour, oocnotes))

/mob/living/carbon/human/proc/shapeshifter_reassemble_human_done(flavour, oocnotes)
	if (client?.prefs)
		client.prefs.vanity_copy_to(src, FALSE, flavour, oocnotes, FALSE)
		act_message(src, null, MSG_SELF(span_danger("You have reformed.")), MSG_OTHERS(span_notify("%U% adopts a new form!")))

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
