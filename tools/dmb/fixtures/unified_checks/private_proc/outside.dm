/datum/unrelated/proc/probe(datum/access/exact, datum/access/child/derived)
    exact.secret(derived.secret(1))
    derived.secret(exact.secret(1))
    exact.guarded(exact.secret(1))
/proc/synthetic_probe()
    var/list/items[2]
