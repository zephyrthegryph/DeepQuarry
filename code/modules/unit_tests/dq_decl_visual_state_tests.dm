// Real constructor/state transitions, shared by the before/after lifecycle capture.
/datum/unit_test/dq_decl_visual
	abstract_type = /datum/unit_test/dq_decl_visual
/datum/unit_test/dq_decl_visual/New()
	..()
	dview(0, test_floor())
	status_policies()
/datum/unit_test/dq_decl_visual/proc/scope_fixture()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.act_taken), GLOB.act_taken)
/datum/unit_test/dq_decl_visual/proc/layer_of(atom/A, state)
	for(var/layer in A.overlays)
		var/mutable_appearance/L = new(layer)
		if(L.icon_state == state)
			return L
	return null

/datum/unit_test/dq_decl_visual/mirror
/datum/unit_test/dq_decl_visual/mirror/Run()
	scope_fixture()
	var/obj/structure/mirror/M = allocate(/obj/structure/mirror, test_floor(), NORTH, TRUE)
	var/obj/structure/mirror/mapped = allocate(/obj/structure/mirror, test_floor())
	TEST_ASSERT(!M.glass, "a constructed mirror is an empty frame")
	TEST_ASSERT_EQUAL(M.icon_state, "mirror_frame", "the empty frame has its constructor state")
	TEST_ASSERT(mapped.glass, "a mapped mirror keeps its glass")
	TEST_ASSERT_EQUAL(mapped.icon_state, "mirror", "the ordinary mirror keeps its default state")

/datum/unit_test/dq_decl_visual/offear
/datum/unit_test/dq_decl_visual/offear/Run()
	scope_fixture()
	var/obj/item/tool/crowbar/source = allocate(/obj/item/tool/crowbar, test_floor())
	set_var(source, nameof(source.name), "snapshot source")
	source.set_dir(EAST)
	var/obj/item/clothing/ears/offear/E = allocate(/obj/item/clothing/ears/offear, source)
	TEST_ASSERT_EQUAL(E.name, source.name, "offear copies its containing item's name")
	TEST_ASSERT_EQUAL(E.desc, source.desc, "offear copies its containing item's description")
	TEST_ASSERT_EQUAL(E.icon, source.icon, "offear copies the actual icon resource")
	TEST_ASSERT_EQUAL(E.icon_state, source.icon_state, "offear copies the actual sprite state")
	TEST_ASSERT_EQUAL(E.dir, EAST, "offear copies orientation")
	set_var(source, nameof(source.name), "later edit")
	TEST_ASSERT_EQUAL(E.name, "snapshot source", "constructor appearance is a snapshot, not a live dependency")

/datum/unit_test/dq_decl_visual/reflector
/datum/unit_test/dq_decl_visual/reflector/Run()
	scope_fixture()
	var/obj/structure/reflector/R = allocate(/obj/structure/reflector/single, test_floor())
	R.setAngle(37)
	draw_now(R)
	var/mutable_appearance/L = layer_of(R, R.deflector_icon_state)
	TEST_ASSERT(L, "the real reflector has a deflector layer")
	var/matrix/expected = turn(matrix(), 37)
	TEST_ASSERT_EQUAL(L.transform.a, expected.a, "the layer rotates to the requested angle")
	TEST_ASSERT_EQUAL(L.transform.e, expected.e, "the real layer matrix matches its angle")
	R.set_can_rotate(FALSE)
	R.setAngle(91)
	draw_now(R)
	L = layer_of(R, R.deflector_icon_state)
	TEST_ASSERT_EQUAL(R.rotation_angle, 37, "locking rejects further angle changes")
	TEST_ASSERT_EQUAL(L.transform.a, expected.a, "locking preserves the last visible orientation")

/datum/unit_test/dq_decl_visual/privacy
/datum/unit_test/dq_decl_visual/privacy/Run()
	scope_fixture()
	var/area/A = get_area(test_floor())
	set_var(A, nameof(A.flags), A.flags | AREA_BLOCK_GHOST_SIGHT)
	var/obj/structure/privacyswitch/S = allocate(/obj/structure/privacyswitch, test_floor())
	draw_now(S)
	TEST_ASSERT_EQUAL(S.icon_state, "privacy1", "a switch reflects an initially protected area")

