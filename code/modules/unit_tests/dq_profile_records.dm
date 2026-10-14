// Profile records (doc/rewrite/proposals/base_vars.md, "profile records"): a human's look is pinned across the move of its
// appearance vars into /datum/record/appearance. The fingerprints below were recorded on the tree before the move
// (r_/g_/b_ triples on the human); the move must not change one pixel.

/// The flat south icon of H, hashed.
/datum/unit_test/proc/dq_profile_look_hash(mob/living/carbon/human/H)
	H.force_update_limbs()
	refresh_flush()
	return md5(icon2base64(getFlatIcon(H, SOUTH)))

/// The first style of `styles` the species of H may wear (deterministic: list order).
/datum/unit_test/proc/dq_profile_style(mob/living/carbon/human/H, list/styles, skip)
	for(var/name in styles)
		if(name == skip)
			continue
		var/datum/sprite_accessory/S = styles[name]
		if(S?.species_allowed && (H.species.get_bodytype(H) in S.species_allowed))
			return name
	return null

/// Dresses H in a fixed, non-default appearance: every colour channel, both styles, a gradient, skin tone, lips.
/datum/unit_test/proc/dq_profile_dress(mob/living/carbon/human/H, tone)
	H.looks.set_hair_style(dq_profile_style(H, GLOB.hair_styles_list, "Bald"))
	H.looks.set_facial_style(dq_profile_style(H, GLOB.facial_hair_styles_list, "Shaved"))
	H.looks.set_grad_style(GLOB.hair_gradients[min(2, length(GLOB.hair_gradients))])
	H.looks.set_hair_color(rgb(200, 40, 90))
	H.looks.set_grad_color(rgb(10, 220, 30))
	H.looks.set_facial_color(rgb(120, 130, 5))
	H.looks.set_eyes_color(rgb(0, 255, 128))
	H.looks.set_skin_color(rgb(90, 160, 70))
	H.looks.set_skin_tone(tone)
	H.looks.set_lip_style("red")

/datum/unit_test/dq_profile_human_look_pin

/datum/unit_test/dq_profile_human_look_pin/Run()
	var/turf/T = test_floor()
	var/list/expected = list(
		"human" = "cee3e25b268799fb815295de91e9dd7d",
		"tajaran_digi" = "d7c426a45102ff69601ca76a265a58d4",
		"unathi" = "c6ce446036a9abf9dfaceb7efcf54192",
		"dna_copy" = "cee3e25b268799fb815295de91e9dd7d",
		"colour_copy" = "cee3e25b268799fb815295de91e9dd7d",
	)
	var/list/got = list()

	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human, T)
	human.set_species(SPECIES_HUMAN)
	dq_profile_dress(human, -40)
	got["human"] = dq_profile_look_hash(human)

	var/mob/living/carbon/human/taj = allocate(/mob/living/carbon/human, T)
	taj.set_species(SPECIES_TAJARAN)
	dq_profile_dress(taj, 0)
	taj.looks.set_digitigrade(1)
	got["tajaran_digi"] = dq_profile_look_hash(taj)

	var/mob/living/carbon/human/unathi = allocate(/mob/living/carbon/human, T)
	unathi.set_species(SPECIES_UNATHI)
	dq_profile_dress(unathi, 0)
	got["unathi"] = dq_profile_look_hash(unathi)

	// DNA carries the look: a body built from the human's UI looks the same.
	human.dna.ResetUIFrom(human)
	var/mob/living/carbon/human/clone = allocate(/mob/living/carbon/human, T)
	clone.set_species(SPECIES_HUMAN)
	clone.looks.set_lip_style("red")
	clone.dna = human.dna.Clone()
	clone.UpdateAppearance()
	got["dna_copy"] = dq_profile_look_hash(clone)

	var/mob/living/carbon/human/copy = allocate(/mob/living/carbon/human, T)
	copy.set_species(SPECIES_HUMAN)
	copy.looks.set_lip_style("red")
	record_copy(copy.looks, human.looks)
	got["colour_copy"] = dq_profile_look_hash(copy)

	var/list/moved = list()
	for(var/name in expected)
		log_test("profile look pin [name] [got[name]]")
		if(got[name] != expected[name])
			moved += name
	TEST_ASSERT(!length(moved), "these looks differ from the ones recorded before the profile move: [jointext(moved, ", ")]")
	// the hash is of a real picture: two different looks hash differently
	TEST_ASSERT(got["human"] != got["unathi"], "a human and an unathi look different")

