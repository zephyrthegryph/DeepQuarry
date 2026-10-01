/mob/selector_probe
 verb/halt_probe()
  set name="Custom Halt"
  world.log << "VERB_CALLED"
 proc/bare_probe()
  halt_probe()
 proc/member_probe(mob/selector_probe/M)
  M.halt_probe()
/mob/selector_probe/child/halt_probe()
 world.log << "VERB_CHILD"
 ..()
/world/New()
 ..()
 var/mob/selector_probe/M=new /mob/selector_probe/child
 M.bare_probe()
 M.member_probe(M)
 shutdown()

