// Recorded against the legacy fit tables before the requirement retirement.
// Each row is the actual consumer refusal, including ordered and species-specific text.
/datum/unit_test/dq_requirement_burndown_pin

/datum/unit_test/dq_requirement_burndown_pin/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_requirement_burndown_pin/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human, test_floor())
	var/static/list/garment_types = list(
		/obj/item/clothing/gloves/gauntlets/rig,
		/obj/item/clothing/gloves/gauntlets/rig/protean,
		/obj/item/clothing/head/helmet/space,
		/obj/item/clothing/head/helmet/space/rig,
		/obj/item/clothing/head/helmet/space/rig/protean,
		/obj/item/clothing/head/helmet/space/void,
		/obj/item/clothing/head/helmet/space/void/zaddat,
		/obj/item/clothing/head/radiation/teshari,
		/obj/item/clothing/head/tesh_hood,
		/obj/item/clothing/shoes,
		/obj/item/clothing/shoes/magboots/rig,
		/obj/item/clothing/shoes/magboots/rig/protean,
		/obj/item/clothing/suit/captunic/capjacket/altevian_admiral,
		/obj/item/clothing/suit/radiation/teshari,
		/obj/item/clothing/suit/space,
		/obj/item/clothing/suit/space/rig,
		/obj/item/clothing/suit/space/rig/protean,
		/obj/item/clothing/suit/space/void,
		/obj/item/clothing/suit/space/void/zaddat,
		/obj/item/clothing/suit/storage/hooded/teshari,
		/obj/item/clothing/suit/storage/teshari/beltcloak,
		/obj/item/clothing/suit/storage/teshari/cloak,
		/obj/item/clothing/suit/storage/toggle/labcoat/teshari,
		/obj/item/clothing/suit/storage/toggle/tesharicoat,
		/obj/item/clothing/suit/storage/toggle/tesharicoatwhite,
		/obj/item/clothing/under/fluff/slime_skeleton,
		/obj/item/clothing/under/punpun,
		/obj/item/clothing/under/teshari,
		/obj/item/clothing/under/vox,
	)
	var/static/list/species_names = list(SPECIES_HUMAN, SPECIES_TESHARI, SPECIES_VOX, SPECIES_WEREBEAST, SPECIES_SKRELL, SPECIES_ALTEVIAN, SPECIES_MONKEY)
	var/list/actual = list()
	var/allowed = 0
	var/refused = 0
	var/list/garments = list()
	for(var/path in garment_types)
		// Nullspace prevents map-side collection while keeping the real constructor.
		var/obj/item/garment = allocate(path, null)
		TEST_ASSERT_NOTNULL(garment, "Every inventoried garment has a real instance")
		TEST_ASSERT(!QDELETED(garment), "The real garment survives construction")
		garments[path] = garment
		own_constructed_contents(garment)
		actual[path] = list()
	// Rebuild the real wearer only once per species, not once per matrix cell.
	for(var/species in species_names)
		wearer.set_species(species)
		TEST_ASSERT_EQUAL(wearer.get_species(), species, "The actual wearer changed species")
		for(var/path in garment_types)
			var/obj/item/garment = garments[path]
			var/reason = dq_constraint_refusal(garment, CONSTRAINT_FIT, garment, wearer)
			if(isnull(reason))
				allowed++
			else
				refused++
			var/list/rows = actual[path]
			rows += "[species]: [isnull(reason) ? "ALLOW" : reason]"
	for(var/path in garment_types)
		var/obj/item/garment = garments[path]
		var/no_wearer = dq_constraint_refusal(garment, CONSTRAINT_FIT, garment, null)
		var/list/rows = actual[path]
		rows += "no wearer: [isnull(no_wearer) ? "ALLOW" : no_wearer]"
	TEST_ASSERT_EQUAL(length(actual), length(garment_types), "Every inventoried fit table was captured")
	TEST_ASSERT(allowed > 0, "The real matrix contains allowed cases, rather than refusing by default")
	TEST_ASSERT(refused > 0, "The real matrix contains refused cases, rather than allowing by default")
	var/dir = "[DQ_SNAPSHOT_ROOT]requirement_burndown_fit/"
	var/list/bad = list()
	var/report = dq_snapshot_compare(dir, "requirement_burndown_fit", actual, dq_snapshot_read_dir(dir, bad), bad)
	TEST_ASSERT_NULL(report, report)

