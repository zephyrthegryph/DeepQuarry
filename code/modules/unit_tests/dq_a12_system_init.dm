// A12 declared lifecycle jobs: actual bodies, circuits and economy constructors.
/datum/unit_test/dq_a12_system_init
	abstract_type = /datum/unit_test/dq_a12_system_init

/datum/unit_test/dq_a12_system_init/New()
	..()
	dview(0, test_floor())
	status_policies()

/datum/unit_test/dq_a12_system_init/brain_host/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/organ/internal/brain/B = allocate(/obj/item/organ/internal/brain, test_floor())
	TEST_ASSERT_NOTNULL(get_mind_host(B), "A real loose brain receives its mind host during setup")
	TEST_ASSERT_NOTNULL(B.defib_clock_at, "The real brain synchronizes its defibrillation clock during setup")

/datum/unit_test/dq_a12_system_init/voice_languages/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/organ/internal/voicebox/robot/R = allocate(/obj/item/organ/internal/voicebox/robot, test_floor())
	var/obj/item/organ/internal/voicebox/horror/H = allocate(/obj/item/organ/internal/voicebox/horror, test_floor())
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_GALCOM] in R.assists_languages, "The real robot voicebox inherits GalCom assistance")
	TEST_ASSERT(GLOB.all_languages[LANGUAGE_EAL] in R.assists_languages, "Its subtype also assists EAL")
	TEST_ASSERT_EQUAL(H.redspace, GLOB.all_languages[LANGUAGE_REDSPACE], "Horror setup keeps the actual shared language reference")
	TEST_ASSERT(H.redspace in H.assists_languages, "The inherited language job uses the horror subtype's language list")

/datum/unit_test/dq_a12_system_init/signaler_pins/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/integrated_circuit/input/signaler/S = allocate(/obj/item/integrated_circuit/input/signaler, test_floor())
	TEST_ASSERT_EQUAL(S.get_pin_data(IC_INPUT, 1), S.frequency, "The inherited synchronous pin builder precedes signaler setup")
	TEST_ASSERT_EQUAL(S.get_pin_data(IC_INPUT, 2), S.code, "The real signaler populates its actual code input")

/datum/unit_test/dq_a12_system_init/device_links/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/item/assembly/electronic_assembly/A = allocate(/obj/item/assembly/electronic_assembly, test_floor())
	TEST_ASSERT_NOTNULL(A.EA, "Declared device contents exist before the wrapper's setup")
	TEST_ASSERT_EQUAL(A.EA.holder(), A, "Wrapper setup binds the actual device holder")
	var/obj/item/integrated_circuit/built_in/device_input/I = locate_within(A.EA, /obj/item/integrated_circuit/built_in/device_input)
	var/obj/item/integrated_circuit/built_in/device_output/O = locate_within(A.EA, /obj/item/integrated_circuit/built_in/device_output)
	TEST_ASSERT_NOTNULL(I, "Device setup constructs its actual built-in input circuit")
	TEST_ASSERT_NOTNULL(O, "Device setup constructs its actual built-in output circuit")
	own(I)
	own(O)
	TEST_ASSERT_EQUAL(I.assembly(), A.EA, "The input circuit points to its actual assembly")
	TEST_ASSERT_EQUAL(O.assembly(), A.EA, "The output circuit points to its actual assembly")

/obj/trader/dq_a12
	start_products = list(/obj/item/pen, /obj/item/paper)

/datum/unit_test/dq_a12_system_init/trader_contents/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	var/obj/trader/dq_a12/T = allocate(/obj/trader/dq_a12, test_floor())
	for(var/obj/item/I in contents_of(T))
		own(I)
	TEST_ASSERT_EQUAL(length(T.products), 2, "The actual trader constructor creates every mapped starting product")
	TEST_ASSERT(locate_within(T, /obj/item/pen), "The actual pen exists in the trader")
	TEST_ASSERT(locate_within(T, /obj/item/paper), "The actual paper exists in the trader")
	TEST_ASSERT_EQUAL(LAZYLEN(T.start_products), 0, "Starting product paths are consumed exactly as before")

/datum/unit_test/dq_a12_system_init/eftpos_manuals/Run()
	set_global(nameof(GLOB.coalesce_runs), GLOB.coalesce_runs)
	set_global(nameof(GLOB.num_financial_terminals), GLOB.num_financial_terminals)
	var/turf/T = test_floor()
	var/list/before = contents_of(T)
	var/counter = GLOB.num_financial_terminals
	var/obj/item/eftpos/E = allocate(/obj/item/eftpos, T)
	TEST_ASSERT_EQUAL(GLOB.num_financial_terminals, counter + 1, "The actual terminal increments its station identifier once")
	TEST_ASSERT_EQUAL(E.linked_account(), GLOB.station_account, "Setup still links the station's actual account")
	var/manuals = 0
	var/parcels = 0
	for(var/atom/movable/O in contents_of(T))
		if(O in before || O == E)
			continue
		own(O)
		if(istype(O, /obj/item/paper))
			var/obj/item/paper/P = O
			if(P.name == "Steps to success: Correct EFTPOS Usage")
				manuals++
				TEST_ASSERT(findtext(P.info, "Memorise your EFTPOS command code"), "The actual manual retains its instructions")
		if(istype(O, /obj/item/smallDelivery))
			var/obj/item/smallDelivery/D = O
			TEST_ASSERT_NOTNULL(D.wrapped, "The actual reference parcel owns its code paper")
			own(D.wrapped)
			parcels++
	TEST_ASSERT_EQUAL(manuals, 1, "Setup leaves one actual user manual on the construction tile")
	TEST_ASSERT_EQUAL(parcels, 1, "Setup leaves one actual wrapped access-code reference on the construction tile")
