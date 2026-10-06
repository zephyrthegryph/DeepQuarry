// The gate fixture of E1 (doc/rewrite/final_api.html, section 19 "The seven workers": "A fixture type declares one of every entry kind;
// explain_type matches a golden dump; ..."). Test-only capabilities and types, compiled under UNIT_TESTS only, so no phase-1 gate needs the
// library. The declarations are real (the macros of code/__defines/engine/declare.dm); what an engine that has not landed owns (an op, a
// stat contribution, a hook) is written with entry_of(kind, key), the generic entry the table keeps for the engine that owns the kind.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// A capability with a selector (key = "label"): two widgets on one type are e1_widget("a") and e1_widget("b"); stacking keeps only the strongest.
CAPABILITY_TYPE(e1_widget, CAP_E1_WIDGET, /datum/capability/e1_widget, key = label, stacks = BEST(power), label = "main", power = 1)
/datum/capability/e1_widget

/datum/capability/e1_widget/entries()
	return list(entry_of("op", "poke"), entry_of("contributes", "glow", stat = STAT_LIGHT_RANGE, value = 2))

/datum/capability/e1_widget/on_activate(datum/activation/A)
	GLOB.e1_log += "activate:[label]:[A.holder.type]"

/datum/capability/e1_widget/on_deactivate(datum/activation/A)
	GLOB.e1_log += "deactivate:[label]"

/// One use per holder (key = NONE), with typed state and capability keys.
CAPABILITY_TYPE(e1_solo, CAP_E1_SOLO, /datum/capability/e1_solo, key = NONE, note = "plain")
/datum/capability/e1_solo
	holder_hooks = HOLDER_HOOK_PREINIT | HOLDER_HOOK_INIT | HOLDER_HOOK_DESTROY

/datum/capability/e1_solo/cap_data_type()
	return /datum/cap_data/e1_solo

/datum/cap_data/e1_solo
	var/count = 0

/datum/capability/e1_solo/on_holder_preinit(datum/act/eval/A)
	GLOB.e1_log += "holder_preinit:[A.holder.type]"

/datum/capability/e1_solo/on_holder_init(datum/act/eval/A)
	GLOB.e1_log += "holder_init:[A.holder.type]:[A.mapload ? "map" : "runtime"]"

/datum/capability/e1_solo/on_holder_destroy(datum/act/eval/A)
	GLOB.e1_log += "holder_destroy:[A.holder.type]"

cap_keys(CAP_E1_SOLO, ARMED = null, LIT = null)

/// A capability whose entries include another capability: the child activation is owned by the parent and ends with it.
CAPABILITY_TYPE(e1_nested, CAP_E1_NESTED, /datum/capability/e1_nested, key = NONE)
/datum/capability/e1_nested/entries()
	return list(e1_widget("inner", power = 3))

/// A capability brought by the beacon: sourced by a flyweight in the lifetime tests.
CAPABILITY_TYPE(e1_beacon, CAP_E1_BEACON, /datum/capability/e1_beacon, key = NONE)
/datum/capability/e1_beacon

GLOBAL_LIST_EMPTY(e1_log)

/// What a species-like relation value grants: its own CAPABILITIES list (the design's SPECIES_CAPABILITIES).
/datum/e1_species
	var/name = "e1 species"

/datum/e1_species/alpha
	name = "alpha"

CAPABILITIES(/datum/e1_species/alpha)
	e1_widget("species", power = 5)
	e1_beacon()

/datum/e1_species/beta
	name = "beta"

CAPABILITIES(/datum/e1_species/beta)
	e1_solo()

/obj/item/e1_part
	name = "e1 part"
	var/shape = "gizmo"

/obj/item/e1_part/tarnished
	shape = "tarnished"

/// The fixture of one of every entry kind.
/obj/e1_fixture
	name = "e1 fixture"
	/// ref_one
	var/datum/e1_species/species
	/// owns_one with a starting occupant
	var/obj/item/e1_part/gizmo
	/// owns_many
	var/list/gizmos
	/// ref_many
	var/list/watchers
	/// one end of a link
	var/obj/e1_fixture/partner
	var/e1_armed = FALSE
	var/e1_setting = 7
	var/list/e1_notes
	var/list/e1_tags

CAPABILITIES(/obj/e1_fixture)
	e1_solo()
	e1_widget("a", power = 2)
	ref_one(nameof(species), /datum/e1_species)
	rel_grants(nameof(species))
	owns_one(nameof(gizmo), /obj/item/e1_part, starts = /obj/item/e1_part)
	owns_many(nameof(gizmos), /obj/item/e1_part)
	ref_many(nameof(watchers), /mob)
	links(/obj/e1_fixture::partner, /obj/e1_fixture::partner)
	slot("e1_slot", accepts = list(/obj/item/e1_part), capacity = 1)
	while_slotted("e1_slot", e1_beacon(), on = ON_HOLDER)
	when(nameof(e1_armed), entry_of("contributes", "armed_glow", stat = STAT_LIGHT_RANGE, value = 4))
	entry_of("op", "toggle")

LIST_STATE(/obj/e1_fixture, e1_notes)
LIST_STATE(/obj/e1_fixture, e1_tags, kind = KIND_SET)

/// A subtype that changes what it inherits.
/obj/e1_fixture/changed
	name = "e1 changed fixture"

CAPABILITIES(/obj/e1_fixture/changed)
	extend("toggle", entry_of("part", "needs"))
	configure(e1_widget("a", power = 9))
	without(CAP_E1_SOLO)

