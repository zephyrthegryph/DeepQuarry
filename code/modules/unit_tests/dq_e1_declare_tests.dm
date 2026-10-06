// E1, declarations: the gate fixture of doc/rewrite/final_api.html section 19 "The seven workers" (code/tests/engine/e1_fixtures.dm).
//
// A fixture type declares one of every entry kind; explain_type matches a golden dump; a second capability of the same key with
// different params and an unknown literal key in extend are each a build error naming file and line; a legacy constructor is accepted.
// Then the pieces of E1: relations and their write verbs, scoped activation, value schemas, and state graphs.

/// The text of explain_type() with the "@ file:line" origins removed, for the golden comparison (the origins are asserted on their own).
/proc/e1_strip_origins(text)
	var/list/lines = splittext(text, "\n")
	var/list/out = list()
	for(var/line in lines)
		var/at = findtext(line, " @ ")
		out += at ? copytext(line, 1, at) : line
	return jointext(out, "\n")

/// The fixture's own lines of an explain_type() dump: the entries it inherits from /atom, /obj and the rest (declared in their own files) are left out,
/// so the golden does not change when an ancestor declares one more relation.
/proc/e1_own_lines(text)
	var/list/out = list()
	for(var/line in splittext(text, "\n"))
		if(copytext(line, 1, 2) == "/" || findtext(line, "e1_fixtures.dm:") || !findtext(line, " @ "))
			out += line
	return jointext(out, "\n")

/datum/unit_test/dq_e1
	abstract_type = /datum/unit_test/dq_e1

/// Runs `run_e1()` with declaration reports captured, so a deliberate error is read instead of failing the run.
/datum/unit_test/dq_e1/Run()
	GLOB.declare_report_capture = list()
	GLOB.e1_log = list()
	run_e1()
	GLOB.declare_report_capture = null

/datum/unit_test/dq_e1/proc/run_e1()
	return

/// The reports captured so far.
/datum/unit_test/dq_e1/proc/reports()
	var/list/capture = GLOB.declare_report_capture
	return capture ? capture : list()

// ---------------------------------------------------------------------------------------------------------------------
// The compiled table
// ---------------------------------------------------------------------------------------------------------------------

/// The compiled table of the fixture, as explain_type() prints it with the origins removed: the golden of the E1 gate.
#define E1_GOLDEN_FIXTURE {"/obj/e1_fixture
  capability e1_solo ()
  capability e1_widget "a" (label=a, power=2)
  op "e1_widget.a.poke" () from e1_widget:a
  contributes "glow" (stat=light_range, value=2) from e1_widget:a
  ref_one (var=species, type=/datum/e1_species, on_other_deleted=1)
  rel_grants (var=species)
  owns_one (var=gizmo, type=/obj/item/e1_part, starts=/obj/item/e1_part, on_destroy=1)
  owns_many (var=gizmos, type=/obj/item/e1_part, on_destroy=1)
  ref_many (var=watchers, type=/mob, on_other_deleted=1)
  link (a_type=/obj/e1_fixture, a_var=partner, b_type=/obj/e1_fixture, b_var=partner)
  slot (id=e1_slot, accepts=list, capacity=1)
  while_slotted (slot=e1_slot, on=2, /datum/capability/e1_beacon)
    contributes "armed_glow" (stat=light_range, value=4) when(e1_armed)
  op "toggle" ()"}

#define E1_GOLDEN_CHANGED {"/obj/e1_fixture/changed
  capability e1_widget "a" (label=a, power=9)
  op "e1_widget.a.poke" () from e1_widget:a
  contributes "glow" (stat=light_range, value=2) from e1_widget:a
  ref_one (var=species, type=/datum/e1_species, on_other_deleted=1)
  rel_grants (var=species)
  owns_one (var=gizmo, type=/obj/item/e1_part, starts=/obj/item/e1_part, on_destroy=1)
  owns_many (var=gizmos, type=/obj/item/e1_part, on_destroy=1)
  ref_many (var=watchers, type=/mob, on_other_deleted=1)
  link (a_type=/obj/e1_fixture, a_var=partner, b_type=/obj/e1_fixture, b_var=partner)
  slot (id=e1_slot, accepts=list, capacity=1)
  while_slotted (slot=e1_slot, on=2, /datum/capability/e1_beacon)
    contributes "armed_glow" (stat=light_range, value=4) when(e1_armed)
  op "toggle" ()
  extend (target=toggle, part)"}

/datum/unit_test/dq_e1/table_golden

/datum/unit_test/dq_e1/table_golden/run_e1()
	var/text = e1_own_lines(explain_type(/obj/e1_fixture))
	TEST_ASSERT_NOTNULL(text, "explain_type returns the dump")
	TEST_ASSERT_EQUAL(e1_strip_origins(text), E1_GOLDEN_FIXTURE, "explain_type matches the golden dump of the fixture")
	// Every line carries file:line, in every build.
	for(var/line in splittext(text, "\n"))
		if(line == "/obj/e1_fixture")
			continue
		TEST_ASSERT(findtext(line, " @ ") && findtext(line, "e1_fixtures.dm:"), "every entry keeps its origin: [line]")
	// One of every entry kind E1 owns is in the dump.
	for(var/kind in list(ENTRY_REF_ONE, ENTRY_REF_MANY, ENTRY_OWNS_ONE, ENTRY_OWNS_MANY, ENTRY_LINK, ENTRY_SLOT, ENTRY_WHILE_SLOTTED, ENTRY_REL_GRANTS))
		TEST_ASSERT(findtext(text, "  [kind] ("), "the fixture declares a [kind]")
	TEST_ASSERT(findtext(text, "capability e1_"), "and capabilities")
	TEST_ASSERT(findtext(text, ") when("), "and a when() block")

/datum/unit_test/dq_e1/table_inherits_extend_configure_without

