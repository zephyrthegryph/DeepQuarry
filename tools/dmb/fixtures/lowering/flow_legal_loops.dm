/proc/flow_assoc_indexed(list/input, list/output)
    for(output[1], output[2] in input)
        output[3] = 1
    return output

/proc/flow_safe_indexed(list/input, list/output)
    var/i = 0
    for(output?[i++] in input)
        .++
    return i

/proc/flow_empty_named_catch()
    try
        throw "test"
    catch(var/e)
    return 1

/proc/flow_constant_range()
    var/out = 0
    for(var/x = 2 in 1 to 20; x < 6; x++)
        out += x
    return out

/proc/flow_indexed(list/input, list/output)
    var/i = 0
    for(output[i++] in input)
        .++
    return i

/proc/flow_assoc_indexed_value(list/input, list/output)
    var/key = 1
    for(key, output[2] in input)
        output[3] = key
    return output

/proc/flow_assoc_indexed_key(list/input, list/output)
    var/value = 1
    for(output[1], value in input)
        output[3] = value
    return output

/proc/loop_owner(list/output)
    return output

/proc/loop_key()
    return 1

/proc/flow_effectful_indexed(list/input, list/output)
    for(loop_owner(output)[loop_key()] in input)
        .++
    return output

/proc/flow_effectful_range(list/output)
    for(loop_owner(output)[loop_key()] in 1 to 3)
        .++
    return output

/proc/flow_filtered_indexed(list/input, list/output)
    for(loop_owner(output)[loop_key()] as num in input)
        .++
    return output

/proc/flow_conditional_indexed(list/input, list/output, mode, fallback)
    for(var/item as anything in input)
        for((mode ? output : input)[mode || fallback] in input)
            .++
    return output

/proc/flow_conditional_assoc(list/input, list/output, mode, fallback)
    for(var/item as anything in input)
        for((mode ? output : input)[mode || fallback], output[mode ? 2 : 1] in input)
            .++
    return output
/proc/flow_typed_assoc(list/input)
    for(var/obj/O, value in input)
        .++
    return input
/proc/flow_conditional_range(list/output, mode, fallback)
    for((mode ? output : loop_owner(output))[mode || fallback] in 1 to 3)
        .++
    return output
