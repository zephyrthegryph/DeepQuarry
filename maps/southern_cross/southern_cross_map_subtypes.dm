// Subtypes for Southern Cross map objects whose settings map lint forbids as
// var-edits (icons, SMES state). Each one carries exactly what the map used to
// set inline, so the loaded result is unchanged.

// --- SMES units -------------------------------------------------------------
// One subtype per distinct starting state used on the map. Name, RCon tag and
// coil count stay as map edits.

/obj/machinery/power/smes/buildable/auxiliary_main
	charge = 1e7
	input_level = 500000
	output_level = 500000

/obj/machinery/power/smes/buildable/charging
	input_attempt = TRUE

/obj/machinery/power/smes/buildable/engine_core
	charge = 2e6
	input_attempt = TRUE
	input_level = 100000
	output_level = 200000

/obj/machinery/power/smes/buildable/engine_main
	charge = 1e7
	input_attempt = TRUE
	input_level = 750000
	output_level = 750000

/obj/machinery/power/smes/buildable/point_of_interest/charging
	input_attempt = TRUE

/obj/machinery/power/smes/buildable/power_shuttle/active
	charge = 4e6
	input_attempt = TRUE
	inputting = TRUE
	outputting = TRUE

/obj/machinery/power/smes/buildable/power_shuttle/charging
	charge = 2e6
	input_attempt = TRUE
	inputting = TRUE

/obj/machinery/power/smes/buildable/precharged
	charge = 2e6
	input_attempt = TRUE

/obj/machinery/power/smes/buildable/precharged_large
	charge = 5e6
	input_attempt = TRUE
	input_level = 200000
	output_level = 200000

/obj/machinery/power/smes/buildable/reactor_auxiliary
	charge = 2e6
	input_attempt = TRUE
	input_level = 500000
	output_level = 350000

/obj/machinery/power/smes/buildable/reactor_main
	charge = 2e6
	input_attempt = TRUE
	input_level = 750000
	output_level = 750000

/obj/machinery/power/smes/buildable/solar
	input_attempt = TRUE
	input_level = 150000
	output_level = 100000

/obj/machinery/power/smes/buildable/substation_research
	charge = 1e7

/obj/machinery/power/smes/buildable/telecommunications_satellite
	charge = 6e6
	input_attempt = TRUE
	inputting = TRUE
	output_level = 250000

// --- Decorative appearances (mostly the CentCom level) ----------------------

/turf/unsimulated/floor/snow_decor
	name = "snow"
	icon = 'icons/turf/snow_new.dmi'
	icon_state = "snow"

/turf/unsimulated/floor/wood_appearance
	icon = 'icons/turf/flooring/wood.dmi'

/turf/unsimulated/wall/blast_door_appearance
	name = "Shuttle Bay Blast Door"
	desc = "That looks like it doesn't open easily."
	icon = 'icons/obj/doors/rapid_pdoor.dmi'
	icon_state = "pdoor1"

/turf/unsimulated/wall/maint_door_appearance
	name = "Sealed Door"
	icon = 'icons/obj/doors/Doormaint.dmi'
	icon_state = "door_closed"

/turf/unsimulated/wall/uranium_door_appearance
	name = "Sealed Door"
	icon = 'icons/obj/doors/Dooruranium.dmi'
	icon_state = "door_closed"

/obj/machinery/door/airlock/uranium_appearance
	icon = 'icons/obj/doors/Dooruranium.dmi'

/turf/simulated/shuttle/wall/no_join/orange
	icon = 'icons/turf/shuttle_orange.dmi'
	icon_state = "orange"
	base_state = "orange"

/obj/structure/showcase/ai_core_appearance
	icon = 'icons/mob/AI.dmi'
	icon_state = "ai-red"

/obj/item/radio/emergency_phone
	icon = 'icons/obj/items.dmi'
	icon_state = "red_phone"
