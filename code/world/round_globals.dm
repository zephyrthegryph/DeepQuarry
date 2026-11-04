GLOBAL_VAR_INIT(game_year, (text2num(time2text(world.realtime, "YYYY")) + 544))
GLOBAL_VAR_INIT(round_progressing, TRUE)

GLOBAL_VAR_INIT(master_mode, "extended") // "extended"
GLOBAL_VAR_INIT(secret_force_mode, "secret") // if this is anything but "secret", the secret rotation will forceably choose this mode.
