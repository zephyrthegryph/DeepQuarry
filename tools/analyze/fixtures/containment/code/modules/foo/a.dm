/mob/a
	loc = T
	src.loc = T
	X.loc=Y
	T.loc = Y
	if(a.loc == b)
	if(a.loc != b)
	if(a.loc <= b)
	if(a.loc >= b)
	oldloc = T
	T.locs = x
	T.loc2 = x
	var/turf/loc = T
	var/loc = T
	var/obj/item/loc = T
	new /obj(loc = T)
	foo(a, loc = T)
	foo(a,loc = T)
	foo( loc = T)
	foo(a, b) loc = T
	x = list(loc = T)
	contents += A
	X.contents += A
	X.contents -= A
	X.contents |= A
	X.contents &= A
	contents.Add(A)
	X.contents.Add(A)
	X.contents . Remove (A)
	X.contents.Cut()
	X.contents.Insert(1, A)
	X.contents.Swap(1, 2)
	X.contents.len
	X.contents == Y
	X.contents.Find(A)
	X.contents.Copy()
	mycontents += A
	var/list/mycontents += A
	my_contents.Add(A)
	loc = T; X.contents += A
	loc = T; loc = U
	X.contents += A; X.contents -= B
	// loc = T
	var/s = "loc = T"
	var/t = "a [loc = T] embedded write"
	loc = T // ALLOW(containment): doMove() is the ledger's own commit point
	// ALLOW(containment): doMove() is the ledger's own commit point
	loc = T
	// ALLOW(containment): doMove() is the ledger's own commit point
	loc = T; X.contents += A
	loc = T // ALLOW(containment)
	X.contents += A // ALLOW(other): a reason for some other lint entirely
	X.contents += A // ALLOW(other, containment): a reason that names two lints
	x = 1 // ALLOW(containment): not a comment-only line so it keeps nothing below
	loc = T
	/* ALLOW(containment): block form of the annotation */ loc = T
	var/turf/loc = T; loc = U
	var/turf/loc = T, loc = U
	lovar/loc =c = 1
	var/loc = T; var/loc = U
	X.contents
		+= A
	loc
		= T
	loc= T
	loc	=	T
	loc =
	loc ==T
