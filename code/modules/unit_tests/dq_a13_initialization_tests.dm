// Real constructors exercise completed declared equipment and presentation setup.
/datum/unit_test/dq_a13_initialization
	abstract_type = /datum/unit_test/dq_a13_initialization

/datum/unit_test/dq_a13_initialization/New()
	. = ..()
	dview(0, test_floor())

/datum/unit_test/dq_a13_initialization/proc/scope_setup()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)

/obj/item/stock_parts/capacitor/dq_a13_rated
	rating = 3

/datum/unit_test/dq_a13_initialization/capacitor_rating/Run()
	scope_setup()
	var/obj/item/stock_parts/capacitor/C = allocate(/obj/item/stock_parts/capacitor/dq_a13_rated, test_floor())
	TEST_ASSERT_EQUAL(C.max_charge, 3000, "The actual rated part returns with its capacity scaled exactly once")
	TEST_ASSERT_EQUAL(C.charge, 0, "Scaling capacity alone does not supply charge")

/obj/compass_holder/dq_a13_heading
	show_heading = TRUE

/datum/unit_test/dq_a13_initialization/compass_markers/Run()
	scope_setup()
	var/obj/compass_holder/C = allocate(/obj/compass_holder/dq_a13_heading, test_floor())
	TEST_ASSERT_NOTNULL(C.compass_heading_marker, "A real heading-enabled compass builds its marker")
	TEST_ASSERT_EQUAL(length(C.compass_static_labels), 24, "The real compass renders every fifteen-degree bearing label")
	TEST_ASSERT_EQUAL(C.compass_heading_marker.plane, PLANE_PLAYER_HUD, "The heading marker is on the actual HUD plane")

/datum/unit_test/dq_a13_initialization/mapper_cache/Run()
	scope_setup()
	var/obj/item/mapping_unit/M = allocate(/obj/item/mapping_unit, test_floor())
	var/atom/movable/screen/mapper/marker/B = M.icon_image_cache["bad"]
	TEST_ASSERT_NOTNULL(B, "The actual mapper provides its fallback marker immediately")
	TEST_ASSERT_EQUAL(B.icon_state, "mapper_none", "The marker keeps the original fallback state")
	TEST_ASSERT_NOTNULL(M.map_image_cache["bad"], "The real mapper has a correctly owned fallback map screen")
	TEST_ASSERT_EQUAL(M.base_prefix, M.marker_prefix, "The durable marker preset is captured before callers receive the mapper")

/datum/unit_test/dq_a13_initialization/instrument_ids/Run()
	scope_setup()
	var/obj/structure/musician/P = allocate(/obj/structure/musician, test_floor())
	TEST_ASSERT_NOTNULL(P.song, "The declared song is built before the constructor releases its source list")
	TEST_ASSERT(isnull(P.allowed_instrument_ids), "The constructor releases its no-longer-needed source list")
	TEST_ASSERT(length(P.song.allowed_instrument_ids) > 0, "The real song retains the configured instruments")

/obj/vehicle/train/engine/quadbike/dq_a13_running
	on = TRUE

/datum/unit_test/dq_a13_initialization/vehicle_shutdown/Run()
	scope_setup()
	var/obj/vehicle/train/engine/quadbike/V = allocate(/obj/vehicle/train/engine/quadbike/dq_a13_running, test_floor())
	TEST_ASSERT(!V.on, "The actual engine and child setup stop a vehicle configured to start running")
	TEST_ASSERT_NOTNULL(V.cell, "Its declared power cell is ready before shutdown setup runs")

/datum/unit_test/dq_a13_initialization/shield_damage/Run()
	scope_setup()
	var/obj/machinery/shield/S = allocate(/obj/machinery/shield/malfai, test_floor())
	TEST_ASSERT_EQUAL(S.get_integrity(), S.max_integrity/2, "A real emergency forcefield applies its configured initial damage after parent setup")

