> **Archived.** Historical record (audit/report/brief); not maintained. The signal-to-event migration map; the migration is done and the DCS is deleted.

# Signal migration map

Historical: the migration this map drove is done and the DCS is deleted (object_model_core.md sec 10). The generator is gone; the events live in `code/datums/om_events/signal_events.dm`.
Rule (object_model_core.md sec 16, completion_plan sec 3.2): synchronous reactions
that can refuse become `/datum/om/event/before/x` returning `EVENT_VETO`; synchronous
notifications become `/datum/om/event/x` via `om_emit()`; deferred or state-driven
reactions become a declared field's channel, a watch or `om_after()`.

Classification: a signal whose sender reads the return value, or whose define is
followed by return flags, is a `before/` event; a name describing a state change
(`CHANGE`, `UPDATE`, `_SET`, `_MOVED`...) is a channel/watch; the rest are events.
Review each during its folder's sweep; the classification is a starting point.

Signals in use: **172** (defined: 182; defined but unused: 10).
Send sites: 228; listener sites: 378.

| Replacement | Signals |
|---|---|
| before/ event (EVENT_VETO) | 45 |
| channel / watch | 18 |
| event | 109 |

## All signals

| Signal | Senders | Listeners | Replacement | Defined in |
|---|---|---|---|---|
| `COMSIG_AFFLICTION_SEVERITY_CHANGED` | 1 | 2 | channel / watch | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_ARCADE_PRIZEVEND` | 1 | 1 | event | `code/__defines/dcs/signals/signals_arcade.dm` |
| `COMSIG_ATOM_AFTER_SUCCESSFUL_INITIALIZED_ON` | 1 | 0 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_ATOM_ATTACKBY` | 2 | 7 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_attack.dm` |
| `COMSIG_ATOM_ATTACK_HAND` | 1 | 2 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_attack.dm` |
| `COMSIG_ATOM_BULLET_ACT` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_ATOM_BUMPED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_ATOM_DIR_CHANGE` | 1 | 2 | channel / watch | `code/__defines/dcs/signals/signals_atom/signals_atom_movement.dm` |
| `COMSIG_ATOM_EMP_ACT` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_ATOM_ENTERED` | 1 | 4 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_ATOM_ENTERING` | 1 | 4 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_ATOM_EXAMINE` | 1 | 6 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_ATOM_EXITED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_ATOM_EXTINGUISH` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_attack.dm` |
| `COMSIG_ATOM_EX_ACT` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_ATOM_FIRE_ACT` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_ATOM_PRE_EMP_ACT` | 1 | 2 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_ATOM_PROPAGATE_RAD_PULSE` | 1 | 3 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_ATOM_SECONDARY_TOOL_ACT` | 1 | 2 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_ATOM_TAKE_DAMAGE` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_attack.dm` |
| `COMSIG_ATOM_TOOL_ACT` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_ATOM_UPDATE_LIGHT_COLOR` | 1 | 1 | channel / watch | `code/__defines/dcs/signals/signals_atom/signals_atom_lighting.dm` |
| `COMSIG_ATOM_UPDATE_LIGHT_FLAGS` | 1 | 1 | channel / watch | `code/__defines/dcs/signals/signals_atom/signals_atom_lighting.dm` |
| `COMSIG_ATOM_UPDATE_LIGHT_ON` | 1 | 1 | channel / watch | `code/__defines/dcs/signals/signals_atom/signals_atom_lighting.dm` |
| `COMSIG_ATOM_UPDATE_LIGHT_POWER` | 1 | 1 | channel / watch | `code/__defines/dcs/signals/signals_atom/signals_atom_lighting.dm` |
| `COMSIG_ATOM_UPDATE_LIGHT_RANGE` | 1 | 1 | channel / watch | `code/__defines/dcs/signals/signals_atom/signals_atom_lighting.dm` |
| `COMSIG_ATOM_USED_IN_CRAFT` | 1 | 2 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_AUTOPSY_PERFORMED` | 1 | 0 | event | `code/__defines/dcs/signals/signals_surgery.dm` |
| `COMSIG_BELLY_UPDATE_VORE_FX` | 3 | 2 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_vore.dm` |
| `COMSIG_BODY_AFFLICTIONS_CHANGED` | 2 | 2 | channel / watch | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_BODY_PART_ATTACHED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_BODY_PART_DETACHED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_CLICK` | 1 | 4 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_mouse.dm` |
| `COMSIG_CLICK_ALT` | 2 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_mouse.dm` |
| `COMSIG_CLIENT_CLICK` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_mouse.dm` |
| `COMSIG_COMPONENT_HANDLED_HEALTH_ICON` | 1 | 0 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_COMPONENT_HANDLED_HUD` | 1 | 0 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_DISPOSAL_FLUSH` | 2 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_disposals.dm` |
| `COMSIG_DISPOSAL_LINK` | 3 | 1 | event | `code/__defines/dcs/signals/signals_disposals.dm` |
| `COMSIG_DISPOSAL_RECEIVE` | 1 | 3 | event | `code/__defines/dcs/signals/signals_disposals.dm` |
| `COMSIG_DISPOSAL_SEND` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_disposals.dm` |
| `COMSIG_DISPOSAL_UNLINK` | 5 | 1 | event | `code/__defines/dcs/signals/signals_disposals.dm` |
| `COMSIG_DO_AFTER_BEGAN` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_DO_AFTER_ENDED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_DQAI_ALLY_DISTRESS` | 2 | 0 | event | `code/modules/combat_ai/_defines.dm` |
| `COMSIG_DQAI_DAMAGE_TAKEN` | 1 | 0 | event | `code/modules/combat_ai/_defines.dm` |
| `COMSIG_DQAI_TARGET_CHANGED` | 4 | 0 | channel / watch | `code/modules/combat_ai/_defines.dm` |
| `COMSIG_DQAI_TARGET_LOST` | 2 | 0 | event | `code/modules/combat_ai/_defines.dm` |
| `COMSIG_FORM_CHANGED` | 1 | 0 | channel / watch | `code/__defines/forms.dm` |
| `COMSIG_GARGOYLE_CHECK_ENERGY` | 1 | 1 | event | `code/__defines/dcs/signals/signals_gargoyle.dm` |
| `COMSIG_GARGOYLE_PAUSE` | 1 | 1 | event | `code/__defines/dcs/signals/signals_gargoyle.dm` |
| `COMSIG_GARGOYLE_TRANSFORMATION` | 1 | 1 | event | `code/__defines/dcs/signals/signals_gargoyle.dm` |
| `COMSIG_GEIGER_COUNTER_SCAN` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_radiation.dm` |
| `COMSIG_GEIGER_COUNTER_SCAN_SUCCESSFUL` | 1 | 0 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_radiation.dm` |
| `COMSIG_GHOST_QUERY_COMPLETE` | 1 | 5 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_GLOB_AUTOPSY_PERFORMED` | 1 | 0 | event | `code/__defines/dcs/signals/signals_global.dm` |
| `COMSIG_GLOB_BRAIN_REMOVED` | 1 | 0 | event | `code/__defines/dcs/signals/signals_global.dm` |
| `COMSIG_GLOB_EXPLOSION` | 1 | 1 | event | `code/__defines/dcs/signals/signals_global.dm` |
| `COMSIG_GLOB_GHOST_CAPTURED` | 1 | 0 | event | `code/__defines/dcs/signals/signals_trasheating.dm` |
| `COMSIG_GLOB_MOB_CREATED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_global.dm` |
| `COMSIG_GLOB_MOB_DEATH` | 1 | 1 | event | `code/__defines/dcs/signals/signals_global.dm` |
| `COMSIG_GLOB_PAYMENT_ACCOUNT_STATUS` | 1 | 1 | event | `code/__defines/dcs/signals/signals_global.dm` |
| `COMSIG_GLOB_PLAY_CINEMATIC` | 1 | 2 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_global.dm` |
| `COMSIG_GLOB_SUPPLY_SHUTTLE_DEPART` | 1 | 1 | event | `code/__defines/dcs/signals/signals_global.dm` |
| `COMSIG_GLOB_WIGHT_CAPTURED` | 1 | 0 | event | `code/__defines/dcs/signals/signals_trasheating.dm` |
| `COMSIG_HANDLE_DISABILITIES` | 1 | 8 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_HANDLE_MUTATIONS` | 1 | 0 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_HANDLE_RADIATION` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_HOSE_FORCEPUMP` | 2 | 1 | event | `code/__defines/dcs/signals/signals_hose.dm` |
| `COMSIG_HUMAN_BURNING` | 1 | 0 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_carbon.dm` |
| `COMSIG_HUMAN_DNA_FINALIZED` | 16 | 2 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_carbon.dm` |
| `COMSIG_HUMAN_GET_ALT_NAME` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_HUMAN_GET_VISIBLE_NAME` | 2 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_carbon.dm` |
| `COMSIG_HUMAN_GET_VOICE` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_INSTRUMENT_END` | 1 | 1 | event | `code/__defines/dcs/signals/signals_music.dm` |
| `COMSIG_INSTRUMENT_START` | 1 | 1 | event | `code/__defines/dcs/signals/signals_music.dm` |
| `COMSIG_IN_RANGE_OF_IRRADIATION` | 4 | 6 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_radiation.dm` |
| `COMSIG_ITEM_ATTACK` | 1 | 1 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_ITEM_ATTACK_SELF` | 1 | 3 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_ITEM_DROPPED` | 1 | 2 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_ITEM_EQUIPPED` | 1 | 3 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_ITEM_PICKUP` | 2 | 0 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_ITEM_PRE_ATTACK` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_ITEM_TOOL_ACTED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_x_act.dm` |
| `COMSIG_LIVING_AHEAL` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_LIVING_BODY_STATUS` | 4 | 2 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_DEATH_FINAL` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_FACTORS_CHANGED` | 1 | 0 | channel / watch | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_LIVING_INJURE` | 1 | 3 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_LIVING_INJURED` | 1 | 3 | event | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_LIVING_INJURY_EXPLAINED` | 1 | 4 | event | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_LIVING_IRRADIATE_EFFECT` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_REGENERATE_LIMBS` | 1 | 0 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_REVIVED` | 1 | 4 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_SHIELD_INJURY` | 1 | 2 | event | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_LIVING_STATUS_BLIND` | 0 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_STATUS_PARALYZE` | 0 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_STATUS_SLEEP` | 0 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_STATUS_STUN` | 0 | 2 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_STATUS_WEAKEN` | 0 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_LIVING_TURF_COLLISION` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_living.dm` |
| `COMSIG_MACHINERY_BROKEN` | 1 | 2 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_MACHINERY_DESTRUCTIVE_SCAN` | 2 | 0 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_MACHINERY_EXPLOSION_DETECTED` | 1 | 0 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_MACHINERY_POWER_LOST` | 1 | 2 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_MACHINERY_POWER_RESTORED` | 1 | 2 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_MATCONTAINER_ITEM_CONSUMED` | 1 | 0 | event | `code/__defines/dcs/signals/signals_material_container.dm` |
| `COMSIG_MATCONTAINER_STACK_RETRIEVED` | 1 | 0 | event | `code/__defines/dcs/signals/signals_material_container.dm` |
| `COMSIG_MATERIAL_SURGERY` | 2 | 1 | event | `code/__defines/material_science.dm` |
| `COMSIG_MOB_APPLY_DAMAGE` | 0 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_CANCEL_CLICKON` | 1 | 0 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_CLIENT_LOGIN` | 1 | 5 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_COMBAT_MODE_CHANGED` | 1 | 0 | channel / watch | `code/__defines/combat_mode.dm` |
| `COMSIG_MOB_DEATH` | 1 | 9 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_DNA_MUTATION` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_EQUIPPED_ITEM` | 1 | 2 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_MOB_GRANTED_ACTION` | 1 | 1 | event | `code/__defines/dcs/signals/signals_action.dm` |
| `COMSIG_MOB_HANDLE_HUD` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_HANDLE_HUD_DARKSIGHT` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_HANDLE_HUD_HEALTH_ICON` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_HANDLE_VISION` | 2 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_LOGIN` | 1 | 4 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_LOGOUT` | 2 | 5 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_MEDICAL_ISSUES_CHANGED` | 2 | 1 | channel / watch | `code/__defines/dcs/signals/signals_medical.dm` |
| `COMSIG_MOB_MIND_TRANSFERRED_INTO` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_MIND_TRANSFERRED_OUT_OF` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_RELAY_MOVEMENT` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_REMOVED_ACTION` | 1 | 1 | event | `code/__defines/dcs/signals/signals_action.dm` |
| `COMSIG_MOB_RESET_PERSPECTIVE` | 1 | 2 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_STATCHANGE` | 1 | 2 | channel / watch | `code/__defines/dcs/signals/signals_mob/signals_mob_main.dm` |
| `COMSIG_MOB_UNEQUIPPED_ITEM` | 1 | 1 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 7 | 27 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_movable.dm` |
| `COMSIG_MOVABLE_BUMP` | 1 | 2 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_movable.dm` |
| `COMSIG_MOVABLE_IMPACT` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_movable.dm` |
| `COMSIG_MOVABLE_MOTIONTRACKER` | 1 | 2 | event | `code/__defines/dcs/signals/signals_motiontracker.dm` |
| `COMSIG_MOVABLE_MOVED` | 1 | 34 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_movable.dm` |
| `COMSIG_MOVABLE_PRE_MOVE` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_movable.dm` |
| `COMSIG_MOVABLE_Z_CHANGED` | 1 | 3 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_atom/signals_atom_movable.dm` |
| `COMSIG_OBJ_DECONSTRUCT` | 2 | 1 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_OBSERVER_APC` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_OBSERVER_DESTROYED` | 1 | 13 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_OBSERVER_GLOBALMOVED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_OBSERVER_SHUTTLE_ADDED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_OBSERVER_SHUTTLE_MOVED` | 1 | 2 | channel / watch | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_OBSERVER_SHUTTLE_PRE_MOVE` | 1 | 1 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_OBSERVER_TURF_ENTERED` | 1 | 2 | event | `code/__defines/dcs/signals/signals_atom/signals_atom_main.dm` |
| `COMSIG_POPUP_CLEARED` | 1 | 1 | event | `code/__defines/dcs/signals/signals_client.dm` |
| `COMSIG_QDELETING` | 2 | 59 | event | `code/__defines/dcs/signals/signals_datum.dm` |
| `COMSIG_REAGENTS_HOLDER_REACTED` | 1 | 2 | event | `code/__defines/dcs/signals/signals_reagent.dm` |
| `COMSIG_REAGENT_EXPOSE_OBJ` | 1 | 1 | event | `code/__defines/dcs/signals/signals_reagent.dm` |
| `COMSIG_REMOTE_VIEW_CLEAR` | 6 | 4 | event | `code/__defines/dcs/signals/signals_remote_view.dm` |
| `COMSIG_ROBOT_BELLY_FULLNESS` | 1 | 1 | event | `code/__defines/robot_parts.dm` |
| `COMSIG_ROBOT_EQUIPMENT_CHANGED` | 1 | 1 | channel / watch | `code/__defines/robot_parts.dm` |
| `COMSIG_ROBOT_ITEM_ATTACK` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_mob/signals_mob_silicon.dm` |
| `COMSIG_SHADEKIN_COMPONENT` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_shadekin.dm` |
| `COMSIG_SHOES_STEP_ACTION` | 1 | 2 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_SILICON_LAWS_CHANGED` | 1 | 1 | channel / watch | `code/__defines/robot_parts.dm` |
| `COMSIG_SLOT_INSERTED` | 2 | 1 | event | `code/__defines/dcs/signals/signals_container.dm` |
| `COMSIG_SLOT_PRE_INSERT` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_container.dm` |
| `COMSIG_SLOT_PRE_REMOVE` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_container.dm` |
| `COMSIG_SLOT_REMOVED` | 2 | 1 | event | `code/__defines/dcs/signals/signals_container.dm` |
| `COMSIG_TECHWEB_ADD_DESIGN` | 1 | 0 | event | `code/__defines/dcs/signals/signals_techweb.dm` |
| `COMSIG_TECHWEB_REMOVE_DESIGN` | 1 | 0 | event | `code/__defines/dcs/signals/signals_techweb.dm` |
| `COMSIG_TELESCI_TELEPORT` | 2 | 1 | event | `code/__defines/dcs/signals/signals_object.dm` |
| `COMSIG_TGUI_WINDOW_VISIBLE` | 1 | 1 | event | `code/__defines/dcs/signals/signals_tgui.dm` |
| `COMSIG_TOOL_ATOM_ACTED_PRIMARY` | 1 | 1 | event | `code/__defines/dcs/signals/signals_tools.dm` |
| `COMSIG_TOOL_ATOM_ACTED_SECONDARY` | 1 | 0 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_tools.dm` |
| `COMSIG_TURF_CHANGE` | 1 | 2 | channel / watch | `code/__defines/dcs/signals/signals_turf.dm` |
| `COMSIG_TURF_PREPARE_STEP_SOUND` | 1 | 1 | before/ event (EVENT_VETO) | `code/__defines/dcs/signals/signals_turf.dm` |
| `COMSIG_UI_ACT` | 1 | 1 | event | `code/__defines/dcs/signals/signals_datum.dm` |
| `COMSIG_UNITTEST_DATA` | 1 | 1 | event | `code/__defines/dcs/signals/signals_unittest.dm` |
| `COMSIG_XENOCHIMERA_COMPONENT` | 1 | 1 | event | `code/__defines/dcs/signals/signals_mob/signals_mob_xenochimera.dm` |

