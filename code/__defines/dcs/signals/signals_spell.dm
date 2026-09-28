// Signals sent to or by spells

// Generic spell signals


	/// Return to prevent the spell cast from continuing.
	/// Return from before cast signals to prevent the spell from giving off sound or invocation.
	/// Return from before cast signals to prevent the spell from going on cooldown before aftercast.


// Sent from /datum/action/cooldown/spell/after_cast() to the caster: (datum/action/cooldown/spell/spell, atom/cast_on)

// Spell type signals

// Pointed projectiles
// Sent from /datum/action/cooldown/spell/pointed/projectile/fire_projectile() to the caster: (datum/action/cooldown/spell/spell, atom/cast_on, obj/projectile/to_fire)

// AOE spells

// Cone spells

// Touch spells

// Jaunt Spells


// Signals for specific spells

// Lichdom


// Instant Summons


// Charge
