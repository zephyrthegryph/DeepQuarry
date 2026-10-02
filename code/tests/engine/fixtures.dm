// The test-only capability registry and fixtures of the E0 proofs (doc/rewrite/final_api.html, section 19 "The E0 proofs"; the
// "Gate fixture (test-only capabilities)" column of "The seven workers").
//
// Every fixture is declared twice. The TYPE is real DM today (plain vars and a placeholder proc or two), so the proofs can create
// it and read what the contracts promise. The CAPABILITIES composition root is written in the final syntax, as a declaration
// marker that expands to nothing (code/__defines/engine/markers.dm): it is the executable specification each engine builds
// against, and the table builder (E1) and generators (E5) read it from here the day they exist. Nothing compiles it before then.
// Final-form lines that use a name already taken on master (TRACKED, SYSTEM_DEF, MSG_DEF) are written as comments for the same reason.
//
// A fixture proc that stands in for engine behaviour that does not exist yet reports it through ENGINE_STUB, so a proof that
// reaches it fails with "E1-E6 not implemented: <what>". Compiled under UNIT_TESTS only.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

#ifndef MAX_PUMP_PRESSURE
/// The pump pressure ceiling of proof 10 (section 4's sample). A test-only value until the atmos pump declares its own.
#define MAX_PUMP_PRESSURE 15000
#endif

/// The slot the hopper of proof 5 declares: slot(SLOT_HOPPER, accepts = list(/obj/item/e0_fixture/sheets), capacity = ...).
#define E0_HOPPER_CAPACITY 10
/// Sheets one load takes (SHEETS_PER_LOAD in 16.14).
#define E0_SHEETS_PER_LOAD 5

// ---- Capability specs: what a grant() names. Plain types, since a constructor call such as mirror_plating(reflect_chance = 45)
// is not DM before E1: e0_mirror_plating(45) builds the spec the engine will intern. ----

/// A test-only capability spec: the definition a grant() applies. E1 replaces these with CAPABILITY_TYPE definitions.
/datum/e0_cap
	/// The CAP_* id the real definition carries.
	var/cap_id

/// CAPABILITY_TYPE(mirror_plating, CAP_E0_MIRROR, /datum/e0_cap/mirror, key = NONE, stacks = BEST(reflect_chance), reflect_chance = 30)
/datum/e0_cap/mirror
	cap_id = CAP_E0_MIRROR
	var/reflect_chance = 30

/// What a fixture writes for mirror_plating(reflect_chance = n).
/proc/e0_mirror_plating(reflect_chance = 30)
	var/datum/e0_cap/mirror/spec = new
	spec.reflect_chance = reflect_chance
	return spec

/// CAPABILITIES(/datum/e0_cap/tk, provides(AFF_MANIPULATE, reach = 15, line_of_sight = TRUE)): telekinesis, a provider.
/datum/e0_cap/tk
	cap_id = CAP_E0_DOOR

/// The CAPABILITY_TYPE(phase_shift, CAP_PHASE_SHIFT, ...) of 16.9: an ability (menu() ops "phase_shift.shift" and "phase_shift.unshift")
/// that grants the phased capability on its own holder (density, invisibility, acts_via, every(1 SECOND) energy drain).
/datum/e0_cap/phase_shift
	cap_id = CAP_PHASE_SHIFT

/// CAPABILITY_TYPE(phased, CAP_PHASED, /datum/capability/phased, key = NONE, drain = 1): density, invisibility, acts_via, every(1 SECOND).
/datum/e0_cap/phased
	cap_id = CAP_PHASED

/// SPECIES_CAPABILITIES for a test species (a species grants capabilities, including hands(), while a mob's species relation names it).
/datum/e0_species
	var/name = "e0 species"

/// SPECIES_CAPABILITIES(/datum/e0_species/shifter, hands(), phase_shift())
/datum/e0_species/shifter
	name = "e0 shifter"

/// SPECIES_CAPABILITIES(/datum/e0_species/plain, hands())
/datum/e0_species/plain
	name = "e0 plain"

// ---- The actor and the wearer: a simple mob with the vars the proofs read ----

/// A test mob. ref_one(nameof(species), /datum/e0_species) is declared on it (the legacy relation view learns the var), dark_energy
/// is the resource of 16.9 (TRACKED schema int(0, 100), default 100), and last_reflect_source is what the test-only mirror's reflect
/// handler writes its A.source into (proof 2).
/mob/living/simple_mob/e0_fixture
	name = "e0 fixture mob"
	has_hands = FALSE
	var/datum/e0_species/species
	var/dark_energy = 100
	/// Written by the reflect handler of the test-only mirror capability: the winning activation source.
	var/last_reflect_source