## By folder

Counts are the sites in that folder only.

### `code/datums/components` (64 signals, 135 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_ATTACKBY` | 0 | 3 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_ATTACK_HAND` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_DIR_CHANGE` | 0 | 2 | channel / watch |
| `COMSIG_ATOM_ENTERED` | 0 | 1 | event |
| `COMSIG_ATOM_ENTERING` | 0 | 3 | event |
| `COMSIG_ATOM_EXAMINE` | 0 | 4 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_EXITED` | 0 | 1 | event |
| `COMSIG_ATOM_UPDATE_LIGHT_COLOR` | 0 | 1 | channel / watch |
| `COMSIG_ATOM_UPDATE_LIGHT_FLAGS` | 0 | 1 | channel / watch |
| `COMSIG_ATOM_UPDATE_LIGHT_ON` | 0 | 1 | channel / watch |
| `COMSIG_ATOM_UPDATE_LIGHT_POWER` | 0 | 1 | channel / watch |
| `COMSIG_ATOM_UPDATE_LIGHT_RANGE` | 0 | 1 | channel / watch |
| `COMSIG_ATOM_USED_IN_CRAFT` | 1 | 2 | event |
| `COMSIG_CLICK` | 0 | 1 | event |
| `COMSIG_DISPOSAL_FLUSH` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_DISPOSAL_LINK` | 0 | 1 | event |
| `COMSIG_DISPOSAL_RECEIVE` | 1 | 0 | event |
| `COMSIG_DISPOSAL_SEND` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_DISPOSAL_UNLINK` | 0 | 1 | event |
| `COMSIG_GARGOYLE_CHECK_ENERGY` | 1 | 1 | event |
| `COMSIG_GARGOYLE_PAUSE` | 1 | 1 | event |
| `COMSIG_GARGOYLE_TRANSFORMATION` | 1 | 1 | event |
| `COMSIG_GEIGER_COUNTER_SCAN` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_HANDLE_DISABILITIES` | 0 | 8 | event |
| `COMSIG_HANDLE_RADIATION` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_HOSE_FORCEPUMP` | 0 | 1 | event |
| `COMSIG_HUMAN_DNA_FINALIZED` | 0 | 2 | event |
| `COMSIG_HUMAN_GET_ALT_NAME` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_HUMAN_GET_VISIBLE_NAME` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_HUMAN_GET_VOICE` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_IN_RANGE_OF_IRRADIATION` | 0 | 2 | before/ event (EVENT_VETO) |
| `COMSIG_ITEM_ATTACK_SELF` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_ITEM_DROPPED` | 0 | 2 | event |
| `COMSIG_ITEM_EQUIPPED` | 0 | 3 | event |
| `COMSIG_ITEM_PRE_ATTACK` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_IRRADIATE_EFFECT` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_STATUS_BLIND` | 0 | 1 | event |
| `COMSIG_LIVING_STATUS_PARALYZE` | 0 | 1 | event |
| `COMSIG_LIVING_STATUS_SLEEP` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_STATUS_STUN` | 0 | 1 | event |
| `COMSIG_LIVING_STATUS_WEAKEN` | 0 | 1 | event |
| `COMSIG_MATCONTAINER_ITEM_CONSUMED` | 1 | 0 | event |
| `COMSIG_MATCONTAINER_STACK_RETRIEVED` | 1 | 0 | event |
| `COMSIG_MOB_CLIENT_LOGIN` | 0 | 1 | event |
| `COMSIG_MOB_DEATH` | 0 | 4 | event |
| `COMSIG_MOB_DNA_MUTATION` | 0 | 1 | event |
| `COMSIG_MOB_HANDLE_HUD` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_HANDLE_HUD_DARKSIGHT` | 0 | 1 | event |
| `COMSIG_MOB_HANDLE_HUD_HEALTH_ICON` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_HANDLE_VISION` | 0 | 1 | event |
| `COMSIG_MOB_LOGOUT` | 0 | 2 | event |
| `COMSIG_MOB_RELAY_MOVEMENT` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_RESET_PERSPECTIVE` | 0 | 2 | event |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 2 | 4 | event |
| `COMSIG_MOVABLE_BUMP` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_IMPACT` | 0 | 1 | event |
| `COMSIG_MOVABLE_MOVED` | 0 | 17 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_Z_CHANGED` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_OBJ_DECONSTRUCT` | 0 | 1 | event |
| `COMSIG_QDELETING` | 0 | 15 | event |
| `COMSIG_REMOTE_VIEW_CLEAR` | 2 | 4 | event |
| `COMSIG_SHADEKIN_COMPONENT` | 0 | 1 | event |
| `COMSIG_SHOES_STEP_ACTION` | 0 | 2 | before/ event (EVENT_VETO) |
| `COMSIG_XENOCHIMERA_COMPONENT` | 0 | 1 | event |

