// The reagent container capability (code/datums/capabilities/library/reagent_container.dm).

/// Lidless, takes pouring and gives it, three amounts.
/obj/cap_fixture/reagent_vat/capabilities()
	. = ..()
	. += reagent_container(volume = 100, transfer_amounts = list(10, 20, 50))

/// A lidded jar that cycles its amount.
/obj/cap_fixture/reagent_jar/capabilities()
	. = ..()
	. += reagent_container(volume = 60, transfer_amounts = list(5, 10), open_lid = TRUE, cycle_transfer = TRUE)

/// A tank: only fills other containers.
/obj/cap_fixture/reagent_tank/capabilities()
	. = ..()
	. += reagent_container(volume = 200, fillable = FALSE)

/// A held capability container whose contents can't be splashed.
/obj/item/cap_fixture_flask
	name = "test flask"

/obj/item/cap_fixture_flask/capabilities()
	. = ..()
	. += reagent_container(volume = 30, splashable = FALSE)

/// Makes B (an allocated legacy beaker) hold `amount` water, pouring 10 at a time.
/proc/dxr_beaker(obj/item/reagent_containers/glass/beaker/B, amount)
	B.amount_per_transfer_from_this = 10
	if(amount)
		B.reagents.add_reagent(REAGENT_ID_WATER, amount)
	return B

/// Init makes the reagents; a lidless container is open; examine and the fill gauge follow the
/// reagents even when they change outside a dispatched call.
/datum/unit_test/dx_cap_reagent_container_basics/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/reagent_vat/vat = allocate(/obj/cap_fixture/reagent_vat, T)
	TEST_ASSERT_NOTNULL(vat.reagents, "the capability made a reagent holder")
	TEST_ASSERT_EQUAL(vat.reagents.maximum_volume, 100, "of the declared volume")
	TEST_ASSERT(vat.cap_state & CAP_LID_OPEN, "a lidless container is open")
	TEST_ASSERT(vat.is_open_container(), "and is_open_container() says so")
	TEST_ASSERT_NULL(dxs_entry(vat, "reagents:lid"), "a lidless container offers no lid entry")
	TEST_ASSERT("It is empty. It holds 100 units." in vat.caps_examine(H), "examine shows an empty container")
	refresh_flush()
	TEST_ASSERT(dxs_has_layer(vat, "fill0"), "the empty gauge is drawn")
	vat.reagents.add_reagent(REAGENT_ID_WATER, 50)
	refresh_flush()
	TEST_ASSERT(dxs_has_layer(vat, "fill2"), "a reagent change outside dispatch redraws the gauge")
	TEST_ASSERT(!dxs_has_layer(vat, "fill0"), "and the old step is gone")
	TEST_ASSERT("It contains 50 of 100 units." in vat.caps_examine(H), "examine shows the volume")
	TEST_ASSERT_EQUAL(refresh_check_drift(vat), FALSE, "the look has no drift")

/// Pour in from a held container, Fill from a tank, and which of the two is offered.
/datum/unit_test/dx_cap_reagent_container_pour_fill/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/reagent_vat/vat = allocate(/obj/cap_fixture/reagent_vat, T)
	var/obj/cap_fixture/reagent_tank/tank = allocate(/obj/cap_fixture/reagent_tank, T)
	var/obj/item/reagent_containers/glass/beaker/full = dxr_beaker(allocate(/obj/item/reagent_containers/glass/beaker, T), 30)
	var/obj/item/reagent_containers/glass/beaker/empty = dxr_beaker(allocate(/obj/item/reagent_containers/glass/beaker, T), 0)
	var/datum/interaction/capability/pour_in = dxs_entry(vat, "reagents:pour_in")
	var/datum/interaction/capability/vat_fill = dxs_entry(vat, "reagents:fill_from")
	var/datum/interaction/capability/tank_fill = dxs_entry(tank, "reagents:fill_from")
	TEST_ASSERT_NOTNULL(pour_in, "a fillable container offers Pour in")
	TEST_ASSERT_NULL(dxs_entry(tank, "reagents:pour_in"), "a tank that takes no pouring offers no Pour in")
	TEST_ASSERT_NOTNULL(tank_fill, "a pourable container offers Fill from")
	TEST_ASSERT_EQUAL(pour_in.why_not(H, vat, empty), "\the [empty] is empty", "an empty held container has nothing to pour")
	TEST_ASSERT_NOTNULL(vat_fill.why_not(H, vat, full), "a full held container pours into a fillable one, never fills from it")
	TEST_ASSERT(pour_in.perform(H, vat, full), "Pour in runs")
	TEST_ASSERT_EQUAL(vat.reagents.total_volume, 10, "the held container's transfer amount went in")
	TEST_ASSERT_EQUAL(full.reagents.total_volume, 20, "and left the beaker")
	tank.reagents.add_reagent(REAGENT_ID_WATER, 100)
	TEST_ASSERT(tank_fill.perform(H, tank, empty), "Fill from the tank runs")
	TEST_ASSERT_EQUAL(empty.reagents.total_volume, 5, "the tank's own transfer amount came out")
	empty.flags &= ~OPENCONTAINER
	TEST_ASSERT_EQUAL(tank_fill.why_not(H, tank, empty), "\the [empty] is closed", "a closed held container can't be filled")

