/datum/unit_test/interim_native_reference_lifetime/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/item/gun/energy/gun = allocate(/obj/item/gun/energy, T)
	var/obj/item/cell/device/borrowed = allocate(/obj/item/cell/device, T)
	var/obj/item/cell/device/independent_cell = allocate(/obj/item/cell/device, T)
	TEST_ASSERT_NOTNULL(gun.get_cell(), "the actual energy gun initially has its constructed internal cell")
	own(gun.get_cell())
	var/datum/borrowed_owner = owner_of(borrowed)
	TEST_ASSERT_NOTEQUAL(borrowed_owner, gun, "the external floor cell is not initially owned by the gun")
	rel_set(gun, nameof(gun.power_supply), borrowed)
	TEST_ASSERT_EQUAL(gun.get_cell(), borrowed, "the production energy gun getter resolves the exact borrowed cell")
	TEST_ASSERT_EQUAL(borrowed.loc, T, "setting the reference does not move the external cell into the gun")
	TEST_ASSERT_EQUAL(owner_of(borrowed), borrowed_owner, "the gun reference preserves the external cell's original owner stamp")
	qdel(gun)
	TEST_ASSERT(QDELETED(gun), "the actual gun has completed teardown")
	TEST_ASSERT(!QDELETED(borrowed), "gun teardown preserves the referenced external cell")
	TEST_ASSERT_EQUAL(borrowed.loc, T, "gun teardown leaves the borrowed cell on its original floor")
	TEST_ASSERT_EQUAL(owner_of(borrowed), borrowed_owner, "gun teardown preserves the borrowed cell's original owner stamp")
	TEST_ASSERT(!QDELETED(independent_cell), "the independent original cell also survives gun teardown")

	var/mob/living/simple_mob/animal = allocate(/mob/living/simple_mob, T)
	var/mob/living/carbon/human/tamer = allocate(/mob/living/carbon/human, T)
	var/mob/living/carbon/human/independent_tamer = allocate(/mob/living/carbon/human, T)
	var/datum/tamer_owner = owner_of(tamer)
	var/datum/independent_tamer_owner = owner_of(independent_tamer)
	TEST_ASSERT_NOTEQUAL(tamer_owner, animal, "the first human is not initially owned by the animal")
	TEST_ASSERT_NOTEQUAL(independent_tamer_owner, animal, "the independent human is not initially owned by the animal")
	rel_add(animal, nameof(animal.tamers), tamer)
	rel_add(animal, nameof(animal.tamers), independent_tamer)
	TEST_ASSERT_EQUAL(length(animal.tamers), 2, "the real animal reference list contains both distinct original tamers")
	TEST_ASSERT((tamer in animal.tamers) && (independent_tamer in animal.tamers), "both exact original tamer identities are linked before deletion")
	TEST_ASSERT_EQUAL(owner_of(tamer), tamer_owner, "linking the first tamer preserves its original owner stamp")
	TEST_ASSERT_EQUAL(owner_of(independent_tamer), independent_tamer_owner, "linking the independent tamer preserves its original owner stamp")
	qdel(tamer)
	TEST_ASSERT(QDELETED(tamer), "the original first tamer is actually deleted")
	TEST_ASSERT_EQUAL(length(animal.tamers), 1, "deleting one tamer removes exactly its real reference list entry")
	TEST_ASSERT(!(tamer in animal.tamers), "the deleted original no longer appears in the production tamers list")
	TEST_ASSERT(independent_tamer in animal.tamers, "the independent original remains linked")
	TEST_ASSERT(!QDELETED(independent_tamer) && !QDELETED(animal), "reference cleanup preserves the independent tamer and animal")
	qdel(animal)
	TEST_ASSERT(!QDELETED(independent_tamer), "animal teardown does not dispose of its remaining referenced tamer")
	TEST_ASSERT_EQUAL(owner_of(independent_tamer), independent_tamer_owner, "animal teardown preserves the surviving human's original owner stamp")