### `code/modules/mob` (52 signals, 70 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_PRE_EMP_ACT` | 0 | 1 | event |
| `COMSIG_CLICK` | 0 | 1 | event |
| `COMSIG_COMPONENT_HANDLED_HEALTH_ICON` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_COMPONENT_HANDLED_HUD` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_DO_AFTER_BEGAN` | 0 | 1 | event |
| `COMSIG_DO_AFTER_ENDED` | 0 | 1 | event |
| `COMSIG_FORM_CHANGED` | 1 | 0 | channel / watch |
| `COMSIG_GHOST_QUERY_COMPLETE` | 0 | 2 | event |
| `COMSIG_GLOB_MOB_CREATED` | 1 | 0 | event |
| `COMSIG_GLOB_MOB_DEATH` | 1 | 0 | event |
| `COMSIG_HANDLE_DISABILITIES` | 1 | 0 | event |
| `COMSIG_HANDLE_MUTATIONS` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_HANDLE_RADIATION` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_HUMAN_BURNING` | 1 | 0 | event |
| `COMSIG_HUMAN_DNA_FINALIZED` | 2 | 0 | event |
| `COMSIG_HUMAN_GET_ALT_NAME` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_HUMAN_GET_VISIBLE_NAME` | 2 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_HUMAN_GET_VOICE` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_AHEAL` | 1 | 0 | event |
| `COMSIG_LIVING_DEATH_FINAL` | 1 | 0 | event |
| `COMSIG_LIVING_INJURE` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_INJURED` | 0 | 2 | event |
| `COMSIG_LIVING_IRRADIATE_EFFECT` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_SHIELD_INJURY` | 0 | 2 | event |
| `COMSIG_LIVING_TURF_COLLISION` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_MACHINERY_DESTRUCTIVE_SCAN` | 1 | 0 | event |
| `COMSIG_MOB_APPLY_DAMAGE` | 0 | 1 | event |
| `COMSIG_MOB_CLIENT_LOGIN` | 1 | 1 | event |
| `COMSIG_MOB_COMBAT_MODE_CHANGED` | 1 | 0 | channel / watch |
| `COMSIG_MOB_DEATH` | 1 | 1 | event |
| `COMSIG_MOB_EQUIPPED_ITEM` | 0 | 1 | event |
| `COMSIG_MOB_HANDLE_HUD` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_HANDLE_HUD_DARKSIGHT` | 1 | 0 | event |
| `COMSIG_MOB_HANDLE_HUD_HEALTH_ICON` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_HANDLE_VISION` | 2 | 0 | event |
| `COMSIG_MOB_LOGIN` | 1 | 0 | event |
| `COMSIG_MOB_LOGOUT` | 1 | 0 | event |
| `COMSIG_MOB_RELAY_MOVEMENT` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_RESET_PERSPECTIVE` | 1 | 0 | event |
| `COMSIG_MOB_UNEQUIPPED_ITEM` | 1 | 0 | event |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 3 | event |
| `COMSIG_MOVABLE_MOTIONTRACKER` | 0 | 1 | event |
| `COMSIG_MOVABLE_MOVED` | 0 | 3 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_PRE_MOVE` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_QDELETING` | 0 | 4 | event |
| `COMSIG_ROBOT_BELLY_FULLNESS` | 1 | 1 | event |
| `COMSIG_ROBOT_EQUIPMENT_CHANGED` | 1 | 1 | channel / watch |
| `COMSIG_ROBOT_ITEM_ATTACK` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_SHADEKIN_COMPONENT` | 1 | 0 | event |
| `COMSIG_SHOES_STEP_ACTION` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_SILICON_LAWS_CHANGED` | 1 | 1 | channel / watch |
| `COMSIG_XENOCHIMERA_COMPONENT` | 1 | 0 | event |

### `code/game/objects` (25 signals, 42 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_AUTOPSY_PERFORMED` | 1 | 0 | event |
| `COMSIG_DISPOSAL_FLUSH` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_DISPOSAL_LINK` | 1 | 0 | event |
| `COMSIG_DISPOSAL_RECEIVE` | 0 | 1 | event |
| `COMSIG_GEIGER_COUNTER_SCAN` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_GEIGER_COUNTER_SCAN_SUCCESSFUL` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_GHOST_QUERY_COMPLETE` | 0 | 2 | event |
| `COMSIG_GLOB_AUTOPSY_PERFORMED` | 1 | 0 | event |
| `COMSIG_GLOB_GHOST_CAPTURED` | 1 | 0 | event |
| `COMSIG_GLOB_WIGHT_CAPTURED` | 1 | 0 | event |
| `COMSIG_HUMAN_DNA_FINALIZED` | 2 | 0 | event |
| `COMSIG_IN_RANGE_OF_IRRADIATION` | 0 | 2 | before/ event (EVENT_VETO) |
| `COMSIG_ITEM_DROPPED` | 1 | 0 | event |
| `COMSIG_ITEM_EQUIPPED` | 1 | 0 | event |
| `COMSIG_ITEM_PICKUP` | 2 | 0 | event |
| `COMSIG_LIVING_INJURE` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_EQUIPPED_ITEM` | 1 | 0 | event |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 2 | 4 | event |
| `COMSIG_MOVABLE_MOTIONTRACKER` | 0 | 1 | event |
| `COMSIG_MOVABLE_MOVED` | 0 | 4 | before/ event (EVENT_VETO) |
| `COMSIG_OBJ_DECONSTRUCT` | 1 | 0 | event |
| `COMSIG_OBSERVER_APC` | 0 | 1 | event |
| `COMSIG_QDELETING` | 0 | 6 | event |
| `COMSIG_REMOTE_VIEW_CLEAR` | 1 | 0 | event |
| `COMSIG_UNITTEST_DATA` | 1 | 0 | event |

