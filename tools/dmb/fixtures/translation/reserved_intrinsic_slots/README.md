# Reserved native variable dispatch slots

The native interpreter reserves the entire FFCD..FFF1 range for variable modifiers/intrinsics. Getter dispatch at 10131055 subtracts FFCD and checks maximum24; setter dispatch at10130a12 checks maximum22. FFED, FFEE and FFEF are not ordinary field-string IDs even though their semantics are not yet named by the decoder.

The translated server's available_station_software field was allocated string65519 (FFEF). SetVar therefore entered the intrinsic handler and raised writing-to-read-only instead of setting that ordinary field. The allocator now leaves all FFCD..FFF1 slots unused for authored strings, and the typed decoder rejects unnamed reserved slots. The wide string-table allocation regression verifies every allocated string can roundtrip as an ordinary Field.

The paired minimal fixture compiles natively and with OpenDream without warnings. It includes the actual two-empty-list field initialization pattern and a World-output cache witness. Native world.log output establishes World before evaluating the RHS; both maxx/maxy lookups then use bare Field.
