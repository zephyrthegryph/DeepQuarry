// Stored references (doc/rewrite/proposals/reference_storage.md): fixes found while converting the lists.

/// The medical console lists the records of GLOB.virusDB (virus id -> record); it once walked the keys as records and listed nothing.
/datum/unit_test/dq_refs_medical_lists_virus_records

/datum/unit_test/dq_refs_medical_lists_virus_records/Run()
	var/list/saved = GLOB.virusDB
	GLOB.virusDB = list()
	var/datum/data/record/rec = new
	rec.fields["name"] = "Test Plague"
	GLOB.virusDB["77"] = rec
	var/list/entries = medical_virus_entries()
	TEST_ASSERT_EQUAL(length(entries), 1, "the console lists the one discovered virus")
	TEST_ASSERT_EQUAL(entries[1]["name"], "Test Plague", "the entry carries the record's name")
	GLOB.virusDB = saved

/// The admin fax cache keeps the newest ADMIN_FAX_KEEP copies and deletes the older ones.
/datum/unit_test/dq_refs_admin_fax_cache_is_bounded

/datum/unit_test/dq_refs_admin_fax_cache_is_bounded/Run()
	test_driver_begin()
	var/list/saved = GLOB.adminfaxes
	GLOB.adminfaxes = list()
	var/obj/item/pen/first = new(null)
	admin_fax_keep(first)
	for(var/i in 1 to ADMIN_FAX_KEEP)
		admin_fax_keep(new /obj/item/pen(null))
	TEST_ASSERT_EQUAL(length(GLOB.adminfaxes), ADMIN_FAX_KEEP, "the cache holds no more than its limit")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(first), "the oldest copy was deleted when it fell out of the cache")
	QDEL_LIST(GLOB.adminfaxes)
	GLOB.adminfaxes = saved

/// A deleted fake sun leaves the family registry (it was a static list nothing removed from).
/datum/unit_test/dq_refs_fake_sun_leaves_registry

/datum/unit_test/dq_refs_fake_sun_leaves_registry/Run()
	var/obj/effect/fake_sun/sun = allocate(/obj/effect/fake_sun, run_loc_floor_bottom_left)
	TEST_ASSERT(sun in REGISTRY_MEMBERS(REGISTRY_FAKE_SUNS), "a fake sun joins the registry")
	qdel(sun)
	TEST_ASSERT(!(sun in REGISTRY_MEMBERS(REGISTRY_FAKE_SUNS)), "a deleted fake sun leaves the registry")

/// A player's preferences refuse an unforced delete (they persist for the round) and a forced one removes them.
/datum/unit_test/dq_refs_preferences_refuse_unforced_delete

/datum/unit_test/dq_refs_preferences_refuse_unforced_delete/Run()
	var/datum/preferences/dq_preview_test_stub/prefs = new()
	qdel(prefs)
	TEST_ASSERT(!QDELETED(prefs), "an unforced delete leaves the preferences whole")
	qdel(prefs, TRUE)
	TEST_ASSERT(QDELETED(prefs), "a forced delete removes them")

/// An op's earlier answers stay readable at its later steps: the op owns the answered prompts (the request layer no longer deletes one an op
/// adopted), so a handler after a wait reads the first question's fields, not a deleted prompt (and the op deletes them when it ends).
/obj/refs_two_step
	name = "two step fixture"
	anchored = TRUE
	var/seen_value
	var/list/seen_choices
	var/seen_second

CAPABILITIES(/obj/refs_two_step)
	op("two", ui_act("two"), asks(/datum/prompt/choice, fields = list("question" = "Which?", "choices" = list("a", "b"), "timeout" = 0), step = "first"), asks(/datum/prompt/text, fields = list("question" = "Why?", "timeout" = 0), step = "second"), then(PROC_REF(finish)))

/obj/refs_two_step/proc/finish(datum/act/op/A)
	var/datum/prompt/choice/first = A.step_answers?["first"]
	seen_value = first?.value
	seen_choices = first?.choices
	seen_second = A.step_value("second")
	return OP_OK

/datum/unit_test/dq_refs_two_step_op_reads_first_prompt_after_wait

/datum/unit_test/dq_refs_two_step_op_reads_first_prompt_after_wait/Run()
	test_driver_begin()
	test_prompts_reset()
	var/mob/living/simple_mob/e0_fixture/M = allocate(/mob/living/simple_mob/e0_fixture)
	var/obj/refs_two_step/C = allocate(/obj/refs_two_step)
	var/datum/op_result/waiting = test_ui(M, C, "two", list())
	TEST_ASSERT_NULL(waiting?.outcome, "the op waits on its first question")
	var/datum/prompt/choice/first_prompt = GLOB.test_prompts[1]
	var/datum/op_result/second = test_answer(M, "a")
	TEST_ASSERT_NULL(second?.outcome, "the op waits on its second question")
	TEST_ASSERT(!QDELETED(first_prompt), "the answered first prompt is kept for the op's later handlers")
	var/datum/op_result/done = test_answer(M, "because")
	TEST_ASSERT_EQUAL(done?.outcome, ACT_COMMITTED, "the op commits after the second answer")
	TEST_ASSERT_EQUAL(C.seen_value, "a", "the handler read the first answer after a later wait")
	TEST_ASSERT_EQUAL(length(C.seen_choices), 2, "and a field of the first prompt (its choices)")
	TEST_ASSERT_EQUAL(C.seen_second, "because", "and the second answer")
	test_time(1 SECOND)
	TEST_ASSERT(QDELETED(first_prompt), "the first prompt is deleted with the op, not kept for the round")
	GLOB.test_prompts = null
	test_driver_end()

