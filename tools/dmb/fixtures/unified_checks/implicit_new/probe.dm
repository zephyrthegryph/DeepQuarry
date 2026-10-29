/proc/known(x)
	return x
/datum/target
/datum/target/New(x)
	return
/proc/probe(a)
	new()
	return new(hidden_after_return())
/proc/argument()
	list("é漢", new(hidden_missing()))
/proc/grouped(a)
	(a ? new() : new())
/proc/hinted()
	var/datum/target/t = new(1)
	new /datum/target(2)
/proc/suppressed()
	new(hidden_missing())
/proc/interpolated()
	"[new()]"