### `code/modules/unit_tests` (25 signals, 34 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_AFFLICTION_SEVERITY_CHANGED` | 0 | 1 | channel / watch |
| `COMSIG_BODY_AFFLICTIONS_CHANGED` | 0 | 1 | channel / watch |
| `COMSIG_BODY_PART_ATTACHED` | 0 | 1 | event |
| `COMSIG_BODY_PART_DETACHED` | 0 | 1 | event |
| `COMSIG_GLOB_PLAY_CINEMATIC` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_ITEM_TOOL_ACTED` | 0 | 1 | event |
| `COMSIG_LIVING_BODY_STATUS` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_DEATH_FINAL` | 0 | 1 | event |
| `COMSIG_LIVING_INJURE` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_INJURY_EXPLAINED` | 0 | 4 | event |
| `COMSIG_LIVING_REVIVED` | 0 | 3 | event |
| `COMSIG_LIVING_STATUS_STUN` | 0 | 1 | event |
| `COMSIG_MACHINERY_BROKEN` | 0 | 2 | event |
| `COMSIG_MACHINERY_POWER_LOST` | 0 | 1 | event |
| `COMSIG_MACHINERY_POWER_RESTORED` | 0 | 1 | event |
| `COMSIG_MOB_DEATH` | 0 | 1 | event |
| `COMSIG_MOB_LOGOUT` | 1 | 0 | event |
| `COMSIG_QDELETING` | 0 | 3 | event |
| `COMSIG_REAGENTS_HOLDER_REACTED` | 0 | 2 | event |
| `COMSIG_SLOT_INSERTED` | 0 | 1 | event |
| `COMSIG_SLOT_PRE_INSERT` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_SLOT_PRE_REMOVE` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_SLOT_REMOVED` | 0 | 1 | event |
| `COMSIG_TOOL_ATOM_ACTED_PRIMARY` | 0 | 1 | event |
| `COMSIG_UNITTEST_DATA` | 0 | 1 | event |

### `code/game/machinery` (12 signals, 29 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ARCADE_PRIZEVEND` | 1 | 0 | event |
| `COMSIG_GLOB_EXPLOSION` | 0 | 1 | event |
| `COMSIG_HUMAN_DNA_FINALIZED` | 5 | 0 | event |
| `COMSIG_MACHINERY_BROKEN` | 1 | 0 | event |
| `COMSIG_MACHINERY_EXPLOSION_DETECTED` | 1 | 0 | event |
| `COMSIG_MACHINERY_POWER_LOST` | 1 | 1 | event |
| `COMSIG_MACHINERY_POWER_RESTORED` | 1 | 1 | event |
| `COMSIG_MOB_STATCHANGE` | 0 | 1 | channel / watch |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 2 | event |
| `COMSIG_MOVABLE_MOVED` | 0 | 4 | before/ event (EVENT_VETO) |
| `COMSIG_OBJ_DECONSTRUCT` | 1 | 0 | event |
| `COMSIG_QDELETING` | 0 | 8 | event |

