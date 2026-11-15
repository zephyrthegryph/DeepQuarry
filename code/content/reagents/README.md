/\*
NOTE: IF YOU UPDATE THE REAGENT-SYSTEM, ALSO UPDATE THIS README.

Structure: /////////////////// //////////////////////////
// Mob or object // -------> // Reagents var (datum) // Is a reference to the datum that holds the reagents.
/////////////////// //////////////////////////
| |
The object that holds everything. V
reagent_list var (list) A List of datums, each datum is a reagent.

    							      |          |          |
    							      V          V          V

    							         reagents (datums)	    	Reagents. I.e. Water , antitoxins or mercury.

Random important notes:

    An objects on_reagent_change will be called every time the objects reagents change.
    Useful if you want to update the objects icon etc.

About the Holder:

    The holder (reagents datum) is the datum that holds a list of all reagents
    currently in the object.It also has all the procs needed to manipulate reagents

    Vars:
    list/datum/reagent/reagent_list
    	List of reagent datums.

    total_volume
    	Total volume of all reagents.

    maximum_volume
    	Maximum volume.

    atom/my_atom
    	Reference to the object that contains this.

    Procs:

    get_free_space()
    	Returns the remaining free volume in the holder.

    get_master_reagent()
    	Returns the reference to the reagent with the largest volume

    get_master_reagent_name()
    	Ditto, but returns the name.

    get_master_reagent_id()
    	Ditto, but returns ID.

    update_total()
    	Updates total volume, called automatically.

    handle_reactions()
    	Checks reagents and triggers any reactions that happen. Usually called automatically.

    add_reagent(var/id, var/amount, var/data = null, var/safety = 0, ...)
    	Adds [amount] units of [id] reagent. [data] will be passed to reagent's mix_data() or initialize_data(). If [safety] is 0, handle_reactions() will be called. Returns 1 if successful, 0 otherwise.
    	Contaminants are reagents too (see "Contaminants" below), so every add, transfer and ingest moves them like any other reagent.

    add_sourced_reagent(var/id, var/amount, list/profile, ...)
    	Adds up to [amount] units of stock [id] with the contaminants of [profile] (contaminant id -> units per unit of stock, chem_source_profile()). Returns the stock added.

    remove_reagent(var/id, var/amount, var/safety = 0)
    	Ditto, but removes reagent. Returns 1 if successful, 0 otherwise.

    del_reagent(var/id)
    	Removes all of the reagent.

    has_reagent(var/id, var/amount = 0)
    	Checks if holder has at least [amount] of [id] reagent. Returns 1 if the reagent is found and volume is above [amount]. Returns 0 otherwise.

    clear_reagents()
    	Removes all reagents.

    get_reagent_amount(var/id)
    	Returns reagent volume. Returns 0 if reagent is not found.

    get_data(var/id)
    	Returns get_data() of the reagent.

    get_reagents()
    	Returns a string containing all reagent ids and volumes, e.g. "carbon(4),nittrogen(5)".

    remove_any(var/amount = 1)
    	Removes up to [amount] of reagents from [src]. Returns actual amount removed.

    trans_to_holder(var/datum/reagents/target, var/amount = 1, var/multiplier = 1, var/copy = 0)
    	Transfers [amount] reagents from [src] to [target], multiplying them by [multiplier]. Returns actual amount removed from [src] (not amount transferred to [target]). If [copy] is 1, copies reagents instead.

    touch(var/atom/target)
    	When applying reagents to an atom externally, touch() is called to trigger any on-touch effects of the reagent.
    	This does not handle transferring reagents to things.
    	For example, splashing someone with water will get them wet and extinguish them if they are on fire,
    	even if they are wearing an impermeable suit that prevents the reagents from contacting the skin.
    	Basically just defers to touch_mob(target), touch_turf(target), or touch_obj(target), depending on target's type.
    	Not recommended to use this directly, since trans_to() calls it before attempting to transfer.

    touch_mob(var/mob/target)
    	Calls each reagent's touch_mob(target).

    touch_turf(var/turf/target)
    	Calls each reagent's touch_turf(target).

    touch_obj(var/obj/target)
    	Calls each reagent's touch_obj(target).

    trans_to(var/atom/target, var/amount = 1, var/multiplier = 1, var/copy = 0)
    	The general proc for applying reagents to things externally (as opposed to directly injected into the contents).
    	It first calls touch, then the appropriate trans_to_*() or splash_mob().
    	If for some reason you want touch effects to be bypassed (e.g. injecting stuff directly into a reagent container or person), call the appropriate trans_to_*() proc.

    	Calls touch() before checking the type of [target], calling splash_mob(target, amount), trans_to_turf(target, amount, multiplier, copy), or trans_to_obj(target, amount, multiplier, copy).

    trans_id_to(var/atom/target, var/id, var/amount = 1)
    	Transfers [amount] of [id] to [target]. Returns amount transferred.

    splash_mob(var/mob/target, var/amount = 1, var/clothes = 1)
    	Checks mob's clothing if [clothes] is 1 and transfers [amount] reagents to mob's skin.
    	Don't call this directly. Call apply_to() instead.

    trans_to_mob(var/mob/target, var/amount = 1, var/type = CHEM_BLOOD, var/multiplier = 1, var/copy = 0)
    	Transfers [amount] reagents to the mob's appropriate holder, depending on [type]. Ignores protection.

    trans_to_turf(var/turf/target, var/amount = 1, var/multiplier = 1, var/copy = 0)
    	Turfs don't currently have any reagents. Puts [amount] reagents into a temporary holder, calls touch_turf(target) from it, and deletes it.

    trans_to_obj(var/turf/target, var/amount = 1, var/multiplier = 1, var/copy = 0)
    	If target has reagents, transfers [amount] to it. Otherwise, same as trans_to_turf().

    atom/proc/create_reagents(var/max_vol)
    	Creates a new reagent datum.

