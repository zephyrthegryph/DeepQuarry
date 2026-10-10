// The foundation forms of the lifecycle declarations (G4), the look library without layer/behind args (G12)
// and coalesced UI pushes with ui_rights (G14): doc/rewrite/lifecycle.md "Starting state",
// doc/rewrite/look.md, doc/rewrite/operations_and_actions.md "UI".

#define REGISTRY_DQ_FORMS_PLAIN "dq_forms_plain"
#define REGISTRY_DQ_FORMS_COND "dq_forms_cond"
REGISTRY_DECLARE(dq_forms_plain, REGISTRY_DQ_FORMS_PLAIN)
REGISTRY_DECLARE_CONDITIONAL(dq_forms_cond, REGISTRY_DQ_FORMS_COND)

// ---- fixtures ----

/obj/item/dq_forms_part
	name = "forms part"

/obj/item/dq_forms_part/better
	name = "better forms part"

/// A relation's starting occupant (rel_one / rel_many with starts =).
/obj/item/dq_forms_holder
	name = "forms holder"
	var/obj/item/dq_forms_part/part
	var/part_type = /obj/item/dq_forms_part
	var/list/spares

/obj/item/dq_forms_holder/relations()
	. = ..()
	. += rel_one(nameof(part), /obj/item/dq_forms_part, kind = RELK_OWNED, policy = OWN_SPILL, starts = nameof(part_type))
	. += rel_many(nameof(spares), /obj/item/dq_forms_part, kind = RELK_OWNED, starts = list(/obj/item/dq_forms_part = 2))

/// A subtype (or a map edit) of the type var picks the occupant.
/obj/item/dq_forms_holder/better
	part_type = /obj/item/dq_forms_part/better

/// No type in the var: nothing starts there.
/obj/item/dq_forms_holder/empty
	part_type = null

/// A test APC that starts no cell and keeps out of its area's power and network (no terminal, no area registration), so a test
/// can allocate one anywhere and take it back whole.
/obj/machinery/power/apc/dx_test
	cell_type = null

/obj/machinery/power/apc/dx_test/init()
	return

/// An APC whose relation starts a high-capacity cell (starts = nameof(cell_type)).
/obj/machinery/power/apc/dx_test/cell_start
	cell_type = /obj/item/cell/high

/// reagents() + configure(reagents(add = | starts = | volume =)) + without(CAP_REAGENTS) (code/library/reagents/reagents.dm).
/obj/item/dq_forms_flask
	name = "forms flask"
	var/volume = 40

CAPABILITIES(/obj/item/dq_forms_flask)
	reagents(PROC_REF(flask_volume), starts = list(REAGENT_ID_WATER = 10))

/// The volume per instance: a holder proc (reagents(volume = PROC_REF(...))).
/obj/item/dq_forms_flask/proc/flask_volume()
	return volume

CAPABILITIES(/obj/item/dq_forms_flask/spiked)
	configure(reagents(add = list(REAGENT_ID_WATER = 5, REAGENT_ID_ETHANOL = 5), volume = 60))

/// starts = replaces the inherited contents.
CAPABILITIES(/obj/item/dq_forms_flask/replaced)
	configure(reagents(starts = list(REAGENT_ID_ETHANOL = 3)))

/// add = on a grandchild merges after the parent's replacement; volume = replaces the volume only.
CAPABILITIES(/obj/item/dq_forms_flask/replaced/topped)
	configure(reagents(add = list(REAGENT_ID_WATER = 2), volume = 25))

/// A volume named by nameof(): read from the holder's var at init (a mapped volume).
/obj/item/dq_forms_flask/by_var
	volume = 55

CAPABILITIES(/obj/item/dq_forms_flask/by_var)
	configure(reagents(volume = nameof(volume)))

CAPABILITIES(/obj/item/dq_forms_flask/dry)
	without(CAP_REAGENTS)

