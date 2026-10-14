/obj/machinery/foo/take_damage(x)
/obj/machinery/foo/fall_apart()
/obj/foo/take_damage(x)
/obj/machinery/foo/other()
/obj/machinery/foo/take_damage(x) // ALLOW(check_grep): ok
/obj/machinery/m1/attackby(obj/item/I, mob/user)
	if(I.has_tool_quality(TOOL_WRENCH))
		return 1
	return ..()

/obj/machinery/m2/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/multitool))
		return 1

/obj/machinery/m3/attackby(obj/item/I, mob/user)
	return ..()

/obj/machinery/m4/attackby(obj/item/I, mob/user)
	if(default_deconstruction_crowbar(I))
		return 1

/obj/machinery/m5/attackby(obj/item/I, mob/user)
	x = alarm_deconstruction_wirecutters(I)
y = default_deconstruction_screwdriver(I)

