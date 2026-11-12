import type { PublicLibraryWikiData } from '../generated/PublicLibraryWiki';
import type {
  WikiBotany,
  WikiCatalog,
  WikiFood,
  WikiGene,
  WikiMaterial,
  WikiOre,
  WikiParticle,
  WikiReagent,
  WikiVirus,
} from '../generated/_schemas';

// Every shape here is generated from its DM schema (UI_SCHEMA wiki_* in code/content/library/wikicomp.dm).
export type Data = PublicLibraryWikiData;

export type PageData = Pick<
  Data,
  | 'material_data'
  | 'particle_data'
  | 'catalog_data'
  | 'ore_data'
  | 'botany_data'
  | 'chemistry_data'
  | 'drink_data'
  | 'food_data'
  | 'virus_data'
  | 'gene_data'
>;

export type FoodData = WikiFood;
export type DrinkData = WikiFood;
export type RedipeData = NonNullable<WikiFood['recipe']>;
export type ReagentData = WikiReagent;
export type BotanyData = WikiBotany;
export type OreData = WikiOre;
export type VirusData = WikiVirus;
export type GeneData = WikiGene;
export type ParticleData = WikiParticle;
export type MaterialData = WikiMaterial;
export type CatalogData = WikiCatalog;

export type ReactionData = Pick<
  WikiFood,
  | 'grinding'
  | 'instant_reactions'
  | 'distilled_reactions'
  | 'fluid'
  | 'produces'
>;
export type GroundMaterial = ReactionData['grinding'];
export type InstantReactions = ReactionData['instant_reactions'];
export type DistilledReactions = ReactionData['distilled_reactions'];
export type DistillComponent = NonNullable<DistilledReactions>[number];
