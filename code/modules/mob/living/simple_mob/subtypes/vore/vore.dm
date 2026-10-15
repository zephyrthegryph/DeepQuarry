/mob/living/simple_mob/vore

/mob/living/simple_mob
	var/nameset
	var/limit_renames = TRUE
	var/copy_prefs_to_mob = TRUE

/mob/living/simple_mob/Login()
	. = ..()

	if(copy_prefs_to_mob)
		login_prefs()

/mob/living/proc/login_prefs()

	identity().ooc_notes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes)
	identity().ooc_notes_likes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_likes)
	identity().ooc_notes_dislikes = client.prefs.read_preference(/datum/preference/text/living/ooc_notes_dislikes)
	identity().ooc_notes_favs = read_preference(/datum/preference/text/living/ooc_notes_favs)
	identity().ooc_notes_maybes = read_preference(/datum/preference/text/living/ooc_notes_maybes)
	identity().ooc_notes_style = read_preference(/datum/preference/toggle/living/ooc_notes_style)
	private_notes = client.prefs.read_preference(/datum/preference/text/living/private_notes)
	vore_prefs.set_digestable(client.prefs_vr.digestable)
	vore_prefs.set_devourable(client.prefs_vr.devourable)
	vore_prefs.set_absorbable(client.prefs_vr.absorbable)
	vore_prefs.feeding = client.prefs_vr.feeding
	vore_prefs.can_be_drop_prey = client.prefs_vr.can_be_drop_prey
	vore_prefs.can_be_drop_pred = client.prefs_vr.can_be_drop_pred
	vore_prefs.can_be_afk_prey = client.prefs_vr.can_be_afk_prey
	vore_prefs.can_be_afk_pred = client.prefs_vr.can_be_afk_pred
	vore_prefs.throw_vore = client.prefs_vr.throw_vore
	vore_prefs.food_vore = client.prefs_vr.food_vore
	rel_set(src, nameof(spont_belly_rear), client.prefs_vr.spont_belly_rear)
	rel_set(src, nameof(spont_belly_left), client.prefs_vr.spont_belly_left)
	rel_set(src, nameof(spont_belly_front), client.prefs_vr.spont_belly_front)
	rel_set(src, nameof(spont_belly_right), client.prefs_vr.spont_belly_right)
	vore_prefs.consume_liquid_belly = client.prefs_vr.consume_liquid_belly
	vore_prefs.allow_spontaneous_tf = client.prefs_vr.allow_spontaneous_tf
	vore_prefs.digest_leave_remains = client.prefs_vr.digest_leave_remains
	vore_prefs.allowmobvore = client.prefs_vr.allowmobvore
	vore_prefs.set_permit_healbelly(client.prefs_vr.permit_healbelly)
	vore_prefs.noisy = client.prefs_vr.noisy
	vore_prefs.selective_preference = client.prefs_vr.selective_preference
	vore_prefs.size_strip_preference = client.prefs_vr.size_strip_preference
	vore_prefs.eating_privacy_global = client.prefs_vr.eating_privacy_global
	vore_prefs.allow_mimicry = client.prefs_vr.allow_mimicry
	vore_prefs.allowtemp = client.prefs_vr.allowtemp

	vore_prefs.drop_vore = client.prefs_vr.drop_vore
	vore_prefs.stumble_vore = client.prefs_vr.stumble_vore
	vore_prefs.slip_vore = client.prefs_vr.slip_vore
	vore_prefs.digest_pain = client.prefs_vr.digest_pain

	vore_prefs.resizable = client.prefs_vr.resizable
	vore_prefs.show_vore_fx = client.prefs_vr.show_vore_fx
	vore_prefs.step_mechanics_pref = client.prefs_vr.step_mechanics_pref
	vore_prefs.pickup_pref = client.prefs_vr.pickup_pref
	vore_prefs.allow_mind_transfer = client.prefs_vr.allow_mind_transfer

	vore_prefs.phase_vore = client.prefs_vr.phase_vore
	vore_prefs.latejoin_vore = client.prefs_vr.latejoin_vore
	vore_prefs.latejoin_prey = client.prefs_vr.latejoin_prey
	vore_prefs.receive_reagents = client.prefs_vr.receive_reagents
	vore_prefs.give_reagents = client.prefs_vr.give_reagents
	vore_prefs.apply_reagents = client.prefs_vr.apply_reagents
	autotransferable = client.prefs_vr.autotransferable
	vore_prefs.noisy_full = client.prefs_vr.noisy_full
	vore_prefs.set_strip_pref(client.prefs_vr.strip_pref)
	vore_prefs.set_contaminate_pref(client.prefs_vr.contaminate_pref)
	vore_prefs.set_vore_sprite_color(client.prefs_vr.vore_sprite_color)
	vore_prefs.set_vore_sprite_multiply(client.prefs_vr.vore_sprite_multiply)
	vore_prefs.no_latejoin_vore_warning = client.prefs_vr.no_latejoin_vore_warning
	vore_prefs.no_latejoin_prey_warning = client.prefs_vr.no_latejoin_prey_warning
	vore_prefs.no_latejoin_vore_warning_time = client.prefs_vr.no_latejoin_vore_warning_time
	vore_prefs.no_latejoin_prey_warning_time = client.prefs_vr.no_latejoin_prey_warning_time
	vore_prefs.no_latejoin_vore_warning_persists = client.prefs_vr.no_latejoin_vore_warning_persists
	vore_prefs.no_latejoin_prey_warning_persists = client.prefs_vr.no_latejoin_prey_warning_persists
	vore_prefs.max_voreoverlay_alpha = client.prefs_vr.max_voreoverlay_alpha
	vore_prefs.belly_rub_target = client.prefs_vr.belly_rub_target
	vore_prefs.soulcatcher_pref_flags = client.prefs_vr.soulcatcher_pref_flags
	vore_prefs.persistend_edit_mode = client.prefs_vr.persistend_edit_mode