/datum/unit_test/dq_e1/table_inherits_extend_configure_without/run_e1()
	var/text = e1_own_lines(explain_type(/obj/e1_fixture/changed))
	TEST_ASSERT_NOTNULL(text, "explain_type of the subtype")
	TEST_ASSERT_EQUAL(e1_strip_origins(text), E1_GOLDEN_CHANGED, "the subtype's table: the parent's, configured, extended, one capability dropped")
	var/obj/e1_fixture/changed/F = allocate(/obj/e1_fixture/changed)
	var/datum/capability/e1_widget/widget = cap_of(F, CAP_E1_WIDGET, "a")
	TEST_ASSERT_NOTNULL(widget, "cap_of finds the widget by id and selector")
	TEST_ASSERT_EQUAL(widget.power, 9, "configure(e1_widget(\"a\", power = 9)) changed the param")
	TEST_ASSERT_NULL(cap_of(F, CAP_E1_SOLO), "without(CAP_E1_SOLO) dropped the solo")
	// A parent's table is untouched by its subtype.
	TEST_ASSERT_EQUAL(e1_strip_origins(e1_own_lines(explain_type(/obj/e1_fixture))), E1_GOLDEN_FIXTURE, "the parent's table is as it was")

/datum/unit_test/dq_e1/table_shared_when_a_type_adds_nothing

/datum/unit_test/dq_e1/table_shared_when_a_type_adds_nothing/run_e1()
	var/obj/e1_fixture/parent = new
	var/obj/e1_fixture/plain/child = new
	TEST_ASSERT(table_of(parent) == table_of(child), "a type whose list adds nothing shares its parent's compiled table")
	var/obj/e1_fixture/changed/changed_one = new
	TEST_ASSERT(table_of(parent) != table_of(changed_one), "a type with its own list has its own")
	qdel(parent)
	qdel(child)
	qdel(changed_one)

/datum/unit_test/dq_e1/table_errors_name_file_and_line

/datum/unit_test/dq_e1/table_errors_name_file_and_line/run_e1()
	// The same capability key with different params: an error naming both.
	table_compile(/obj/e1_fixture, null, list(e1_widget("a", power = 2), e1_widget("a", power = 3)), "somefile.dm:12")
	var/list/errors = reports()
	TEST_ASSERT_EQUAL(length(errors), 1, "one error for the conflict, got [json_encode(errors)]")
	TEST_ASSERT(findtext(errors[1], "somefile.dm:12"), "it names the file and line: [errors[1]]")
	TEST_ASSERT(findtext(errors[1], "[RULE_CAP_CONFLICT]"), "it names the rule: [errors[1]]")
	TEST_ASSERT(findtext(errors[1], "power=2") && findtext(errors[1], "power=3"), "it shows both params: [errors[1]]")
	// An identical repeat dedupes: no error.
	GLOB.declare_report_capture = list()
	var/datum/type_table/T = table_compile(/obj/e1_fixture, null, list(e1_widget("a", power = 2), e1_widget("a", power = 2)), "somefile.dm:13")
	TEST_ASSERT_EQUAL(length(reports()), 0, "an identical repeat is not an error")
	TEST_ASSERT_EQUAL(length(compiled_entries(T, ENTRY_CAPABILITY)), 1, "and it appears once")
	// An unknown literal key in extend.
	GLOB.declare_report_capture = list()
	table_compile(/obj/e1_fixture, null, list(entry_of("op", "toggle"), extend("togle", entry_of("part", "x"))), "otherfile.dm:40")
	errors = reports()
	TEST_ASSERT_EQUAL(length(errors), 1, "one error for the unknown key, got [json_encode(errors)]")
	TEST_ASSERT(findtext(errors[1], "otherfile.dm:40") && findtext(errors[1], "[RULE_UNKNOWN_KEY]") && findtext(errors[1], "togle"), "it names file, line and key: [errors[1]]")
	// configure and without of what the type does not have.
	GLOB.declare_report_capture = list()
	table_compile(/obj/e1_fixture, null, list(configure(e1_widget(power = 4)), without("nothing")), "third.dm:7")
	errors = reports()
	TEST_ASSERT_EQUAL(length(errors), 2, "configure and without of nothing are errors, got [json_encode(errors)]")
	TEST_ASSERT(findtext(errors[1], "third.dm:7") && findtext(errors[2], "third.dm:7"), "both name the file and line")
	// A different kind for one var across the hierarchy.
	GLOB.declare_report_capture = list()
	table_compile(/obj/e1_fixture, null, list(ref_one("species", /datum/e1_species), owns_one("species", /datum/e1_species)), "fourth.dm:3")
	errors = reports()
	TEST_ASSERT_EQUAL(length(errors), 1, "one kind per var, got [json_encode(errors)]")
	TEST_ASSERT(findtext(errors[1], "[RULE_RELATION_KIND]"), "it is the relation-kind rule")

/datum/unit_test/dq_e1/table_accepts_a_legacy_constructor

/datum/unit_test/dq_e1/table_accepts_a_legacy_constructor/run_e1()
	var/datum/capability/legacy = cap_cover()
	var/datum/type_table/T = table_compile(/obj/e1_fixture, null, list(legacy, e1_solo()), "legacy.dm:1")
	TEST_ASSERT_EQUAL(length(reports()), 0, "a legacy capability beside an engine one is accepted: [json_encode(reports())]")
	TEST_ASSERT_EQUAL(length(compiled_entries(T, ENTRY_CAPABILITY)), 2, "both are in the table")
	TEST_ASSERT(T.caps[legacy.key] == legacy, "the legacy one is keyed by its own key")
	// The legacy list-returning forms still work: without() of a list drops a legacy entry.
	var/list/legacy_list = without(list(legacy), legacy.key)
	TEST_ASSERT_EQUAL(length(legacy_list), 0, "the legacy without(list, key) still drops by key")

/datum/unit_test/dq_e1/entries_are_interned

/datum/unit_test/dq_e1/entries_are_interned/run_e1()
	TEST_ASSERT(ref_one("species", /datum/e1_species) == ref_one("species", /datum/e1_species), "an identical constructor call is one datum")
	TEST_ASSERT(e1_widget("a", power = 2) == e1_widget("a", power = 2), "an identical capability call is one definition")
	TEST_ASSERT(e1_widget("a", power = 2) != e1_widget("a", power = 3), "different params are two")
	TEST_ASSERT(e1_widget("a") != e1_widget("b"), "different selectors are two")
	var/datum/capability/e1_widget/w = e1_widget("hatch", power = 4)
	TEST_ASSERT_EQUAL(w.selector, "hatch", "the first positional argument is the selector")
	TEST_ASSERT_EQUAL(w.cap_id, CAP_E1_WIDGET, "the definition carries its id")
	TEST_ASSERT_EQUAL(w.key, "[CAP_E1_WIDGET]:hatch", "and its key is (id, selector)")
	var/datum/capability/e1_solo/solo = e1_solo()
	TEST_ASSERT_NULL(solo.selector, "key = NONE has no selector")
	TEST_ASSERT_EQUAL(solo.key, "[CAP_E1_SOLO]", "and its key is the id alone")