CAPABILITIES(/obj/item/dq_forms_flask/tinted)
	configure(reagents(volume = 20, starts = list(REAGENT_ID_ETHANOL = 5), tint = TRUE))

/// A reagent named by holder vars (the old DECLARE_REAGENT_FROM_VAR).
/obj/item/dq_forms_flask/from_var
	var/reagent_id = REAGENT_ID_ETHANOL
	var/reagent_amount = 7

CAPABILITIES(/obj/item/dq_forms_flask/from_var)
	configure(reagents(volume = 30, starts = list(), starts_from = list(nameof(reagent_id) = nameof(reagent_amount))))

/// Computed amounts and data: a var-read amount summed with a subtype's number, data from a var and from a proc.
/obj/item/dq_forms_flask/computed
	var/units = 4
	var/list/taste = list("forms" = 1)

/obj/item/dq_forms_flask/computed/proc/blood_units()
	return 6

/obj/item/dq_forms_flask/computed/proc/blood_data()
	return list("blood_type" = "O-")

CAPABILITIES(/obj/item/dq_forms_flask/computed)
	configure(reagents(starts = list(REAGENT_ID_NUTRIMENT = nameof(units), REAGENT_ID_BLOOD = PROC_REF(blood_units)), data = list(REAGENT_ID_NUTRIMENT = nameof(taste), REAGENT_ID_BLOOD = PROC_REF(blood_data))))

/obj/item/dq_forms_flask/computed/more

CAPABILITIES(/obj/item/dq_forms_flask/computed/more)
	configure(reagents(add = list(REAGENT_ID_NUTRIMENT = 2)))

/// A holder of a /datum/reagents subtype.
CAPABILITIES(/obj/item/dq_forms_flask/distilling)
	configure(reagents(holder = /datum/reagents/distilling))

/// gas_store(): a mixture made at init and owned.
/obj/item/dq_forms_tank
	name = "forms tank"
	var/datum/gas_mixture/air_contents

/obj/item/dq_forms_tank/capabilities()
	. = ..()
	. += gas_store(nameof(air_contents), 70, T20C, list(GAS_O2 = ONE_ATMOSPHERE))

/// membership(joins =): an ordinary and a conditional registry.
/obj/item/dq_forms_member
	name = "forms member"

/obj/item/dq_forms_member/capabilities()
	. = ..()
	. += membership(joins = list(REGISTRY_DQ_FORMS_PLAIN, REGISTRY_DQ_FORMS_COND))

/// after_init(): a one-shot timer armed at init; the delay may be a holder var.
/obj/item/dq_forms_timer
	name = "forms timer"
	var/fuse = 2 SECONDS
	var/fired = 0

CAPABILITIES(/obj/item/dq_forms_timer)
	after_init(nameof(fuse), then(PROC_REF(go_off)))

/obj/item/dq_forms_timer/proc/go_off(datum/act/A)
	fired++

/// type_verb(..., login = TRUE).
/mob/living/simple_mob/dq_forms_login

/mob/living/simple_mob/dq_forms_login/type_verbs()
	. = ..()
	. += type_verb(/mob/living/simple_mob/dq_forms_login/proc/dq_forms_player_verb, login = TRUE)
	. += /mob/living/simple_mob/dq_forms_login/proc/dq_forms_always_verb

/mob/living/simple_mob/dq_forms_login/proc/dq_forms_player_verb()
	set name = "DQ forms player verb"
	return

/mob/living/simple_mob/dq_forms_login/proc/dq_forms_always_verb()
	set name = "DQ forms always verb"
	return

/// A window stand-in: counts coalesced pushes (no client, no window).
/datum/tgui/dq_forms_probe
	var/pushes = 0

/datum/tgui/dq_forms_probe/New()
	return

/datum/tgui/dq_forms_probe/push_coalesced()
	pushes++
	return TRUE

/datum/dq_forms_ui_host
	var/acted = 0