/// A human is made with its looks record: owned, edited through VV by its setters, shown in place, copied whole, gone with it.
/datum/unit_test/dq_profile_record_basics

/datum/unit_test/dq_profile_record_basics/Run()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/datum/record/appearance/looks = H.looks
	TEST_ASSERT(istype(looks), "a human is made with its looks record")
	TEST_ASSERT_EQUAL(owner_of(looks), H, "the human owns it")
	TEST_ASSERT_EQUAL(lowertext(looks.skin_color), "#eeceb3", "a human starts with the skin colour the old vars gave it")

	looks.vv_edit_var("hair_color", "#123456")
	TEST_ASSERT_EQUAL(looks.hair_color, "#123456", "an admin edit of a field goes through its setter")
	TEST_ASSERT(findtext(debug_variable("looks", looks, 0, H), "hair_color"), "VV shows the record's fields under the mob")

	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, T)
	record_copy(other.looks, looks)
	TEST_ASSERT(record_equal(other.looks, looks), "a copy holds every field: [jointext(record_diff(other.looks, looks), ", ")]")
	TEST_ASSERT(other.looks != looks, "and is its own record")

	qdel(H)
	TEST_ASSERT(QDELETED(looks), "the record goes with its holder")

#define DQ_PROFILE_SAVES "code/modules/unit_tests/data/profile_saves/"

/// A real character save (a headless test account's preferences.json) applied to a human lands in its profile records, and
/// written back from the records it saves the same values: the save format did not change (colours were already "#rrggbb"
/// strings on disk, so the profile move needs no savefile migration).
/datum/unit_test/dq_profile_pref_save_roundtrip

/datum/unit_test/dq_profile_pref_save_roundtrip/Run()
	var/path = "data/dq_profile_saves/[world.realtime]_[rand(1, 99999)]/preferences.json"
	TEST_ASSERT(fcopy(DQ_PROFILE_SAVES + "headless_preferences.json", path), "the fixture save is copied to a scratch path")
	var/datum/preferences/dq_test_stub/P = allocate(/datum/preferences/dq_test_stub)
	P.load_and_save = TRUE
	P.path = path
	P.load_savefile()
	TEST_ASSERT(P.load_character(1), "the real save loads")
	var/list/saved = P.savefile.get_entry("character1")
	TEST_ASSERT(islist(saved), "it has a first character")

	// savefile key -> list(record var, field)
	var/list/map = list(
		"hair_color" = list("looks", "hair_color"), "grad_color" = list("looks", "grad_color"), "facial_color" = list("looks", "facial_color"),
		"eyes_color" = list("looks", "eyes_color"), "skin_color" = list("looks", "skin_color"), "synth_color_rgb" = list("looks", "synth_color_rgb"),
		"skin_tone" = list("looks", "skin_tone"), "hair_style_name" = list("looks", "hair_style"), "facial_style_name" = list("looks", "facial_style"),
		"grad_style_name" = list("looks", "grad_style"), "digitigrade" = list("looks", "digitigrade"), "synth_color" = list("looks", "synth_color"),
		"synth_markings" = list("looks", "synth_markings"),
		"age" = list("bio", "age"), "home_system" = list("bio", "home_system"), "birthplace" = list("bio", "birthplace"),
		"citizenship" = list("bio", "citizenship"), "religion" = list("bio", "religion"), "med_record" = list("bio", "med_record"),
		"sec_record" = list("bio", "sec_record"), "gen_record" = list("bio", "gen_record"), "custom_say" = list("bio", "custom_say"),
		"custom_whisper" = list("bio", "custom_whisper"), "custom_ask" = list("bio", "custom_ask"), "custom_exclaim" = list("bio", "custom_exclaim"),
		"nickname" = list("bio", "nickname"),
	)
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/list/applied = list()
	for(var/pref_type in GLOB.preference_entries)
		var/datum/preference/pref = GLOB.preference_entries[pref_type]
		if(pref.savefile_identifier != PREFERENCE_CHARACTER || !(pref.savefile_key in map))
			continue
		pref.apply(H, P.read_preference(pref_type), P)
		applied[pref.savefile_key] = pref_type
	TEST_ASSERT_EQUAL(length(applied), length(map), "every mapped key has its preference: [jointext(map - applied, ", ")]")

	var/list/wrong = list()
	for(var/key in map)
		var/list/where = map[key]
		var/datum/record/R = H.vars[where[1]]
		var/expected = P.read_preference(applied[key])
		var/got = R.vars[where[2]]
		if(istext(expected) && istext(got) ? lowertext(expected) != lowertext(got) : expected != got)
			wrong += "[key]: [expected] != [got]"
	TEST_ASSERT(!length(wrong), "the save's values land in the records: [jointext(wrong, "; ")]")

	// Written back from the records (the persistence path), saved and read again: the same values on disk.
	apply_coloration_to_prefs(H, P)
	P.save_character()
	P.savefile.save()
	var/datum/json_savefile/again = new(path)
	var/list/reloaded = again.get_entry("character1")
	var/list/moved = list()
	for(var/key in list("hair_color", "facial_color", "eyes_color", "skin_color", "skin_tone", "hair_style_name", "facial_style_name"))
		if("[saved[key]]" != "[reloaded[key]]")
			moved += "[key]: [saved[key]] -> [reloaded[key]]"
	TEST_ASSERT(!length(moved), "a save written from the records holds the values it was loaded from: [jointext(moved, "; ")]")
	fdel(path)

