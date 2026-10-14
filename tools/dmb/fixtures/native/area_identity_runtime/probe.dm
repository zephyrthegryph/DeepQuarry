/world
	area = /area/space
	turf = /turf/space
/area/space
/area/room
/turf/space
/turf/floor
/world/New()
	..()
	var/list/seen = list()
	for(var/turf/T in world)
		var/area/A = T.loc
		world.log << "DQ_AREA [T.x],[T.y] [T.type] [A.type] [A == locate(/area/space) ? "first" : "other"] idx=[seen.Find(A) || (seen += A) && seen.len]"
	var/n = 0
	for(var/area/A in world)
		n++
	world.log << "DQ_AREA count [n]"
	shutdown()
