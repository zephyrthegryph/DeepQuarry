/obj/item/reagent_containers/food/snacks/monkeycube
	name = "monkey cube"
	desc = "Just add water!"
	flags = OPENCONTAINER
	icon_state = "monkeycube"
	bitesize = 12
	filling_color = "#ADAC7F"

	var/wrapped = 0
	var/monkey_type = "Monkey"
	special_handling = TRUE

// A wrapped cube is unwrapped by using it in hand.
CAPABILITIES(/obj/item/reagent_containers/food/snacks/monkeycube)
	configure(item_handling(center_x = 16, center_y = 14))
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 10)))
	op("unwrap_cube", in_hand(), priority(OP_PRIORITY_PART), when(PROC_REF(cube_is_wrapped)), label("Unwrap it"), then(PROC_REF(cube_unwrapped)))

/obj/item/reagent_containers/food/snacks/monkeycube/proc/cube_is_wrapped(datum/act/op/A)
	return !!wrapped

/obj/item/reagent_containers/food/snacks/monkeycube/proc/cube_unwrapped(datum/act/op/A)
	Unwrap(A.actor)
	return OP_OK

/obj/item/reagent_containers/food/snacks/monkeycube/proc/Expand()
	src.visible_message(span_infoplain(span_bold("\The [src]") + " expands!"))
	var/mob/living/carbon/human/H = new(get_turf(src))
	H.set_species(monkey_type)
	H.set_real_name(H.species.get_random_name())
	H.name = H.real_name
	H.set_low_sorting_priority(TRUE)
	H.species.produceCopy(H.species.traits.Copy(),H,null,FALSE)
	if(ismob(loc))
		var/mob/M = loc
		M.unEquip(src)
	if(possessed_voice && LAZYLEN(possessed_voice))
		var/mob/living/voice/V = possessed_voice[1]
		V.mind.transfer_to(H)
		rel_set(H, nameof(H.tf_mob_holder), V.tf_mob_holder)
		spent(V)
	replace_with(src, H)
	return H

/obj/item/reagent_containers/food/snacks/monkeycube/proc/Unwrap(mob/user as mob)
	set_icon_state("monkeycube")
	desc = "Just add water!"
	to_chat(user, "You unwrap the cube.")
	set_wrapped(FALSE)
	set_open_by_flag(TRUE)
	return

/obj/item/reagent_containers/food/snacks/monkeycube/On_Consume(mob/M)
	var/mob/living/Prey = Expand()

	if(!isliving(M))
		return

	var/mob/living/Pred = M
	if(Pred.vore_prefs.can_be_drop_pred && Pred.vore_prefs.food_vore && vore_selected_of(Pred))
		vore_selected_of(Pred).nom_atom(Prey)

/obj/item/reagent_containers/food/snacks/monkeycube/on_reagent_change()
	if(reagents.has_reagent(REAGENT_ID_WATER))
		Expand()

/obj/item/reagent_containers/food/snacks/monkeycube/wrapped
	desc = "Still wrapped in some paper."
	icon_state = "monkeycubewrap"
	flags = NONE
	wrapped = 1

/obj/item/reagent_containers/food/snacks/monkeycube/farwacube
	name = "farwa cube"
	monkey_type = SPECIES_MONKEY_TAJ

/obj/item/reagent_containers/food/snacks/monkeycube/wrapped/farwacube
	name = "farwa cube"
	monkey_type = SPECIES_MONKEY_TAJ

/obj/item/reagent_containers/food/snacks/monkeycube/stokcube
	name = "stok cube"
	monkey_type = SPECIES_MONKEY_UNATHI

/obj/item/reagent_containers/food/snacks/monkeycube/wrapped/stokcube
	name = "stok cube"
	monkey_type = SPECIES_MONKEY_UNATHI

/obj/item/reagent_containers/food/snacks/monkeycube/neaeracube
	name = "neaera cube"
	monkey_type = SPECIES_MONKEY_SKRELL

/obj/item/reagent_containers/food/snacks/monkeycube/wrapped/neaeracube
	name = "neaera cube"
	monkey_type = SPECIES_MONKEY_SKRELL

/obj/item/reagent_containers/food/snacks/monkeycube/sobakacube
	name = "sobaka cube"
	monkey_type = SPECIES_MONKEY_AKULA

/obj/item/reagent_containers/food/snacks/monkeycube/wrapped/sobakacube
	name = "sobaka cube"
	monkey_type = SPECIES_MONKEY_AKULA

/obj/item/reagent_containers/food/snacks/monkeycube/sarucube
	name = "saru cube"
	monkey_type = SPECIES_MONKEY_SERGAL

/obj/item/reagent_containers/food/snacks/monkeycube/wrapped/sarucube
	name = "saru cube"
	monkey_type = SPECIES_MONKEY_SERGAL

/obj/item/reagent_containers/food/snacks/monkeycube/sparracube
	name = "sparra cube"
	monkey_type = SPECIES_MONKEY_NEVREAN

/obj/item/reagent_containers/food/snacks/monkeycube/wrapped/sparracube
	name = "sparra cube"
	monkey_type = SPECIES_MONKEY_NEVREAN

/obj/item/reagent_containers/food/snacks/monkeycube/wolpincube
	name = "wolpin cube"
	monkey_type = SPECIES_MONKEY_VULPKANIN

/obj/item/reagent_containers/food/snacks/monkeycube/wrapped/wolpincube
	name = "wolpin cube"
	monkey_type = SPECIES_MONKEY_VULPKANIN
