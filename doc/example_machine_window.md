# Worked example: a machine with a window and a button

This is the shape of a machine that opens a tgui window and takes one button press, written in the forms on master today. It is
copied from a real type, the atmospheric alert console (`code/content/machinery/computer/atmos_alert.dm`, window
`tgui/packages/tgui/interfaces/AtmosAlertConsole.tsx`), cut down to the parts that matter. The design behind each form is
`doc/rewrite/final_api.html` (sections 1, 9 and 13); AGENTS.md section 3a lists the forms.

## 1. The type and its block

```dm
/obj/machinery/computer/atmos_alert
	name = "atmospheric alert computer"
	desc = "Used to access the station's atmospheric sensors."
	circuit = VARIANT(/obj/item/circuitboard/atmos_alert)
	icon_keyboard = "atmos_key"
	icon_screen = "alert:0"

CAPABILITIES(/obj/machinery/computer/atmos_alert)
	configure(light_glow(color = "#e6ffff"))
	after_init(0, then(PROC_REF(listen_alarms)))
	interface("AtmosAlertConsole")
	op("clear", ui_act("clear", arg("ref", schema_text(32))), then(PROC_REF(ui_act_clear)))
```

- `interface("AtmosAlertConsole")` is the window: the name of the `.tsx` file under `tgui/packages/tgui/interfaces/`. It also gives
  the machine its "open the window" op; there is no `ui_interact()` or `attack_hand()` to write. `title =` sets the window title
  (`interface("AiSlipper", title = "AI Liquid Dispenser")` in `code/content/machinery/ai_slipper.dm`).
- `op("clear", ui_act("clear", arg("ref", schema_text(32))), then(PROC_REF(ui_act_clear)))` is the button. `ui_act("clear", ...)` binds
  it to the window action `act('clear', {...})` the TSX sends; `arg()` declares each parameter with a schema, so a missing or malformed
  value is refused before your proc runs. `then()` names the effect.
- `after_init(0, then(PROC_REF(listen_alarms)))` is work after the map load (instead of a `LateInitialize()` or an `Initialize()` tail).

## 2. The data the window shows

```dm
/obj/machinery/computer/atmos_alert/ui_data(datum/act/eval/A)
	var/list/data = list()
	var/list/major_alarms = list()
	for(var/datum/alarm/alarm in GLOB.atmosphere_alarm.major_alarms(get_z(src)))
		major_alarms[++major_alarms.len] = list("name" = sanitize(alarm.alarm_name()), "ref" = handle_of(alarm))
	data["priority_alarms"] = major_alarms
	return data
```

- `ui_data(datum/act/eval/A)` returns the window's data; `A.actor` is the viewer when the data depends on who looks.
- A thing the window can point back at is sent as `handle_of(thing)`, never a raw `\ref`.
- `analyze gen` writes the TypeScript type of this data to `tgui/packages/tgui/interfaces/generated/` (build output, gitignored).

## 3. The effect

```dm
/obj/machinery/computer/atmos_alert/proc/listed_alarms()
	var/list/listed = list()
	listed += GLOB.atmosphere_alarm.major_alarms(get_z(src))
	listed += GLOB.atmosphere_alarm.minor_alarms(get_z(src))
	return listed

/obj/machinery/computer/atmos_alert/proc/ui_act_clear(datum/act/op/A, ref)
	var/datum/alarm/alarm = ui_member(ref, listed_alarms(), /datum/alarm)
	if(alarm)
		for(var/datum/alarm_source/alarm_source in alarm.sources)
			var/obj/machinery/alarm/air_alarm = alarm_source.source
			if(istype(air_alarm))
				air_alarm.atmos_reset()
	. = TRUE
```

- The handler takes the op context (`datum/act/op/A`; `A.actor` is who pressed) and then the declared `arg()`s in order.
- `ui_member(value, within, type)` (`code/library/capabilities/ui_actions.dm`) turns a handle back into a datum only if it is one the
  window listed and of the right type: a forged or stale handle names nothing.
- Effects never sleep and never print a refusal and return; a refusal is a requirement (next section).

## 4. Refusing a press

A refusal is a `needs()` requirement on the op or on the whole window, which returns null to allow or a reason. From
`code/content/machinery/ai_slipper.dm`: every window action is refused while the panel is locked, unless the actor is a silicon.

```dm
	extend(TAG_UI, needs(any_of(req_is(nameof(locked), FALSE, because = MSG(ai_slipper/panel_locked)), req_actor_kind(/mob/living/silicon, because = MSG(ai_slipper/panel_locked)))))

MSG_DEF_SELF(ai_slipper/panel_locked, "Control panel is locked!")
```

A requirement on one button goes in its op: `op("x", ui_act("x"), needs(req_...(...)), then(PROC_REF(x)))`. The native requirements are
in `code/library/requirements/`.

## 5. The window

```tsx
type Data = { priority_alarms: alarm[]; minor_alarms: alarm[] };

export const AtmosAlertConsole = (props) => {
  const { act, data } = useBackend<Data>();
  // ...
  <Button onClick={() => act('clear', { ref: alert.ref })} />
};
```

The action name and parameter names match the `ui_act()` and `arg()` declarations; nothing else connects them.

## 6. Checklist

- Build (`tools/build/build.sh dm` or a focused test run): the build regenerates `deepquarry.dme` and the generated DM. Commit the
  manifest, never `code/engine/_generated/`.
- `bash tools/ci/check_ratchets.sh --changed-only`.
- A behaviour test beside the type or under `code/tests/unit_tests/` (it is included automatically), run with
  `bash tools/dq_focused_test.sh /datum/unit_test/<name>`.
- A state var other code reacts to is written through its generated `set_<var>()` (`set_locked(!locked)` in `ai_slipper.dm`).
