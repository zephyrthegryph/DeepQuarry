// Types the Southern Cross map data references that were removed from the
// base tree after the fork. Defined here as thin subtypes so the hand-mapped
// station (southern_cross-*.dmm) and its kit lists compile and function.

// The merc "Skipjack" boarding craft's spawn area (used across southern_cross-6.dmm).
/area/skipjack_station/start
	name = "Skipjack"
	icon_state = "shuttlered"

// Southern Cross issue phase weapons, carried in station armory kits.
/obj/item/gun/energy/phasegun
	name = "phase pistol"
	desc = "A compact directed-energy sidearm."

/obj/item/gun/energy/phasegun/pistol

/obj/item/gun/energy/phasegun/rifle
	name = "phase rifle"
	desc = "A directed-energy longarm."

// High-tier stock parts used in Southern Cross machinery presets.
/obj/item/stock_parts/micro_laser/high
	name = "high-power micro-laser"
	rating = 2

/obj/item/stock_parts/matter_bin/super
	name = "super matter bin"
	rating = 3

// Codex reference book placed in Southern Cross offices.
/obj/item/book/codex/corp_regs
	name = "\improper NanoTrasen corporate regulations"

// Southern Cross armory/security ammunition boxes.
/obj/item/storage/box/stunshells
	name = "box of stun shells"

/obj/item/storage/box/stunshells/large
	name = "large box of stun shells"

/obj/item/storage/box/flashshells
	name = "box of flash shells"

/obj/item/storage/box/beanbags
	name = "box of beanbag shells"

/obj/item/storage/box/shotgunammo
	name = "box of shotgun slugs"

/obj/item/storage/box/shotgunammo/large
	name = "large box of shotgun slugs"

/obj/item/storage/box/shotgunshells
	name = "box of shotgun shells"

/obj/item/storage/box/blanks
	name = "box of blank shells"

// Circuitboards for the stubbed R&D machines above.
/obj/item/circuitboard/rdserver
	name = "circuit board (R&D server)"

/obj/item/circuitboard/protolathe
	name = "circuit board (protolathe)"

// --- Science / medical machines from frameworks the fork replaced ---
// The old baystation R&D (/obj/machinery/r_n_d/*, /computer/rdconsole/*) and
// disease2 virology systems were removed in favour of the tg R&D framework.
// Southern Cross's science/medical bays still map the old types, so these are
// inert placeholder stubs: the station boots and the rooms are walkable, but
// R&D, robotics and virology are non-functional pending a port to the current
// systems. Computers inherit the console sprite; the rest are bare markers.

/obj/machinery/computer/rdconsole
	name = "R&D console"
/obj/machinery/computer/rdconsole/core
/obj/machinery/computer/rdconsole/robotics
/obj/machinery/computer/diseasesplicer
	name = "disease splicer console"
/obj/machinery/computer/centrifuge
	name = "isolation centrifuge"

/obj/machinery/r_n_d
	name = "research machine"
	density = TRUE
	anchored = TRUE
/obj/machinery/r_n_d/circuit_imprinter
/obj/machinery/r_n_d/protolathe
/obj/machinery/r_n_d/destructive_analyzer
/obj/machinery/r_n_d/server
/obj/machinery/r_n_d/server/core
/obj/machinery/r_n_d/server/robotics

/obj/machinery/disease2
	name = "pathology machine"
	density = TRUE
	anchored = TRUE
/obj/machinery/disease2/isolator
/obj/machinery/disease2/incubator
/obj/machinery/disease2/diseaseanalyser

/obj/machinery/pros_fabricator
	name = "prosthetics fabricator"
	density = TRUE
	anchored = TRUE

/obj/item/antibody_scanner
	name = "antibody scanner"

/obj/item/virusdish
	name = "virus dish"
/obj/item/virusdish/random

// The engine-submap loader landmark; the engine-submap system was dropped with
// the quarry, so this is an inert marker (the engine room loads no engine).
/obj/effect/landmark/engine_loader
