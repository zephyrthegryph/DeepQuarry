/datum/smoke_math
    var/base = 4
    var/datum/smoke_modified/child
    var/grid[3][2]
    var/static/shared_count = 0
    var/static/list/shared_values = list(6, 7)
    var/list/items = list (1, 2)
    var/list/pairs = alist("native"=4)

/datum/smoke_math/proc/add(value)
    return base + value

/datum/smoke_math/proc/context_reference()
    return __TYPE__ == /datum/smoke_math && __PROC__ == /datum/smoke_math/proc/context_reference && nameof(type::base) == "base"

/datum/smoke_math/proc/renamed_method()
    set name = "Method title"
    return 17

/datum/smoke_math/verb/smoke_verb()
    return 19

/datum/smoke_math/child/add(value)
    value += 1
    return ..()

/datum/smoke_modified
    var/value = 2
    var/observed
    var/list/items
    var/observed_length
    var/type_default = /datum/smoke_math::base
    var/list/empty_newlist = newlist()

/datum/smoke_modified/New()
    observed = value
    observed_length = length(items)

/particles/smoke_particle
    color = 0
    position = generator("circle", 0, 16, NORMAL_RAND)

/mob/smoke_mob
    var/observed = 7

/var/global/list/smoke_global = list(3, 4)
/var/global/smoke_array[2][3]
/var/global/smoke_qualified = 3
/var/global/smoke_handler = /proc/smoke_counter
/var/global/smoke_shift = -1 << 1
/var/global/smoke_modulo = 5.5 % 2

/proc/smoke_counter()
    var/static/count = 0
    count += 1
    return count

/proc/smoke_vars_shadow()
    var/static/list/vars = list(4, 5)
    return vars[1] + global.vars["smoke_qualified"]

/proc/smoke_implicit_return(value)
    . = value
    . += 1

/proc/smoke_labeled_loops()
    var/count = 0
    break_loop:
        for(var/outer in list(1, 2, 3))
            for(var/inner in list(4, 5))
                count += 1
                if(count == 3) break break_loop
    world.log << "LABEL_BREAK [count]"
    if(count != 3) return FALSE
    count = 0
    var/total = 0
    continue_loop:
        for(var/outer in list(1, 2, 3))
            for(var/inner in list(4, 5))
                count += 1
                total += outer
                if(count > 8)
                    world.log << "LABEL_CONTINUE_FAIL [count] [total]"
                    return FALSE
                continue continue_loop
    world.log << "LABEL_CONTINUE [count] [total]"
    return count == 3 && total == 6

/proc/smoke_comparisons(value)
    var/list/results = list(value == 3, value != 3, value < 4, value > 4, value <= 3, value >= 4)
    if(results[1] != 1 || results[2] != 0 || results[3] != 1 || results[4] != 0 || results[5] != 1 || results[6] != 0)
        return FALSE
    var/equal = value == 3
    var/unequal = value != 3
    var/less = value < 4
    if(!equal || unequal || !less) return FALSE
    if(!(value == 3) || !(value != 4)) return FALSE
    if((value == 3 ? 7 : 8) != 7) return FALSE
    if((value != 3 ? 7 : 8) != 8) return FALSE
    return (value == 3 && value < 4) && (value != 3 || value >= 3)

/proc/smoke_goto_iterator()
    var/count = 0
    for(var/outer in list(1, 2, 3))
        for(var/inner in list(4, 5))
            count += 1
            if(count == 3) goto completed
    completed:
        return count == 3

/proc/smoke_switch_range(value)
    switch(value)
        if(4 to 6) return 20
        if(1 to 3) return 10
        else return 30

