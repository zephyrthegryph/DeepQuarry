/datum/holder
 var/list/available_station_software
 var/list/available_other_software
/datum/holder/proc/build_software_lists()
 available_station_software=list()
 available_other_software=list()
 return available_station_software
/proc/world_output_fields()
 world.log << world.maxx+world.maxy
