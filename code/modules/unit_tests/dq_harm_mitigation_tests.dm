// Harm and mitigation: weapons declare injury kinds, armour is asked by kind,
// injure() runs one ordered pipeline and can explain it, object damage is
// derived from the kind, and the pharmacology catalogue split keeps its data.

/datum/modifier/dq_test_physical_half
	name = "test physical resistance"
	factors = alist(BF_INCOMING_PHYSICAL = 0.5)

/// Weapons, projectiles, blobs and animal / unarmed attacks declare what they inflict.
/datum/unit_test/dq_harm_kind_declarations
	/// Amount entering injure()'s pipeline, keyed by kind, for the split-hit check.
	var/list/split_shares

/datum/unit_test/dq_harm_kind_declarations/proc/on_split_explained(mob/living/source, incoming_kind, kind, list/stages, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	if(length(stages))
		var/list/first_stage = stages[1]
		split_shares["[incoming_kind]"] = first_stage[2]

/datum/unit_test/dq_harm_kind_declarations/Run()
	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife)
	TEST_ASSERT_EQUAL(knife.injury_kind, INJURY_CUT, "a knife should cut")
	var/obj/item/projectile/bullet/bullet = allocate(/obj/item/projectile/bullet)
	TEST_ASSERT_EQUAL(bullet.injury_kind, INJURY_PIERCE, "a bullet should pierce")
	var/obj/item/projectile/beam/laser = allocate(/obj/item/projectile/beam)
	TEST_ASSERT_EQUAL(laser.injury_kind, INJURY_BURN, "a laser should burn")
	var/obj/item/projectile/beam/stun/stun = allocate(/obj/item/projectile/beam/stun)
	TEST_ASSERT_EQUAL(stun.injury_kind, INJURY_PAIN, "a stun beam should inflict pain")
	var/obj/item/projectile/beam/burstlaser/ion/ion = allocate(/obj/item/projectile/beam/burstlaser/ion)
	TEST_ASSERT(ion.emp_on_hit, "an ion bolt should pulse instead of injuring")
	TEST_ASSERT_EQUAL(ion.injury_kind, INJURY_ELECTRIC, "an ion bolt is electrical")

	// Mixed hits split their damage by share.
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/obj/item/melee/energy/axe/axe = allocate(/obj/item/melee/energy/axe)
	axe.activate(victim)
	TEST_ASSERT_NOTNULL(axe.injury_kinds, "a lit energy axe should sear (burn plus cut)")
	var/share = 0
	for(var/kind in axe.injury_kinds)
		share += axe.injury_kinds[kind]
	TEST_ASSERT(dq_near(share, 1), "mixed-hit shares should sum to 1, got [share]")
	axe.deactivate(victim)
	TEST_ASSERT_NULL(axe.injury_kinds, "an unlit axe is a plain axe")
	TEST_ASSERT_EQUAL(axe.injury_kind, INJURY_CUT, "an unlit axe still cuts")

	// A split hit sends each kind its share into injure(). Read what enters the
	// pipeline, not what lands: how much lands depends on the body's prior state.
	var/mob/living/carbon/human/split_victim = allocate(/mob/living/carbon/human)
	split_shares = list()
	RegisterSignal(split_victim, COMSIG_LIVING_INJURY_EXPLAINED, PROC_REF(on_split_explained))
	split_victim.injure_split(INJURY_BURN, alist(INJURY_BURN = 0.25, INJURY_BLUNT = 0.75), 20, BP_TORSO, flags = INJURE_SILENT)
	UnregisterSignal(split_victim, COMSIG_LIVING_INJURY_EXPLAINED)
	TEST_ASSERT(dq_near(split_shares["[INJURY_BURN]"], 5), "a split hit should send its burn share (5), got [split_shares["[INJURY_BURN]"]]")
	TEST_ASSERT(dq_near(split_shares["[INJURY_BLUNT]"], 15), "a split hit should send its blunt share (15), got [split_shares["[INJURY_BLUNT]"]]")

	var/datum/blob_type/living_agate/agate = new
	TEST_ASSERT_NOTNULL(agate.injury_kinds, "the agate blob should sear")
	qdel(agate)
	var/datum/unarmed_attack/claws/claws = new
	TEST_ASSERT_EQUAL(claws.injury_kind, INJURY_CUT, "claws should cut")
	qdel(claws)
	var/mob/living/simple_mob/animal/hyena/hyena = allocate(/mob/living/simple_mob/animal/hyena)
	TEST_ASSERT_EQUAL(hyena.attack_injury_kind, INJURY_CUT, "a hyena bite should cut")
	TEST_ASSERT_EQUAL(victim.generic_attack_injury_kind(hyena), INJURY_CUT, "animal attacks should use the animal's declared kind")

	// Every projectile declares a real kind.
	for(var/path in typesof(/obj/item/projectile))
		var/obj/item/projectile/P = path
		var/kind = initial(P.injury_kind)
		TEST_ASSERT(isnum(kind) && kind >= 1 && kind <= INJURY_KIND_COUNT, "[path] should declare an INJURY_* kind, has [kind]")