/datum/dq_forms_ui_host/proc/act_poke(mob/user)
	acted++
	return TRUE

/datum/dq_forms_ui_host/admin
	ui_rights = R_ADMIN

// ---- G4 ----

/// rel_one / rel_many (kind = RELK_OWNED, starts =) make the starting occupant at init, from the type var; the
/// relation's policy still decides teardown.
/datum/unit_test/dq_forms_relation_starts/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_forms_holder/H = allocate(/obj/item/dq_forms_holder, T)
	TEST_ASSERT(istype(H.part, /obj/item/dq_forms_part) && !istype(H.part, /obj/item/dq_forms_part/better), "the starting occupant is the type var's type")
	TEST_ASSERT_EQUAL(H.part.loc, H, "made inside its holder")
	TEST_ASSERT_EQUAL(length(H.spares), 2, "a list relation starts with list(type = count)")
	var/obj/item/dq_forms_holder/better/B = allocate(/obj/item/dq_forms_holder/better, T)
	TEST_ASSERT(istype(B.part, /obj/item/dq_forms_part/better), "a subtype's type var picks another occupant")
	var/obj/item/dq_forms_holder/empty/E = allocate(/obj/item/dq_forms_holder/empty, T)
	TEST_ASSERT_NULL(E.part, "a null type var starts nothing")
	TEST_ASSERT_EQUAL(own_entry(H, nameof(H.part))?[OWNE_KIND], OWNK_OWN, "the occupant is owned")
	TEST_ASSERT(own_table_of(H).start_vars?[nameof(H.part)], "the table lists the starting occupant")
	var/obj/item/dq_forms_part/spilled = H.part
	qdel(H)
	TEST_ASSERT(!QDELETED(spilled) && spilled.loc == T, "OWN_SPILL drops the part when the holder goes")
	qdel(spilled)

/// The APC's cell is its relation's starting occupant (starts = nameof(cell_type)).
/datum/unit_test/dq_forms_apc_cell_starts/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/power/apc/dx_test/cell_start/A = allocate(/obj/machinery/power/apc/dx_test/cell_start, T)
	TEST_ASSERT(istype(A.cell, /obj/item/cell/high), "the APC starts with its cell_type")
	TEST_ASSERT_EQUAL(A.cell.loc, A, "inside the APC")
	var/obj/machinery/power/apc/dx_test/none = allocate(/obj/machinery/power/apc/dx_test, T)
	TEST_ASSERT_NULL(none.cell, "cell_type = null starts no cell")

/// owns_one(starts =) lands in the ownership table's starting occupants and makes the child.
/datum/unit_test/dq_forms_default_child_wrapper/Run()
	var/obj/item/dq_decl_probe/probe = allocate(/obj/item/dq_decl_probe, dq_containment_floor())
	var/list/starts = own_table_of(probe).start_vars
	TEST_ASSERT(starts?[nameof(probe.part)], "owns_one(starts =) lands in the ownership table's starting occupants")
	TEST_ASSERT(istype(probe.part, /obj/item/dq_decl_part), "and the child is made")
	TEST_ASSERT(istype(probe.mapped_part, /obj/item/dq_decl_part/better), "a path held in the var still wins")

