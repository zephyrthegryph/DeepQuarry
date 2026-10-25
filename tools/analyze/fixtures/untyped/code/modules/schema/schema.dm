// untyped fixture: a var with a SCHEMA is a value; its assignments are checked against the schema, not reported as entity sources.

/datum/msg
/datum/msg/op
/datum/msg/op/busy
/obj/item/stack
/obj/item/stack/rods
/obj/item/fish
/obj/item/fish/koi

/proc/make_thing()
	return new /obj/item/fish

/proc/pick_path(flag)
	return flag ? /obj/item/stack/rods : /obj/item/fish

/obj/thing
	var/debris_type
	var/fish_type
	var/reason
	var/schooled
	var/stray
	var/bad_debris
	var/bad_reason
	var/path_user

SCHEMA(/obj/thing, debris_type, schema_path(/obj/item/stack))
SCHEMA(/obj/thing, fish_type, schema_path(/obj/item/fish))
SCHEMA(/obj/thing, reason, schema_msg())
SCHEMA(/obj/thing, schooled, list_of(schema_path(/obj/item/fish)))
SCHEMA(/obj/thing, bad_debris, schema_path(/obj/item/stack))
SCHEMA(/obj/thing, bad_reason, schema_msg())

/obj/thing/proc/fill()
	debris_type = /obj/item/stack/rods
	fish_type = make_thing()
	fish_type = /obj/item/fish/koi
	reason = /datum/msg/op/busy
	reason = make_thing()
	schooled = make_thing()
	stray = make_thing()
	bad_debris = /obj/item/fish
	bad_reason = /obj/item/stack/rods
	bad_reason = prob(50) ? /datum/msg/op/busy : /obj/item/fish

/obj/thing/proc/picked()
	path_user = pick_path(1)
	path_user = /obj/item/stack/rods

/obj/thing/sub
	// a subtype overrides the default and keeps the schema found down the chain
	debris_type = /obj/item/stack/rods

/obj/thing/sub/proc/more()
	debris_type = /obj/item/fish
