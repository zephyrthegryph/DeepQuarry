# Vore option profile cohort

Source-only; verification is pending the coordinated gate. This cohort removes sixteen
`base_var` rows from `code/modules/vore/eating`: gain/loss rates, voice frequency,
emote sound mode, trash catching, entry-log muting, liquid visuals, the two
admin feeding switches, appendage color/mode, whole-food feeding, skin reagent and
injection reagent/amount/verb. They now live in an owned `/datum/record/vore_options`,
built by the existing profile mechanism before mob initialization.

This is deliberately separate from `vore_prefs`: copying consent preferences to a
transformed mob copied only the two explicit appendage fields, not the other
options. The same three physique fields still copy in
`copy_physique_from`, without accidentally copying the other options. Preference
application still uses the original `weight_gain`, `weight_loss`, `voice_freq`
and `emote_sound_mode` save keys. There is no save schema change. Every runtime
write uses the profile setter; every production reader uses the record. SWOOPIE's
per-type admin-trash default is a profile starting field in its existing single
capability block. No duplicate base state remains.

Focused selectors: `dq_vore_options_home` and `dq_vore_trait_option_home`. They assert private records, all sixteen
original defaults, real preference application and unchanged serialized keys,
actual toggle verbs, custom-frequency zero/clamping, physique-copy boundaries and
consent-copy boundaries. Also rerun the adjusted existing
`dq_med6_life_stages_idle_when_healthy` fixture.

The remaining 34 eating rows include transient counters, callbacks and references.
The existing three serialized trait keys (`appendage_color`,
`appendage_alt_setting`, `stuffing_feeder`) retain their schemas and metadata. The
real trait dispatcher now routes those keys to the profile setters for apply and
reset; all unrelated keys retain their existing behavior. Reset still restores
initial values, not the type-configured/current values. Real trait apply/unapply
is covered in the second selector. Plants and scel retain their per-type color
defaults through existing profile starting-field declarations. Transformation
copying still copies only the two original appendage options.

Mutable voice sound lists retain their existing identity and default behavior;
this cohort does not replace them with null. Injection uses the same selected
reagent and exact original amount/string; the existing reagent behavior fixture
is migrated to the profile setters too.
