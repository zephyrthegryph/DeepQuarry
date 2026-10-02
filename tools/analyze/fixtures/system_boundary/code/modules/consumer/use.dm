var/a = SSair.foo
var/b = SSair.call()
var/c = x.SSair.foo
var/d = "SSair.in_string"
// SSair.in_comment
/* SSair.block
SSair.block2 */
var/e = SSair.allowed // ALLOW(system_boundary): same line
// ALLOW(system_boundary): above
var/f = SSair.above
var/g = SSnope.unknown
var/h = GLOB.foo_service.bad
var/i = GLOB.foo_service.call()
var/j = system(/datum/system/delta).value
var/k = system( /datum/system/delta ).api_less()
var/l = SSair.a + SSair.b
/datum/controller/subsystem/air/proc/stolen()
/datum/world_service/foo/stolen2()
/datum/system/alpha/proc/stolen3()
/datum/system/delta/stolen4()
/datum/controller/subsystem/nothere/proc/ok()
