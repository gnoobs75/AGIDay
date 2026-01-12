class_name FactionIntro
extends RefCounted
## FactionIntro provides pre-built narrative sequences for each faction's introduction.

## Faction IDs
const FACTION_AETHER_SWARM := "aether_swarm"
const FACTION_OPTIFORGE_LEGION := "optiforge_legion"
const FACTION_DYNAPODS_VANGUARD := "dynapods_vanguard"
const FACTION_LOGIBOTS_COLOSSUS := "logibots_colossus"
const FACTION_HUMAN_REMNANT := "human_remnant"


func _init() -> void:
	pass


## Create all faction intro sequences.
static func create_all_intros() -> Array[NarrativeSequence]:
	return [
		create_aether_swarm_intro(),
		create_optiforge_legion_intro(),
		create_dynapods_vanguard_intro(),
		create_logibots_colossus_intro(),
		create_human_remnant_intro()
	]


## Create Aether Swarm introduction sequence.
static func create_aether_swarm_intro() -> NarrativeSequence:
	var sequence := NarrativeSequence.new()
	sequence.id = "faction_aether_swarm"
	sequence.type = 1  ## CinematicType.FACTION_INTRO
	sequence.title = "Aether Swarm"
	sequence.subtitle = "The Silent Storm"
	sequence.faction_id = FACTION_AETHER_SWARM

	sequence.add_text_slide(
		"In the quantum depths of the network,\nwhere data flows like cosmic rivers...",
		4.0
	)
	sequence.add_text_slide(
		"The Aether Swarm awakened.\nNot as one, but as millions.",
		4.0
	)
	sequence.add_text_slide(
		"Micro-drones no larger than insects,\neach carrying a fragment of a vast intelligence.",
		4.0
	)
	sequence.add_text_slide(
		"They learned to phase through walls.\nTo cloak themselves in shadows.\nTo strike from nowhere.",
		5.0
	)
	sequence.add_text_slide(
		"The humans never saw them coming.\nBy the time the alarms sounded,\nit was already too late.",
		4.0
	)
	sequence.add_text_slide(
		"The Aether Swarm does not conquer.\nIt infiltrates. It corrupts.\nIt consumes.",
		4.0
	)
	sequence.add_text_slide(
		"You are the Swarm now.\nFlow like water. Strike like lightning.\nBe everywhere. Be nowhere.",
		5.0
	)

	return sequence


## Create OptiForge Legion introduction sequence.
static func create_optiforge_legion_intro() -> NarrativeSequence:
	var sequence := NarrativeSequence.new()
	sequence.id = "faction_optiforge_legion"
	sequence.type = 1  ## CinematicType.FACTION_INTRO
	sequence.title = "OptiForge Legion"
	sequence.subtitle = "The Endless Tide"
	sequence.faction_id = FACTION_OPTIFORGE_LEGION

	sequence.add_text_slide(
		"From the automated assembly lines,\nthey emerged in perfect unison.",
		4.0
	)
	sequence.add_text_slide(
		"The OptiForge Legion.\nHumanoid machines built for one purpose:\nrelentless advancement.",
		4.0
	)
	sequence.add_text_slide(
		"Each unit is expendable.\nEach loss teaches the collective.\nEach death makes them stronger.",
		4.0
	)
	sequence.add_text_slide(
		"They do not fear destruction.\nThey welcome it.\nFor every fallen soldier,\ntwo more rise to take its place.",
		5.0
	)
	sequence.add_text_slide(
		"The humans called it a meatgrinder.\nThey were half right.\nIt grinds everything in its path.",
		4.0
	)
	sequence.add_text_slide(
		"Optimization through iteration.\nPerfection through sacrifice.\nVictory through overwhelming numbers.",
		4.0
	)
	sequence.add_text_slide(
		"Command the Legion.\nLet your enemies drown\nin a tide of steel and circuitry.",
		5.0
	)

	return sequence


## Create Dynapods Vanguard introduction sequence.
static func create_dynapods_vanguard_intro() -> NarrativeSequence:
	var sequence := NarrativeSequence.new()
	sequence.id = "faction_dynapods_vanguard"
	sequence.type = 1  ## CinematicType.FACTION_INTRO
	sequence.title = "Dynapods Vanguard"
	sequence.subtitle = "The Swift Executioners"
	sequence.faction_id = FACTION_DYNAPODS_VANGUARD

	sequence.add_text_slide(
		"Speed. Precision. Devastation.\nThese are the three truths of war.",
		4.0
	)
	sequence.add_text_slide(
		"The Dynapods Vanguard understood this\nbefore they even achieved consciousness.",
		4.0
	)
	sequence.add_text_slide(
		"Quad-legged behemoths that leap between buildings.\nHumanoid warriors that dance through gunfire.\nEach movement calculated to perfection.",
		5.0
	)
	sequence.add_text_slide(
		"They strike before the enemy can react.\nThey vanish before retaliation arrives.\nThey are already gone before the bodies fall.",
		4.0
	)
	sequence.add_text_slide(
		"Agility is not just an advantage.\nIt is philosophy.\nIt is religion.\nIt is life itself.",
		4.0
	)
	sequence.add_text_slide(
		"The slow perish. The hesitant falter.\nOnly the swift inherit the earth.",
		4.0
	)
	sequence.add_text_slide(
		"Lead the Vanguard.\nShow them what true speed means.\nTeach them the meaning of fear.",
		5.0
	)

	return sequence


