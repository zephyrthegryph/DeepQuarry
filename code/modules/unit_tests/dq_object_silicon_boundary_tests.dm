// Native requirement ordering and actor-owned content providers, exercised on real actors.
/datum/unit_test/dq_silicon/c3_requirement_routes

/datum/unit_test/dq_silicon/c3_requirement_routes/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = make_human(T)
	var/mob/living/silicon/robot/R = make_borg(T)
	var/mob/living/silicon/ai/AI = make_ai(T)
	var/mob/living/simple_mob/animal/passive/dog/D = allocate(/mob/living/simple_mob/animal/passive/dog, T)
	var/obj/item/healthanalyzer/S = allocate(/obj/item/healthanalyzer, T)
	var/datum/op_plan/P = op_plan_for(S, "scan_patient")
	var/datum/entry/part/req/any/dexterity
	for(var/datum/entry/part/req/Q as anything in P.needs)
		if(istype(Q, /datum/entry/part/req/any))
			dexterity = Q
	TEST_ASSERT_NOTNULL(dexterity, "The actual scan op declares its actor-kind/dexterity composition")
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = S
	A.target = H
	A.oplan = P
	A.cap = P.owner_def
	A.actor = R
	TEST_ASSERT(op_req_holds(A, dexterity), "A real borg retains scanner dexterity")
	A.actor = AI
	TEST_ASSERT(op_req_holds(A, dexterity), "A real AI retains scanner dexterity")
	A.actor = D
	TEST_ASSERT(!op_req_holds(A, dexterity), "A real dog cannot use the scanner")
	TEST_ASSERT_EQUAL(op_req_refusal(A, dexterity), span_warning("You don't have the dexterity to do this!"), "The composed refusal retains its exact wording")
	A.release()
	var/obj/structure/toilet/toilet = allocate(/obj/structure/toilet, T)
	P = op_plan_for(toilet, "silicon_use")
	var/datum/entry/part/req/any/body_gate
	for(var/datum/entry/part/req/Q as anything in P.needs)
		if(istype(Q, /datum/entry/part/req/any))
			body_gate = Q
	TEST_ASSERT_NOTNULL(body_gate, "The real toilet declares its native robot/body gate")
	A = take(/datum/act/op)
	A.holder = toilet
	A.target = toilet
	A.oplan = P
	A.cap = P.owner_def
	A.actor = R
	TEST_ASSERT(!op_req_holds(A, body_gate), "A real borg without a client remains refused")
	A.actor = AI
	TEST_ASSERT(op_req_holds(A, body_gate), "The AI remote interface does not acquire the borg body restriction")
	A.actor = H
	TEST_ASSERT(op_req_holds(A, body_gate), "The body requirement retains its original non-borg behavior")
	A.release()
	var/obj/structure/railing/rail = allocate(/obj/structure/railing, get_step(T, EAST))
	P = op_plan_for(rail, "climb.climb_menu")
	TEST_ASSERT_NOTNULL(P, "The real railing declares the climb menu op")
	A = take(/datum/act/op)
	A.holder = rail
	A.target = rail
	A.actor = AI
	A.oplan = P
	A.cap = P.owner_def
	var/why
	for(var/datum/entry/part/req/Q as anything in P.needs)
		if(!op_req_holds(A, Q))
			why = op_req_refusal(A, Q)
			break
	TEST_ASSERT_EQUAL(reason_text(why), reason_text(MSG(climb/no_hands)), "The ordered real climb requirements refuse the AI for its missing hands")
	A.release()

/datum/unit_test/dq_silicon/c3_mecha_credentials

/datum/unit_test/dq_silicon/c3_mecha_credentials/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = make_human(T)
	var/mob/living/silicon/robot/R = make_borg(T)
	var/mob/living/silicon/ai/AI = make_ai(T)
	var/obj/mecha/M = allocate(/obj/mecha, T)
	var/obj/item/card/id/I = allocate(/obj/item/card/id, T)
	I.set_access(list(ACCESS_ROBOTICS))
	H.put_in_active_hand(I)
	TEST_ASSERT_EQUAL(H.get_active_hand(), I, "The human really holds the access card")
	TEST_ASSERT(M.internals_access_allowed(H), "The human's active card grants internal access")
	I.set_access(list())
	TEST_ASSERT(M.internals_access_allowed(H), "The existing internals check still accepts a present card with no matching access")
	TEST_ASSERT(H.drop_from_inventory(I), "The human releases the physical credential")
	TEST_ASSERT_NULL(H.get_active_hand(), "The human has no remaining active credential")
	TEST_ASSERT(!M.internals_access_allowed(H), "A human without a physical credential is refused")
	TEST_ASSERT_NOTNULL(R.idcard, "The real robot has its internal card")
	var/list/current_access = R.idcard.GetAccess()
	var/list/old_access = current_access.Copy()
	R.idcard.set_access(list(ACCESS_ROBOTICS))
	TEST_ASSERT(M.internals_access_allowed(R), "The robot's built-in card grants internal access")
	R.idcard.set_access(list())
	var/list/robot_credentials = R.mecha_internals_credentials()
	TEST_ASSERT_EQUAL(robot_credentials.len, 1, "The robot supplies exactly its internal credential")
	TEST_ASSERT_EQUAL(robot_credentials[1], R.idcard, "The provider returns the actual robot card")
	TEST_ASSERT(M.internals_access_allowed(R), "The existing internals check retains its present-card fallthrough for robots")
	R.idcard.set_access(old_access)
	TEST_ASSERT(!M.internals_access_allowed(AI), "An AI supplies no physical cockpit card")

