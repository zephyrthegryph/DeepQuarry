// DQAdd — Spawn the NIF item onto the character at spawn from the three NIF prefs.
// Lives in a hook because the spawn depends on three prefs together (path + durability +
// savedata), and the per-pref apply for nif_path alone doesn't know about durability or
// savedata.

/datum/preference_apply_hook/nif
	priority = APPLY_HOOK_PRIORITY_LATE
	skip_on_preview = TRUE

/datum/preference_apply_hook/nif/apply(mob/living/carbon/human/target, datum/preferences/preferences)
	if(!ishuman(target) || ismannequin(target))
		return

	var/obj/item/nif/nif_path = preferences.read_preference(/datum/preference/nif_path)
	var/nif_durability = preferences.read_preference(/datum/preference/numeric/nif_durability)
	var/list/nif_savedata = preferences.read_preference(/datum/preference/nif_savedata)
	if(!ispath(nif_path) || !nif_durability)
		return
	new nif_path(target, nif_durability, nif_savedata)
