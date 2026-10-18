# `.dmt`: a typed language for DeepQuarry

**Status: FINAL. Approved by the user on 2026-10-17.**
This document supersedes `dmt_proposal.md` (the research draft) and `dmt_syntax_v2.md`. Where they disagree, this one wins.

Library names in the examples (`light_glow`, `op`, `Look`, `Prompt`) are illustrative. The language and the rules are final.

---

## 0. Summary

`.dmt` is a statically typed language with C-family syntax that compiles to DM. It mixes with `.dm` file by file, so BYOND stays the
reference for semantics and tests. A later backend lowers the same typed program to native code (RustyDream).

| Area | Decision |
|---|---|
| **Core** | Small and generic: classes (DM types), structs, enums, traits, generics, user-definable effects, relations, `const` evaluation and attributes |
| **Library, not builtins** | `Option`, `Result`, collections, `Duration` and unit suffixes, ownership and relations, the lifecycle, `capabilities`, ops, timers, systems |
| **What it guarantees** | No nulls; no dynamic calls; no sleeping outside declared effects; no stored references outside relations or `Weak<T>` (so no reference leaks); purity is inferred; change tracking comes from whole-program analysis |

---

## 1. Goals and non-goals

**Goals**
1. **Remove whole classes of bugs by construction:** null dereference, hard deletes and reference leaks, sleeping in effects, stale derived
   reads, untracked writes, `:` access, untyped FFI.
2. **Gradual adoption:** `.dm` and `.dmt` in one build, one file at a time.
3. **BYOND stays the oracle:** the output is readable `.dm`, and every existing test keeps its meaning.
4. **The framework is library code:** the design forms (final_api.html) are written in `.dmt`, and their semantics don't change.
5. **One program, two runtimes:** datums on BYOND, archetype ECS storage natively.
6. **Deterministic parallelism** on the native backend, enforced by the language from the first layer that has systems.

**Non-goals**
- No new engine design; final_api.html is still the design.
- No flag day: content nobody touches stays `.dm`.
- No runtime reflection, multi-shot continuations or textual macros.
- No speedup on BYOND: the output is as fast as hand-written DM.

---

## 2. Syntax rules

1. **Braces delimit blocks.** Indentation never changes meaning.
2. **Every statement ends with `;`.** Return is always explicit (`return x;`); the last expression is never returned implicitly.
3. **Functions** are `fn name(param: Type, ...) -> Ret { ... }`. A one-line body is `fn f(x: num) -> num => x * 2;`.
4. **`if (cond) { }`, `while (cond) { }`, `for (x in xs) { }`** take parentheses, as in DM and C.
5. **Operators are symbols:** `&&`, `||`, `!`, `==`, `!=`, `<=`, `+=`. The only word operators are `is` (type and pattern test) and `as`
   (checked cast).
6. **Lambdas are ordinary arguments with named parameters:** `(m) => m.alive()` or `(m: /mob) => { ...; return x; }`. There are no trailing
   lambdas and no implicit `it`.
7. **Named arguments use `name = value`:** `Prompt.text("Label?", max = 40)`. Attributes use the same form in brackets:
   `@test[tag = "power"]`.
8. **Strings interpolate with DM's brackets:** `"\The [user] lights [self]."`.
9. **Fields:** `var x: T = v;` (mutable) or `let x: T = v;` (set at creation) declares one. `override x = v;` changes an inherited default.
   Methods are overridden with `override fn`.
10. **`self` is the instance and is implicit in methods.** `Self` is the type. `Self.cell` is a field reference and `Cell.percent` a method
    reference.
11. **Unit suffixes are written directly on numbers:** `2s`, `1.5s`, `500ms`, `3t`. Suffixes are library functions (`suffix s(n: num) -> Duration`).
12. **Compile-time evaluation is `const`,** as in Zig: `const MAX = 40;`, `const fn`, `const { }` blocks, `const T: Type` parameters.
13. **There are no `??`, `let ... else` or `it`.** Use `.or(default)`, `require` or narrowing, and named lambda parameters instead.

