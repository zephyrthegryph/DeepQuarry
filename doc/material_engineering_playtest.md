# Material engineering playtest

## Working with an assembly

Use the normal fabrication recipe and its component choices. Stock defaults remain
available; custom choices replace individual functional parts, not the item's identity.
Right-click the finished assembly with a multitool to see temperature, installed
parts, condition, measured power, and any limiting component. Keep the tool in hand
and remain beside the assembly to record continuous operation.

Right-click with a screwdriver to open the service cover. Apply an ordinary
material stack and select the part to replace. The required sheets are consumed.
Replacing a liner restores the liner; replacing the pressure shell clears its
permanent fatigue. Recalculating an assembly's properties does not recharge its
cell, restore its structural health, or replenish a spent thermal buffer.

## Three useful experiments

### Cold electrical assembly

Fit a low-resistance/superconducting current collector, a phase-change thermal
buffer, and thermal insulation to a normal power cell. Cool the actual assembly
below the collector's critical temperature before applying load. Fresh cryogenic
stock at room temperature is not a free source of cooling.

The buffer absorbs a finite quantity of heat at its phase temperature. Insulation
slows incoming heat but also makes recooling slower. Exceeding critical current or
exhausting the cold buffer restores electrical resistance. The cell then loses
more stored energy to heat for the same delivered output; it never creates extra
charge simply because the conductor is superconducting.

### Pump and containment

Connect a pump between a supply and a receiver. The conductor and moving parts
affect electrical efficiency and available pumping capacity. Compression deposits
useful work into the destination gas and motor losses into the assembly. Pressure
strength depends on the shell, its temperature, and permanent fatigue. Chemical
attack depends on the exposed liner and exposure duration.

Switching a pump off does not protect it from its internal gas or the surrounding
atmosphere. Dedicated heat-exchange pipes retain their existing exchange behavior.

### Sustained beam

Build and connect a normal emitter with a safe target. Its diagnostics allow pulse
energy and cadence changes. The emitter accumulates supplied electrical energy,
then spends the reservoir on a beam and waste heat. Faster requested firing cannot
produce energy that the supply has not delivered. Material limits and temperature
can reduce charging power, and a hot assembly needs real cooling.

## Recording a qualification

The contract specifies an operating envelope. Accept it before beginning the
observation. Record a complete 45-second run with the multitool, then apply the
tool to a powered photocopier with toner. Fax the ordinary paper report to
NanoTrasen Engineering Assurance.

Measurements include actual delivered output, efficiency, peak temperature, and
gas receiver pressure where relevant. Copied papers retain the same evidence
identity and cannot complete another qualification. Observations cannot predate
acceptance. Changing parts or settings resets the current observation.

## Simulation boundaries

This is a gameplay-scale model, not a real electrical circuit simulator. The
station distribution model uses a nominal voltage and a reduced resistor graph;
it distinguishes branches and parallel loops rather than charging every cable for
the whole network's demand. Material heat capacity and geometry use representative
assembly values. Precise throughput and thermal balancing still need multiplayer
playtesting, especially unusually large custom power networks.
