/proc/test()
    for()
        break
    for(var/x = 0; 1; x++)
        break
    for(var/y = 0; 5 <= 7; y++)
        break
    for(var/z = 1; z <= 6; z++) // Legit, should have no error
        break
    return