/// Armour is looked up by injury kind at the hit part, from the worn armour
/// lists, and mitigates only hits from outside (INJURE_ARMORED).
/datum/unit_test/dq_harm_armor_by_kind
	var/list/explained

/datum/unit_test/dq_harm_armor_by_kind/proc/on_explained(mob/living/source, incoming_kind, kind, list/stages, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	explained = stages.Copy()

/datum/unit_test/dq_harm_armor_by_kind/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.set_armor(dq_armor(list("melee" = 40, "bullet" = 30, "laser" = 20, "energy" = 10, "bomb" = 5, "bio" = 50, "rad" = 60)))
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "the vest should equip")

	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_TORSO), 40, "blunt reads melee armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_CUT, BP_TORSO), 40, "cut reads melee armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_PIERCE, BP_TORSO), 30, "pierce reads bullet armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BURN, BP_TORSO), 20, "burn reads laser armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_ELECTRIC, BP_TORSO), 10, "electric reads energy armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_PAIN, BP_TORSO), 10, "pain reads energy armour")
	TEST_ASSERT_EQUAL(H.injury_armor(ARMOR_BLAST, BP_TORSO), 5, "blast reads bomb armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_TOXIN, BP_TORSO), 50, "toxin reads bio armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_CORROSIVE, BP_TORSO), 50, "corrosive reads bio armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_RADIATION, BP_TORSO), 60, "radiation reads rad armour")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_FROSTBITE, BP_TORSO), 0, "no armour resists frostbite")
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, BP_HEAD), 0, "a vest doesn't armour the head")
	var/obj/item/organ/external/chest = H.get_organ(BP_TORSO)
	var/obj/item/organ/internal/heart = H.internal_organs_by_name[O_HEART]
	TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, chest), 40, "a limb target reads its own armour")
	if(heart)
		TEST_ASSERT_EQUAL(H.injury_armor(INJURY_BLUNT, heart), 40, "an organ target reads its limb's armour")
	TEST_ASSERT_EQUAL(H.armor_against(INJURY_PIERCE, BP_TORSO, 25), 5, "penetration ignores armour points")

	// Burn armour 20 mitigates exactly 20% of an armoured hit, and only an armoured one.
	// Read the armour stage itself: what the body does with the rest depends on its prior wounds.
	RegisterSignal(H, COMSIG_LIVING_INJURY_EXPLAINED, PROC_REF(on_explained))
	H.injure(INJURY_BURN, 10, BP_TORSO, flags = INJURE_SILENT)
	TEST_ASSERT(!length(explained) || explained[1][1] != INJURY_STAGE_ARMOR, "harm from inside the body shouldn't meet armour")
	H.injure(INJURY_BURN, 10, BP_TORSO, flags = INJURE_SILENT | INJURE_ARMORED)
	var/list/armour_stage = explained[1]
	TEST_ASSERT_EQUAL(armour_stage[1], INJURY_STAGE_ARMOR, "an armoured hit should meet armour first")
	var/kept = armour_stage[3] / armour_stage[2]
	TEST_ASSERT(dq_near(kept, 0.8), "20 burn armour should stop 20% of an armoured burn, kept [kept]")
	H.injure(INJURY_BURN, 10, BP_TORSO, armor_pen = 20, flags = INJURE_SILENT | INJURE_ARMORED)
	armour_stage = explained[1]
	TEST_ASSERT(dq_near(armour_stage[3], armour_stage[2]), "20 penetration should defeat 20 burn armour ([armour_stage[3]] of [armour_stage[2]])")
	UnregisterSignal(H, COMSIG_LIVING_INJURY_EXPLAINED)

	// Simple mobs read their natural armour list the same way.
	var/mob/living/simple_mob/animal/passive/mouse/M = allocate(/mob/living/simple_mob/animal/passive/mouse)
	M.set_armor(dq_armor(list("melee" = 35, "bullet" = 15, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 100, "rad" = 100)))
	TEST_ASSERT_EQUAL(M.injury_armor(INJURY_CUT), 35, "a simple mob's cut armour is its melee armour")
	TEST_ASSERT_EQUAL(M.injury_armor(INJURY_PIERCE), 15, "a simple mob's pierce armour is its bullet armour")
	TEST_ASSERT_EQUAL(M.injury_armor(INJURY_BURN), 0, "a simple mob's burn armour is its laser armour")


