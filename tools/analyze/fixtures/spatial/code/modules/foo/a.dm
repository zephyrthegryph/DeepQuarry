/obj/a
	for(var/obj/item/I in X.contents)
	for(var/obj/item/I in src.contents)
	for(var/I in a.b.contents)
	for(var/I in a:contents)
	for(var/I in a:b.contents)
	for(var/I in contents)
	for(var/I in src)
	for(var/I in loc)
	for(var/I in T)
	for(var/I in H)
	for(var/I in M)
	for(var/I in A)
	for(var/I in AM)
	for(var/I in holder)
	for(var/I in container)
	for(var/I in src )
	for(var/I in src, 1)
	for(var/I in srcx)
	for(var/I in Tx)
	for(var/I in t)
	for(var/I in T.contents)
	for(var/I in X.contentsx)
	for(var/I in X.contents_list)
	var/n = contents.len
	var/n = X.contents.len
	var/n = X.contents . len
	var/n = length(contents)
	var/n = length( contents )
	var/n = length(X.contents)
	var/n = contents.length
	var/n = mycontents.len
	var/n = my_contents.len
	locate(/obj/item) in X.contents
	locate(/obj/item) in slot_contents(X)
	locate(/obj/item) in X.slot_contents(Y)
	locate(/obj/item) in latent_entries(X)
	locate(/obj/item) in latent_materialize_all(X)
	locate(/obj/item) in get_all_contents(X)
	locate(/obj/item) in turf_contents_of_type(X)
	locate(/obj/item) in area_contents_of_type(X)
	locate(/obj/item) in contents_property(X)
	locate(/obj/item) in contents_of(X)
	locate(/obj/item) in contents_of (X)
	locate(/obj/item) in a.b.contents_of(X)
	locate(/obj/item) in my_list
	locate(X) in view(7)
	locate (X) in L
	locate(/obj/item, X) in L
	locate(foo(bar)) in L
	var/x = locate(/obj) in world
	locate(/obj/item) in slot_contents_extra(X)
	locate(/obj/item) in slot_contents
	locate(/obj/item)in L
	// for(var/I in X.contents)
	var/s = "in X.contents"
	var/t = "a [length(contents)] embedded read"
	for(var/I in X.contents) // ALLOW(spatial): the holder is a plain list wrapper
	// ALLOW(spatial): the holder is a plain list wrapper
	for(var/I in X.contents)
	// ALLOW(spatial): the holder is a plain list wrapper
	for(var/I in X.contents) for(var/J in src)
	for(var/I in X.contents) // ALLOW(spatial)
	for(var/I in X.contents) // ALLOW(other): a reason for some other lint entirely
	for(var/I in X.contents) // ALLOW(other, spatial): a reason that names two lints
	x = 1 // ALLOW(spatial): not a comment-only line so it keeps nothing below
	for(var/I in X.contents)
	/* ALLOW(spatial): block form of the annotation */ for(var/I in X.contents)
	for(var/I in X.contents) for(var/J in Y.contents)
	for(var/I in src) for(var/J in loc)
	for(var/I in src) if(contents.len) locate(/obj) in L
