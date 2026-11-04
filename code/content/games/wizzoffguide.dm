/obj/item/book/manual/wizzoffguide
	name = "WizOff Guide"
	icon = 'icons/obj/playing_cards.dmi'
	icon_state ="wizoff_guide"
	item_state = "book16"
	author = "Donk Co."
	title = "WizOff Guide"
	dat = {"

		<html>
			<head>
			<style>
			h1 {font-size: 18px; margin: 15px 0px 5px;}
			h2 {font-size: 15px; margin: 15px 0px 5px;}
			h3 {font-size: 13px; margin: 5px 0px 5px;}
			li {margin: 2px 0px 2px 15px;}
			ul {margin: 5px; padding: 0px;}
			ol {margin: 5px; padding: 0px 15px;}
			body {font-size: 13px; font-family: Verdana;}
			</style>
			</head>
			<body>
			<h1><u>Wiz-Off Player Guide</u></h1>
			<h2>How to play Wiz-Off!</h2>
			<h3>The wizard themed card game</h3>
			<p>Each player draws 5 cards. There are five rounds. Each round,<br>
			a player selects a card to play, and the winner is selected<br>
			based on the following rules:</p>
			<ol>
				<li>Offensive (O) beats Utility (U)!</li>
				<li>Defensive (D) beats Offensive (O)!</li>
				<li>Utility (U) beats Defensive (D)!</li>
				<li>If both players play the same type of spell, <br>
				the higher number wins!</li>
			</ol>
			<p>The player who wins the most of the 5 rounds wins the game!<br>
			Now get ready to battle for the fate of the universe: Wiz-Off!</p>
			</body>
		</html>

		"}

CAPABILITIES(/obj/item/book/manual/wizzoffguide)
	configure(item_sounds(drop = SFX_ITEMS_DROP_PAPER, pickup = SFX_ITEMS_PICKUP_PAPER))
