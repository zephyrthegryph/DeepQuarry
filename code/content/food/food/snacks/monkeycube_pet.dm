// Pet cubes!
/obj/item/reagent_containers/food/snacks/monkeycube/pet
	var/pet_path = null

/obj/item/reagent_containers/food/snacks/monkeycube/pet/wrapped
	desc = "Still wrapped in some paper."
	icon_state = "monkeycubewrap"
	flags = NONE
	wrapped = 1

/obj/item/reagent_containers/food/snacks/monkeycube/pet/Expand()
	var/mob/holder
	if(ismob(loc))
		holder = loc
	if(loc?.release_refusal(src, holder))
		return 0
	src.visible_message("<b>\The [src]</b> expands!")
	if(pet_path)
		new pet_path(get_turf(src))
	consume(src, holder)
	return 1
