var/const/inventory_fixture_resource = 'contract-resource.txt'
/datum/inventory_test
    var/tier = 0
/datum/inventory_test/normal
/datum/inventory_test/exhaustive
    tier = 1
/world/New()
    ..()
    var/resource_text = file2text(inventory_fixture_resource)
    var/list/paths = typesof(/datum/inventory_test) - /datum/inventory_test
    var/typed_count = 0
    for(var/datum/inventory_test/test_path in paths)
        typed_count++
    var/untyped_count = 0
    var/excluded_count = 0
    for(var/test_path in paths)
        var/datum/inventory_test/test_type = test_path
        untyped_count++
        if(initial(test_type.tier) == 1)
            excluded_count++
    world.log << "DQ_INVENTORY typed_count [typed_count]"
    world.log << "DQ_INVENTORY untyped_count [untyped_count]"
    world.log << "DQ_INVENTORY excluded_count [excluded_count]"
    if(resource_text)
        world.log << "DQ_INVENTORY finished"
    shutdown()
