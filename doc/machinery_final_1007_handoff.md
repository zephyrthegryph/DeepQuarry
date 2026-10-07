# Machinery final follow-up, 2026-10-07

Branch: `codex/machinery-final-1007` (source and snapshots through `044fdff2f8`), based on the pushed `codex/machinery-followup-1007` checkpoint `cb03761f55`. That checkpoint includes master `eac3bc655d` in merge `4e247bcd36`.

## Conversions

The complete machinery/power sweep reduced 121 targeted declarations to zero: 42 interactions, seven emag declarations, nine damage reactions, four repeats, 40 field-family declarations and 19 topic rows. Folder-scoped declaration and field bans are already present on the inherited branch. The final branch preserves them; no ceilings, annotations or exemptions were added.

Gas watchers use the native atmosphere API. The old gas-watch file and hub are deleted. Channel power contributes directly to the machine power stat; stored machine condition bits are gone. F5/F7 are marked complete with the surviving observer and compatibility roles explained.

The seven requested prompt paths already use chained asks. An unused gear-dispenser admin prompt helper and its callback were removed; the regression now calls the actual public VV op. Other request paths are not silently counted as converted: the remaining inventory is recorded separately below.

## Final fixes

- Gravity teardown preserves whole-generator deletion without running damage reactions on deleting parts or deleted holders. The main removes its active membership before recalculating supplied gravity.
- Canonical work stages implement the adapter query helpers. The adapter regression uses a genuinely declared isolated stage dependency instead of assuming retired production stages still declare reads.
- Explicit instantaneous admission samples bypass menu caching, including enclosing read scopes; tracked-only caches remain active and exception paths restore the scope and purity depth.
- Camera, upload level, remote robot, floor-light custody, suit cycler and Santa identity admission use the current input state without invented dependency keys. Waiting mutable requirements still require real tracking.
- Cell Charge/Drain preserve visible not-in-hand refusals and inspect actual active/inactive hand interfaces.
- Shuttle authorization and six suit cycler/recharge station item rows retain their exact missing-item refusals. Borg catalogue availability is checked by the production request before it opens.
- Synchronous request completion cannot attach a closed request or overwrite the next question; declared step names are installed before callbacks run.
- AI and cyborg upload consoles dispatch real law modules to installation ahead of the generic item fallback, with exact production-law and unrelated-pen regressions.
- Camera, Doppler, AI status display and Pandemic retain their original disabled menu refusals and physical reach/capability gates. Camera also fixes the old predicate receiver that incorrectly disabled valid blunt-item attacks. Pandemic physically inserts actual beakers and syringes ahead of generic computer item use; invalid items retain their fallback.
- Syndicate-pod and prison-shuttle generated window opens obey their existing access/route requirements. This closes a bypass; documented public credentialed acceptance remains.
- The ATM return field has the explicit Use label.
- DX click capture evaluates when conditions; the all-candidate diagnostic remains unchanged.

These causes are documented in `doc/rewrite/intended_changes.md`. I7 native instrument captures are reviewed per class (283 classes), with restored refusal rows and real-effect regressions. The 227 matching global conversion pins share that exact producer; the other 735 pins are not claimed verified or refreshed. DX dynamic golden refresh covers 332 scenarios in 24 target classes, preserving every previous menu key and their relative order, plus the two unchanged dynamic rows and all 247 static rows.

## Verification

Generator, lint (TypeScript/Biome/analyze), DreamChecker (0 diagnostics), and the standalone ratchet script pass. Engine layering remains enabled at 0. All 41 named focused tests below passed across clean targeted runs, including every requested red test. The final three menu guard tests passed with actual distance and STAT_CAN_ACT vetoes, preserving hand/slot custody; I7 passed without re-blessing against the final production code. Compile: 0 errors, 42 existing warnings. Successful runs had zero boot runtimes and zero state leaks. No full suite or shard run was used.

The developmental stun probes exposed a separate mob status-to-capability bridge gap, reported below rather than patched in protected code. They are not represented as passing stun regressions. Machinery tests verify the declared native capability-stat contract.