/// The lid: bit, name by state, examine, overlay and the refusals it causes.
/datum/unit_test/dx_cap_reagent_container_lid/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/reagent_jar/jar = allocate(/obj/cap_fixture/reagent_jar, T)
	var/obj/item/reagent_containers/glass/beaker/full = dxr_beaker(allocate(/obj/item/reagent_containers/glass/beaker, T), 30)
	var/datum/interaction/capability/lid = dxs_entry(jar, "reagents:lid")
	var/datum/interaction/capability/pour_in = dxs_entry(jar, "reagents:pour_in")
	TEST_ASSERT_NOTNULL(lid, "a lidded container offers the lid")
	TEST_ASSERT(!jar.is_open_container(), "the jar starts closed")
	TEST_ASSERT_EQUAL(lid.display_name(H, jar), "Open lid", "named for opening while closed")
	TEST_ASSERT("Its lid is closed." in jar.caps_examine(H), "examine says the lid is closed")
	TEST_ASSERT_EQUAL(pour_in.why_not(H, jar, full), "\the [jar] is closed", "a closed jar refuses pouring")
	refresh_flush()
	TEST_ASSERT(dxs_has_layer(jar, "lid"), "the lid overlay is drawn")
	TEST_ASSERT(lid.perform(H, jar, null), "opening the lid runs")
	TEST_ASSERT(jar.cap_state & CAP_LID_OPEN, "the bit is set")
	TEST_ASSERT(jar.is_open_container(), "is_open_container() follows the bit")
	TEST_ASSERT_EQUAL(lid.display_name(H, jar), "Close lid", "named for closing while open")
	TEST_ASSERT_NULL(pour_in.why_not(H, jar, full), "an open jar takes pouring")
	refresh_flush()
	TEST_ASSERT(!dxs_has_layer(jar, "lid"), "the lid overlay is gone")

/// Set transfer amount: the form's handler validates, the cycle steps.
/datum/unit_test/dx_cap_reagent_container_amount/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/reagent_vat/vat = allocate(/obj/cap_fixture/reagent_vat, T)
	var/obj/cap_fixture/reagent_jar/jar = allocate(/obj/cap_fixture/reagent_jar, T)
	var/datum/interaction/capability/vat_amount = dxs_entry(vat, "reagents:amount")
	var/datum/interaction/capability/jar_amount = dxs_entry(jar, "reagents:amount")
	TEST_ASSERT_EQUAL(length(vat_amount?.form), 1, "the vat asks with a form")
	TEST_ASSERT(!length(jar_amount?.form), "the cycling jar doesn't ask")
	TEST_ASSERT_EQUAL(reagent_transfer_amount(vat), 10, "the default is the first amount")
	TEST_ASSERT_EQUAL(jointext(vat.cap_reagent_amount_choices(H), ","), "10,20,50", "the choices are the declared amounts")
	TEST_ASSERT(vat.cap_reagent_set_amount(H, null, amount = "20"), "a valid choice is taken")
	TEST_ASSERT_EQUAL(reagent_transfer_amount(vat), 20, "and becomes the transfer amount")
	TEST_ASSERT_EQUAL(vat.cap_reagent_set_amount(H, null, amount = "7"), UI_REFUSED, "an undeclared amount is refused")
	TEST_ASSERT_EQUAL(reagent_transfer_amount(vat), 20, "and changes nothing")
	TEST_ASSERT(jar_amount.perform(H, jar, null), "the cycle runs")
	TEST_ASSERT_EQUAL(reagent_transfer_amount(jar), 10, "to the next amount")
	TEST_ASSERT(jar_amount.perform(H, jar, null), "and again")
	TEST_ASSERT_EQUAL(reagent_transfer_amount(jar), 5, "wrapping around")

/// Splash: only with help intent off, only splashable contents, and the held-side API.
/datum/unit_test/dx_cap_reagent_container_splash/Run()
	var/turf/T = run_loc_floor_bottom_left
	var/mob/living/carbon/human/H = allocate(/mob/living/carbon/human, T)
	var/obj/cap_fixture/reagent_vat/vat = allocate(/obj/cap_fixture/reagent_vat, T)
	var/obj/item/reagent_containers/glass/beaker/full = dxr_beaker(allocate(/obj/item/reagent_containers/glass/beaker, T), 20)
	var/obj/item/cap_fixture_flask/flask = allocate(/obj/item/cap_fixture_flask, T)
	flask.reagents.add_reagent(REAGENT_ID_WATER, 10)
	var/datum/interaction/capability/splash = dxs_entry(vat, "reagents:splash:[I_HURT]")
	TEST_ASSERT_NOTNULL(splash, "a container offers Splash")
	H.set_use_stance(I_HELP)
	TEST_ASSERT_NOTNULL(splash.why_not(H, vat, full), "with help intent on, Splash isn't offered")
	H.set_use_stance(I_HURT)
	TEST_ASSERT_NULL(splash.why_not(H, vat, full), "with help intent off, a full beaker can splash")
	TEST_ASSERT_EQUAL(splash.why_not(H, vat, flask), "\the [flask] can't be splashed", "unsplashable contents are refused")
	TEST_ASSERT(splash.perform(H, vat, full), "Splash runs")
	TEST_ASSERT_EQUAL(full.reagents.total_volume, 0, "the beaker is emptied")
	TEST_ASSERT(!flask.cap_reagent_splash_onto(H, T), "the held-side API refuses unsplashable contents")
	var/obj/item/reagent_containers/glass/beaker/more = dxr_beaker(allocate(/obj/item/reagent_containers/glass/beaker, T), 10)
	TEST_ASSERT(more.cap_reagent_splash_onto(H, T), "the held-side API splashes a legacy beaker onto a turf")
	TEST_ASSERT_EQUAL(more.reagents.total_volume, 0, "and empties it")
	H.set_use_stance(I_HELP)
