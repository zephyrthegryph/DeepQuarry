/proc/collision()
 return 99
/datum/shadow/proc/collision()
 return 7
/datum/shadow/proc/probe()
 return collision()
/datum/shadow/child/proc/inherited_probe()
 return collision()
/datum/shadow/proc/explicit_global()
 return global.collision()
