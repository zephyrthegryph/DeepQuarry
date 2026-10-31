/mob/living/silicon/robot/malf/gravekeeper
	icon_state = "drone-lost"
	modtype = "Gravekeeper"
	restrict_modules_to = list("Gravekeeper")

CAPABILITIES(/mob/living/silicon/robot/malf/gravekeeper)
	configure(mob_kind(can_be_antagged = FALSE))

/mob/living/silicon/robot/malf/gravekeeper/setup_laws()
	..()
	rel_set(src, nameof(laws), new /datum/ai_laws/gravekeeper())

/mob/living/silicon/robot/malf/gravekeeper/setup_module()
	..()
	rel_set(src, nameof(module), new /obj/item/robot_module/robot/malf/gravekeeper(src))