/// injure() mitigates in order - armour, shields, factors, species/part - and
/// records every stage for COMSIG_LIVING_INJURY_EXPLAINED.
/datum/unit_test/dq_harm_mitigation_pipeline
	var/list/explained
	var/explained_kind

/datum/unit_test/dq_harm_mitigation_pipeline/proc/on_explained(mob/living/source, incoming_kind, kind, list/stages, zone, atom/injury_source, flags)
	SIGNAL_HANDLER
	explained = stages.Copy()
	explained_kind = kind

/datum/unit_test/dq_harm_mitigation_pipeline/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human)
	var/obj/item/clothing/suit/armor/vest/vest = allocate(/obj/item/clothing/suit/armor/vest)
	vest.set_armor(dq_armor(list("melee" = 40, "bullet" = 0, "laser" = 0, "energy" = 0, "bomb" = 0, "bio" = 0, "rad" = 0)))
	TEST_ASSERT(H.equip_to_slot_if_possible(vest, slot_wear_suit, disable_warning = TRUE), "the vest should equip")
	var/datum/modifier/shield_projection/bruteburn/weak/shield = H.add_modifier(/datum/modifier/shield_projection/bruteburn/weak)
	TEST_ASSERT_NOTNULL(shield, "the shield modifier should apply")
	var/obj/item/cell/cell = allocate(/obj/item/cell/high)
	shield.energy_source = cell
	shield.damage_cost = 1
	H.add_modifier(/datum/modifier/dq_test_physical_half)
	RegisterSignal(H, COMSIG_LIVING_INJURY_EXPLAINED, PROC_REF(on_explained))

	var/applied = H.injure(INJURY_BLUNT, 40, BP_TORSO, flags = INJURE_ARMORED | INJURE_SILENT)
	TEST_ASSERT_NOTNULL(explained, "injure() should explain its mitigation to listeners")
	var/list/order = list()
	for(var/list/stage as anything in explained)
		order += stage[1]
	TEST_ASSERT_EQUAL(jointext(order, ","), jointext(list(INJURY_STAGE_ARMOR, INJURY_STAGE_SHIELD, INJURY_STAGE_FACTORS, INJURY_STAGE_BODY), ","), "mitigation should run armour, shield, factors, body in that order")
	var/list/armour = explained[1]
	TEST_ASSERT(dq_near(armour[2], 40), "the armour stage should see the raw 40")
	var/armour_kept = armour[3] / armour[2]
	TEST_ASSERT(dq_near(armour_kept, 0.6), "40 melee armour should stop 40% of the blow, kept [armour_kept]")
	for(var/i in 2 to length(explained))
		var/list/previous = explained[i - 1]
		var/list/stage = explained[i]
		TEST_ASSERT(dq_near(stage[2], previous[3]), "stage [stage[1]] should take what [previous[1]] let through")
	var/list/shield_stage = explained[2]
	TEST_ASSERT(dq_near(shield_stage[3], shield_stage[2] * 0.5), "a fully charged weak shield halves physical harm")
	var/list/factor_stage = explained[3]
	TEST_ASSERT(dq_near(factor_stage[3], factor_stage[2] * 0.5), "BF_INCOMING_PHYSICAL 0.5 should halve what is left")
	var/list/body_stage = explained[4]
	TEST_ASSERT(dq_near(applied, body_stage[3], 0.01), "the body should receive what the last stage let through ([body_stage[3]] vs [applied])")
	TEST_ASSERT(cell.charge < cell.maxcharge, "the shield should drain its cell for what it absorbs")

	// Resistance-free harm skips stages 2-4; unarmoured harm skips stage 1.
	explained = null
	H.injure(INJURY_BLUNT, 10, BP_TORSO, flags = INJURE_IGNORE_RESISTANCE | INJURE_SILENT)
	TEST_ASSERT_EQUAL(length(explained), 0, "exact harm (no armour, no resistance) should have no mitigation stages")
	explained = null
	H.injure(INJURY_BLUNT, 10, BP_TORSO, flags = INJURE_SILENT)
	TEST_ASSERT_EQUAL(length(explained), 3, "harm from inside the body skips armour")
	UnregisterSignal(H, COMSIG_LIVING_INJURY_EXPLAINED)


