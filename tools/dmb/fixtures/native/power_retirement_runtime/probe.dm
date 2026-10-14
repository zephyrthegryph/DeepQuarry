// Deterministic historical power_bridge event decoder, without FFI or game boot.
#define POWER_EV_BIND 1
#define POWER_EV_RETIRED 3
var/global/retirement_branches = 0
var/global/retirement_completed = 0

/datum/retirement_network
    var/marker = 7

/proc/decode_retirements(list/events, list/power_regions, label)
    var/count = 0
    var/i = 1
    var/len = length(events)
    while(i < len)
        var/kind = events[i]
        var/n = events[i + 1]
        var/at = i + 2
        i = at + n
        count++
        switch(kind)
            if(POWER_EV_BIND)
                world.log << "DQ_RETIRE bind [label]"
            if(POWER_EV_RETIRED)
                retirement_branches++
                world.log << "DQ_RETIRE lookup [label] [at]"
                var/datum/retirement_network/network = power_regions[events[at]]
                if(network)
                    world.log << "DQ_RETIRE network [label] [network.marker]"
                    power_regions -= events[at]
                retirement_completed++
    world.log << "DQ_RETIRE decoded [label] [count]"

/proc/run_retirement_case(label, list/events, list/regions)
    retirement_branches = 0
    retirement_completed = 0
    world.log << "DQ_RETIRE begin [label]"
    decode_retirements(events, regions, label)
    // Runtime errors terminate the called decoder; its caller still reports.
    world.log << "DQ_RETIRE end [label] [retirement_branches] [retirement_completed]"

/world/New()
    ..()
    var/datum/retirement_network/network = new
    run_retirement_case("valid", list(POWER_EV_RETIRED, 1, 1), list(network))
    run_retirement_case("outer_bounds", list(POWER_EV_RETIRED, 1, 999), list(network))
    run_retirement_case("inner_bounds", list(POWER_EV_RETIRED, 1), list(network))
    run_retirement_case("mixed_packets", list(POWER_EV_BIND, 1, 0, POWER_EV_RETIRED, 1, 1), list(network))
    world.log << "DQ_RETIRE finished"
    shutdown()