/proc/smoke_exercise()
    if(!(/datum/smoke_math/proc/add in typesof(/datum/smoke_math/proc))) return -36
    var/created_verb = new /datum/smoke_math/verb/smoke_verb()
    if(created_verb != /datum/smoke_math/verb/smoke_verb) return -38
    if(smoke_vars_shadow() != 7) return -39
    if(smoke_shift != 0 || smoke_modulo != 1) return -40
    if((5.5 % 2) != 1 || (-5.5 % 2) != -1 || (-1 >> 1) != 8388607 || (1 << 24) != 0 || (-1 << 1) != 0) return -41
    var/mob/smoke_mob/smoke_mob = new
    if(!ismob(smoke_mob) || smoke_mob.type != /mob/smoke_mob || smoke_mob.observed != 7) return -42
    del(smoke_mob)
    var/list/empty = list()
    if(length(empty) != 0) return -34
    var/list/logical_left = list(0, 1)
    var/list/logical_right = list(7, 9)
    logical_left[1] ||= logical_right[1]
    logical_left[2] &&= logical_right[2]
    if(logical_left[1] != 7 || logical_left[2] != 9 || logical_right[1] != 7 || logical_right[2] != 9) return -37
    if(/datum/smoke_math/child::base != 4) return -30
    if(smoke_switch_range(2) != 10 || smoke_switch_range(5) != 20 || smoke_switch_range(9) != 30) return -28
    if(!smoke_goto_iterator()) return -27
    if(!smoke_comparisons(3)) return -25
    if(!smoke_labeled_loops()) return -24
    if(smoke_implicit_return(5) != 6)
        return -12
    var/datum/smoke_modified/modified = new /datum/smoke_modified{value=11;items=list(1,2)}
    if(modified.value != 11 || modified.observed != 11 || modified.observed_length != 2)
        return -13
    if(modified.type_default != 4 || length(modified.empty_newlist) != 0) return -29
    if(modified.type != /datum/smoke_modified) return -31
    if(modified.parent_type != /datum) return -32
    if(length(typesof(/datum/smoke_modified)) != 1) return -33
    var/datum/smoke_math/math = new
    if(!math.context_reference()) return -19
    if(math.renamed_method() != 17) return -20
    if(math?.renamed_method() != 17) return -22
    var/datum/smoke_math/derived = new /datum/smoke_math/child
    if(derived.add(1) != 6) return -21
    var/particles/smoke_particle/particle = new
    if(particle.count != 100 || particle.color != 0 || isnull(particle.position)) return -23
    if(math.pairs["native"] != 4) return -18
    global.smoke_qualified = 9
    if(global.smoke_qualified != 9) return -14
    if(!islist(global.vars) || global.vars["smoke_qualified"] != 9) return -35
    math.child = new()
    if(!istype(math.child) || math.child.value != 2) return -15
    var/list/pairs = alist("a"=2,"b"=3)
    var/pair_total = 0
    for(var/key, value in pairs)
        pair_total += value
    if(pair_total != 5) return -16
    var/list/values = list(2, 3, 5)
    var/total = 0
    for(var/value in values)
        total += value
    if(math.add(total) != 14)
        return -1
    if(length(math.items) != 2 || smoke_global[2] != 4)
        return -2
    if(smoke_counter() != 1 || smoke_counter() != 2)
        return -3
    if(call(smoke_handler)() != 3) return -17
    if(length(math.grid) != 3 || length(math.grid[1]) != 2)
        return -7
    if(length(smoke_array) != 2 || length(smoke_array[1]) != 3)
        return -8
    var/datum/smoke_math/other = new
    math.shared_count = 9
    math.shared_values[1] = 8
    if(other.shared_count != 9 || other.shared_values[1] != 8)
        return -9
    math.base = 5
    if(math.add(total) != 15)
        return -4
    try
        throw 7
    catch(var/problem)
        if(problem != 7)
            return -5
    switch(total)
        if(1) return -26
        if(10) total = 20
        else return -6
    var/steps = 0
    while(steps < 2) steps += 1
    for(steps = 0, steps < 3, steps += 1);
    if(steps != 3) return -10
    for(steps = 0, ++steps < 3);
    if(steps != 3) return -11
    return min(20, 30) + max(2, 3)

/world/New()
    ..()
    world.log << "RUST_COMPILER_SMOKE [smoke_exercise()]"
    del(world)