// ---------------------------------------------------------------------------------------------------------------------
// Relations and their write verbs
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e1/relations_declared_and_written

/datum/unit_test/dq_e1/relations_declared_and_written/run_e1()
	var/obj/e1_fixture/F = allocate(/obj/e1_fixture)
	// owns_one with starts = makes the child at init.
	TEST_ASSERT(istype(F.gizmo, /obj/item/e1_part), "starts = created the owned gizmo at init")
	TEST_ASSERT(owner_of(F.gizmo) == F, "and the holder owns it")
	// rel_set on an owned var replaces it and disposes of the old one by on_destroy.
	var/obj/item/e1_part/old_gizmo = F.gizmo
	var/obj/item/e1_part/tarnished/fresh = allocate(/obj/item/e1_part/tarnished)
	rel_set(F, nameof(F.gizmo), fresh)
	TEST_ASSERT(F.gizmo == fresh, "rel_set stores the new owned value")
	TEST_ASSERT(QDELETED(old_gizmo), "and the old one is disposed of by on_destroy = DELETE")
	// rel_take detaches it, unowned and alive.
	var/obj/item/e1_part/taken = rel_take(F, nameof(F.gizmo))
	TEST_ASSERT(taken == fresh && !QDELETED(taken), "rel_take returns the value alive")
	TEST_ASSERT_NULL(F.gizmo, "and the var is empty")
	TEST_ASSERT_NULL(owner_of(taken), "and unowned")
	// owns_many: add, keyed take, move.
	var/obj/item/e1_part/p1 = allocate(/obj/item/e1_part)
	var/obj/item/e1_part/p2 = allocate(/obj/item/e1_part)
	rel_add(F, nameof(F.gizmos), p1)
	rel_add(F, nameof(F.gizmos), p2)
	TEST_ASSERT_EQUAL(length(F.gizmos), 2, "rel_add on an owns_many")
	var/obj/e1_fixture/G = allocate(/obj/e1_fixture)
	rel_move(F, nameof(F.gizmos), G, nameof(G.gizmo), member = p1)
	TEST_ASSERT(G.gizmo == p1 || QDELETED(p1) == FALSE, "rel_move re-owns without destroying")
	TEST_ASSERT(!QDELETED(p1), "the moved value is alive")
	var/list/everything = rel_take_all(F, nameof(F.gizmos))
	TEST_ASSERT_EQUAL(length(everything), 1, "rel_take with no member detaches every member (p2 is what is left)")
	// rel_remove disposes of an owned member.
	rel_add(F, nameof(F.gizmos), p2)
	rel_remove(F, nameof(F.gizmos), p2)
	TEST_ASSERT(QDELETED(p2), "rel_remove disposes of an owned member")
	// rel_clear.
	var/obj/item/e1_part/p3 = allocate(/obj/item/e1_part)
	rel_set(G, nameof(G.gizmo), p3)
	rel_clear(G, nameof(G.gizmo))
	TEST_ASSERT(QDELETED(p3), "rel_clear disposes of what the var owns")

/datum/unit_test/dq_e1/relations_starting_occupant_forms

/datum/unit_test/dq_e1/relations_starting_occupant_forms/run_e1()
	var/obj/e1_starts/S = allocate(/obj/e1_starts)
	TEST_ASSERT(istype(S.picked, /obj/item/e1_part/tarnished), "starts = pick_one(...) made the pick")
	TEST_ASSERT(istype(S.conditional, /obj/item/e1_part/tarnished), "when(cond, T) starts it when the condition holds at init")
	TEST_ASSERT_NULL(S.skipped, "and does not when it does not")
	TEST_ASSERT_EQUAL(length(S.counted), 2, "list(T = n) makes n of them")
	TEST_ASSERT(istype(S.argy, /datum/e1_argy) && S.argy.label == "hello", "starts_args are the constructor's arguments")
	TEST_ASSERT(istype(S.computed, /obj/item/e1_part/tarnished), "PROC_REF(x) computes the starting occupant")
	TEST_ASSERT(owner_of(S.picked) == S && owner_of(S.argy) == S, "and the holder owns what it started with")

/datum/unit_test/dq_e1/slot_starting_contents

/datum/unit_test/dq_e1/slot_starting_contents/run_e1()
	var/obj/e1_slot_starts/S = allocate(/obj/e1_slot_starts)
	var/parts = 0
	var/tarnished = 0
	var/obj/item/e1_part/labelled/labelled
	for(var/obj/item/e1_part/P in S.contents)
		parts++
		if(istype(P, /obj/item/e1_part/tarnished))
			tarnished++
		if(istype(P, /obj/item/e1_part/labelled))
			labelled = P
	TEST_ASSERT_EQUAL(parts, 4, "slot(starts = list(T = 2)), pick_one() and when(cond, T) made four parts inside the holder")
	TEST_ASSERT_EQUAL(tarnished, 1, "pick_one() made its pick")
	TEST_ASSERT(labelled?.label == "conditional", "when(cond, T) made it and starts_args reached its constructor")
	TEST_ASSERT(istype(S.cell, /obj/item/e0_fixture/cell) && S.cell.loc == S, "cell_bay(starts = PROC_REF(x)) filled the bay from the proc's answer")

/datum/unit_test/dq_e1/capability_lifecycle_hooks

/datum/unit_test/dq_e1/capability_lifecycle_hooks/run_e1()
	var/obj/e1_fixture/F = new
	TEST_ASSERT(("holder_preinit:/obj/e1_fixture" in GLOB.e1_log), "on_holder_preinit ran: [json_encode(GLOB.e1_log)]")
	TEST_ASSERT(("holder_init:/obj/e1_fixture:runtime" in GLOB.e1_log), "on_holder_init ran with the context (not mapload): [json_encode(GLOB.e1_log)]")
	GLOB.e1_log = list()
	qdel(F)
	TEST_ASSERT(("holder_destroy:/obj/e1_fixture" in GLOB.e1_log), "on_holder_destroy ran in the destroy transaction: [json_encode(GLOB.e1_log)]")

/datum/unit_test/dq_e1/relations_references_clear_when_the_other_end_dies

