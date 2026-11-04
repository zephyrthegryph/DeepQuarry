/obj/item/reagent_containers/food/snacks/canned/brainzsnax
	name = "\improper BrainzSnax"
	icon_state = "brainzsnax"
	desc = "A can of grey matter marketed for xenochimeras."
	trash = /obj/item/trash/brainzsnax
	canned_open_state = "brainzsnax-open"
	filling_color = "#caa3c9"
	bitesize = 2
	var/brainmeat = REAGENT_ID_BRAINPROTEIN

/// Ten units of its brain meat.
/obj/item/reagent_containers/food/snacks/canned/brainzsnax/proc/brain_contents()
	return brainmeat ? list("[brainmeat]" = 10) : null

CAPABILITIES(/obj/item/reagent_containers/food/snacks/canned/brainzsnax)
	configure(atom_rules(description_fluff = "As the cartoon brain with limbs proudly proclaims, \"It's meat. Eat it!\" On the can is printed \"Rich in limbic system\" and \
	under that in infinitely small letters, \"Warning, product must be eaten within two hours of opening. May contain prion disease. \
	GrubCo LTD is not liable for any brain damage occurring after consumption of product.\""))
	configure(item_handling(center_x = 15, center_y = 9))
	configure(reagents(contents_from = PROC_REF(brain_contents)))

/obj/item/reagent_containers/food/snacks/canned/brainzsnax/red
	name = "\improper BrainzSnax RED"
	icon_state = "brainzsnaxred"
	desc = "A can of grey matter marketed for xenochimeras. This one has added tomato sauce."
	trash = /obj/item/trash/brainzsnaxred
	canned_open_state = "brainzsnaxred-open"
	filling_color = "#a6898d"
	bitesize = 2
	brainmeat = REAGENT_ID_REDBRAINPROTEIN

CAPABILITIES(/obj/item/reagent_containers/food/snacks/canned/brainzsnax/red)
	configure(atom_rules(description_fluff = "As the cartoonish brain with limbs proudly proclaims, \"It's meat. Eat it!\" On the can is printed \"Yummy red stuff!\" and \
	under that in infinitely small letters, \"Warning, product must be eaten within two hours of opening. May contain prion disease. \
	GrubCo LTD is not liable for any brain damage occurring after consumption of product.\""))
	configure(item_handling(center_x = 15, center_y = 9))
