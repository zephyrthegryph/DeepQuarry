/obj/item/frame
	name = "frame parts"
	desc = "Used for building frames."
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "frame_bitem"
	var/build_machine_type
	var/build_wall_only = FALSE
	var/refund_amt = 5
	var/refund_type = /obj/item/stack/material/steel
	var/reverse = 0 //if resulting object faces opposite its dir (like light fixtures)
	var/list/frame_types_floor
	var/list/frame_types_wall

/obj/item/frame/proc/update_type_list()
	if(!frame_types_floor)
		frame_types_floor = GLOB.construction_frame_floor
	if(!frame_types_wall)
		frame_types_wall = GLOB.construction_frame_wall

/obj/item/frame/wrench_act(mob/user, obj/item/tool)
	replace_with(src, refund_type, refund_amt)
	return ITEM_INTERACT_SUCCESS

/obj/item/frame/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	update_type_list()
	if(!build_machine_type && !build_wall_only)
		om_prompt(src, user, list("kind" = "list", "message" = "What kind of frame would you like to make?", "title" = "Frame type request", "choices" = frame_types_floor, "requires" = PROMPT_HELD), PROC_REF(floor_frame_chosen))
		return
	build_on_floor(user, null)

/obj/item/frame/proc/floor_frame_chosen(mob/user, datum/frame/frame_types/frame_type, datum/om/prompt/ask)
	if(build_machine_type)
		return
	build_machine_type = /obj/structure/frame
	if(frame_type.frame_size != 5)
		new /obj/item/stack/material/steel(user.loc, (5 - frame_type.frame_size))
	build_on_floor(user, frame_type)

/obj/item/frame/proc/build_on_floor(mob/user, datum/frame/frame_types/frame_type)
	var/ndir
	ndir = user.dir
	if(!(ndir in GLOB.cardinal))
		return

	var/obj/machinery/M = new build_machine_type(get_turf(src.loc), ndir, 1, frame_type)
	M.init_forensic_data().merge_allprints(forensic_data)
	if(istype(src.loc, /obj/item/gripper)) //Typical gripper shenanigans
		user.drop_item()
	consume(src, user)

/obj/item/frame/proc/try_build(turf/on_wall, mob/user as mob)
	update_type_list()

	if(get_dist(on_wall, user)>1)
		return

	var/ndir
	if(reverse)
		ndir = get_dir(user, on_wall)
	else
		ndir = get_dir(on_wall, user)

	if(!(ndir in GLOB.cardinal))
		return

	var/turf/loc = get_turf(user)
	var/area/A = loc.loc
	if(!istype(loc, /turf/simulated/floor))
		to_chat(user, span_danger("\The [src] cannot be placed on this spot."))
		return

	if(A.requires_power == 0 || A.name == "Space")
		to_chat(user, span_danger("\The [src] cannot be placed in this area."))
		return

	if(gotwallitem(loc, ndir))
		to_chat(user, span_danger("There's already an item on this wall!"))
		return

	if(!build_machine_type)
		om_prompt(src, user, list("kind" = "list", "message" = "What kind of frame would you like to make?", "title" = "Frame type request", "choices" = frame_types_wall, "requires" = PROMPT_HELD, "data" = list("loc" = loc, "dir" = ndir)), PROC_REF(wall_frame_chosen))
		return
	build_on_wall(user, loc, ndir, null)

/obj/item/frame/proc/wall_frame_chosen(mob/user, datum/frame/frame_types/frame_type, datum/om/prompt/ask)
	if(build_machine_type)
		return
	build_machine_type = /obj/structure/frame
	if(frame_type.frame_size != 5)
		new /obj/item/stack/material/steel(user.loc, (5 - frame_type.frame_size))
	build_on_wall(user, ask.get("loc"), ask.get("dir"), frame_type)

/obj/item/frame/proc/build_on_wall(mob/user, turf/loc, ndir, datum/frame/frame_types/frame_type)
	var/obj/machinery/M = new build_machine_type(loc, ndir, 1, frame_type)
	M.init_forensic_data().merge_allprints(forensic_data)
	if(istype(src.loc, /obj/item/gripper)) //Typical gripper shenanigans
		user.drop_item()
	consume(src, user)

/obj/item/frame/light
	name = "light fixture frame"
	desc = "Used for building lights."
	icon = 'icons/obj/lighting.dmi'
	icon_state = "tube-construct-item"
	refund_amt = 2
	build_machine_type = /obj/machinery/light_construct
	reverse = 1

/obj/item/frame/light/small
	name = "small light fixture frame"
	icon_state = "bulb-construct-item"
	refund_amt = 1
	build_machine_type = /obj/machinery/light_construct/small

/obj/item/frame/extinguisher_cabinet
	name = "extinguisher cabinet frame"
	desc = "Used for building fire extinguisher cabinets."
	icon = 'icons/obj/closet.dmi'
	icon_state = "extinguisher_empty"
	refund_amt = 4
	build_machine_type = /obj/structure/extinguisher_cabinet

/obj/item/frame/noticeboard
	name = "noticeboard frame"
	desc = "Used for building noticeboards."
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "nboard00"
	refund_amt = 4
	refund_type = /obj/item/stack/material/wood
	build_machine_type = /obj/structure/noticeboard

/obj/item/frame/mirror
	name = "mirror frame"
	desc = "Used for building mirrors."
	icon = 'icons/obj/watercloset.dmi'
	icon_state = "mirror_frame"
	refund_amt = 1
	build_machine_type = /obj/structure/mirror

/obj/item/frame/fireaxe_cabinet
	name = "fire axe cabinet frame"
	desc = "Used for building fire axe cabinets."
	icon = 'icons/obj/closet.dmi'
	icon_state = "fireaxe0101"
	refund_amt = 4
	build_machine_type = /obj/structure/fireaxecabinet
