# Static initializer lifetime runtime contract

Two constructions of the same datum must initialize its static slot once. Both
receivers initially read7; a write through the first is visible as19 through the
second. The instance contrast performs its initialization in `New()`, producing
11 and22 with two initializer calls. This avoids an illegal runtime expression
in an instance field default. These are independent expected values, pending
actual pinned BYOND/native execution; they do not establish historical power
runtime causality.

`run.py` reuses the existing bounded paired runtime launcher and transports the
explicit resource with digest checks. `run_retained.py` reuses the existing
single-daemon contract: initial, unchanged, body return7→13, then an unrelated
instance default insertion. Every revision requires fresh/retained DMB and RSC
byte equality plus independent BYOND runtime marker equality and no runtimes.
Each revision creates a new world; static lifetime is per world, not across DD
processes. No new runtime executor or cache is introduced.

Run either entrypoint with the same explicit native/template/DM/DD pins and an
owned E:/dq-cache output root as callable_semantics_runtime. Root dispatches the
bounded execution. No execution is performed by authoring this fixture.
