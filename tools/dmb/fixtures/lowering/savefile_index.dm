/proc/savefile_read(var/savefile/file, var/key, var/value)
    file[key] >> value
    return value

/proc/savefile_read_into_list(var/savefile/file, var/key, var/list/values, var/index)
    file[key] >> values[index]

/proc/savefile_write(var/savefile/file, var/key, var/value)
    file[key] << value

/proc/savefile_read_field(var/savefile/file, var/key, var/atom/owner)
    file[key] >> owner.name
