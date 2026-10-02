/datum/life
	latent_safe = TRUE
	var/foo

/datum/life/child
	var/bar

/datum/life/off
	latent_safe = FALSE

/datum/life/off/inherits_off
	var/baz

/datum/not_safe
	var/x

/obj/item/safe_item
	latent_safe = TRUE

/datum/life/Initialize(mapload)
	. = ..()
	GLOB.lifelist += src
	GLOB.lifelist -= src
	GLOB.lifelist |= src
	GLOB.lifelist &= src
	GLOB.lifelist ^= src
	GLOB.lifemap[key] = src
	GLOB.lifemap[key] == src
	GLOB.lifemap [key] = src
	GLOB.lifelist.Add(src)
	GLOB.lifelist.Remove(src)
	GLOB.lifelist.Insert(1, src)
	GLOB.lifelist.Cut()
	GLOB.lifelist.Swap(1, 2)
	GLOB.lifelist.Find(src)
	GLOB.single = src
	GLOB.lifelist+=src
	GLOB.lifelist.len
	START_PROCESSING(SSobj, src)
	START_PROCESSING_MACHINE(src)
	START_PROCESSINGX(src)
	STOP_PROCESSING(SSobj, src)
	RegisterSignal(SSdcs, COMSIG_X, PROC_REF(a))
	RegisterSignal( SSdcs, COMSIG_X, PROC_REF(a))
	RegisterSignal(src, COMSIG_X, PROC_REF(a))
	GLOB.radio_service.add_object(src, 1)
	set_frequency(1459)
	var/x = new /obj/radio_thing(set_frequency(2))
	// GLOB.commented += src
	var/s = "START_PROCESSING(SSobj, src) GLOB.in_string += 1"
	GLOB.lifelist += src; START_PROCESSING(SSobj, src)

	/* GLOB.in_block_comment += 1 */
	GLOB.after_blank += 1
  	GLOB.space_tab_indent += 1
GLOB.not_in_body += 1

/datum/life/child/proc/Initialize(mapload)
	..()
	START_PROCESSING(SSfastprocess, src)
	if(x)
		GLOB.nested += src

/datum/life/child/New()
	GLOB.not_initialize += src

/datum/life/off/Initialize(mapload)
	GLOB.off_type += 1

/datum/life/off/inherits_off/Initialize(mapload)
	GLOB.inherits_off += 1

/datum/not_safe/Initialize(mapload)
	GLOB.not_safe += 1

/datum/unknown_type/Initialize(mapload)
	GLOB.unknown += 1

/obj/item/Initialize(mapload)
	GLOB.ancestor_of_safe += 1

/obj/Initialize(mapload)
	GLOB.obj_ancestor += 1

/atom/Initialize(mapload)
	GLOB.atom_ancestor += 1

/atom/movable/Initialize(mapload)
	GLOB.movable_ancestor += 1

/datum/Initialize(mapload)
	GLOB.datum_ancestor += 1

/turf/Initialize(mapload)
	GLOB.turf_not_ancestor += 1

/mob/Initialize(mapload)
	GLOB.mob_not_ancestor += 1

/proc/Initialize(mapload)
	GLOB.proc_owner += 1
