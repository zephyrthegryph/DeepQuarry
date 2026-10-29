/obj/effect/landmark/poi_loader
	name = "PoI Loader"
	var/size_x
	var/size_y
	var/poi_type = null
	var/remove_from_pool = TRUE

INITIALIZE_IMMEDIATE(/obj/effect/landmark/poi_loader)

CAPABILITIES(/obj/effect/landmark/poi_loader)
	setup(PROC_REF(queue_poi))

/obj/effect/landmark/poi_loader/proc/queue_poi()
	SSpois.enqueue(src)
