// Simple holder for each floor in the lift.
/datum/turbolift_floor
	var/area_ref
	var/label
	var/name
	var/announce_str
	var/arrival_sound
	var/delay_time

	/// The floor's exterior doors, airlocks and firedoors (a relation view: doors leave when they die).
	var/list/doors
	/// The floor's call panel (REL_PAIR with its `floor`).
	var/tmp/obj/structure/lift/button/ext_panel


CAPABILITIES(/datum/turbolift_floor)
	ref_many(nameof(doors))

/datum/turbolift_floor/proc/set_area_ref(ref)
	var/area/turbolift/A = locate(ref)
	if(!istype(A))
		log_mapping("Turbolift floor area was of the wrong type: ref=[ref]")
		return

	area_ref = ref
	label = A.lift_floor_label
	name = A.lift_floor_name ? A.lift_floor_name : A.name
	announce_str = A.lift_announce_str
	arrival_sound = A.arrival_sound
	delay_time = A.delay_time

//called when a lift has queued this floor as a destination
/datum/turbolift_floor/proc/pending_move(datum/turbolift/lift)
	if(ext_panel)
		ext_panel.light_up()

//called when a lift arrives at this floor
/datum/turbolift_floor/proc/arrived(datum/turbolift/lift)
	if(!lift.fire_mode)
		lift.open_doors(src)
	if(ext_panel)
		ext_panel.reset()