---

## 3. Built in versus library

| Built into the compiler | Library (`std`, `library`); lang items are marked `@lang[...]` |
|---|---|
| `class`, `struct`, `enum`, `trait`, `impl`, `effect`, `relation`, `try`/`handle`, `using` | `enum Option<T> { None, Some(T) }` marked `@lang[option]`, which gives `T?` and narrowing on `== None` |
| Generics, trait bounds, const generics, associated types and constants | `enum Result<T, E>` plus `trait Try`, which decides how `require` exits |
| Effect rows (inferred, polymorphic) and the access row (read and write sets) | `List<T>`, `Map<K, V>`, `Set<T>`, and adapters (`map`, `filter`, `fold`) |
| Narrowing, `require`, `requires`, `with` | Relations (`Owns`, `Inside`, `Watches`, slot policies), `Weak<T>`, the `Lifecycle` trait |
| The stored-reference rule (§9) | `capabilities`, `op`, `every`, `after`, `system`, `Query`, `Changed<F>` |
| `const` evaluation with type reflection, attributes | `Duration` and suffixes, `Color`, units (`Kpa`, `Kelvin`, `Watts`) |
| Primitives: `num` (f32, exactly BYOND's), `int` (f32-exact integer), `bool`, `text`, `Type<T>`, `Never`, `()` | Engine effects `Delay`, `Ask`, `Rng`, `Io`, `Refuse`, `Schedule`, and their default handlers |

`Option</obj>` and `Option<num>` are stored as a nullable var (`None` is `null`), so they cost nothing at runtime.

---

## 4. The language by example

### 4.1 Classes, fields and overrides

```
class /obj/item/cell {                     // the path is the type; the parent is /obj/item, as in DM
    var charge: num = 0;
    var max_charge: num = 1000;
    let rigged: bool = false;

    fn percent() -> num => charge / max_charge * 100;
    fn full() -> bool => charge >= max_charge;
}

class /obj/item/cell/high {
    override max_charge = 10000;
    override charge = 10000;
}

use /obj/item/cell as Cell;
```

### 4.2 Enums with data, `match`, and `is` patterns

```
enum ChargeMode { Idle, Charging(rate: num), Fault(reason: Msg) }

fn describe(m: ChargeMode) -> text {
    match (m) {
        ChargeMode.Idle => { return "idle"; }
        ChargeMode.Charging(var r) if (r > 50) => { return "fast charging"; }
        ChargeMode.Charging(_) => { return "charging"; }
        ChargeMode.Fault(var why) => { return "fault: [why]"; }
    }                                      // a missing case is a compile error
}

if (mode is ChargeMode.Charging(var rate)) { use_power(rate); }
```

### 4.3 Options and narrowing

```
var name = ask(who, Prompt.text("Label?", max = 40));   // name: text?
if (name == None) { return; }
l.name = name;                                           // narrowed to text

var label = name.or("unnamed");
```

Fields narrow too: a field stays narrowed until the next assignment to it, or until a call whose write set includes it. The compiler knows
every function's write set from the access row.

### 4.4 Requirements in one line

There are three forms. They all desugar to `if (!cond) { exit; }`, and the exit depends on the function:
- a function using `Refuse` refuses, with the message;
- a function returning a `Try` type returns its failure;
- anything else returns.

```
// 1. The statement form: checks and binds mid-body
fn label_locker(who: /mob, l: /obj/structure/closet) uses Delay, Ask {
    wait(5s);
    require name = ask(who, Prompt.text("Label?", max = 40));
    l.name = name;
}

fn charge_step() {
    require cell else { mode = ChargeMode.Idle; };
    require mode is ChargeMode.Charging(var rate);
    cell.charge = min(cell.charge + rate, cell.max_charge);
}

// 2. The clause form: declarative preconditions on the signature. They must be pure.
fn insert(a: Act)
    requires cell == None    : Msg.ChargerFull,
             a.held is Cell  : Msg.NotACell,
             !panel_open     : Msg.PanelOpen
    uses Delay, Ask
{
    wait(1s, keeps = Held | Adjacent);
    cell = a.held;                         // a.held narrowed to Cell by the clause
}

// 3. The scoped form: run a block only when the values are present
with (c = cell, m = holder()) {
    m.show("[c.percent()]%");
}
```

An op uses a function's `requires` clauses as its requirement (`op("insert", holding<Cell>(), Self.insert)`). UI and AI can then ask
"would this be allowed?" without running the body.

### 4.5 Structs, tuples and newtypes

```
@derive[Eq, Codec]
struct Glow { lum: num; color: Color? = None; range: num = 2; }

var g = Glow(lum = 3, color = Some(#E09D37));
var dim = g.with(lum = 1);                 // structs are immutable values
var (x, y) = turf.coords();

struct Kpa(num);  struct Kelvin(num);  struct Watts(num);  struct Id<T>(int);
```

### 4.6 Traits, generics and associated items

```
trait Powered {
    fn draw_watts() -> Watts;
    fn priority() -> int => 5;
}

impl Powered for /obj/machinery/cell_charger {
    fn draw_watts() -> Watts {
        if (mode is ChargeMode.Charging(var r)) { return Watts(r * 10); }
        return Watts(5);
    }
}

fn total_draw<T: Powered>(xs: List<T>) -> Watts => xs.fold(Watts(0), (acc, x) => acc + x.draw_watts());

trait Add<R> { type Out; fn add(r: R) -> Out; }
trait Reagent { const COLOR: Color; const BOILING: Kelvin; }

class Pool<T: /datum, const CAP: int = 64> {
    var free: List<T> = [];
    fn take(make: () -> T) -> T => free.pop().or_else(make);
}
```

### 4.7 Capability bounds, read-only parameters, sealed hierarchies and typestate

```
fn drain<T: Has<Powered>>(m: T) { m.power.draw(5); }      // checked statically
fn describe(c: in Cell) -> text => "[c.percent()]%";        // `in`: no writes through c

sealed class /datum/damage { }                               // exhaustive `match` over its subclasses

struct Frame<S> { }
fn wire(f: Frame<Bare>) -> Frame<Wired>;
fn screw(f: Frame<Wired>) -> Frame<Done>;                    // screwing an unwired frame does not compile
```

### 4.8 Type values

```
fn spawn<T: /atom/movable>(kind: Type<T>, at: /turf) -> T;

var kind: Type<Cell> = /obj/item/cell/high;
var c = spawn(kind, here);                  // c: Cell
for (t in Cell.subtypes()) { register(t); }
var base = kind.default(Self.max_charge);   // DM's initial(), typed
```

### 4.9 Lambdas, function references and functional style

```
var double = (x: num) => x * 2;                                // (num) -> num
var names = mobs.filter((m) => m.alive()).map((m) => m.name);
var total = cells.map(Cell.percent).sum();                     // unbound method reference
after(5s, charger.finish);                                     // bound method reference
xs.sort_by((a, b) => a.priority() <=> b.priority());
```

A stored closure (a timer or an observer) holds what it captures weakly, and it does not run if a captured target is gone.

### 4.10 Extension functions and suffixes

```
suffix s(n: num) -> Duration => Duration.from_ds(n * 10);
suffix ms(n: num) -> Duration => Duration.from_ds(n / 100);

extend /mob {                              // statically dispatched; adds no proc to /mob
    fn is_stunned() -> bool => has_status(Status.Stun);
}
```

### 4.11 Unions at the BYOND boundary only

An `extern` declaration may say `-> /mob | /obj | None` when a built-in really returns mixed things. You `match` on it right away, and `.dmt`
code cannot declare its own unions; enums cover that.

---

## 5. Effects

### 5.1 Declaring, performing and inferring

```
effect Delay  { fn wait(d: Duration); }
effect Ask    { fn ask<T>(who: /mob, p: Prompt<T>) -> T?; }
effect Rng    { fn roll(lo: int, hi: int) -> int; }
effect Refuse { fn refuse(why: Msg) -> Never; }
effect Emit<E> { fn emit(e: E); }
```

- Effect operations are ordinary calls.
- Effects are inferred within a module, and a `pub fn` declares them with `uses`.
- A function with no effects is pure. A look's `draw`, a stat formula and every `requires` clause must be pure; the compiler checks it.
- **Effect polymorphism** lets higher-order functions pass effects through:

```
fn map<T, U, E>(xs: List<T>, f: (T) -> U uses E) -> List<U> uses E;
```

### 5.2 Handlers

**Inline, mainly for tests:**

```
@test[tag = "lockers"]
fn labelling_waits_and_uses_the_answer() {
    var l = spawn(/obj/structure/closet, test_turf());
    var waited = 0s;
    try {
        label_locker(test_mob(), l);
    } handle Delay.wait(d) {
        waited += d;
        resume();
    } handle Ask.ask(who, prompt) {
        resume(Some("Morgue"));
    }
    assert(waited == 5s && l.name == "Morgue");
}
```

**As an `impl`, the general form:**

```
struct TestClock { var now: Duration = 0s; }

impl Delay for TestClock {
    fn wait(d: Duration) { now += d; }      // returning resumes the caller
}

var clock = TestClock();
using (clock) { label_locker(test_mob(), l); }
```

- A handler method that returns resumes the caller.
- A handler that truly suspends takes an explicit `k: Continuation<T>` parameter. Only engine handlers like the kernel's `Delay` need that.
- The engine installs default handlers around every op, timer and system: `Delay` becomes a kernel timer, `Ask` a request, `Rng` the seeded
  RNG and `Io` async IO.

### 5.3 Lowering on BYOND

| Handler kind | Lowered to |
|---|---|
| **Returns normally** (`Rng`, `Emit`, `Log`, most user handlers) | A plain proc call on the active handler |
| **Never resumes** (`Refuse`) | An early return of the reason through the frames |
| **Suspends** (`Delay`, `Ask`, `Io`) | A state-machine datum: locals become vars, `resume()` runs `switch(pc)`, and it is registered with the kernel's timers and requests |

Only functions that can reach a suspending effect become state machines. Continuations are one-shot. A frame belongs to the entity it runs
on, so destroying the entity cancels it.

---

## 6. `const` and attributes

```
@derive[Codec]
struct Reading { kpa: Kpa; temp: Kelvin; }

const fn derive_codec(t: TypeInfo) -> Items { ... }      // walks t.fields and emits encode/decode

@test[tag = "power"]
fn charger_fills_cell() { ... }
```

- `capabilities { }`, `op`, `every`, `construction` and `relation` are `const` functions or ordinary functions in the library.
- Their errors point at user code, and `dmt expand` shows what they generate.
- Changing them never needs a compiler release.

---

## 7. Lifecycle

```
trait Lifecycle {
    fn on_init(ctx: Init) uses Schedule { }      // writes self, can schedule; cannot wait or ask
    fn on_destroy(force: bool) { }               // consequences only
}
```

| Today | In `.dmt` |
|---|---|
| An `Initialize()` override with an ALLOW annotation | `override fn on_init(ctx)`, which the checker limits to per-instance state and scheduling |
| `starts =` | A relation-end initializer: `var cell: Owns.child<Cell>? = spawn(/obj/item/cell/high);` |
| `after_init(delay, then(...))` | `ctx.after(2s, Self.sync);` |
| `Destroy()` overrides | Forbidden. Teardown is generated from the type's relation ends and weak handles, like Rust's drop glue. |

---

## 8. Change tracking

- There is no `TRACKED` and no setters to write. Assignments are plain (`lit = true;`).
- The compiler sees every write and every pure reactive read (looks, stats, `requires` clauses, `Changed<F>` queries). From those it emits the
  change graph's per-type plans.
- A field that nothing reacts to compiles to a plain assignment.
- `.dmt` fields are write-private to `.dmt`. `.dm` code writes them through generated setters, which keeps the analysis closed.
- The runtime is the approved change graph: `write(E, key)`, the four timing classes, queues and subscriptions.

---

## 9. Relations, ownership, hooks and systems

### 9.1 The core rule

> **A field that stores an entity must be a relation end or a `Weak<T>`.** Parameters and locals are borrows and are unrestricted.

Everything else is library code.

### 9.2 Relations, Bevy-style

```
relation Owns<P: /datum, C: /datum> {
    source C.owner: P;                     // at most one owner (Bevy's ChildOf)
    target P.owned: Set<C>;                // kept in sync (Bevy's Children)
    on_target_destroyed(p, c) { destroy(c); }
}

relation Inside<C: /atom, I: /atom/movable> {
    source I.container: C;
    target C.contents_of: List<I>;
    on_target_destroyed(box, item) { spill(item, box, box.spill_policy); }
}

relation Watches<A: /datum, B: /datum> {   // many-to-many, which our `links` need
    many A.watching: Set<B>;
    many B.watched_by: Set<A>;
    on_either_destroyed = Unlink;
}
```

You write one side (`item.container = locker;`) and the generated setter keeps the other side and runs the hooks.

| Approved form (relations proposal) | As a library relation |
|---|---|
| `owns_one` / `owns_many` | `Owns` |
| `ref_one` / `ref_many` | A relation with `on_target_destroyed = Clear` (a stored, strong, non-owning reference) |
| `ref_*(weak)` | `Weak<T>` |
| `links` (with conflict refusal) | A many-to-many relation with a conflict hook |
| `slot` | A relation whose `on_link` hook runs the admission requirement |
| SPILL, SPILL_FRACTION, PRIVATE_COPY | Policy values used in hooks |
| BYOND built-ins (`vis_contents`, `client.screen`, `image.loc`, ...) | `@native` relations: the engine provides storage, and the type system sees both ends |

**Hook ordering:** hooks run inside the write. On parallel systems, effects a hook causes on other entities are deferred commands.

### 9.3 Hooks, observers and systems

| Bevy | `.dmt` |
|---|---|
| Component hooks | Capability and relation hooks |
| Observers | `observe<Opened>((e) => ...)`; `publish(...)`; `Emit<E>` underneath |
| Systems with `Changed<T>` | `system` with typed queries; `Changed<F>` reads a change-graph subscription queue, so there is no scan |

```
system Power {
    every(1s);
    fn rebalance(dt: Duration,
                 changed: Query</obj/machinery, Changed<Self.stat>, With<Powered>>,
                 grid: Res<Grid>) {
        for (m in changed) { grid.update(m, m.draw_watts()); }
    }
}
```

### 9.4 Parallelism (native backend)

- Systems with disjoint read and write sets run in parallel.
- A query marked `par` runs its body in parallel when it writes only the entity being iterated.
- Writes to other entities from `par` code are deferred commands, applied at the end of the phase in entity-id order.
- The DM backend emulates the same deferral, so both backends behave identically.
- Outside `par`, the change graph's inline settle rule applies unchanged.

---

## 10. Full conversion: the candle family

```
module content.items.candle;

use library.light.{light_glow, set_glow, Glow};
use library.ops.{Act, in_hand, holding, tool};
use library.items.{item_sounds, replace_with};

class /obj/item/flame/candle {
    override name = "red candle";
    override desc = "a red pillar candle. Its specially-formulated fuel-oxidizer wax mixture allows continued combustion in airless environments.";
    override icon = 'icons/obj/candle.dmi';
    override icon_state = "candle1";
    override w_class = ItemSize.Tiny;

    var wax: num = 7200;                    // four hours at one step every 2s
    var icon_type: text = "candle";

    capabilities {
        light_glow(color = #E09D37);
        item_sounds(drop = Sfx.ItemsDropGloves, pickup = Sfx.ItemsPickupGloves);
        op("snuff", in_hand(), Self.snuff);
        op("light_from", holding</obj/item/flame>(), Self.light_from);
        op("use_welder", tool(Tool.Welder), Self.welder_used, costs = Fuel(0));
        every(2s, Self.flame_step, active = (c) => c.lit);
    }

    fn wax_stage() -> int {
        if (wax > 3600) { return 1; }
        if (wax > 800) { return 2; }
        return 3;
    }

    fn look_state() -> text => "[icon_type][wax_stage()][lit ? "_lit" : ""]";

    override fn draw(look: Look) {          // pure: no effects, so no writes
        super.draw(look);
        look.state(look_state());
    }

    fn light_from(a: Act) requires a.held.lit : Msg.ReqFailed {
        light(user = a.actor);
    }

    fn welder_used(a: Act) requires a.held.welder().on : Msg.ReqFailed {
        light(flavor = notice("\The [a.actor] casually lights [self] with [a.held]."));
    }

    fn light(flavor: text? = None, user: /mob? = None) {
        if (lit) { return; }
        lit = true;
        if (flavor == None) {
            flavor = user == None ? notice("\The [self] lights up.") : notice("\The [user] lights [self].");
        }
        visible_message(flavor);
        set_glow(self, Glow(lum = CANDLE_LUM));
    }

    fn snuff() {
        if (!lit) { return; }
        lit = false;
        set_glow(self, Glow(lum = 0));
    }

    fn flame_step() {
        if (wax > 0) { wax -= 1; }
        if (wax <= 0) {                     // never below zero
            burn_out();
            return;
        }
        if (loc is /turf) { loc.hotspot_expose(700, 5); }    // loc narrowed to /turf
    }

    fn burn_out() {
        if (loc is /mob) { dropped(loc); }
        replace_with(self, /obj/item/trash/candle);
    }
}

class /obj/item/flame/candle/small {
    override name = "small red candle";
    override desc = "a small red candle, for more intimate candle occasions.";
    override icon_state = "smallcandle";
    override icon_type = "smallcandle";
    override w_class = ItemSize.Small;
}

class /obj/item/flame/candle/candelabra {
    override name = "candelabra";
    override desc = "a small gold candelabra. The cups that hold the candles save some of the wax from dripping off, allowing the candles to burn longer.";
    override icon_state = "candelabra";
    override w_class = ItemSize.Small;
    override wax = 20000;

    override fn burn_out() { snuff(); }      // the cups keep it: it goes out and shows melted

    override fn look_state() -> text {
        if (wax <= 0) { return "candelabra_melted"; }
        return lit ? "candelabra_lit" : "candelabra";
    }
}

class /obj/item/flame/candle/everburn {
    override wax = 99999;
    override fn on_init(ctx: Init) { light(flavor = notice("\The [self] mysteriously lights itself!")); }
}
```

What `light()` lowers to on BYOND:

```dm
/obj/item/flame/candle/proc/light(flavor_text = null, mob/user = null)
	if(lit)
		return
	set_lit(TRUE)                                   // generated setter: one change-graph plan lookup
	if(isnull(flavor_text))
		flavor_text = isnull(user) ? span_notice("\The [src] lights up.") : span_notice("\The [user] lights [src].")
	visible_message(flavor_text)
	set_glow(src, GLOW(CANDLE_LUM, null, null))
```

## 11. Full conversion: a machine with an effectful op

```
module content.machinery.cell_charger;

class /obj/machinery/cell_charger {
    var mode: ChargeMode = ChargeMode.Idle;
    var rate: num = 50;
    var cell: Owns.child<Cell>? = None;      // owned; the Owns policy handles destroy

    capabilities {
        powered();
        slot(Self.cell, accepts = Cell, capacity = 1, replace = Refuse);
        op("insert", holding<Cell>(), Self.insert);
        op("eject", empty_hand(), Self.eject);
        every(1s, Self.charge_step, active = (c) => c.mode != ChargeMode.Idle);
    }

    fn insert(a: Act)
        requires cell == None   : Msg.ChargerFull,
                 a.held is Cell : Msg.NotACell
        uses Delay, Ask
    {
        wait(1s, keeps = Held | Adjacent);
        var fast = ask(a.actor, Prompt.confirm("Fast charge? It wears the cell.")).or(false);
        commit;                               // no waiting or asking after this point
        cell = a.held;                        // the relation setter moves it out of the hand
        mode = ChargeMode.Charging(fast ? rate * 2 : rate);
    }

    fn eject(a: Act) requires cell != None : Msg.ChargerEmpty {
        a.actor.put_in_hands(cell);           // relinks the cell; the charger's end clears
        mode = ChargeMode.Idle;
    }

    fn charge_step() {
        require cell else { mode = ChargeMode.Idle; };
        require mode is ChargeMode.Charging(var r);
        cell.charge = min(cell.charge + r, cell.max_charge);
        if (cell.full()) {
            mode = ChargeMode.Idle;
            publish(Charged(self, cell));
        }
    }

    override fn draw(look: Look) {
        super.draw(look);
        with (c = cell) { look.layer("cell-[ceil(c.percent() / 25)]"); }
    }
}

impl Powered for /obj/machinery/cell_charger {
    fn draw_watts() -> Watts {
        if (mode is ChargeMode.Charging(var r)) { return Watts(r * 10); }
        return Watts(5);
    }
}
```

`insert` is the only state machine here, because it uses `Delay` and `Ask`. Its `requires` clauses are the op's requirement. `draw` is pure,
and `charge_step` writes but cannot wait.

---

## 12. Interop with `.dm`

- **`.dmt` calling `.dm`:** through `extern` declarations generated from analyze's semantic model of `.dm`. That boundary is unchecked by
  design, and BYOND built-ins get hand-written typed externs (`get_step(...) -> /turf?`).
- **`.dm` calling `.dmt`:** allowed. Debug and test builds insert type and null assertions at the entry points.
- **Fields:** `.dmt` fields are written from `.dm` only through generated setters.
- **Rust FFI:** `extern rust` declarations are generated from the Rust signatures, which are the source of truth. On BYOND they lower to
  generated byondapi marshalling; natively they are direct calls on shared data.
- **The new tree:** AGENTS.md §3c is amended so that a file converted to `.dmt` in place counts as fully migrated. It does not need a separate
  pure `git mv`.

## 13. Tooling

| Tool | Decision |
|---|---|
| **Front end** | `tools/dmb` (dmbc): the `.dmt` parser and type checker are a second front end that lowers into the same IR as DM, so `.dm` and `.dmt` share one compile, the daemon's incremental sessions and native source positions. Error-recovering, hand-written. `tools/analyze` keeps the lints and reads `.dmt` through dmbc's front end. |
| **Output** | No generated `.dm`: `.dmt` compiles straight to dmbc's IR. `dmt expand` is an optional debug dump of the lowered form. |
| **Source maps** | Not needed: dmbc carries native source positions for `.dmt` |
| **Commands** | `dmt check`, `dmt expand`, `dmt fmt`; an LSP later |
| **DreamChecker** | Keeps running on `.dm` files; `.dmt` is checked by dmbc's type checker and analyze's lints |
| **Agents** | One grammar, errors that name the fix (analyze's style), and this document as the reference |

## 14. Rollout: layers that each ship

Each layer lands, is used on real files, and stays useful if work stops there.

| Layer | Adds | Pilot and gate |
|---|---|---|
| **L1** | dmbc accepts `.dmt` files with L1 syntax: parser, classes, fields, `fn`, typed parameters, control flow, `Option` lang item and narrowing, `require`/`with`, simple enums, interpolation, lowering to the shared IR | `code/engine/stats` and `kernel/safe.dm` convert, and their tests pass unchanged |
| **L2** | Enums with data, `match`/`is` patterns, structs, tuples, newtypes, generics, traits, associated items, extension functions, suffixes | `Duration` and units move to `std` |
| **L3** | Lambdas, function references, adapters, effect polymorphism | Callbacks without `CALLBACK` boilerplate |
| **L4** | Effects with engine handlers (`Delay`, `Ask`, `Rng`, `Refuse`, `Schedule`), state-machine lowering, `requires` clauses, `commit` | One op family converts with no `sleep`; its requirements come from `requires` |
| **L5** | User-defined effects, `try`/`handle`, impl handlers and `using`, `@test` | Scripted tests replace hand-made test hooks |
| **L6** | The stored-reference rule, `relation`, `Weak<T>`, `Lifecycle`, generated teardown, capability bounds | Static leak freedom on converted files; relations runtime as the lowering target |
| **L7** | `const` evaluation, attributes, `@derive` | `capabilities`, `op` and `every` as library code |
| **L8** | Whole-program change analysis, write-private fields | The change graph's plans emitted by the compiler |
| **L9** | Native backend on RustyDream, `par` systems | Decided after L6, on a measured benchmark slice |

**Ordering against the in-flight migration:**
- L1–L3 can start now; they don't touch the framework.
- L7 waits for the final_api phase 1–2 forms to land.
- Until a layer lands, AGENTS.md's "write what exists on master today" applies to every agent.

## 15. Decisions (all resolved)

| # | Question | Decision |
|---|---|---|
| 1 | Surface syntax | C-family with braces and semicolons (§2) |
| 2 | Front-end location | `tools/dmb`, as a second front end in dmbc that lowers into the same IR as DM; analyze reads `.dmt` through it |
| 3 | Generated `.dm` | None; `.dmt` lowers to the shared IR, and `dmt expand` is an optional debug dump |
| 4 | Number semantics | `num` is f32 exactly as BYOND; `int` is an f32-exact integer |
| 5 | Effect set | User-definable |
| 6 | Effect rows | Two: effects, and access (read and write sets) |
| 7 | References | Relations plus `Weak<T>` for storage; borrows for locals and parameters; no `own`/`ref` keywords |
| 8 | Parallel rule | `par` systems and queries only, emulated on the DM backend |
| 9 | Rust FFI source of truth | Rust signatures, with generated externs |
| 10 | AGENTS.md §3c | Amended: in-place `.dmt` conversion counts as migrated |
| 11 | Pilot | `engine/stats` and `kernel/safe.dm`, then `time` and `requests` |
| 12 | Ordering | L1–L3 now; L7 after the framework forms land |
| 13 | Native commitment | Decided after L6 on a benchmark slice |
| 14 | Source-map probe | Dropped: native source positions |

## 16. Risks

- **Two languages during the transition.** Mitigation: generated externs, strict boundaries, one file at a time.
- **Debugging lowered code.** Mitigation: native source positions in dmbc, and `dmt expand` as a debug dump.
- **Effect lowering correctness.** Mitigation: frames are tested through handlers, and tests run on BYOND.
- **Native speed is a hypothesis, not a result.** RustyDream was slow because of dynamic semantics (tagged values, name lookup, possible
  suspension anywhere, interpreter fallback). Typing removes those causes, but L9 is decided on measurements.
- **BYOND built-in behaviour natively** (appearances, view, maps, browse/tgui) stays the largest native risk, and it is RustyDream's scope.
