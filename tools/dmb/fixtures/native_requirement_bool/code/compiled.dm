/proc/req_bool(value)
    return value
/proc/needs(value)
    return value
#define WRAPPED(x) req_bool(x)
#define REQ_TAG(x) x
/obj/probe
    proc/run(holder)
        needs(
            req_bool(1))
        var/x = WRAPPED(2)
        holder.req_bool(3)
        global.req_bool(4)
        req_bool(5).next()
        for(var/i=req_bool(6);req_bool(7);req_bool(8))
            needs(REQ_TAG(9))
        ::WRAPPED(11)
        return
        WRAPPED(10)
