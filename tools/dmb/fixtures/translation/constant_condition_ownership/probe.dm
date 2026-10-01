/datum/C/proc/managed()
 return list(1)
/proc/if_null(datum/C/O)
 O.managed()
 if(null)
  return 1
 return 0
/proc/if_true(datum/C/O)
 O.managed()
 if(1)
  return 1
 return 0
/proc/if_false(datum/C/O)
 O.managed()
 if(0)
  return 1
 return 0
/proc/while_null(datum/C/O)
 O.managed()
 while(null)
  return 1
 return 0
/proc/while_true(datum/C/O)
 O.managed()
 while(1)
  return 1
 return 0
/proc/while_false(datum/C/O)
 O.managed()
 while(0)
  return 1
 return 0
/proc/runtime_condition(datum/C/O,flag)
 O.managed()
 if(flag)
  return 1
 return 0
/proc/nested_constant_scope(datum/C/O)
 O.managed()
 if(1)
  var/const/K=7
  var/i=2
  if(null)
   return 1
  return K+i
 return 0
/proc/constant_else_if(datum/C/O)
 O.managed()
 if(null)
  return 1
 else if(1)
  return 2
 else
  return 3
/proc/constant_text(datum/C/O)
 O.managed()
 if("yes")
  return 1
 return 0
/proc/constant_empty_text(datum/C/O)
 O.managed()
 if("")
  return 1
 return 0
/proc/constant_type(datum/C/O)
 O.managed()
 if(/datum/C)
  return 1
 return 0
/proc/dead_const()
 if(0)
  var/const/DEAD=7
 return 0
