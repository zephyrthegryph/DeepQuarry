/proc/global_parameter(/var/global_parameter_value = 7)
    return global_parameter_value
/proc/global_parameter_read()
    return global_parameter_value
/proc/global_parameter_write(value)
    global_parameter_value = value
    return global_parameter_value
/var/list/force516=alist()