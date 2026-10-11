/datum/unit_test/dq_culture_payload_ownership/Run()
	var/obj/item/reagent_containers/glass/beaker/vial/culture/cold/C = allocate(/obj/item/reagent_containers/glass/beaker/vial/culture/cold)
	var/datum/reagent/blood/B = C.reagents.get_reagent(REAGENT_ID_BLOOD)
	TEST_ASSERT(B && length(B.data["viruses"]) == 1, "real culture starts with infected blood")
	var/datum/affliction/contagion/donor = C.diseases[1]
	var/list/viruses = B.data["viruses"]
	var/datum/affliction/contagion/owned = viruses[1]
	TEST_ASSERT(owned != donor, "blood owns an independent copy of vial disease")
	var/datum/reagent_payload/P = reagent_payload(B)
	var/list/copied = P.value["viruses"]
	var/datum/affliction/contagion/temporary = copied[1]
	TEST_ASSERT(temporary != owned && temporary != donor, "scoped getter copies owned children")
	qdel(P)
	TEST_ASSERT(QDELETED(temporary), "temporary payload deletes its copied disease")
	TEST_ASSERT(!QDELETED(owned) && !QDELETED(donor), "temporary deletion preserves blood and donor")
	SetViruses(B, B.data)
	var/list/replaced = B.data["viruses"]
	TEST_ASSERT(replaced[1] != owned && QDELETED(owned), "self replacement copies first then deletes displaced child")
	TEST_ASSERT(!QDELETED(donor), "replacement never deletes vial's borrowed source")
	var/datum/affliction/contagion/latest = replaced[1]
	C.reagents.clear_reagents()
	TEST_ASSERT(QDELETED(latest), "deleting reagent deletes its final payload")
	TEST_ASSERT(!QDELETED(donor), "source owner remains alive")

/datum/unit_test/dq_culture_payload_ownership/transfer/Run()
	var/obj/item/reagent_containers/glass/beaker/vial/culture/cold/C = allocate(/obj/item/reagent_containers/glass/beaker/vial/culture/cold)
	var/obj/item/reagent_containers/glass/beaker/T = allocate(/obj/item/reagent_containers/glass/beaker)
	TEST_ASSERT_EQUAL(C.reagents.trans_id_to(T, REAGENT_ID_BLOOD, 3, TRUE), 3, "real temporary-holder transfer preserves quantity")
	var/datum/reagent/blood/source = C.reagents.get_reagent(REAGENT_ID_BLOOD)
	var/datum/reagent/blood/destination = T.reagents.get_reagent(REAGENT_ID_BLOOD)
	TEST_ASSERT(source && destination, "both holders retain real blood")
	var/list/S = source.data["viruses"]
	var/list/D = destination.data["viruses"]
	TEST_ASSERT(length(S) == 1 && length(D) == 1 && S[1] != D[1], "transfer children have distinct ownership")
	var/datum/affliction/contagion/survivor = D[1]
	C.reagents.clear_reagents()
	TEST_ASSERT(!QDELETED(survivor), "destination survives source deletion")
	T.reagents.clear_reagents()
	TEST_ASSERT(QDELETED(survivor), "destination releases its final disease")

/datum/unit_test/dq_culture_payload_ownership/codec/Run()
	var/obj/item/reagent_containers/glass/beaker/vial/culture/cold/C = allocate(/obj/item/reagent_containers/glass/beaker/vial/culture/cold)
	var/datum/reagent/blood/B = C.reagents.get_reagent(REAGENT_ID_BLOOD)
	var/datum/state_context/ctx = allocate(/datum/state_context)
	var/datum/state_codec/reagents/codec = allocate(/datum/state_codec/reagents)
	var/encoded = codec.encode_payload(B, ctx, "culture test")
	TEST_ASSERT(islist(encoded) && encoded["reagent_payload"], "domain codec stores owned child wrappers")
	var/datum/reagent_payload/P = codec.decode_payload(B, encoded, ctx)
	var/list/copies = P.value["viruses"]
	var/list/originals = B.data["viruses"]
	TEST_ASSERT(length(copies) == 1 && copies[1] != originals[1], "decode materializes independent child")
	var/datum/affliction/contagion/child = copies[1]
	qdel(P)
	TEST_ASSERT(QDELETED(child) && !QDELETED(originals[1]), "decoded temporary child is owned without deleting source")