/// Object and structure damage is derived from the injury kind in one place.
/datum/unit_test/dq_harm_object_damage_derived

/datum/unit_test/dq_harm_object_damage_derived/Run()
	for(var/kind in list(INJURY_BLUNT, INJURY_CUT, INJURY_PIERCE))
		TEST_ASSERT_EQUAL(injury_kind_obj_damage_type(kind), BRUTE, "[injury_kind_name(kind)] should dent objects (BRUTE)")
	for(var/kind in list(INJURY_BURN, INJURY_CORROSIVE))
		TEST_ASSERT_EQUAL(injury_kind_obj_damage_type(kind), BURN, "[injury_kind_name(kind)] should scorch objects (BURN)")
	for(var/kind in list(INJURY_PAIN, INJURY_TOXIN, INJURY_ELECTRIC, INJURY_RADIATION, INJURY_NEURAL, INJURY_CELLULAR))
		TEST_ASSERT_NULL(injury_kind_obj_damage_type(kind), "[injury_kind_name(kind)] shouldn't damage objects")

	var/obj/item/material/knife/knife = allocate(/obj/item/material/knife)
	TEST_ASSERT_EQUAL(knife.obj_damage_type(), BRUTE, "a knife dents objects")
	var/obj/item/projectile/beam/laser = allocate(/obj/item/projectile/beam)
	TEST_ASSERT_EQUAL(laser.get_structure_damage(), laser.damage, "a laser should hurt structures")
	var/obj/item/projectile/beam/stun/stun = allocate(/obj/item/projectile/beam/stun)
	TEST_ASSERT_EQUAL(stun.get_structure_damage(), 0, "a stun beam shouldn't hurt structures")
	var/obj/item/projectile/beam/burstlaser/ion/ion = allocate(/obj/item/projectile/beam/burstlaser/ion)
	TEST_ASSERT_EQUAL(ion.get_structure_damage(), 0, "an ion bolt shouldn't hurt structures")


/// The pharmacology split keeps the catalogue: abstract family bases are not
/// diagnoses, every concrete condition carries the family header, and staged
/// overdoses keep their Mild / Severe / Critical tables.
/datum/unit_test/dq_pharmacology_catalogue

/datum/unit_test/dq_pharmacology_catalogue/Run()
	var/list/catalogued = dq_catalogued_affliction_types()
	var/list/expected = list(
		/datum/affliction/chem_side_effect = list("Side effect", 10),
		/datum/affliction/chem_interaction = list("Interaction", 7),
		/datum/affliction/overdose = list("Overdose", 37),
	)
	for(var/family in expected)
		TEST_ASSERT(!(family in catalogued), "the abstract [family] shouldn't be catalogued")
		var/list/spec = expected[family]
		var/list/members = subtypesof(family)
		TEST_ASSERT_EQUAL(length(members), spec[2], "[family] should keep its [spec[2]] conditions")
		for(var/T in members)
			TEST_ASSERT(T in catalogued, "[T] should be catalogued")
			var/datum/affliction/A = dq_proto(T)
			TEST_ASSERT_EQUAL(A.category, "Pharmacological", "[T] should be pharmacological")
			TEST_ASSERT_EQUAL(A.subcategory, spec[1], "[T] should be a [spec[1]]")
			TEST_ASSERT_EQUAL(A.progression_rate, 0, "[T] should only follow its chem")
			TEST_ASSERT(length(A.caused_by_chems), "[T] should declare the chems that cause it")

	for(var/T in subtypesof(/datum/affliction/overdose))
		var/datum/affliction/overdose/OD = dq_proto(T)
		TEST_ASSERT(OD.chem_scaling, "[T] should scale with the excess dose")
		var/list/stages = OD.get_stages()
		TEST_ASSERT_EQUAL(jointext(stages, ","), "Mild,Severe,Critical", "[T] should stage Mild, Severe, Critical")
		for(var/stage_name in stages)
			var/list/entry = stages[stage_name]
			TEST_ASSERT(length(entry["symptom_pool"]), "[T] [stage_name] should have symptoms")
			TEST_ASSERT(entry["min_symptoms"] <= entry["max_symptoms"], "[T] [stage_name] should show a sane symptom count")

	var/list/built = chem_stage(list(/datum/affliction_symptom/nausea = 10), 1, 2, list("organ_damage_per_tick" = 0.5))
	TEST_ASSERT_EQUAL(built["min_symptoms"], 1, "chem_stage should keep the symptom range")
	TEST_ASSERT_EQUAL(built["organ_damage_per_tick"], 0.5, "chem_stage should merge extra stage keys")
