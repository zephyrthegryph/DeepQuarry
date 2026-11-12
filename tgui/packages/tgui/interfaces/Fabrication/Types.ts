import type { BooleanLike } from 'tgui-core/react';

/**
 * A map of keyed materials to a quantity.
 */
export type MaterialMap = Record<string, number>;

/**
 * A single, uniquely identifiable material.
 */
export type Material = {
  /**
   * The human-readable name of the material.
   */
  name: string;

  /**
   * An internal reference to the material that the server can use to uniquely
   * identify the material.
   */
  ref: number;

  /**
   * The amount of material; 100 units is one sheet.
   */
  amount: number;

  /**
   * The color of the material.
   */
  color: string;
  materialClass?: string;
};

/**
 * A single design that the fabricator can print.
 */
export type Design = {
  /**
   * The name of the design.
   */
  name: string;

  /**
   * A human-readable description of the design.
   */
  desc: string;

  /**
   * The individual material cost to print the design, adjusted for the
   * fabricator's part efficiency.
   */
  cost: MaterialMap;

  /**
   * A reference to the design's design datum.
   */
  id: string;

  /**
   * The categories the design should be present in. Subcategories are
   * slash-delimited, and categories always start with a slash.
   */
  categories: string[];

  /**
   * The icon used to represent this design, generated in
   * /datum/asset/spritesheet_batched/research_designs. **The image within may not be
   * 32x32.**
   */
  icon: string;

  /**
   * If set, this design lets the user pick which loaded material to build it
   * from; `cost` covers only the fixed materials, and `selectableAmount` units of
   * the chosen material are consumed on top.
   */
  materialConfigurable?: BooleanLike;
  /** Product geometry used to choose relevant material diagnostics. */
  materialProfile?: string | null;
  /** Functional construction slots stored on the finished object. */
  materialSlots?: MaterialSlot[];
};

export type MaterialSlot = {
  role: string;
  label: string;
  amount: number;
  defaultMaterial?: string | null;
  optional: BooleanLike;
  description?: string | null;
};

/**
 * A loaded material offered in a material-selectable design's picker.
 */
export type MaterialChoice = {
  /** Registry id passed back to the server on build. */
  id: string;
  /** Human-readable label shown in the dropdown. */
  label: string;
  /** How many whole sheets are loaded. */
  sheets: number;
  color: string;
  layers: { role: string; name: string; share: number }[];
  responses: string[];
  hardness: number;
  density: number;
  integrity: number;
  elasticity: number;
  brittleness: number;
  toughness: number;
  conductivity: number;
  heatResistance: number;
  thermalInsulation: number;
  corrosionResistance: number;
  pressureLimit: number;
  resistivity?: number;
  criticalTemperature?: number;
  criticalCurrentDensity?: number;
  specificHeat?: number;
  phaseCapacity?: number;
  phaseTemperature?: number;
  dielectricStrength?: number;
  meltingPoint?: number;
};
