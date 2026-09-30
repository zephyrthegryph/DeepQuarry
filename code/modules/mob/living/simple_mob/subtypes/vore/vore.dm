/mob/living/simple_mob/vore
	mob_class = MOB_CLASS_ANIMAL
	mob_bump_flag = 0
	can_be_drop_pred = TRUE

/mob/living/simple_mob
	var/nameset
	var/limit_renames = TRUE
	var/copy_prefs_to_mob = TRUE

DECLARE_LOGIN_VERB(/mob/living/simple_mob, /mob/living/simple_mob/proc/set_name)
DECLARE_LOGIN_VERB(/mob/living/simple_mob, /mob/living/simple_mob/proc/set_desc)
DECLARE_LOGIN_VERB(/mob/living/simple_mob, /mob/living/simple_mob/proc/set_gender)

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
	digestable = client.prefs_vr.digestable
	devourable = client.prefs_vr.devourable
	absorbable = client.prefs_vr.absorbable
	feeding = client.prefs_vr.feeding
	can_be_drop_prey = client.prefs_vr.can_be_drop_prey
	can_be_drop_pred = client.prefs_vr.can_be_drop_pred
	can_be_afk_prey = client.prefs_vr.can_be_afk_prey
	can_be_afk_pred = client.prefs_vr.can_be_afk_pred
	throw_vore = client.prefs_vr.throw_vore
	food_vore = client.prefs_vr.food_vore
	rel_set(src, nameof(spont_belly_rear), client.prefs_vr.spont_belly_rear)
	rel_set(src, nameof(spont_belly_left), client.prefs_vr.spont_belly_left)
	rel_set(src, nameof(spont_belly_front), client.prefs_vr.spont_belly_front)
	rel_set(src, nameof(spont_belly_right), client.prefs_vr.spont_belly_right)
	consume_liquid_belly = client.prefs_vr.consume_liquid_belly
	allow_spontaneous_tf = client.prefs_vr.allow_spontaneous_tf
	digest_leave_remains = client.prefs_vr.digest_leave_remains
	allowmobvore = client.prefs_vr.allowmobvore
	permit_healbelly = client.prefs_vr.permit_healbelly
	noisy = client.prefs_vr.noisy
	selective_preference = client.prefs_vr.selective_preference
	size_strip_preference = client.prefs_vr.size_strip_preference
	eating_privacy_global = client.prefs_vr.eating_privacy_global
	allow_mimicry = client.prefs_vr.allow_mimicry
	allowtemp = client.prefs_vr.allowtemp

	drop_vore = client.prefs_vr.drop_vore
	stumble_vore = client.prefs_vr.stumble_vore
	slip_vore = client.prefs_vr.slip_vore
	digest_pain = client.prefs_vr.digest_pain

	resizable = client.prefs_vr.resizable
	show_vore_fx = client.prefs_vr.show_vore_fx
	step_mechanics_pref = client.prefs_vr.step_mechanics_pref
	pickup_pref = client.prefs_vr.pickup_pref
	allow_mind_transfer = client.prefs_vr.allow_mind_transfer

	phase_vore = client.prefs_vr.phase_vore
	latejoin_vore = client.prefs_vr.latejoin_vore
	latejoin_prey = client.prefs_vr.latejoin_prey
	receive_reagents = client.prefs_vr.receive_reagents
	give_reagents = client.prefs_vr.give_reagents
	apply_reagents = client.prefs_vr.apply_reagents
	autotransferable = client.prefs_vr.autotransferable
	noisy_full = client.prefs_vr.noisy_full
	strip_pref = client.prefs_vr.strip_pref
	contaminate_pref = client.prefs_vr.contaminate_pref
	vore_sprite_color = client.prefs_vr.vore_sprite_color
	vore_sprite_multiply = client.prefs_vr.vore_sprite_multiply
	no_latejoin_vore_warning = client.prefs_vr.no_latejoin_vore_warning
	no_latejoin_prey_warning = client.prefs_vr.no_latejoin_prey_warning
	no_latejoin_vore_warning_time = client.prefs_vr.no_latejoin_vore_warning_time
	no_latejoin_prey_warning_time = client.prefs_vr.no_latejoin_prey_warning_time
	no_latejoin_vore_warning_persists = client.prefs_vr.no_latejoin_vore_warning_persists
	no_latejoin_prey_warning_persists = client.prefs_vr.no_latejoin_prey_warning_persists
	max_voreoverlay_alpha = client.prefs_vr.max_voreoverlay_alpha
	belly_rub_target = client.prefs_vr.belly_rub_target
	soulcatcher_pref_flags = client.prefs_vr.soulcatcher_pref_flags
	persistend_edit_mode = client.prefs_vr.persistend_edit_mode

/mob/living/simple_mob/proc/set_name()
	set name = "Set Name"
	set desc = "Sets your mobs name. You only get to do this once."
	set category = VERB_CAT_ABILITIES_SETTINGS
	if(limit_renames && nameset)
		to_chat(src, span_userdanger("You've already set your name. Ask an admin to toggle \"nameset\" to 0 if you really must."))
		return
	om_ask(src, /datum/om/prompt/text, PROC_REF(name_set_entered), title = "Name set", message = "Set your name. You only get to do this once. Max 52 chars.", max_length = MAX_NAME_LEN, encode = FALSE)

/mob/living/simple_mob/proc/name_set_entered(datum/om/prompt/text/ask)
	var/newname = ask.text
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
	om_ask(src, /datum/om/prompt/text, PROC_REF(desc_set_entered), title = "Description set", message = "Set your description. Max 4096 chars.", multiline = TRUE, encode = FALSE)

/mob/living/simple_mob/proc/desc_set_entered(datum/om/prompt/text/ask)
	var/newdesc = ask.text
	newdesc = sanitizeSafe(newdesc, MAX_MESSAGE_LEN)
	if(newdesc)
		desc = newdesc

/mob/living/simple_mob/proc/set_gender()
	set name = "Set Gender"
	set desc = "Set your gender."
	set category = VERB_CAT_ABILITIES_SETTINGS
	om_ask(src, /datum/om/prompt/choice, PROC_REF(gender_set_chosen), title = "Set Gender", message = "Please select a gender:", choices = list(FEMALE, MALE, NEUTER, PLURAL))

/mob/living/simple_mob/proc/gender_set_chosen(datum/om/prompt/choice/ask)
	var/newgender = ask.choice
	gender = newgender

/mob/living/simple_mob/vore/aggressive
	mob_bump_flag = HEAVY

