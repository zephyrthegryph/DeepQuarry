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

/// The test-only capabilities: real CAPABILITY_TYPE definitions (E1), so grant(), revoke() and granted() work on them. A /datum/e0_cap is a
/// capability definition datum; its params are its vars.
/datum/e0_cap
	parent_type = /datum/capability

/// CAPABILITY_TYPE(mirror_plating, CAP_E0_MIRROR, /datum/capability/mirror, key = NONE, stacks = BEST(reflect_chance), reflect_chance = 30)
CAPABILITY_TYPE(e0_mirror_plating, CAP_E0_MIRROR, /datum/e0_cap/mirror, key = NONE, stacks = BEST(reflect_chance), reflect_chance = 30)
/datum/e0_cap/mirror

/// The mirror's hooks: a projectile hit is taken over with probability reflect_chance (one roll, drawn by the winning activation only).
/datum/e0_cap/mirror/entries()
	return list(extend(/datum/act/hit/projectile, instead(chance(reflect_chance), then(CAP_PROC(reflect)))))

/// The reflect handler: records the winning activation's source on the wearer (proof 2).
/datum/e0_cap/mirror/proc/reflect(datum/act/A)
	var/mob/living/simple_mob/e0_fixture/wearer = A.holder
	wearer.last_reflect_source = A.source

MSG_DEF_SELF(phase/phased, "You are phased out: you can act only through your abilities.")

/// The CAPABILITY_TYPE(phase_shift, CAP_PHASE_SHIFT, ...) of 16.9: an ability (menu() ops "phase_shift.shift" and "phase_shift.unshift")
/// that grants the phased capability on its own holder (density, invisibility, acts_via, every(1 SECOND) energy drain). The constructor is
/// e0_phase_shift (the final name is the shadekin's, phase 2); prefix = keeps the op keys the doc's.
CAPABILITY_TYPE(e0_phase_shift, CAP_PHASE_SHIFT, /datum/e0_cap/phase_shift, key = NONE, prefix = "phase_shift", cost = 50)
/datum/e0_cap/phase_shift

/datum/e0_cap/phase_shift/entries()
	return list(
		op("shift", label("Phase shift"), menu(button = "phase_shift", bind = "shift+f"), 			when(cond_not(CAP_PROC(is_phased))), 			costs(RES_DARK_ENERGY, cost), 			grants(/datum/e0_cap/phased, on = ON_HOLDER)), // the grant lands on the op's own holder, so its source is this activation: it ends with the ability
		op("unshift", label("Phase back in"), menu(button = "phase_shift", bind = "shift+f"), 			when(CAP_PROC(is_phased)), 			then(CAP_PROC(shift_back))))

/datum/e0_cap/phase_shift/proc/is_phased(datum/act/A)
	return granted(A.holder, /datum/e0_cap/phased)

/datum/e0_cap/phase_shift/proc/shift_back(datum/act/A)
	revoke(A.holder, /datum/e0_cap/phased, source = A.activation) // the same source grants() used

/// CAPABILITY_TYPE(phased, CAP_PHASED, /datum/capability/phased, key = NONE, drain = 1): density, invisibility, acts_via, every(1 SECOND).
CAPABILITY_TYPE(e0_phased, CAP_PHASED, /datum/e0_cap/phased, key = NONE, prefix = "phased", drain = 1)
/datum/e0_cap/phased

/datum/e0_cap/phased/entries()
	return list(
		contributes(STAT_DENSITY, FALSE, priority = PRIORITY_FORCE), // TOP: through walls and people
		contributes(STAT_INVISIBILITY, INVISIBILITY_SHADEKIN), // MAX
		contributes(STAT_ACTS_VIA, ORIGIN_VERB | ORIGIN_HOTKEY, reason = MSG(phase/phased)), // MASK_AND: abilities only, so the way back still works
		every(1 SECOND, then(CAP_PROC(drain_energy))))

/// A per-second drain that takes its energy in whole steps; when there is none it forces the unshift through the button's own op, whose
/// revoke ends the activation that owns this handler (the handler finishes first, nothing of it runs again).
/datum/e0_cap/phased/proc/drain_energy(datum/act/timer/A)
	var/mob/living/simple_mob/e0_fixture/H = A.holder
	var/wanted = ceil(drain * A.dt / (1 SECOND))
	if(res_spend(H, RES_DARK_ENERGY, wanted) < wanted)
		perform_op(H, H, "phase_shift.unshift", origin = ORIGIN_SYSTEM)

