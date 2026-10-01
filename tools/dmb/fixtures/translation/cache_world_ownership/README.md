# World method-result ownership

Seven authored bodies compare completely with native output in both debug modes:
name/contents reads, an intervening global helper, writes, compound assignment,
another selected owner, and a branch. Only a previously captured World method
receiver enables direct field reuse. Other-owner and branch-target controls
require fresh World selection. Ordinary world-field lowering remains unchanged.
