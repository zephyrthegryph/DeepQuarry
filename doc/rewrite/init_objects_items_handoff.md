# Item initialization source cohort

Base: c3cb037784. Source only; no generator, lint, compiler or tests run here.

- Pipe painter: initial mode uses rolls() from the actual pipe-colour catalogue,
  independent of the later modes derives(). Distribution is uniform; native
  seeded rolls preserve explicitly supplied values and no longer consume global RNG.
- Debug RIG kit: set_info() constant outputs are type defaults. Its null optional
  data produces no allowed-type additions and no light-overlay override.
- Internal storage: keeps_if() checks location type before binding its typed owner;
  setup() links/names valid storage only. There are no descendant Initialize()
  overrides. This additionally repairs the invalid-owner typed-link crash.
- Head commcard: radio_listen(1435) replaces its manual radio subscription and owns
  teardown. The bug-monitor initializer was already commented out and is deleted.
- Radio: initial frequency sanitization is a pure initial derives(). Headset key
  channel setup runs after owned keys exist and before materialization subscribes;
  InitAtom runs setup_run before materialize. No headset descendant initializer
  consumes those channels between parent return and setup.
- GPS/translocator: existing setup helpers are declared directly. No descendant
  initializers exist. GPS creates its compass before binding the holder; the
  translocator builds the same radial image catalogue before materialization.

Focused selectors in dq_init_objects_items_tests.dm:
- /datum/unit_test/dq_init_objects_items
- /datum/unit_test/dq_init_objects_radio
- /datum/unit_test/dq_init_objects_device_setup

Root owns DME wiring and verification. Full original object baseline inventory
is in the ignored review packet data/codex-init-objects/inventory.json; no baseline
has been edited. Remaining initializers are not declared unconvertible: stack
amount/material ordering, tether construction before parent initialization,
flipper pAI/emag sequencing, ghost experiment ownership and storage latent
contents need their own mechanism/ordering review before conversion.

Additional source cohorts (also unverified):
- UAV ion trail: the existing native trail constructor already attaches to its
  owner and records its turf. owns_one starts_set preserves the old stopped
  on/processing flags; the redundant initializer is removed.
- Spectral goggles: the existing glasses hud_overlay lookup replaces the stored
  global-screen link, preserving static_vision and the clear advanced subtype.
- Cigarette packs: setup brands the real contents after the storage parent; no
  descendant initializer consumes brands earlier.
- TGMC MRE: setup uses the existing meal helper; component setup applies the
  seasoning after flavor params and the reagent capability are ready.
- Shield generators: owns_one starts_after(bcell) builds the gun through a typed
  factory preserving its exact (loc, generator) constructor arguments. Gun setup
  relinks the borrowed cell after the energy-gun parent's initializer clears it.
  No generator subtype Initialize overrides consume the weapon earlier.

Additional selectors (same test file): dq_init_objects_uav_trail,
dq_init_objects_spectral_goggles, dq_init_objects_cigarette_brand,
dq_init_objects_mre and dq_init_objects_shield_generator. Lifetime checks cover
owned gun/trail deletion and the gun's borrowed-cell non-deletion.

## Final source inventory before verification

This author removed 17 live Initialize overrides plus the already-commented
bug-monitor override from 16 production files. Matching original fingerprint
identities estimates 49 init baseline rows removed; this is not an analyzer
result. No baseline file has been edited. The original objects baseline has
571 rows; the original items/ subtree alone has 194. Other authors' weapon and
non-item changes are excluded from this author's 49-row estimate.