/// Machinery and item references cleared by their declared relation: deleting the target leaves the holder's var null (a news post's channel,
/// a news photo's photo, a charge's target, a valve's attacher).
/datum/unit_test/dq_refs_machinery_item_refs_clear_on_delete

/datum/unit_test/dq_refs_machinery_item_refs_clear_on_delete/Run()
	var/datum/feed_channel/channel = new
	var/datum/feed_message/post = new
	rel_set(post, nameof(post.parent_channel), channel)
	TEST_ASSERT(post.parent_channel == channel, "the post names its channel")
	qdel(channel)
	TEST_ASSERT_NULL(post.parent_channel, "a deleted channel leaves no reference on its post")
	qdel(post)

	var/obj/item/photo/shot = allocate(/obj/item/photo, run_loc_floor_bottom_left)
	var/datum/news_photo/attachment = new(shot, FALSE)
	TEST_ASSERT(attachment.photo == shot, "the attachment names its photo")
	qdel(shot)
	TEST_ASSERT_NULL(attachment.photo, "a deleted photo leaves no reference on its news attachment")
	qdel(attachment)

	var/obj/item/plastique/charge = allocate(/obj/item/plastique, run_loc_floor_bottom_left)
	var/obj/item/pen/stuck_to = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	rel_set(charge, nameof(charge.target), stuck_to)
	TEST_ASSERT(charge.target == stuck_to, "the charge names what it is stuck to")
	qdel(stuck_to)
	TEST_ASSERT_NULL(charge.target, "a deleted target leaves no reference on the charge")

	var/obj/item/transfer_valve/valve = allocate(/obj/item/transfer_valve, run_loc_floor_bottom_left)
	var/mob/living/simple_mob/e0_fixture/who = allocate(/mob/living/simple_mob/e0_fixture)
	rel_set(valve, nameof(valve.attacher), who)
	TEST_ASSERT(valve.attacher == who, "the valve names who attached it")
	qdel(who)
	TEST_ASSERT_NULL(valve.attacher, "a deleted mob leaves no reference on the valve")

/// The uplink selections are boot singletons: an unforced delete leaves them whole (what lets the global hold one without a relation).
/datum/unit_test/dq_refs_uplink_selection_refuses_unforced_delete

/datum/unit_test/dq_refs_uplink_selection_refuses_unforced_delete/Run()
	var/datum/uplink_random_selection/selection = new
	qdel(selection)
	TEST_ASSERT(!QDELETED(selection), "an unforced delete leaves the selection whole")
	qdel(selection, TRUE)
	TEST_ASSERT(QDELETED(selection), "a forced delete removes it")

/// A portal leads to a turf or a landmark as well as an item: its destination is typed /atom, so a wormhole to a turf keeps its link (the
/// declared relation refused it while the var was typed /obj/item) and a deleted destination clears it.
/datum/unit_test/dq_refs_portal_leads_to_a_turf

/datum/unit_test/dq_refs_portal_leads_to_a_turf/Run()
	var/turf/here = run_loc_floor_bottom_left
	var/turf/there = get_step(here, EAST)
	var/obj/effect/portal/portal = allocate(/obj/effect/portal, here)
	rel_set(portal, nameof(portal.target), there)
	TEST_ASSERT_EQUAL(portal.target_ref(), there, "a portal's destination can be a turf")
	var/obj/item/pen/mark = allocate(/obj/item/pen, there)
	rel_set(portal, nameof(portal.target), mark)
	TEST_ASSERT_EQUAL(portal.target_ref(), mark, "or an object")
	qdel(mark)
	TEST_ASSERT_NULL(portal.target_ref(), "a deleted destination clears the portal's link")

/// An advanced pinpointer follows a person as well as an object (the DNA mode): its target is typed /atom and clears when the person is deleted.
/datum/unit_test/dq_refs_pinpointer_follows_a_person

/datum/unit_test/dq_refs_pinpointer_follows_a_person/Run()
	var/obj/item/pinpointer/advpinpointer/pointer = allocate(/obj/item/pinpointer/advpinpointer)
	var/mob/living/carbon/human/person = allocate(/mob/living/carbon/human)
	rel_set(pointer, nameof(pointer.target), person)
	TEST_ASSERT_EQUAL(pointer.target_ref(), person, "the pinpointer holds the person it follows")
	qdel(person)
	TEST_ASSERT_NULL(pointer.target_ref(), "deleting the person clears the pinpointer's target")