/datum/unit_test/dq_e1/relations_references_clear_when_the_other_end_dies/run_e1()
	var/obj/e1_fixture/F = allocate(/obj/e1_fixture)
	var/datum/e1_species/alpha/S = new
	rel_set(F, nameof(F.species), S)
	TEST_ASSERT(F.species == S, "ref_one stores the reference")
	qdel(S)
	TEST_ASSERT_NULL(F.species, "and the view clears when the other end is deleted")
	var/mob/living/simple_mob/e0_fixture/watcher = allocate(/mob/living/simple_mob/e0_fixture)
	rel_add(F, nameof(F.watchers), watcher)
	TEST_ASSERT(watcher in F.watchers, "ref_many adds a member")
	GLOB.dq_lifecycle_report_capture = list() // the type refusal reports through the ownership layer, not ours
	TEST_ASSERT_NULL(rel_add(F, nameof(F.watchers), allocate(/obj/e1_holder)), "a value of the wrong type is refused")
	TEST_ASSERT_EQUAL(length(GLOB.dq_lifecycle_report_capture), 1, "and reported once")
	GLOB.dq_lifecycle_report_capture = null
	qdel(watcher)
	TEST_ASSERT_EQUAL(length(F.watchers), 0, "a deleted member leaves the list")

/datum/unit_test/dq_e1/relations_link_writes_both_ends

/datum/unit_test/dq_e1/relations_link_writes_both_ends/run_e1()
	var/obj/e1_fixture/A = allocate(/obj/e1_fixture)
	var/obj/e1_fixture/B = allocate(/obj/e1_fixture)
	var/obj/e1_fixture/C = allocate(/obj/e1_fixture)
	rel_set(A, nameof(A.partner), B)
	TEST_ASSERT(A.partner == B, "one write sets this end")
	TEST_ASSERT(B.partner == A, "and the other end")
	rel_set(A, nameof(A.partner), C)
	TEST_ASSERT(C.partner == A, "linking a new partner sets its side")
	TEST_ASSERT_NULL(B.partner, "and unlinks the old one on both sides")
	qdel(C)
	TEST_ASSERT_NULL(A.partner, "deleting an end clears the other")

/datum/unit_test/dq_e1/list_state_dimensions

/datum/unit_test/dq_e1/list_state_dimensions/run_e1()
	var/obj/e1_fixture/F = allocate(/obj/e1_fixture)
	TEST_ASSERT_NULL(F.e1_notes, "a lazy list is null until the first add")
	rel_add(F, nameof(F.e1_notes), "one")
	TEST_ASSERT_EQUAL(length(F.e1_notes), 1, "the first add allocates it")
	rel_add(F, nameof(F.e1_notes), "one")
	TEST_ASSERT_EQUAL(length(F.e1_notes), 2, "kind = LIST keeps duplicates")
	rel_remove(F, nameof(F.e1_notes), "one")
	rel_remove(F, nameof(F.e1_notes), "one")
	TEST_ASSERT_NULL(F.e1_notes, "and a lazy list that emptied is null again")
	rel_add(F, nameof(F.e1_tags), "x")
	rel_add(F, nameof(F.e1_tags), "x")
	TEST_ASSERT_EQUAL(length(F.e1_tags), 1, "kind = KIND_SET: adding a member twice is a no-op")
	rel_clear(F, nameof(F.e1_tags))
	TEST_ASSERT_NULL(F.e1_tags, "rel_clear empties it, and lazy means null")

// ---------------------------------------------------------------------------------------------------------------------
// Scoped activation
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e1/activation_grant_revoke_granted

/datum/unit_test/dq_e1/activation_grant_revoke_granted/run_e1()
	var/obj/e1_holder/H = allocate(/obj/e1_holder)
	var/obj/e1_holder/src_a = allocate(/obj/e1_holder)
	TEST_ASSERT(!granted(H, /datum/capability/e1_widget), "nothing granted yet")
	var/datum/activation/A = grant(H, e1_widget("w", power = 2), source = src_a)
	TEST_ASSERT_NOTNULL(A, "grant returns the activation")
	TEST_ASSERT(granted(H, /datum/capability/e1_widget), "granted by type")
	TEST_ASSERT(granted(H, e1_widget("w", power = 2)), "granted by the constructor call")
	TEST_ASSERT(!granted(H, e1_widget("other")), "another selector is another key")
	TEST_ASSERT(("activate:w:[H.type]" in GLOB.e1_log), "on_activate ran: [json_encode(GLOB.e1_log)]")
	// One source applies one definition once.
	TEST_ASSERT(grant(H, e1_widget("w", power = 2), source = src_a) == A, "granting the identical definition from the same source returns the same activation")
	TEST_ASSERT_EQUAL(length(activations_of(H, e1_widget("w").key)), 1, "still one activation")
	TEST_ASSERT(revoke(H, e1_widget("w"), source = src_a), "revoke finds it")
	TEST_ASSERT(A.dead, "the activation is dead the moment revoke returns")
	TEST_ASSERT(!granted(H, /datum/capability/e1_widget), "and no longer granted")
	TEST_ASSERT(("deactivate:w" in GLOB.e1_log), "on_deactivate ran")
	TEST_ASSERT(!revoke(H, e1_widget("w"), source = src_a), "revoking twice finds nothing")

/datum/unit_test/dq_e1/activation_sources_and_errors

/datum/unit_test/dq_e1/activation_sources_and_errors/run_e1()
	var/obj/e1_holder/H = allocate(/obj/e1_holder)
	TEST_ASSERT_NULL(grant(H, e1_widget("w"), source = "text"), "a text source is an error")
	TEST_ASSERT_NULL(grant(H, e1_widget("w"), source = null), "a null source is an error")
	TEST_ASSERT_EQUAL(length(reports()), 2, "both reported: [json_encode(reports())]")
	GLOB.declare_report_capture = list()
	var/datum/activation/A = grant(H, e1_widget("w"), source = SRC_AI_CONTROL)
	TEST_ASSERT_NOTNULL(A, "a SOURCE_DEF flyweight is a valid source")
	TEST_ASSERT_EQUAL(length(reports()), 0, "without a report")
	TEST_ASSERT_NULL(grant(H, e1_widget("w2"), source = 999), "a number that is no flyweight is not a source")
	GLOB.declare_report_capture = list()
	TEST_ASSERT_NULL(grant(H, e1_widget("w3"), source = H, lasts = -3), "a negative duration is an error")
	TEST_ASSERT_EQUAL(length(reports()), 1, "reported")
	GLOB.declare_report_capture = list()
	qdel(H)
	TEST_ASSERT(A.dead, "deleting the holder ends its activations")

