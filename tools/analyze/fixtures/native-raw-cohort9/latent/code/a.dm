/obj/holder
	latent_contents = TRUE
/obj/holder/proc/run()
	for(var/x in contents)
		return x
	var/obj/holder/H
	H.contents.len
	H.contents.len // ALLOW(latent): deliberate compatibility annotation used by the raw judge
