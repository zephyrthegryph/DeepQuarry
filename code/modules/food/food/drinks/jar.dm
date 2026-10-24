///jar
/obj/item/reagent_containers/food/drinks/jar
	name = "empty jar"
	desc = "A jar. You're not sure what it's supposed to hold."
	icon_state = "jar"
	item_state = "beaker"

CAPABILITIES(/obj/item/reagent_containers/food/drinks/jar)
	configure(movable_motion(unacidable = TRUE))
	configure(item_handling(center_x = 15, center_y = 8))

/obj/item/reagent_containers/food/drinks/jar/on_reagent_change()
	if (reagents.reagent_list.len > 0)
		switch(reagents.get_master_reagent_id())
			if("slime")
				set_icon_state("jar_slime")
				name = "slime jam"
				desc = "A jar of slime jam. Delicious!"
			else
				set_icon_state("jar_what")
				name = "jar of something"
				desc = "You can't really tell what this is."
	else
		set_icon_state("jar")
		name = "empty jar"
		desc = "A jar. You're not sure what it's supposed to hold."
		return