### `code/controllers/subsystems` (20 signals, 24 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_AFFLICTION_SEVERITY_CHANGED` | 0 | 1 | channel / watch |
| `COMSIG_BODY_AFFLICTIONS_CHANGED` | 0 | 1 | channel / watch |
| `COMSIG_GLOB_EXPLOSION` | 1 | 0 | event |
| `COMSIG_GLOB_MOB_CREATED` | 0 | 1 | event |
| `COMSIG_GLOB_MOB_DEATH` | 0 | 1 | event |
| `COMSIG_GLOB_PAYMENT_ACCOUNT_STATUS` | 0 | 1 | event |
| `COMSIG_GLOB_SUPPLY_SHUTTLE_DEPART` | 1 | 0 | event |
| `COMSIG_IN_RANGE_OF_IRRADIATION` | 4 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_REVIVED` | 0 | 1 | event |
| `COMSIG_LIVING_TURF_COLLISION` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_EQUIPPED_ITEM` | 0 | 1 | event |
| `COMSIG_MOB_LOGIN` | 0 | 1 | event |
| `COMSIG_MOB_LOGOUT` | 0 | 1 | event |
| `COMSIG_MOB_MEDICAL_ISSUES_CHANGED` | 0 | 1 | channel / watch |
| `COMSIG_MOB_MIND_TRANSFERRED_INTO` | 0 | 1 | event |
| `COMSIG_MOB_MIND_TRANSFERRED_OUT_OF` | 0 | 1 | event |
| `COMSIG_MOB_UNEQUIPPED_ITEM` | 0 | 1 | event |
| `COMSIG_MOVABLE_MOTIONTRACKER` | 1 | 0 | event |
| `COMSIG_MOVABLE_MOVED` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_QDELETING` | 0 | 2 | event |

### `code/modules/body` (13 signals, 18 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_AFFLICTION_SEVERITY_CHANGED` | 1 | 0 | channel / watch |
| `COMSIG_ATOM_ATTACKBY` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_TOOL_ACT` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_BODY_AFFLICTIONS_CHANGED` | 2 | 0 | channel / watch |
| `COMSIG_BODY_PART_ATTACHED` | 1 | 0 | event |
| `COMSIG_BODY_PART_DETACHED` | 1 | 0 | event |
| `COMSIG_LIVING_BODY_STATUS` | 4 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_FACTORS_CHANGED` | 1 | 0 | channel / watch |
| `COMSIG_LIVING_INJURE` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_INJURED` | 1 | 0 | event |
| `COMSIG_LIVING_INJURY_EXPLAINED` | 1 | 0 | event |
| `COMSIG_LIVING_REVIVED` | 1 | 0 | event |
| `COMSIG_LIVING_SHIELD_INJURY` | 1 | 0 | event |

### `code/game/atom` (16 signals, 16 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_AFTER_SUCCESSFUL_INITIALIZED_ON` | 1 | 0 | event |
| `COMSIG_ATOM_BULLET_ACT` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_BUMPED` | 1 | 0 | event |
| `COMSIG_ATOM_DIR_CHANGE` | 1 | 0 | channel / watch |
| `COMSIG_ATOM_EMP_ACT` | 1 | 0 | event |
| `COMSIG_ATOM_ENTERED` | 1 | 0 | event |
| `COMSIG_ATOM_ENTERING` | 1 | 0 | event |
| `COMSIG_ATOM_EXAMINE` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_EXITED` | 1 | 0 | event |
| `COMSIG_ATOM_EXTINGUISH` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_EX_ACT` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_FIRE_ACT` | 1 | 0 | event |
| `COMSIG_ATOM_PRE_EMP_ACT` | 1 | 0 | event |
| `COMSIG_ATOM_TAKE_DAMAGE` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 1 | 0 | event |
| `COMSIG_OBSERVER_TURF_ENTERED` | 0 | 1 | event |

### `code/_onclick` (12 signals, 14 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_ATTACKBY` | 2 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_ATTACK_HAND` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_SECONDARY_TOOL_ACT` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_TOOL_ACT` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_CLICK_ALT` | 2 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ITEM_ATTACK` | 1 | 0 | event |
| `COMSIG_ITEM_ATTACK_SELF` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ITEM_PRE_ATTACK` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_ITEM_TOOL_ACTED` | 1 | 0 | event |
| `COMSIG_MOB_CANCEL_CLICKON` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_TOOL_ATOM_ACTED_PRIMARY` | 1 | 0 | event |
| `COMSIG_TOOL_ATOM_ACTED_SECONDARY` | 1 | 0 | before/ event (EVENT_VETO) |

### `code/modules/material_science` (11 signals, 14 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_ATTACKBY` | 0 | 2 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_EXAMINE` | 0 | 2 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_FIRE_ACT` | 0 | 1 | event |
| `COMSIG_ATOM_PRE_EMP_ACT` | 0 | 1 | event |
| `COMSIG_ATOM_PROPAGATE_RAD_PULSE` | 0 | 1 | event |
| `COMSIG_ATOM_SECONDARY_TOOL_ACT` | 0 | 2 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_TAKE_DAMAGE` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_IN_RANGE_OF_IRRADIATION` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MATERIAL_SURGERY` | 0 | 1 | event |
| `COMSIG_MOVABLE_MOVED` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_TURF_CHANGE` | 0 | 1 | channel / watch |

### `code/modules/recycling` (6 signals, 13 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_ENTERED` | 0 | 2 | event |
| `COMSIG_DISPOSAL_FLUSH` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_DISPOSAL_LINK` | 2 | 0 | event |
| `COMSIG_DISPOSAL_RECEIVE` | 0 | 2 | event |
| `COMSIG_DISPOSAL_SEND` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_DISPOSAL_UNLINK` | 5 | 0 | event |

### `code/modules/tgui` (6 signals, 12 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_HUMAN_DNA_FINALIZED` | 1 | 0 | event |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 5 | event |
| `COMSIG_MOVABLE_Z_CHANGED` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_REMOTE_VIEW_CLEAR` | 3 | 0 | event |
| `COMSIG_TGUI_WINDOW_VISIBLE` | 1 | 0 | event |
| `COMSIG_UI_ACT` | 1 | 0 | event |

### `code/_onclick/hud` (6 signals, 12 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_CLIENT_CLICK` | 0 | 1 | event |
| `COMSIG_MOB_GRANTED_ACTION` | 1 | 1 | event |
| `COMSIG_MOB_REMOVED_ACTION` | 1 | 1 | event |
| `COMSIG_POPUP_CLEARED` | 1 | 1 | event |
| `COMSIG_QDELETING` | 0 | 4 | event |
| `COMSIG_TGUI_WINDOW_VISIBLE` | 0 | 1 | event |

### `code/modules/combat_ai` (7 signals, 12 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_DQAI_ALLY_DISTRESS` | 2 | 0 | event |
| `COMSIG_DQAI_DAMAGE_TAKEN` | 1 | 0 | event |
| `COMSIG_DQAI_TARGET_CHANGED` | 4 | 0 | channel / watch |
| `COMSIG_DQAI_TARGET_LOST` | 2 | 0 | event |
| `COMSIG_LIVING_INJURED` | 0 | 1 | event |
| `COMSIG_MOB_LOGIN` | 0 | 1 | event |
| `COMSIG_MOB_STATCHANGE` | 0 | 1 | channel / watch |

### `code/datums` (7 signals, 10 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_GHOST_QUERY_COMPLETE` | 1 | 0 | event |
| `COMSIG_MOB_LOGIN` | 0 | 1 | event |
| `COMSIG_MOB_LOGOUT` | 0 | 1 | event |
| `COMSIG_MOB_MIND_TRANSFERRED_INTO` | 1 | 0 | event |
| `COMSIG_MOB_MIND_TRANSFERRED_OUT_OF` | 1 | 0 | event |
| `COMSIG_OBSERVER_DESTROYED` | 1 | 0 | event |
| `COMSIG_QDELETING` | 0 | 4 | event |

### `code/modules/xenoarcheaology` (8 signals, 8 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_ATTACKBY` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_ATTACK_HAND` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_BULLET_ACT` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_ATOM_BUMPED` | 0 | 1 | event |
| `COMSIG_ATOM_EX_ACT` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_BUMP` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_MOVED` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_REAGENT_EXPOSE_OBJ` | 0 | 1 | event |

### `code/modules/research` (8 signals, 8 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ARCADE_PRIZEVEND` | 0 | 1 | event |
| `COMSIG_CLICK_ALT` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_ITEM_ATTACK_SELF` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MACHINERY_DESTRUCTIVE_SCAN` | 1 | 0 | event |
| `COMSIG_TECHWEB_ADD_DESIGN` | 1 | 0 | event |
| `COMSIG_TECHWEB_REMOVE_DESIGN` | 1 | 0 | event |
| `COMSIG_TELESCI_TELEPORT` | 0 | 1 | event |
| `COMSIG_UI_ACT` | 0 | 1 | event |

### `code/modules/vore` (4 signals, 8 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_BELLY_UPDATE_VORE_FX` | 3 | 2 | before/ event (EVENT_VETO) |
| `COMSIG_CLICK` | 0 | 1 | event |
| `COMSIG_HUMAN_DNA_FINALIZED` | 1 | 0 | event |
| `COMSIG_MOB_CLIENT_LOGIN` | 0 | 1 | event |