/// reagents(): a holder filled at init; configure(reagents(add =)) merges, starts = replaces, volume = replaces the volume; without() drops it.
/datum/unit_test/dq_forms_reagents/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_forms_flask/F = allocate(/obj/item/dq_forms_flask, T)
	TEST_ASSERT_EQUAL(F.reagents?.maximum_volume, 40, "volume answered by the holder proc")
	TEST_ASSERT_EQUAL(F.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "starting contents")
	var/obj/item/dq_forms_flask/spiked/S = allocate(/obj/item/dq_forms_flask/spiked, T)
	TEST_ASSERT_EQUAL(S.reagents.maximum_volume, 60, "configure(volume =) replaces the volume")
	TEST_ASSERT_EQUAL(S.reagents.get_reagent_amount(REAGENT_ID_WATER), 15, "configure(add =) merges into the inherited contents")
	TEST_ASSERT_EQUAL(S.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 5, "and brings its own")
	var/obj/item/dq_forms_flask/replaced/R = allocate(/obj/item/dq_forms_flask/replaced, T)
	TEST_ASSERT_EQUAL(R.reagents.get_reagent_amount(REAGENT_ID_WATER), 0, "configure(starts =) replaces the inherited contents")
	TEST_ASSERT_EQUAL(R.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 3, "with its own")
	TEST_ASSERT_EQUAL(R.reagents.maximum_volume, 40, "and keeps the inherited volume")
	var/obj/item/dq_forms_flask/replaced/topped/top = allocate(/obj/item/dq_forms_flask/replaced/topped, T)
	TEST_ASSERT_EQUAL(top.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 3, "an inherited replacement still applies")
	TEST_ASSERT_EQUAL(top.reagents.get_reagent_amount(REAGENT_ID_WATER), 2, "and the subtype's add goes after it")
	TEST_ASSERT_EQUAL(top.reagents.maximum_volume, 25, "volume = replaces the volume")
	var/obj/item/dq_forms_flask/by_var/BV = allocate(/obj/item/dq_forms_flask/by_var, T)
	TEST_ASSERT_EQUAL(BV.reagents.maximum_volume, 55, "nameof(var) reads the holder's var")
	TEST_ASSERT_EQUAL(BV.reagents.get_reagent_amount(REAGENT_ID_WATER), 10, "and keeps the inherited contents")
	var/obj/item/dq_forms_flask/dry/D = allocate(/obj/item/dq_forms_flask/dry, T)
	TEST_ASSERT_NULL(D.reagents, "without(CAP_REAGENTS) drops the holder")
	var/obj/item/dq_forms_flask/tinted/tint = allocate(/obj/item/dq_forms_flask/tinted, T)
	TEST_ASSERT_EQUAL(uppertext(copytext(tint.color, 1, 8)), uppertext(copytext(tint.reagents.get_color(), 1, 8)), "tint colours from the reagents")
	var/obj/item/dq_forms_flask/from_var/V = allocate(/obj/item/dq_forms_flask/from_var, T)
	TEST_ASSERT_EQUAL(V.reagents.get_reagent_amount(REAGENT_ID_ETHANOL), 7, "starts_from reads the id and amount vars")
	TEST_ASSERT_EQUAL(V.reagents.get_reagent_amount(REAGENT_ID_WATER), 0, "starts = list() empties the inherited contents")
	var/obj/item/dq_forms_flask/computed/C = allocate(/obj/item/dq_forms_flask/computed, T)
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT), 4, "an amount named by nameof() reads the var")
	TEST_ASSERT_EQUAL(C.reagents.get_reagent_amount(REAGENT_ID_BLOOD), 6, "an amount named by PROC_REF() asks the holder")
	var/list/blood = C.reagents.get_data(REAGENT_ID_BLOOD)
	TEST_ASSERT_EQUAL(blood?["blood_type"], "O-", "data = gives the reagent the proc's data")
	var/obj/item/dq_forms_flask/computed/more/CM = allocate(/obj/item/dq_forms_flask/computed/more, T)
	TEST_ASSERT_EQUAL(CM.reagents.get_reagent_amount(REAGENT_ID_NUTRIMENT), 6, "a subtype's add sums with an inherited computed amount")
	var/obj/item/dq_forms_flask/distilling/DS = allocate(/obj/item/dq_forms_flask/distilling, T)
	TEST_ASSERT(istype(DS.reagents, /datum/reagents/distilling), "holder = picks the holder type")
	// Memory: one shared capability per declaration, nothing per instance but the holder itself.
	var/obj/item/dq_forms_flask/F2 = allocate(/obj/item/dq_forms_flask, T)
	TEST_ASSERT(table_cap_defs(table_of(F), CAP_REAGENTS, null)[1] == table_cap_defs(table_of(F2), CAP_REAGENTS, null)[1], "the capability is one flyweight per declaration")
	TEST_ASSERT_NULL(capability_data(F), "no per-instance capability data")
	var/obj/item/dq_forms_part/plain_part = allocate(/obj/item/dq_forms_part, T)
	TEST_ASSERT_NULL(plain_part.reagents, "a type without the capability allocates nothing")
	// The worked conversion: the reagent tanks.
	var/obj/structure/reagent_dispensers/watertank/high/W = allocate(/obj/structure/reagent_dispensers/watertank/high, T)
	TEST_ASSERT_EQUAL(W.reagents.maximum_volume, 5000, "the tank's volume")
	TEST_ASSERT_EQUAL(W.reagents.get_reagent_amount(REAGENT_ID_WATER), 5000, "a high-capacity tank adds its water to the plain tank's")