About Reagents:

    Reagents are all the things you can mix and fille in bottles etc. This can be anything from
    rejuvs over water to... iron.

    Vars:

    name
    	Name that shows up in-game.

    id
    	ID that is used for internal tracking. MUST BE UNIQUE.

    description
    	Description that shows up in-game.

    datum/reagents/holder
    	Reference to holder.

    reagent_state
    	Could be GAS, LIQUID, or SOLID. Affects nothing. Reserved for future use.

    list/data
    	Use varies by reagent. Custom variable. For example, blood stores blood group and viruses.

    volume
    	Current volume.

    metabolism
    	How quickly reagent is processed in mob's bloodstream; by default aslo affects ingest and touch metabolism.

    ingest_met
    	How quickly reagent is processed when ingested; [metabolism] is used if zero.

    touch_met
    	Ditto when touching.

    dose
    	How much of the reagent has been processed, limited by [max_dose]. Used for reagents with varying effects (e.g. ethanol or rezadone) and overdosing.

    max_dose
    	Maximum amount of reagent that has ever been in a mob. Exists so dose won't grow infinitely when small amounts of reagent are added over time.

    overdose
    	If [dose] is bigger than [overdose], overdose() proc is called every tick.

    scannable
    	If set to 1, will show up on health analyzers by name.

    affects_dead
    	If set to 1, will affect dead players. Used by Adminordrazine.

    glass_icon_state
    	Used by drinks. icon_state of the glass when this reagent is the master reagent.

    glass_name
    	Ditto for glass name.

    glass_desc
    	Ditto for glass desciption.

    glass_center_of_mass_x
    glass_center_of_mass_y
    	Used for glass placement on tables.

    color
    	"#RRGGBB" or "#RRGGBBAA" where A is alpha channel.

    color_weight
    	How much reagent affects color of holder. Used by paint.

    Procs:

    remove_self(var/amount)
    	Removes [amount] of itself.

    touch_mob(var/mob/M)
    	Called when reagent is in another holder and not splashing the mob. Can be used with noncarbons.

    touch_obj(var/obj/O)
    	How reagent reacts with objects.

    touch_turf(var/turf/T)
    	How reagent reacts with turfs.

    on_mob_life(var/mob/living/carbon/M, var/alien, var/location)
    	Makes necessary checks and calls one of affect procs.

    affect_blood(var/mob/living/carbon/M, var/alien, var/removed)
    	How reagent affects mob when injected. [removed] is the amount of reagent that has been removed this tick. [alien] is the mob's reagent flag.

    affect_ingest(var/mob/living/carbon/M, var/alien, var/removed)
    	Ditto, ingested. Defaults to affect_blood with halved dose.

    affect_touch(var/mob/living/carbon/M, var/alien, var/removed)
    	Ditto, touching.

    overdose(var/mob/living/carbon/M, var/alien)
    	Called when dose is above overdose. Defaults to M.injure(INJURY_TOXIN, ...).

    initialize_data(var/newdata)
    	Called when reagent is created. Defaults to setting [data] to [newdata].

    mix_data(var/newdata, var/newamount)
    	Called when [newamount] of reagent with [newdata] data is added to the current reagent. Used by paint.

    get_data()
    	Returns data. Can be overriden.

