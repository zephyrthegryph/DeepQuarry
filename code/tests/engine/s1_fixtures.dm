// The fixtures of the slots and inventory step (doc/rewrite/final_api.html, section 6 "Containment and slots", section 8 "providers", section 10
// "while_slotted", section 11 "SPECIES_CAPABILITIES, hands()"): holders with real ledger slots whose items and occupants get hooks while they are
// slotted, species that grant providers and hooks, a transfer that has requirements on both sides, a type-level every() and an on_change across a
// relation hop. Test-only types, compiled under UNIT_TESTS only (code/modules/unit_tests/dq_s1_slots_tests.dm drives them).

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

MSG_DEF_SELF(s1/no_trinkets, "It only takes gizmos.")
MSG_DEF_SELF(s1/welded, "It is welded in.")
MSG_DEF_SELF(s1/not_the_steward, "Only the steward may do that.")

/// The amount an e4_strike on `E` ends with (what its hooks made of `amount`): the argument itself when nothing hooks the action.
/proc/s1_strike(datum/E, amount = 10)
	var/datum/act/e4_strike/F = ACT_TRY(E, e4_strike, amount)
	if(isnull(F))
		return null
	. = ACT_FINAL(F, amount, amount)
	act_done(F)

// ---- holders with real slots ----

/// A rack: two slots, "s1_main" (the default) and "s1_side", nothing refused. An occupant of s1_main has the rack's +4 on a strike.
/obj/s1_fixture/rack
	name = "s1 rack"
	var/removed_heard = 0
	var/inserted_heard = 0
	/// Welded: a needs() on the remove action refuses a transfer out.
	var/welded = FALSE

/datum/om/relation/slot/s1_main
	holder = /obj/s1_fixture/rack
	slot_id = "s1_main"
	name = "main"
	is_default = TRUE

/datum/om/relation/slot/s1_side
	holder = /obj/s1_fixture/rack
	slot_id = "s1_side"
	name = "side"

CAPABILITIES(/obj/s1_fixture/rack)
	while_slotted("s1_main", extend(/datum/act/e4_strike, adjusts("amount", by = 4)), on = ON_CONTENTS)
	extend(/datum/act/remove, needs(req_bool(PROC_REF(not_welded), because = MSG(s1/welded))))
	on_notice(/datum/notice/removed, then(PROC_REF(heard_removed)))
	on_notice(/datum/notice/inserted, then(PROC_REF(heard_inserted)))

TRACKED(/obj/s1_fixture/rack, welded)

/obj/s1_fixture/rack/proc/not_welded(datum/act/A)
	return !welded

/obj/s1_fixture/rack/proc/heard_removed(datum/act/A)
	removed_heard++

/obj/s1_fixture/rack/proc/heard_inserted(datum/act/A)
	inserted_heard++

/// A rack that takes only gizmos, only from its steward, and has room for one. (An insert needs() is a hook of the holder; the capacity is the slot's.)
/obj/s1_fixture/picky
	name = "s1 picky rack"
	var/mob/steward
	var/removed_heard = 0
	var/inserted_heard = 0
	var/welded = FALSE

/datum/om/relation/slot/s1_picky
	holder = /obj/s1_fixture/picky
	slot_id = "s1_picky"
	name = "picky"
	is_default = TRUE
	capacity_model = SLOT_CAPACITY_COUNT
	capacity = 1

CAPABILITIES(/obj/s1_fixture/picky)
	ref_one(nameof(steward), /mob)
	extend(/datum/act/insert, needs(req_bool(PROC_REF(takes_gizmos_only), because = MSG(s1/no_trinkets))), needs(req_bool(PROC_REF(actor_is_steward), because = MSG(s1/not_the_steward))))
	extend(/datum/act/remove, needs(req_bool(PROC_REF(not_welded), because = MSG(s1/welded))))
	on_notice(/datum/notice/removed, then(PROC_REF(heard_removed)))
	on_notice(/datum/notice/inserted, then(PROC_REF(heard_inserted)))

TRACKED(/obj/s1_fixture/picky, welded)

/obj/s1_fixture/picky/proc/takes_gizmos_only(datum/act/A)
	var/datum/act/insert/F = A
	return istype(F.item, /obj/item/s1_fixture/gizmo)

/obj/s1_fixture/picky/proc/actor_is_steward(datum/act/A)
	var/datum/act/action/F = A
	return isnull(steward) || F.actor == steward

/obj/s1_fixture/picky/proc/not_welded(datum/act/A)
	return !welded

/obj/s1_fixture/picky/proc/heard_removed(datum/act/A)
	removed_heard++

/obj/s1_fixture/picky/proc/heard_inserted(datum/act/A)
	inserted_heard++

// ---- what the holders hold ----

/obj/item/s1_fixture
	name = "s1 item"

/// +1 on a strike to the rack it sits in, while it sits in the rack's main slot (and nowhere else).
/obj/item/s1_fixture/gizmo
	name = "s1 gizmo"
	slot_flags = SLOT_BELT

CAPABILITIES(/obj/item/s1_fixture/gizmo)
	while_slotted("s1_main", extend(/datum/act/e4_strike, adjusts("amount", by = 1)), on = ON_HOLDER)

/// Not a gizmo.
/obj/item/s1_fixture/trinket
	name = "s1 trinket"

/// Worn gear: +2 on a strike to whoever wears it, in any worn slot. Held, it does nothing.
/obj/item/s1_fixture/charm
	name = "s1 charm"
	slot_flags = SLOT_BELT

