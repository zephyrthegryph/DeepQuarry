// The neck gaiter loadout picker offers the gaiter family's variants (code/content/gear/loadout_mask.dm), and a loadout saved when the picker
// was a type list (the name of a subtype) or a key still loads.

/// The index of the picker's variant tweak in `G`'s tweaks (0 when it has none).
/proc/dq_gaiter_tweak_index(datum/gear/G)
	for(var/i in 1 to length(G.gear_tweaks))
		if(istype(LAZYACCESS(G.gear_tweaks, i), /datum/gear_tweak/variant))
			return i
	return 0

/datum/unit_test/dq_gaiter_picker_spawns_variants

/datum/unit_test/dq_gaiter_picker_spawns_variants/Run()
	var/datum/gear/G = GLOB.gear_datums["neck gaiter selection"]
	TEST_ASSERT_NOTNULL(G, "the gaiter picker is in the loadout")
	var/ti = dq_gaiter_tweak_index(G)
	TEST_ASSERT(ti > 0, "the picker has a variant tweak")
	var/datum/gear_tweak/variant/gt = G.gear_tweaks[ti]
	var/turf/T = dq_containment_floor()
	var/obj/item/clothing/accessory/gaiter/base_type = /obj/item/clothing/accessory/gaiter
	var/base_name = initial(base_type.name)
	TEST_ASSERT(base_name in gt.valid_variants, "the plain gaiter is offered")
	TEST_ASSERT_NULL(gt.valid_variants[base_name], "the plain gaiter has no variant key")
	var/list/table = GLOB.dq_variants_accessory_gaiter
	var/spawned = 0
	for(var/key in table)
		var/list/row = table[key]
		var/shown = row["name"] || key
		TEST_ASSERT_EQUAL(gt.valid_variants[shown], key, "[shown] is offered as variant [key]")
		var/obj/item/clothing/accessory/gaiter/made = G.spawn_item(T, list("[ti]" = shown))
		TEST_ASSERT(istype(made, /obj/item/clothing/accessory/gaiter), "[shown] spawns a gaiter")
		TEST_ASSERT_EQUAL(made.name, shown, "[shown] spawns with its row's name")
		qdel(made)
		spawned++
	TEST_ASSERT(spawned > 0, "some variants were spawned")
	var/obj/item/clothing/accessory/gaiter/plain = G.spawn_item(T, list("[ti]" = base_name))
	TEST_ASSERT_EQUAL(plain.name, base_name, "the plain gaiter spawns plain")
	qdel(plain)

/datum/unit_test/dq_gaiter_picker_migrates_old_saves

/datum/unit_test/dq_gaiter_picker_migrates_old_saves/Run()
	var/datum/gear/G = GLOB.gear_datums["neck gaiter selection"]
	var/ti = dq_gaiter_tweak_index(G)
	TEST_ASSERT(ti > 0, "the picker has a variant tweak")
	var/list/row = GLOB.dq_variants_accessory_gaiter["tan"]
	var/tan_name = row["name"]
	var/list/meta = list("[ti]" = "tan")
	gear_tweaks_migrate_meta(G, meta)
	TEST_ASSERT_EQUAL(meta["[ti]"], tan_name, "a saved variant key becomes the name the picker shows")
	meta = list("[ti]" = uppertext(tan_name))
	gear_tweaks_migrate_meta(G, meta)
	TEST_ASSERT_EQUAL(meta["[ti]"], tan_name, "a name in other capitalization becomes the picker's")
	meta = list("[ti]" = "black half-mask")
	gear_tweaks_migrate_meta(G, meta)
	TEST_ASSERT_EQUAL(meta["[ti]"], "black half-mask", "a name the picker shows stays")
	meta = list("[ti]" = "no such gaiter ever")
	gear_tweaks_migrate_meta(G, meta)
	TEST_ASSERT_EQUAL(meta["[ti]"], "no such gaiter ever", "an unknown value is left for the tweak to ignore")
	var/list/again = meta.Copy()
	gear_tweaks_migrate_meta(G, again)
	TEST_ASSERT_EQUAL(json_encode(again), json_encode(meta), "migrating twice changes nothing")

	// Through the load path.
	var/datum/preference/gear_list/pref = GLOB.preference_entries[/datum/preference/gear_list]
	var/list/entry = list()
	entry[G.display_name] = list("[ti]" = "tan")
	var/list/clean = pref.sanitize(list("_default" = entry), null)
	TEST_ASSERT_EQUAL(clean["_default"][G.display_name]["[ti]"], tan_name, "loading a saved loadout migrates the picker's value")
