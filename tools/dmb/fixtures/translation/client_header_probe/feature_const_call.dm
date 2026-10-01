var/const/LIB = "test.dll"
/proc/feature_probe()
    return call(LIB,"symbol")()
