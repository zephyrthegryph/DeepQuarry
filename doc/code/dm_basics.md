# DM Basics

This codebase is written in DM, a C-like interpreted language with a lot of weird quirks and systems.
This document tries to describe them all in an understandable way for a non-DM user.
Some basic coding knowledge is expected. https://www.byond.com/docs/ref/#/DM has the DM docs, with additional info.

# Types

Everything in the code has a "type", which defines what that thing is. For instance, a machine has the type /obj/machine/MACHINE_NAME.
Types are organized into a hierarchy, where things further down inherit properties from the things above them.
Taking that earlier example, it means /obj is a type, /obj/machine is a type, and /obj/machine/MACHINE_NAME is a type.

Types have a set of variables, and a static initializer. For example:

```
/obj/machinery/power/apc
	name = "area power controller"

	var/area/area
```

Static initializers run once for the entire type before the game has even started, and can
either override a variable's value (as it does for name) or declare a new field (as it does for area).

A single type can have any number of static initializers, meaning multiple different files can add new variables to a type,
but this is generally not a good idea.

When a type is created in game, it will only use memory for fields with values other than the default, which is important to keep in mind for memory reasons.
However, lists break that rule, they always exist on every single instance, so lists can take up tons of memory. Lazylists exist to fix this issue, by using
null instead of an empty list.

# Special Types

DM has special behavior for something depending on the start of the type, look at the DM reference to see all of them.
The most important ones are "datums", data that doesn't exist in the world, and "atoms", things that do exist in the world.