//A locking mechanism that pulses when hit by a projectile. The base one responds to high-power lasers.

/obj/structure/prop/lock
	name = "weird lock"
	desc = "An esoteric object that responds to.. something."
	icon = 'icons/obj/props/prism.dmi'
	icon_state = "lock"

	var/enabled = 0
	var/lockID = null

	var/list/linked_objects

// many-to-many with puzzle doors: leaves each door's lock list.
CAPABILITIES(/obj/structure/prop/lock)
	links(/obj/structure/prop/lock::linked_objects, /obj/machinery/door/blast/puzzle::locks, a_many = TRUE, b_many = TRUE)

/obj/structure/prop/lock/proc/toggle_lock()
	enabled = !enabled

	if(enabled)
		icon_state = "[initial(icon_state)]-active"
	else
		icon_state = "[initial(icon_state)]"

/obj/structure/prop/lock/projectile
	name = "beam lock"
	desc = "An esoteric object that responds to high intensity light."

	var/projectile_key = /obj/item/projectile/beam
	var/timed = 0
	var/timing = 0
	var/time_limit = 1500 // In ticks. Ten is one second.

	interaction_message = span_notice("The object remains inert to your touch.")

/obj/structure/prop/lock/projectile/bullet_act(obj/item/projectile/Proj)
	if(!istype(Proj, projectile_key) || timing)
		return

	if(istype(Proj, /obj/item/projectile/beam/heavylaser/cannon) || istype(Proj, /obj/item/projectile/beam/emitter) || (Proj.damage >= 80 && Proj.obj_damage_type() == BURN))
		toggle_lock()
		visible_message(span_notice("\The [src] [enabled ? "disengages" : "engages"] its locking mechanism."))

		if(timed)
			timing = 1
			after(src, time_limit, PROC_REF(toggle_lock))
