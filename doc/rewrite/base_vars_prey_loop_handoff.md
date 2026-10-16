# Belly sound replay cooldown

Source-only: one eating `base_var` row removed, verification pending. The per-mob
`next_preyloop` deadline now lives in the existing declared cooldown table. The
real sound replay handler still requires sound consent, a wet belly and its wet
loop; it uses the same strict `< world.time` readiness and 52-second duration.
No deadline/clock semantics changed.

Focused selector: `dq_prey_loop_cooldown_home`. It runs the real replay handler on
an actually contained sound-enabled fixture, asserts the deadline and unaffected
outside audience, then checks exact-expiry refusal and post-expiry replay. The
fixture overrides only the client's sound preference lookup because it has no
client, leaving the production audience selection/replay logic intact.
