/proc/read_value(savefile/source, value)
    source >> value
/proc/write_value(savefile/source, value)
    source << value
/proc/shift_return(value)
    return value >> 1

/proc/read_entry(savefile/source, value)
    source["entry"] >> value
/proc/write_entry(savefile/source, value)
    source["entry"] << value
