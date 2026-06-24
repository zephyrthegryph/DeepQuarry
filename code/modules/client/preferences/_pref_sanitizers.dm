// per-pref sanitize() overrides. Migrated from the Bay handlers' sanitize_character
// procs into the new architecture. The central sanitize_preferences() proc walks the
// registry and invokes sanitize() on each entry; cross-pref invariants stay in
// /datum/preference_constraint subtypes.

// ----- Thermal messages: cap to 10 entries -----

/datum/preference/custom_heat/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value))
		return list()
	if(value.len > 10)
		value.Cut(11)
	return value

/datum/preference/custom_cold/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value))
		return list()
	if(value.len > 10)
		value.Cut(11)
	return value

// ----- Language lists: type guards + species-relative truncation -----

/datum/preference/alternate_languages/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value))
		return list()
	var/datum/species/S = GLOB.all_species[preferences.read_preference(/datum/preference/choiced/species)]
	if(!S)
		return value
	var/extra = preferences.read_preference(/datum/preference/numeric/human/extra_languages) || 0
	var/cap = S.num_alternate_languages + extra
	if(value.len > cap)
		value.len = cap
	// Strip illegal languages (not in species secondary list AND not whitelisted).
	// Iterate over a Copy() — DM's `for(var/x in list)` over an assoc list
	// whose entries are being removed underneath produces undefined skips.
	for(var/language in value.Copy())
		var/datum/language/L = GLOB.all_languages[language]
		if(!istype(L) || (L.flags & RESTRICTED))
			value -= language
			continue
		if(!(language in S.secondary_langs) && preferences.client && !is_lang_whitelisted(preferences.client, L))
			value -= language
	return value

/datum/preference/language_prefixes/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value) || !value.len)
		var/list/defaults = CONFIG_GET(str_list/language_prefixes)
		return defaults.Copy()
	var/static/list/forbidden_prefixes = list(";", ":", ".", "!", "*", "^", "-")
	for(var/prefix in value.Copy()) // iterate copy; mutating `value` mid-loop skips entries
		if(prefix in forbidden_prefixes)
			value -= prefix
	return value

/datum/preference/language_custom_keys/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value))
		return list()
	var/datum/species/S = GLOB.all_species[preferences.read_preference(/datum/preference/choiced/species)]
	var/list/alt = preferences.read_preference(/datum/preference/alternate_languages) || list()
	for(var/key in value.Copy()) // iterate copy; .Remove() mid-loop skips entries
		var/lang = value[key]
		if(!lang)
			value.Remove(key)
			continue
		if(!S)
			continue
		if((lang == S.language) || (lang == S.default_language && S.default_language != S.language) || (lang in alt))
			continue
		value.Remove(key)
	return value

// ----- Body markings: type guard, strip unknown styles, init per-marking sub-lists -----

/datum/preference/body_markings/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value))
		value = list()
	value &= GLOB.body_marking_styles_list
	for(var/M in value)
		if(!islist(value[M]))
			var/col = istext(value[M]) ? value[M] : "#000000"
			value[M] = preferences.mass_edit_marking_list(M, color = col)
	return value

// ----- Ear secondary colors: list, length cap, hex sanitize -----

/datum/preference/ear_secondary_colors/sanitize(list/value, datum/preferences/preferences)
	value = SANITIZE_LIST(value)
	var/cap = length(GLOB.fancy_sprite_accessory_color_channel_names)
	if(value.len > cap)
		value.len = cap
	for(var/i in 1 to value.len)
		value[i] = sanitize_hexcolor(value[i], "#ffffff")
	return value

// ----- bgstate must be in the choice list -----

/datum/preference/text/human/bgstate/sanitize(value, datum/preferences/preferences)
	if(!value || !(value in bgstate_choices))
		return "000"
	return value

// ----- Size / Voice / Sound clamps + defaults -----

/datum/preference/numeric/human/weight_vr/sanitize(value, datum/preferences/preferences)
	return sanitize_integer(value, WEIGHT_MIN, WEIGHT_MAX, 137)

/datum/preference/numeric/human/weight_gain/sanitize(value, datum/preferences/preferences)
	return sanitize_integer(value, 0, 100, 100)

/datum/preference/numeric/human/weight_loss/sanitize(value, datum/preferences/preferences)
	return sanitize_integer(value, 0, 100, 50)

/datum/preference/toggle/human/fuzzy/sanitize(value, datum/preferences/preferences)
	return sanitize_integer(value, 0, 1, 0)

/datum/preference/toggle/human/offset_override/sanitize(value, datum/preferences/preferences)
	return sanitize_integer(value, 0, 1, TRUE)

