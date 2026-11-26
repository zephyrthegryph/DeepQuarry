/// The size in bytes of a file on disk, from its metadata (no read), or null when it does not exist.
/proc/file_size_on_disk(path)
	return vg_file_size(path)