/datum/unit_test/dq_culture_payload_ownership/mixed_and_paint/Run()
	var/obj/item/reagent_containers/glass/beaker/vial/culture/cold/C = allocate(/obj/item/reagent_containers/glass/beaker/vial/culture/cold)
	var/obj/item/reagent_containers/glass/beaker/vial/culture/flu/F = allocate(/obj/item/reagent_containers/glass/beaker/vial/culture/flu)
	var/obj/item/reagent_containers/glass/beaker/T = allocate(/obj/item/reagent_containers/glass/beaker)
	TEST_ASSERT_EQUAL(C.reagents.trans_to_holder(T.reagents, 3), 3, "first donor seeds recipient")
	var/datum/reagent/blood/B = T.reagents.get_reagent(REAGENT_ID_BLOOD)
	var/list/before = B.data["viruses"]
	var/datum/affliction/contagion/displaced = before[1]
	TEST_ASSERT_EQUAL(F.reagents.trans_to_holder(T.reagents, 2), 2, "real addition invokes blood mixing")
	var/list/after = B.data["viruses"]
	TEST_ASSERT(length(after) == 1 && QDELETED(displaced), "engineered mix replaces and deletes displaced blood copy")
	var/datum/affliction/contagion/mixed = after[1]
	TEST_ASSERT(mixed in B.codec_children, "mixed result is owned by surviving blood")
	T.reagents.clear_reagents()
	TEST_ASSERT(QDELETED(mixed), "final mixed child has bounded lifetime")
	var/datum/reagent/paint/P = allocate(/datum/reagent/paint)
	P.initialize_data("#123456")
	SetViruses(P, "#123456")
	TEST_ASSERT_EQUAL(P.get_data(), "#123456", "scalar paint payload never enters list-copy branch")

/datum/unit_test/dq_culture_payload_ownership/watch_lifetime/Run()
	var/list/before = list()
	for(var/index in GLOB.op_watchers)
		var/list/on = GLOB.op_watchers[index]
		before[index] = on.Copy()
	var/list/hops_before = GLOB.every_hop_watches.Copy()
	var/obj/item/reagent_containers/glass/beaker/vial/culture/cold/C = allocate(/obj/item/reagent_containers/glass/beaker/vial/culture/cold)
	var/obj/item/reagent_containers/glass/beaker/vial/culture/flu/F = allocate(/obj/item/reagent_containers/glass/beaker/vial/culture/flu)
	var/obj/item/reagent_containers/glass/beaker/T = allocate(/obj/item/reagent_containers/glass/beaker)
	TEST_ASSERT_EQUAL(C.reagents.trans_to_holder(T.reagents, 3), 3, "Real culture transfer creates independent infected blood")
	TEST_ASSERT_EQUAL(F.reagents.trans_to_holder(T.reagents, 2), 2, "Second real culture executes engineered mixing")
	var/datum/reagent/blood/B = T.reagents.get_reagent(REAGENT_ID_BLOOD)
	TEST_ASSERT(B && length(B.data["viruses"]) == 1, "Mixed recipient owns real disease before cleanup")
	var/list/diseases = B.data["viruses"]
	var/datum/affliction/contagion/mixed = diseases[1]
	var/datum/reagent_payload/P = reagent_payload(B)
	var/list/temporary = P.value["viruses"]
	var/datum/affliction/contagion/copy = temporary[1]
	TEST_ASSERT(copy != mixed, "Temporary snapshot is independent before teardown")
	// Keep exact identities alive in local lists; this does not change registry membership.
	var/list/created = list()
	for(var/index in GLOB.op_watchers)
		var/list/on = GLOB.op_watchers[index]
		var/list/old = before[index]
		var/list/added = on.Copy()
		if(old)
			added -= old
		if(length(added))
			created[index] = added
	var/list/hops_created = list()
	for(var/index in GLOB.every_hop_watches)
		if(!(index in hops_before))
			hops_created[index] = GLOB.every_hop_watches[index]
	qdel(P)
	qdel(C)
	qdel(F)
	qdel(T)
	TEST_ASSERT(QDELETED(copy) && QDELETED(mixed), "All observed recipient and snapshot children are destroyed")
	for(var/index in created)
		var/list/added = created[index]
		var/list/on = GLOB.op_watchers[index]
		for(var/datum/watcher as anything in added)
			TEST_ASSERT(!(watcher in on), "Actual snapshot-created watcher was removed from its exact index [index]")
	for(var/index in before)
		var/list/old = before[index]
		var/list/on = GLOB.op_watchers[index]
		TEST_ASSERT_EQUAL(length(on), length(old), "Preexisting watch-index membership has unchanged cardinality [index]")
		for(var/datum/watcher as anything in old)
			TEST_ASSERT(watcher in on, "Each preexisting watcher remains at its original index [index]")
	for(var/index in GLOB.op_watchers)
		TEST_ASSERT(index in before, "No new watch index survives teardown [index]")
	for(var/index in hops_created)
		TEST_ASSERT(!(index in GLOB.every_hop_watches), "Actual new hop-registry entry was removed [index]")
	for(var/index in hops_before)
		TEST_ASSERT_EQUAL(GLOB.every_hop_watches[index], hops_before[index], "Preexisting hop watcher retains exact identity [index]")
	for(var/index in GLOB.every_hop_watches)
		TEST_ASSERT(index in hops_before, "No new hop-registry identity survives teardown [index]")

