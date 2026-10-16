# Remove retired identity shadows

Source-only; seven `base_var` rows removed, verification pending. Nickname, flavor
text and the four character records already live in the owned `bio` profile.
These six unused `/mob` declarations were leftover duplicates. All actual mob
consumers and preference writers already read/write `bio`; the bare names in the
vore slot chooser and hologram examine are locals, not missed field readers.
No consumer behavior, save keys, profile fields or defaults change.

Focused selectors: `dq_identity_shadow_retirement`, `dq_profile_record_basics`,
`dq_profile_pref_save_roundtrip`, `dq_profile_records_on_every_mob`. The new test
asserts absence of all six duplicate fields, actual profile storage and the real
flavor-text reader, then verifies native record copying and identity isolation.

The seventh field, `do_afters`, was the retired scheduler's unused per-mob list.
A tracked-code and maps search finds only its declaration, with no reader,
writer, subtype default or serialized key. Its absence is asserted explicitly;
no live task or wait state is changed.