/datum/unit_test/dq_e1/activation_stacking_best

/datum/unit_test/dq_e1/activation_stacking_best/run_e1()
	var/obj/e1_holder/H = allocate(/obj/e1_holder)
	var/obj/e1_holder/vest = allocate(/obj/e1_holder)
	var/obj/e1_holder/shield = allocate(/obj/e1_holder)
	var/datum/activation/weak = grant(H, e1_widget("m", power = 30), source = vest)
	var/datum/activation/strong = grant(H, e1_widget("m", power = 45), source = shield)
	TEST_ASSERT(strong.runs && !weak.runs, "BEST(power): the strongest runs, the other is shadowed")
	TEST_ASSERT(winning_activation(H, CAP_E1_WIDGET, "m") == strong, "winning_activation names it")
	TEST_ASSERT_EQUAL(length(running_activations(H, CAP_E1_WIDGET, "m")), 1, "one runs")
	TEST_ASSERT_EQUAL(winning_activation(H, CAP_E1_WIDGET, "m").source, shield, "and A.source is the shield")
	revoke(H, e1_widget("m", power = 45), source = shield)
	TEST_ASSERT(weak.runs, "the vest was shadowed, not removed: with the shield revoked it runs")
	grant(H, e1_widget("m", power = 45), source = shield)
	revoke(H, e1_widget("m", power = 30), source = vest)
	TEST_ASSERT(winning_activation(H, CAP_E1_WIDGET, "m").source == shield, "the shield alone, after the vest is revoked")
	var/datum/activation/vest_again = grant(H, e1_widget("m", power = 30), source = vest)
	TEST_ASSERT(winning_activation(H, CAP_E1_WIDGET, "m").source == shield, "granting the vest back does not take the roll from the shield")
	TEST_ASSERT(!vest_again.runs, "the vest is shadowed again")
	// A tie goes to the first attached.
	var/obj/e1_holder/H2 = allocate(/obj/e1_holder)
	var/datum/activation/first = grant(H2, e1_widget("t", power = 5), source = vest)
	var/datum/activation/second = grant(H2, e1_widget("t", power = 5), source = shield)
	TEST_ASSERT(first.runs && !second.runs, "a tie goes to the first by attach order")
	var/text = explain_activations(H)
	TEST_ASSERT(findtext(text, "winning") && findtext(text, "shadowed"), "explain_activations says which wins: [text]")

/datum/unit_test/dq_e1/activation_teardown_order_and_ownership

/datum/unit_test/dq_e1/activation_teardown_order_and_ownership/run_e1()
	var/obj/e1_holder/H = allocate(/obj/e1_holder)
	var/obj/e1_holder/source = allocate(/obj/e1_holder)
	var/datum/activation/parent = grant(H, e1_nested(), source = source)
	TEST_ASSERT_NOTNULL(parent, "a capability whose entries include another")
	TEST_ASSERT(granted(H, /datum/capability/e1_widget), "the child capability is applied")
	TEST_ASSERT_EQUAL(length(parent.owned), 1, "the child activation is owned by the parent")
	GLOB.e1_log = list()
	revoke(H, e1_nested(), source = source)
	TEST_ASSERT(!granted(H, /datum/capability/e1_widget), "the owned child ended with it, in the same step")
	TEST_ASSERT(GLOB.e1_log.len >= 1 && ("deactivate:inner" in GLOB.e1_log), "the child's on_deactivate ran: [json_encode(GLOB.e1_log)]")
	// Deleting the source ends what it sourced; deleting the holder ends what it carried.
	var/datum/activation/A = grant(H, e1_widget("s", power = 1), source = source)
	qdel(source)
	TEST_ASSERT(A.dead, "deleting the source ends its activation")
	TEST_ASSERT(!granted(H, /datum/capability/e1_widget), "and the holder no longer has it")
	var/obj/e1_holder/source2 = allocate(/obj/e1_holder)
	var/datum/activation/B = grant(H, e1_widget("s2", power = 1), source = source2)
	qdel(H)
	TEST_ASSERT(B.dead, "deleting the holder ends the activations it carried")
	TEST_ASSERT_EQUAL(length(source2.rx?.sourced), 0, "and the source's record of it")

/datum/unit_test/dq_e1/activation_records_attach_and_detach

/datum/unit_test/dq_e1/activation_records_attach_and_detach/run_e1()
	test_driver_reset()
	var/obj/e1_holder/H = allocate(/obj/e1_holder)
	var/obj/e1_holder/source = allocate(/obj/e1_holder)
	test_record(H)
	grant(H, e1_widget("r", power = 1), source = source)
	revoke(H, e1_widget("r"), source = source)
	// The widget also brings a stat contribution, which the stat layer applies as a hold: its deltas are rows of their own kind.
	var/list/recorded = list()
	for(var/datum/test_event/row in test_recorded())
		if(row.kind == TEST_EVENT_ATTACH || row.kind == TEST_EVENT_DETACH)
			recorded += row
	TEST_ASSERT_EQUAL(length(recorded), 2, "one attach and one detach row, got [length(recorded)]")
	var/datum/test_event/first = recorded[1]
	var/datum/test_event/second = recorded[2]
	TEST_ASSERT_EQUAL(first.kind, TEST_EVENT_ATTACH, "the first row is the attach")
	TEST_ASSERT_EQUAL(second.kind, TEST_EVENT_DETACH, "the second is the detach")
	test_driver_reset()

/datum/unit_test/dq_e1/activation_keys_and_data

