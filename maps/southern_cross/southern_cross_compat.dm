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