/// SPECIES_CAPABILITIES for a test species (a species grants capabilities, including hands(), while a mob's species relation names it).
/datum/e0_species
	var/name = "e0 species"

/// SPECIES_CAPABILITIES(/datum/e0_species/shifter, hands(), phase_shift())
/datum/e0_species/shifter
	name = "e0 shifter"

CAPABILITIES(/datum/e0_species/shifter)
	e0_phase_shift()

/// SPECIES_CAPABILITIES(/datum/e0_species/plain, hands())
/datum/e0_species/plain
	name = "e0 plain"

// ---- The actor and the wearer: a simple mob with the vars the proofs read ----

/// A test mob. ref_one(nameof(species), /datum/e0_species) and rel_grants(nameof(species)) are declared on it (a species change is a relation
/// write that grants and revokes what the new species declares), dark_energy
/// is the resource of 16.9 (TRACKED schema int(0, 100), default 100), and last_reflect_source is what the test-only mirror's reflect
/// handler writes its A.source into (proof 2).
/mob/living/simple_mob/e0_fixture
	name = "e0 fixture mob"
	has_hands = TRUE // a body that can hold things: its own hands() (below) is gated by it
	var/datum/e0_species/species
	var/dark_energy = 100
	/// Written by the reflect handler of the test-only mirror capability: the winning activation source.
	var/last_reflect_source

CAPABILITIES(/mob/living/simple_mob/e0_fixture)
	ref_one(nameof(species), /datum/e0_species)
	rel_grants(nameof(species))
	hands()

/// Delivers one beam hit to this mob as a world action: ACT_TRY(src, hit_projectile, packet), act_done(). Returns the act's
/// outcome (null when the hit was refused or taken over). The mirror's reflect handler runs inside ACT_TRY.
/mob/living/simple_mob/e0_fixture/proc/e0_beam_hit()
	var/datum/act/hit/projectile/H = ACT_TRY(src, hit_projectile, null)
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

/// The door of proof 1 and, three times over, of proof 6: one capability with one op that two inputs reach.
CAPABILITY_TYPE(e0_door, CAP_E0_DOOR, /datum/capability/e0_door, key = NONE)
cap_keys(CAP_E0_DOOR, OPEN = null)
/datum/capability/e0_door

/datum/capability/e0_door/entries()
	return list(op("toggle", inputs(hand(), ui_act("toggle")), toggles(E0_DOOR_OPEN), logs(LOG_GAME)))

/obj/e0_fixture
	name = "e0 fixture"
	anchored = TRUE

/obj/e0_fixture/door
	name = "e0 door"
	density = TRUE

/// density is a TOP stat: right the moment the door opens.
CAPABILITIES(/obj/e0_fixture/door)
	e0_door()
	when(E0_DOOR_OPEN, contributes(STAT_DENSITY, FALSE, priority = PRIORITY_FORCE))

// ---- Proof 4: the library terminal ----

/// The print op of 16.13 without its database step.
/obj/e0_fixture/library
	name = "e0 library terminal"
	var/selected_id = 0
	/// The id the print op's then() read through A.captured(nameof(selected_id)) (written by the handler), and what it logged.
	var/printed_id

TRACKED_SCHEMA(/obj/e0_fixture/library, selected_id, int(0), default = 0)

MSG_DEF_SELF(library/nothing_selected, "Nothing is selected.")

CAPABILITIES(/obj/e0_fixture/library)
	op("select", ui_act(arg("id", int(1))), then(PROC_REF(select_row)))
	op("print", ui_act(), needs(req_is(nameof(selected_id), because = MSG(library/nothing_selected))),
		confirms("Print the selected book?"), captures(nameof(selected_id)), then(PROC_REF(print_book)), logs(LOG_GAME))

/obj/e0_fixture/library/proc/select_row(datum/act/op/A, id)
	set_selected_id(id)
	return OP_OK

