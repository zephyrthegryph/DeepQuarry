/obj/worker_item
    var/amount = 0

/datum/worker_base
    var/value = 1
    var/asset = 'asset.txt'
    var/modified = /obj/worker_item{amount=1}
    proc/read_value()
        return value
