//Most interesting stuff happens in disperser_fire.dm
//This is just basic construction and deconstruction and the like

/obj/machinery/disperser
	name = "abstract parent for disperser"
	desc = "You should never see one of these, bap your mappers."
	icon = 'icons/obj/disperser.dmi'
	idle_power_usage = 200
	density = TRUE
	anchored = TRUE
	maintenance_flags = MACHINE_MAINT_STANDARD

// ALLOW(init/INSTANCE_STATE): takes the parts it was built with
/obj/machinery/disperser/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/disperser/examine(mob/user)
	. = ..()
	if(panel_open)
		to_chat(user, "The maintenance panel is open.")

/obj/machinery/disperser/proc/wrench_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(!panel_open)
		to_chat(user, span_notice("The maintenance panel must be screwed open for this!"))
		return OP_OK
	act_message(user, src, MSG_SELF(span_notice("You rotate %T% with %I%.")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " rotates %T% with %I%.")), \
		item = tool)
	set_dir(turn(dir, 90))
	play_sfx(src, SFX_ITEMS_JAWS_PRY)
	return OP_OK

/obj/machinery/disperser/proc/screwdriver_used(datum/act/op/A)
	return OP_DECLINE

CAPABILITIES(/obj/machinery/disperser)
	op("use_crowbar", tool(TOOL_CROWBAR), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(crowbar_used)))
	op("use_wrench", tool(TOOL_WRENCH), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(wrench_used)))
	op("use_screwdriver", tool(TOOL_SCREWDRIVER), priority(OP_PRIORITY_DEFAULT), wait(0), then(PROC_REF(screwdriver_used)))

/obj/machinery/disperser/proc/crowbar_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	if(default_part_replacement(user, tool))
		return OP_OK
	return OP_DECLINE

/obj/machinery/disperser/front
	name = "obstruction removal ballista beam generator"
	desc = "A complex machine which shoots concentrated material beams.\
		<br>A sign on it reads: <i>STAY CLEAR! DO NOT BLOCK!</i>"
	icon_state = "front"
	circuit = /obj/item/circuitboard/disperserfront

/obj/machinery/disperser/middle
	name = "obstruction removal ballista fusor"
	desc = "A complex machine which transmits immense amount of data \
		from the material deconstructor to the particle beam generator.\
		<br>A sign on it reads: <i>EXPLOSIVE! DO NOT OVERHEAT!</i>"
	icon_state = "middle"
	circuit = /obj/item/circuitboard/dispersermiddle
	// maximum_component_parts = list(/obj/item/stock_parts = 15)

/obj/machinery/disperser/back
	name = "obstruction removal ballista material deconstructor"
	desc = "A prototype machine which can deconstruct materials atom by atom.\
		<br>A sign on it reads: <i>KEEP AWAY FROM LIVING MATERIAL!</i>"
	icon_state = "back"
	circuit = /obj/item/circuitboard/disperserback
	density = FALSE
	layer = UNDER_JUNK_LAYER //So the charges go above us.