/// type_verb(..., login = TRUE): only once a player has had the mob; plain type_verbs() entries from init.
/datum/unit_test/dq_forms_login_verbs/Run()
	var/mob/living/simple_mob/dq_forms_login/M = allocate(/mob/living/simple_mob/dq_forms_login, dq_containment_floor())
	var/player_verb = /mob/living/simple_mob/dq_forms_login/proc/dq_forms_player_verb
	var/always_verb = /mob/living/simple_mob/dq_forms_login/proc/dq_forms_always_verb
	TEST_ASSERT(player_verb in type_verbs_login(M), "the login entry is split out")
	TEST_ASSERT(!(player_verb in type_verbs_always(M)), "and is not an always verb")
	TEST_ASSERT(always_verb in M.verbs, "a plain type verb is there from init")
	TEST_ASSERT(!(player_verb in M.verbs), "an NPC never carries a login verb")
	TEST_ASSERT(!verb_store_wants(M, M, player_verb), "the store refuses it without a player")
	// The worked conversion and the wrapper: /mob/living's player verbs (login.dm) and DECLARE_LOGIN_VERB.
	TEST_ASSERT(/mob/living/proc/escapeOOC in type_verbs_login(M), "living mobs' player verbs are login entries")
	TEST_ASSERT(!(/mob/living/proc/escapeOOC in M.verbs), "and not on an NPC")

/// gas_store(): the mixture exists at init with the declared gases, owned by the holder.
/datum/unit_test/dq_forms_gas_store/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_forms_tank/K = allocate(/obj/item/dq_forms_tank, T)
	TEST_ASSERT(istype(K.air_contents, /datum/gas_mixture), "the mixture is made at init")
	TEST_ASSERT_EQUAL(K.air_contents.return_volume(), 70, "its volume")
	var/expected = ONE_ATMOSPHERE * 70 / (R_IDEAL_GAS_EQUATION * T20C)
	TEST_ASSERT(abs(K.air_contents.get_moles(GAS_O2) - expected) < 0.01, "its oxygen (P V / R T)")
	TEST_ASSERT_EQUAL(own_entry(K, nameof(K.air_contents))?[OWNE_KIND], OWNK_OWN, "owned by the holder")
	var/obj/structure/transit_tube_pod/pod = allocate(/obj/structure/transit_tube_pod, T)
	TEST_ASSERT(istype(pod.air_contents, /datum/gas_mixture), "the worked conversion: the transit pod carries its air")

