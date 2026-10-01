/datum/op_probe
 var/value=1
 var/datum/op_probe/child
 var/list/L=list(1,2,3)
/proc/assign_into_local()
 var/a=5
 a := 10
 return (a := 11)
/proc/assign_into_field(datum/op_probe/o)
 o.value := 12
 return (o.value := 13)
/proc/assign_into_index(list/L,key)
 L[key] := 14
 return (L[key] := 15)
/proc/initial_arg(a)
 return initial(a)
/proc/initial_index(datum/op_probe/o,i)
 return initial(o.L[i])
/proc/saved_index(datum/op_probe/o,i)
 return issaved(o.L[i])
/proc/logical_field(datum/op_probe/o)
 return (o.value ||= 5)
/proc/logical_safe(datum/op_probe/o)
 return (o?.value ||= 5)
/proc/initial_args_index(a)
 return initial(args[1])
/proc/assign_into_local_branch(flag)
 var/a=7
 return (a := (flag ? 1 : 2))
/proc/assign_into_field_branch(datum/op_probe/o,flag)
 return (o.value := (flag ? 1 : 2))
/proc/assign_into_index_branch(list/L,key,flag)
 return (L[key] := (flag ? 1 : 2))
/proc/assign_into_index_key(list/L,flag)
 return (L[flag ? 1 : 2] := 9)
/proc/assign_into_index_owner(list/A,list/B,flag)
 return ((flag ? A : B)[1] := 8)
/proc/assign_into_index_logical(list/L,key,val)
 return (L[key] := (val || 3))
/proc/assign_into_nested_rhs(datum/op_probe/o)
 var/a=7
 return (o.value := (a := 4))

/proc/world_cache_src_assignment(datum/op_probe/o)
 o.value = world.time
 o.value = world.time
/proc/world_cache_index_mutation(list/L)
 var/t = world.time
 L[1]++
 var/u = world.time
 return t+u
/proc/world_cache_chain_mutation(datum/op_probe/o)
 var/t = world.time
 o.value++
 var/u = world.time
 return t+u
/proc/world_cache_call(datum/op_probe/o)
 var/t = world.time
 o.act()
 var/u = world.time
 return t+u
/datum/op_probe/proc/act()
 return value
/datum/op_probe/proc/world_cache_own_assignment()
 value = world.time
 value = world.time
/proc/world_cache_bare_world()
 var/w=world
 var/t=world.time
 return list(w,t)
/proc/shared_pop_aug(flag, a)
 (flag ? 5 : (a *= 2))
 return a
/proc/shared_pop_sub(flag, a)
 (flag ? 5 : (a -= 2))
 return a
/proc/shared_pop_post(flag, a)
 (flag ? 5 : a++)
 return a
/proc/shared_pop_pre(flag, a)
 (flag ? 5 : ++a)
 return a
/proc/shared_pop_index(flag, list/L, key)
 (flag ? 5 : L[key]++)
 return L
/proc/shared_pop_assign_into(flag, a)
 (flag ? 5 : (a := 2))
 return a
/proc/shared_pop_assign(flag, a)
 (flag ? 5 : (a = 2))
 return a
/proc/nested_safe_rhs_aug(list/L,key,datum/op_probe/o)
 L[key] *= o?.child?.value
 return L
/proc/nested_safe_rhs_into(list/L,key,datum/op_probe/o)
 L[key] := o?.child?.value
 return L
/proc/world_cache_join(flag,datum/op_probe/o)
 var/t=0
 if(flag)
  o.value=1
 else
  t=world.time
 return list(t,world.time)
/proc/world_cache_short_circuit(datum/op_probe/o)
 var/t=o.value && world.time
 return list(t,world.time)
/proc/world_cache_loop(flag,datum/op_probe/o)
 var/t=world.time
 while(flag--)
  t=world.time
  o.value=1
 return t
/proc/single_safe_index_rhs_aug(list/L,key,datum/op_probe/o)
 L[key] *= o?.value["k"]
 return L
/proc/single_safe_index_rhs_into(list/L,key,datum/op_probe/o)
 L[key] := o?.value["k"]
 return L
/proc/shared_pop_logical_or(flag,datum/op_probe/o,v)
 (flag ? 1 : (o.value ||= v))
 return o.value
/proc/shared_pop_logical_and(flag,datum/op_probe/o,v)
 (flag ? 1 : (o.value &&= v))
 return o.value
/proc/shared_pop_logical_reverse(flag,datum/op_probe/o,v)
 (flag ? (o.value ||= v) : 1)
 return o.value
/proc/shared_pop_logical_index(flag,list/L,key,v)
 (flag ? 1 : (L[key] &&= v))
 return L
