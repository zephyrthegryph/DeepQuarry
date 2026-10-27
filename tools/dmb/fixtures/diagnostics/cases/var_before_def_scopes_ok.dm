/datum/e
	var/answered

/proc/foo()
	return 1

/datum/e/proc/inner(x)
	answered = 1
	if(x)
		var/answered = 2
		return answered

/datum/e/proc/dotted()
	src.answered = 1
	var/answered = 2
	return answered

/datum/e/proc/looped(list/x)
	answered = 1
	for(var/answered in x)
		return answered

/datum/e/proc/called()
	foo()
	var/foo = 2
	return foo

/datum/e/proc/after_loop(list/x)
	for(var/item in x)
		return item
	var/item = 1
	return item