/obj/e0_fixture/library/proc/print_book(datum/act/op/A)
	var/captured_id = A.captured(nameof(selected_id))
	var/obj/item/e0_fixture/book/B = new(get_turf(src))
	B.book_id = captured_id
	printed_id = captured_id
	act_log(A, "printed book [captured_id]")
	return OP_OK

/// The variant whose print op reads the selection with resume = CANCEL_IF_CHANGED: the op ends refused, "it changed while you were deciding".
/obj/e0_fixture/library/strict
	name = "e0 strict library terminal"

CAPABILITIES(/obj/e0_fixture/library/strict)
	extend("print", captures(nameof(selected_id), resume = CANCEL_IF_CHANGED))

/// What the print op produces: carries the id the first actor confirmed.
/obj/item/e0_fixture/book
	name = "e0 book"
	var/book_id

// ---- Proof 5: the hopper ----

/// The fabricator hopper of 16.14.
/obj/e0_fixture/hopper
	name = "e0 hopper"

#define SLOT_HOPPER "hopper"

MSG_DEF(fab/loaded, "You load the sheets.", "%U% loads the sheets.")

CAPABILITIES(/obj/e0_fixture/hopper)
	slot(SLOT_HOPPER, accepts = list(/obj/item/e0_fixture/sheets), capacity = E0_HOPPER_CAPACITY)
	op("load", stack(/obj/item/e0_fixture/sheets, E0_SHEETS_PER_LOAD), wait(2 SECONDS), put_in(SLOT_HOPPER),
		says(MSG(fab/loaded)), logs(LOG_GAME))

/// The containment ledger's slot of the hopper: one slot, sheets counted in units.
/datum/relation_definition/slot/e0_hopper
	holder = /obj/e0_fixture/hopper
	slot_id = SLOT_HOPPER
	name = "hopper"
	is_default = TRUE
	capacity_model = SLOT_CAPACITY_UNITS
	capacity = E0_HOPPER_CAPACITY
	drop_policy = SLOT_DROP_SPILL

/datum/relation_definition/slot/e0_hopper/cost(atom/holder, atom/movable/thing)
	var/units = thing.vars["amount"]
	return isnum(units) ? units : 1

/obj/item/e0_fixture/sheets
	name = "e0 sheets"
	var/amount = 10

/// Kai's fill, landing inside Rae's wait: fills the hopper to capacity in one step. E1's slot(SLOT_HOPPER) and move_into() replace
/// the placeholder move; the fixture calls this one proc so the proof text does not change.
/obj/e0_fixture/hopper/proc/e0_fill_to_capacity(obj/item/e0_fixture/sheets/filler)
	filler.amount = E0_HOPPER_CAPACITY
	filler.forceMove(src)

// ---- Proof 7: the cabinet ----

/// A machine with a cover and a cell slot, for reach, containment and capability changes under cached menus. Its cover starts open and its bay
/// starts with a cell (so the first read of the bay lists the take op), and a crowbar pries a panel over five seconds: that op sits just above the
/// take op, which would otherwise take the cell for any click (take_out is the higher tier).
#define BAY_CABINET "cabinet"

/obj/e0_fixture/cabinet
	name = "e0 cabinet"
	var/obj/item/e0_fixture/cell/cell
	var/panel_open = FALSE

CAPABILITIES(/obj/e0_fixture/cabinet)
	cover(open = hand(), starts_open = TRUE)
	space(BAY_CABINET, door = CAP_COVER)
	cell_bay(nameof(cell), at = BAY_CABINET, accepts = /obj/item/e0_fixture/cell, starts = /obj/item/e0_fixture/cell)
	op("pry_panel", tool(TOOL_CROWBAR), priority(above("cell_bay.cell.take")), wait(5 SECONDS), toggles(nameof(panel_open)))

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
/obj/e0_fixture/lamp
	name = "e0 lamp"

STAT(/obj/e0_fixture/lamp, e0_lamp_range, MAX)

CAPABILITIES(/obj/e0_fixture/lamp)
	contributes(STAT_E0_LAMP_RANGE, PROC_REF(lit_range))

/// What the lamp reads: the night range while the night system says night, the day range otherwise.
/obj/e0_fixture/lamp/proc/lit_range(datum/act/A)
	return e0_night_active() ? E0_LAMP_NIGHT_RANGE : E0_LAMP_DAY_RANGE