### `code/game` (6 signals, 7 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_BUMP` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_IMPACT` | 1 | 0 | event |
| `COMSIG_MOVABLE_MOVED` | 1 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_PRE_MOVE` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_Z_CHANGED` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_QDELETING` | 0 | 1 | event |

### `code/modules/events` (2 signals, 7 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_GLOB_SUPPLY_SHUTTLE_DEPART` | 0 | 1 | event |
| `COMSIG_OBSERVER_DESTROYED` | 0 | 6 | event |

### `code/modules/overmap` (3 signals, 7 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_OBSERVER_DESTROYED` | 0 | 4 | event |
| `COMSIG_OBSERVER_SHUTTLE_MOVED` | 0 | 2 | channel / watch |
| `COMSIG_OBSERVER_SHUTTLE_PRE_MOVE` | 0 | 1 | event |

### `code/modules/shuttles` (4 signals, 7 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_OBSERVER_SHUTTLE_ADDED` | 0 | 1 | event |
| `COMSIG_OBSERVER_SHUTTLE_MOVED` | 1 | 0 | channel / watch |
| `COMSIG_OBSERVER_SHUTTLE_PRE_MOVE` | 1 | 0 | event |
| `COMSIG_QDELETING` | 0 | 4 | event |

### `code/datums/containment` (4 signals, 6 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_SLOT_INSERTED` | 2 | 0 | event |
| `COMSIG_SLOT_PRE_INSERT` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_SLOT_PRE_REMOVE` | 1 | 0 | before/ event (EVENT_VETO) |
| `COMSIG_SLOT_REMOVED` | 2 | 0 | event |

### `code/datums/observation` (5 signals, 6 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOB_STATCHANGE` | 1 | 0 | channel / watch |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 2 | 0 | event |
| `COMSIG_OBSERVER_APC` | 1 | 0 | event |
| `COMSIG_OBSERVER_SHUTTLE_ADDED` | 1 | 0 | event |
| `COMSIG_OBSERVER_TURF_ENTERED` | 1 | 0 | event |

### `code/modules/lighting` (5 signals, 5 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_UPDATE_LIGHT_COLOR` | 1 | 0 | channel / watch |
| `COMSIG_ATOM_UPDATE_LIGHT_FLAGS` | 1 | 0 | channel / watch |
| `COMSIG_ATOM_UPDATE_LIGHT_ON` | 1 | 0 | channel / watch |
| `COMSIG_ATOM_UPDATE_LIGHT_POWER` | 1 | 0 | channel / watch |
| `COMSIG_ATOM_UPDATE_LIGHT_RANGE` | 1 | 0 | channel / watch |

### `code/datums/elements` (5 signals, 5 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |
| `COMSIG_MOVABLE_MOVED` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_OBSERVER_TURF_ENTERED` | 0 | 1 | event |
| `COMSIG_QDELETING` | 0 | 1 | event |
| `COMSIG_TURF_PREPARE_STEP_SOUND` | 0 | 1 | before/ event (EVENT_VETO) |

### `code/modules/reagents` (4 signals, 4 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_HOSE_FORCEPUMP` | 1 | 0 | event |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |
| `COMSIG_REAGENTS_HOLDER_REACTED` | 1 | 0 | event |
| `COMSIG_REAGENT_EXPOSE_OBJ` | 1 | 0 | event |

### `code/datums/proximity_monitor` (3 signals, 4 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_MOVED` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOVABLE_Z_CHANGED` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_QDELETING` | 0 | 2 | event |

### `code/modules/instruments` (2 signals, 4 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_INSTRUMENT_END` | 1 | 1 | event |
| `COMSIG_INSTRUMENT_START` | 1 | 1 | event |

### `code/modules/nifsoft` (4 signals, 4 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_CLICK` | 0 | 1 | event |
| `COMSIG_MOB_CLIENT_LOGIN` | 0 | 1 | event |
| `COMSIG_MOB_DEATH` | 0 | 1 | event |
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |

### `code/datums/cinematics` (3 signals, 4 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_GLOB_PLAY_CINEMATIC` | 1 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_MOB_CLIENT_LOGIN` | 0 | 1 | event |
| `COMSIG_QDELETING` | 0 | 1 | event |

### `code/modules/organs` (3 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_EMP_ACT` | 0 | 1 | event |
| `COMSIG_GLOB_BRAIN_REMOVED` | 1 | 0 | event |
| `COMSIG_HUMAN_DNA_FINALIZED` | 1 | 0 | event |

### `code/modules/surgery` (2 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_LIVING_REGENERATE_LIMBS` | 1 | 0 | event |
| `COMSIG_MATERIAL_SURGERY` | 2 | 0 | event |

### `code/modules/economy` (3 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_GLOB_PAYMENT_ACCOUNT_STATUS` | 1 | 0 | event |
| `COMSIG_ITEM_ATTACK` | 0 | 1 | event |
| `COMSIG_ITEM_ATTACK_SELF` | 0 | 1 | before/ event (EVENT_VETO) |

### `code/game/turfs` (2 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_PROPAGATE_RAD_PULSE` | 0 | 2 | event |
| `COMSIG_TURF_CHANGE` | 1 | 0 | channel / watch |

### `code/modules/maint_recycler` (3 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_ENTERING` | 0 | 1 | event |
| `COMSIG_MOB_LOGIN` | 0 | 1 | event |
| `COMSIG_MOB_LOGOUT` | 0 | 1 | event |

### `code/modules/blob2` (2 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_GHOST_QUERY_COMPLETE` | 0 | 1 | event |
| `COMSIG_OBSERVER_GLOBALMOVED` | 1 | 1 | event |

### `code/modules/contracts` (2 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOB_DEATH` | 0 | 1 | event |
| `COMSIG_MOB_MEDICAL_ISSUES_CHANGED` | 2 | 0 | channel / watch |

### `code/modules/resleeving` (1 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_HUMAN_DNA_FINALIZED` | 3 | 0 | event |

### `code/modules/admin` (2 signals, 3 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_HUMAN_DNA_FINALIZED` | 1 | 0 | event |
| `COMSIG_QDELETING` | 0 | 2 | event |

### `code/modules/keybindings` (2 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_CLICK` | 1 | 0 | event |
| `COMSIG_ROBOT_ITEM_ATTACK` | 1 | 0 | before/ event (EVENT_VETO) |

### `code/modules/holomap` (2 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |
| `COMSIG_OBSERVER_DESTROYED` | 0 | 1 | event |

### `code/modules/integrated_electronics` (2 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |
| `COMSIG_OBSERVER_DESTROYED` | 0 | 1 | event |

### `code/datums/status_effects` (2 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_EXTINGUISH` | 0 | 1 | before/ event (EVENT_VETO) |
| `COMSIG_LIVING_AHEAL` | 0 | 1 | event |

### `code/modules/lootpanel` (2 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_QDELETING` | 0 | 1 | event |
| `COMSIG_TURF_CHANGE` | 0 | 1 | channel / watch |

### `code/modules/telesci` (1 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_TELESCI_TELEPORT` | 2 | 0 | event |

### `code/datums/om` (2 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_DO_AFTER_BEGAN` | 1 | 0 | event |
| `COMSIG_DO_AFTER_ENDED` | 1 | 0 | event |

### `code/modules/power` (2 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_HOSE_FORCEPUMP` | 1 | 0 | event |
| `COMSIG_IN_RANGE_OF_IRRADIATION` | 0 | 1 | before/ event (EVENT_VETO) |

### `code/modules/client` (2 signals, 2 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_CLIENT_CLICK` | 1 | 0 | event |
| `COMSIG_QDELETING` | 1 | 0 | event |

### `code/game/dna` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOB_DNA_MUTATION` | 1 | 0 | event |

### `code/modules/gamemaster` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_OBSERVER_DESTROYED` | 0 | 1 | event |

### `code/modules/generated_station` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOB_DEATH` | 0 | 1 | event |

### `code/modules/shieldgen` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |

### `code/game/mecha` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |

