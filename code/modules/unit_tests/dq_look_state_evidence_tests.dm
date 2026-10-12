#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)
// Uses the snapshot producer's exact construction path
// seed, actual snapshot allocator, reset, deadline settlement and layer capture.
/datum/unit_test/dq_look_frostbelle_harvest_state/Run()
	dq_look_scope_globals()
	var/type = /obj/structure/flora/sif/frostbelle
	var/turf/T = test_floor()
	dq_look_reset(T)
	rand_seed(dq_test_seed_for("[type]"))
	rolls_fix_seed(dq_test_seed_for("[type]"))
	var/obj/structure/flora/sif/frostbelle/F = dq_snapshot_allocate(type, T)
	TEST_ASSERT(!QDELETED(F), "The real producer frostbelle survives creation")
	dq_look_settle()
	TEST_ASSERT(F.max_harvests >= 0 && F.max_harvests <= 2, "The real rolled harvest capacity stays in its declared0–2 range")
	TEST_ASSERT_EQUAL(F.harvest_count, 0, "The freshly allocated producer shrub has not been harvested")
	var/expected_suffix = F.max_harvests > 0 ? F.variantnum : ""
	TEST_ASSERT_EQUAL(F.appearance_variant(), expected_suffix, "Zero harvest capacity removes the numbered look; positive capacity preserves the actual rolled variant")
	TEST_ASSERT_EQUAL(F.icon_state, "frostbelle[expected_suffix]", "The settled actual producer sprite matches its real harvest capacity")
	log_test("LOOK STATE EVIDENCE frostbelle max_harvests=[F.max_harvests] harvest_count=[F.harvest_count] variantnum=[F.variantnum] state=[F.icon_state]")
	qdel(F)
	dq_look_reset(T)

/datum/unit_test/dq_look_teppi_setup_state/Run()
	dq_look_scope_globals()
	var/turf/T = test_floor()
	var/static/list/eyes = list("#4848a7", "#f346ff", "#b20005", "#ff9a06", "#0cb600", "#32ffff", "#272523", "#ffffff")
	var/static/list/horns = list("#454238", "#a3d5d7", "#763851", "#0d0c2f", "#ffc965")
	for(var/type in list(/mob/living/simple_mob/vore/alienanimals/teppi, /mob/living/simple_mob/vore/alienanimals/teppi/mutant, /mob/living/simple_mob/vore/alienanimals/teppi/baby))
		dq_look_reset(T)
		rand_seed(dq_test_seed_for("[type]"))
		rolls_fix_seed(dq_test_seed_for("[type]"))
		var/mob/living/simple_mob/vore/alienanimals/teppi/P = dq_snapshot_allocate(type, T)
		TEST_ASSERT(!QDELETED(P), "Real producer Teppi survives creation[type]")
		dq_look_settle()
		TEST_ASSERT_NOTNULL(P.eye_color, "Setup must populate actual eye_color[type]; uncolored captured overlay cannot conceal a missing field")
		TEST_ASSERT(P.eye_color in eyes, "Setup eyes use one of the exact declared weighted palette choices[type]")
		TEST_ASSERT_NOTNULL(P.horn_color, "Setup must populate actual horn_color[type]")
		TEST_ASSERT(P.horn_color in horns, "Setup horns use the declared palette[type]")
		var/eyes_seen = 0
		var/observed_eye_color
		// Normalize the actual recorded field through the same appearance helper:
		// BYOND can represent explicit white as a default/null appearance color.
		var/image/expected_eye = look_overlay_image(P.icon, "eye_base", color = P.eye_color, appearance_flags = (RESET_COLOR|KEEP_APART|PIXEL_SCALE))
		var/mutable_appearance/expected = new(expected_eye)
		for(var/layer in P.overlays)
			var/mutable_appearance/actual = new(layer)
			if(actual.icon_state != "eye_base")
				continue
			eyes_seen++
			observed_eye_color = actual.color
			TEST_ASSERT_EQUAL(actual.color, expected.color, "Settled eyes reflect actual setup state after appearance normalization[type]")
		TEST_ASSERT_EQUAL(eyes_seen, 1, "The actual settled look contains exactly one eye layer[type]")
		log_test("LOOK STATE EVIDENCE [type] eye_color=[P.eye_color] eye_layer_color=[observed_eye_color] horn_color=[P.horn_color] marking_type=[P.marking_type] inherit_colors=[P.inherit_colors]")
		qdel(P)
		dq_look_reset(T)

/datum/unit_test/dq_look_base_fields_not_probed/Run()
	dq_look_scope_globals()
	var/turf/T = test_floor()
	var/list/base_vars = dq_look_state_base_vars(/mob, T)
	TEST_ASSERT("vg_entity" in base_vars, "Native identity is declared on the real mob base; it is not a content appearance input")
	for(var/type in list(/mob/living/silicon/robot/drone/jan, /mob/living/silicon/robot/drone/min))
		dq_look_reset(T)
		var/atom/subject = dq_snapshot_allocate(type, T)
		var/list/names = dq_look_probe_names(subject, base_vars, "*", list())
		var/list/illegal = list()
		for(var/name in names)
			if(name in base_vars)
				illegal += name
		// Destroy before asserting: these are real native-bound drones, and an
		// assertion must not leave their entity or children alive.
		qdel(subject)
		dq_look_reset(T)
		TEST_ASSERT_EQUAL(length(illegal), 0, "Unknown plans exclude every actual base field[type]: [jointext(illegal, ", ")]")
		TEST_ASSERT(!("vg_entity" in names), "Unknown-plan exploration never writes a Rust identity handle[type]")
#endif
