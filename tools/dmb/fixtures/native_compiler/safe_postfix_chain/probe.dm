var/index_calls=0
/datum/chain_probe
 var/list/entries
 var/datum/chain_probe/child
 var/value=7
 proc/read_value()
  return value
/proc/index_key()
 index_calls++
 return "x"
/proc/index_chain(datum/chain_probe/L)
 return L?.entries[index_key()]["y"]
/proc/member_chain(datum/chain_probe/L)
 return L?.child.value
/proc/call_chain(datum/chain_probe/L)
 return L?.child.read_value()
/proc/grouped_index(datum/chain_probe/L)
 return (L?.entries)["x"]
/world/New()
 ..()
 var/datum/chain_probe/L=new
 L.entries=list("x"=list("y"=7))
 L.child=new
 world.log << "SAFE_CHAIN [isnull(index_chain(null))] [isnull(member_chain(null))] [isnull(call_chain(null))] [index_calls] [index_chain(L)] [member_chain(L)] [call_chain(L)]"
 shutdown()
