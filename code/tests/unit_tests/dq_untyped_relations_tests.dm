// The vars the `untyped` ratchet found holding an entity are typed and declared: a ref_one (cleared when its target is deleted) or a weak
// ref_one (a handle, read back by the generated accessor). Each family below points the var at a real target and deletes the target.

/// rel_set() points the declared one at `target`; deleting `target` clears it. Returns a problem text, or null.
/datum/unit_test/proc/untyped_ref_clears(datum/holder, var_name, datum/target)
	rel_set(holder, var_name, target)
	if(holder.vars[var_name] != target)
		return "[holder.type].[var_name] did not take [target.type]"
	qdel(target)
	if(!isnull(holder.vars[var_name]))
		return "[holder.type].[var_name] still names a deleted [target.type]"
	return null

/// A weak one holds a handle (text), the accessor reads the live target, and null once it is gone; the handle stays.
/datum/unit_test/proc/untyped_weak_reads(datum/holder, var_name, datum/target)
	rel_set(holder, var_name, target)
	if(!istext(holder.vars[var_name]))
		return "[holder.type].[var_name] holds no handle"
	if(call(holder, var_name)() != target)
		return "[holder.type].[var_name]() does not read the target"
	qdel(target)
	if(!isnull(call(holder, var_name)()))
		return "[holder.type].[var_name]() reads a deleted [target.type]"
	if(!istext(holder.vars[var_name]))
		return "[holder.type].[var_name] lost its handle when the target died"
	return null

/datum/unit_test/untyped_relations_turret_target

/datum/unit_test/untyped_relations_turret_target/Run()
	var/obj/machinery/porta_turret/turret = allocate(/obj/machinery/porta_turret)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/problem = untyped_ref_clears(turret, nameof(turret.last_target), victim)
	TEST_ASSERT(!problem, problem)

/datum/unit_test/untyped_relations_portal_creator

/datum/unit_test/untyped_relations_portal_creator/Run()
	var/obj/effect/portal/portal = allocate(/obj/effect/portal)
	var/obj/item/hand_tele/tele = allocate(/obj/item/hand_tele)
	var/problem = untyped_ref_clears(portal, nameof(portal.creator), tele)
	TEST_ASSERT(!problem, problem)

/datum/unit_test/untyped_relations_mimic_nest

/datum/unit_test/untyped_relations_mimic_nest/Run()
	var/obj/structure/closet/crate/mimic/crate = allocate(/obj/structure/closet/crate/mimic)
	var/obj/structure/mob_spawner/spawner = allocate(/obj/structure/mob_spawner)
	var/problem = untyped_ref_clears(crate, nameof(crate.nest), spawner)
	TEST_ASSERT(!problem, problem)

/datum/unit_test/untyped_relations_glamour_ring_owner

/datum/unit_test/untyped_relations_glamour_ring_owner/Run()
	var/obj/structure/glamour_ring/ring = allocate(/obj/structure/glamour_ring)
	var/mob/living/carbon/human/owner = allocate(/mob/living/carbon/human)
	var/problem = untyped_ref_clears(ring, nameof(ring.connected_mob), owner)
	TEST_ASSERT(!problem, problem)

/datum/unit_test/untyped_relations_vehicle_dummy_load

/datum/unit_test/untyped_relations_vehicle_dummy_load/Run()
	var/datum/vehicle_dummy_load/dummy = new
	var/obj/item/cargo = allocate(/obj/item/storage/toolbox)
	var/problem = untyped_ref_clears(dummy, nameof(dummy.actual_load), cargo)
	TEST_ASSERT(!problem, problem)
	qdel(dummy)

/datum/unit_test/untyped_relations_map_load_inputs

/datum/unit_test/untyped_relations_map_load_inputs/Run()
	var/datum/map_load/load = new
	var/datum/map_template/template = new
	var/problem = untyped_ref_clears(load, nameof(load.template), template)
	TEST_ASSERT(!problem, problem)
	var/datum/atom_init_job/job = new
	problem = untyped_ref_clears(load, nameof(load.init_job), job)
	TEST_ASSERT(!problem, problem)
	// A parsed map is kept unless forced: it is let go of by release(), not by deleting it.
	// release() lets go of what the finished load held, through the declared relation.
	rel_set(load, nameof(load.parsed), new /datum/parsed_map)
	rel_set(load, nameof(load.source), new /datum/parsed_map)
	load.release()
	TEST_ASSERT_NULL(load.parsed, "release() clears parsed")
	TEST_ASSERT_NULL(load.source, "release() clears source")
	TEST_ASSERT_NULL(load.init_job, "release() clears init_job")
	qdel(load)

/datum/unit_test/untyped_relations_remote_scene_tool_last_loc

