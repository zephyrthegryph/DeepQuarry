# Fake-attacker image cache cohort (source only)

Owner directory `code/modules/flufftext/`: one list_init row removed. The private cardinal-image cache is null until create_images_from actually builds images, then uses existing LAZYSET. Client assignment checks are null-safe and teardown clears the list lazily after deleting its actual images. The four image definitions, directional cache keys, appearance copying, movement animation and client behavior are unchanged. No shared/static cache or ownership policy is substituted.

`dq_fake_attacker_cache_home` checks no pre-source allocation, real cardinal images/appearance, real movement anchor changes and qdel clearing actual image references. No generation, compile, tests, baseline update or stamp has run.
