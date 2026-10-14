var/const/R_COMPONENT = 255
/datum/probe
    var/source_red = 255
    var/rgb_three = rgb(255,201,49)
    var/rgb_four = rgb(255,201,49,128)
    var/rgb_fractional = rgb(12.9,0.9,254.9)
    var/rgb_outside = rgb(-5,300,512)
    var/rgb_alias = rgb(R_COMPONENT,201,49)
    var/rgb_runtime = rgb(source_red,201,49)
/proc/rgb_three()
    return rgb(255,201,49)
/proc/rgb_four()
    return rgb(255,201,49,128)
/proc/rgb_fractional()
    return rgb(12.9,0.9,254.9)
/proc/rgb_outside()
    return rgb(-5,300,512)
/proc/rgb_alias()
    return rgb(R_COMPONENT,201,49)