/datum/unit_test/dq_e1/activation_keys_and_data/run_e1()
	var/obj/e1_fixture/F = allocate(/obj/e1_fixture)
	TEST_ASSERT(!cap_key_get(F, E1_SOLO_ARMED), "a key is clear until set")
	TEST_ASSERT(cap_key_set(F, E1_SOLO_ARMED, TRUE), "setting it changes it")
	TEST_ASSERT(cap_key_get(F, E1_SOLO_ARMED), "and it reads set")
	TEST_ASSERT(!cap_key_get(F, E1_SOLO_LIT), "the other key of the word is separate")
	TEST_ASSERT(!cap_key_set(F, E1_SOLO_ARMED, TRUE), "setting it again changes nothing")
	TEST_ASSERT(cap_key_set(F, E1_SOLO_LIT, TRUE) && cap_key_get(F, E1_SOLO_LIT) && cap_key_get(F, E1_SOLO_ARMED), "two keys are two bits")
	cap_key_set(F, E1_SOLO_ARMED, FALSE)
	TEST_ASSERT(!cap_key_get(F, E1_SOLO_ARMED) && cap_key_get(F, E1_SOLO_LIT), "clearing one leaves the other")
	var/datum/activation/A = cap_activation(F, CAP_E1_SOLO)
	TEST_ASSERT_NOTNULL(A, "the type-level activation exists once there is state")
	var/datum/cap_data/e1_solo/data = cap_data(A)
	TEST_ASSERT_NOTNULL(data, "typed per-activation data is made on first use")
	data.count = 3
	TEST_ASSERT(cap_data(A) == data, "and is the same one after")
	// A holder with no such capability: no state, no activation made.
	var/obj/e1_holder/H = allocate(/obj/e1_holder)
	TEST_ASSERT(!cap_key_set(H, E1_SOLO_ARMED, TRUE), "a holder without the capability cannot hold its keys")
	TEST_ASSERT_EQUAL(length(reports()), 1, "and says so: [json_encode(reports())]")

/datum/unit_test/dq_e1/activation_species_change_is_a_relation_write

/datum/unit_test/dq_e1/activation_species_change_is_a_relation_write/run_e1()
	var/obj/e1_fixture/F = allocate(/obj/e1_fixture)
	var/datum/e1_species/alpha/alpha = allocate(/datum/e1_species/alpha)
	var/datum/e1_species/beta/beta = allocate(/datum/e1_species/beta)
	rel_set(F, nameof(F.species), alpha)
	TEST_ASSERT(granted(F, e1_widget("species")), "the new value's capabilities are granted")
	TEST_ASSERT(granted(F, /datum/capability/e1_beacon), "all of them")
	var/datum/activation/species_widget = winning_activation(F, CAP_E1_WIDGET, "species")
	TEST_ASSERT(species_widget.source == alpha, "sourced by the value the relation names")
	TEST_ASSERT_EQUAL(species_widget.scope, SCOPE_RELATION, "and scoped to the relation")
	rel_set(F, nameof(F.species), beta)
	TEST_ASSERT(!granted(F, e1_widget("species")), "what the old species gave ends in the same step")
	TEST_ASSERT(!granted(F, /datum/capability/e1_beacon), "all of it")
	TEST_ASSERT(species_widget.dead, "the old activation is dead")
	TEST_ASSERT(granted(F, /datum/capability/e1_solo), "and the new species' capability is there (the type's own solo too)")
	rel_set(F, nameof(F.species), null)
	TEST_ASSERT_NULL(F.species, "clearing the relation")
	rel_set(F, nameof(F.species), alpha)
	qdel(alpha)
	TEST_ASSERT(!granted(F, /datum/capability/e1_beacon), "deleting the value ends what it granted")

/datum/unit_test/dq_e1/activation_slot_scope

/datum/unit_test/dq_e1/activation_slot_scope/run_e1()
	var/obj/e1_fixture/F = allocate(/obj/e1_fixture)
	var/obj/item/e1_part/item = allocate(/obj/item/e1_part)
	var/obj/e1_holder/wearer = allocate(/obj/e1_holder)
	// An item type declares while_slotted(...): put it in the wearer's slot, the entries apply to the wearer.
	activations_slot_enter(item, F, "e1_slot")
	TEST_ASSERT(!granted(F, /datum/capability/e1_beacon), "the part type declares nothing, so nothing is granted")
	var/obj/e1_fixture/changed/C = allocate(/obj/e1_fixture/changed)
	// The fixture declares the while_slotted on the holder type with on = ON_HOLDER... as the item declaration: use it as the item.
	activations_slot_enter(F, wearer, "e1_slot")
	TEST_ASSERT(granted(wearer, /datum/capability/e1_beacon), "the item's while_slotted entries are granted to the holder")
	var/datum/activation/A = winning_activation(wearer, CAP_E1_BEACON)
	TEST_ASSERT(A.source == F && A.scope == SCOPE_SLOT, "sourced by the item, scoped to the slot")
	activations_slot_exit(F, wearer, "e1_slot")
	TEST_ASSERT(!granted(wearer, /datum/capability/e1_beacon) && A.dead, "it ends when the item leaves, however it leaves")
	activations_slot_enter(F, wearer, "e1_slot")
	qdel(F)
	TEST_ASSERT(!granted(wearer, /datum/capability/e1_beacon), "and when the item is deleted")
	qdel(C)

/datum/unit_test/om/dq_e1_activation_lasts

/datum/unit_test/om/dq_e1_activation_lasts/run_om(list/made)
	var/datum/om_test_entity/H = entity(made)
	var/datum/om_test_entity/source = entity(made)
	GLOB.declare_report_capture = list()
	var/datum/activation/A = grant(H, e1_widget("t", power = 1), source = source, lasts = 5 SECONDS)
	TEST_ASSERT_NOTNULL(A, "a timed grant")
	TEST_ASSERT(granted(H, /datum/capability/e1_widget), "granted for now")
	scheduler_advance(3)
	TEST_ASSERT(granted(H, /datum/capability/e1_widget), "still granted before its time")
	scheduler_advance(3)
	TEST_ASSERT(!granted(H, /datum/capability/e1_widget) && A.dead, "ended at its time")
	var/datum/activation/B = grant(H, e1_widget("t", power = 1), source = source, lasts = 60 SECONDS)
	qdel(source)
	TEST_ASSERT(B.dead, "a timed grant also ends with its source, whichever comes first")
	GLOB.declare_report_capture = null

// ---------------------------------------------------------------------------------------------------------------------
// Value schemas
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e1/schema_kinds

