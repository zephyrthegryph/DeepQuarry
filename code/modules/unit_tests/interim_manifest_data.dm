/// A declared invisible manifest still produces its actual registered crew listing.
/datum/unit_test/interim_manifest_data/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/crew = allocate(/mob/living/carbon/human, T)
	crew.name = "Interim Manifest Crew"
	var/obj/effect/manifest/source = allocate(/obj/effect/manifest, T)
	TEST_ASSERT(!QDELETED(source), "actual manifest initializes alive")
	TEST_ASSERT_EQUAL(source.invisibility, INVISIBILITY_ABSTRACT, "actual manifest starts hidden")
	TEST_ASSERT_EQUAL(length(contents_of(T, /obj/item/paper)), 0, "actual fixture starts without manifest paper")
	TEST_ASSERT((crew in REGISTRY_MEMBERS(REGISTRY_MOBS)), "actual initialized crew is in the registry used by manifests")
	var/assignment = crew.get_assignment()
	TEST_ASSERT(assignment && length(assignment), "actual crew assignment is nonempty before checking paper contents")
	source.manifest()
	own_turf_contents(T)
	TEST_ASSERT(QDELETED(source), "actual manifest generation replaces its invisible source")
	var/list/papers = contents_of(T, /obj/item/paper)
	TEST_ASSERT_EQUAL(length(papers), 1, "actual generation creates exactly one paper")
	var/obj/item/paper/product = papers[1]
	TEST_ASSERT_EQUAL(product.loc, T, "actual manifest paper retains the original floor")
	TEST_ASSERT_EQUAL(product.name, "paper- 'Crew Manifest'", "actual product retains its manifest title")
	TEST_ASSERT(findtext(product.info, "Crew Manifest"), "actual paper contains its crew heading")
	TEST_ASSERT(findtext(product.info, crew.name), "actual paper lists the real registered crew member")
	TEST_ASSERT(findtext(product.info, assignment), "actual paper contains the real crew assignment")
	TEST_ASSERT(!QDELETED(crew), "actual manifest generation preserves its crew member")
