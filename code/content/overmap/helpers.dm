/proc/get_overmap_sector(z)
	if(using_map.use_overmap)
		return read_once(GLOB.map_sectors["[z]"])
	else
		return null
