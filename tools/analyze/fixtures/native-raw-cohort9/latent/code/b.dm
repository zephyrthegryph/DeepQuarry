/obj/holder/eager
	latent_contents = FALSE
/obj/holder/eager/proc/run()
	for(var/x in contents)
		return x
