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
	// The one entry the target may keep is the harness's own: the unit test names everything it allocate()d through its `allocated` relation.
	var/stray_edges = 0
	for(var/index_key in target.om_refs_in)
		if(target.om_refs_in[index_key] != "allocated")
			stray_edges++
	TEST_ASSERT_EQUAL(stray_edges, 0, "and the target keeps no back-edge naming the holder")
	TEST_ASSERT(!rel_names(probe, nameof(probe.probe_link), target), "and the target's reverse index no longer names the holder")

/// A panel's host is a relation: deleting the mob clears it, and the panel stays whole until its window closes.
/datum/unit_test/dq_refs_panel_host_clears_when_mob_is_deleted

/datum/unit_test/dq_refs_panel_host_clears_when_mob_is_deleted/Run()
	var/mob/living/carbon/human/host = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/languages_panel/panel = new(host)
	TEST_ASSERT_EQUAL(panel.host, host, "the panel names its host")
	qdel(host)
	TEST_ASSERT_NULL(panel.host, "deleting the host clears the panel's host")
	qdel(panel)

/// A VR avatar and its body name each other (vr_holder / vr_link are one linked pair): writing one end sets the other, deleting either clears both.
/datum/unit_test/dq_refs_vr_pair_links_and_clears

/datum/unit_test/dq_refs_vr_pair_links_and_clears/Run()
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/avatar = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	rel_set(avatar, nameof(avatar.vr_holder), body)
	TEST_ASSERT_EQUAL(body.vr_link, avatar, "the body names the avatar once the avatar names the body")
	qdel(avatar)
	TEST_ASSERT_NULL(body.vr_link, "deleting the avatar clears the body's link")

/// A borg module's matter reserve is a relation: deleting the synth clears the decompiler's pointer to it.
/datum/unit_test/dq_refs_decompiler_synth_clears_when_deleted

/datum/unit_test/dq_refs_decompiler_synth_clears_when_deleted/Run()
	var/obj/item/matter_decompiler/decompiler = allocate(/obj/item/matter_decompiler)
	var/datum/matter_synth/metal/synth = new(1000)
	rel_set(decompiler, nameof(decompiler.metal), synth)
	TEST_ASSERT_EQUAL(decompiler.metal, synth, "the decompiler names the reserve")
	qdel(synth)
	TEST_ASSERT_NULL(decompiler.metal, "deleting the reserve clears the decompiler's pointer")

/// A xenomorph owns its six ability actions: they exist from init and go with it.
/datum/unit_test/dq_refs_xeno_owns_its_actions

/datum/unit_test/dq_refs_xeno_owns_its_actions/Run()
	var/mob/living/simple_mob/xeno_ch/xeno = allocate(/mob/living/simple_mob/xeno_ch, run_loc_floor_bottom_left)
	var/datum/action/innate/xeno_ch/xeno_build/build = xeno.build_action
	TEST_ASSERT(istype(build), "the build action exists from init")
	TEST_ASSERT(istype(xeno.spin_action), "so do the others")
	qdel(xeno)
	TEST_ASSERT(QDELETED(build), "deleting the xenomorph deletes its actions")

/// A malf hardware installs into its AI through the AI's owned `hardware` slot: the AI owns it, clearing the slot deletes it.
/datum/unit_test/dq_refs_malf_hardware_is_owned_by_its_ai

/datum/unit_test/dq_refs_malf_hardware_is_owned_by_its_ai/Run()
	var/mob/living/silicon/ai/AI = allocate(/mob/living/silicon/ai, run_loc_floor_bottom_left, null, null, null, TRUE)
	var/datum/malf_hardware/dual_cpu/hardware = new
	rel_set(hardware, nameof(hardware.owner), AI)
	hardware.install()
	TEST_ASSERT_EQUAL(AI.hardware, hardware, "install() puts the hardware in the AI's slot")
	TEST_ASSERT_EQUAL(hardware.owner_ref(), AI, "and the hardware names its AI")
	rel_clear(AI, nameof(AI.hardware))
	TEST_ASSERT(QDELETED(hardware), "clearing the slot deletes the hardware the AI owned")
	TEST_ASSERT_NULL(AI.hardware, "and the slot is empty")