/datum/affliction/contagion/dq_culture_decode_fault
	var/static/datum/last_failed

/datum/affliction/contagion/dq_culture_decode_fault/state_post_apply(list/blob, flags)
	last_failed = src
	CRASH("culture codec deliberate postapply failure")

/datum/unit_test/dq_culture_payload_ownership/registry/Run()
	var/datum/reagent/blood/B = allocate(/datum/reagent/blood)
	var/datum/state_context/ctx = allocate(/datum/state_context)
	var/datum/state_codec/reagents/codec = allocate(/datum/state_codec/reagents)
	var/datum/species/S = GLOB.all_species[SPECIES_HUMAN]
	TEST_ASSERT(S, "Actual registered human species exists")
	var/encoded = list("reagent_payload" = TRUE, "plain" = ctx.encode_value(list("donor" = S), "registry borrow"), "children" = list("viruses" = list()))
	var/datum/reagent_payload/P = codec.decode_payload(B, encoded, ctx)
	TEST_ASSERT_EQUAL(P.value["donor"], S, "Real registry wrapper decodes to borrowed singleton identity")
	qdel(P)
	TEST_ASSERT(!QDELETED(S) && GLOB.all_species[SPECIES_HUMAN] == S, "Payload deletion preserves registered singleton and its index")
	var/bad = list("viruses" = list(ctx.encode_value(S, "invalid virus registry")))
	var/caught = FALSE
	try
		var/datum/reagent_payload/unexpected = codec.decode_payload(B, bad, ctx)
		qdel(unexpected)
	catch(var/exception/fault)
		caught = !isnull(fault)
	TEST_ASSERT(caught, "Malformed virus registry child refuses ownership rather than adopting borrowed singleton")
	TEST_ASSERT(!QDELETED(S) && GLOB.all_species[SPECIES_HUMAN] == S, "Malformed decode preserves actual borrowed registry identity")

/datum/unit_test/dq_culture_payload_ownership/postapply_failure/Run()
	var/datum/reagent/blood/B = allocate(/datum/reagent/blood)
	var/datum/state_context/ctx = allocate(/datum/state_context)
	var/datum/state_codec/reagents/codec = allocate(/datum/state_codec/reagents)
	var/datum/affliction/contagion/dq_culture_decode_fault/source = allocate(/datum/affliction/contagion/dq_culture_decode_fault)
	var/old_failed = source.last_failed
	var/encoded = list("reagent_payload" = TRUE, "plain" = ctx.encode_value(list(), "fault plain"), "children" = list("viruses" = list(list(STATE_WRAP_OWNED = ctx.serialize_datum(source, NONE)))))
	var/caught = FALSE
	try
		var/datum/reagent_payload/unexpected = codec.decode_payload(B, encoded, ctx)
		qdel(unexpected)
	catch(var/exception/fault)
		caught = !isnull(fault)
	var/datum/failed = source.last_failed
	source.last_failed = old_failed
	TEST_ASSERT(caught, "Actual child postapply fault propagates through reagent decoder")
	TEST_ASSERT(failed && failed != source && QDELETED(failed), "Freshly allocated failing child is deleted before payload ownership could adopt it")
	TEST_ASSERT(!QDELETED(source), "Source contagion survives failed materialization")
