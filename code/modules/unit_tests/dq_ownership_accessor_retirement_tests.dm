// Policies pinned before replacing dynamic ownership accessors.
/obj/ownership_retirement_state_probe
	var/obj/item/deleted_child
	var/obj/item/spilled_child
	var/list/deleted_children
	var/list/watches

CAPABILITIES(/obj/ownership_retirement_state_probe)
	owns_one(nameof(deleted_child))
	owns_one(nameof(spilled_child), on_destroy = ON_DESTROY_SPILL)
	owns_many(nameof(deleted_children))
	owns_many(nameof(watches), /datum/native_watch/gas)

/obj/ownership_retirement_state_probe/proc/watch_heard(datum/native_watch/gas/W, mixture_id, change_mask, list/observation, observation_index)
	return

/datum/unit_test/ownership_retirement_codec_policy_pin

/datum/unit_test/ownership_retirement_codec_policy_pin/Run()
	var/obj/ownership_retirement_state_probe/H = allocate(/obj/ownership_retirement_state_probe)
	var/datum/state_codec/owned/C = allocate(/datum/state_codec/owned)
	var/datum/state_context/ctx = allocate(/datum/state_context)
	var/obj/item/deleted = allocate(/obj/item, H)
	var/obj/item/spilled = allocate(/obj/item, H)
	rel_set(H, nameof(H.deleted_child), deleted)
	rel_set(H, nameof(H.spilled_child), spilled)
	C.decode(H, nameof(H.deleted_child), null, ctx)
	C.decode(H, nameof(H.spilled_child), null, ctx)
	TEST_ASSERT(QDELETED(deleted), "Null decoding must delete a DELETE child")
	TEST_ASSERT(!QDELETED(spilled), "Null decoding must preserve a SPILL child")
	TEST_ASSERT_EQUAL(spilled.loc, get_turf(H), "The preserved child must spill to the holder turf")
	var/obj/item/member = allocate(/obj/item, H)
	rel_add(H, nameof(H.deleted_children), member)
	C.decode(H, nameof(H.deleted_children), list(STATE_WRAP_OWNED = list(), "shape" = "list"), ctx)
	TEST_ASSERT(QDELETED(member), "Decoding an empty list disposes of previous DELETE members")
	TEST_ASSERT_EQUAL(length(H.deleted_children), 0, "The decoded list must be empty")
	var/obj/item/reset_deleted = allocate(/obj/item, H)
	var/obj/item/reset_spilled = allocate(/obj/item, H)
	rel_set(H, nameof(H.deleted_child), reset_deleted)
	rel_set(H, nameof(H.spilled_child), reset_spilled)
	TEST_ASSERT(state_reset_owned_var(H, nameof(H.deleted_child), null), "Serializer reset must recognize owned DELETE var")
	TEST_ASSERT(state_reset_owned_var(H, nameof(H.spilled_child), null), "Serializer reset must recognize owned SPILL var")
	TEST_ASSERT(QDELETED(reset_deleted), "Serializer reset must honor DELETE")
	TEST_ASSERT(!QDELETED(reset_spilled), "Serializer reset must honor SPILL")
	TEST_ASSERT_EQUAL(reset_spilled.loc, get_turf(H), "Serializer reset spills to the holder turf")

/datum/unit_test/ownership_retirement_fabricator_policy_pin

/datum/unit_test/ownership_retirement_fabricator_policy_pin/Run()
	var/obj/machinery/autolathe/M = allocate(/obj/machinery/autolathe)
	var/list/entry = own_table_of(M).entries[nameof(M.print_run)]
	TEST_ASSERT(entry && entry[OWNE_KIND] == OWNK_OWN && entry[OWNE_ARG] == OWN_DELETE && !entry[OWNE_LIST], "The actual autolathe print_run must be a DELETE single")
	var/datum/fab_run/run = allocate(/datum/fab_run)
	run.sound = nameof(M.print_sound)
	rel_set(M, nameof(M.print_run), run)
	cap_key_set(M, FABRICATOR_PRINTING, TRUE, null)
	TEST_ASSERT(fabricator_printing(M), "Setup reserves the real machine for its print run")
	fabricator_run_ended(M, nameof(M.print_run))
	TEST_ASSERT(QDELETED(run), "Ending fabrication must delete its run")
	TEST_ASSERT_NULL(M.print_run, "Ending fabrication must release the run slot")
	TEST_ASSERT(!fabricator_printing(M), "Ending fabrication must release its printing reservation")

/datum/unit_test/ownership_retirement_gas_watch_policy_pin