/// Delivers one beam hit to this mob as a world action: ACT_TRY(src, hit_projectile, packet), act_done(). Returns the act's
/// outcome (null when the hit was refused or taken over). The mirror's reflect handler runs inside ACT_TRY.
/mob/living/simple_mob/e0_fixture/proc/e0_beam_hit()
	var/datum/act/hit/projectile/H = e0_act_try(src, /datum/act/hit/projectile, null)
	if(!H)
		return null
	if(H == ACT_PASS)
		return ACT_COMMITTED
	var/outcome = H.outcome
	act_done(H)
	return outcome

/// Source items of proof 2: each declares while_slotted(SLOT_ANY_WORN, mirror_plating(reflect_chance = n), on = ON_HOLDER).
/obj/item/e0_fixture
	name = "e0 item"

/// CAPABILITIES(/obj/item/e0_fixture/vest, while_slotted(SLOT_ANY_WORN, mirror_plating(), on = ON_HOLDER))
/obj/item/e0_fixture/vest
	name = "e0 laserproof vest"

/// CAPABILITIES(/obj/item/e0_fixture/shield, while_slotted(SLOT_ANY_WORN, mirror_plating(reflect_chance = 45), on = ON_HOLDER))
/obj/item/e0_fixture/shield
	name = "e0 mirror shield"

// ---- Proof 1 and 6: the door ----

/// The door of proof 1 and, three times over, of proof 6.
/// CAPABILITY_TYPE(e0_door, CAP_E0_DOOR, /datum/capability/e0_door, key = NONE)
/// cap_keys(CAP_E0_DOOR, OPEN = MSG(e0_door/closed))
/// CAPABILITIES(/obj/e0_fixture/door,
///   e0_door(),         // op("toggle", inputs(hand(), ui_act()), toggles(DOOR_OPEN), logs(LOG_GAME)): "e0_door.toggle"
///   when(DOOR_OPEN, contributes(STAT_DENSITY, FALSE, priority = PRIORITY_FORCE)))   // density is a TOP stat: right the moment the door opens
/obj/e0_fixture
	name = "e0 fixture"
	anchored = TRUE

/obj/e0_fixture/door
	name = "e0 door"
	density = TRUE

// ---- Proof 4: the library terminal ----

/// The print op of 16.13 without its database step.
/// TRACKED(/obj/e0_fixture/library, selected_id, schema = int(0), default = 0)
/// CAPABILITIES(/obj/e0_fixture/library,
///   interface("E0Library"),   ui_shape(selected_id),
///   op("select", ui_act(arg("id", int(1))), then(PROC_REF(select_row))),
///   op("print", ui_act(), needs(req_is(nameof(selected_id), because = MSG(library/nothing_selected))),
///      confirms("Print the selected book?"), captures(nameof(selected_id)), then(PROC_REF(print_book))))
/obj/e0_fixture/library
	name = "e0 library terminal"
	var/selected_id = 0
	/// The id the print op's then() read through A.captured(nameof(selected_id)) (written by the handler), and what it logged.
	var/printed_id

/// The variant whose print op reads the selection with resume = CANCEL_IF_CHANGED: the op ends refused, "it changed while you were deciding".
/// CAPABILITIES(/obj/e0_fixture/library/strict, extend("print", replaces(captures(nameof(selected_id), resume = CANCEL_IF_CHANGED))))
/obj/e0_fixture/library/strict
	name = "e0 strict library terminal"

/// What the print op produces: carries the id the first actor confirmed.
/obj/item/e0_fixture/book
	name = "e0 book"
	var/book_id

// ---- Proof 5: the hopper ----

/// The fabricator hopper of 16.14.
/// CAPABILITIES(/obj/e0_fixture/hopper,
///   slot(SLOT_HOPPER, accepts = list(/obj/item/e0_fixture/sheets), capacity = E0_HOPPER_CAPACITY),
///   op("load", stack(/obj/item/e0_fixture/sheets, E0_SHEETS_PER_LOAD), wait(2 SECONDS), put_in(SLOT_HOPPER),
///      says(MSG(fab/loaded)), logs(LOG_GAME)))
/obj/e0_fixture/hopper
	name = "e0 hopper"

/obj/item/e0_fixture/sheets
	name = "e0 sheets"
	var/amount = 10

/// Kai's fill, landing inside Rae's wait: fills the hopper to capacity in one step. E1's slot(SLOT_HOPPER) and move_into() replace
/// the placeholder move; the fixture calls this one proc so the proof text does not change.
/obj/e0_fixture/hopper/proc/e0_fill_to_capacity(obj/item/e0_fixture/sheets/filler)
	filler.amount = E0_HOPPER_CAPACITY
	filler.forceMove(src)

// ---- Proof 7: the cabinet ----

/// A machine with a cover and a cell slot, for reach, containment and capability changes under cached menus.
/// CAPABILITIES(/obj/e0_fixture/cabinet,
///   cover(),                          // "cover.open" toggles COVER_OPEN
///   compartment(BAY_CABINET, door = CAP_COVER),
///   cell_bay(nameof(cell), at = BAY_CABINET),   // "cell_bay.cell.insert", "cell_bay.cell.take"
///   provides_none(),
///   op("pry_panel", tool(TOOL_CROWBAR), wait(5 SECONDS), toggles(PANEL_OPEN)))
/obj/e0_fixture/cabinet
	name = "e0 cabinet"
	var/obj/item/e0_fixture/cell/cell

