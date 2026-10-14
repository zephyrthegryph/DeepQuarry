/obj/holder
	latent_contents = TRUE

/obj/holder/proc/walk()
	for(var/x in contents)
	for(var/x in src.contents)
	for(var/x in src)
	var/n = contents.len
	var/m = length(contents)
	var/k = length( src.contents )
	var/q = src.contents.len
	var/z = x.contents.len
	for(var/x in contents) // ALLOW(latent): fine
	// ALLOW(latent): above
	for(var/x in contents)
	// for(var/x in contents)
	var/s = "in contents"
	var/url = "http://x"; for(var/a in contents)
	for(var/x in contents) // ALLOW(latent)
	for(var/x in contentsfoo)
	for(var/x in src.contents_x)
x_global = 1
/obj/holder/verb/doit()
	for(var/x in contents)
/obj/holder/sub
	latent_contents = FALSE
/obj/holder/sub/proc/walk()
	for(var/x in contents)
/obj/holder/sub/deeper
/obj/holder/sub/deeper/proc/walk()
	for(var/x in contents)
/obj/holder/sub/again
	latent_contents = TRUE
/obj/holder/sub/again/proc/walk()
	for(var/x in contents)
/obj/other/proc/t()
	var/obj/holder/H = new
	for(var/x in H.contents)
	for(var/x in H)
	var/obj/plain/P
	for(var/x in P.contents)
	var//obj/holder/G
	for(var/x in G.contents) // trailing
/obj/other/proc/t2()
	for(var/x in H.contents)
	for(var/x in contents)
// comment at column zero keeps the owner
	var/obj/holder/H2
	for(var/x in H2.contents)