Exact removed type identities:
- `/obj/item/commcard/head`
- `/obj/item/gps`
- `/obj/item/personal_shield_generator`
- `/obj/item/gun/energy/gun/generator`
- `/obj/item/pipe_painter`
- `/obj/item/radio/headset`
- `/obj/item/radio`
- `/obj/item/bug_monitor`
- `/obj/item/perfect_tele`
- `/obj/item/clothing/glasses/ghost`
- `/obj/item/kit/suit/rig/debug`
- `/obj/item/stack/sandbags`
- `/obj/item/stack`
- `/obj/item/uav`
- `/obj/item/storage/fancy/cigarettes`
- `/obj/item/storage/internal`
- `/obj/item/storage/box/tgmc_mre`
- `/obj/item/reagent_containers/food/snacks/tgmc_mre_component`

Ten focused leaves now exist in dq_init_objects_items_tests.dm. Besides the
selectors above, dq_init_objects_stack_amounts tests actual phoron material
construction, variant/no-variant sprite defaults and supplied merge/sale defaults.
Root owns generation, baseline shrink, compilation, tests and the commit.

## Residual ownership partition (59 original rows)

These remain unconverted, not claimed universally unsupported. Their source
identities are retained in the ignored inventory packet for the next cohort.
- `code/game/objects/items.dm`: 8 rows.
- `code/game/objects/items/contraband.dm`: 1 rows.
- `code/game/objects/items/devices/communicator/cartridge.dm`: 1 rows.
- `code/game/objects/items/devices/communicator/communicator.dm`: 12 rows.
- `code/game/objects/items/devices/defib.dm`: 1 rows.
- `code/game/objects/items/devices/flipper.dm`: 3 rows.
- `code/game/objects/items/devices/radio/intercom.dm`: 4 rows.
- `code/game/objects/items/devices/radio/radio.dm`: 1 rows.
- `code/game/objects/items/devices/radio/radiopack.dm`: 1 rows.
- `code/game/objects/items/devices/scanners/motion_tracker.dm`: 4 rows.
- `code/game/objects/items/ghost_hunting/trap.dm`: 9 rows.
- `code/game/objects/items/ghost_hunting/weapons.dm`: 1 rows.
- `code/game/objects/items/trash.dm`: 2 rows.
- `code/game/objects/items/trash_material.dm`: 5 rows.
- `code/game/objects/items/weapons/storage/storage.dm`: 5 rows.
- `code/game/objects/mail.dm`: 1 rows.

Concrete ordering/contracts requiring care:

- Defib, radio pack and proton-pack tether calls run before parent Initialize.
  make_tethered adds actions_types before the item parent installs actions, so
  setup() is too late. Existing tether capability entries do not declare this
  constructor contract. A proper reusable tether lifecycle form is needed rather
  than moving the imperative call into a late wrapper.
- Storage's latent starts_with processing/calibration precedes child initializers.
  Generic initial_contents is eager and does not preserve latent eligible storage
  contents. A setup wrapper would run after child consumers. This needs the
  existing storage lifecycle migrated as a unit, retaining lazy semantics.
- Base item tool interning/action installation/embed defaults have many descendant
  initializer consumers. Moving the whole base body to setup changes their input
  ordering; its action/grant and trait contracts must be handled explicitly.
- Flipper's emag and pAI creation run before parent initialization, while its
  emotion runs after. These must not be merged into one late callback.
- Trash persistence depends on the actual mapload argument; setup has no mapload
  argument. A saved shadow flag is not introduced here.
- Ghost experiment-handler construction installs observers, ownership and RND
  connection state. A native owned constructor is plausible, but must prove the
  earlier ownership phase preserves those side effects before replacing it.

Other residuals (powder appearance, communicator camera/Exonet setup, mercenary
lookup, intercom power/hearing, motion subscriptions, material-trash random mix
and junk-mail generation) are source/behavior migration work still pending, not
proven engine gaps. The communicator file also contains a ghost mob initializer;
its type ownership is outside this item cohort despite its legacy file location.

The two accidentally presumed built-in name/desc setters were removed after
source review. Internal storage and cigarette descriptions retain direct built-in
assignments; no such setter APIs are invented. No remaining set_name/set_desc
calls occur in this author's changed production files.
