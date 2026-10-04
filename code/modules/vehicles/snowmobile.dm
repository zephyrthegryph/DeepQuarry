/obj/vehicle/train/engine/quadbike/snowmobile
	name = "snowmobile"
	desc = "An electric snowmobile for traversing snow and ice with ease! Other terrain, not so much."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "snowmobile"

	load_item_visible = 1
	speed_mod = 0.6 //Speed on non-specially-defined tiles
	car_limit = 0	//No trailers.
	max_buckled_mobs = 2
	active_engines = 1
	key_type = /obj/item/key/snowmobile
	outdoors_speed_mod = 0.7 //The general 'outdoors' speed. I.E., the general difference you'll be at when driving outside on ideal terrain (...Snow)
	frame_state = "snowmobile" //Custom-item proofing!
	paint_base = 'icons/obj/vehicles.dmi'
	pixel_x = 0
	latch_on_start = 0

	var/riding_datum_type = /datum/riding/snowmobile

/obj/item/key/snowmobile
	name = "key"
	desc = "A keyring with a small steel key, and an ice-blue fob reading \"CHILL\"."
	icon = 'icons/obj/vehicles.dmi'
	icon_state = "sno_keys"
	w_class = ITEMSIZE_TINY

/obj/vehicle/train/engine/quadbike/snowmobile/random/Initialize(mapload)
	paint_color = rgb(rand(1,255),rand(1,255),rand(1,255))
	. = ..()

CAPABILITIES(/obj/vehicle/train/engine/quadbike/snowmobile)
	owns_one(nameof(riding_datum), /datum/riding, starts = nameof(riding_datum_type))
	op("snowmobile_drag", item(/atom/movable), gesture(GESTURE_DRAG), label("Buckle"), then(PROC_REF(interaction_snowmobile_drag)))
	op("snowmobile_hand", hand(), then(PROC_REF(interaction_snowmobile_hand)))

/obj/vehicle/train/engine/quadbike/snowmobile/built/Initialize(mapload)
	dir = 2 //To match the under construction frame
	. = ..()

/obj/vehicle/train/engine/quadbike/snowmobile/get_turf_speeds(atom/prev_loc)
	// Same speed if turf type doesn't change
	if(istype(loc, prev_loc.type) || istype(prev_loc, loc.type))
		return
	if(istype(loc, /turf/simulated/floor/water))
		speed_mod = outdoors_speed_mod * 6 //Well that was a stupid idea wasn't it?
	else if(istype(loc, /turf/simulated/floor/outdoors/rocks))
		speed_mod = initial(speed_mod) * 1.5 //Rocks are hard, hard and skids don't mix so you're relying on the treads. Basically foot speed.
	else if(istype(loc, /turf/simulated/floor/outdoors/dirt) || istype(loc, /turf/simulated/floor/outdoors/grass) || istype(loc, /turf/simulated/floor/outdoors/newdirt) || istype(loc, /turf/simulated/floor/outdoors/newdirt_nograss))
		speed_mod = outdoors_speed_mod //Dirt and grass aren't strictly what this is designed for but its a baseline.
	else if(istype(loc, /turf/simulated/floor/outdoors/mud))
		speed_mod = outdoors_speed_mod * 1.4 //Workable, not great though.
	else if(istype(loc, /turf/simulated/floor/outdoors/snow) || istype(loc, /turf/simulated/floor/outdoors/ice))
		speed_mod = outdoors_speed_mod * 0.8 //Now we're talking!
	else
		speed_mod = initial(speed_mod)
	update_car(train_length, active_engines)

/obj/vehicle/train/engine/quadbike/snowmobile/handle_vehicle_icon()
	return

//Required for the riding datum to behave:

/// Old MouseDrop_T: mobs buckle/unbuckle through the riding datum; anything else falls to the train's load.
/obj/vehicle/train/engine/quadbike/snowmobile/proc/interaction_snowmobile_drag(datum/act/op/A)
	var/mob/user = A.actor
	var/atom/movable/C = A.held
	if(!ismob(C))
		return OP_DECLINE
	if(C in src?.buckled_mob_list())
		user_unbuckle_mob(C, user)
	else
		user_buckle_mob(C, user)
	return TRUE

/// Old attack_hand: buckle yourself on, or off (replaces the train climb/unload).
/obj/vehicle/train/engine/quadbike/snowmobile/proc/interaction_snowmobile_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(user == load)
		unload(load, user)
		to_chat(user, "You unbuckle yourself from \the [src].")
		return TRUE
	if(user in src?.buckled_mob_list())
		unbuckle_mob(user)
		return TRUE
	else if(!load && load(user, user))
		to_chat(user, "You buckle yourself to \the [src].")
		return TRUE
	return TRUE