/// The test-only system of proof 8 and the flag it owns (a lazy system: the kernel does not boot it).
/datum/system/e0_night
	name = "e0 night"
	lazy_only = TRUE
	var/night = FALSE

TRACKED(/datum/system/e0_night, night)

GLOBAL_DATUM_INIT(e0_night_service, /datum/system/e0_night, new)

SYSTEM_ACCESSOR(e0_night, e0_night_active, nameof(night))

/// Flips the night flag (set_night(TRUE)): the marked cascade starts.
/proc/e0_flip_night(night = TRUE)
	GLOB.e0_night_service.set_night(night)

/// The notice chain of proof 8: a listener whose on_notice handler publishes the next notice and counts itself. A FIXED action, so PUBLISH sends it.
ACTION(e0_chain, hop, FIXED, notice = /datum/notice/e0_chain)

/// The listener of the chain: hears each hop and publishes the next until `length`.
/datum/e0_chain_node
	var/length = 0

CAPABILITIES(/datum/e0_chain_node)
	on_notice(/datum/notice/e0_chain, then(PROC_REF(hear)))

/datum/e0_chain_node/proc/hear(datum/act/A)
	var/datum/notice/e0_chain/N = A
	GLOB.e0_chain_handled++
	if(N.hop < length)
		PUBLISH(src, e0_chain, hop = N.hop + 1)
	else
		GLOB.e0_chain_node = null // the listener is let go with the end of the chain

GLOBAL_VAR(e0_chain_node)

/// Starts a chain of `length` notices: each handler publishes the next, synchronously, so the depth is the chain's own.
/proc/e0_start_notice_chain(length)
	var/datum/e0_chain_node/node = new
	node.length = length
	GLOB.e0_chain_node = node
	PUBLISH(node, e0_chain, hop = 1)

/// Notices the chain's handler counted: the proof compares it with test_notice_count().
GLOBAL_VAR_INIT(e0_chain_handled, 0)

// ---- Proof 9: the door assembly ----

/// A test-only type with construction(GRAPH_DOOR_ASSEMBLY) (section 12): the graph is declared in e1_fixtures.dm (every edge instant, so a click is
/// one step), and the board of the boarded stage goes into the assembly's construction slot.
/obj/e0_fixture/door_assembly
	name = "e0 door assembly"

/// The boarded stage puts the board in the assembly's construction slot, declared as an entry (four things at most).
CAPABILITIES(/obj/e0_fixture/door_assembly)
	construction(GRAPH_DOOR_ASSEMBLY)
	slot(SLOT_CONSTRUCTION, capacity = 4)

/// A subtype placed finished. Two paths lead from the frame to finished, so the type names which one the history is seeded along.
/obj/e0_fixture/door_assembly/finished
	name = "e0 finished door assembly"

CAPABILITIES(/obj/e0_fixture/door_assembly/finished)
	configure(construction_graph(start = STAGE_DOOR_FINISHED, via = list(STAGE_DOOR_WIRED, STAGE_DOOR_BOARDED)))

/// The board the boarded stage takes: item(/obj/item/e0_fixture/board) with put_in(SLOT_CONSTRUCTION).
/obj/item/e0_fixture/board
	name = "e0 airlock board"

/// The prefab kit that skips the board: item(/obj/item/e0_fixture/door_kit) with consumes(), from = STAGE_DOOR_WIRED, key = "kit".
/obj/item/e0_fixture/door_kit
	name = "e0 door kit"

// ---- Proof 10: the pump ----

/obj/e0_fixture/pump
	name = "e0 pump"
	var/target_pressure = 101

TRACKED_SCHEMA(/obj/e0_fixture/pump, target_pressure, num(0, MAX_PUMP_PRESSURE, step = 1), default = 101)

CAPABILITIES(/obj/e0_fixture/pump)
	interface("E0Pump", title = "Gas Pump")
	ui_shape(target_pressure)
	op("set_pressure", ui_act(arg("pressure", from = nameof(target_pressure))), then(PROC_REF(set_pressure)))

/obj/e0_fixture/pump/proc/set_pressure(datum/act/op/A, pressure)
	set_target_pressure(pressure)
	return OP_OK

#endif
