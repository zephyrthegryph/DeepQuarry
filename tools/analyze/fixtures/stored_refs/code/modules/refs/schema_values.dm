// A list var declared a list of paths is a value, not a store of entities: no `list` finding although a proc fills it from an entity-typed call.

/obj/school
	var/list/kinds
	var/list/held

SCHEMA(/obj/school, kinds, list_of(schema_path(/obj/school)))

/obj/school/proc/fill(obj/school/other)
	kinds += other
	held += other
