/proc/istype_fx(I)
	if(istype(I, /obj/item/tool/wrench))
	if(istype(I,/obj/item/weldingtool))
	if(istype(I, /obj/item/multitool/x))
	if(istype(I, /obj/item/toolbox))
	x = I.is_wrench()
	x = I.is_wrenches()
	x = I.is_welder()
	if(istype(I, /obj/item/tool)) // ALLOW(check_grep): ok