/// A xenomorph's hotbar actions exist from creation (the mob owns them) and are deleted with it.
/datum/unit_test/dq_refs_xeno_actions_exist_from_creation

/datum/unit_test/dq_refs_xeno_actions_exist_from_creation/Run()
	var/mob/living/simple_mob/xeno_ch/hunter/hunter = allocate(/mob/living/simple_mob/xeno_ch/hunter, run_loc_floor_bottom_left)
	TEST_ASSERT_NOTNULL(hunter.build_action, "the build action exists once the mob exists")
	TEST_ASSERT_NOTNULL(hunter.pounce_action, "and so does the hunter's pounce action")
	hunter.pounce_action.Grant(hunter)
	TEST_ASSERT_EQUAL(hunter.pounce_action.parent_xeno, hunter, "granting binds the action to its xeno")
	var/datum/action/innate/xeno_ch/xeno_pounce/pounce = hunter.pounce_action
	qdel(hunter)
	TEST_ASSERT(QDELETED(pounce), "the actions are deleted with the mob that owns them")

/// Storing a mind in a sleevemate leaves the mind with no current body: clearing the link goes through the relation, not a raw write.
/datum/unit_test/dq_refs_mind_current_clears_through_the_relation

/datum/unit_test/dq_refs_mind_current_clears_through_the_relation/Run()
	var/mob/living/carbon/human/body = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/mind/mind = new("refs_test")
	rel_set(mind, nameof(mind.current), body)
	TEST_ASSERT_EQUAL(mind.current, body, "the mind's current body is set")
	rel_clear(mind, nameof(/datum/mind::current))
	TEST_ASSERT_NULL(mind.current, "rel_clear leaves the mind with no current body")
	TEST_ASSERT(!rel_names(mind, nameof(mind.current), body), "and the body's reverse index no longer names the mind")
	qdel(mind)

/// w6a2: a board game's seated player is a declared relation: deleting the player clears the seat instead of keeping the mob alive.
/datum/unit_test/dq_refs_w6a2_board_game_player_clears_on_delete

/datum/unit_test/dq_refs_w6a2_board_game_player_clears_on_delete/Run()
	var/mob/living/carbon/human/one = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/structure/casino_table/board_game/checkers/table = allocate(/obj/structure/casino_table/board_game/checkers, run_loc_floor_bottom_left)
	var/datum/board_game/checkers/game = table.game_ui
	TEST_ASSERT(istype(game), "the checkers table holds a checkers game")
	rel_set(game, nameof(game.player_one), one)
	TEST_ASSERT_EQUAL(game.player_one, one, "the player takes the seat")
	TEST_ASSERT_EQUAL(game.parent, table, "the game names its table")
	qdel(one, TRUE)
	TEST_ASSERT_NULL(game.player_one, "deleting the player clears the seat")

/// w6a3: a contract's funding account is a declared relation: deleting the account clears the field instead of keeping it alive.
/datum/unit_test/dq_refs_w6a3_contract_funding_account_clears_on_delete

/datum/unit_test/dq_refs_w6a3_contract_funding_account_clears_on_delete/Run()
	var/datum/money_account/funder = new
	var/datum/contract/contract = new
	rel_set(contract, nameof(contract.funding_account), funder)
	TEST_ASSERT_EQUAL(contract.funding_account, funder, "the contract names its funding account")
	qdel(funder, TRUE)
	TEST_ASSERT_NULL(contract.funding_account, "deleting the account clears the contract's field")
	qdel(contract, TRUE)

/// w6a3: an EFTPOS scanner's linked account is a declared relation: deleting the account unlinks it.
/datum/unit_test/dq_refs_w6a3_eftpos_linked_account_clears_on_delete

/datum/unit_test/dq_refs_w6a3_eftpos_linked_account_clears_on_delete/Run()
	var/obj/item/eftpos/scanner = allocate(/obj/item/eftpos, run_loc_floor_bottom_left)
	var/datum/money_account/account = new
	rel_set(scanner, nameof(scanner.linked_account), account)
	TEST_ASSERT_EQUAL(scanner.linked_account, account, "the scanner links the account")
	qdel(account, TRUE)
	TEST_ASSERT_NULL(scanner.linked_account, "deleting the account unlinks the scanner")
	own_turf_contents(run_loc_floor_bottom_left) // the account's setup left a receipt and its parcel on the block: the test owns them

