/mob/living/proc/ventcrawl()
	set name = "Crawl through Vent"
	set desc = "Enter an air vent and crawl through the pipe system."
	set category = "Abilities.General"
	var/pipe = start_ventcrawl(TYPE_PROC_REF(/mob/living, ventcrawl))
	if(pipe)
		handle_ventcrawl(pipe)
