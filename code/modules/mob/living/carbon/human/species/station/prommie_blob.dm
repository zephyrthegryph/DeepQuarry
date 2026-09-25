// The promethean's true form: the character's own mob as a slime. Tougher
// against blows, far more vulnerable to heat, and it keeps its hat.

/datum/component/forms/promethean

/datum/component/forms/promethean/get_form_types()
	var/static/list/types = list(/datum/form/human, /datum/form/promethean_blob)
	return types

/datum/form/promethean_blob
	name = "promethean blob"
	id = "promethean_blob"
	form_flag = FORM_FLAG_PROMETHEAN_BLOB
	draws_body = FALSE
	factors = alist(BF_INCOMING_PHYSICAL = 0.75, BF_INCOMING_THERMAL = 2)
	enter_message = "squishes into their true form!"
	enter_sound = 'sound/effects/slime_squish.ogg'
	/// Spread out into an adult-sized puddle.
	var/is_wide = FALSE
	/// Gemstone shine overlay.
	var/shiny = FALSE

/datum/form/promethean_blob/get_form_verbs()
	var/static/list/form_verbs = list(
		/mob/living/carbon/human/proc/prommie_toggle_expand,
		/mob/living/carbon/human/proc/prommie_toggle_shine,
		/mob/living/carbon/human/proc/prommie_select_colour,
	)
	return form_verbs

/datum/form/promethean_blob/on_enter(datum/component/forms/F, mob/living/carbon/human/H)
	release_everything(H)
	..()

/datum/form/promethean_blob/on_exit(datum/component/forms/F, mob/living/carbon/human/H)
	..()
	H.visible_message(span_infoplain(span_bold("[H.name]") + " pulls together, forming a humanoid shape!"))
	playsound(H, 'sound/effects/slime_squish.ogg', 15)

/datum/form/promethean_blob/build_overlays(datum/component/forms/F, mob/living/carbon/human/H)
	var/slime_icon = 'icons/mob/slime2.dmi'
	. = list()
	var/image/body = image(slime_icon, "slime [is_wide ? "adult" : "baby"]")
	body.color = rgb(H.r_skin, H.g_skin, H.b_skin)
	body.appearance_flags |= (RESET_COLOR | PIXEL_SCALE)
	. += body
	if(H.stat == DEAD)
		return
	var/image/light = image(slime_icon, "slime light")
	light.appearance_flags |= RESET_COLOR
	. += light
	if(shiny)
		var/image/shine = image(slime_icon, "slime shiny")
		shine.appearance_flags |= RESET_COLOR
		. += shine
	var/image/mood = image(slime_icon, "aslime-:3")
	mood.appearance_flags |= RESET_COLOR
	. += mood
	// Hat simulator: whatever is on the head stays there.
	if(H.get_equipped_item(SLOT_ID_HEAD))
		var/hat_state = H.get_equipped_item(SLOT_ID_HEAD).item_state ? H.get_equipped_item(SLOT_ID_HEAD).item_state : H.get_equipped_item(SLOT_ID_HEAD).icon_state
		var/image/hat = image('icons/inventory/head/mob.dmi', hat_state)
		hat.pixel_y = -7
		hat.color = H.get_equipped_item(SLOT_ID_HEAD).color
		hat.appearance_flags |= (RESET_COLOR | KEEP_APART)
		. += hat

/// Slime bodies knit a little on their own, and pain fades fast.
/datum/form/promethean_blob/on_life(datum/component/forms/F, mob/living/carbon/human/H)
	H.mend(TREAT_OXYGENATION, 0.2)
	H.mend(TREAT_ANTITOXIN, 0.2)
	H.mend(TREAT_BURN_CARE, 0.2)
	H.mend(TREAT_GENETIC_REPAIR, 0.2)
	H.mend(TREAT_TISSUE_REPAIR, 0.2)
	H.mend(TREAT_ANALGESIC, 6)

/mob/living/carbon/human/proc/prommie_blobform()
	set name = "Toggle Blobform"
	set desc = "Switch between amorphous and humanoid forms."
	set category = "Abilities.Promethean"

	var/datum/component/forms/F = get_forms()
	if(!F)
		return
	if(!isturf(loc))
		to_chat(src, span_warning("You need more space to perform this action!"))
		return
	if(stat || get_paralysis() || get_stunned() || get_weakened() || restrained())
		to_chat(src, span_warning("You can only do this while not stunned."))
		return
	if(F.is_form(/datum/form/promethean_blob))
		F.set_form(/datum/form/human)
	else
		F.set_form(/datum/form/promethean_blob)

/mob/living/carbon/human/proc/prommie_toggle_expand()
	set name = "Toggle Width"
	set desc = "Switch between smole and lorge."
	set category = "Abilities.Promethean"

	var/datum/form/promethean_blob/B = current_form()
	if(!istype(B) || stat || world.time < last_special)
		return
	last_special = world.time + 2.5 SECONDS
	B.is_wide = !B.is_wide
	if(B.is_wide)
		visible_message(span_infoplain(span_bold("[name]") + " flows outwards, their goop expanding!"))
	else
		visible_message(span_infoplain(span_bold("[name]") + " pulls together, compacting themselves into a small ball!"))
	get_forms().refresh_appearance()

/mob/living/carbon/human/proc/prommie_toggle_shine()
	set name = "Toggle Shine"
	set desc = "Shine on you crazy diamond."
	set category = "Abilities.Promethean"

	var/datum/form/promethean_blob/B = current_form()
	if(!istype(B) || stat || world.time < last_special)
		return
	last_special = world.time + 2.5 SECONDS
	B.shiny = !B.shiny
	if(B.shiny)
		visible_message(span_infoplain(span_bold("[name]") + " glistens and sparkles, shining brilliantly."))
	else
		visible_message(span_infoplain(span_bold("[name]") + " dulls their shine, becoming more translucent."))
	get_forms().refresh_appearance()

/mob/living/carbon/human/proc/prommie_select_colour()
	set name = "Select Body Colour"
	set category = "Abilities.Promethean"

	if(!istype(current_form(), /datum/form/promethean_blob) || stat || world.time < last_special)
		return
	last_special = world.time + 2.5 SECONDS
	var/new_skin = tgui_color_picker(src, "Please select a new body color.", "Shapeshifter Colour", rgb(r_skin, g_skin, b_skin))
	if(!new_skin || stat)
		return
	shapeshifter_set_colour(new_skin)
	get_forms()?.refresh_appearance()