Native I7 records cover 283 classes. All 227 overlapping global conversion pins were refreshed from the same reviewed canonical producer; the other 735 global pins remain unchanged and are not claimed verified. Per-class causes, including exact refusal restorations, corrected camera receiver, access fixes and fixture isolation, are documented in intended_changes.md.

Baseline fingerprints versus master `eac3bc655d`: base_vars 981→912; instance_list 48→0; silicon_entry 110→101; dx_review 175→169; system_boundary 301→300. Total removed: 133. None added.

## Focused verification names

- `/datum/unit_test/read_once_menu_contract/visibility`
- `/datum/unit_test/read_once_menu_contract/tracked_cache`
- `/datum/unit_test/read_once_menu_contract/nested`
- `/datum/unit_test/read_once_menu_contract/exception`
- `/datum/unit_test/read_once_machinery_admission/helmet_customisation`
- `/datum/unit_test/read_once_machinery_admission/suit_customisation`
- `/datum/unit_test/read_once_machinery_admission/camera_injury_kind`
- `/datum/unit_test/dq_hc_struct/cell_hand_menu_admission`
- `/datum/unit_test/round2_gravity_teardown/damage`
- `/datum/unit_test/round2_gravity_teardown/main_destroy`
- `/datum/unit_test/round2_gravity_teardown/part_destroy`
- `/datum/unit_test/kernel_work_stage_adapter`
- `/datum/unit_test/kernel_stage_adapter_graph`
- `/datum/unit_test/dq_interaction_domain_snapshot/i7_bulk`
- `/datum/unit_test/interim_airlock_wire_electrify_actor`
- `/datum/unit_test/round2_robot_fabricator_consumption`
- `/datum/unit_test/round2_robot_fabricator_consumption/stale`
- `/datum/unit_test/dq_om_wake_status_display`
- `/datum/unit_test/interim_large_parcel_unwrap`
- `/datum/unit_test/dq_eg2/interim_domination_native_cancel`
- `/datum/unit_test/dq_e2/input_kinds`
- `/datum/unit_test/dq_pp/gravgen_spin_up`
- `/datum/unit_test/dq_pp/gravgen_spin_down`
- `/datum/unit_test/dq_pp/gravgen_breaker`
- `/datum/unit_test/om/interim_gear_pack_actor_refusal`
- `/datum/unit_test/read_once_machinery_admission/floor_light_custody`
- `/datum/unit_test/dq_hc_struct/shuttle_authorize_menu_parity`
- `/datum/unit_test/dq_hc_struct/cycler_missing_item_menu_parity`
- `/datum/unit_test/dq_hc_struct/recharger_missing_item_menu_parity`
- `/datum/unit_test/dq_hc_computers/round2_borgupload_empty_selection`
- `/datum/unit_test/dq_hc_computers/round2_sync_answer_chain`
- `/datum/unit_test/dx_menu_order`

- `/datum/unit_test/dq_hc_computers/round2_borg_module_click`
- `/datum/unit_test/dq_hc_computers/round2_ai_module_click`

- `/datum/unit_test/dq_hc_struct/camera_missing_item_menu_parity`
- `/datum/unit_test/dq_hc_struct/doppler_missing_item_menu_parity`
- `/datum/unit_test/round2_menu_refusal_restore/status_display`
- `/datum/unit_test/round2_menu_refusal_restore/pandemic/beaker`
- `/datum/unit_test/round2_menu_refusal_restore/pandemic/syringe`
- `/datum/unit_test/dq_hc_computers/syndicate_pod_public_access_gate`
- `/datum/unit_test/dq_hc_computers/prison_public_window_access_and_break_gate`

## Remaining legacy and ownership

There are no targeted declaration forms, field macros or old watch calls in machinery/power. `power_change()` observers remain for subtype effects; `set_powered()` is a manual test/benchmark stat-hold shim, not an area power writer. Vehicle condition bits are a separate model.