/// W6B: a genetic side effect names the human suffering it as a relation: deleting the human clears the pointer.
/datum/unit_test/dq_refs_w6b_side_effect_host_clears_when_deleted

/datum/unit_test/dq_refs_w6b_side_effect_host_clears_when_deleted/Run()
	var/mob/living/carbon/human/host = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/genetics/side_effect/effect = new
	rel_set(effect, nameof(effect.host), host)
	TEST_ASSERT_EQUAL(effect.host, host, "the side effect names its host")
	qdel(host)
	TEST_ASSERT_NULL(effect.host, "deleting the host clears the side effect's pointer")
	qdel(effect)

/// W6B: a book's barcode scanner names its associated computer as a relation.
/datum/unit_test/dq_refs_w6b_barcode_scanner_book_clears_when_deleted

/datum/unit_test/dq_refs_w6b_barcode_scanner_book_clears_when_deleted/Run()
	var/obj/item/barcodescanner/scanner = allocate(/obj/item/barcodescanner)
	var/obj/item/book/book = allocate(/obj/item/book)
	rel_set(scanner, nameof(scanner.book), book)
	TEST_ASSERT_EQUAL(scanner.book, book, "the scanner names the scanned book")
	qdel(book)
	TEST_ASSERT_NULL(scanner.book, "deleting the book clears the scanner's pointer")

/// w6a4: the retail scanner names its linked account as a relation: deleting the account clears the link.
/datum/unit_test/dq_refs_w6a4_retail_scanner_account_clears_on_delete

/datum/unit_test/dq_refs_w6a4_retail_scanner_account_clears_on_delete/Run()
	var/obj/item/retail_scanner/scanner = allocate(/obj/item/retail_scanner, run_loc_floor_bottom_left)
	var/datum/money_account/account = new
	rel_set(scanner, nameof(scanner.linked_account), account)
	TEST_ASSERT_EQUAL(scanner.linked_account, account, "the scanner links the account")
	qdel(account, TRUE)
	TEST_ASSERT_NULL(scanner.linked_account, "deleting the account unlinks the scanner")

/// w6a4: a flight port names the vessel occupying it as a relation: deleting the vessel frees the berth.
/datum/unit_test/dq_refs_w6a4_flight_port_occupant_clears_on_delete

/datum/unit_test/dq_refs_w6a4_flight_port_occupant_clears_on_delete/Run()
	var/datum/flight_port/port = new
	var/datum/flight_vessel/vessel = new
	rel_set(port, nameof(port.occupied_by), vessel)
	TEST_ASSERT_EQUAL(port.occupied_by, vessel, "the port names its occupant")
	qdel(vessel, TRUE)
	TEST_ASSERT_NULL(port.occupied_by, "deleting the vessel clears the berth")
	qdel(port, TRUE)

/// w6a1: a telecube's mate clears when the other cube is deleted.
/datum/unit_test/dq_refs_w6a1_telecube_mate_clears_on_delete

/datum/unit_test/dq_refs_w6a1_telecube_mate_clears_on_delete/Run()
	var/obj/item/telecube/a = allocate(/obj/item/telecube, run_loc_floor_bottom_left)
	var/obj/item/telecube/c = allocate(/obj/item/telecube, run_loc_floor_bottom_left)
	rel_set(a, nameof(a.mate), c)
	TEST_ASSERT_EQUAL(a.mate, c, "the cube names its mate")
	qdel(c, TRUE)
	TEST_ASSERT_NULL(a.mate, "deleting the mate clears the pointer")

/// w6a1: an affliction's owner and location clear when they are deleted.
/datum/unit_test/dq_refs_w6a1_affliction_owner_location_clear_on_delete

