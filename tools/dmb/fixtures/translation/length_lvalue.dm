var/global/list/G
/proc/length_pre(list/L)
    return ++length(L)
/proc/length_post(list/L)
    return length(L)--
/proc/length_add(list/L,N)
    return length(L) += N
/proc/length_field(datum/holder/H)
    return --length(H.L)
/proc/length_index(list/L,K)
    return ++length(L[K])
/proc/length_global()
    return length(G)++
/proc/length_statement(list/L)
    --length(L)
    return length(L)
/proc/load_native_ext(Library,Function)
    return load_ext(Library,Function)
/datum/holder
    var/list/L
