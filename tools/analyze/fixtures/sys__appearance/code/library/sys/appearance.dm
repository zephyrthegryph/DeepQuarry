/obj/machinery/widget/update_icon()
	return

/obj/machinery/widget/proc/appearance_overlays()
	add_overlay(x)
	set_on(1)

/obj/machinery/widget/proc/runtime_calls()
	set_on(TRUE)
	update_icon()