/// A subtype that adds nothing: it shares its parent's compiled table.
/obj/e1_fixture/plain
	name = "e1 plain fixture"

/// A child with constructor arguments (starts_args).
/datum/e1_argy
	var/label
	var/datum/holder_ref

/datum/e1_argy/New(holder, label_arg)
	label = label_arg

/// The starting-occupant forms: pick_one, when(cond, T), a list with counts, starts_args and a proc.
/obj/e1_starts
	name = "e1 starts"
	var/obj/item/e1_part/picked
	var/obj/item/e1_part/conditional
	var/obj/item/e1_part/skipped
	var/list/counted
	var/datum/e1_argy/argy
	var/obj/item/e1_part/computed
	var/flag = TRUE
	var/off_flag = FALSE

CAPABILITIES(/obj/e1_starts)
	owns_one(nameof(picked), /obj/item/e1_part, starts = pick_one(list(/obj/item/e1_part/tarnished = 1)))
	owns_one(nameof(conditional), /obj/item/e1_part, starts = when(nameof(flag), /obj/item/e1_part/tarnished))
	owns_one(nameof(skipped), /obj/item/e1_part, starts = when(nameof(off_flag), /obj/item/e1_part/tarnished))
	owns_many(nameof(counted), /obj/item/e1_part, starts = list(/obj/item/e1_part = 2))
	owns_one(nameof(argy), /datum/e1_argy, starts = /datum/e1_argy, starts_args = list("hello"))
	owns_one(nameof(computed), /obj/item/e1_part, starts = PROC_REF(make_computed))

/obj/e1_starts/proc/make_computed(datum/act/A)
	return /obj/item/e1_part/tarnished

/// slot(starts =, starts_args =) and a capability built on a slot (cell_bay(starts = PROC_REF(x))).
/obj/e1_slot_starts
	name = "e1 slot starts"
	var/flag = TRUE
	var/obj/item/e0_fixture/cell/cell

CAPABILITIES(/obj/e1_slot_starts)
	slot("e1_pair", accepts = list(/obj/item/e1_part), capacity = 2, starts = list(/obj/item/e1_part = 2))
	slot("e1_pick", accepts = list(/obj/item/e1_part), capacity = 1, starts = pick_one(list(/obj/item/e1_part/tarnished = 1)))
	slot("e1_cond", accepts = list(/obj/item/e1_part), capacity = 1, starts = when(nameof(flag), /obj/item/e1_part/labelled), starts_args = list("conditional"))
	cell_bay(nameof(cell), accepts = /obj/item/e0_fixture/cell, starts = PROC_REF(pick_cell))

/obj/e1_slot_starts/proc/pick_cell(datum/act/A)
	return /obj/item/e0_fixture/cell

/// A part that takes a constructor argument (starts_args on a slot).
/obj/item/e1_part/labelled
	var/label

CAPABILITIES(/obj/item/e1_part/labelled)
	param(nameof(label), pos = 1)


/// A holder for the per-instance lifetime tests: no declared relations, so it is only a holder.
/obj/e1_holder
	name = "e1 holder"

/// The tracked schema fixture: the pump of proof 10 and the schema kinds.
/obj/e1_schema
	name = "e1 schema"
	var/target_pressure = 101
	var/dial = 3
	var/mode = "off"
	var/label = "x"
	var/count = 4

TRACKED_SCHEMA(/obj/e1_schema, target_pressure, num(0, MAX_PUMP_PRESSURE, step = 1), default = 101)
TRACKED_SCHEMA(/obj/e1_schema, dial, int(0, 10))
TRACKED_SCHEMA(/obj/e1_schema, mode, enum(list("off", "on", "syphon")))
TRACKED_SCHEMA(/obj/e1_schema, label, schema_text(8))
SCHEMA(/obj/e1_schema, count, int(1, 9))

#ifndef MAX_PUMP_PRESSURE
#define MAX_PUMP_PRESSURE 15000
#endif

// ---- the state graph of section 12 (proof 9): a door assembly with two paths to finished ----

STATE_GRAPH(GRAPH_DOOR_ASSEMBLY)
	start(STAGE_DOOR_FRAME)
	stage(STAGE_DOOR_WIRED, stack(/obj/item/stack/cable_coil, 5))
	stage(STAGE_DOOR_BOARDED, item(/obj/item/e0_fixture/board), put_in(SLOT_CONSTRUCTION))
	stage(STAGE_DOOR_FINISHED, tool(TOOL_SCREWDRIVER), wait(0), from = STAGE_DOOR_BOARDED)
	stage(STAGE_DOOR_FINISHED, item(/obj/item/e0_fixture/door_kit), consumes(), from = STAGE_DOOR_WIRED, key = "kit", undo = list(tool(TOOL_CROWBAR), wait(0)))
	dismantle(tool(TOOL_WELDER))

/obj/e1_assembly
	name = "e1 assembly"

CAPABILITIES(/obj/e1_assembly)
	construction(GRAPH_DOOR_ASSEMBLY)

/// Placed finished: two paths lead to that stage, so the type names the one it stands for.
/obj/e1_assembly/finished
	name = "e1 finished assembly"

CAPABILITIES(/obj/e1_assembly/finished)
	configure(construction_graph(start = STAGE_DOOR_FINISHED, via = list(STAGE_DOOR_WIRED, STAGE_DOOR_BOARDED)))

/// An entity with no graph, for the negative reads.
/obj/e1_assembly/bare
	name = "e1 bare"

#endif
