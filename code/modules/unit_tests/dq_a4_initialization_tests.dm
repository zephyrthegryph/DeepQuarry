// Machinery lifecycle setup is complete when a real constructor returns.
/datum/unit_test/dq_a4_initialization
	abstract_type = /datum/unit_test/dq_a4_initialization

/datum/unit_test/dq_a4_initialization/New()
	. = ..()
	dview(0, test_floor())

/datum/unit_test/dq_a4_initialization/proc/scope_setup()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.roll_serial), GLOB.roll_serial)

/datum/unit_test/dq_a4_initialization/colour_matrix/Run()
	scope_setup()
	var/obj/machinery/gear_painter/P = allocate(/obj/machinery/gear_painter, test_floor())
	TEST_ASSERT_EQUAL(length(P.color_matrix_last), 12, "The real painter starts with its complete identity colour matrix")
	for(var/i = 1 to 12)
		TEST_ASSERT_EQUAL(P.color_matrix_last[i], (i == 1 || i == 5 || i == 9) ? 1 : 0, "Identity matrix entry [i] is initialized")
	var/obj/machinery/gear_painter/other = allocate(/obj/machinery/gear_painter, test_floor())
	TEST_ASSERT(P.color_matrix_last != other.color_matrix_last, "Mutable matrices belong to each painter separately")

/obj/machinery/requests_console/dq_a4_department
	department = "A4 setup fixture"
	departmentType = RC_ASSIST|RC_SUPPLY|RC_INFO

/datum/unit_test/dq_a4_initialization/department_registration/Run()
	scope_setup()
	set_global(nameof(GLOB.req_console_assistance), GLOB.req_console_assistance.Copy())
	set_global(nameof(GLOB.req_console_supplies), GLOB.req_console_supplies.Copy())
	set_global(nameof(GLOB.req_console_information), GLOB.req_console_information.Copy())
	var/obj/machinery/requests_console/C = allocate(/obj/machinery/requests_console/dq_a4_department, test_floor())
	TEST_ASSERT_EQUAL(C.name, "A4 setup fixture requests console", "The console uses its configured department")
	TEST_ASSERT_EQUAL(C.announcement.title, "A4 setup fixture announcement", "The declared announcement is configured after it exists")
	TEST_ASSERT_EQUAL(C.announcement.newscast, 1, "Department announcements permit newscasts")
	TEST_ASSERT(C.department in GLOB.req_console_assistance, "The assistance directory includes the department")
	TEST_ASSERT(C.department in GLOB.req_console_supplies, "The supply directory includes the department")
	TEST_ASSERT(C.department in GLOB.req_console_information, "The information directory includes the department")
	qdel(C)
	TEST_ASSERT(!("A4 setup fixture" in GLOB.req_console_assistance), "Destruction removes the department registration")

/datum/unit_test/dq_a4_initialization/nuclear_wire_rolls/Run()
	scope_setup()
	var/obj/machinery/nuclearbomb/B = allocate(/obj/machinery/nuclearbomb, test_floor())
	var/code = text2num(B.r_code)
	TEST_ASSERT(code >= 10000 && code <= 99999, "The real bomb has a five-digit rolled authorization code")
	TEST_ASSERT_EQUAL(length(B.wires_list), 7, "Every wire starts with an intact state")
	for(var/wire in B.wires_list)
		TEST_ASSERT_EQUAL(B.wires_list[wire], 0, "Wire [wire] starts intact")
	TEST_ASSERT(B.light_wire in B.wires_list, "The light wire is a real wire")
	TEST_ASSERT(B.timing_wire in B.wires_list, "The timer wire is a real wire")
	TEST_ASSERT(B.safety_wire in B.wires_list, "The safety wire is a real wire")
	TEST_ASSERT(B.light_wire != B.timing_wire && B.light_wire != B.safety_wire && B.timing_wire != B.safety_wire, "The three independent functions use distinct wires")

/datum/unit_test/dq_a4_initialization/rcd_turret_integrity/Run()
	scope_setup()
	var/obj/machinery/porta_turret/rcd/T = allocate(/obj/machinery/porta_turret/rcd, test_floor())
	TEST_ASSERT_EQUAL(T.max_integrity, 20, "The RCD turret retains its compiled maximum integrity")
	TEST_ASSERT_EQUAL(T.get_integrity(), 5, "The RCD turret starts at the reduced integrity")

/datum/unit_test/dq_a4_initialization/floodlight_started_on/Run()
	scope_setup()
	var/obj/machinery/floodlight/F = allocate(/obj/machinery/floodlight/starts_on, test_floor())
	TEST_ASSERT_NOTNULL(F.cell, "The declared floodlight cell exists before its startup hook")
	TEST_ASSERT(F.on, "The starts-on floodlight is switched on before construction returns")
