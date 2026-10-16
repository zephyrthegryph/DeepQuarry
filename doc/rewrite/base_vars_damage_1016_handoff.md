# Damage configuration base-variable cohort

Three base declarations move to one inheriting `damage_profile` type trait: damage wear text, damage-band announcements and ionic integrity susceptibility. Existing window, door, sensor, shield and projector defaults become declarations in their existing capability blocks. Damage sinks, EMP routing and examine/announcement text read the same values through the profile.

Historical map/VV names map to the trait fields; native writes copy on write and publish its dependency key. No ownership, timer, lifetime or damage formula changes are intended.

Source coverage: `dq_base_vars_damage` checks shared defaults, all five specialized policies, old-name override isolation, actual examine text, real ionic damage and explicit-zero admin overrides. It has not been compiled or run here; root owns generation, baseline updates and verification. Source estimate: three baseline identities removed, not an analyzer-confirmed count.