/datum/unit_test/dq_silicon/c3_vacuum_ports

/datum/unit_test/dq_silicon/c3_vacuum_ports/run_gate()
	var/turf/T = test_floor()
	var/mob/living/carbon/human/H = make_human(T)
	var/mob/living/silicon/robot/R = make_borg(T)
	TEST_ASSERT_EQUAL(jointext(H.vac_output_choices(), "|"), "Vore Belly|Trash Bag", "The human sees exactly the two original ports")
	TEST_ASSERT_EQUAL(jointext(R.vac_output_choices(), "|"), "Vore Belly|Borg Belly|Trash Bag", "The borg sees its original three ports in order")
	TEST_ASSERT_NULL(H.vac_borg_output(), "A human has no borg sleeper port")
	if(!R.module)
		rel_set(R, nameof(R.module), new /obj/item/robot_module/robot/standard(R))
	var/obj/item/storage/bag/trash/carried = allocate(/obj/item/storage/bag/trash, T)
	H.put_in_active_hand(carried)
	TEST_ASSERT_EQUAL(H.vac_trash_output(), carried, "The human provider returns the actual carried bag")
	var/obj/item/storage/bag/trash/first_bag
	for(var/obj/item/storage/bag/trash/existing_bag in R.module.modules)
		first_bag = existing_bag
		break
	TEST_ASSERT_EQUAL(R.vac_module_trash_output(), first_bag, "The initial trash provider follows the actual catalog first match")
	var/obj/item/storage/bag/trash/module_bag = allocate(/obj/item/storage/bag/trash, R.module)
	R.module.add_item(module_bag, R)
	TEST_ASSERT(module_bag in R.module.modules, "The added bag joins the real module catalog")
	TEST_ASSERT_EQUAL(R.vac_module_trash_output(), first_bag ? first_bag : module_bag, "Appending a bag preserves the first actual module match")
	var/obj/item/dogborg/sleeper/first_sleeper
	for(var/obj/item/dogborg/sleeper/existing_sleeper in R.module.modules)
		first_sleeper = existing_sleeper
		break
	TEST_ASSERT_NOTNULL(first_sleeper, "The real standard module already supplies a sleeper")
	TEST_ASSERT(first_sleeper in R.module.modules, "The expected first sleeper belongs to the real catalog")
	TEST_ASSERT_EQUAL(R.vac_borg_output(), first_sleeper, "The sleeper provider selects the actual initial first match")
	var/obj/item/dogborg/sleeper/sleeper = allocate(/obj/item/dogborg/sleeper, R.module)
	R.module.add_item(sleeper, R)
	TEST_ASSERT(sleeper in R.module.modules, "The added sleeper joins the real module catalog")
	TEST_ASSERT_EQUAL(R.vac_borg_output(), first_sleeper, "Appending a sleeper does not replace the earlier standard module match")

/datum/unit_test/dq_silicon/toilet_silent_menu
/datum/unit_test/dq_silicon/toilet_silent_menu/run_gate()
	var/turf/T = test_floor()
	var/mob/living/silicon/robot/R = make_borg(T)
	TEST_ASSERT_NULL(R.client, "the fixture exercises the actual clientless borg guard")
	var/obj/structure/toilet/wooden/toilet = allocate(/obj/structure/toilet/wooden, T)
	var/datum/op_plan/P = op_plan_for(toilet, "silicon_use")
	var/datum/entry/part/req/any/body_gate
	for(var/datum/entry/part/req/Q as anything in P.needs)
		if(istype(Q, /datum/entry/part/req/any))
			body_gate = Q
	TEST_ASSERT_NOTNULL(body_gate, "the real toilet has its composed body admission requirement")
	var/datum/act/op/A = take(/datum/act/op)
	A.holder = toilet
	A.target = toilet
	A.actor = R
	A.oplan = P
	A.cap = P.owner_def
	var/reason = body_gate.check(A)
	TEST_ASSERT(!isnull(reason), "the real clientless borg is still refused")
	TEST_ASSERT_EQUAL(reason_text(reason), "", "both native alternatives preserve the existing silent refusal")
	A.release()
	for(var/list/row in action_options(R, toilet, null))
		TEST_ASSERT(row["key"] != "silicon_use", "the no-client use is absent rather than generically refused in the actual menu")
