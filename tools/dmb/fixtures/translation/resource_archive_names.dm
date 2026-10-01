#define FILE_DIR "resource_archive_assets/external"
/proc/resource_names()
    return list('ExternalAsset.txt','externalasset.txt','./ExternalAsset.txt','ExternalAsset\.txt','a\'b.txt','Tab\tName.txt','sub/Part.txt','sub\\Part.txt','resource_archive_assets/normal.txt','resource_archive_assets/opaque.bin')
/proc/resource_kinds()
    return list('resource_archive_assets/tiny.bmp','resource_archive_assets/tiny.jpg','resource_archive_assets/tiny.png',
        'resource_archive_assets/probe.mod','resource_archive_assets/probe.it','resource_archive_assets/probe.xm','resource_archive_assets/probe.s3m','resource_archive_assets/probe.zip','resource_archive_assets/probe.rsc','resource_archive_assets/probe.wma','resource_archive_assets/probe.ico','resource_archive_assets/probe.cur','resource_archive_assets/probe.au','resource_archive_assets/probe.aif','resource_archive_assets/probe.flac','resource_archive_assets/probe.m4a','resource_archive_assets/probe.avi','resource_archive_assets/probe.wmv','resource_archive_assets/probe.mpeg','resource_archive_assets/probe.webm','resource_archive_assets/probe.svg','resource_archive_assets/probe.dat','resource_archive_assets/probe.jpeg')
