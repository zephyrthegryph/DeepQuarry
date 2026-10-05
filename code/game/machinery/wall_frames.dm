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

MSG_DEF_SELF(frame/bad_spot, "It cannot be placed on this spot.")
MSG_DEF_SELF(frame/bad_area, "It cannot be placed in this area.")
MSG_DEF_SELF(frame/wall_taken, "There's already an item on this wall!")

/// A frame held to a wall (or an anchored window) from the floor beside it becomes what it frames, there (op frame.mount); the type
/// decides what that is (mount_on()): a fixture or cabinet, or a machine at the first stage of its build graph (the APC frame).
CAPABILITIES(/obj/item/frame)
	op("self", in_hand(), then(PROC_REF(interaction_self)))
	op("mount", at_target(/turf/simulated/wall), at_target(/obj/structure/window), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK),
		label("Mount on the wall"), wait(0),
		needs(req(PROC_REF(mount_facing), silent = TRUE), req_frame_mount()),
		then(PROC_REF(mount_on)))

/// Old attack_self.
/obj/item/frame/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	update_type_list()
	if(!build_machine_type && !build_wall_only)
		open_request(src, /datum/prompt/choice, PROC_REF(floor_frame_chosen), valid = PROC_REF(frame_type_open), answerer = user, title = "Frame type request", question = "What kind of frame would you like to make?", choices = frame_types_floor, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
		return TRUE
	build_on_floor(user, null)
	return TRUE

/// Re-checked on the answer: the frame hasn't been given a type meanwhile.
/obj/item/frame/proc/frame_type_open(datum/request/R)
	return !build_machine_type

/// The wall version also remembers where it goes.
/datum/prompt/choice/frame_type_wall
	var/turf/wall_turf
	var/wall_dir

CAPABILITIES(/datum/prompt/choice/frame_type_wall)
	ref_one(nameof(wall_turf), /turf)

/obj/item/frame/proc/floor_frame_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/datum/frame/frame_types/frame_type = A.answer.answer_value
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

/// The way the mounted thing faces: away from the wall, or into it for a frame that faces backwards (a light fixture).
/obj/item/frame/proc/mount_dir(atom/wall, mob/user)
	return reverse ? get_dir(user, wall) : get_dir(wall, user)

/// The builder is beside the wall, straight in front of it (the old guard refused silently).
/obj/item/frame/proc/mount_facing(datum/act/op/A)
	var/atom/wall = A.target
	var/mob/user = A.actor
	if(!wall || !user || get_dist(wall, user) > 1)
		return FALSE
	var/obj/structure/window/W = wall
	if(istype(W) && !W.anchored)
		return FALSE
	return (mount_dir(wall, user) in GLOB.cardinal)

/// Why the frame can't go on this wall from where the builder stands, or null.
/obj/item/frame/proc/mount_refusal(datum/act/op/A)
	var/turf/spot = get_turf(A.actor)
	var/area/where = spot?.loc
	if(!istype(spot, /turf/simulated/floor))
		return /datum/msg/frame/bad_spot
	if(where.requires_power == 0 || where.name == "Space")
		return /datum/msg/frame/bad_area
	if(gotwallitem(spot, mount_dir(A.target, A.actor)))
		return /datum/msg/frame/wall_taken
	return null

/// req_frame_mount(): the frame's mount_refusal() has nothing against the spot. Asked when the frame is held to a wall; nothing caches it.
/proc/req_frame_mount()
	return part_make(/datum/entry/part/req/frame_mount)

/datum/entry/part/req/frame_mount
	part_name = "req_frame_mount"

/datum/entry/part/req/frame_mount/holds(datum/act/op/A)
	var/obj/item/frame/F = A.holder
	return !istype(F) || isnull(F.mount_refusal(A))

/datum/entry/part/req/frame_mount/refusal(datum/act/op/A)
	var/obj/item/frame/F = A.holder
	return (istype(F) && F.mount_refusal(A)) || default_reason

/datum/entry/part/req/frame_mount/read_keys(datum/act/op/A)
	return list()

/// The mount: a frame of no set kind asks which kind first; one that knows builds there.
/obj/item/frame/proc/mount_on(datum/act/op/A)
	var/mob/user = A.actor
	update_type_list()
	var/turf/spot = get_turf(user)
	var/ndir = mount_dir(A.target, user)
	if(!build_machine_type)
		open_request(src, /datum/prompt/choice/frame_type_wall, PROC_REF(wall_frame_chosen), valid = PROC_REF(frame_type_open), answerer = user, title = "Frame type request", question = "What kind of frame would you like to make?", choices = frame_types_wall, wall_turf = spot, wall_dir = ndir, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)
		return OP_OK
	build_on_wall(user, spot, ndir, null)
	return OP_OK

/obj/item/frame/proc/wall_frame_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/frame_type_wall/R = A.request
	var/mob/user = R.answerer
	var/datum/frame/frame_types/frame_type = A.answer.answer_value
	build_machine_type = /obj/structure/frame
	if(frame_type.frame_size != 5)
		new /obj/item/stack/material/steel(user.loc, (5 - frame_type.frame_size))
	build_on_wall(user, R.wall_turf, R.wall_dir, frame_type)

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
