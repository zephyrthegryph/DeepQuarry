/obj/machinery/x/proc/y(mob/user, obj/item/I)
	user.drop_item()
	own_set(src, nameof(src.cell), I)