### `code/modules/clothing` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |

### `code/modules/paperwork` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_MOVABLE_ATTEMPTED_MOVE` | 0 | 1 | event |

### `code/_helpers` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_PROPAGATE_RAD_PULSE` | 1 | 0 | event |

### `code/modules/mining` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_ATOM_ENTERED` | 0 | 1 | event |

### `code/datums/behaviours` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_TURF_PREPARE_STEP_SOUND` | 1 | 0 | before/ event (EVENT_VETO) |

### `code/modules/tooltip` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_QDELETING` | 0 | 1 | event |

### `code/datums/lifecycle` (1 signals, 1 sites)

| Signal | Senders | Listeners | Replacement |
|---|---|---|---|
| `COMSIG_QDELETING` | 1 | 0 | event |

## Components and elements

A component becomes a behaviour whose state lives on the entity (declared fields);
an element becomes a shared behaviour singleton (no per-instance state). Add sites
count `AddComponent`/`AddComponentFrom`/`LoadComponent`/`AddElement` calls naming the type.

| Type | Kind | Add sites | Folders adding it | Equivalent | Defined in |
|---|---|---|---|---|---|
| `/datum/component/alt_appearances_owner` | component | 1 | `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/sparse_vars/alt_appearance.dm` |
| `/datum/component/alt_appearances_viewer` | component | 1 | `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/sparse_vars/alt_appearance.dm` |
| `/datum/component/antag` | component | 0 |  | behaviour (entity state) | `code/datums/components/antags/antag.dm` |
| `/datum/component/antag/changeling` | component | 1 | `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/antags/changeling/changeling.dm` |
| `/datum/component/artifact_master` | component | 1 | `code/modules/xenoarcheaology` 1 | behaviour (entity state) | `code/modules/xenoarcheaology/effect_master.dm` |
| `/datum/component/artifact_master/dreameel` | component | 0 |  | behaviour (entity state) | `code/modules/mob/living/simple_mob/subtypes/vore/spacecritters.dm` |
| `/datum/component/artifact_master/gasoxy` | component | 0 |  | behaviour (entity state) | `code/modules/mob/living/simple_mob/subtypes/vore/spacecritters.dm` |
| `/datum/component/artifact_master/gravity` | component | 0 |  | behaviour (entity state) | `code/modules/mob/living/simple_mob/subtypes/vore/spacecritters.dm` |
| `/datum/component/artifact_master/hungry_statue` | component | 0 |  | behaviour (entity state) | `code/modules/xenoarcheaology/artifacts/predefined/hungry_statue.dm` |
| `/datum/component/artifact_master/nightmare` | component | 0 |  | behaviour (entity state) | `code/modules/mob/living/simple_mob/subtypes/vore/spacecritters.dm` |
| `/datum/component/burninlight` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/burninlight.dm` |
| `/datum/component/burninlight/shadow` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/burninlight.dm` |
| `/datum/component/carried_afflictions` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/modules/mob/living/silicon/robot/component.dm` |
| `/datum/component/character_setup` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/modules/mob/living/living.dm` |
| `/datum/component/connect_containers` | component | 1 | `code/datums/proximity_monitor` 1 | behaviour (entity state) | `code/datums/components/connect_containers.dm` |
| `/datum/component/connect_loc_behalf` | component | 0 |  | behaviour (entity state) | `code/datums/components/connect_loc_behalf.dm` |
| `/datum/component/connect_mob_behalf` | component | 0 |  | behaviour (entity state) | `code/datums/components/connect_mob_behalf.dm` |
| `/datum/component/connect_range` | component | 3 | `code/datums/proximity_monitor` 2, `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/connect_range.dm` |
| `/datum/component/contract_document` | component | 1 | `code/modules/contracts` 1 | behaviour (entity state) | `code/modules/contracts/medical_trial_side_contracts.dm` |
| `/datum/component/contract_evidence_carrier` | component | 1 | `code/modules/contracts` 1 | behaviour (entity state) | `code/modules/contracts/contract_evidence.dm` |
| `/datum/component/coprolalia_disability` | component | 0 |  | behaviour (entity state) | `code/datums/components/disabilities/coprolalia.dm` |
| `/datum/component/coughing_disability` | component | 0 |  | behaviour (entity state) | `code/datums/components/disabilities/coughing.dm` |
| `/datum/component/crowd_detection` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/crowd_detection.dm` |
| `/datum/component/crowd_detection/agoraphobia` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/crowd_detection.dm` |
| `/datum/component/crowd_detection/lonely` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/crowd_detection.dm` |
| `/datum/component/crowd_detection/lonely/major` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/crowd_detection.dm` |
| `/datum/component/diabetic` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/low_sugar.dm` |
| `/datum/component/disposal_system_connection` | component | 3 | `code/modules/recycling` 2, `code/game/objects` 1 | behaviour (entity state) | `code/datums/components/machinery/disposal_connection.dm` |
| `/datum/component/dizzy_shake` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/animations/dizzy.dm` |
| `/datum/component/dq_property_test` | component | 1 | `code/modules/unit_tests` 1 | behaviour (entity state) | `code/modules/unit_tests/dq_property_tests.dm` |
| `/datum/component/drippy` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/drippy.dm` |
| `/datum/component/dry` | component | 1 | `code/modules/clothing` 1 | behaviour (entity state) | `code/datums/components/dry.dm` |
| `/datum/component/economic_adoption` | component | 1 | `code/modules/economy` 1 | behaviour (entity state) | `code/modules/economy/service_invoices.dm` |
| `/datum/component/effect_remover` | component | 1 | `code/modules/anomalies` 1 | behaviour (entity state) | `code/datums/components/effect_remover.dm` |
| `/datum/component/epilepsy_disability` | component | 0 |  | behaviour (entity state) | `code/datums/components/disabilities/epilepsy.dm` |
| `/datum/component/experiment_handler` | component | 5 | `code/modules/research` 2, `code/game/machinery` 1, `code/game/objects` 1, `code/modules/mob` 1 | behaviour (entity state) | `code/modules/research/tg/experisci/experiment/handlers/experiment_handler.dm` |
| `/datum/component/forensics_state` | component | 4 | `code/datums/components` 4 | behaviour (entity state) | `code/datums/components/sparse_vars/forensics.dm` |
| `/datum/component/forms` | component | 0 |  | behaviour (entity state) | `code/modules/mob/living/carbon/human/species/station/protean/forms.dm` |
| `/datum/component/forms/promethean` | component | 0 |  | behaviour (entity state) | `code/modules/mob/living/carbon/human/species/station/prommie_blob.dm` |
| `/datum/component/forms/protean` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/modules/mob/living/carbon/human/species/station/protean/protean_form.dm` |
| `/datum/component/gargoyle` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/gargoyle.dm` |
| `/datum/component/geiger_sound` | component | 1 | `code/game/objects` 1 | behaviour (entity state) | `code/datums/components/geiger_sound.dm` |
| `/datum/component/geiger_sound/wall` | component | 1 | `code/game/objects` 1 | behaviour (entity state) | `code/datums/components/geiger_sound.dm` |
| `/datum/component/gibbing_disability` | component | 0 |  | behaviour (entity state) | `code/datums/components/disabilities/gibbing.dm` |
| `/datum/component/hallucinations` | component | 1 | `code/modules/flufftext` 1 | behaviour (entity state) | `code/modules/flufftext/Hallucination.dm` |
| `/datum/component/hose_connector` | component | 0 |  | behaviour (entity state) | `code/datums/components/reagent_hose/connector.dm` |
| `/datum/component/hose_connector/endless_drain` | component | 2 | `code/game/objects` 2 | behaviour (entity state) | `code/datums/components/reagent_hose/connector.dm` |
| `/datum/component/hose_connector/endless_source` | component | 0 |  | behaviour (entity state) | `code/datums/components/reagent_hose/connector.dm` |
| `/datum/component/hose_connector/endless_source/water` | component | 1 | `code/game/objects` 1 | behaviour (entity state) | `code/datums/components/reagent_hose/connector.dm` |
| `/datum/component/hose_connector/inflation` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/reagent_hose/inflation.dm` |
| `/datum/component/hose_connector/input` | component | 10 | `code/modules/refinery` 5, `code/ATMOSPHERICS/components` 2, `code/modules/reagents` 2, `code/modules/vehicles` 1 | behaviour (entity state) | `code/datums/components/reagent_hose/connector.dm` |
| `/datum/component/hose_connector/input/borg` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/reagent_hose/inflation.dm` |
| `/datum/component/hose_connector/input/fryer` | component | 1 | `code/modules/food` 1 | behaviour (entity state) | `code/datums/components/reagent_hose/connector.dm` |
| `/datum/component/hose_connector/output` | component | 9 | `code/ATMOSPHERICS/components` 2, `code/modules/reagents` 2, `code/modules/refinery` 2, `code/modules/power` 1 | behaviour (entity state) | `code/datums/components/reagent_hose/connector.dm` |
| `/datum/component/hose_connector/output/borg` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/reagent_hose/inflation.dm` |
| `/datum/component/hose_connector/output/cow` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/reagent_hose/connector.dm` |
| `/datum/component/jittery_shake` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/animations/jittery.dm` |
| `/datum/component/material_container` | component | 0 |  | behaviour (entity state) | `code/datums/components/materials/material_container.dm` |
| `/datum/component/material_response` | component | 1 | `code/modules/material_science` 1 | behaviour (entity state) | `code/modules/material_science/material_responses.dm` |
| `/datum/component/mind_host` | component | 2 | `code/modules/mob` 1, `code/modules/organs` 1 | behaviour (entity state) | `code/datums/components/mind_host.dm` |
| `/datum/component/movable_state` | component | 12 | `code/datums/components` 12 | behaviour (entity state) | `code/datums/components/sparse_vars/movable_misc.dm` |
| `/datum/component/nervousness_disability` | component | 0 |  | behaviour (entity state) | `code/datums/components/disabilities/nervousness.dm` |
| `/datum/component/nif_menu` | component | 1 | `code/modules/nifsoft` 1 | behaviour (entity state) | `code/modules/nifsoft/nif_tgui.dm` |
| `/datum/component/nutrition_size_change` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/nutrition_size_change.dm` |
| `/datum/component/nutrition_size_change/growing` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/nutrition_size_change.dm` |
| `/datum/component/nutrition_size_change/shrinking` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/nutrition_size_change.dm` |
| `/datum/component/observer_events` | component | 1 | `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/sparse_vars/observer_events.dm` |
| `/datum/component/overlay_lighting` | component | 2 | `code/game` 2 | behaviour (entity state) | `code/datums/components/overlay_lighting.dm` |
| `/datum/component/personal_crafting` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/crafting/crafting.dm` |
| `/datum/component/photosynth` | component | 1 | `code/modules/unit_tests` 1 | behaviour (entity state) | `code/datums/components/traits/photosynth.dm` |
| `/datum/component/pollen_disability` | component | 0 |  | behaviour (entity state) | `code/datums/components/disabilities/pollen.dm` |
| `/datum/component/promethean_biology` | component | 0 |  | behaviour (entity state) | `code/modules/mob/living/carbon/human/species/station/prometheans.dm` |
| `/datum/component/radiation_effects` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/radiation_effects.dm` |
| `/datum/component/radiation_effects/besk` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/radiation_effects.dm` |
| `/datum/component/radiation_effects/diona` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/radiation_effects.dm` |
| `/datum/component/radiation_effects/promethean` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/radiation_effects.dm` |
| `/datum/component/radiation_effects/radiation_immune` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/radiation_effects.dm` |
| `/datum/component/radiation_effects/shadekin` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/radiation_effects.dm` |
| `/datum/component/reactive_icon_update` | component | 1 | `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/reactive_icon_update.dm` |
| `/datum/component/reactive_icon_update/clothing` | component | 1 | `code/modules/vore` 1 | behaviour (entity state) | `code/datums/components/reactive_icon_update.dm` |
| `/datum/component/recursive_move` | component | 24 | `code/modules/tgui` 5, `code/datums/components` 4, `code/game/objects` 3, `code/game/machinery` 2 | behaviour (entity state) | `code/datums/components/recursive_move.dm` |
| `/datum/component/remote_materials` | component | 2 | `code/modules/research` 2 | behaviour (entity state) | `code/datums/components/materials/remote_materials.dm` |
| `/datum/component/remote_view` | component | 5 | `code/modules/mob` 3, `code/datums/components` 1, `code/modules/flufftext` 1 | behaviour (entity state) | `code/datums/components/remote_view.dm` |
| `/datum/component/remote_view/item_zoom` | component | 3 | `code/game/objects` 2, `code/defines/obj` 1 | behaviour (entity state) | `code/datums/components/remote_view.dm` |
| `/datum/component/remote_view/mob_holding_item` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/remote_view.dm` |
| `/datum/component/remote_view/mremote_mutation` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/datums/components/remote_view.dm` |
| `/datum/component/remote_view/viewer_managed` | component | 1 | `code/datums` 1 | behaviour (entity state) | `code/datums/components/remote_view.dm` |
| `/datum/component/robot_belly` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/modules/mob/living/silicon/robot/dogborg/robot_belly.dm` |
| `/datum/component/rotting_disability` | component | 0 |  | behaviour (entity state) | `code/datums/components/disabilities/rotting.dm` |
| `/datum/component/schizophrenia` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/hallucinations.dm` |
| `/datum/component/shadekin` | component | 0 |  | behaviour (entity state) | `code/datums/components/species/shadekin/shadekin.dm` |
| `/datum/component/shadekin/full` | component | 2 | `code/modules/unit_tests` 2 | behaviour (entity state) | `code/datums/components/species/shadekin/shadekin.dm` |
| `/datum/component/shadekin/full/rakshasa` | component | 0 |  | behaviour (entity state) | `code/datums/components/species/shadekin/shadekin.dm` |
| `/datum/component/shadekin/phase_only` | component | 2 | `code/modules/unit_tests` 2 | behaviour (entity state) | `code/datums/components/species/shadekin/shadekin.dm` |
| `/datum/component/squeak` | component | 2 | `code/modules/clothing` 2 | behaviour (entity state) | `code/datums/components/squeak.dm` |
| `/datum/component/topturfcrossed` | component | 1 | `code/datums/elements` 1 | behaviour (entity state) | `code/datums/elements/topturfcrossed.dm` |
| `/datum/component/tourettes_disability` | component | 0 |  | behaviour (entity state) | `code/datums/components/disabilities/tourettes.dm` |
| `/datum/component/turfslip` | component | 1 | `code/game/turfs` 1 | behaviour (entity state) | `code/datums/components/turfslip.dm` |
| `/datum/component/update_on_z` | component | 1 | `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/sparse_vars/update_on_z.dm` |
| `/datum/component/using_machine_shim` | component | 1 | `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/materials/machine_shim.dm` |
| `/datum/component/vore_panel` | component | 1 | `code/modules/mob` 1 | behaviour (entity state) | `code/modules/vore/eating/living.dm` |
| `/datum/component/waddle_trait` | component | 1 | `code/datums/components` 1 | behaviour (entity state) | `code/datums/components/traits/waddle.dm` |
| `/datum/component/weaver` | component | 0 |  | behaviour (entity state) | `code/datums/components/traits/weaver.dm` |
| `/datum/component/xenochimera` | component | 1 | `code/datums/diseases` 1 | behaviour (entity state) | `code/datums/components/species/xenochimera.dm` |
| `/datum/component/xenoqueenbuff` | component | 0 |  | behaviour (entity state) | `code/datums/components/xenoqueen.dm` |
| `/datum/element/dcs_get_id_from_arguments_mock_element` | element | 0 |  | shared behaviour singleton | `code/modules/unit_tests/dcs_get_id_from_elements.dm` |
| `/datum/element/dcs_get_id_from_arguments_mock_element2` | element | 0 |  | shared behaviour singleton | `code/modules/unit_tests/dcs_get_id_from_elements.dm` |
| `/datum/element/footstep_override` | element | 0 |  | shared behaviour singleton | `code/datums/elements/footstep_override.dm` |