/datum/unit_test/dq_decl_visual/pda
/datum/unit_test/dq_decl_visual/pda/Run()
	scope_fixture()
	var/obj/item/pda/P = allocate(/obj/item/pda, test_floor())
	draw_now(P)
	TEST_ASSERT(layer_of(P, "pda-pen"), "the real starting pen has its visible layer")
	var/datum/data/pda/app/program = P.find_program(/datum/data/pda/app/main_menu)
	TEST_ASSERT(program, "the real PDA creates its main menu program")
	program.notify(null)
	draw_now(P)
	TEST_ASSERT(layer_of(P, "pda-r"), "a notifying real program adds its alert layer")
	program.unnotify()
	draw_now(P)
	TEST_ASSERT(!layer_of(P, "pda-r"), "clearing the last notification removes its alert layer")

/datum/unit_test/dq_decl_visual/micro
/datum/unit_test/dq_decl_visual/micro/Run()
	scope_fixture()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor(), SPECIES_TESHARI)
	TEST_ASSERT(H.species.is_micro_carry(H), "the fixture uses a real micro-carry species")
	var/obj/item/holder/micro/M = allocate(/obj/item/holder/micro, test_floor(), H)
	TEST_ASSERT_EQUAL(M.held_mob, H, "the actual holder binds its constructor occupant")
	TEST_ASSERT_EQUAL(M.icon_state, "teshariplushie_white", "the held species chooses its actual holder sprite")
	TEST_ASSERT_EQUAL(M.item_state, "teshariplushie_white", "the species also selects its held sprite")
	TEST_ASSERT_NULL(M.icon_override, "the special sprite clears the incompatible icon override")

/obj/machinery/artifact/dq_decl_visual_crystal
	predefined_icon_num = 7
/datum/unit_test/dq_decl_visual/artifact
/datum/unit_test/dq_decl_visual/artifact/Run()
	scope_fixture()
	var/obj/machinery/artifact/A = allocate(/obj/machinery/artifact/dq_decl_visual_crystal, test_floor())
	TEST_ASSERT(A.artifact_master, "the real artifact constructor creates its effects owner")
	draw_now(A)
	TEST_ASSERT_EQUAL(A.icon_num, 7, "the constructor preserves a predefined artifact number")
	TEST_ASSERT_EQUAL(A.icon_state, "ano7[A.appearance_active()]", "the existing native draw owns the artifact activation sprite")

// Native privacy dependency regression, deliberately excluded from the old-code capture.
// PDA physical-contents invalidation remains unsupported without a native read contract.
/datum/unit_test/dq_decl_visual/live_redraws
/datum/unit_test/dq_decl_visual/live_redraws/Run()
	scope_fixture()
	var/area/A = get_area(test_floor())
	set_var(A, nameof(A.flags), A.flags & ~AREA_BLOCK_GHOST_SIGHT)
	var/obj/structure/privacyswitch/S = allocate(/obj/structure/privacyswitch, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "privacy0", "an unprotected area starts red")
	set_var(A, nameof(A.flags), A.flags | AREA_BLOCK_GHOST_SIGHT)
	refresh_flush()
	TEST_ASSERT_EQUAL(S.icon_state, "privacy1", "an admin flag edit updates the existing switch through its tracked area")

/datum/unit_test/dq_decl_visual/fixed_states
/datum/unit_test/dq_decl_visual/fixed_states/Run()
	scope_fixture()
	var/turf/T = get_step(test_floor(), EAST)
	TEST_ASSERT(T, "the fixture has a neighboring turf")
	var/old_type = T.type
	defer_cleanup(T, TYPE_PROC_REF(/turf, ChangeTurf), old_type)
	T = T.ChangeTurf(/turf/space)
	var/obj/structure/lattice/L = allocate(/obj/structure/lattice, T)
	TEST_ASSERT(!QDELETED(L), "a real lattice survives over open space")
	TEST_ASSERT_EQUAL(L.icon_state, "latticeblank", "the real lattice has its runtime base state")
	TEST_ASSERT_EQUAL(L.icon, 'icons/obj/smoothlattice.dmi', "the runtime state uses the smooth lattice resource")
	qdel(L)
	var/turf/simulated/shuttle/wall/W = T.ChangeTurf(/turf/simulated/shuttle/wall/dark/no_join)
	TEST_ASSERT_EQUAL(W.icon_state, W.base_state, "a no-join shuttle wall uses its instance base state instead of the map preview")
	W.ChangeTurf(old_type)
	var/obj/structure/prop/machine/nt_pod/P = allocate(/obj/structure/prop/machine/nt_pod, test_floor())
	for(var/atom/movable/visual in P.vis_contents)
		if(!owner_of(visual))
			own(visual)
	TEST_ASSERT_EQUAL(P.icon_state, "nt_pod", "the real prop constructor leaves the runtime pod state")
	TEST_ASSERT(length(P.vis_contents), "the real pod constructor still creates its presentation components")
