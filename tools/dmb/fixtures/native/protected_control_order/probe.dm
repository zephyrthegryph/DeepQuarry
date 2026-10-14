var/global/control_asset = 'contract-resource.txt'
/world/New()
    ..()
    world.log << "DQ_PROTECTED return=[nested_return()] resource=[control_asset]"
    world.log << "DQ_PROTECTED loop=[caught_loop_transfers()]"
    world.log << "DQ_PROTECTED switch=[switch_throw()]"
    world.log << "DQ_PROTECTED finished"
    shutdown()
