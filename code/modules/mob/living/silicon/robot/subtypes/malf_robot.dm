/mob/living/silicon/robot/malf
	lawupdate = FALSE
	scrambledcodes = TRUE
	modtype = "Malf"
	lawchannel = "State"
	braintype = "Drone"
	ui_theme = "malfunction"
	idcard_type = /obj/item/card/id/lost
	cell_type = /obj/item/cell/high // 15k cell, as recharging stations are a lot more rare on the Surface.

/mob/living/silicon/robot/malf/setup_brain()
	..()
	mmi = new /obj/item/mmi/digital/robot(src) // Explicitly a drone.
	updatename(modtype)
	playsound(src, 'sound/mecha/nominalsyndi.ogg', 75, 0)

/mob/living/silicon/robot/malf/setup_module()
	..()
	if(!restrict_modules_to)
		restrict_modules_to = GLOB.malf_module_types
