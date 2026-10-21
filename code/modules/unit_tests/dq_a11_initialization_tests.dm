// Constructor regressions for declared atmos, research and mode setup.
/datum/unit_test/dq_a11_initialization
	abstract_type = /datum/unit_test/dq_a11_initialization

/datum/unit_test/dq_a11_initialization/New()
	. = ..()
	dview(0, test_floor())

/datum/unit_test/dq_a11_initialization/proc/scope_setup()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)

/obj/machinery/atmospherics/pipeturbine/dq_a11_east
	dir = EAST

/datum/unit_test/dq_a11_initialization/turbine_ports/Run()
	scope_setup()
	var/obj/machinery/atmospherics/pipeturbine/T = allocate(/obj/machinery/atmospherics/pipeturbine/dq_a11_east, test_floor())
	TEST_ASSERT_NOTNULL(T.air_in, "The real turbine's declared inlet exists before setup")
	TEST_ASSERT_NOTNULL(T.air_out, "The real turbine's declared outlet exists before setup")
	TEST_ASSERT_EQUAL(T.volume_ratio, 0.2, "The turbine derives its actual 200:800 port ratio")
	TEST_ASSERT_EQUAL(T.initialize_directions, NORTH|SOUTH, "An east-facing turbine connects across its actual axis")

/datum/unit_test/dq_a11_initialization/message_server/Run()
	scope_setup()
	var/obj/machinery/message_server/S = allocate(/obj/machinery/message_server, test_floor())
	TEST_ASSERT(S.decryptkey != "password", "The real server rolls its key rather than retaining the placeholder")
	TEST_ASSERT(findtext("0123456789", copytext(S.decryptkey, length(S.decryptkey), length(S.decryptkey)+1)), "The key's final character has the original digit distribution")
	TEST_ASSERT_EQUAL(length(S.pda_msgs), 1, "Construction records exactly one startup message")
	var/datum/data_pda_msg/M = S.pda_msgs[1]
	TEST_ASSERT_EQUAL(M.recipient, "System Administrator", "The real startup recipient survives declared setup")
	TEST_ASSERT_EQUAL(M.sender, "system", "The startup message remains attributed to the system")

/datum/unit_test/dq_a11_initialization/changeling_creator/Run()
	scope_setup()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, test_floor())
	var/obj/item/melee/changeling/W = allocate(/obj/item/melee/changeling, H)
	TEST_ASSERT_EQUAL(W.creator, H, "A real grown weapon captures its actual living constructor owner")
	TEST_ASSERT_EQUAL(W.loc, H, "Declared formation does not displace the weapon")

/datum/unit_test/dq_a11_initialization/research_disk/Run()
	scope_setup()
	var/obj/item/disk/tech_disk/D = allocate(/obj/item/disk/tech_disk, test_floor())
	TEST_ASSERT_NOTNULL(D.stored_research(), "The disk constructor retains its actual research store")
	TEST_ASSERT(D.pixel_x >= -D.randpixel && D.pixel_x <= D.randpixel, "The native jitter preserves the configured horizontal range")
	TEST_ASSERT(D.pixel_y >= -D.randpixel && D.pixel_y <= D.randpixel, "The native jitter preserves the configured vertical range")

/datum/unit_test/dq_a11_initialization/gas_plane/Run()
	scope_setup()
	var/obj/effect/overlay/gas/G = allocate(/obj/effect/overlay/gas, null, 2)
	TEST_ASSERT_EQUAL(G.plane_offset, 2, "The actual positional plane parameter survives until setup")
	TEST_ASSERT_EQUAL(G.plane, ABOVE_GAME_PLANE, "The native plane job preserves this backend's scalar-plane contract")

/datum/unit_test/dq_a11_initialization/pipe_and_vent_rendering/Run()
	scope_setup()
	var/obj/machinery/atmospherics/pipe/simple/P = allocate(/obj/machinery/atmospherics/pipe/simple/hidden, test_floor())
	TEST_ASSERT_EQUAL(P.alpha, 255, "A hidden map pipe becomes opaque at runtime despite its editor alpha")
	TEST_ASSERT(isnull(P.icon), "Runtime pipe rendering uses its cached overlays rather than the editor icon")
	var/obj/machinery/atmospherics/unary/vent_pump/V = allocate(/obj/machinery/atmospherics/unary/vent_pump, test_floor())
	TEST_ASSERT_EQUAL(V.air_contents.return_volume(), V.vent_volume, "The real vent keeps its configured port volume")
	TEST_ASSERT(isnull(V.icon), "The vent renderer clears the map-only icon")
