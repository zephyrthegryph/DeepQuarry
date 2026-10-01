/proc/implicit_type()
 return locate(/obj)
/proc/explicit_world()
 return locate(/obj) in world
/proc/implicit_value(x)
 return locate(x)
/proc/explicit_value(x)
 return locate(x) in world
/proc/explicit_list(x,list/L)
 return locate(x) in L
/var/list/force516 = alist()
