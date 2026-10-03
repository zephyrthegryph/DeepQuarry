// Test-only types of the library capability tests (code/modules/unit_tests/dq_lib_*_tests.dm). Compiled under UNIT_TESTS only; each type declares the
// capability it exercises in the final form, as a house would.

#if defined(UNIT_TESTS) || defined(SPACEMAN_DMM)

/// Held containers: the reagent_container() capability on items.
/obj/item/lib_fixture
	name = "lib fixture item"

/// A lidded beaker (starts closed) and its larger configured sibling.
/obj/item/lib_fixture/beaker
	name = "lib beaker"

CAPABILITIES(/obj/item/lib_fixture/beaker, \
	reagent_container(volume = 60, transfer = list(5, 10, 15, 30, 60), lid = TRUE))

/obj/item/lib_fixture/beaker/large
	name = "lib large beaker"

CAPABILITIES(/obj/item/lib_fixture/beaker/large, \
	configure(reagent_container(volume = 120)))

/// A lidless flask: open from the start. It draws from a tap.
/obj/item/lib_fixture/flask
	name = "lib flask"

CAPABILITIES(/obj/item/lib_fixture/flask, \
	reagent_container(volume = 30, transfer = list(5, 10, 15, 30), taps = list(/obj/lib_fixture/tap)))

/// A syringe: the same capability with a needle, and one op changed with extend: a wait and an admin log.
/obj/item/lib_fixture/syringe
	name = "lib syringe"

CAPABILITIES(/obj/item/lib_fixture/syringe, \
	reagent_container(volume = 15, transfer = list(5, 10, 15), needle = TRUE), \
	extend("reagent_container.inject", wait(3 SECONDS), logs(LOG_ADMIN)))

/// A jug: every setting of reagent_container() is a var of the type, and it takes the lid off at the start, rests on tables and feeds others.
/obj/item/lib_fixture/jug
	name = "lib jug"
	var/capacity = 80
	var/per_transfer = 20
	var/least = 2
	var/most = 40
	var/list/contents_at_start = list(REAGENT_ID_WATER = 30)

CAPABILITIES(/obj/item/lib_fixture/jug, \
	reagent_container(volume = nameof(capacity), transfer_default = nameof(per_transfer), transfer_min = nameof(least), transfer_max = nameof(most), \
		starts = nameof(contents_at_start), lid = TRUE, starts_open = TRUE, rests_on = REAGENT_CONTAINER_CAN_BE_PLACED_INTO_DEFAULT, feed = TRUE, examine_range = 1, splash_mobs = FALSE))

/// A smaller jug with another start: the settings are changed on the var lines.
/obj/item/lib_fixture/jug/small
	name = "lib small jug"
	capacity = 25
	per_transfer = 5
	contents_at_start = null

/// A sprayer: it sprays one transfer at a time and does not pour.
/obj/item/lib_fixture/sprayer
	name = "lib sprayer"

CAPABILITIES(/obj/item/lib_fixture/sprayer, \
	reagent_container(volume = 30, transfer = list(5, 10), spray = TRUE))

/// An open tank: the capability on a bigger lidless holder, standing for any open container a transfer meets.
/obj/lib_fixture
	name = "lib fixture"

/obj/lib_fixture/tank
	name = "lib tank"
	flags = OPENCONTAINER

CAPABILITIES(/obj/lib_fixture/tank, 	reagent_container(volume = 100, transfer = list(5, 10)))

/// A tap: a closed tank that is drawn from, 10 units at a time.
/obj/lib_fixture/tap
	name = "lib tap"

CAPABILITIES(/obj/lib_fixture/tap, \
	reagent_container(volume = 100, transfer = list(10), lid = TRUE))

/// Stacks: stackable() on an item whose units are its `amount`.
/obj/item/lib_fixture/sheets
	name = "lib sheets"
	var/amount = 1
	var/max_amount = 10

CAPABILITIES(/obj/item/lib_fixture/sheets, \
	stackable(max_amount = 10))

/// Interiors: a container the actor can be put inside, and its escape.
/obj/lib_fixture/pod
	name = "lib pod"
	/// What the capability reads through escape_chance = nameof(chance_var).
	var/chance_var = 100

CAPABILITIES(/obj/lib_fixture/pod, \
	interior(escape_wait = 10 SECONDS, escape_chance = 100))

/obj/lib_fixture/pod/stubborn
	name = "lib stubborn pod"

CAPABILITIES(/obj/lib_fixture/pod/stubborn, \
	configure(interior(escape_chance = 0)))

/obj/lib_fixture/pod/by_var
	name = "lib var pod"

CAPABILITIES(/obj/lib_fixture/pod/by_var, \
	configure(interior(escape_chance = nameof(chance_var))))

/// Traits: a thing that is radiation protected by what it is, with a line saying so.
/obj/item/lib_fixture/hazmat
	name = "lib hazmat"

CAPABILITIES(/obj/item/lib_fixture/hazmat, \
	trait(TRAIT_RADIATION_PROTECTED_CLOTHING, examine = "A hazmat patch is sewn on."))

/// Natural weapons: a mob with no hands and a bite, and something to bite.
/mob/living/simple_mob/lib_fixture_biter
	name = "lib biter"
	has_hands = FALSE

CAPABILITIES(/mob/living/simple_mob/lib_fixture_biter, \
	natural_weapon(/datum/natural_weapon/bite, damage = 10))

/obj/lib_fixture/dummy
	name = "lib dummy"
	max_integrity = 100
	anchored = TRUE

/// Presentation: a type that declares examine lines and look layers of its own over a capability key.
/obj/lib_fixture/glow_box
	name = "lib glow box"
	var/lit = FALSE
	var/shown_note = "A note says hello."

TRACKED(/obj/lib_fixture/glow_box, lit)

CAPABILITIES(/obj/lib_fixture/glow_box, \
	examine_line("It is a box."), \
	examine_line(PROC_REF(note_line)), \
	examine_line("It glows.", when = nameof(lit)), \
	look_layer("glow", when = nameof(lit)), \
	look_layer("box"))

/obj/lib_fixture/glow_box/proc/note_line(datum/act/A)
	return shown_note

#endif
