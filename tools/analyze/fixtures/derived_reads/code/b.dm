/obj/thing
	var/level = 0
	var/extra = 0
	var/total = 0
	var/spare = 0
	var/obj/thing/parent
	var/list/kids

TRACKED(/obj/thing, level)
REL(/obj/thing, parent)

/obj/thing/derived()
	. = ..()
	. += derive(nameof(total), nameof(level))
	. += drawn_from(nameof(total), nameof(spare), rel(nameof(parent), nameof(/obj/thing::level)), rel(nameof(kids), nameof(/obj/thing::mystery)))
	. += ui_from(nameof(cap_state))

/obj/thing/derive_total()
	return level + extra

/obj/thing/on_state_changed(bits)
	return

/obj/thing/tgui_data(mob/user)
	var/level = 5
	// ALLOW(derived_reads): fixture keep
	. = list("level" = level, "n" = total)
	. += total

// relations() entries declare a relation; a mixin-style header with a trailing call is a proc.
/obj/thing/relations()
	. = ..()
	. += rel_one(nameof(parent), /obj/thing)
	. += rel_many(nameof(kids), /obj/thing)

/obj/thing/other
	var/size = 1
	var/obj/thing/link

OWN(/obj/thing/other, link)

/obj/thing/other/derived()
	. = ..()
	. += drawn_from(rel(nameof(link), nameof(/obj/thing::mystery)), nameof(size), nameof(undefined_thing))
	. += drawn_from(rel(nameof(size), nameof(/obj/thing::level)))
	. += drawn_from(rel(nameof(parent)))
	. += drawn_from(rel(
		nameof(link),
		nameof(/obj/thing::total)))

/obj/thing/other/draw()
	return size + level + undefined_thing

/obj/thing/other/hidden_verbs()
	var/size = 2
	return size

/obj/thing/other/should_run()
	return src.size
