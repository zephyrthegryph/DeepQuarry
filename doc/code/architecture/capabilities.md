# Capabilities

Capabilities are a set of generic components that are combined together to build up what a thing does.
They are built to be one framework that unites everything across the codebase, whether it's a machine, chemical, mob, etc.

# Definition

Capabilities are defined using the CAPABILITIES macro, they inherit from the parent type, and take any number of arguments.

```
CAPABILITIES(/atom/example, first_capability(), second_capability())
```

These build on capability datums:

```
// The capability stating that a machine uses power
/datum/capability/powered
	key = CAP_POWERED
	var/channel = POWER_CHANNEL_EQUIPMENT
	var/idle_draw = 0      // watts while idle
	var/active_draw = 0    // watts while working

// This proc provides helpful defaults for users
/proc/powered(channel = POWER_CHANNEL_EQUIPMENT, idle = 0, active = 0)
	return capability(/datum/capability/powered, settings = list("channel" = channel, "idle_draw" = idle, "active_draw" = active))
```

Each capability has a unique key.

# Composition

Capabilities are compositional, meaning you can build one capability on top of others.

```
// Both reuse the same power code defined by powered, with different idle and active power draws
CAPABILITIES(/obj/machine/my_machine, powered(active = 150))
CAPABILITIES(/obj/machine/my_other_machine, powered(idle = 20, active = 300))
```

# Configuration

Despite capabilities being inherited, a child can configure the parent's capabilities to add in their own behavior or change values.
This can be done in three ways:

```
// Change the active power usage to 1500
CAPABILITIES(/obj/machine/my_machine/super_machine, configure(CAP_POWERED, active = 1500))
// Removes the power usage entirely
CAPABILITIES(/obj/machine/my_machine/dummy, without(CAP_POWERED))
// Targets a tag instead of a key, so each UI action now requires being unlocked 
CAPABILITIES(/obj/machine/my_machine/lockable, extend(TAG_UI, needs(req_clear(LOCKED))))
```

# Operations

Operations are the things that can actually be done with the atom. 
Pressing a button in a UI, clicking on something, and using an item are all operations.

Operations are built from their own subset of components, like how capabilities are:

## Input

Input is how the operation is done. For instance, requiring a tool:

```
op("pry_open", "Pry open", tool(TOOL_CROWBAR))
```

## Selection

Selection defines when an operation should be done and which operation takes precendence, like attacking a machine vs using a tool on it:

```
op("pry_open", "Pry open", tool(TOOL_CROWBAR), hostile(), priority(OP_PRIORITY_PART))
```