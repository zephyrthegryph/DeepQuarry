# Body and afflictions

This module owns body plans, organs, injury and affliction state, symptoms, and
body factor calculations. Medical treatments in `code/modules/medical` consume
these models; body types define the contracts they use.

The DM health analyzer treats this directory as a module boundary. Collection
contracts on `/datum/affliction` describe treatment rates, organ targets, and
symptom weights shared with medical code.
