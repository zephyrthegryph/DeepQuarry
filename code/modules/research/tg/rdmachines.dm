// The R&D machines' base (doc/rewrite/final_api.html section 16, doc/rewrite/conversion_guide.md): the protolathe, the circuit imprinter and the
// destructive analyzer.
//
// ONE CAPABILITIES list says what they share: a machine built from a board (behind the open panel a crowbar takes it apart: board_machine()), a
// wrench that frees it (2 seconds, the panel shut), a screwdriver panel with the R&D wiring behind it (the hack and the disable wires, a high
// voltage decoy), a part-replacer target, the item it holds (the analyzer's), and a window that the disable wire shuts. Its link to the
// techweb is its own: connected at init to the station's server, kept in `stored_research`.

MSG_DEF_SELF(rnd/disabled, "It does not respond.")

/obj/machinery/rnd
	name = "R&D Device"
	icon = 'icons/obj/machines/research_vr.dmi'
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE

	///Ref to global science techweb.
	var/datum/techweb/stored_research
	///The item loaded inside the machine, used by experimentors and destructive analyzers only (owned; spills when the machine dies).
	var/obj/item/loaded_item

/// The hacked designs are unlocked: the hack wire cut, or pulsed (lathe_wires()).
STAT(/obj/machinery/rnd, hacked, ANY)
/// The machine will not work: the disable wire cut, or pulsed (lathe_wires()).
STAT(/obj/machinery/rnd, disabled, ANY)

CAPABILITIES(/obj/machinery/rnd)
	machine_basics(repair = NONE, frame = board_machine())
	owns_one(nameof(loaded_item), on_destroy = ON_DESTROY_SPILL)
	panel()
	extend("panel.open", wait(0))
	extend("panel.open", then(PROC_REF(panel_toggled)))
	// three wires and five duds, every machine its own colours: the hack and the disable (a pulse flips them) and a high-voltage decoy
	wires(name = "R&D Machinery", count = 8, randomize = TRUE, by_hand = TRUE, status_lines = PROC_REF(wire_lights))
	lathe_wires()
	shock_wire(wire = WIRE_SHOCK)
	anchor()
	extend("anchor.toggle", wait(2 SECONDS), needs(req_closed(SPACE_PANEL)))
	on_change(nameof(anchored), ANY, then(PROC_REF(anchor_moved)))
	part_replacement()
	extend(TAG_UI, needs(req_is(STAT_DISABLED, FALSE, because = MSG(rnd/disabled))))

/obj/machinery/rnd/Initialize(mapload)
	. = ..()
	if(!stored_research)
		CONNECT_TO_RND_SERVER_ROUNDSTART(stored_research, src)
	if(stored_research)
		on_connected_techweb()

// the techweb logs the disconnection.
/obj/machinery/rnd/on_destroy(force)
	if(stored_research)
		log_research("[src] disconnected from techweb [stored_research] (destroyed).")
	..()

///Called when attempting to connect the machine to a techweb, forgetting the old.
/obj/machinery/rnd/proc/connect_techweb(datum/techweb/new_techweb)
	if(stored_research)
		log_research("[src] disconnected from techweb [stored_research] when connected to [new_techweb].")
	stored_research = new_techweb
	if(!isnull(stored_research))
		on_connected_techweb()

///Called post-connection to a new techweb.
/obj/machinery/rnd/proc/on_connected_techweb()
	SHOULD_CALL_PARENT(FALSE)

/// The panel was opened: whoever opened it sees the wires.
/obj/machinery/rnd/proc/panel_toggled(datum/act/op/A)
	if(panel_open(src))
		wires_open(src, A.actor)

/// Freed or bolted down, its power follows.
/obj/machinery/rnd/proc/anchor_moved(datum/act/A)
	power_change()

/obj/machinery/rnd/dismantle()
	var/obj/item/our_item = rel_take(src, nameof(loaded_item))
	if(our_item)
		our_item.forceMove(drop_location())
	. = ..()

// ---- the wires ----

/obj/machinery/rnd/proc/wire_lights()
	return list(
		"The red light is [disabled ? "off" : "on"].",
		"The blue light is [hacked ? "off" : "on"].")
