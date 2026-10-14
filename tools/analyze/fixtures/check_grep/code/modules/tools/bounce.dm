/obj/machinery/thing/screwdriver_act(mob/user, obj/item/I)
	if(x)
		return

	attackby(I, user)
	return TRUE

/obj/machinery/thing/crowbar_act_secondary(mob/user)
	I.attackby(x)

/obj/other/wrench_act(mob/user)
	var/x = 1
 	attackby(I)

/obj/other/multitool_act(mob/user)
	attackby(I) // ALLOW(check_grep): ok
