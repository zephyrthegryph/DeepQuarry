/client/input_topic(hsrc, href, list/href_list)
	return _Topic(hsrc, href, href_list)

/mob/input_say(message)
	return say(message)

/mob/input_point(atom/target)
	return _pointed(target)

/client/input_key_loop()
	return keyLoop()
