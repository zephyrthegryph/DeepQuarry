/proc/FLOAT_LAYER_power()
    return FLOAT_LAYER**2
/proc/FLOAT_LAYER_negpower()
    return -FLOAT_LAYER**2
/proc/FLOAT_LAYER_multiply()
    return FLOAT_LAYER*2
/proc/FLOAT_LAYER_negative()
    return -FLOAT_LAYER
/proc/FLOAT_LAYER_divide()
    return 8/FLOAT_LAYER
/proc/FLOAT_LAYER_parenthesized()
    return (FLOAT_LAYER)**2
/proc/FLOAT_PLANE_power()
    return FLOAT_PLANE**2
/proc/FLOAT_PLANE_negpower()
    return -FLOAT_PLANE**2
/proc/FLOAT_PLANE_multiply()
    return FLOAT_PLANE*2
/proc/FLOAT_PLANE_negative()
    return -FLOAT_PLANE
/proc/FLOAT_PLANE_divide()
    return 8/FLOAT_PLANE
/proc/FLOAT_PLANE_parenthesized()
    return (FLOAT_PLANE)**2
/proc/negative_power()
    return -2**2
/proc/grouped_negative()
    return (-2)**2
/proc/negative_group()
    return -(2**2)
/proc/power_chain()
    return 2**3**2
/proc/left_power()
    return (2**3)**2
/proc/negative_chain()
    return -2**3**2
/proc/logical_power()
    return !0**0
/proc/logical_group()
    return !(0**0)
/proc/bitwise_power()
    return ~2**2