/// membership(joins =): in both registries while materialized (the conditional one too), out when deleted.
/datum/unit_test/dq_forms_membership/Run()
	var/obj/item/dq_forms_member/M = allocate(/obj/item/dq_forms_member, dq_containment_floor())
	TEST_ASSERT(registry_has(REGISTRY_DQ_FORMS_PLAIN, M), "an ordinary registry is joined")
	TEST_ASSERT(registry_has(REGISTRY_DQ_FORMS_COND, M), "a conditional registry is joined at materialize")
	registry_leave(REGISTRY_DQ_FORMS_COND, M)
	TEST_ASSERT(!registry_has(REGISTRY_DQ_FORMS_COND, M), "code may still leave the conditional one")
	qdel(M)
	TEST_ASSERT(!registry_has(REGISTRY_DQ_FORMS_PLAIN, M), "deleted: out of the registry")
	var/obj/item/taperecorder/R = allocate(/obj/item/taperecorder, dq_containment_floor())
	TEST_ASSERT(registry_has(REGISTRY_LISTENING_OBJECTS, R), "the worked conversion: a tape recorder listens")

/// after_init(): the timer is armed when the holder initializes and fires once, after its delay.
/datum/unit_test/dq_forms_after_init/Run()
	scheduler_test_begin()
	var/obj/item/dq_forms_timer/timer = new(dq_containment_floor())
	TEST_ASSERT_EQUAL(timer.fired, 0, "the timer waits")
	scheduler_advance(1)
	TEST_ASSERT_EQUAL(timer.fired, 0, "still waiting at half its delay")
	scheduler_advance(2)
	TEST_ASSERT_EQUAL(timer.fired, 1, "it fired once")
	scheduler_advance(3)
	TEST_ASSERT_EQUAL(timer.fired, 1, "and only once")
	qdel(timer)
	scheduler_test_end()
	var/obj/item/broken_gun/wreck = allocate(/obj/item/broken_gun, dq_containment_floor())
	TEST_ASSERT(after_pending(wreck, "after_init:1"), "the worked conversion: a broken gun arms its self-check")

/// Native traits preserve radiation protection and its examine output.
/datum/unit_test/dq_forms_type_trait/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, dq_containment_floor())
	var/obj/item/clothing/suit/radiation/S = allocate(/obj/item/clothing/suit/radiation, dq_containment_floor())
	TEST_ASSERT(has_trait(S, TRAIT_RADIATION_PROTECTED_CLOTHING), "the trait is there from init")
	TEST_ASSERT(span_notice(RADIATION_CLOTHING_EXAMINE) in examine_collect(S, H), "and its examine line")
	var/obj/item/clothing/head/radiation/hood = allocate(/obj/item/clothing/head/radiation, dq_containment_floor())
	TEST_ASSERT(has_trait(hood, TRAIT_RADIATION_PROTECTED_CLOTHING), "the actual hood also starts protected")
	TEST_ASSERT(span_notice(RADIATION_CLOTHING_EXAMINE) in examine_collect(hood, H), "the hood retains its examine line")

// ---- G12 ----

/// Library constructors take requirements, not behind/blocked_by/locked_by: req_set / req_clear fold onto the
/// entries' gate bits and keep their messages.
/datum/unit_test/dq_forms_library_requirements/Run()
	var/datum/capability/P = cap_gating(new /datum/capability, needs = req_clear(COVER))
	TEST_ASSERT_EQUAL(P.blocked_by, COVER, "req_clear(COVER) folds onto blocked_by")
	TEST_ASSERT_NULL(P.needs, "and leaves no requirement behind")
	var/datum/capability/C = cap_gating(new /datum/capability, needs = req_clear(LOCK))
	TEST_ASSERT_EQUAL(C.locked_by, LOCK, "req_clear(LOCK) folds onto locked_by (\"it's locked\")")
	var/datum/capability/slot/S = cap_slot(nameof(/obj/item/dq_forms_holder::part), /obj/item, needs = list(req_set(COVER), GLOBAL_PROC_REF(cap_in_reach)))
	TEST_ASSERT_EQUAL(S.behind, COVER, "req_set(COVER) folds onto behind")
	TEST_ASSERT_EQUAL(S.needs, GLOBAL_PROC_REF(cap_in_reach), "the other needs stay")

