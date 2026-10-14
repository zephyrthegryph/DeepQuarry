# Portable machine cell redraw follow-up

The pump and scrubber native looks now watch their actual cell. Emptying or restoring charge invalidates a warmed running indicator without the retired power-change/update-icon relay. The two obsolete derived-read annotations are removed.

Real-cell tests cover pump and scrubber charge transitions, stored-cell overlays, and the recharged laser's charge meter. Verification is pending. Focus: dq_requirement_protocol_pin, dq_conversion_pin, dq_portable_cell_redraw, dq_stored_cell_redraw, dq_recharger_energy_native_redraw. No pin goldens or baselines have changed.

The stored-cell fixture reuses the floodlight and heater's actual starting cells. Only an empty bay receives a newly allocated cell. This preserves the floodlight's contained ownership policy and avoids leaving an untracked displaced starting cell.