/obj/item/e0_fixture/cell
	name = "e0 cell"

/// The value of a var an engine has not declared yet (a base stat, a material), or null while the var does not exist.
/proc/e0_var(datum/entity, var_name)
	return (var_name in entity.vars) ? entity.vars[var_name] : null

/// TRUE when a menu read (action_options()) lists `key`, optionally only when it is enabled.
/proc/e0_menu_has(list/menu, key, enabled_only = FALSE)
	for(var/list/entry in menu)
		if(entry["key"] == key && (!enabled_only || entry["enabled"]))
			return TRUE
	return FALSE

// ---- Proof 8: the night-shift cascade ----

/// What a lamp reads at night (its nightshift_range) and by day (its brightness_range).
#define E0_LAMP_NIGHT_RANGE 2
#define E0_LAMP_DAY_RANGE 4

/// A lamp whose light range is a stat read through the night-shift accessor (16.11), charged to LANE_SIMULATION.
/// STAT(/obj/e0_fixture/lamp, e0_lamp_range, MAX)
/// CAPABILITIES(/obj/e0_fixture/lamp,
///   contributes(STAT_E0_LAMP_RANGE, PROC_REF(lit_range)))   // lit_range(): night_shift_active() ? nightshift_range : brightness_range
/obj/e0_fixture/lamp
	name = "e0 lamp"
	var/e0_lamp_range = 4

/// The test-only system of proof 8 and the flag it owns.
/// SYSTEM_DEF(e0_night)  /datum/system/e0_night: lane = LANE_WORLD, TRACKED(.., night, schema = bool)
/// SYSTEM_ACCESSOR(e0_night, e0_night_active, nameof(night))
/// CAPABILITIES(/datum/system/e0_night, on_change(nameof(night), then(PROC_REF(announce))))
/// Flips the night flag (set_night(TRUE)): the marked cascade starts.
/proc/e0_flip_night(night = TRUE)
	ENGINE_STUB(ENGINE_E3, "test SYSTEM_DEF e0_night: set_night() flipping a tracked var that SYSTEM_ACCESSOR readers recompute (marked fan-out)")

/// The notice chain of proof 8: an on_notice handler publishes the next notice and counts itself. Starts a chain of `length` notices.
/// ACTION-free: the notice is published with PUBLISH-equivalent act_done() on a test action.
/datum/notice/e0_chain
	var/hop = 0

/proc/e0_start_notice_chain(length)
	ENGINE_STUB(ENGINE_E4, "hooks: a test on_notice(/datum/notice/e0_chain) handler that publishes the next notice (synchronous delivery, depth cap, the queue)")

/// Notices the chain's handler counted: the proof compares it with test_notice_count().
GLOBAL_VAR_INIT(e0_chain_handled, 0)

// ---- Proof 9: the door assembly ----

/// A test-only type with construction(GRAPH_DOOR_ASSEMBLY) (section 12).
/// CAPABILITIES(/obj/e0_fixture/door_assembly, construction(GRAPH_DOOR_ASSEMBLY),
///   extend("construction.build:door_wired", wait(0)))
/obj/e0_fixture/door_assembly
	name = "e0 door assembly"

/// A subtype placed finished. Two paths lead from the frame to finished, so the type names which one the history is seeded along.
/// CAPABILITIES(/obj/e0_fixture/door_assembly/finished,
///   configure(CAP_CONSTRUCTION, start = STAGE_DOOR_FINISHED, via = list(STAGE_DOOR_WIRED, STAGE_DOOR_BOARDED)))
/obj/e0_fixture/door_assembly/finished
	name = "e0 finished door assembly"

/// The board the boarded stage takes: item(/obj/item/e0_fixture/board) with put_in(SLOT_CONSTRUCTION).
/obj/item/e0_fixture/board
	name = "e0 airlock board"

/// The prefab kit that skips the board: item(/obj/item/e0_fixture/door_kit) with consumes(), from = STAGE_DOOR_WIRED, key = "kit".
/obj/item/e0_fixture/door_kit
	name = "e0 door kit"

// ---- Proof 10: the pump ----

/// TRACKED(/obj/e0_fixture/pump, target_pressure, schema = num(0, MAX_PUMP_PRESSURE, step = 1), default = ONE_ATMOSPHERE)
/// CAPABILITIES(/obj/e0_fixture/pump,
///   interface("E0Pump", title = "Gas Pump"), ui_shape(target_pressure),
///   op("set_pressure", ui_act(arg("pressure", from = nameof(target_pressure))), then(PROC_REF(set_pressure))))
/obj/e0_fixture/pump
	name = "e0 pump"
	var/target_pressure = 101.325

#endif
