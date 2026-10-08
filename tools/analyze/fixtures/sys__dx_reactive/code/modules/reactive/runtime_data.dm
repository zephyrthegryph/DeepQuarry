/datum/capability/runtime_fixture/draw(atom/holder, datum/look/look)
	var/datum/payload = capability_data(holder)?["fixture"]
	if(payload?.fixture_value)
		return

/datum/capability/runtime_foreign_fixture/draw(atom/holder, datum/look/look)
	var/atom/foreign_holder = locate()
	var/datum/payload = capability_data(foreign_holder)?["fixture"]
	if(payload?.fixture_value)
		return
