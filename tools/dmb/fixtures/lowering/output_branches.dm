#define FILE_DIR "."
/var/list/force_516 = alist()
/obj
    var/value
/proc/out_field(obj/O, a, b)
    O.value << (a ? b : 3)
/proc/out_index(list/L, k, a, b)
    L[k] << (a ? b : 3)
/proc/out_receiver(obj/A, obj/B, a, b)
    (a ? A : B).value << (b || 5)
/proc/ctor_branch(a,b)
    var/list/L = new /list(a ? b : 2)
    return L
