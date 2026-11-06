# Proposal: opening a tgui window and asking for a file never sleep the caller

Status: approved by the user for building (the last two blocking keeps in the UI layer). Scope: doc section 2 (requests), section 13 (windows, prompts),
`code/library/ui/tgui/tgui_window.dm`, `code/content/client/dx_exec.dm`, `code/library/prompts/`.

Evidence base: `origin/master` at `1e14e5b4b6` (3 Nov 2026). The two keeps this removes were read at that commit.

## 0. Summary

1. **`tgui_window.initialize()` read three `winexists()` answers in the same proc.** `winexists()` is a client round trip, so the proc suspended its caller and
   every caller of `tgui_interact()` carried an `INVOKE_ASYNC`/`set waitfor = FALSE` with an `ALLOW(scheduler)` (11 sites in 9 files), and three more
   `winexists()` calls in `code/world/systems/tgui.dm` (window teardown) carried their own.
2. **`input() as file` is BYOND's only way to receive a client file.** Five sites (the two eventkit spawners, four calls, and the circuit printer import)
   each suspended the admin's or player's proc on the dialog.

## 1. Opening a window: a probe chain, not a wait

`initialize()` records what it was given (`initial_*`), sets `status = LOADING`, mints the page's `document_id`, sends the shell assets, and returns. The
parts that needed an answer from the client are steps that run when the answer arrives, through `dx_winexists()` (the one executor of BYOND's blocking
built-ins, `dx_exec.dm`):

| Step | Runs when | Does |
|---|---|---|
| `open_probe_exists` | the pooled id was probed | `winclone()` the hidden template if the id is absent, probe again |
| `open_probe_shell` | the clone was probed | `native_shell = (type == "MAIN")`, hide it, then build the page and `browse()` it |
| `open_probe_browser` | the browse was probed | `is_browser = (type == "BROWSER")`, set `on-close`, `opening = FALSE`, flush anything that became READY meanwhile |

A window that is not pooled starts at the browse step. Each callback carries the `document_id` it was issued for and drops itself when the window has
since been closed, re-initialised or has no client, so a late answer never browses a superseded page.

**Queueing.** `send_message()`, `send_raw_message()` and `flush_message_queue()` hold messages while `status != READY` **or** `opening`: the output
control name depends on `is_browser`, which is only known after the last probe. A `ready` from the page that arrives before the last probe sets
READY but does not flush; the last probe flushes.

**Timeout and close.** `open_probe_timeout` is armed (`TGUI_OPEN_PROBE_TIMEOUT`) with the first probe and cancelled by the last. If a probe never
answers the window logs it (`log_tgui`), drops its queue and goes back to CLOSED so the pool can hand it out again. `close()` ends an open in progress
the same way. A client that disconnects mid chain drops the callback (dx_exec drops answers of a gone client).

**Callers.** `tgui_interact()` and the lobby, shock, media and say windows now return at once, so the `INVOKE_ASYNC` wrappers and `waitfor = FALSE`
come off. `force_close_all_windows`, `reconcile_client_windows` and `force_close_window` hide a stale window from a `dx_winexists()` callback.

## 2. A file prompt kind

`/datum/prompt/file` is a request kind like `text` or `number`; `asks(/datum/prompt/file, fields = list("question" = ..., "extensions" = list("png")))`
and `open_request(src, /datum/prompt/file, PROC_REF(done), answerer = M, ...)` both work. Its answer is the uploaded file (`A.answer.value`).

`begin()` hands the dialog to `prompt_file_dialog()`, the one proc that runs `input(...) as null|file` (`set waitfor = FALSE`, annotated once). It
delivers through `prompt_window_answer()` / `prompt_window_closed()` like a window does, so `normalize()`/`refusal()` (is a file, within `max_bytes`,
extension allowed) apply and a refusal asks again. An answer that lands after the request ended (timeout, owner gone) is dropped. Test drivers and AIs
answer with `request_answer()` as for any prompt, so the kind is testable with a stubbed file.

Callers converted: eventkit item and structure (the setup stages gain `icon`/`icon2` steps; a cancelled or timed-out upload means no custom sprite, as
before), and the circuit printer import (re-checks adjacency when the file arrives).

## 3. Tests

* `tgui_window_open_does_not_sleep`: a window with a stub transport opens, queues an update, is driven through the three answers, holds the update
  until the last probe, then delivers it in order.
* `tgui_window_open_stale_and_timeout`: a closed or re-initialised window ignores a late probe; a silent probe times out and the window is reusable.
* `prompt_file_answers_and_refuses`: the kind through `request_answer()` with a stub file: accepted, refused by extension, cancelled.

## 4. Counts

ALLOW annotations before and after are in the landing report.