/datum/unit_test/dq_a13_initialization/recycler_display/Run()
	scope_setup()
	var/obj/machinery/maint_recycler/R = allocate(/obj/machinery/maint_recycler, test_floor())
	TEST_ASSERT_NOTNULL(R.hatch, "The real recycler owns its animated hatch before display setup")
	TEST_ASSERT_EQUAL(R.hatch.icon_state, "door closed", "The actual hatch starts closed")
	TEST_ASSERT(R.hatch in R.vis_contents, "The constructor displays its own hatch")
	TEST_ASSERT_EQUAL(R.monitor_screen.icon_state, "screen_off", "Its screen starts off")
	TEST_ASSERT(R.monitor_screen in R.vis_contents, "The constructor displays its own monitor")

/datum/unit_test/dq_a13_initialization/meteorite_rotation/Run()
	scope_setup()
	var/obj/structure/meteorite/M = allocate(/obj/structure/meteorite, test_floor())
	var/list/rolled_contents = contents_of(M)
	TEST_ASSERT(length(rolled_contents) > 0, "The real meteorite constructor generates its actual ore or artifact contents")
	for(var/atom/movable/child in rolled_contents)
		own(child)
	TEST_ASSERT(isicon(M.icon), "The real meteorite realizes its rotated icon at construction")
	TEST_ASSERT(M.icon != initial(M.icon), "The constructor does not leave the original unrotated resource")

/datum/unit_test/dq_a13_initialization/analysis_memo/Run()
	scope_setup()
	var/obj/item/folder/white_rd/F = allocate(/obj/item/folder/white_rd, test_floor())
	var/obj/item/paper/P = locate(/obj/item/paper) in contents_of(F)
	TEST_ASSERT_NOTNULL(P, "The actual research folder constructs its analysis memo")
	own(P)
	TEST_ASSERT_EQUAL(contents_count(F), 1, "The folder starts with exactly its one authored memo")
	TEST_ASSERT_EQUAL(P.loc, F, "The constructor places the actual memo inside its folder")
	TEST_ASSERT_EQUAL(P.name, "Memo RE: proper analysis procedure", "The memo retains its exact authored title")
	TEST_ASSERT_EQUAL(P.info, "<br>We keep test dummies in pens here for a reason", "The memo retains its actual authored instructions")

/datum/unit_test/dq_a13_initialization/lootsafe_contents/Run()
	scope_setup()
	for(var/safe_type in list(/obj/structure/closet/crate/secure/lootsafe/numberlock/weak, /obj/structure/closet/crate/secure/lootsafe/devillock))
		var/obj/structure/closet/crate/secure/lootsafe/S = allocate(safe_type, test_floor())
		own_generated_contents(S)
		TEST_ASSERT_EQUAL(length(S.code), S.codelen, "The actual safe constructor generates its subtype's full code")
		var/list/alphabet = TYPE_TABLE_GET(S, code_alphabet)
		var/list/seen = list()
		for(var/character in S.code)
			TEST_ASSERT(character in alphabet, "Every actual code character belongs to the subtype's declared alphabet")
			TEST_ASSERT(!(character in seen), "The actual generated code never repeats a character")
			seen += character
		TEST_ASSERT(contents_count(S) > 0, "The constructor generates actual loot after its code")
		TEST_ASSERT(cap_key_get(S, LOCK_LOCKED), "Generating the initial code and loot leaves the real safe locked")

/// Capture real generated descendants before spill-on-delete containers materialize them.
/datum/unit_test/dq_a13_initialization/proc/own_generated_contents(atom/holder)
	if(istype(holder, /obj/item/storage))
		var/list/materialized = holder.latent_materialize_all()
		var/list/real_contents = contents_of(holder)
		TEST_ASSERT(!holder.has_latent(), "Native storage materialization consumes every latent entry")
		TEST_ASSERT(length(materialized) <= length(real_contents), "Every newly materialized item is represented in the real native contents")
		for(var/atom/movable/created in materialized)
			TEST_ASSERT(created in real_contents, "Native materialization returns the exact object held by its actual storage")
	for(var/atom/movable/child in contents_of(holder))
		own(child)
		own_generated_contents(child)
