# Voice sound-list profile home

Source-only; one eating `base_var` row removed, verification pending. The actual
sound selection list now lives with the native voice options. The existing
profile's starting-fields form supplies a fresh empty list per mob before init,
preserving the original non-null empty-list behavior without a new annotation.
The retired per-mob initialized-list annotation is removed. All consumers,
preference/login writers, prompt callbacks and explicit physique copying use the
profile; whole-list assignment still retains the exact sound-list identity.
No whole-profile copying or new serialization is introduced.

Focused selectors: `dq_voice_sound_list_home` and the existing
`interim_voice_type_request` (actual choice/cancel/stale-submit behavior), alongside
`dq_vore_options_home` and `dq_vore_trait_option_home`. The new leaf asserts actual
non-null empty defaults, per-mob identity, real setter identity and isolation.