/datum/unit_test/untyped_relations_remote_scene_tool_last_loc/Run()
	var/obj/item/remote_scene_tool/tool = allocate(/obj/item/remote_scene_tool)
	var/obj/item/holder = allocate(/obj/item/storage/toolbox)
	var/problem = untyped_ref_clears(tool, nameof(tool.last_loc), holder)
	TEST_ASSERT(!problem, problem)

/datum/unit_test/untyped_relations_power_sink_drain_loc

/datum/unit_test/untyped_relations_power_sink_drain_loc/Run()
	var/obj/item/rig_module/power_sink/sink = allocate(/obj/item/rig_module/power_sink)
	var/obj/item/place = allocate(/obj/item/storage/toolbox)
	var/problem = untyped_ref_clears(sink, nameof(sink.drain_loc), place)
	TEST_ASSERT(!problem, problem)

/datum/unit_test/untyped_relations_laserdome_pieces

/datum/unit_test/untyped_relations_laserdome_pieces/Run()
	var/obj/item/laserdome_flag/flag = allocate(/obj/item/laserdome_flag)
	var/obj/item/place = allocate(/obj/item/storage/toolbox)
	var/problem = untyped_ref_clears(flag, nameof(flag.start_pos), place)
	TEST_ASSERT(!problem, problem)
	var/obj/item/laserdome_hyperball/ball = allocate(/obj/item/laserdome_hyperball)
	var/obj/item/spot = allocate(/obj/item/storage/toolbox)
	problem = untyped_ref_clears(ball, nameof(ball.start_pos), spot)
	TEST_ASSERT(!problem, problem)
	var/mob/living/carbon/human/thrower = allocate(/mob/living/carbon/human)
	problem = untyped_ref_clears(ball, nameof(ball.last_holder), thrower)
	TEST_ASSERT(!problem, problem)

/datum/unit_test/untyped_relations_animated_blood_last_loc

/datum/unit_test/untyped_relations_animated_blood_last_loc/Run()
	var/obj/effect/decal/cleanable/blood/splatter/animated/blood = allocate(/obj/effect/decal/cleanable/blood/splatter/animated)
	var/obj/item/place = allocate(/obj/item/storage/toolbox)
	var/problem = untyped_ref_clears(blood, nameof(blood.loc_last_process), place)
	TEST_ASSERT(!problem, problem)

/datum/unit_test/untyped_relations_xenobio_loaded_item

/datum/unit_test/untyped_relations_xenobio_loaded_item/Run()
	var/obj/item/xenobio/launcher = allocate(/obj/item/xenobio)
	var/obj/item/loaded = allocate(/obj/item/storage/toolbox)
	var/problem = untyped_ref_clears(launcher, nameof(launcher.loaded_item), loaded)
	TEST_ASSERT(!problem, problem)

/// A hub's self-lock is a declared one: the portal's own deletion lets go of itself, and a locked destination that dies is forgotten.
/datum/unit_test/untyped_relations_dark_portal_lock

/datum/unit_test/untyped_relations_dark_portal_lock/Run()
	var/obj/structure/dark_portal/minion/portal = allocate(/obj/structure/dark_portal/minion)
	var/obj/structure/dark_portal/hub/hub = allocate(/obj/structure/dark_portal/hub)
	var/problem = untyped_ref_clears(portal, nameof(portal.locked), hub)
	TEST_ASSERT(!problem, problem)
	var/obj/structure/dark_portal/hub/closed = allocate(/obj/structure/dark_portal/hub)
	rel_set(closed, nameof(closed.locked), closed)
	TEST_ASSERT_EQUAL(closed.locked, closed, "a closed hub points at itself")
	qdel(closed)
	TEST_ASSERT_NULL(closed.locked, "the deleted hub no longer holds itself")

/// The basket's offhand grip: the basket names its grip, the grip names its basket, and dropping the basket ends the grip and clears both.
/datum/unit_test/untyped_relations_laundry_basket_grip

/datum/unit_test/untyped_relations_laundry_basket_grip/Run()
	var/obj/item/storage/laundry_basket/basket = allocate(/obj/item/storage/laundry_basket)
	var/obj/item/storage/laundry_basket/offhand/grip = allocate(/obj/item/storage/laundry_basket/offhand)
	var/mob/living/carbon/human/carrier = allocate(/mob/living/carbon/human)
	rel_set(grip, nameof(grip.linked), basket)
	rel_set(basket, nameof(basket.linked), grip)
	TEST_ASSERT_EQUAL(grip.linked, basket, "the grip names its basket")
	basket.dropped(carrier)
	TEST_ASSERT(QDELETED(grip), "dropping the basket ends the grip")
	TEST_ASSERT_NULL(basket.linked, "and the basket forgets it")

