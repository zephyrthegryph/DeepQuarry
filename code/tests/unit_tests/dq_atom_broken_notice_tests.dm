// atom_break() overrides are on_notice(/datum/notice/machinery_broken | /datum/notice/atom_broken) reactions now.

/datum/unit_test/dq_atom_broken_grille

/datum/unit_test/dq_atom_broken_grille/Run()
	var/turf/T = dq_containment_floor()
	var/obj/structure/grille/grille = allocate(/obj/structure/grille, T)
	TEST_ASSERT(grille.density, "a whole grille is dense")
	grille.atom_break(MELEE)
	TEST_ASSERT(!grille.density, "a broken grille is a passable stub")
	TEST_ASSERT(grille.destroyed, "and is marked destroyed")

/datum/unit_test/dq_atom_broken_shieldgen

/datum/unit_test/dq_atom_broken_shieldgen/Run()
	var/turf/T = dq_containment_floor()
	var/obj/machinery/shieldgen/gen = allocate(/obj/machinery/shieldgen, T)
	TEST_ASSERT(!gen.malfunction, "a new shield generator works")
	TEST_ASSERT(gen.atom_break(MELEE), "breaking it flips it")
	TEST_ASSERT(gen.malfunction, "and a broken generator malfunctions")
