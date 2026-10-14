# Icon receiver grammar capture

Compile-only discovery of authored `icon.Insert` and `icon.MapColors` calls.
No expected opcode shape is asserted before capture. No DreamDaemon is started.

```powershell
python tools/dmb/fixtures/native/icon_receiver_grammar/run.py --dm "D:/Program Files (x86)/BYOND516/bin/dm.exe" --dm-sha256 8cac7e8bd48219f8a7fb622535a1ce1a914d0a9a3e909bc9ceb84b3074709dc0 --inspector E:/dq-cache/dmb-native-v2/frozen-build/20261010-062957-inspector-a0bb00f6.exe --inspector-sha256 5a73ad00b2b2bec2bc2941816a5c31e95481dcbf7ddebc0f1fad6cf9f7f03035
```

Each child has a 30-second watchdog; the aggregate has 180 seconds and an owned
4 GB Job. Pins, fixture inputs and compiled output are checked before/after use.
The immutable receipt preserves procedure IDs, code-list IDs and raw word rows.
`proc-code` is a locator only: decode failure is retained and allowed if its
exact procedure header is available. `proc` then `list` capture raw words without
using opcode grammar. A complete capture establishes authentic bytes, not a
semantic interpretation or native/BYOND equivalence. Decoder changes require
review against the pinned format reference and these captured rows.
