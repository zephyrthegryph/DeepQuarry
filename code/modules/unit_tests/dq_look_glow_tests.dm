// Light as a look part (doc/rewrite/final_api.html section 13, "Light is a look part"): look.glow(range, power, color), GLOW(), GLOW_OFF and the
// look_glow() entry. The engine applies the light when the look is applied; a draw never calls set_glow().

/// A probe that declares its light: steady, or from a proc over a tracked colour.
/obj/structure/dq_glow_probe
	name = "glow probe"
	var/shade = "#ff0000"
	var/lit = TRUE

TRACKED(/obj/structure/dq_glow_probe, shade)
TRACKED(/obj/structure/dq_glow_probe, lit)

CAPABILITIES(/obj/structure/dq_glow_probe)
	look_glow(PROC_REF(probe_glow), when = nameof(lit))

/obj/structure/dq_glow_probe/proc/probe_glow(datum/act/A)
	return GLOW(3, 0.5, shade)

/// A probe whose draw names the light itself.
/obj/structure/dq_glow_drawn
	name = "drawn glow probe"
	var/strength = 0

TRACKED(/obj/structure/dq_glow_drawn, strength)

/obj/structure/dq_glow_drawn/draw(datum/look/look)
	..()
	if(strength < 0)
		look.glow(GLOW_OFF)
	else
		look.glow(strength, 1, "#00ff00")

/datum/unit_test/dq_look_glow
	abstract_type = /datum/unit_test/dq_look_glow

/datum/unit_test/dq_look_glow/builder_forms
/datum/unit_test/dq_look_glow/draw_light_applies
/datum/unit_test/dq_look_glow/entry_applies

/// The builder: numbers first is a light, a name first an emissive part, GLOW() and GLOW_OFF are values.
/datum/unit_test/dq_look_glow/builder_forms/Run()
	var/datum/look/look = new
	look.glow(2, 0.5, "#123456")
	TEST_ASSERT_EQUAL(json_encode(look.light_spec), json_encode(list(2, 0.5, "#123456")), "glow(range, power, color) is the light")
	TEST_ASSERT_NULL(look.parts, "and adds no part")
	look = new
	look.glow(GLOW(4, 1, "#abcdef"))
	TEST_ASSERT_EQUAL(json_encode(look.light_spec), json_encode(list(4, 1, "#abcdef")), "glow(GLOW()) is the same light")
	look = new
	look.glow(3)
	TEST_ASSERT_EQUAL(json_encode(look.light_spec), json_encode(list(3, 1, null)), "a bare range lights at power 1 in the holder's colour")
	look = new
	look.glow(0)
	TEST_ASSERT_NULL(look.light_spec, "a zero range names no light")
	look.glow(GLOW_OFF)
	TEST_ASSERT_EQUAL(json_encode(look.light_spec), json_encode(list(0, 0, null)), "GLOW_OFF names a dark look")
	look = new
	look.glow("screen", "on")
	TEST_ASSERT_NULL(look.light_spec, "a name first is the emissive part, not a light")
	TEST_ASSERT_EQUAL(length(look.parts), 1, "which it adds")
	var/datum/look/one = new
	one.glow(2, 1, "#ff0000")
	var/datum/look/two = new
	two.glow(2, 1, "#00ff00")
	TEST_ASSERT(one.change_key() != two.change_key(), "the light is part of the change key")

/// A draw's light reaches the holder, follows its tracked reads, and a dark look turns it off.
/datum/unit_test/dq_look_glow/draw_light_applies/Run()
	var/obj/structure/dq_glow_drawn/P = allocate(/obj/structure/dq_glow_drawn, test_floor())
	P.set_strength(3)
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(P).range, 3, "the draw's light is applied")
	TEST_ASSERT_EQUAL(glow_of(P).color, "#00ff00", "in its colour")
	TEST_ASSERT(P.light_on, "and it is on")
	P.set_strength(-1)
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(P).range, 0, "GLOW_OFF turns it off")
	P.set_strength(2)
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(P).range, 2, "a tracked read relights it")
	P.set_strength(0)
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(P).range, 0, "a look that names no light turns the earlier light off")

/// A look_glow() entry lights the holder from its proc, follows the proc's tracked reads and its condition.
/datum/unit_test/dq_look_glow/entry_applies/Run()
	var/obj/structure/dq_glow_probe/P = allocate(/obj/structure/dq_glow_probe, test_floor())
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(P).range, 3, "the declared light is applied at its first draw")
	TEST_ASSERT_EQUAL(glow_of(P).color, "#ff0000", "in the colour the proc read")
	P.set_shade("#0000ff")
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(P).color, "#0000ff", "a tracked var the proc reads redraws the light")
	P.set_lit(FALSE)
	refresh_flush()
	TEST_ASSERT_EQUAL(glow_of(P).range, 0, "the light goes out while its condition fails")
