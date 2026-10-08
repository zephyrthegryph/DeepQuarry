// Legacy names forward to the real generic engine implementation.

/proc/om_native_watch_of(handle)
	return kernel_native_native_watch_of(arglist(args))

/proc/om_native_dispatch(handle, list/arguments)
	return kernel_native_native_dispatch(arglist(args))