/datum/unit_test/dq_refs_w6a1_affliction_owner_location_clear_on_delete/Run()
	var/datum/affliction/aff = new
	var/mob/living/carbon/human/owner = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/obj/item/organ/part = allocate(/obj/item/organ, run_loc_floor_bottom_left)
	rel_set(aff, nameof(aff.owner), owner)
	rel_set(aff, nameof(aff.location), part)
	qdel(part, TRUE)
	TEST_ASSERT_NULL(aff.location, "deleting the part clears the location")
	qdel(owner, TRUE)
	TEST_ASSERT_NULL(aff.owner, "deleting the owner clears the owner")
	qdel(aff, TRUE)

/// w6a1: the belly overlay panel survives its mob being deleted first (owner() reads null, on_destroy does not runtime).
/datum/unit_test/dq_refs_w6a1_belly_overlay_owner_deleted_first

/datum/unit_test/dq_refs_w6a1_belly_overlay_owner_deleted_first/Run()
	var/mob/living/carbon/human/owner = allocate(/mob/living/carbon/human, run_loc_floor_bottom_left)
	var/datum/belly_overlay_tgui/panel = new /datum/belly_overlay_tgui(owner)
	TEST_ASSERT_EQUAL(panel.owner(), owner, "the panel names its mob")
	qdel(owner, TRUE)
	TEST_ASSERT_NULL(panel.owner(), "deleting the mob clears the panel's owner")
	qdel(panel, TRUE)

/// w6a1: the admin PM prompt names its ticket as a relation: deleting the ticket clears it (a real ticket needs a client, so the test sets the field the way open_request does).
/datum/unit_test/dq_refs_w6a1_adminpm_ticket_clears_on_delete

/// A ticket that skips the constructor (the real one deletes itself without a client).
/datum/ticket/dq_refs_w6a1_fixture

/datum/ticket/dq_refs_w6a1_fixture/New()
	return

/datum/unit_test/dq_refs_w6a1_adminpm_ticket_clears_on_delete/Run()
	var/datum/ticket/stand_in = new /datum/ticket/dq_refs_w6a1_fixture
	var/datum/prompt/text/admin_pm/asked = new
	rel_set(asked, nameof(asked.ticket), stand_in)
	TEST_ASSERT_EQUAL(asked.ticket, stand_in, "the prompt names its ticket")
	qdel(stand_in, TRUE)
	TEST_ASSERT_NULL(asked.ticket, "deleting the ticket clears the prompt's pointer")
	qdel(asked, TRUE)

/// w6a1: reopening the whitelist editor (an owned var on the admin holder) disposes of the previous editor.
/datum/unit_test/dq_refs_w6a1_whitelist_editor_reopen_disposes_old

/datum/unit_test/dq_refs_w6a1_whitelist_editor_reopen_disposes_old/Run()
	var/fixture_key = "dq_refs_w6a1_wl"
	set_global("admin_datums", GLOB.admin_datums.Copy())
	set_global("deadmins", GLOB.deadmins.Copy())
	var/datum/admins/holder = allocate(/datum/admins, list(), fixture_key)
	GLOB.admin_datums -= fixture_key
	var/datum/whitelist_editor/first = new
	rel_set(holder, nameof(/datum/admins::whitelist_editor), first)
	TEST_ASSERT_EQUAL(holder.whitelist_editor, first, "the holder names its editor")
	var/datum/whitelist_editor/second = new
	rel_set(holder, nameof(/datum/admins::whitelist_editor), second)
	TEST_ASSERT(QDELETED(first), "the replaced editor is disposed of")
	TEST_ASSERT_EQUAL(holder.whitelist_editor, second, "the holder names the new editor")

/// w6a4: a prompt field a relation declares is written through the relation: deleting the target clears the prompt's field.
/datum/unit_test/dq_refs_w6a4_open_request_relation_field_clears_on_delete

/datum/unit_test/dq_refs_w6a4_open_request_relation_field_clears_on_delete/Run()
	var/datum/exported_crate/record = new
	var/datum/prompt/yes_no/supply_delete_record/asked = open_request(src, /datum/prompt/yes_no/supply_delete_record, null, timeout = 0, record = record)
	TEST_ASSERT_NOTNULL(asked, "the prompt opened")
	TEST_ASSERT_EQUAL(asked.record, record, "the prompt names the record")
	qdel(record, TRUE)
	TEST_ASSERT_NULL(asked.record, "deleting the record clears the prompt's field")
	qdel(asked, TRUE)

