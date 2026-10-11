/proc/insert_receiver(icon/receiver, icon/source)
    receiver.Insert(source)
    return receiver

/proc/map_colors_receiver(icon/receiver)
    receiver.MapColors(1, 0, 0, 0, 1, 0, 0, 0, 1)
    return receiver