/// The weak ones: the var is a handle and the accessor reads the target only while it lives.
/datum/unit_test/untyped_relations_weak_handles

/datum/unit_test/untyped_relations_weak_handles/Run()
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human)
	var/obj/item/gun/launcher/crossbow/bow = allocate(/obj/item/gun/launcher/crossbow)
	var/problem = untyped_weak_reads(bow, nameof(bow.current_user), user)
	TEST_ASSERT(!problem, problem)
	var/mob/living/carbon/human/registrant = allocate(/mob/living/carbon/human)
	var/obj/item/toy/acorn_branch/branch = allocate(/obj/item/toy/acorn_branch)
	problem = untyped_weak_reads(branch, nameof(branch.registered_mob), registrant)
	TEST_ASSERT(!problem, problem)
	TEST_ASSERT_NULL(branch.registered_mob(), "a registrant who is gone leaves the branch free")
	var/obj/machinery/status_display/display = allocate(/obj/machinery/status_display)
	var/obj/item/source = allocate(/obj/item/storage/toolbox)
	problem = untyped_weak_reads(display, nameof(display.shuttle_key_token), source)
	TEST_ASSERT(!problem, problem)

/// A gone registrant frees the acorn branch: the next person registers and pulls an acorn.
/datum/unit_test/untyped_followup_acorn_branch_frees

/datum/unit_test/untyped_followup_acorn_branch_frees/Run()
	var/mob/living/carbon/human/first = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/second = allocate(/mob/living/carbon/human)
	var/obj/item/toy/acorn_branch/branch = allocate(/obj/item/toy/acorn_branch)
	rel_set(branch, nameof(branch.registered_mob), first)
	TEST_ASSERT_EQUAL(branch.registered_mob(), first, "the registrant is read back while they live")
	qdel(first)
	TEST_ASSERT_NULL(branch.registered_mob(), "the deleted registrant no longer resolves")
	var/datum/act/op/A = new
	A.actor = second
	branch.interaction_self(A)
	TEST_ASSERT_EQUAL(branch.registered_mob(), second, "the next person registers")
	qdel(A)

/// The death record keeps the attacker's name and key after the attacker is deleted.
/datum/unit_test/untyped_followup_lastattacker_record

/datum/unit_test/untyped_followup_lastattacker_record/Run()
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human)
	var/mob/living/carbon/human/attacker = allocate(/mob/living/carbon/human)
	attacker.set_real_name("Test Attacker")
	victim.note_attacker(attacker)
	var/list/live = victim.last_attacker_record()
	TEST_ASSERT_EQUAL(live[1], "Test Attacker", "a live attacker is recorded by name")
	qdel(attacker)
	TEST_ASSERT_NULL(victim.lastattacker(), "the handle no longer resolves")
	var/list/gone = victim.last_attacker_record()
	TEST_ASSERT_EQUAL(gone[1], "Test Attacker", "the name survives the attacker")

/// The laserdome ball keeps the thrower's name as text for its announcements.
/datum/unit_test/untyped_followup_laserdome_holder_name

/datum/unit_test/untyped_followup_laserdome_holder_name/Run()
	var/obj/item/laserdome_hyperball/ball = allocate(/obj/item/laserdome_hyperball)
	var/mob/living/carbon/human/thrower = allocate(/mob/living/carbon/human)
	var/expected = "[thrower]"
	rel_set(ball, nameof(ball.last_holder), thrower)
	ball.last_holder_name = "[thrower]"
	qdel(thrower)
	TEST_ASSERT_NULL(ball.last_holder, "the strong reference clears")
	TEST_ASSERT_EQUAL(ball.last_holder_name, expected, "the announcements still have a name")

/// Nar-Sie's target takes a mob through rel_set, a beacon for the plain singularity, and clears when the target is deleted.
/datum/unit_test/untyped_followup_narsie_target

/datum/unit_test/untyped_followup_narsie_target/Run()
	var/obj/singularity/narsie/narsie = allocate(/obj/singularity/narsie)
	var/mob/living/carbon/human/food = allocate(/mob/living/carbon/human)
	narsie.acquire(food)
	TEST_ASSERT_EQUAL(narsie.target, food, "Nar-Sie hunts the mob")
	qdel(food)
	TEST_ASSERT_NULL(narsie.target, "the deleted mob is no longer the target")
	var/obj/machinery/power/singularity_beacon/beacon = allocate(/obj/machinery/power/singularity_beacon)
	var/problem = untyped_ref_clears(narsie, nameof(narsie.target), beacon)
	TEST_ASSERT(!problem, problem)
