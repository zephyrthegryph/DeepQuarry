// A complete tank hierarchy preserves gas/proxy setup before subtype fill and scale.
/datum/unit_test/dq_init_objects_tank_hierarchy

/datum/unit_test/dq_init_objects_tank_hierarchy/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/tank/oxygen/T = allocate(/obj/item/tank/oxygen, test_floor())
	TEST_ASSERT(T.air_contents && T.air_contents.return_pressure() > 0, "the actual oxygen tank has initialized native gas")
	TEST_ASSERT(T.proxyassembly, "base tank setup creates the actual assembly proxy")
	TEST_ASSERT_EQUAL(T.proxyassembly.tank, T, "the proxy links its exact actual tank")
	TEST_ASSERT_EQUAL(T.proxyassembly.loc, T, "the proxy stays contained in its tank")
	TEST_ASSERT_EQUAL(owner_of(T.proxyassembly), T, "the tank keeps its pre-existing native proxy ownership")
	var/obj/item/tankassemblyproxy/P = T.proxyassembly
	qdel(T)
	TEST_ASSERT(QDELETED(P), "deleting the tank deletes its actually owned proxy")
	var/obj/item/tank/phoron/pressurized/fuel = allocate(/obj/item/tank/phoron/pressurized, test_floor())
	TEST_ASSERT(fuel.proxyassembly && fuel.proxyassembly.tank == fuel, "pressurized descendant setup still follows base proxy setup")
	TEST_ASSERT_EQUAL(fuel.icon_scale_x, 0.8, "the separate pressurized scale setup retains its final horizontal result")
	TEST_ASSERT_EQUAL(fuel.icon_scale_y, 0.8, "the separate pressurized scale setup retains its final vertical result")

/datum/unit_test/dq_init_objects_tank_hierarchy/bomb_fill

/datum/unit_test/dq_init_objects_tank_hierarchy/bomb_fill/Run()
	dq_init_objects_fixture_scope()
	var/obj/item/tank/phoron/onetankbomb/full/F = allocate(/obj/item/tank/phoron/onetankbomb/full, test_floor())
	var/obj/item/tank/oxygen/onetankbomb/S = allocate(/obj/item/tank/oxygen/onetankbomb, test_floor(), 0)
	TEST_ASSERT_EQUAL(LINDA_GAS_AMT(F.air_contents, GAS_PHORON), 10, "the full type default fills actual phoron after base gas setup")
	TEST_ASSERT_EQUAL(LINDA_GAS_AMT(F.air_contents, GAS_O2), 15, "the full type default fills actual oxygen")
	TEST_ASSERT_EQUAL(LINDA_GAS_AMT(S.air_contents, GAS_PHORON), 3, "an explicit zero constructor parameter retains the small phoron fill")
	TEST_ASSERT_EQUAL(LINDA_GAS_AMT(S.air_contents, GAS_O2), 4.5, "an explicit zero constructor parameter retains the small oxygen fill")
	for(var/obj/item/tank/T as anything in list(F, S))
		TEST_ASSERT(T.valve_welded && T.wired, "the actual bomb constructor welds and wires its real tank")
		TEST_ASSERT(T.proxyassembly && T.proxyassembly.assembly, "the bomb subtype sees base setup's actual proxy before attaching its assembly")
		TEST_ASSERT_EQUAL(T.proxyassembly.assembly.loc, T, "the actual bomb assembly is constructed inside its tank")
		TEST_ASSERT_EQUAL(T.air_contents.return_temperature(), PLASMA_MINIMUM_BURN_TEMPERATURE - 1, "the constructor retains its actual gas heating target")