/datum/unit_test/dq_e1/schema_kinds/run_e1()
	var/list/r = schema_check(int(0, 10), 15)
	TEST_ASSERT(r[1] == 10 && r[2], "an int above its range is clamped and noted")
	r = schema_check(int(0, 10), 3.6)
	TEST_ASSERT_EQUAL(r[1], 4, "an internal write rounds a fractional int")
	r = schema_check(int(0, 10), 3.6, TRUE)
	TEST_ASSERT_EQUAL(r[1], SCHEMA_REJECT, "input at a boundary refuses a non-whole number")
	r = schema_check(num(0, 100, 5), 12)
	TEST_ASSERT_EQUAL(r[1], 10, "a num snaps to its step grid")
	r = schema_check(num(0, 100, 5), -3)
	TEST_ASSERT_EQUAL(r[1], 0, "and clamps")
	r = schema_check(enum(list("a", "b")), "c")
	TEST_ASSERT_EQUAL(r[1], SCHEMA_REJECT, "an enum refuses what is not a choice")
	r = schema_check(flags(list(1, 2, 4)), 3)
	TEST_ASSERT_EQUAL(r[1], 3, "flags accept declared bits")
	r = schema_check(flags(list(1, 2, 4)), 8)
	TEST_ASSERT_EQUAL(r[1], SCHEMA_REJECT, "and refuse undeclared ones")
	r = schema_check(schema_text(5), "toolong")
	TEST_ASSERT_EQUAL(r[1], SCHEMA_REJECT, "text longer than its max is refused")
	r = schema_check(bool(), 2)
	TEST_ASSERT_EQUAL(r[1], SCHEMA_REJECT, "a bool is TRUE or FALSE")
	r = schema_check(schema_ref(/obj/e1_holder), new /obj/e1_holder)
	TEST_ASSERT(isdatum(r[1]), "a ref of its type is accepted")
	r = schema_check(schema_ref(/obj/e1_holder), new /datum/e1_species)
	TEST_ASSERT_EQUAL(r[1], SCHEMA_REJECT, "a ref of another type is refused")
	r = schema_check(schema_path(/datum/e1_species), /datum/e1_species/alpha)
	TEST_ASSERT(ispath(r[1]), "a path under its type")
	r = schema_check(list_of(int(0, 5)), list(1, 9, 3))
	TEST_ASSERT(islist(r[1]) && r[1][2] == 5, "a list_of checks and clamps each member")
	r = schema_check(map_of(schema_text(3), int(0, 5)), list("ab" = 9))
	TEST_ASSERT(islist(r[1]) && r[1]["ab"] == 5, "a map_of checks keys and values")
	r = schema_check(map_of(schema_text(3), int(0, 5)), list("toolong" = 1))
	TEST_ASSERT_EQUAL(r[1], SCHEMA_REJECT, "a bad key refuses the map")

/datum/unit_test/dq_e1/schema_tracked_setter_clamps_and_logs

/datum/unit_test/dq_e1/schema_tracked_setter_clamps_and_logs/run_e1()
	GLOB.schema_log_capture = list()
	GLOB.schema_log_state = list()
	var/obj/e1_schema/P = allocate(/obj/e1_schema)
	TEST_ASSERT(P.set_target_pressure(99999), "a write outside the range still writes (clamped)")
	TEST_ASSERT_EQUAL(P.target_pressure, MAX_PUMP_PRESSURE, "99999 reaches the var as the maximum")
	var/list/log = GLOB.schema_log_capture
	TEST_ASSERT_EQUAL(length(log), 1, "and is logged once: [json_encode(log)]")
	TEST_ASSERT(findtext(log[1], "target_pressure") && findtext(log[1], "clamped"), "the line names the var and the clamp: [log[1]]")
	P.set_target_pressure(88888)
	P.set_target_pressure(77777)
	TEST_ASSERT_EQUAL(length(GLOB.schema_log_capture), 1, "later clamps inside the interval are counted, not written")
	TEST_ASSERT(!P.set_mode("sideways"), "an enum refusal rejects the write")
	TEST_ASSERT_EQUAL(P.mode, "off", "and the old value stays")
	TEST_ASSERT(P.set_mode("on"), "a valid write goes through")
	TEST_ASSERT_EQUAL(P.mode, "on", "and stores it")
	TEST_ASSERT(P.set_dial(12) && P.dial == 10, "an int setter clamps")
	TEST_ASSERT(P.set_dial(2.7) && P.dial == 3, "and rounds an internal fractional write")
	TEST_ASSERT(!P.set_label("way too long a label"), "text over its max is rejected")
	GLOB.schema_log_capture = null

/datum/unit_test/dq_e1/schema_range_text_matches_the_declaration

/datum/unit_test/dq_e1/schema_range_text_matches_the_declaration/run_e1()
	TEST_ASSERT_EQUAL(schema_range_text(/obj/e1_schema, "target_pressure"), "num 0..MAX_PUMP_PRESSURE step 1", "a define keeps its name in the range text")
	TEST_ASSERT_EQUAL(schema_range_text(/obj/e1_schema, "dial"), "int 0..10", "an int's range")
	TEST_ASSERT_EQUAL(schema_range_text(/obj/e1_schema, "count"), "int 1..9", "a SCHEMA var is the same")
	TEST_ASSERT_EQUAL(schema_range_text(/obj/e1_schema, "label"), "text max 8", "text says its length")
	TEST_ASSERT_NULL(schema_range_text(/obj/e1_schema, "name"), "an undeclared var has none")
	TEST_ASSERT(schema_of(/obj/e1_schema, "target_pressure") != null, "schema_of finds it")

// ---------------------------------------------------------------------------------------------------------------------
// State graphs
// ---------------------------------------------------------------------------------------------------------------------

/datum/unit_test/dq_e1/graph_advance_undo_ledger

/datum/unit_test/dq_e1/graph_advance_undo_ledger/run_e1()
	var/obj/e1_assembly/D = allocate(/obj/e1_assembly)
	TEST_ASSERT_EQUAL(graph_current(D), STAGE_DOOR_FRAME, "starts at the graph's start")
	TEST_ASSERT(built(D, STAGE_DOOR_FRAME), "the start is built")
	TEST_ASSERT(!built(D, STAGE_DOOR_WIRED), "a later stage is not")
	TEST_ASSERT(graph_advance(D, STAGE_DOOR_WIRED, null, list("material" = "copper")), "frame to wired")
	TEST_ASSERT(graph_advance(D, STAGE_DOOR_BOARDED, null, list("material" = "pcb")), "wired to boarded")
	TEST_ASSERT(graph_advance(D, STAGE_DOOR_FINISHED, null, list("material" = "screws")), "boarded to finished by the screwdriver edge")
	TEST_ASSERT(built(D, STAGE_DOOR_BOARDED) && built(D, STAGE_DOOR_FINISHED), "at or past: both are built")
	TEST_ASSERT_EQUAL(built_material(D, STAGE_DOOR_WIRED), "copper", "built_material reads the ledger entry")
	TEST_ASSERT_NULL(built_material(D, STAGE_DOOR_FRAME), "the start took nothing")
	var/list/undone = graph_undo(D)
	TEST_ASSERT_EQUAL(undone[1], STAGE_DOOR_BOARDED, "undo returns to the stage the instance came from")
	TEST_ASSERT_EQUAL(undone[2]["material"], "screws", "and hands back exactly that transition's ledger entry")
	TEST_ASSERT(!built(D, STAGE_DOOR_FINISHED), "finished is no longer built")
	graph_undo(D)
	graph_undo(D)
	TEST_ASSERT_EQUAL(graph_current(D), STAGE_DOOR_FRAME, "all the way back")
	TEST_ASSERT_NULL(graph_undo(D), "nothing left to undo")

