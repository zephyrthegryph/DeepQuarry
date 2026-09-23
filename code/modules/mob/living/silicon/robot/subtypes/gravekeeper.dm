/mob/living/silicon/robot/malf/gravekeeper
	icon_state = "drone-lost"
	modtype = "Gravekeeper"
	can_be_antagged = FALSE
	restrict_modules_to = list("Gravekeeper")

/mob/living/silicon/robot/malf/gravekeeper/setup_laws()
	..()
	laws = new /datum/ai_laws/gravekeeper()

/mob/living/silicon/robot/malf/gravekeeper/setup_module()
	..()
	module = new /obj/item/robot_module/robot/malf/gravekeeper(src)
