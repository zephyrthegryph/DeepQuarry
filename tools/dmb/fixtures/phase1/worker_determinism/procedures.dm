/proc/worker_global()
    var/static/local = 3
    return local + 4

/proc/worker_modified()
    return (/obj/worker_item{amount=1})
