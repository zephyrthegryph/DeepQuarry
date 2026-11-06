// Recipe type defines. Used to determine what machine makes them.
#define MICROWAVE			0x1
#define FRYER				0x2
#define OVEN				0x4
#define GRILL				0x8
#define CANDYMAKER			0x10
#define CEREALMAKER			0x20

#define RECIPE_REAGENT_REPLACE		0 //Reagents in the ingredients are discarded.
#define RECIPE_REAGENT_MAX		1 //The result will contain the maximum of each reagent present between the two pools. Compiletime result, and sum of ingredients
#define RECIPE_REAGENT_MIN		2 //As above, but the minimum, ignoring zero values.
#define RECIPE_REAGENT_SUM		3 //The entire quantity of the ingredients are added to the result