CAPABILITIES(/obj/item/s1_fixture/charm)
	while_slotted(SLOT_ANY_WORN, extend(/datum/act/e4_strike, adjusts("amount", by = 2)), on = ON_HOLDER)

/// Held gear: +3 on a strike to whoever holds it in a hand.
/obj/item/s1_fixture/torch
	name = "s1 torch"

CAPABILITIES(/obj/item/s1_fixture/torch)
	while_slotted(SLOT_ANY_HELD, extend(/datum/act/e4_strike, adjusts("amount", by = 3)), on = ON_HOLDER)

/// A belly whose prey get +5 on a strike while they are inside it.
/obj/belly/s1_test

CAPABILITIES(/obj/belly/s1_test)
	while_slotted(BELLY_SLOT_INTERIOR, extend(/datum/act/e4_strike, adjusts("amount", by = 5)), on = ON_CONTENTS)

// ---- providers ----

/// A held spear: it reaches two tiles and attacks. Provided only while it is the held item.
/obj/item/s1_fixture/spear
	name = "s1 spear"

CAPABILITIES(/obj/item/s1_fixture/spear)
	provides(AFF_ATTACK, reach = 2)

/// A worn gauntlet: its wearer manipulates one tile away for as long as it is worn.
/obj/item/s1_fixture/gauntlet
	name = "s1 gauntlet"
	slot_flags = SLOT_BELT

CAPABILITIES(/obj/item/s1_fixture/gauntlet)
	while_slotted(SLOT_ANY_WORN, provides(AFF_MANIPULATE, reach = 1), on = ON_HOLDER)

// ---- species ----

/// A test species a mob names through a relation: what its own CAPABILITIES list says is what the mob gets while it names it.
/datum/s1_species
	var/name = "s1 species"

/// Hands, and a hook of its own (+6 on a strike).
/datum/s1_species/brawler
	name = "s1 brawler"

CAPABILITIES(/datum/s1_species/brawler)
	hands()
	extend(/datum/act/e4_strike, adjusts("amount", by = 6))

/// Nothing at all.
/datum/s1_species/blob
	name = "s1 blob"

/// A simple mob that can hold things and has no hands of its own: its species decides.
/mob/living/simple_mob/s1_fixture
	name = "s1 fixture mob"
	has_hands = TRUE
	var/datum/s1_species/species

CAPABILITIES(/mob/living/simple_mob/s1_fixture)
	ref_one(nameof(species), /datum/s1_species)
	rel_grants(nameof(species))

/// The same with a body that cannot hold anything: a species' hands() is gated by the body.
/mob/living/simple_mob/s1_fixture_handless
	name = "s1 handless mob"
	has_hands = FALSE
	var/datum/s1_species/species

CAPABILITIES(/mob/living/simple_mob/s1_fixture_handless)
	ref_one(nameof(species), /datum/s1_species)
	rel_grants(nameof(species))

// ---- type-level every() ----

/// Two type-level every() entries: one runs every second, one every two seconds while it is powered.
/obj/s1_fixture/ticker
	name = "s1 ticker"
	var/powered = FALSE
	var/ticks = 0
	var/slow_ticks = 0

CAPABILITIES(/obj/s1_fixture/ticker)
	every(1 SECOND, then(PROC_REF(tick)))
	every(2 SECONDS, then(PROC_REF(slow_tick)), when = "powered")

/obj/s1_fixture/ticker/proc/tick(datum/act/timer/A)
	ticks++

/obj/s1_fixture/ticker/proc/slow_tick(datum/act/timer/A)
	slow_ticks++

/// A subtype adds its own and keeps the parent's.
/obj/s1_fixture/ticker/fast
	name = "s1 fast ticker"
	var/fast_ticks = 0

CAPABILITIES(/obj/s1_fixture/ticker/fast)
	every(5, then(PROC_REF(fast_tick)))

/obj/s1_fixture/ticker/fast/proc/fast_tick(datum/act/timer/A)
	fast_ticks++

// ---- on_change across a relation hop ----

/// The far end: a tracked charge.
/obj/s1_fixture/terminal
	name = "s1 terminal"
	var/charge = 0

TRACKED(/obj/s1_fixture/terminal, charge)

/// Its on_change names the far var through the relation, terminal.charge.
/obj/s1_fixture/meter
	name = "s1 meter"
	var/obj/s1_fixture/terminal/terminal
	var/seen_charge
	var/changes_seen = 0

CAPABILITIES(/obj/s1_fixture/meter)
	ref_one(nameof(terminal), /obj/s1_fixture/terminal)
	on_change(nameof(terminal.charge), ANY, then(PROC_REF(charge_changed)))

/obj/s1_fixture/meter/proc/charge_changed(datum/act/A)
	changes_seen++
	seen_charge = terminal?.charge

/// The same path read by a hook granted at runtime (an activation's), so it has no on_change of its own.
/obj/s1_fixture/bare_meter
	name = "s1 bare meter"
	var/obj/s1_fixture/terminal/terminal
	var/seen_charge
	var/changes_seen = 0

CAPABILITIES(/obj/s1_fixture/bare_meter)
	ref_one(nameof(terminal), /obj/s1_fixture/terminal)

/obj/s1_fixture/bare_meter/proc/charge_changed(datum/act/A)
	changes_seen++
	seen_charge = terminal?.charge

#endif
