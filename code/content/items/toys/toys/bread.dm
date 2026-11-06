/obj/item/reagent_containers/food/snacks/slice/bread
	var/toasted = FALSE

/obj/item/reagent_containers/food/snacks/slice/bread/afterattack(atom/A, mob/user as mob, proximity)
	if(istype(A, /obj/item/toy/plushie/ipc) && !toasted)
		toasted = TRUE
		set_icon('icons/obj/toy.dmi')
		set_icon_state("toast")
		to_chat(user, span_notice(" You insert bread into the toaster. "))
		play_sfx(loc, SFX_MACHINES_DING)