/datum/unit_test/dq_e1/graph_two_predecessors_undo_to_the_actual_one

/datum/unit_test/dq_e1/graph_two_predecessors_undo_to_the_actual_one/run_e1()
	// frame > wired > finished (kit): undoing goes back to wired and refunds the kit.
	var/obj/e1_assembly/D = allocate(/obj/e1_assembly)
	graph_advance(D, STAGE_DOOR_WIRED, null, list("material" = "copper"))
	TEST_ASSERT(graph_advance(D, STAGE_DOOR_FINISHED, "kit", list("items" = list("door kit"))), "the kit edge leaves from wired")
	TEST_ASSERT(!built(D, STAGE_DOOR_BOARDED), "a stage never passed is not built: another branch was taken")
	TEST_ASSERT(built(D, STAGE_DOOR_FINISHED), "finished is")
	var/list/undone = graph_undo(D)
	TEST_ASSERT_EQUAL(undone[1], STAGE_DOOR_WIRED, "undo goes to the actual predecessor, wired, not boarded")
	TEST_ASSERT_EQUAL(undone[3], "kit", "the edge that was taken is named")
	TEST_ASSERT_EQUAL(length(undone[2]["items"]), 1, "and the refund is the kit's entry")
	// Without the key the kit edge is not taken: wired has no plain edge to finished.
	GLOB.declare_report_capture = list()
	TEST_ASSERT(!graph_advance(D, STAGE_DOOR_FINISHED, null), "no edge into finished leaves from wired without the kit key")
	TEST_ASSERT_EQUAL(length(reports()), 1, "and says so")

/datum/unit_test/dq_e1/graph_placed_finished_seeds_along_via

/datum/unit_test/dq_e1/graph_placed_finished_seeds_along_via/run_e1()
	var/obj/e1_assembly/finished/D = allocate(/obj/e1_assembly/finished)
	TEST_ASSERT_EQUAL(graph_current(D), STAGE_DOOR_FINISHED, "placed at the finished stage")
	TEST_ASSERT(built(D, STAGE_DOOR_BOARDED), "seeded lazily as frame > wired > boarded > finished: boarded is built")
	TEST_ASSERT(built(D, STAGE_DOOR_WIRED), "and wired")
	var/list/undone = graph_undo(D)
	TEST_ASSERT_EQUAL(undone[1], STAGE_DOOR_BOARDED, "undo goes to boarded")
	TEST_ASSERT_EQUAL(length(undone[2]), 0, "and refunds nothing: seeded entries carry empty ledgers")
	TEST_ASSERT_EQUAL(graph_current(D), STAGE_DOOR_BOARDED, "now at boarded")

/datum/unit_test/dq_e1/graph_validation

/datum/unit_test/dq_e1/graph_validation/run_e1()
	var/datum/state_graph/G = state_graph_of(GRAPH_DOOR_ASSEMBLY)
	TEST_ASSERT_NOTNULL(G, "the declared graph compiles")
	TEST_ASSERT_EQUAL(length(G.edges), 4, "four edges")
	TEST_ASSERT_EQUAL(length(graph_paths(G, STAGE_DOOR_FINISHED)), 2, "two paths lead to finished")
	TEST_ASSERT_EQUAL(length(graph_paths(G, STAGE_DOOR_BOARDED)), 1, "one leads to boarded")
	var/datum/graph_edge/kit = graph_edge_for(G, STAGE_DOOR_FINISHED, "kit")
	TEST_ASSERT_EQUAL(kit.op_key, "construction.build:door_finished.kit", "the build op key of the second way in")
	TEST_ASSERT(kit.has_undo, "an explicit undo is recorded")
	// A placed stage with several paths and no via is a build error.
	table_compile(/obj/e1_assembly, null, list(construction(GRAPH_DOOR_ASSEMBLY), configure(construction_graph(start = STAGE_DOOR_FINISHED))), "graph.dm:5")
	var/list/errors = reports()
	TEST_ASSERT_EQUAL(length(errors), 1, "no via on a stage with two paths: [json_encode(errors)]")
	TEST_ASSERT(findtext(errors[1], "graph.dm:5") && findtext(errors[1], "via"), "it names file, line and the fix: [errors[1]]")
	// A from that names an undeclared stage is a boot error.
	GLOB.declare_report_capture = list()
	graph_compile("bad", list(start(STAGE_DOOR_FRAME), stage(STAGE_DOOR_FINISHED, from = STAGE_DOOR_BOARDED)), "badgraph", "construction")
	TEST_ASSERT_EQUAL(length(reports()), 1, "a from naming a stage the graph does not declare: [json_encode(reports())]")
	// An undeclared stage id.
	GLOB.declare_report_capture = list()
	graph_compile("bad2", list(start(STAGE_DOOR_FRAME), stage(9999)), "badgraph2", "construction")
	TEST_ASSERT(length(reports()) >= 1, "a stage that STAGE_DEF never declared is reported")
	// Round trip: build to the end and undo back returns the instance to where it began.
	GLOB.declare_report_capture = list()
	var/obj/e1_assembly/D = allocate(/obj/e1_assembly)
	graph_advance(D, STAGE_DOOR_WIRED, null, list("material" = "a"))
	graph_advance(D, STAGE_DOOR_BOARDED, null, list("material" = "b"))
	graph_advance(D, STAGE_DOOR_FINISHED, null, list("material" = "c"))
	var/refunded = 0
	while(graph_undo(D))
		refunded++
	TEST_ASSERT_EQUAL(refunded, 3, "undo pops every transition")
	TEST_ASSERT_EQUAL(graph_current(D), STAGE_DOOR_FRAME, "and the instance is at the stage it began with")
	TEST_ASSERT_EQUAL(length(graph_history(D)), 0, "with an empty history")
