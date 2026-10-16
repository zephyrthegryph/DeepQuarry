# Blood constructor context (review draft)

Fourteen init rows become a typed holder-init capability, using the real `A.mapload`, plus `keeps_if()` for the old QDEL hint. No runtime verification has run. Include the new test file and run `/datum/unit_test/dq_init_objects_blood_context` and its `/mapload_and_discard` leaf.

The atom root has already set its own ATOM_INITIALIZED bit before this hook; peer bits are unchanged. The old body consumes only initialized *other* puddles, never the current holder. A marked holder returns from the hook, then keeps_if records deferred discard; the atoms system waits for the complete Initialize chain exactly as for the old returned QDEL hint. The actual animated descendant only remembers its location in its tail; the regression checks that tail still executes. Inherited persistence registration is still forgotten on discard. No new immediate holder qdel occurs inside engine_holder_init.

The inherited age/contagion apply callback runs later than the new hook, but this blood body reads neither age nor viruses. Blood subtype amount is bound before capabilities. No blood descendant except animated has an Initialize override; animated does not read drying or forensics. Dry-delay scheduling is only armed after the chain, preserving mapped-vs-runtime timing. New tracked delete/delay setters preserve genuine keeps_if and after_init dependencies.
