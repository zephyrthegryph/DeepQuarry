# Living voice and butchery configuration

Nine base fields move to native copy-on-write type traits: five sound/pain
configuration values and four butchering configuration values. Existing type
defaults become configure entries in their existing CAPABILITIES blocks; types
without a block get one. Shared pain-alternative lists retain their original
reference semantics. Mutable meat stock, consumed loot and existing owned sound
datums are unchanged. Historical map/VV field names route through var_names;
explicit FALSE and null overrides retain their meanings.

The say_list_type field is deliberately retained: mecha rolls that field through
rolls(nameof(say_list_type)), whose existing implementation writes a real holder
var. A trait-target roll needs an actual supported contract, not a replacement
wrapper. DNA and species datum sound fields are independent and untouched.

New focused selectors are dq_voice_configuration_home and
dq_butchery_configuration_home. They exercise real emote/sound readers, actual
harvest output and decrement, map writes, admin edits and peer/type isolation.
Existing dq_living_ability_tests runtime overrides now use native set_trait.
Root must include code/__defines/mob_configuration.dm with the defines and
code/modules/unit_tests/dq_mob_configuration_home_tests.dm with unit tests.
No generation, analyzer, compile or runtime verification was run for this cohort.
Baseline updates remain pending; expected additional reduction is nine rows.

The source preflight caught six cross-file composition-root duplicates. Their
configuration entries are now merged into the existing canonical blocks in
simple_mob.dm, denecrotizer.dm, the two combat_ai glitch ports, metBaseType.dm
and bigdragon.dm. A full source-only scan confirms one literal CAPABILITIES
block per type. No existing entry was removed. Verification remains pending.