About Recipes:

    Recipes are simple datums that contain a list of required reagents and a result.
    They also have a proc that is called when the recipe is matched.

    Vars:

    name
    	Name of the reaction, currently unused.

    id
    	ID of the reaction, must be unique.

    result
    	ID of the resulting reagent. Can be null.

    list/required_reagents
    	Reagents that are required for the reaction and are used up during it.

    list/catalysts
    	Ditto, but not used up.

    list/inhibitors
    	Opposite, prevent the reaction from happening.

    result_amount
    	Amount of resulting reagent.

    mix_message
    	Message that is shown to mobs when reaction happens.

    Procs:

    can_happen(var/datum/reagents/holder)
    	Customizable. If it returns 0, reaction will not happen. Defaults to always returning 1. Used by slime core reactions.

    on_reaction(var/datum/reagents/holder, var/created_volume)
    	Called when reaction happens. Used by explosives.

    send_data(var/datum/reagents/T)
    	Sets resulting reagent's data. Used by blood paint.

About the Tools:

    By default, all atom have a reagents var - but its empty. if you want to use an object for the chem.
    system you'll need to add something like this in its new proc:

    atom/proc/create_reagents(var/max_volume)

    Other important stuff:

    amount_per_transfer_from_this var
    	This var is mostly used by beakers and bottles.
    	It simply tells us how much to transfer when
    	'pouring' our reagents into something else.

    atom/proc/is_open_container()
    	Checks atom/var/flags & OPENCONTAINER.
    	If this returns 1 , you can use syringes, beakers etc
    	to manipulate the contents of this object.
    	If it's 0, you'll need to write your own custom reagent
    	transfer code since you will not be able to use the standard
    	tools to manipulate it.

\*/

Contaminants
------------
Impurities are reagents (`/datum/reagent/contaminant`, `code/content/reagents/reagents/content/contaminants.dm`): 2u of "Heavy metals" is 2u in the
beaker, with its own volume. It is added, transferred, mixed, splashed, ingested and metabolised like any reagent and does its own harm from its own
metabolism, by role: toxic (organ or general toxin damage per unit), reactive (a chance of a burn per cycle), biological (toxin and a fever), inert
(nothing). No ordinary recipe takes or makes one, so a contaminant rides along and dilutes (only neutralisation reacts with a residue, see
"Purification"). Nothing is attached to another reagent; there is no per-reagent fraction and no potency scaling.

Purity belongs to the mixture: 1 minus the contaminant volume over the holder's total volume (`purity()`, computed, never stored), and its grade
(`grade()`: Crude under 60%, Standard 60-90%, Pharma 90-99%, Reagent 99% and over). The grade is a readout (scanners, the book): no recipe asks for one
(`needs_grade` is gone), purity is only the natural fallout of how a batch was made.

A source (a chemical dispenser cartridge) rolls a profile per round (`chem_source_profile(reagent, source_key, grade)`, deterministic for the round
seed): the units of each contaminant that come with each unit of stock. `add_sourced_reagent()` adds stock and contaminants together; the cartridge fills
with it, recharges with it (`add_stock()`, used by the dispenser and the synthesizer, so a recharge never raises purity) and dispenses with it
(`dispense_to()`: the stock asked for and the contaminants that sit with it). Scanners, the chem master, the analyzer and the health scanner list each
contaminant as a line of its own and say the mixture's grade; the medical book's Purity tab is read from the contaminant types. `GLOB.chem_trace` logs
source rolls, stock added, dispenses, refused graded reactions and effects on a patient.