// ---- G14 ----

/// changed() UI marks and ui_push_mark() deliver at most one push per open window per pass.
/datum/unit_test/dq_forms_ui_push_coalesced/Run()
	var/datum/dq_forms_ui_host/host = new
	var/datum/tgui/dq_forms_probe/probe = new
	LAZYADD(host.open_tguis, probe)
	ui_push_flush()
	TEST_ASSERT_EQUAL(ui_push_mark(host), 1, "one window queued")
	ui_push_mark(host)
	refresh_ui(host)
	TEST_ASSERT_EQUAL(length(SSui_push.pending), 1, "marked three times, queued once")
	ui_push_flush()
	TEST_ASSERT_EQUAL(probe.pushes, 1, "one push delivered")
	TEST_ASSERT_NULL(SSui_push.pending, "the queue is empty after the pass")
	refresh_mark(host, DEP_UI)
	refresh_mark(host, DEP_UI)
	refresh_flush()
	TEST_ASSERT_EQUAL(probe.pushes, 2, "two refresh marks in one frame: one more push")
	LAZYREMOVE(host.open_tguis, probe)

/// ui_rights: the admin state, and a refused (audited) action for anyone without the rights.
/datum/unit_test/dq_forms_ui_rights/Run()
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, dq_containment_floor())
	var/datum/tgui/dq_forms_probe/window = new
	rel_set(window, nameof(window.user), H)
	var/datum/dq_forms_ui_host/plain = new
	var/datum/dq_forms_ui_host/admin/panel = new
	TEST_ASSERT_EQUAL(panel.tgui_state(H), ADMIN_STATE(R_ADMIN), "ui_rights gives the admin state")
	TEST_ASSERT_EQUAL(plain.tgui_state(H), GLOB.tgui_default_state, "no ui_rights: the default state")
	var/list/result = ui_named_dispatch(panel, "poke", list(), window)
	TEST_ASSERT(result?[1] && !result[2], "an action by a user without the rights is refused")
	TEST_ASSERT_EQUAL(panel.acted, 0, "and its handler never ran")
	result = ui_named_dispatch(plain, "poke", list(), window)
	TEST_ASSERT(result?[1] && result[2], "without ui_rights the action runs")
	TEST_ASSERT_EQUAL(plain.acted, 1, "once")
	rel_clear(window, nameof(window.user))
	var/datum/round_status_panel/rsp = new
	TEST_ASSERT_EQUAL(rsp.ui_interface(null), "RoundStatusPanel", "the converted panel opens by tgui_id")
	TEST_ASSERT_EQUAL(rsp.tgui_state(null), ADMIN_STATE(R_ADMIN | R_EVENT | R_SERVER), "and gates by ui_rights")
	qdel(rsp)

#undef REGISTRY_DQ_FORMS_PLAIN
#undef REGISTRY_DQ_FORMS_COND

/// keeps_if(): an atom whose condition fails at init is discarded (INITIALIZE_HINT_QDEL); one whose condition holds is kept.
/obj/item/dq_forms_keeps
	name = "forms keeps"

/obj/item/dq_forms_keeps/proc/on_a_mob()
	return ismob(loc)

CAPABILITIES(/obj/item/dq_forms_keeps)
	keeps_if(PROC_REF(on_a_mob))

/datum/unit_test/dq_forms_keeps_if/Run()
	var/turf/T = dq_containment_floor()
	var/obj/item/dq_forms_keeps/loose = new(T)
	TEST_ASSERT(QDELETED(loose), "a failed keeps_if() discards the atom at init")
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/item/dq_forms_keeps/held = allocate(/obj/item/dq_forms_keeps, H)
	TEST_ASSERT(!QDELETED(held), "a holding keeps_if() keeps it")
	TEST_ASSERT(!init_discard_pending?[held], "and leaves no mark")
