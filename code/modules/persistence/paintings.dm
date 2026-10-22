/datum/persistent/paintings
	name = "paintings"
	//entries_expire_at = 1000 // Basically forever
	var/max_entries = 1000 //1000 paintings is a lot, and will take a long time to cycle through.

/datum/persistent/paintings/SetFilename()
	filename = "data/persistent/paintings.json"

/datum/persistent/paintings/Initialize()
	. = ..()
	load_database()

/// Reads the painting database from disk into the persistence system and loads the frames from it.
/datum/persistent/paintings/proc/load_database()
	if(fexists(filename))
		SSpersistence.load_paintings(json_decode(file2text(filename)))
		var/list/tokens = persistence_all_paintings()
		for(var/list/token in tokens)
			token["age"]++ // Increment age!
			if(!CheckTokenSanity(token))
				tokens -= token

	SSpersistence.reset_unpicked_paintings()

	for(var/obj/structure/sign/painting/P in persistence_painting_frames())
		P.load_persistent()

/datum/persistent/paintings/CheckTokenSanity(list/token)
	var/png_filename = "data/paintings/[token["persistence_id"]]/[token["md5"]].png"
	if(!fexists(png_filename))
		return FALSE
	return TRUE

/datum/persistent/paintings/Shutdown()
	for(var/obj/structure/sign/painting/P in persistence_painting_frames())
		P.save_persistent()

	if(SSpersistence.painting_count() > max_entries)
		var/this_many = SSpersistence.painting_count()
		var/over = this_many - max_entries
		log_admin("There are [over] more painting(s) stored than the maximum allowed.")
		while(over > 0)
			var/list/d = persistence_all_paintings()[1]
			var/png_filename = "data/paintings/[d["persistence_id"]]/[d["md5"]].png"
			fdel(png_filename)
			if(SSpersistence.remove_painting(d))
				log_admin("A painting was deleted")
			else
				log_and_message_admins("Attempted to delete a painting, but failed.")
			over --

	if(fexists(filename))
		fdel(filename)
	to_file(file(filename), json_encode(persistence_all_paintings()))
