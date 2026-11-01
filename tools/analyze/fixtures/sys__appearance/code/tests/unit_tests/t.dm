OM_FIELD(/obj/machinery/unit, utf, FALSE, CHANGE_UT)
APPEARANCE_TEMPLATE(/obj/machinery/unit, "u{utf}")

/obj/machinery/unit/update_icon()
	return

/obj/machinery/unit/proc/ut()
	set_utf(TRUE)
	update_icon()

/obj/machinery/widget/proc/ut_widget()
	set_on(TRUE)
	update_icon()
