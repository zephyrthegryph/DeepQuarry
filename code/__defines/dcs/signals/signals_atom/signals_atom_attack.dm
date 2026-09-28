// Atom attack signals. Format:
// When the signal is called: (signal arguments)
// All signals send the source datum of the signal as the first argument

///from base of atom/attackby(): (/obj/item, /mob/living, list/modifiers)
#define COMSIG_ATOM_ATTACKBY "atom_attackby"
///Return this in response if you don't want afterattack to be called
//from base of atom/attack_basic_mob(): (/mob/user)
/// from base of [/atom/proc/extinguish]
#define COMSIG_ATOM_EXTINGUISH "atom_extinguish"
///from base of [/atom/proc/take_damage]: (damage_amount, damage_type, damage_flag, sound_effect, attack_dir, aurmor_penetration)
#define COMSIG_ATOM_TAKE_DAMAGE "atom_take_damage"
	/// Return bitflags for the above signal which prevents the atom taking any damage.
/* Attack signals. They should share the returned flags, to standardize the attack chain. */
/// tool_act -> pre_attack -> target.attackby (item.attack) -> afterattack
	///Ends the attack chain. If sent early might cause posterior attacks not to happen.
	///Skips the specific attack step, continuing for the next one to happen.
///from base of atom/attack_hand(): (mob/user, list/modifiers)
#define COMSIG_ATOM_ATTACK_HAND "atom_attack_hand"

	///The damage type of the weapon projectile is non-lethal stamina
	///the attacker is shoving the source
	/// The attack is a damaging-type attack


