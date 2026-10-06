//grass
/obj/structure/flora/grass
	name = "grass"
	icon = 'icons/obj/flora/snowflora.dmi'
	anchored = TRUE

TYPE_TABLE_DECLARE(/obj/structure/flora/grass, grass_icon_choice, null)

// ALLOW(init/CTOR_ARGS): grass_icon is a constructor argument from whoever builds it
/obj/structure/flora/grass/Initialize(mapload, grass_icon)
	var/list/icon_choice = TYPE_TABLE_GET(src, grass_icon_choice)
	if(icon_choice)
		grass_icon = "[icon_choice[1]][rand(1, 3)][icon_choice[2]]"
		. = ..(mapload, grass_icon)
	else
		. = ..()
	icon_state = grass_icon

/obj/structure/flora/grass/brown
	icon_state = "snowgrass1bb"

TYPE_TABLE(/obj/structure/flora/grass/brown, grass_icon_choice, list("snowgrass", "bb"))

/obj/structure/flora/grass/green
	icon_state = "snowgrass1gb"

TYPE_TABLE(/obj/structure/flora/grass/green, grass_icon_choice, list("snowgrass", "gb"))

/obj/structure/flora/grass/both
	icon_state = "snowgrassall1"

TYPE_TABLE(/obj/structure/flora/grass/both, grass_icon_choice, list("snowgrassall", ""))