64 other open_request sites remain in 29 files, primarily separate UI/consent/callback flows beyond the seven named paths. The complete per-site inventory and reasons are in the appendix below. Protected combat AI and mob library packs were not edited. The complete remaining-form audit is in `doc/machinery_final_1007_remaining_legacy.md`: 22 appearance bridges, four loot declarations, three shared caches, six world/callback aliases, compatibility construction requirements and ownership helpers. These are separate appearance/cache/loot/ownership/construction migrations; no targeted declaration or gas-watch debt is hidden by that inventory.

## Appendix: separate request paths

# Remaining request inventory after requested seven machinery paths

Total: **64 sites**.
These are separate UI, admin, construction or consent request paths, not the seven listed hand/topic paths. No blanket conversion was made; each needs an independent op-flow design and focused test. Gear dispenser obsolete admin callback is removed.

## code/game/machinery/atmo_control.dm (5)
- Line 265, `/obj/machinery/computer/general_air_control/proc/ask_control_port(mob/user, obj/item/tool, port_name, handler)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice/air_control_port, handler, answerer = user, title = "Configuration", question = "Would you like to set an [port_name] or clear it?", choices = list("Set", "Clear", "Cancel"), buttons = TRUE, tool = tool, port_name = port_name, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`
- Line 315, `/obj/machinery/computer/general_air_control/proc/configure_sensors(mob/living/user, obj/item/multitool/tool)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice/air_control_sensors, PROC_REF(sensor_config_chosen), answerer = user, title = "Configuration", question = "Would you like to add or remove a sensor/meter?", choices = list("Add", "Remove", "Cancel"), tool = tool, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`
- Line 330, `/obj/machinery/computer/general_air_control/proc/sensor_config_chosen(datum/act/request/A)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text/air_control_sensor_name, PROC_REF(sensor_named), answerer = user, title = "Name", question = "Enter a name for the Sensor/Meter.", name_text = TRUE, device = device, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`
- Line 336, `/obj/machinery/computer/general_air_control/proc/sensor_config_chosen(datum/act/request/A)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(sensor_removal_chosen), answerer = user, title = "Sensor/Meter Removal", question = "Select a sensor/meter to remove", choices = sensor_names, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`
- Line 360, `/obj/machinery/computer/general_air_control/proc/sensor_removal_chosen(datum/act/request/A)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/air_control_sensor_remove, PROC_REF(sensor_removal_confirmed), answerer = R.answerer, title = "Warning", question = "Are you sure you want to remove the sensor/meter '[A.answer.value]'?", sensor_names = R.choices, to_remove = A.answer.value, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`

## code/game/machinery/camera/camera_assembly.dm (4)
- Line 112, `/obj/item/camera_assembly/screwdriver_act(mob/user, obj/item/tool)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(camera_networks_entered), answerer = user, title = "Set Network", question = "Which networks would you like to connect this camera to? Separate networks with a comma. No Spaces!\nFor example: "+using_map.station_short+",Security,Secret ", default = camera_network ? camera_network : NETWORK_DEFAULT, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`
- Line 128, `/obj/item/camera_assembly/proc/camera_networks_entered(datum/act/request/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text/camera_name, PROC_REF(camera_configured), valid = PROC_REF(camera_state_ok), answerer = user, title = "Set Camera Name", question = "How would you like to name the camera?", default = camera_name ? camera_name : temptag, max_len = MAX_NAME_LEN, encode = FALSE, networks = tempnetwork, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`
- Line 153, `/obj/item/camera_assembly/proc/ask_camera_direction(mob/user, obj/machinery/camera/C, chances)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice/camera_direction, PROC_REF(camera_direction_chosen), answerer = user, title = "Assembling Camera", question = "Direction?", choices = list("NORTH", "EAST", "SOUTH", "WEST", "LEAVE IT"), camera = C, chances = chances, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`
- Line 170, `/obj/item/camera_assembly/proc/camera_direction_chosen(datum/act/request/A)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/camera_direction_ok, PROC_REF(camera_direction_confirmed), answerer = R.answerer, title = "Confirmation", question = "Is this what you want? Chances Remaining: [R.chances]", camera = C, chances = R.chances, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`

