#define RETURN_TYPE(X) set SpacemanDMM_return_type = X

/obj/thing
	var/image/stored
	var/mutable_appearance/mstored
	var/datum/other/helper
	var/plain

/datum/other
	var/dir

/proc/built_image() as /image
	return image('a.dmi', "s")

/proc/built_mutable()
	RETURN_TYPE(/mutable_appearance)
	return mutable_appearance('a.dmi', "s")

/proc/not_an_image() as /datum/other
	return new /datum/other()

/proc/bad_typed_local()
	var/image/I = image('a.dmi', "s")
	I.dir = NORTH

/proc/bad_mutable_local()
	var/mutable_appearance/M = mutable_appearance('a.dmi', "s")
	M.dir = EAST

/proc/bad_param(image/I, mutable_appearance/M)
	I.dir = SOUTH
	M.dir = WEST

/proc/bad_untyped_local()
	var/I = image('a.dmi', "s")
	I.dir = NORTH
	var/M = mutable_appearance('a.dmi', "s")
	M.dir = NORTH

/proc/bad_new()
	var/I = new /image('a.dmi', "s")
	I.dir = NORTH

/proc/bad_call_result()
	var/A = built_image()
	A.dir = NORTH
	var/B = built_mutable()
	B.dir = NORTH
	built_image().dir = NORTH

/proc/bad_compound(image/I)
	I.dir |= NORTH

/obj/thing/proc/bad_field()
	stored.dir = NORTH
	mstored.dir = NORTH
	src.stored.dir = NORTH

/proc/good_constructor_dir()
	var/image/I = image('a.dmi', "s", dir = NORTH)
	return I

/proc/good_read(image/I)
	if(I.dir == NORTH)
		return I.dir

/proc/good_other_dir(datum/other/O, atom/A)
	O.dir = NORTH
	A.dir = NORTH
	var/D = new /datum/other()
	D.dir = NORTH
	var/N = not_an_image()
	N.dir = NORTH

/proc/good_untyped_param(x)
	x.dir = NORTH

/obj/thing/proc/good_field_other()
	helper.dir = NORTH
	dir = NORTH
	src.dir = NORTH
	plain.dir = NORTH