// Supplement the existing devour/digest order coverage with the remaining consent branches.
/datum/unit_test/dq_requirement_burndown_consent/Run()
	var/list/pair = vore_test_pair()
	var/mob/living/carbon/human/predator = pair[1]
	var/mob/living/carbon/human/prey = pair[2]
	prey.vore_prefs.set_permit_healbelly(FALSE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(VORE_CONSENT_HEAL, predator, prey), "they don't allow healing bellies", "The actual healing preference supplies its exact refusal")
	prey.vore_prefs.set_permit_healbelly(TRUE)
	TEST_ASSERT_NULL(vore_consent_refusal(VORE_CONSENT_HEAL, predator, prey), "A live consenting prey allows healing")
	prey.vore_prefs.set_strip_pref(FALSE)
	TEST_ASSERT_EQUAL(vore_consent_refusal(VORE_CONSENT_STRIP, predator, prey), "they don't allow stripping", "The actual stripping preference supplies its exact refusal")
	TEST_ASSERT(!vore_consents(VORE_CONSENT_STRIP, predator, prey), "The effect's boolean consumer agrees with the refusal")
	prey.vore_prefs.set_strip_pref(TRUE)
	TEST_ASSERT_NULL(vore_consent_refusal(VORE_CONSENT_STRIP, predator, prey), "The actual preference recovers stripping permission")
	TEST_ASSERT(vore_consents(VORE_CONSENT_STRIP, predator, prey), "The effect's boolean consumer agrees with recovery")