/datum/preference/numeric/human/voice_freq/sanitize(value, datum/preferences/preferences)
	if(value == 0)
		return 0
	return sanitize_integer(value, MIN_VOICE_FREQ, MAX_VOICE_FREQ, 42500)

/datum/preference/numeric/human/size_multiplier/sanitize(value, datum/preferences/preferences)
	if(isnull(value) || value < RESIZE_TINY || value > RESIZE_HUGE)
		return RESIZE_NORMAL
	return value

/datum/preference/text/human/custom_speech_bubble/sanitize(value, datum/preferences/preferences)
	if(!(value in GLOB.selectable_speech_bubbles))
		return "default"
	return value

/datum/preference/text/human/custom_footstep/sanitize(value, datum/preferences/preferences)
	return value || "Default"

/datum/preference/text/human/species_sound/sanitize(value, datum/preferences/preferences)
	return value || "Unset"

// ----- Trait list type guards -----
// Structural guards only — the typed_list base's pref_deserialize already does the
// per-entry typepath check on load, so by the time sanitize sees the value it's already
// a list of trait paths. Keep these as a defensive backstop.

/datum/preference/typed_list/traits/pos_traits/sanitize(value, datum/preferences/preferences)
	return islist(value) ? value : list()

/datum/preference/typed_list/traits/neu_traits/sanitize(value, datum/preferences/preferences)
	return islist(value) ? value : list()

/datum/preference/typed_list/traits/neg_traits/sanitize(value, datum/preferences/preferences)
	return islist(value) ? value : list()

// ----- Blood -----

/datum/preference/color/human/blood_color/sanitize(value, datum/preferences/preferences)
	return sanitize_hexcolor(value, default = "#A10808")

/datum/preference/text/human/blood_reagents/sanitize(value, datum/preferences/preferences)
	return sanitize_text(value, "default")

// ----- NIF -----

/datum/preference/nif_path/sanitize(value, datum/preferences/preferences)
	if(value && !ispath(value))
		value = text2path(value)
	if(value && !ispath(value, /obj/item/nif))
		return null
	// No-free-NIFs check for protean: handled by /datum/preference_constraint/species_strips_protean_nif.
	return value

/datum/preference/nif_savedata/sanitize(value, datum/preferences/preferences)
	return islist(value) ? value : list()

// ----- Underwear: type guards + strip stale categories/items -----

/datum/preference/all_underwear/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value))
		value = list()
		// Seed defaults by gender.
		for(var/datum/category_group/underwear/WRC in GLOB.global_underwear.categories)
			for(var/datum/category_item/underwear/WRI in WRC.items)
				var/id_gender = preferences.read_preference(/datum/preference/choiced/gender/identifying)
				if(WRI.is_default(id_gender ? id_gender : MALE))
					value[WRC.name] = WRI.name
					break
	for(var/category_name in value.Copy()) // iterate copy; -= mid-loop skips entries
		var/datum/category_group/underwear/UWC = GLOB.global_underwear.categories_by_name[category_name]
		if(!UWC || !UWC.items_by_name[value[category_name]])
			value -= category_name
	return value

/datum/preference/all_underwear_metadata/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value))
		return list()
	var/list/all_underwear = preferences.read_preference(/datum/preference/all_underwear) || list()
	for(var/key in value.Copy()) // iterate copy; -= mid-loop skips entries
		if(!(key in all_underwear))
			value -= key
	return value

// ----- Gear slot / list -----

// gear_slot is text now ("_default" or a job title). Default to "_default" if
// the stored value is empty/garbage.
/datum/preference/text/human/gear_slot/sanitize(value, datum/preferences/preferences)
	if(!istext(value) || !length(value))
		return "_default"
	return value

// Walk every per-job loadout in the map and prune unknown / over-budget gear.
// Old shape was {slot_num_str: list_of_gear}; the keys changed to job titles + "_default"
// but the per-list cleanup logic is identical.
/datum/preference/gear_list/sanitize(list/value, datum/preferences/preferences)
	if(!islist(value))
		return list()
	for(var/loadout_key in value)
		var/list/active_gear_list = value[loadout_key]
		if(!islist(active_gear_list))
			value[loadout_key] = list()
			continue
		var/total_cost = 0
		for(var/gear_name in active_gear_list.Copy())
			var/datum/gear/G = GLOB.gear_datums[gear_name]
			if(!G)
				active_gear_list -= gear_name
				continue
			if(total_cost + G.cost > MAX_GEAR_COST)
				active_gear_list -= gear_name
				continue
			total_cost += G.cost
	return value
