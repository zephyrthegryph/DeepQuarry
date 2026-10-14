# Portable machine cell redraw follow-up

The pump and scrubber native looks now watch their actual cell. Emptying or restoring charge invalidates a warmed running indicator without the retired power-change/update-icon relay. The four obsolete derived-read annotations and two duplicate derived() tables are removed.

Real-cell tests cover pump and scrubber charge transitions, stored-cell overlays, and the recharged laser's charge meter. Verification is pending. Focus: dq_requirement_protocol_pin, dq_conversion_pin, dq_portable_cell_redraw, dq_stored_cell_redraw, dq_recharger_energy_native_redraw. No pin goldens or baselines have changed.

The stored-cell fixture reuses the floodlight and heater's actual starting cells. Only an empty bay receives a newly allocated cell. This preserves the floodlight's contained ownership policy and avoids leaving an untracked displaced starting cell.

The first gate 9519f5e721 stopped on two legacy derived-read findings before runtime verification; it is interrupted and unstamped. The duplicate derived() tables and their now-unused annotations are retired in favor of generated native draw reads plus the actual-cell watch. Targeted dependency checks pass without baseline changes. A new complete gate is required.
