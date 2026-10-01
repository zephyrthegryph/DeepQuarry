var/global/datum/holder/OTHER
var/global/seen
/datum/holder
 var/value
 var/other
 var/datum/holder/child
/datum/holder/Del()
 seen=OTHER
 OTHER=new /datum/holder
 return ..()
/datum/holder/proc/managed()
 return list(1)
/datum/holder/proc/getter_first()
 return value+other
/datum/holder/proc/setter_reads()
 value=9
 return value+other
/datum/holder/proc/setter_src_rebind(datum/holder/O)
 value=9
 src=O
 return value+other
/datum/holder/proc/setter_branch(flag)
 value=9
 if(flag)
  other=4
 return value+other
/datum/holder/proc/method_branch(flag)
 managed()
 if(flag)
  other=4
 return value+other
/datum/holder/proc/setter_other(datum/holder/O)
 value=9
 O.other=4
 return value+other
/datum/holder/proc/setter_derived()
 value=9
 child.other=4
 return value+other
/datum/holder/proc/setter_managed_old()
 value=new /datum/holder
 value=new /datum/holder
 return value
/proc/world_getter_first()
 return world.name+world.status
/proc/world_setter_reads()
 world.name="changed"
 return world.name+world.status
/proc/world_setter_branch(flag)
 world.name="changed"
 if(flag)
  world.status="status"
 return world.name+world.status
/proc/world_setter_other(datum/holder/O)
 world.name="changed"
 O.other=4
 return world.name+world.status
