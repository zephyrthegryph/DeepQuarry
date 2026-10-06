/obj/item/storage/sample_container/get_mechanics_info(list/additional_information)
	return ..(list("Scooping samples up with the container negates the risk of hurting yourself if you don't have thick enough gloves.") + additional_information)

/obj/item/storage/sample_container
	name = "sample container"
	desc = "A small containment device used to safely collect and carry up to eight research samples. Has a loop for attaching to belts."
	icon = 'icons/obj/samples.dmi'
	icon_state = "sample_container_0"

	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	storage_slots = 8
	max_storage_space = ITEMSIZE_TINY * 8
	var/lightcolor = "#EFF1BF"

	drop_sound = SFX_ITEMS_DROP_GASCAN
	pickup_sound = SFX_ITEMS_PICKUP_GASCAN



CAPABILITIES(/obj/item/storage/sample_container)
	configure(storage(accepts = list(/obj/item/research_sample), max_size = ITEMSIZE_TINY))

/obj/item/storage/sample_container/draw(datum/look/look)
	. = ..()
	look.state("sample_container_[held_count()]")
	if(held_count() > 0)
		look.light(1, held_count(), lightcolor)

/obj/item/storage/sample_container/afterattack(turf/T as turf, mob/user as mob)
	for(var/obj/item/research_sample/S in turf_contents_of_type(T, /obj/item/research_sample))
		if(contents_count(src) >= max_storage_space)
			to_chat(user, span_notice("\The [src] is full!"))
			return
		else
			S.forceMove(src)
			to_chat(user, span_notice("You scoop \the [S] into \the [src]."))
