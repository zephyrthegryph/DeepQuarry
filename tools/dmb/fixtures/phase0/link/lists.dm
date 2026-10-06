/world/New()
    ..()
    var/list/L = list("z", "a", "z", "m")
    phase0_emit("sequence", L)
    var/list/A = list("z" = 1, "a" = 2, "m" = 3)
    A["a"] = 4
    var/list/keys = list()
    var/list/values = list()
    for(var/key in A)
        keys += key
        values += A[key]
    phase0_emit("associative_keys", keys)
    phase0_emit("associative_values", values)
    A -= "a"
    A["a"] = 5
    keys = list()
    for(var/key in A)
        keys += key
    phase0_emit("reinserted_keys", keys)
    phase0_finish()
