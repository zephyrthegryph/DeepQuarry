# Emote cooldown-home cohort (source only)

Owner directory `code/modules/emotes/`: three base vars removed. `next_emote` and `next_emote_refresh` use the existing native cooldown table, with the exact same strict `< world.time` readiness and absolute world-time deadline. The carbon slip consumer reads that same native deadline. The emote-help summary was assigned then read only in one help branch, so it becomes a local value rather than a cached base var. The belly's separate `next_emote` member and cadence are unchanged.

Required external edits are the mob's existing cooldown declaration and the carbon slip consumer. No new CAPABILITIES block/base var, no changed clock, and no change to emote output/rate limits. `dq_emote_cooldown_home` exercises a real default nod, exact boundary/readiness, independent mobs and independent refresh versus ordinary cooldowns. Source only; no generation, compile, tests, baseline update or stamp yet.
