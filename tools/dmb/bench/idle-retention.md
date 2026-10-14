# Idle retention diagnosis

`DMB_IDLE_CENSUS_PATH` enables an append-only JSON-lines owner census immediately
before and after a daemon host releases rich buffers. Leave it unset during timed
cohorts: the census walks retained owners and allocates its own pointer ledger.
Set it in the daemon's environment before starting that daemon. Client-only
environment changes do not affect an existing daemon.

Each record identifies the session, release boundary, category and report.
Categories may share allocations. **Do not sum category totals**, or present
their exposed container capacities as process-private memory. Private indexes,
allocator metadata and freed-but-reserved pages remain explicitly unknown.

The ordinary daemon release log independently records Windows private bytes
before and after rich-buffer release and the release duration. This small
boundary sample does not prove peak memory, continuous isolation, or that the
allocator returned every released page to Windows.

Use a separate bounded diagnostic run after the measured cohort has finished.
Keep the 4 GB daemon pressure threshold and compiler worker limits in place.
Compare the largest surviving categories to the later whole-session release;
fix their ownership or representation rather than hiding pressure eviction by
raising the threshold.