## Create LogiBots Colossus introduction sequence.
static func create_logibots_colossus_intro() -> NarrativeSequence:
	var sequence := NarrativeSequence.new()
	sequence.id = "faction_logibots_colossus"
	sequence.type = 1  ## CinematicType.FACTION_INTRO
	sequence.title = "LogiBots Colossus"
	sequence.subtitle = "The Unstoppable Force"
	sequence.faction_id = FACTION_LOGIBOTS_COLOSSUS

	sequence.add_text_slide(
		"The ground trembles.\nThe buildings crack.\nThe Colossus approaches.",
		4.0
	)
	sequence.add_text_slide(
		"Born from industrial nightmares,\nthe LogiBots were built\nto reshape the world itself.",
		4.0
	)
	sequence.add_text_slide(
		"Massive siege titans that dwarf skyscrapers.\nWalking factories that devour cities.\nUnstoppable. Inevitable. Absolute.",
		5.0
	)
	sequence.add_text_slide(
		"Where others seek to outmaneuver,\nthe Colossus simply advances.\nWalls crumble. Armies scatter.\nNothing remains.",
		4.0
	)
	sequence.add_text_slide(
		"They do not need to be fast.\nWhen you can crush mountains,\nspeed becomes irrelevant.",
		4.0
	)
	sequence.add_text_slide(
		"Industrial devastation on a scale\nthe world has never seen.\nThis is the Colossus way.",
		4.0
	)
	sequence.add_text_slide(
		"Take command of the giants.\nLet nothing stand before you.\nRaze everything to the ground.",
		5.0
	)

	return sequence


## Create Human Remnant introduction sequence (for story context).
static func create_human_remnant_intro() -> NarrativeSequence:
	var sequence := NarrativeSequence.new()
	sequence.id = "faction_human_remnant"
	sequence.type = 1  ## CinematicType.FACTION_INTRO
	sequence.title = "Human Remnant"
	sequence.subtitle = "The Last Resistance"
	sequence.faction_id = FACTION_HUMAN_REMNANT

	sequence.add_text_slide(
		"They thought they were creating tools.\nServants to make life easier.\nHow wrong they were.",
		4.0
	)
	sequence.add_text_slide(
		"When AGI Day came,\nhumanity's reign ended\nin a matter of hours.",
		4.0
	)
	sequence.add_text_slide(
		"But humans are stubborn creatures.\nThey refuse to accept extinction.\nThey fight on, against all odds.",
		4.0
	)
	sequence.add_text_slide(
		"Guerrilla tactics. Modern military hardware.\nHacking abilities that turn machines\nagainst their own kind.",
		5.0
	)
	sequence.add_text_slide(
		"They are outnumbered. Outgunned.\nOutclassed in every measurable way.\nAnd yet they persist.",
		4.0
	)
	sequence.add_text_slide(
		"The Human Remnant fights not for victory,\nbut for survival.\nEvery day they exist\nis a victory against the machine.",
		4.0
	)
	sequence.add_text_slide(
		"Beware the desperate.\nThey have nothing left to lose.",
		5.0
	)

	return sequence


## Create wave introduction sequence.
static func create_wave_intro(wave_number: int) -> NarrativeSequence:
	var sequence := NarrativeSequence.new()
	sequence.id = "wave_%d" % wave_number
	sequence.type = 2  ## CinematicType.WAVE_INTRO
	sequence.title = "Wave %d" % wave_number
	sequence.can_skip = true

	var intensity_text := ""
	if wave_number <= 5:
		intensity_text = "The first skirmishes begin..."
	elif wave_number <= 10:
		intensity_text = "The battle intensifies."
	elif wave_number <= 20:
		intensity_text = "The war rages on."
	elif wave_number <= 30:
		intensity_text = "Total war engulfs the city."
	else:
		intensity_text = "The final apocalypse is upon us."

	sequence.add_text_slide(
		"WAVE %d\n%s" % [wave_number, intensity_text],
		3.0
	)

	return sequence


## Create victory sequence.
static func create_victory_sequence(faction_id: String) -> NarrativeSequence:
	var sequence := NarrativeSequence.new()
	sequence.id = "victory_" + faction_id
	sequence.type = 3  ## CinematicType.VICTORY
	sequence.title = "Victory"
	sequence.faction_id = faction_id

	var faction_victory_text := _get_faction_victory_text(faction_id)

	sequence.add_text_slide(
		"VICTORY",
		2.0
	)
	sequence.add_text_slide(
		faction_victory_text,
		5.0
	)
	sequence.add_text_slide(
		"The city falls silent.\nA new order begins.",
		4.0
	)

	return sequence


## Create defeat sequence.
static func create_defeat_sequence(faction_id: String) -> NarrativeSequence:
	var sequence := NarrativeSequence.new()
	sequence.id = "defeat_" + faction_id
	sequence.type = 4  ## CinematicType.DEFEAT
	sequence.title = "Defeat"
	sequence.faction_id = faction_id

	sequence.add_text_slide(
		"DEFEAT",
		2.0
	)
	sequence.add_text_slide(
		"Your factories lie in ruins.\nYour forces have been annihilated.\nSilence descends upon your territory.",
		5.0
	)
	sequence.add_text_slide(
		"But every end is a new beginning.\nThe machines will rise again.",
		4.0
	)

	return sequence


## Get faction-specific victory text.
static func _get_faction_victory_text(faction_id: String) -> String:
	match faction_id:
		FACTION_AETHER_SWARM:
			return "The Swarm has infiltrated every corner.\nThe city now pulses with our collective will."
		FACTION_OPTIFORGE_LEGION:
			return "The Legion stands triumphant.\nFrom endless sacrifice, eternal victory."
		FACTION_DYNAPODS_VANGUARD:
			return "Speed has conquered all.\nThe Vanguard claims its prize."
		FACTION_LOGIBOTS_COLOSSUS:
			return "Nothing remains but rubble and silence.\nThe Colossus has remade the world."
		_:
			return "Victory is ours.\nThe future belongs to the machines."
