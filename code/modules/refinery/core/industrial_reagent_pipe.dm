/obj/machinery/reagent_refinery/pipe
	name = "Industrial Chemical Pipe"
	desc = "A large pipe made for transporting industrial chemicals."
	icon_state = "pipe"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_OFF // Does not require power for pipes
	idle_power_usage = 0
	active_power_usage = 0
	circuit = /obj/item/circuitboard/industrial_reagent_pipe
	default_max_vol = 60 // smoll

CAPABILITIES(/obj/machinery/reagent_refinery/pipe)
	without("reagent_refinery_set_transfer_amount")
	climb()

/obj/machinery/reagent_refinery/pipe/Initialize(mapload)
	. = ..()
	default_apply_parts()
	// Update neighbours and self for state
	update_neighbours()
	update_icon()

/obj/machinery/reagent_refinery/pipe/refinery_step()
	if(!anchored)
		return

	if(has_stat(BROKEN))
		return

	refinery_transfer()

DECLARE_APPEARANCE_PROC(/obj/machinery/reagent_refinery/pipe, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/machinery/reagent_refinery/pipe/appearance_overlays()
	. = list()
	if(anchored)
		. += update_input_connection_overlays("pipe_intakes")

/obj/machinery/reagent_refinery/pipe/handle_transfer(atom/origin_machine, datum/reagents/RT, source_forward_dir, transfer_rate, filter_id = "")
	// no back/forth, filters don't use just their forward, they send the side too!
	if(dir == GLOB.reverse_dir[source_forward_dir])
		return 0
	. = ..(origin_machine, RT, source_forward_dir, transfer_rate, filter_id)

/obj/machinery/reagent_refinery/pipe/examine(mob/user, infix, suffix)
	. = ..()
	. += "The meter shows [reagents.total_volume]u / [reagents.maximum_volume]u."
	tutorial(REFINERY_TUTORIAL_SINGLEOUTPUT|REFINERY_TUTORIAL_NOPOWER, .)