// Include every legacy table, including explicit null overrides and holder shorthands.
/datum/unit_test/dq_requirement_burndown_pin/acceptance/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)
	var/mob/living/carbon/human/wearer = allocate(/mob/living/carbon/human, test_floor())
	wearer.set_species(SPECIES_HUMAN)
	var/static/list/declarations = list(
		list(/obj/item/clothing/shoes/none, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/changeling, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/cultrobes, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/space/cult, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/technomancer, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/storage/backpack/saddlebag, CONSTRAINT_EQUIP),
		list(/obj/item/storage/backpack/saddlebag_common, CONSTRAINT_EQUIP),
		list(/obj/item/storage/internal, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/shoes, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/shoes/magboots, CONSTRAINT_FIT),
		list(/obj/item/clothing/head/helmet/space/rig, CONSTRAINT_FIT),
		list(/obj/item/clothing/gloves/gauntlets/rig, CONSTRAINT_FIT),
		list(/obj/item/clothing/shoes/magboots/rig, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/rig, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/rig, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/head/helmet/space, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/head/helmet/space/void, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/void, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/void, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/head/helmet/space/void/zaddat, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/void/zaddat, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/void/zaddat, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/teshari/cloak, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/teshari/cloak/jobs/hos, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/teshari/cloak/jobs/sec, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/labcoat/teshari, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/toggle/tesharicoat, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/toggle/tesharicoatwhite, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/hooded/teshari, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/hooded/teshari, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/head/tesh_hood, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/teshari/beltcloak, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/teshari/beltcloak/jobs/sec, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/teshari/beltcloak/jobs/hos, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/armor, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/armor/swat, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/vest, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/vest/press, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/armor/centcomm, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/armor/pcarrier, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/armor/vest/wolftaur, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/armor/vest/wolftaur, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/armor/combat/crusader_explo, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/bio_suit, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/explorer, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/captain, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/hop, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/security, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/security/hos, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/medical, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/medical/sar, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/science, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/engineering, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/hydro, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/miner, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/explorer, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/raincoat, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/hoodie, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/snowsuit, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/snowsuit/command, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/snowsuit/security, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/snowsuit/medical, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/snowsuit/engineering, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/snowsuit/cargo, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/snowsuit/science, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/apron, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hooded/chaplain_hoodie, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/chef, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/det_trench, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/forensics, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/hazardvest, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/fr_jacket, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/surgicalapron, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/labcoat, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/lasertag, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/lasertag/bluetag, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/lasertag/redtag, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/lasertag/omni, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/judgerobe, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/syndicatefake, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/leathercoat, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/neocoat, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/trench, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/duster, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/bomber, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/leather_jacket, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/brown_jacket, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/denim_jacket, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/varsity, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/runner, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/track, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/flannel, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/snowsuit, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/toggle/moto_jacket, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/talonbomberjacket, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/drake_cloak, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/barding, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/captunic/capjacket/altevian_admiral, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/solgov/service, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/storage/solgov/dress, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/dress/solgov, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/dress/saare, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/fire, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/bomb_suit/security, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/radiation, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/radiation/teshari, CONSTRAINT_FIT),
		list(/obj/item/clothing/head/radiation/teshari, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/storage/toggle/paramedic, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/wizrobe, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/shoes/tribalwear, CONSTRAINT_FIT),
		list(/obj/item/clothing/under/teshari, CONSTRAINT_FIT),
		list(/obj/item/clothing/under/vox, CONSTRAINT_FIT),
		list(/obj/item/clothing/under/punpun, CONSTRAINT_FIT),
		list(/obj/item/clothing/head/helmet/space/rig/protean, CONSTRAINT_FIT),
		list(/obj/item/clothing/gloves/gauntlets/rig/protean, CONSTRAINT_FIT),
		list(/obj/item/clothing/shoes/magboots/rig/protean, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/rig/protean, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/rig/protean, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/gripper, CONSTRAINT_HOLD),
		list(/obj/item/gripper/engineering, CONSTRAINT_HOLD),
		list(/obj/item/gripper/drone, CONSTRAINT_HOLD),
		list(/obj/item/gripper/omni, CONSTRAINT_HOLD),
		list(/obj/item/gripper/miner, CONSTRAINT_HOLD),
		list(/obj/item/gripper/security, CONSTRAINT_HOLD),
		list(/obj/item/gripper/paperwork, CONSTRAINT_HOLD),
		list(/obj/item/gripper/medical, CONSTRAINT_HOLD),
		list(/obj/item/gripper/research, CONSTRAINT_HOLD),
		list(/obj/item/gripper/circuit, CONSTRAINT_HOLD),
		list(/obj/item/gripper/service, CONSTRAINT_HOLD),
		list(/obj/item/gripper/gravekeeper, CONSTRAINT_HOLD),
		list(/obj/item/gripper/scene, CONSTRAINT_HOLD),
		list(/obj/item/gripper/no_use/organ, CONSTRAINT_HOLD),
		list(/obj/item/gripper/no_use/organ/robotics, CONSTRAINT_HOLD),
		list(/obj/item/gripper/no_use/mech, CONSTRAINT_HOLD),
		list(/obj/item/gripper/no_use/loader, CONSTRAINT_HOLD),
		list(/obj/item/gripper/syndicate, CONSTRAINT_HOLD),
		list(/obj/item/clothing/head/helmet/space/void/engineering/hazmat/fluff/screehelm, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/space/void/engineering/hazmat/fluff/screespess, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/head/fluff/avida, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/under/fluff/aluranevines, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/head/helmet/space/fluff/joan, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/space/fluff/joan, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/storage/hooded/wintercoat/jessie, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/space/void/engineering/kate, CONSTRAINT_FIT),
		list(/obj/item/clothing/head/helmet/space/fluff/kate, CONSTRAINT_FIT),
		list(/obj/item/clothing/head/helmet/space/fluff/kate, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/under/dress/fluff/kilano, CONSTRAINT_FIT),
		list(/obj/item/clothing/gloves/fluff/kilano/netra, CONSTRAINT_FIT),
		list(/obj/item/clothing/shoes/boots/fluff/kilano, CONSTRAINT_FIT),
		list(/obj/item/clothing/gloves/fluff/kilano, CONSTRAINT_FIT),
		list(/obj/item/clothing/head/helmet/space/void/security/hasd, CONSTRAINT_FIT),
		list(/obj/item/clothing/head/helmet/space/void/security/hasd, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/space/void/security/hasd, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/void/security/hasd, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/under/fluff/slime_skeleton, CONSTRAINT_FIT),
		list(/obj/item/clothing/under/fluff/slime_skeleton, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/head/helmet/space/void/engineering/zena, CONSTRAINT_FIT),
		list(/obj/item/clothing/suit/space/void/engineering/zena, CONSTRAINT_FIT),
		list(/obj/item/clothing/under/skirt/outfit/fluff/nikki, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/shoes/fluff/nikki, CONSTRAINT_EQUIP),
		list(/obj/item/clothing/suit/storage/hooded/purple_robes, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/suit/armor/vest/wolftaur/serdy, CONSTRAINT_FIT),
		list(/obj/item/melee/fluffstuff/wolfgirlsword, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/clothing/glasses/welding/tiemgogs, CONSTRAINT_EQUIP),
		list(/obj/item/rig/nikki, CONSTRAINT_SUIT_STORAGE),
		list(/obj/item/rig/nikki, CONSTRAINT_EQUIP),
		list(/obj/item/remote_scene_tool/tally_necklace, CONSTRAINT_EQUIP),
		list(/obj/item/oldtwohanded, CONSTRAINT_EQUIP),
	)
	var/static/list/candidate_types = list(/obj/item/pen, /obj/item/tool/wrench, /obj/item/tank/emergency/oxygen, /obj/item/paper, /obj/item/photo, /obj/item/paper_bundle, /obj/item/stack/material/steel)
	var/list/candidates = list()
	for(var/path in candidate_types)
		candidates += allocate(path, null)
	var/list/holders = list()
	var/mob/living/silicon/robot/gripper_owner
	var/list/actual = list()
	var/queries = 0
	for(var/list/declaration as anything in declarations)
		var/path = declaration[1]
		var/channel = declaration[2]
		var/obj/item/holder = holders[path]
		if(!holder)
			// Use the actual production-owned pockets: a free-standing item is not
			// a declaration of internal storage ownership.
			if(path == /obj/item/storage/internal)
				var/obj/item/clothing/suit/storage/jacket = allocate(/obj/item/clothing/suit/storage, wearer.loc)
				var/obj/item/storage/internal/pockets = jacket.pockets
				holder = pockets
				TEST_ASSERT_EQUAL(pockets?.master_item(), jacket, "Actual pocket ownership links its real jacket")
			else if(ispath(path, /obj/item/gripper))
				if(!gripper_owner)
					gripper_owner = allocate(/mob/living/silicon/robot, wearer.loc)
				holder = allocate(path, gripper_owner)
			else
				holder = allocate(path, wearer)
			TEST_ASSERT_NOTNULL(holder, "[path] has a real holder")
			TEST_ASSERT(!QDELETED(holder), "[path] survives its actual valid-owner constructor")
			holders[path] = holder
			own_constructed_contents(holder)
			actual[path] = list()
		var/list/rows = actual[path]
		TEST_ASSERT_NOTNULL(acceptance_plan_for(holder, channel), "[path] [channel] has its real compiled native declaration")
		if(channel == CONSTRAINT_FIT || channel == CONSTRAINT_EQUIP)
			var/reason = dq_constraint_refusal(holder, channel, holder, wearer)
			rows += "[channel] wearer=Human: [isnull(reason) ? "ALLOW" : reason]"
			queries++
		else
			for(var/obj/item/candidate as anything in candidates)
				var/reason = dq_constraint_refusal(holder, channel, candidate, wearer)
				rows += "[channel] candidate=[candidate.type]: [isnull(reason) ? "ALLOW" : reason]"
				queries++
	TEST_ASSERT_EQUAL(length(declarations), 173, "The pin inventory includes every old acceptance table, including null overrides")
	TEST_ASSERT(queries > length(declarations), "Holder tables exercise different real accepted/rejected candidate families")
	var/dir = "[DQ_SNAPSHOT_ROOT]requirement_burndown_acceptance/"
	var/list/bad = list()
	var/report = dq_snapshot_compare(dir, "requirement_burndown_acceptance", actual, dq_snapshot_read_dir(dir, bad), bad)
	TEST_ASSERT_NULL(report, report)