## code/game/machinery/computer/ai_core.dm (2)
- Line 167, `/obj/structure/AIcore/screwdriver_act(mob/user, obj/item/tool)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(D, /datum/prompt/yes_no, TYPE_PROC_REF(/obj/structure/AIcore/deactivated, latejoin_answered), answerer = user, title = "Latejoin", question = "Would you like this core to be open for latejoining AIs?", timeout = 0)`
- Line 311, `/proc/empty_ai_core_choices()`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(user, /datum/prompt/choice, TYPE_PROC_REF(/client, empty_ai_core_latejoin_chosen), valid = TYPE_PROC_REF(/client, empty_ai_core_latejoin_valid), answerer = user.mob, title = "Toggle AI Core Latejoin", question = "Which core?", choices = assoc_to_keys(empty_ai_core_choices()), timeout = 0)`

## code/game/machinery/computer/arcade.dm (1)
- Line 1176, `/obj/machinery/computer/arcade/clawmachine/proc/pay_with_card(obj/item/card/id/I, obj/item/ID_container, mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/number/claw_pin, PROC_REF(card_pin_entered), valid = PROC_REF(request_usable), answerer = user, account = I.associated_account_number, timeout = 0)`

## code/game/machinery/computer/medical.dm (1)
- Line 329, `/obj/machinery/computer/med_data/proc/ui_act_edit_notes(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/record_notes_delete, PROC_REF(record_notes_confirmed), valid = PROC_REF(record_notes_valid), answerer = A.actor, record = target, timeout = 0)`

## code/game/machinery/computer/message.dm (4)
- Line 207, `/obj/machinery/computer/message_monitor/proc/ui_act_find(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(server_selected), valid = PROC_REF(request_usable), answerer = A.actor, title = "Select a server.", question = "Please select a server.", choices = server_choices(), timeout = 0)`
- Line 262, `/obj/machinery/computer/message_monitor/proc/ui_act_pass(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(current_key_entered), valid = PROC_REF(request_usable), answerer = A.actor, question = "Please enter the current decryption key.", timeout = 0)`
- Line 376, `/obj/machinery/computer/message_monitor/proc/ui_act_addtoken(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(token_entered), valid = PROC_REF(request_usable), answerer = A.actor, title = "Token creation", question = "Enter text you want to be filtered out", timeout = 0)`
- Line 417, `/obj/machinery/computer/message_monitor/proc/current_key_entered(datum/act/request/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(new_key_entered), valid = PROC_REF(request_usable), answerer = A.request.answerer, question = "Please enter the new key (3 - 16 characters max):", max_len = 16, timeout = 0)`

## code/game/machinery/computer/security.dm (1)
- Line 309, `/obj/machinery/computer/secure_data/proc/ui_act_edit_notes(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/record_notes_delete, PROC_REF(record_notes_confirmed), valid = PROC_REF(record_notes_valid), answerer = A.actor, record = target, timeout = 0)`

## code/game/machinery/computer/skills.dm (1)
- Line 747, `/obj/machinery/computer/skills/proc/ui_act_edit_notes(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/record_notes_delete, PROC_REF(record_notes_confirmed), valid = PROC_REF(record_notes_valid), answerer = A.actor, record = target, timeout = 0)`

## code/game/machinery/cryopod.dm (1)
- Line 689, `/obj/machinery/cryopod/proc/go_in(mob/M, mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/cryo_consent, PROC_REF(storage_consent_answered), answerer = M, title = "Cryopod", question = "Would you like to enter long-term storage?", loader = user, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`

## code/game/machinery/deployable.dm (1)
- Line 222, `/obj/structure/barricade/cutout/proc/cutout_interaction_item(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(cutout_type_chosen), answerer = user, question = "What would you like to paint the cutout as?", title = "Cutout Painting", choices = cutout_types, subject = I, ask_flags = ASK_HELD | ASK_CAPABLE, timeout = 0)`

## code/game/machinery/embedded_controller/construction.dm (1)
- Line 7, `/obj/item/circuitboard/airlock_cycling/multitool_act(mob/user, obj/item/tool)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(board_type_chosen), answerer = user, question = "What do you want to reconfigure the board to?", title = "Multitool-Circuitboard interface", choices = list("Button", "Sensor", "Controller - Standard", "Controller - Advanced", "Controller - Access"), ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`

## code/game/machinery/food_replicator.dm (1)
- Line 63, `/obj/machinery/food_replicator/interact(mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(dish_chosen), answerer = user, question = "What would you like to print?", title = "Print a dish", choices = products, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`

## code/game/machinery/jukebox.dm (5)
- Line 415, `/obj/machinery/media/jukebox/ghost/proc/manual_track_add(mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text/jukebox_track, PROC_REF(url_entered), answerer = user, title = "Track URL", question = "REQUIRED: Provide URL for track", rights = R_FUN|R_ADMIN, timeout = 0)`
- Line 430, `/obj/machinery/media/jukebox/ghost/proc/url_entered(datum/act/request/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text/jukebox_track, PROC_REF(title_entered), answerer = A.request.answerer, title = "Track Title", question = "REQUIRED: Provide title for track", rights = R_FUN|R_ADMIN, track_url = A.answer.value, timeout = 0)`
- Line 436, `/obj/machinery/media/jukebox/ghost/proc/title_entered(datum/act/request/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/number/jukebox_track, PROC_REF(duration_entered), answerer = R.answerer, title = "Track Duration", question = "REQUIRED: Provide duration for track (in deciseconds, aka seconds*10)", rights = R_FUN|R_ADMIN, track_url = R.track_url, track_title = A.answer.value, timeout = 0)`
- Line 442, `/obj/machinery/media/jukebox/ghost/proc/duration_entered(datum/act/request/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text/jukebox_track, PROC_REF(artist_entered), answerer = R.answerer, title = "Track Artist", question = "Optional: Provide artist for track", rights = R_FUN|R_ADMIN, track_url = R.track_url, track_title = R.track_title, track_duration = A.answer.value, timeout = 0)`
- Line 455, `/obj/machinery/media/jukebox/ghost/proc/manual_track_remove(mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(manual_track_removal_entered), answerer = user, title = "Remove Track", question = "Input track title or URL to remove (must be exact)", rights = R_FUN|R_ADMIN, timeout = 0)`

## code/game/machinery/machinery.dm (2)
- Line 688, `/obj/machinery/proc/ask_frequency(mob/user, current)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/number, PROC_REF(frequency_entered), answerer = user, title = "[src] frequency", question = "[src] has a frequency of [current]. What would you like it to be?", default = current, max_value = RADIO_HIGH_FREQ, min_value = RADIO_LOW_FREQ, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`
- Line 700, `/obj/machinery/proc/ask_text_var(mob/user, var_name, message, title, max_length = MAX_NAME_LEN)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text/machine_var, PROC_REF(text_var_entered), answerer = user, title = title, question = message, default = vars[var_name], max_len = max_length, name_text = (max_length <= MAX_NAME_LEN), var_name = var_name, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 0)`

## code/game/machinery/magnet.dm (1)
- Line 269, `/obj/machinery/magnetic_controller/proc/magnet_operation(mob/user, op)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(magnet_path_entered), answerer = user, question = "Please define a new path!", default = path, max_len = MAX_MESSAGE_LEN, ask_flags = ASK_CAPABLE, timeout = 0)`

## code/game/machinery/medical_kiosk.dm (1)
- Line 92, `/obj/machinery/medical_kiosk/proc/start_using(mob/living/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(service_chosen), valid = PROC_REF(kiosk_ready), answerer = user, title = "[src]", question = "What service would you like?", choices = list("Health Scan", "Backup Scan", "Cancel"), buttons = TRUE, ask_flags = ASK_ADJACENT | ASK_CAPABLE, timeout = 10 SECONDS)`

## code/game/machinery/newscaster.dm (6)
- Line 418, `/obj/machinery/newscaster/proc/ui_act_submit_new_channel(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/news_channel_create, PROC_REF(channel_creation_confirmed), valid = PROC_REF(caster_valid), answerer = user, title = "Network Channel Handler", question = "Please confirm Feed channel creation", author = our_user, channel = channel_name, locked = c_locked, timeout = 0)`
- Line 427, `/obj/machinery/newscaster/proc/ui_act_set_channel_receiving(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(receiving_channel_chosen), valid = PROC_REF(caster_valid), answerer = user, title = "Network Channel Handler", question = "Choose receiving Feed Channel", choices = available_channels, timeout = 0)`
- Line 432, `/obj/machinery/newscaster/proc/ui_act_set_new_message(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(story_written), valid = PROC_REF(caster_valid), answerer = user, title = "Network Channel Handler", question = "Write your Feed story", default = "", max_len = MAX_MESSAGE_LEN, multiline = TRUE, encode = FALSE, timeout = 0)`
- Line 437, `/obj/machinery/newscaster/proc/ui_act_set_new_title(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(title_written), valid = PROC_REF(caster_valid), answerer = user, title = "Network Channel Handler", question = "Enter your Feed title", default = "", max_len = MAX_KEYPAD_INPUT_LEN, timeout = 0)`
- Line 494, `/obj/machinery/newscaster/proc/ui_act_submit_wanted(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no, PROC_REF(wanted_change_confirmed), valid = PROC_REF(caster_valid), answerer = user, title = "Network Security Handler", question = "Please confirm Wanted Issue change.", yes_text = "Confirm", no_text = "Cancel", timeout = 0)`
- Line 504, `/obj/machinery/newscaster/proc/ui_act_cancel_wanted(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no, PROC_REF(wanted_removal_confirmed), valid = PROC_REF(caster_valid), answerer = user, title = "Network Security Handler", question = "Please confirm Wanted Issue removal", yes_text = "Confirm", no_text = "Cancel", timeout = 0)`

## code/game/machinery/painter.dm (1)
- Line 191, `/obj/machinery/gear_painter/proc/ui_act_choose_color(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/color, PROC_REF(color_chosen), valid = PROC_REF(colour_valid), answerer = user, default = activecolor, title = "ColorMate colour picking", question = "Choose a color: ", timeout = 0)`

## code/game/machinery/pandemic.dm (2)
- Line 161, `/obj/machinery/computer/pandemic/proc/print_form(datum/affliction/contagion/engineered/D, mob/living/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text/pandemic_release_reason, PROC_REF(release_reason_written), valid = PROC_REF(request_usable), answerer = user, title = "Write", question = "Enter a reason for the release", multiline = TRUE, affliction = D, timeout = 0)`
- Line 171, `/obj/machinery/computer/pandemic/proc/release_reason_written(datum/act/request/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/pandemic_release_sign, PROC_REF(release_form_written), valid = PROC_REF(sign_usable), answerer = R.answerer, title = "Signature", question = "Would you like to add your signature?", disease = R.affliction, reason = A.answer.value, timeout = 0)`

## code/game/machinery/petrification.dm (5)
- Line 178, `/obj/machinery/petrification/proc/set_input(option, mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/color/statue_tint, PROC_REF(tint_chosen), answerer = user, title = "Statue color", question = "Choose the color for the [identifier] to be:", default = tint)`
- Line 180, `/obj/machinery/petrification/proc/set_input(option, mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text/statue_option, PROC_REF(statue_text_entered), answerer = user, title = "Statue [option]", question = "What should the [option] be?", default = vars[option], option = option)`
- Line 188, `/obj/machinery/petrification/proc/set_input(option, mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice/statue_target, PROC_REF(petrify_target_chosen), answerer = user, title = "Petrification Target", question = "Choose the target.", choices = targets)`
- Line 234, `/obj/machinery/petrification/proc/petrify_target_chosen(datum/act/request/A)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice/petrify_consent, PROC_REF(first_confirmed), answerer = H, operator = A.request.answerer, question = "You have been selected as a petrification target. If you press confirm, you will possibly be turned into a statue, and if the option is selected, possibly one that cannot be reverted back from a statue at all.")`
- Line 264, `/obj/machinery/petrification/proc/first_confirmed(datum/act/request/A)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice/petrify_consent, PROC_REF(second_confirmed), answerer = H, operator = ask.operator, question = "This is your last warning, are you -certain-?")`

## code/game/machinery/status_display_ai.dm (1)
- Line 44, `/mob/living/silicon/ai/proc/set_ai_status_displays()`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(ai_status_display_chosen), answerer = src, title = "AI Status", question = "Please, select a status:", choices = ai_emotions, timeout = 0)`

