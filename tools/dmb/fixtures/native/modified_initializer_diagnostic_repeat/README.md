# Modified initializer diagnostic repeats

Compile-only observations for the inconsistent secondary diagnostic recorded
with identical source and pinned BYOND516.1687 in actual846 and actual4bf.
Three baseline repetitions and four controls use independent fresh directories.
Controls add an existing global `amount` proc, two fields, empty fields, and a
valid declared type. Legality and complete diagnostic lists are observed.
No native compiler or DreamDaemon is launched; no diagnostic rule is inferred.

```powershell
python tools/dmb/fixtures/native/modified_initializer_diagnostic_repeat/run.py --dm "D:/Program Files (x86)/BYOND516/bin/dm.exe" --dm-sha256 8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0
```

Each child has a30second watchdog; the whole observation has240seconds and an
owned4GB Job. Cwd is each independent directory. Environment values are recorded
only for the explicit relevant roster; PATH is hashed rather than printed.
Raw stdout/stderr, their hashes, copied/authored input hashes, compiler identity,
acceptance, complete diagnostics, and owned cleanup remain in the E: receipt.
`baseline_stable` is an observation, not the driver's completion criterion.
