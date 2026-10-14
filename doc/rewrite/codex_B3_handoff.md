# B3 supply and contracts boundary handoff

system_boundary146→127:10 private-state rows (41 accesses) and9 externally-defined-proc rows (59 methods) removed. The59 method headers/bodies moved unchanged into owner API files, included at their original declaration positions. Console/PDA/shipping callers use identity-preserving owner APIs; detached lists preserve iteration order and live UI refs are checked against owner membership. One additional unbaselined malignant-organ export-rate read now uses money_to_export_points, preserving fractional units.

New tests dq_contract_boundary and dq_supply_boundary cover registry snapshots, live ref admission, catalog identity, shipping queue membership, fractional conversion and counter reads. Focused owner workflow coverage will be verified in the serialized lane gate. No remaining production private-state or external-owner-proc sites found for these owners. No tracked/setter/ownership declaration changes. No push or merge.
