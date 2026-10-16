# Last-attacker native relation

Source-only; one `/atom` `base_var` row removed, verification pending. Last attack
attribution is now a declared single non-owning native link to its actor, with a
many inverse. The two actual writers (ordinary item attack and anodevice tap)
record the same actor at the same point before logging/effects. Death reporting
reads the same actor's current name/key through the typed lookup. Attribution
replacement, explicit clearing and endpoint deletion remove the link without
owning or deleting the other endpoint. Existing debug/attack logging is retained.

Focused selector: `dq_last_attacker_link_home`. It exercises both real attack
writers, actual replacement and inverse membership, clearing without deletion,
and endpoint-qdel cleanup. Existing damage/melee workflows should accompany it.
The declaration is added to the existing single `/atom` block; no base pointer,
shadow datum state, lifetime ownership or extra per-atom record is introduced.
