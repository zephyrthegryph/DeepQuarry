Pinned checker parent search reaches global source and builtin procs, unlike
native runtime instance-method lookup. Independent reference gives only the
seeded genuine_missing error at (8,12). Keep runtime query behavior unchanged.
Command: dreamchecker.exe -e tools/dmb/fixtures/unified_checks/parent_call_global/probe.dme
The root-lookup repair is draft-only while the current gate runs.
