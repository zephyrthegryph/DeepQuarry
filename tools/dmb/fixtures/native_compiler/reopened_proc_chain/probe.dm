/datum/chain
 proc/chain_probe()
  world.log << "CHAIN_BASE"
/datum/chain/chain_probe()
 world.log << "CHAIN_SECOND"
 ..()
/datum/chain/chain_probe()
 world.log << "CHAIN_THIRD"
 ..()
/datum/chain/child
/world/New()
 ..()
 var/datum/chain/child/C=new
 C.chain_probe()
 shutdown()