/datum/unit_test/dq_requirement_burndown_pin/proc/own_constructed_contents(atom/holder)
	for(var/atom/movable/child as anything in contents_of(holder))
		own(child)
		own_constructed_contents(child)

// A genuine native plain-item declaration reaches the item override branch.
// Storage has a different restrict_hold() override for its own capability.
/obj/item/dq_native_override_pin

CAPABILITIES(/obj/item/dq_native_override_pin)
	acceptance(CONSTRAINT_HOLD, req_acceptance_type(list(/obj/item/pen), because = "it doesn't take that"), req_acceptance_max_size(ITEMSIZE_SMALL, PROP_UNIT_SIZE_CLASS))

// Give the actual size provider a distinct declared type baseline, independent
// of whether a live field is part of this type's saved-state schema.
/obj/item/pen/dq_larger_override_pin
	w_class = ITEMSIZE_SMALL

// Capture the existing dynamic holder override, including its current refusal text.
/datum/unit_test/dq_requirement_burndown_pin/hold_override/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/dq_native_override_pin/holder = allocate(/obj/item/dq_native_override_pin, null)
	var/obj/item/pen/exact = allocate(/obj/item/pen, null)
	var/obj/item/pen/dq_larger_override_pin/oversize = allocate(/obj/item/pen/dq_larger_override_pin, null)
	var/obj/item/tool/wrench/wrong_type = allocate(/obj/item/tool/wrench, null)
	exact.set_w_class(ITEMSIZE_TINY)
	wrong_type.set_w_class(ITEMSIZE_TINY)
	TEST_ASSERT_EQUAL(dq_property(exact, PROP_SIZE_CLASS), ITEMSIZE_TINY, "Exact candidate has its actual tiny numeric property")
	TEST_ASSERT_EQUAL(dq_property(oversize, PROP_SIZE_CLASS), ITEMSIZE_SMALL, "Above-boundary candidate has its actual larger numeric property")
	TEST_ASSERT_NOTNULL(acceptance_plan_for(holder, CONSTRAINT_HOLD), "A real native holder exercises its native override path")
	holder.restrict_hold(list(/obj/item/pen), ITEMSIZE_TINY)
	var/datum/entry/part/acceptance_plan/overridden = acceptance_plan_for(holder, CONSTRAINT_HOLD)
	TEST_ASSERT_NOTNULL(overridden, "Actual override resolves to a native plan")
	var/size_leaves = 0
	for(var/datum/entry/part/req/R as anything in overridden.children)
		if(istype(R, /datum/entry/part/req/acceptance_leaf/max_size))
			size_leaves++
			TEST_ASSERT_EQUAL(R.args["max_size"], ITEMSIZE_TINY, "Real resolved override carries the requested tiny boundary")
	TEST_ASSERT_EQUAL(size_leaves, 1, "Actual override replaces, rather than duplicates, the size requirement")
	TEST_ASSERT_NULL(dq_constraint_refusal(holder, CONSTRAINT_HOLD, exact, null), "The exact numeric boundary allows the actual pen")
	TEST_ASSERT_NOTNULL(dq_constraint_refusal(holder, CONSTRAINT_HOLD, oversize, null), "The actual above-boundary pen is refused")
	TEST_ASSERT_EQUAL(dq_constraint_refusal(holder, CONSTRAINT_HOLD, wrong_type, null), "it doesn't take that", "The first type requirement still wins")
	var/list/rows = list(
		"exact boundary: [dq_constraint_refusal(holder, CONSTRAINT_HOLD, exact, null) || "ALLOW"]",
		"above boundary: [dq_constraint_refusal(holder, CONSTRAINT_HOLD, oversize, null)]",
		"wrong type: [dq_constraint_refusal(holder, CONSTRAINT_HOLD, wrong_type, null)]",
	)
	holder.restrict_hold(list(/obj/item/pen), ITEMSIZE_SMALL)
	TEST_ASSERT_NULL(dq_constraint_refusal(holder, CONSTRAINT_HOLD, oversize, null), "The actual native override recovers admission at its new boundary")
	rows += "raised boundary: [dq_constraint_refusal(holder, CONSTRAINT_HOLD, oversize, null) || "ALLOW"]"
	var/dir = "[DQ_SNAPSHOT_ROOT]requirement_burndown_override/"
	var/list/bad = list()
	var/report = dq_snapshot_compare(dir, "requirement_burndown_override", list(/obj/item/dq_native_override_pin = rows), dq_snapshot_read_dir(dir, bad), bad)
	TEST_ASSERT_NULL(report, report)

