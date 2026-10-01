/var/const/GN=7
/var/const/GS="hello"
/var/const/GT=/datum/C
/datum/C
 var/const/FN=8
 var/const/FS="world"
 var/const/FT=/datum/C
 proc/managed()
  return list(1)
/proc/global_number(datum/C/O)
 O.managed()
 return GN
/proc/global_text(datum/C/O)
 O.managed()
 return GS
/proc/global_type(datum/C/O)
 O.managed()
 return GT
/proc/field_number(datum/C/O)
 O.managed()
 return O.FN
/proc/field_text(datum/C/O)
 O.managed()
 return O.FS
/proc/field_type(datum/C/O)
 O.managed()
 return O.FT
/proc/fold_global()
 return GN+1
/proc/fold_field(datum/C/O)
 return O.FN+1
/proc/get_owner(datum/C/O)
 return O
/proc/computed_number(datum/C/O)
 O.managed()
 return get_owner(O).FN
/proc/safe_number(datum/C/O)
 O.managed()
 return O?.FN
/proc/colon_number(datum/C/O)
 O.managed()
 return O:FN
/datum/Other
 var/FN=99
/proc/computed_collision(datum/C/O)
 return get_owner(O).FN
/proc/typed_collision(datum/C/O)
 return O.FN
/proc/nested_local_lifetime(flag)
 if(flag)
  var/const/STEP=5
  var/i=0
  while(i<2)
   i+=STEP
 return 0
/proc/nested_local_spawn(flag)
 spawn(0)
  if(flag)
   var/const/STEP=5
   var/i=0
   while(i<2)
    i+=STEP
 return 0
/proc/computed_text_math(datum/C/O)
 return get_owner(O).FS+"!"
/proc/computed_text_condition(datum/C/O)
 if(get_owner(O).FS)
  return 1
 return 0
/proc/safe_text_condition(datum/C/O)
 if(O?.FS)
  return 1
 return 0
/proc/computed_text_while(datum/C/O)
 while(get_owner(O).FS)
  return 1
 return 0
