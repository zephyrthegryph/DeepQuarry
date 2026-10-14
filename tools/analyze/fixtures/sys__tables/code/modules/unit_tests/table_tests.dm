/obj/thing/proc/test_names()
	var/static/list/table = list("a", "b")
	return table

/obj/thing/proc/test_list()
	return list("a")

// ALLOW(instance_list): not worth it