// Drive the actual pilot callback through the native timer, with a real helm
// whose nullspace location is deliberately included in the configured levels.
/datum/unit_test/dq_pilotslug_helm_destination
	parent_type = /datum/unit_test/dq_requirement_burndown_pin

/datum/unit_test/dq_pilotslug_helm_destination/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	test_driver_begin()
	var/turf/start = test_floor()
	var/turf/destination = get_step(start, EAST)
	TEST_ASSERT(istype(destination), "Real neighboring turf exists")
	// Scope the map setting through the normal test override helper; no live
	// gameplay requirement depends on this static map configuration.
	set_var(using_map, nameof(using_map.player_levels), list(0))
	var/obj/machinery/computer/ship/helm/invalid = allocate(/obj/machinery/computer/ship/helm, start)
	invalid.moveToNullspace()
	TEST_ASSERT_NULL(get_turf(invalid), "The actual invalid candidate has no destination turf")
	TEST_ASSERT(invalid.z in using_map.player_levels, "The old z-only predicate would include this actual helm")
	var/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug/P = allocate(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, start)
	P.set_takes_a_helm(TRUE)
	P.set_ghostjoin(FALSE)
	after(P, 0, TYPE_PROC_REF(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, take_a_helm))
	test_phase(KERNEL_PHASE_D)
	TEST_ASSERT_EQUAL(P.loc, start, "No valid destination leaves the real pilot in place")
	TEST_ASSERT(!P.ghostjoin, "Failed relocation does not open the pilot to ghosts")
	var/obj/machinery/computer/ship/helm/valid = allocate(/obj/machinery/computer/ship/helm, destination)
	TEST_ASSERT_EQUAL(get_turf(valid), destination, "The actual eligible helm has a real turf")
	using_map.player_levels += start.z
	var/list/eligible_helms = list()
	for(var/obj/machinery/computer/ship/helm/H in world)
		if(QDELETED(H))
			continue
		var/turf/helm_turf = get_turf(H)
		if(helm_turf && (helm_turf.z in using_map.player_levels))
			eligible_helms += H
	TEST_ASSERT_EQUAL(length(eligible_helms), 1, "The strict fixture has exactly one eligible real helm")
	TEST_ASSERT_EQUAL(eligible_helms[1], valid, "The only eligible real helm is the positive fixture target")
	after(P, 0, TYPE_PROC_REF(/mob/living/simple_mob/vore/alienanimals/catslug/custom/pilotslug, take_a_helm))
	test_phase(KERNEL_PHASE_D)
	TEST_ASSERT_EQUAL(P.loc, destination, "The native timer relocates the pilot to the real valid helm")
	TEST_ASSERT(P.ghostjoin, "Successful actual relocation keeps the original ghost-admission behavior")
	test_driver_end()