/mob/living/simple_mob/proc/set_name()
	set name = "Set Name"
	set desc = "Sets your mobs name. You only get to do this once."
	set category = VERB_CAT_ABILITIES_SETTINGS
	if(limit_renames && nameset)
		to_chat(src, span_userdanger("You've already set your name. Ask an admin to toggle \"nameset\" to 0 if you really must."))
		return
	open_request(src, /datum/prompt/text, PROC_REF(name_set_entered), answerer = src, title = "Name set", question = "Set your name. You only get to do this once. Max 52 chars.", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE, timeout = 0)

/mob/living/simple_mob/proc/name_set_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/newname = A.answer.value
	newname = sanitizeSafe(newname, MAX_NAME_LEN)
	if(limit_renames && nameset)
		return
	if (newname)
		name = newname
		voice_name = newname
		nameset = 1

/mob/living/simple_mob/proc/set_desc()
	set name = "Set Description"
	set desc = "Set your description."
	set category = VERB_CAT_ABILITIES_SETTINGS
	open_request(src, /datum/prompt/text, PROC_REF(desc_set_entered), answerer = src, title = "Description set", question = "Set your description. Max 4096 chars.", multiline = TRUE, encode = FALSE, timeout = 0)

/mob/living/simple_mob/proc/desc_set_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/newdesc = A.answer.value
	newdesc = sanitizeSafe(newdesc, MAX_MESSAGE_LEN)
	if(newdesc)
		desc = newdesc

/mob/living/simple_mob/proc/set_gender()
	set name = "Set Gender"
	set desc = "Set your gender."
	set category = VERB_CAT_ABILITIES_SETTINGS
	open_request(src, /datum/prompt/choice, PROC_REF(gender_set_chosen), answerer = src, title = "Set Gender", question = "Please select a gender:", choices = list(FEMALE, MALE, NEUTER, PLURAL), timeout = 0)

/mob/living/simple_mob/proc/gender_set_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/newgender = A.answer.value
	gender = newgender

/mob/living/simple_mob/vore/aggressive

CAPABILITIES(/mob/living/simple_mob/vore/aggressive)
	configure(mob_movement(bump = HEAVY))

