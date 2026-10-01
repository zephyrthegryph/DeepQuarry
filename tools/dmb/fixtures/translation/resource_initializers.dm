var/global/resource_source = 'asset.txt'
/datum/resource_initializers
    var/file_literal = file('asset.txt')
    var/icon_literal = icon('asset.txt', "")
    var/static/static_file_literal = file('asset.txt')
    var/static/static_file_dynamic = file(resource_source)
    var/static/static_icon_literal = icon('asset.txt', "")
    var/static/static_icon_dynamic = icon(resource_source, "")
/var/list/force516=alist()