Purification
------------
How a mixture is made clean again (or dirty), all of it logged under `GLOB.chem_trace`:

* **Temperature.** A holder has the temperature of what holds it (`get_temperature()`; a beaker's heat body, else the room). Every instant-regime chemistry
  recipe has a working range and a narrower ideal band, filed by class in `code/content/reagents/reactions/reaction_temperatures.dm` (ambient: drinks, food,
  paint, virology; gentle: the default, room temperature is ideal; warm; hot; violent). Inside the ideal band the product is clean; inside the range but off the
  band the recipe still goes but leaves contaminants (too cold: organic residue; too hot: reactive impurity and a loss of product), scaled by the distance
  (0 at the band's edge, 1 at the range's edge); outside the range nothing reacts. Only a holder in a loose reagent container is gated: a mob's blood, a
  machine's buffer, a grenade or a slime extract are not. `reaction_temperature_state()` / `apply_temperature_effects()` in
  `code/domains/world_model/reagents/chem_temperature.dm`.
* **Catalyst.** A catalyst belongs to a process (see "Block structures and processes"). A sheet of a material with catalytic activity dropped into a glass
  container (click it on the container; "Take out the catalyst" from the menu) is the solid catalyst of the routes that run on one; it no longer widens the band of
  every recipe.
* **Hot plate** (`/obj/machinery/chem_hot_plate`): stand a glass container on it, set the dial in Celsius (radial menu), switch it on. Each second it feeds the
  container's heat body up to `HOT_PLATE_POWER` joules, never past the dial, draws its active power while on, lets the contents react and boils them.
* **Boiling** (`code/domains/world_model/reagents/boiling.dm`, points in `code/content/reagents/reagents/boiling_points.dm`): every reagent has `boiling_point_k()`.
  `boil_step(seconds)` removes what is above its point, gradually, taking latent heat out of the container; it returns the vapour. Nothing boils by itself: the
  hot plate and the bunsen burner ask for it. Vapour is deleted unless a **condenser** (`/obj/machinery/chem_condenser`) on or next to the hot plate collects it into
  the container under its spout (`condense()`): distillation, so a contaminant that never boils stays in the flask.
* **Funnel and filters** (`code/content/reagents/purification/`): a funnel fits on a glass container, a filter goes in the funnel, and every pour into that
  container (`trans_to_holder()`) goes through the filter first (`trans_through_filter()`). A filter takes by TAG (a contaminant's tags come from its block
  structure): paper the solids, charcoal the organics, a sorbent filter (an ion-exchange filter: a paper filter lined with a material sheet) the ionic, metallic,
  sulfurous and nonpolar by the material's sorption, oxidisers and sulfur by its catalytic activity, biological by its antimicrobial activity. Every contaminant has a
  floor (`filter_floor`, a share of the mixture): no filter takes it below that, so a trace of dioxin stays. A filter has a capacity that
  every unit caught and every unit of product kept back uses up, it works less as it fills and a full one passes everything.
* **Neutralisation** is the `neutralise` process (generated: every acid with every base): an acid and a base make the salt (a chemical when one has that
  structure, else salts) and water. A rule's reagent terms after the first in `makes` are by-products made beside the product.
* **No free purification.** A contaminant cannot be picked out of a mixture: `trans_id_to()` and `trans_type_to()` of a stock reagent carry its share of the
  contaminants (`draw_portion()`) and refuse a contaminant, `isolate_reagent()` keeps the contaminants, and the chem master and the dispenser refuse to move or
  discard one on its own.


Block structures and processes
------------------------------
`code/domains/world_model/reagents/blocks/` (the machinery) and `code/content/reagents/blocks/` (the declarations).

* **Structures.** A chemistry reagent is built of blocks, declared by reagent id in `GLOB.chem_declared_structures` (`structures.dm`; by id, because a
  subtype inherits a var and every vodka is not an ethanol): `cores` (short chain, long chain, ring, double ring, sugar ring, amino, steroid, nitrogen
  ring, siloxane, phoron lattice), `groups` hung on them (hydroxyl, carbonyl, carboxyl, amine, nitro, halide, thiol, phosphate, metal centre; a group named twice
  is two), `links` (ester, amide), or, for an inorganic, a `cation` and an `anion`. The formula, the class ("alcohol", "ester", "acid", "salt"...) and the tags
  (organic, polar, nonpolar, ionic, acidic, basic, metallic, sulfurous, halogenated, nitrogenous, oxidiser, biological) are derived from the structure
  (`chem_structure_of(id)`, `.formula()`, `.class_name()`, `.tags`). Contaminants have structures too: their tags are what filters take them by. Cores
  come from feedstock; nothing builds a core from elements.
* **Processes** (`processes.dm`; fifteen, `polymerise` reserved for the materials lane): oxidise, reduce, halogenate, nitrate, substitute (a halide for an amine
  or a thiol), phosphorylate, decarboxylate, condense, hydrolyse, ferment, crack, neutralise, displace (a metal for a metal, or a metal bound to a carboxyl or
  phosphate), electrolyse (a conductive sheet in a container on a plate that is on), polymerise. A process says which structures it acts on and what they become
  (`variants()`), what it adds (an oxidiser, a nitrating acid, water), the catalyst kinds it runs on, its temperature band, and the trace-potent contaminants it leaves
  (`fallout()`). It never names a chemical it makes.
* **Routes.** At boot every process is run over every structure (`chem_routes_build()`): a variant whose end structure is a chemical that exists is a route that
  makes it, one whose end structure nobody has is a route that makes organic residue (salts, for neutralisation). Byproducts are balanced, one unit being one
  part. Each route is written once per catalyst kind and compiled into the transformation table (rule type `/transformation/process_route`, `route_id` on the
  rule; a declared recipe wins a shared reactant). `chem_routes_dump()` lists them all and `dq_chem_routes_pinned` pins the list
  (`code/tests/unit_tests/snapshots/xform/chem_routes.txt`; `--bless` after reading what changed: a cheap route to something gated is the thing to catch).
  A route only runs in a loose container, and outside the temperature band of its process it does not run.
* **Catalyst kinds.** None (heat and the added reagent only, 80% selective), dissolved acid or base (sulphuric acid, lye: lowers the band, spent into acid or base
  residue), solid metal or solid acid (a sheet in the container: its catalytic activity lowers the band and raises the selectivity; porous material is a solid
  acid; sulfur and heavy metals poison it), enzyme (gentle heat only, spent into endotoxin, killed by heavy metals). The share of a product a catalyst was not
  selective for is organic residue: that and the fallout are the natural purity.
* **Trace-potent contaminants**, one clear symptom each, strong at a trace, made by processes and carried by no source: hydrochloric acid (burns; freed by
  halogenation), dioxin (skin lesions; hot halogenation of a ring with a hydroxyl), nitrosamine (slow genetic damage; nitrating an amine), peroxide (detonates when
  its container is heated: `detonate_peroxide()` in `boil_step()`; a hot uncatalysed oxidation), methanol (blindness; fermentation), plasticiser (slows the
  metabolism; hot condensation of a ring), tar (strains the lungs; cracking, decarboxylating), plus heavy metals (liver) and endotoxin (toxin and fever), now
  stronger.
* **Interference.** Acid and base cancel into salts; sulfur and heavy metals poison a metal catalyst, heavy metals an enzyme; water blocks a condensation and
  drives hydrolysis, which is its reverse; an oxidiser left over oxidises the next product (the routes chain); peroxide detonates on heating.
* **The book** shows each reagent's block diagram (formula, class, tags, blocks), the processes that act on it and what they give, and for a generated recipe
  its process, catalyst and clean temperature. The burn medicines are the first family converted: silicate and an acid make kelotane (a siloxane with a
  hydroxyl) and leave salts; kelotane and phosphorus, hot, make dermaline (a phosphate on it) and water.
