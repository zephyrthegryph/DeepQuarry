/obj/outer
    var/child
/obj/inner
    var/amount
/proc/modified_value()
    return /obj/outer{child=/obj/inner{amount=7}}
/proc/unrelated()
    return 2
