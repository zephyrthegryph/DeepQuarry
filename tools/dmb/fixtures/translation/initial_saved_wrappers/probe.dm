/datum/wrapper
 var/v=3
/proc/initial_saved_local()
 var/foo=7
 return initial(issaved(foo))
/proc/initial_saved_arg(foo)
 return initial(issaved(foo))
/proc/initial_saved_field(datum/wrapper/O)
 return initial(issaved(O.v))
/proc/saved_initial_field(datum/wrapper/O)
 return issaved(initial(O.v))
/proc/initial_initial_field(datum/wrapper/O)
 return initial(initial(O.v))
/proc/saved_saved_field(datum/wrapper/O)
 return issaved(issaved(O.v))
/proc/initial_saved_computed()
 return initial(issaved(get_owner().v))
/proc/get_owner()
 return new /datum/wrapper

/proc/saved_local()
 var/foo=7
 return issaved(foo)
/proc/saved_arg(foo)
 return issaved(foo)
/proc/saved_initial_local()
 var/foo=7
 return issaved(initial(foo))
/proc/saved_initial_arg(foo)
 return issaved(initial(foo))
/proc/initial_const()
 var/const/foo=7
 return initial(issaved(foo))
/proc/saved_const()
 var/const/foo=7
 return issaved(initial(foo))

/proc/ordinary_const()
 var/const/foo=7
 return foo
/datum/wrapper/proc/managed()
 return list(1)
/proc/constant_number_read(datum/wrapper/O)
 var/const/X=7
 O.managed()
 return X
/proc/constant_text_read(datum/wrapper/O)
 var/const/X="hello"
 O.managed()
 return X
/proc/constant_type_read(datum/wrapper/O)
 var/const/X=/datum/wrapper
 O.managed()
 return X
/proc/constant_number_fold()
 var/const/X=7
 return X+1
/proc/constant_text_fold()
 var/const/X="hello"
 return X+"!"
/proc/constant_unused()
 var/const/UNUSED=11
 return 0