/// Removing an anomaly modifier undoes its effect on the anomaly it was added to; the removal does not bind the anomaly again (it used to write
/// the link where it should have left it), and the modifier's link clears when the anomaly is deleted.
/datum/unit_test/dq_refs_anomaly_modifier_removal_undoes_effect

/datum/unit_test/dq_refs_anomaly_modifier_removal_undoes_effect/Run()
	var/obj/effect/anomaly/anomaly = allocate(/obj/effect/anomaly)
	var/datum/anomaly_modifiers/move/modifier = new
	modifier.on_add(anomaly)
	TEST_ASSERT_EQUAL(modifier.attached_anomaly, anomaly, "the modifier binds to the anomaly it is added to")
	TEST_ASSERT_EQUAL(anomaly.move_chance, ANOMALY_MOVECHANCE, "and applies its effect")
	modifier.on_remove(anomaly)
	TEST_ASSERT_EQUAL(modifier.attached_anomaly, anomaly, "removal leaves the binding to the stats that delete the modifier")
	TEST_ASSERT_EQUAL(anomaly.move_chance, 0, "removal undoes the effect")
	qdel(anomaly)
	TEST_ASSERT_NULL(modifier.attached_anomaly, "deleting the anomaly clears the modifier's link")
	qdel(modifier)

/// An objective's target is a mind and nothing else: the heist objectives that name a type or a material keep it in their own vars, and a
/// deleted mind clears the objective's target.
/datum/unit_test/dq_refs_objective_target_is_a_mind

/datum/unit_test/dq_refs_objective_target_is_a_mind/Run()
	var/datum/objective/heist/loot/loot = new
	loot.choose_target()
	TEST_ASSERT(ispath(loot.loot_path, /obj), "the loot objective names the type to steal in its own var")
	TEST_ASSERT_NULL(loot.target, "and leaves the mind target empty")
	var/datum/objective/heist/salvage/salvage = new
	salvage.choose_target()
	TEST_ASSERT(istext(salvage.material_name), "the salvage objective names its material in its own var")
	TEST_ASSERT_NULL(salvage.target, "and leaves the mind target empty")
	var/datum/mind/victim = new("dq_refs_objective_target")
	rel_set(loot, nameof(loot.target), victim)
	TEST_ASSERT_EQUAL(loot.target, victim, "a mind can be the target")
	qdel(victim)
	TEST_ASSERT_NULL(loot.target, "a deleted mind clears the objective's target")
	qdel(loot)
	qdel(salvage)

/// A malfunction research ability owns the next one of its chain: it is built with it and deleted with it.
/datum/unit_test/dq_refs_malf_research_chain_is_owned

/datum/unit_test/dq_refs_malf_research_chain_is_owned/Run()
	var/datum/malf_research_ability/interdiction/recall_shuttle/root = new
	var/datum/malf_research_ability/second = root.next
	TEST_ASSERT(istype(second, /datum/malf_research_ability/interdiction/unlock_cyborg), "the first ability starts with the second of its tree")
	var/datum/malf_research_ability/third = second?.next
	TEST_ASSERT(istype(third, /datum/malf_research_ability/interdiction/hack_cyborg), "which starts with the third")
	qdel(root)
	TEST_ASSERT(QDELETED(second), "deleting the head of the chain deletes the next ability")
	TEST_ASSERT(QDELETED(third), "and the one after it")

/// A hydraulic clamp on any working exosuit (a hoverpod, not only a ripley) holds that chassis as its cargo holder.
/datum/unit_test/dq_refs_clamp_holds_a_working_chassis

/datum/unit_test/dq_refs_clamp_holds_a_working_chassis/Run()
	var/obj/mecha/working/hoverpod/pod = allocate(/obj/mecha/working/hoverpod)
	var/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp/clamp = allocate(/obj/item/mecha_parts/mecha_equipment/tool/hydraulic_clamp)
	clamp.attach(pod)
	TEST_ASSERT_EQUAL(clamp.cargo_holder(), pod, "the clamp's cargo holder is the hoverpod it is bolted to")
	qdel(pod)
	TEST_ASSERT_NULL(clamp.cargo_holder(), "deleting the chassis clears the clamp's cargo holder")

/// A keep = FALSE param that is a relation is dropped through the relation: the target's back-edge goes with it.
/obj/refs_param_probe
	name = "param probe"
	var/atom/movable/probe_link

CAPABILITIES(/obj/refs_param_probe)
	ref_one(nameof(probe_link), /atom/movable)
	param(nameof(probe_link), pos = 1, keep = FALSE)

/datum/unit_test/dq_refs_dropped_param_leaves_no_back_edge

/datum/unit_test/dq_refs_dropped_param_leaves_no_back_edge/Run()
	var/obj/item/pen/target = allocate(/obj/item/pen, run_loc_floor_bottom_left)
	var/obj/refs_param_probe/probe = allocate(/obj/refs_param_probe, run_loc_floor_bottom_left, target)
	TEST_ASSERT_NULL(probe.probe_link, "a keep = FALSE param is dropped when Initialize() returns")
	TEST_ASSERT(!rel_names(probe, nameof(probe.probe_link), target), "and the target's reverse index no longer names the holder")
