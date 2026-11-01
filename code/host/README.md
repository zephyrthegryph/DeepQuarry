# code/base

The neutral layer below the engine: helpers the engine calls (text, lists, sorts, logging entry points, pathfinding, time), the act context types and adjacency. `engine_layering` holds it to the engine's boundary: nothing here may name library, content, domains or old-tree code. What needs content is a virtual proc declared here and implemented in `code/content/`.

This README defines the module boundary for source health analysis.