## code/game/machinery/telecomms/traffic_control.dm (1)
- Line 102, `/obj/machinery/computer/telecomms/traffic/proc/traffic_set_network(mob/user)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(network_entered), answerer = user, title = "Comm Monitor", question = "Which network do you want to view?", default = network, max_len = 15, ask_flags = ASK_CAPABLE, timeout = 0)`

## code/game/machinery/transportpod.dm (1)
- Line 39, `/obj/machinery/transportpod/proc/ask_to_launch(datum/act/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no, PROC_REF(launch_answered), answerer = N.occupant, title = "Transport Pod", question = "Are you sure you're ready to launch?", ask_flags = ASK_INSIDE, timeout = 0)`

## code/game/machinery/virtual_reality/ar_console.dm (3)
- Line 124, `/obj/machinery/vr_sleeper/alien/enter_vr()`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no, PROC_REF(alien_engage_answered), answerer = occupant, title = "Commmit?", question = "This pod is already linked. Are you certain you wish to engage?", ask_flags = ASK_INSIDE, timeout = 0)`
- Line 172, `/obj/machinery/vr_sleeper/alien/proc/alien_engage(mob/living/carbon/human/occupant)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(alien_avatar_renamed), valid = PROC_REF(asked_is_avatar), answerer = avatar(), title = "Name change", question = "Your mind feels foggy. You're certain your name is [occupant.real_name], but it could also be [avatar().name]. Would you like to change it to something else?", max_len = MAX_NAME_LEN, timeout = 0)`
- Line 180, `/obj/machinery/vr_sleeper/alien/proc/alien_engage(mob/living/carbon/human/occupant)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(alien_avatar_renamed), valid = PROC_REF(asked_is_avatar), answerer = avatar(), title = "Name change", question = "Your mind feels foggy. You're certain your name is [occupant.real_name], but it feels like it is [avatar().name]. Would you like to change it to something else?", max_len = MAX_NAME_LEN, timeout = 0)`

## code/game/machinery/virtual_reality/vr_console.dm (6)
- Line 233, `/obj/machinery/vr_sleeper/proc/ask_leave_vr(handler)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no, handler, valid = PROC_REF(asked_is_avatar), answerer = avatar(), title = "Leave VR?", question = "Someone wants to remove you from virtual reality. Do you want to leave?", timeout = 0)`
- Line 284, `/obj/machinery/vr_sleeper/proc/enter_vr()`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no, PROC_REF(vr_reuse_answered), answerer = occupant, title = "New avatar", question = "You already have a [avatar().stat == DEAD ? "" : "deceased "]Virtual Reality avatar. Would you like to use it?", ask_flags = ASK_INSIDE, timeout = 0)`
- Line 305, `/obj/machinery/vr_sleeper/proc/vr_choose_avatar(mob/living/carbon/human/occupant)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(location_chosen), valid = PROC_REF(occupant_inside), answerer = occupant, title = "Spawn location", question = "Please select a location to spawn your avatar at:", choices = vr_landmarks, timeout = 0)`
- Line 322, `/obj/machinery/vr_sleeper/proc/location_chosen(datum/act/request/A)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no/vr_avatar_mob, PROC_REF(as_mob_answered), valid = PROC_REF(occupant_inside), answerer = A.request.answerer, title = "Join as a mob?", question = "Would you like to play as a different creature?", location = A.answer.value, timeout = 0)`
- Line 329, `/obj/machinery/vr_sleeper/proc/as_mob_answered(datum/act/request/A)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice/vr_avatar_creature, PROC_REF(creature_chosen), valid = PROC_REF(occupant_inside), answerer = R.answerer, title = "Mob list", question = "Please select a creature:", choices = GLOB.vr_mob_tf_options, location = R.location, timeout = 0)`
- Line 388, `/obj/machinery/vr_sleeper/proc/vr_avatar_chosen(mob/living/carbon/human/occupant, S, tf)`: retained separate request path; existing consent/answer callback requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(vr_avatar_named), valid = PROC_REF(asked_is_avatar), answerer = avatar(), title = "Name change", question = "You are entering virtual reality. Your username is currently [src.name]. Would you like to change it to something else?", max_len = MAX_NAME_LEN, timeout = 0)`

## code/game/machinery/virtual_reality/vr_procs.dm (3)
- Line 37, `/mob/living/carbon/human/proc/vr_transform_into_mob()`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(vr_creature_chosen), answerer = src, title = "Mob list", question = "Please select a creature:", choices = GLOB.vr_mob_tf_options, ask_flags = ASK_CONSCIOUS, timeout = 0)`
- Line 60, `/mob/living/carbon/human/proc/fake_exit_vr()`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/yes_no, PROC_REF(fake_exit_vr_answered), answerer = src, title = "Log out?", question = "Would you like to log out of virtual reality?", timeout = 0)`
- Line 105, `/mob/living/carbon/human/proc/ask_vr_ghost_name(old_name)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/text, PROC_REF(vr_avatar_renamed), answerer = src, title = "Name change", question = "You are entering virtual reality. Your username is currently [old_name]. Would you like to change it to something else?", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)`

## code/game/machinery/wall_frames.dm (2)
- Line 45, `/obj/item/frame/proc/interaction_self(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice, PROC_REF(floor_frame_chosen), valid = PROC_REF(frame_type_open), answerer = user, title = "Frame type request", question = "What kind of frame would you like to make?", choices = frame_types_floor, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)`
- Line 136, `/obj/item/frame/proc/mount_on(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/choice/frame_type_wall, PROC_REF(wall_frame_chosen), valid = PROC_REF(frame_type_open), answerer = user, title = "Frame type request", question = "What kind of frame would you like to make?", choices = frame_types_wall, wall_turf = spot, wall_dir = ndir, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)`

## code/modules/power/cable.dm (1)
- Line 941, `/obj/item/stack/cable_coil/alien/proc/alien_coil_hand(datum/act/op/A)`: retained separate request path; existing UI/admin/construction entry or action requires its own chained-asks migration rather than changing the already-converted listed seven.
  `open_request(src, /datum/prompt/number, PROC_REF(alien_wire_taken), answerer = user, title = "Split stacks", question = "How many units of wire do you want to take from [src]? You can only take up to [amount] at a time.", default = 1, max_value = amount, min_value = 1, ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)`

## Bug outside this batch: mob status-to-capability bridge

A human with godmode disabled can receive stun without operation_actor_capable(0) becoming false. The three focused admission probes demonstrated that assumption failing. The native adapter in code/datums/operations/native_requirement_adapter.dm reads STAT_CAN_ACT; status callbacks update posture/movement, and no stun contribution to that stat was found. This belongs to the protected mob/body capability adapter owner (code/library/mob), not the machinery guard. Machinery regressions exercise the declared capability stat directly with hold/release, and do not claim to fix the status bridge. Protected files remain untouched.
