// The promethean's true form: the character's own mob as a slime. Tougher
// against blows, far more vulnerable to heat, and it keeps its hat.

/datum/forms/promethean

TYPE_TABLE(/datum/forms/promethean, get_form_types, list(/datum/form/human, /datum/form/promethean_blob))

/datum/form/promethean_blob
	name = "promethean blob"
	id = "promethean_blob"
	form_flag = FORM_FLAG_PROMETHEAN_BLOB
	ticks = TRUE
	draws_body = FALSE
	factors = alist(BF_INCOMING_PHYSICAL = 0.75, BF_INCOMING_THERMAL = 2)
	enter_message = "squishes into their true form!"
	enter_sound = SFX_EFFECTS_SLIME_SQUISH
	/// Spread out into an adult-sized puddle.
	var/is_wide = FALSE
	/// Gemstone shine overlay.
	var/shiny = FALSE

TYPE_TABLE(/datum/form/promethean_blob, get_form_verbs, list( \
		/mob/living/carbon/human/proc/prommie_toggle_expand, \
		/mob/living/carbon/human/proc/prommie_toggle_shine, \
		/mob/living/carbon/human/proc/prommie_select_colour, \
	))

/datum/form/promethean_blob/on_enter(datum/forms/F, mob/living/carbon/human/H)
	release_everything(H)
	..()

/datum/form/promethean_blob/on_exit(datum/forms/F, mob/living/carbon/human/H)
	..()
	act_message(H, null, others = span_infoplain(span_bold("%U%") + " pulls together, forming a humanoid shape!"))
	play_sfx(H, SFX_EFFECTS_SLIME_SQUISH, 0.3, vary = FALSE)

/datum/form/promethean_blob/build_overlays(datum/forms/F, mob/living/carbon/human/H)
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
/datum/form/promethean_blob/on_life(datum/forms/F, mob/living/carbon/human/H)
	H.mend(TREAT_OXYGENATION, 0.2)
	H.mend(TREAT_ANTITOXIN, 0.2)
	H.mend(TREAT_BURN_CARE, 0.2)
	H.mend(TREAT_GENETIC_REPAIR, 0.2)
	H.mend(TREAT_TISSUE_REPAIR, 0.2)
	H.mend(TREAT_ANALGESIC, 6)

/mob/living/carbon/human/proc/prommie_blobform()
	set name = "Toggle Blobform"
	set desc = "Switch between amorphous and humanoid forms."
	set category = VERB_CAT_ABILITIES_PROMETHEAN

	var/datum/forms/F = get_forms()
	if(!F)
		return
	if(!isturf(loc))
		to_chat(src, span_warning("You need more space to perform this action!"))
		return
	if(stat || has_status(STAT_PARALYZED) || has_status(STAT_STUNNED) || has_status(STAT_WEAKENED) || restrained())
		to_chat(src, span_warning("You can only do this while not stunned."))
		return
	if(F.is_form(/datum/form/promethean_blob))
		F.set_form(/datum/form/human)
	else
		F.set_form(/datum/form/promethean_blob)

/mob/living/carbon/human/proc/prommie_toggle_expand()
	set name = "Toggle Width"
	set desc = "Switch between smole and lorge."
	set category = VERB_CAT_ABILITIES_PROMETHEAN

	var/datum/form/promethean_blob/B = current_form()
	if(!istype(B) || stat || !COOLDOWN_FINISHED(src, last_special))
		return
	COOLDOWN_START(src, last_special, 2.5 SECONDS)
	B.is_wide = !B.is_wide
	if(B.is_wide)
		visible_message(span_infoplain(span_bold("[name]") + " flows outwards, their goop expanding!"))
	else
		visible_message(span_infoplain(span_bold("[name]") + " pulls together, compacting themselves into a small ball!"))
	get_forms().refresh_appearance()

/mob/living/carbon/human/proc/prommie_toggle_shine()
	set name = "Toggle Shine"
	set desc = "Shine on you crazy diamond."
	set category = VERB_CAT_ABILITIES_PROMETHEAN

	var/datum/form/promethean_blob/B = current_form()
	if(!istype(B) || stat || !COOLDOWN_FINISHED(src, last_special))
		return
	COOLDOWN_START(src, last_special, 2.5 SECONDS)
	B.shiny = !B.shiny
	if(B.shiny)
		visible_message(span_infoplain(span_bold("[name]") + " glistens and sparkles, shining brilliantly."))
	else
		visible_message(span_infoplain(span_bold("[name]") + " dulls their shine, becoming more translucent."))
	get_forms().refresh_appearance()

/mob/living/carbon/human/proc/prommie_select_colour()
	set name = "Select Body Colour"
	set category = VERB_CAT_ABILITIES_PROMETHEAN

	if(!istype(current_form(), /datum/form/promethean_blob) || stat || !COOLDOWN_FINISHED(src, last_special))
		return
	COOLDOWN_START(src, last_special, 2.5 SECONDS)
	open_request(src, /datum/prompt/color, PROC_REF(prommie_colour_chosen), answerer = src, title = "Shapeshifter Colour", question = "Please select a new body color.", default = rgb(r_skin, g_skin, b_skin), ask_flags = ASK_CONSCIOUS, timeout = 0)

/mob/living/carbon/human/proc/prommie_colour_chosen(datum/act/request/A)
	if(!A.answer)
		return
	if(!A.answer.value)
		return
	shapeshifter_set_colour(A.answer.value)
	get_forms()?.refresh_appearance()