/datum/unit_test/ownership_retirement_gas_watch_policy_pin/Run()
	var/obj/ownership_retirement_state_probe/H = allocate(/obj/ownership_retirement_state_probe)
	var/obj/machinery/atmospherics/pipe/simple/P = allocate(/obj/machinery/atmospherics/pipe/simple)
	var/obj/machinery/atmospherics/pipe/simple/heat_exchanging/HE = allocate(/obj/machinery/atmospherics/pipe/simple/heat_exchanging)
	var/obj/machinery/atmospherics/pipeturbine/T = allocate(/obj/machinery/atmospherics/pipeturbine)
	var/obj/machinery/power/generator/G = allocate(/obj/machinery/power/generator)
	for(var/list/pair as anything in list(list(P, nameof(P.leak_watches)), list(HE, nameof(HE.glow_watches)), list(T, nameof(T.side_watches)), list(G, nameof(G.loop_watches))))
		var/datum/holder = pair[1]
		var/list/entry = own_table_of(holder).entries[pair[2]]
		TEST_ASSERT(entry && entry[OWNE_KIND] == OWNK_OWN && entry[OWNE_LIST] && entry[OWNE_ARG] == OWN_DELETE, "Every current gas-watch consumer declares a DELETE many: [holder.type].[pair[2]]")
	var/datum/gas_mixture/air = allocate(/datum/gas_mixture, 70)
	gas_watch_many(H, nameof(H.watches), list(air, air), GAS_DEPENDENCY_ALL, TYPE_PROC_REF(/obj/ownership_retirement_state_probe, watch_heard))
	TEST_ASSERT_EQUAL(length(H.watches), 1, "Repeated mixture IDs create exactly one real native watch")
	var/datum/native_watch/gas/W = H.watches[1]
	gas_watch_many_clear(H, nameof(H.watches))
	TEST_ASSERT(QDELETED(W), "Clearing the dynamic watch var deletes the native watch")
	TEST_ASSERT_EQUAL(length(H.watches), 0, "Clearing removes every watch from the owner")

/datum/unit_test/ownership_retirement_lemat_policy_pin

/datum/unit_test/ownership_retirement_lemat_policy_pin/Run()
	var/obj/item/gun/projectile/revolver/lemat/G = allocate(/obj/item/gun/projectile/revolver/lemat)
	for(var/slot in list(nameof(G.loaded), nameof(G.secondary_loaded), nameof(G.tertiary_loaded)))
		var/list/entry = own_table_of(G).entries[slot]
		TEST_ASSERT(entry && entry[OWNE_KIND] == OWNK_OWN && entry[OWNE_LIST] && entry[OWNE_ARG] == OWN_DELETE, "Each dynamic cylinder pool is an owned DELETE list: [slot]")
	var/list/primary = G.loaded.Copy()
	var/list/secondary = G.secondary_loaded.Copy()
	TEST_ASSERT(length(primary) > 0 && length(secondary) > 0, "A real LeMat must initialize both cylinder pools")
	G.swap_cylinder(nameof(G.secondary_loaded), nameof(G.tertiary_loaded))
	TEST_ASSERT_EQUAL(length(G.loaded), length(secondary), "The secondary pool becomes loaded")
	TEST_ASSERT_EQUAL(length(G.tertiary_loaded), length(primary), "The primary pool becomes stashed")
	TEST_ASSERT_EQUAL(length(G.secondary_loaded), 0, "The incoming pool is emptied")
	for(var/datum/round as anything in secondary)
		TEST_ASSERT(round in G.loaded, "Every secondary round remains loaded and alive")
		TEST_ASSERT(!QDELETED(round), "Swapping never disposes of incoming rounds")
	G.swap_cylinder(nameof(G.tertiary_loaded), nameof(G.secondary_loaded))
	for(var/datum/round as anything in primary)
		TEST_ASSERT(round in G.loaded, "Swapping back restores each primary round")
		TEST_ASSERT(!QDELETED(round), "Swapping back preserves primary rounds")
	var/list/none = rel_take_all(G, nameof(G.tertiary_loaded))
	TEST_ASSERT(islist(none) && !length(none), "The empty lazy cylinder always yields an empty list")

/datum/unit_test/ownership_retirement_carried_afflictions

/datum/unit_test/ownership_retirement_carried_afflictions/Run()
	var/datum/carried_afflictions/C = allocate(/datum/carried_afflictions)
	var/list/empty = C.release()
	TEST_ASSERT(islist(empty) && !length(empty), "An unset carried-affliction list releases an empty list")
	var/datum/affliction/A = allocate(/datum/affliction)
	C.take(list(A))
	var/list/released = C.release()
	TEST_ASSERT_EQUAL(length(released), 1, "Release returns the actual carried affliction")
	TEST_ASSERT_EQUAL(released[1], A, "The same affliction returns to the caller")
	TEST_ASSERT(!QDELETED(A), "Release must preserve the affliction")
	TEST_ASSERT_EQUAL(length(C.afflictions), 0, "Release empties its old owner")

/datum/unit_test/ownership_retirement_card_shuffle

/datum/unit_test/ownership_retirement_card_shuffle/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	for(var/path in list(/obj/item/deck/cards, /obj/item/deck/tarot, /obj/item/deck/dark_tarot))
		var/obj/item/deck/D = allocate(path)
		var/list/cards = D.cards.Copy()
		TEST_ASSERT(length(cards) > 0, "The actual deck must contain cards before shuffle")
		D.shuffle(user)
		TEST_ASSERT_EQUAL(length(D.cards), length(cards), "Shuffle preserves the exact card count")
		for(var/datum/playingcard/C as anything in cards)
			TEST_ASSERT(C in D.cards && !QDELETED(C), "Shuffle preserves every original card")
