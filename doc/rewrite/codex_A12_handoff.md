# A12 initialization sweep handoff

Worktree E:/projects/dq-wt/codex-A12; branch codex/A12; base 1fff26dc1f.
Offline expected baseline 250 -> 181: init_lines 244 -> 178; world_reads 6 -> 3. Exact retained identities in residual-fingerprints.txt. Root analyzer confirmation remains required; no baseline edited.

16 declared setup jobs in 14 production files:
- Internal organ conditional sellability; brain clock and actual mind host; voicebox language assistance; horror language lookup.
- Electronic assembly's existing owned device backlink and that device's two built-in circuits; video camera name; signaler pins; both EPv2 address/node jobs (discovery admin message preserved); pre-attached grenade.
- Integrated radio PDA binding.
- EFTPOS account/id/reference/manual; trader ordered product construction/removal and optional movement; vendor slogan/ads/inventory; refill type name.

Parent-order safeguards:
- Body construction remains before parent living init, organ placement/data/prosthetics before descendants, and external/stump/cell/head pre-parent facts unchanged.
- Generic circuit pin construction remains synchronous in Initialize: mux/demux/memory build their pin metadata before parent and signalers consume constructed pins afterward. Only independent subtype work moved.
- Internal organ setup precedes brain/voicebox setup, and voicebox setup precedes horror lookup. No remaining organ subtype initializer consumes sellability, brain-host or language-assistance outputs. The old inherited body/owner prerequisites remain synchronous.
- Built-in input/output constructors and backlinks retain order, then the outer wrapper binds holder. No new ownership/ref declarations.
- Trader still draws from the original world RNG and interleaves each chosen child constructor with removal from its original start list.
- EFTPOS retains account binding, counter/id, access-code reference, manual construction and stamps in their exact order.
- All changed type CAPABILITIES blocks are unique tree-wide; no second block added over an existing block elsewhere.

Residuals (counts include init_lines and world_reads; fingerprints list every line):
body.dm 2: body creation before parent, needed for organ attachment.
organ.dm 27: owner placement, real DNA/species and prosthetic prerequisite consumed by subtype initialization.
organ_external.dm 3: nonstandard parent argument and actual owner color.
organ_stump.dm 9: actual stump_of copied before parent; post-parent damage/robotic state from that same limb.
machine.dm 7: pre-parent robotize, or actual owner/installed_mmi constructor arguments.
slime.dm 3: actual owner's species blood color.
standard.dm 2: pre-parent config-derived head-gib policy.
assemblies/clothing.dm 9: pre-parent integrated assembly creation, earpiece speaker before parent clothing work.
integrated_circuit.dm 6: actual displayed name/size plus synchronous pin builder prerequisite.
subtypes/camera.dm 6: pre-parent network-id/camera-net registration/name, consumed by camera parent init.
data_transfer.dm 15: pre-parent pin tables and actual pin-count-derived descriptions.
memory.dm 4: pre-parent input/output definitions and actual configured complexity.
exotic_feedstocks.dm 13: real constructor material/amount args, their fallback random draws and nonstandard parent forwarding.
material_machines.dm 4: chamber snapshot from actual construction turf air.
processed_material.dm 6: actual material/amount-derived economic provenance and copied batch state.
material_synth.dm 2: actual supplied material-derived name/description.
sheets/_sheets.dm 14: parent material lookup, recipes/conductivity/color/name, needed by child material/alloy initializers.
pda/ai.dm 2: pAI owner identity from actual location.
pda/pda.dm 45: mixed-order constructor: program binding/pen precede actual human profile selection; main-menu activation follows it and precedes pAI child owner capture. Moving only the lifecycle prefix to setup would place menu activation before program binding; moving the complete helper would reorder the child's constructor identity. Actual profile/map state stays unchanged.
pda/radio.dm 2: actual mapped frequency sanitizer before materialization.

Root include: code/modules/unit_tests/dq_a12_system_init.dm.
Six focused tests /datum/unit_test/dq_a12_system_init/{brain_host,voice_languages,signaler_pins,device_links,trader_contents,eftpos_manuals}; plus task-required dq_look_pin. Real constructors assert clock/host, language references, pin data, built-in device/holder links, actual product construction, and reference/manual side effects. No default-pass assertions.

Fixture review: New warms dview/status policies; each run scopes coalesce_runs. EFTPOS scopes terminal counter and explicitly owns constructor-created manual, reference parcel and wrapped paper so parcel spill cannot leave a paper behind. Trader fixture adds no vars and has no random/movement work; its constructed products and the device built-in circuits are explicitly fixture-owned for cleanup. No human-profile/base layout changes.

No source declaration/old setter line removals: read-only multiset check passed. No new setters, refs, ownership declarations, base vars or ALLOWs. No logging removal. Whitespace check passes. No builds/tests/cargo/gen/manifest/baseline/commits/pushes by subagent.

Root analyzer preflight: baseline4115 ->4046 (69 rows removed), decl47unchanged; generated tracked check clean. Runtime verification pending.

Compile repair: signaler_pins referenced IC_INPUT after the electronics module undefines it. The fixture now uses its own scoped input-selector constant with the existing get_pin_data API, matching interim_ic_signal_recipient and round2 circuit tests; no production code changed. The initial gate stopped before any world; original focused execution remains pending.