/datum/unit_test/interim_native_contract_pair_lifetime/Run()
	var/datum/contract/parent = allocate(/datum/contract)
	var/datum/contract/child = allocate(/datum/contract)
	var/datum/contract/sibling = allocate(/datum/contract)
	var/datum/child_owner = owner_of(child)
	var/datum/sibling_owner = owner_of(sibling)
	TEST_ASSERT(parent.add_child(child), "the production contract accepts its original first child")
	TEST_ASSERT(parent.add_child(sibling), "the production contract accepts a distinct sibling")
	TEST_ASSERT_EQUAL(child.parent, parent, "the actual first child's back reference names the original parent")
	TEST_ASSERT_EQUAL(sibling.parent, parent, "the actual sibling's back reference names the original parent")
	TEST_ASSERT_EQUAL(length(parent.children), 2, "the reciprocal parent list contains exactly two children")
	TEST_ASSERT((child in parent.children) && (sibling in parent.children), "the reciprocal list contains both original child identities")
	TEST_ASSERT_EQUAL(owner_of(child), child_owner, "the first child keeps its original ownership")
	TEST_ASSERT_EQUAL(owner_of(sibling), sibling_owner, "the sibling keeps its original ownership")
	qdel(child)
	TEST_ASSERT(QDELETED(child), "the first child actually completes teardown")
	TEST_ASSERT_EQUAL(length(parent.children), 1, "child deletion clears exactly one reciprocal entry")
	TEST_ASSERT(sibling in parent.children, "the original sibling remains in the parent's list")
	TEST_ASSERT_EQUAL(sibling.parent, parent, "the surviving sibling keeps its parent reference")
	qdel(parent)
	TEST_ASSERT(QDELETED(parent), "the parent actually completes teardown")
	TEST_ASSERT(!QDELETED(sibling), "parent teardown preserves its referenced sibling")
	TEST_ASSERT_NULL(sibling.parent, "parent teardown clears the surviving child's back reference")
	TEST_ASSERT_EQUAL(owner_of(sibling), sibling_owner, "parent teardown preserves the sibling's original ownership")

// Unique keys isolate inherited production keyed declarations from map fixtures.
/obj/effect/step_trigger/autostrip/interim_native_keyed_fixture
	targetid = "interim-native-autostrip-keyed-lifetime"

/obj/effect/autostriptarget/interim_native_keyed_fixture
	targetid = "interim-native-autostrip-keyed-lifetime"

/obj/effect/autostriptarget/mob/interim_native_keyed_fixture
	targetid = "interim-native-autostrip-keyed-lifetime"

/datum/unit_test/interim_native_autostrip_keyed_lifetime/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/obj/effect/step_trigger/autostrip/early = allocate(/obj/effect/step_trigger/autostrip/interim_native_keyed_fixture, T)
	TEST_ASSERT_NULL(early.target_ref(), "source materialized first has no ordinary keyed target")
	TEST_ASSERT_NULL(early.Mtarget(), "source materialized first has no mob keyed target")
	var/obj/effect/autostriptarget/first = allocate(/obj/effect/autostriptarget/interim_native_keyed_fixture, T)
	TEST_ASSERT_EQUAL(early.target_ref(), first, "late ordinary target binds the exact original identity")
	TEST_ASSERT_NULL(early.Mtarget(), "ordinary target does not satisfy the mob-subtype keyed reference")
	var/obj/effect/autostriptarget/mob/mob_target = allocate(/obj/effect/autostriptarget/mob/interim_native_keyed_fixture, T)
	TEST_ASSERT_EQUAL(early.target_ref(), first, "adding a mob target preserves the already-bound ordinary identity")
	TEST_ASSERT_EQUAL(early.Mtarget(), mob_target, "late mob target binds the exact subtype identity")
	var/obj/effect/step_trigger/autostrip/late = allocate(/obj/effect/step_trigger/autostrip/interim_native_keyed_fixture, T)
	TEST_ASSERT_EQUAL(late.target_ref(), first, "source materialized after targets finds the original ordinary identity")
	TEST_ASSERT_EQUAL(late.Mtarget(), mob_target, "source materialized after targets finds the original mob identity")
	qdel(first)
	TEST_ASSERT(QDELETED(first), "ordinary target actually completes teardown")
	TEST_ASSERT_NULL(early.target_ref(), "ordinary target deletion clears the earlier source")
	TEST_ASSERT_NULL(late.target_ref(), "ordinary target deletion clears the later source")
	TEST_ASSERT_EQUAL(early.Mtarget(), mob_target, "ordinary target deletion preserves the independent mob reference")
	var/obj/effect/autostriptarget/replacement = allocate(/obj/effect/autostriptarget/interim_native_keyed_fixture, T)
	TEST_ASSERT_EQUAL(early.target_ref(), replacement, "replacement target rebinds the earlier source to its exact new identity")
	TEST_ASSERT_EQUAL(late.target_ref(), replacement, "replacement target rebinds the later source to its exact new identity")
	qdel(mob_target)
	TEST_ASSERT(QDELETED(mob_target), "mob target actually completes teardown")
	TEST_ASSERT_NULL(early.Mtarget(), "mob target deletion clears the earlier subtype reference")
	TEST_ASSERT_NULL(late.Mtarget(), "mob target deletion clears the later subtype reference")
	TEST_ASSERT_EQUAL(early.target_ref(), replacement, "mob target deletion preserves the replacement ordinary reference")
	qdel(early)
	TEST_ASSERT(!QDELETED(replacement), "source teardown preserves the independently materialized target")
	TEST_ASSERT_EQUAL(late.target_ref(), replacement, "one source teardown preserves the other source's target")