/// A real vore save (a headless test account's vore/character1.json) read into the save format, imported into a mob's record and
/// exported again gives back every field it had.
/datum/unit_test/dq_profile_vore_prefs_roundtrip

/datum/unit_test/dq_profile_vore_prefs_roundtrip/Run()
	var/list/json = json_decode(file2text(DQ_PROFILE_SAVES + "headless_vore_character1.json"))
	TEST_ASSERT(length(json) > 50, "the real vore save decodes")
	var/datum/vore_preferences/loaded = allocate(/datum/vore_preferences)
	for(var/key in json)
		if(key in loaded.vars)
			loaded.vars[key] = json[key]
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	record_import(H.vore_prefs, loaded)
	TEST_ASSERT_EQUAL(H.vore_prefs.vore_taste, json["vore_taste"], "the mob tastes as saved")
	TEST_ASSERT_EQUAL(H.vore_prefs.digestable, json["digestable"], "and is as digestable as saved")

	var/datum/vore_preferences/saved = allocate(/datum/vore_preferences)
	record_export(H.vore_prefs, saved)
	var/list/moved = list()
	var/compared = 0
	for(var/field in record_fields(H.vore_prefs))
		if(!(field in json))
			continue
		compared++
		if(json_encode(saved.vars[field]) != json_encode(json[field]))
			moved += field
	TEST_ASSERT(compared > 50, "most of the record is in the save ([compared] fields)")
	TEST_ASSERT(!length(moved), "a save made from the record holds what was loaded: [jointext(moved, ", ")]")

	// tf_form and shapeshift copy the whole record
	var/mob/living/carbon/human/other = allocate(/mob/living/carbon/human, test_floor())
	record_copy(other.vore_prefs, H.vore_prefs)
	TEST_ASSERT(record_equal(other.vore_prefs, H.vore_prefs), "a copy holds every vore field: [jointext(record_diff(other.vore_prefs, H.vore_prefs), ", ")]")
	TEST_ASSERT(other.vore_prefs.nutrition_messages != H.vore_prefs.nutrition_messages, "and its message lists are its own")

/// Every mob has an identity and vore record, not only humans: a robot's flavour text and a simple mob's say verb live there.
/datum/unit_test/dq_profile_records_on_every_mob

/datum/unit_test/dq_profile_records_on_every_mob/Run()
	var/mob/living/simple_mob/animal/passive/mouse/mouse = allocate(/mob/living/simple_mob/animal/passive/mouse, test_floor())
	TEST_ASSERT(istype(mouse.bio, /datum/record/identity), "a simple mob has an identity record")
	TEST_ASSERT(istype(mouse.vore_prefs, /datum/record/vore_prefs), "and a vore record")
	TEST_ASSERT(!("looks" in mouse.vars), "but no human looks")

#undef DQ_PROFILE_SAVES