/// w6a4: the emergency shuttle system names its shuttle through its own relation.
/datum/unit_test/dq_refs_w6a4_emergency_shuttle_relation_declared

/datum/unit_test/dq_refs_w6a4_emergency_shuttle_relation_declared/Run()
	var/datum/shuttle/autodock/ferry/emergency/w6a4_stub/stub = new
	var/datum/shuttle/autodock/ferry/emergency/prior = SSemergency_shuttle.vars["shuttle"]
	rel_clear(SSemergency_shuttle, "shuttle")
	rel_set(SSemergency_shuttle, nameof(/datum/system/emergency_shuttle::shuttle), stub)
	TEST_ASSERT_EQUAL(SSemergency_shuttle.vars["shuttle"], stub, "the system names the shuttle it was given")
	qdel(stub, TRUE)
	TEST_ASSERT_NULL(SSemergency_shuttle.vars["shuttle"], "deleting the shuttle clears the system's field")
	if(prior && !QDELETED(prior))
		rel_set(SSemergency_shuttle, "shuttle", prior)

/// A bare emergency shuttle for the relation test: the real constructor registers radio, landmarks and the shuttle registry.
/datum/shuttle/autodock/ferry/emergency/w6a4_stub
	defer_initialisation = TRUE
	shuttle_area = /area

/datum/shuttle/autodock/ferry/emergency/w6a4_stub/New()
	return

/// w6a2: a declared keep = FALSE param is dropped through its relation after init, so the target keeps no back-edge to the holder.
/datum/unit_test/dq_refs_w6a2_dropped_param_leaves_no_back_edge

/datum/unit_test/dq_refs_w6a2_dropped_param_leaves_no_back_edge/Run()
	var/obj/item/mmi/brain_box = allocate(/obj/item/mmi, run_loc_floor_bottom_left)
	var/obj/item/organ/internal/mmi_holder/holder = allocate(/obj/item/organ/internal/mmi_holder, run_loc_floor_bottom_left, TRUE, brain_box)
	TEST_ASSERT_NULL(holder.installed_mmi, "the constructor param is dropped when init returns")
	TEST_ASSERT(!rel_names(holder, nameof(holder.installed_mmi), brain_box), "and the target's reverse index no longer names the holder")

/// w6a2: the locket owns its keepsake, and opening it hands the paper over to the floor alive instead of disposing of it.
/datum/unit_test/dq_refs_w6a2_locket_open_hands_keepsake_over

/datum/unit_test/dq_refs_w6a2_locket_open_hands_keepsake_over/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human, T)
	var/obj/item/clothing/accessory/locket/locket = allocate(/obj/item/clothing/accessory/locket, T)
	locket.open = TRUE
	var/obj/item/paper/paper = allocate(/obj/item/paper, T)
	TEST_ASSERT(user.put_in_inactive_hand(paper), "the keepsake is in hand")
	test_op_handler(locket, "locket_insert_item", user, paper)
	TEST_ASSERT_EQUAL(locket.held(), paper, "the locket holds the paper")
	var/obj/item/taken = rel_take(locket, nameof(locket.held)) // what opening the locket does to the keepsake
	TEST_ASSERT_EQUAL(taken, paper, "taking the keepsake hands back the paper")
	TEST_ASSERT(!QDELETED(paper), "taking the keepsake does not dispose of it")
	TEST_ASSERT_NULL(locket.held(), "and the locket no longer holds it")

/// w6a2: the same holds for a stump built from the limb it replaces.
/datum/unit_test/dq_refs_w6a2_stump_param_leaves_no_back_edge

/datum/unit_test/dq_refs_w6a2_stump_param_leaves_no_back_edge/Run()
	var/obj/item/organ/external/limb = allocate(/obj/item/organ/external/arm, run_loc_floor_bottom_left)
	var/obj/item/organ/external/stump/stump = allocate(/obj/item/organ/external/stump, run_loc_floor_bottom_left, null, limb)
	TEST_ASSERT_NULL(stump.stump_of, "the limb param is dropped when init returns")
	TEST_ASSERT(!rel_names(stump, nameof(stump.stump_of), limb), "and the limb's reverse index no longer names the stump")