/datum/interim_ability_argument_observer
	var/calls = 0
	var/list/first_arguments
	var/list/latest_arguments
	var/prior_call_marker

/datum/interim_ability_argument_observer/proc/observe(list/arguments)
	calls++
	if(calls == 1)
		first_arguments = arguments
	latest_arguments = arguments
	if(arguments)
		prior_call_marker = arguments["callback_calls"]
		arguments["callback_calls"] = calls

/datum/unit_test/interim_ability_callback_arguments/Run()
	var/datum/interim_ability_argument_observer/default_observer = allocate(/datum/interim_ability_argument_observer)
	var/atom/movable/screen/ability/verb_based/default_ability = allocate(/atom/movable/screen/ability/verb_based)
	default_ability.object_used = default_observer
	default_ability.verb_to_call = TYPE_PROC_REF(/datum/interim_ability_argument_observer, observe)
	default_ability.activate()
	TEST_ASSERT_EQUAL(default_observer.calls, 1, "the production ability dispatches its configured callback")
	TEST_ASSERT_NOTNULL(default_observer.first_arguments, "the actual callback receives the allocated default argument list")
	TEST_ASSERT_EQUAL(default_ability.arguments_to_use, default_observer.first_arguments, "the callback receives the exact stored default list")
	default_ability.activate()
	TEST_ASSERT_EQUAL(default_observer.calls, 2, "the second production activation dispatches the callback again")
	TEST_ASSERT_EQUAL(default_observer.latest_arguments, default_observer.first_arguments, "both callbacks receive the same original default list")
	TEST_ASSERT_EQUAL(default_observer.prior_call_marker, 1, "the second callback sees the first callback's mutation")
	TEST_ASSERT_EQUAL(default_observer.latest_arguments["callback_calls"], 2, "the second callback updates that same mutable list")

	var/datum/interim_ability_argument_observer/supplied_observer = allocate(/datum/interim_ability_argument_observer)
	var/atom/movable/screen/ability/verb_based/supplied_ability = allocate(/atom/movable/screen/ability/verb_based)
	var/list/supplied_arguments = list("callback_calls" = 7)
	supplied_ability.object_used = supplied_observer
	supplied_ability.verb_to_call = TYPE_PROC_REF(/datum/interim_ability_argument_observer, observe)
	supplied_ability.arguments_to_use = supplied_arguments
	supplied_ability.activate()
	TEST_ASSERT_EQUAL(supplied_observer.calls, 1, "the supplied-argument ability invokes its actual callback")
	TEST_ASSERT_EQUAL(supplied_observer.first_arguments, supplied_arguments, "the callback receives the original caller-supplied list without copying")
	TEST_ASSERT_EQUAL(supplied_ability.arguments_to_use, supplied_arguments, "activation retains the original caller-supplied identity")
	TEST_ASSERT_EQUAL(supplied_observer.prior_call_marker, 7, "the callback reads the original supplied contents")
	TEST_ASSERT_EQUAL(supplied_arguments["callback_calls"], 1, "the callback mutation reaches the original supplied list")
