// DQ-migrated: equipment scalar prefs.
//
// headset/backbag/pdachoice prefs deleted. Headsets and backpacks are now
// regular loadout gear datums (see code/datums/gear/loadout_standard_kit.dm),
// and the PDA chassis pick was purely cosmetic — players get the default chassis.
// Mob vars H.headset / H.backbag / H.pdachoice still exist with their hardcoded defaults
// in human_defines.dm; the job-outfit pre_equip and antag spawners that read them
// continue to work unchanged (just always pick the canonical first variant now).

// no_jacket pref deleted. Players who want to spawn without a uniform jacket
// pick a different uniform via the regular loadout system. Existing code that read the
// pref (job.dm equip_rank, outfit.dm equip_base) now equips the default unconditionally.


