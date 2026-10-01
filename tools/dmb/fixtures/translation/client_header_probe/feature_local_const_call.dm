/proc/feature_probe()
    var/const/lib = "test.dll"
    return call(lib,"symbol")()
