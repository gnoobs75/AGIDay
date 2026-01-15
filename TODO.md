# AGI Day: The Awakening - Development TODO

## Session Startup Prompt
When starting a new Claude Code session, say:
> "Continue development on AGI Day. Read TODO.md for current status and next tasks."

---

## Recently Completed (This Session)
- [x] Removed wave spawning system - replaced with continuous gameplay
- [x] Added wreckage drops when units die (50% REE value, 60s decay)
- [x] Implemented harvester/collector units (gold visuals, AI state machine)
- [x] Created faction selection screen (4 factions, click to select, SPACE to start)
- [x] Added strategic AI for opponent factions (spawning, attacking, harvesting)
- [x] Improved procedural bot visuals (unique style per faction)
- [x] Balanced initial spawning (2 of each unit type + 1 harvester per faction)
- [x] Fixed material access for CSGCombiner3D procedural bots
- [x] **Faction-specific unit stats** (FACTION_STAT_MODIFIERS: health, damage, speed, attack_speed, range)
- [x] **Per-unit attack speed** (replaced global ATTACK_COOLDOWN with unit-based attack_speed)
- [x] **Faction-specific projectiles** (FACTION_PROJECTILE_STYLES: shape, size, speed, emission)
- [x] **Enhanced death effects** (faction-specific explosions with debris for heavy factions)
- [x] **Improved tooltip** (now shows DPS, range, attack speed)
- [x] **Enhanced muzzle flash** (faction-specific size and intensity)
- [x] **Splash damage for heavy units** (tank projectiles deal AOE damage with visual ring effect)
- [x] **Building salvage system** (harvesters target damaged buildings, extract REE with 1.5x bonus)
- [x] **Power grid system** (factories need power, brownout/blackout affects production speed)
- [x] **District capture system** (5x5 grid, unit presence captures zones, visual indicators)
- [x] **Passive district income** (3 REE/sec per controlled district)
- [x] **Faction positions on sides** (North/East/South/West instead of corners)
- [x] **Faction camera positioning** (camera starts behind player's factory, looking toward center)
- [x] **District count UI** (shows player districts / total in resource panel)
- [x] **District domination victory** (control 60%+ of districts after 2 minutes = win)
- [x] **GPUParticles3D explosion effects** (faction-specific particle explosions with sparks and smoke)
- [x] **GPU projectile trails** (particle trails that follow projectiles, faction-colored)
- [x] **Impact effects** (particle burst on projectile hit for units, buildings, factories)
- [x] **Factory production effects** (welding sparks on unit production complete)
- [x] **Ability activation effects** (particle effects for Phase Shift, Overclock, Siege Formation, etc.)
- [x] **Hive Mind XP pools** (Combat/Economy/Engineering XP with tier-based buffs: damage, attack speed, dodge, crit)
- [x] **Human Remnant NPC faction** (wave spawning from edges, 60s delay, ambush damage bonus, brown faction color)
- [x] **Human patrol groups in city** (13 patrol locations throughout city, spawned when HR activates, mixed unit types)
- [x] **Fixed city building alignment** (factory positions updated from corners to sides: N/E/S/W)
- [x] **Building rendering fallback** (auto-spawns grid of buildings if WFC produces too few)
- [x] **Fixed factory visual positions** (main.tscn factories moved from corners to sides: N/E/S/W matching FACTORY_POSITIONS)
- [x] **Military Installation at city center** (Human Resistance HQ with walls, towers, barracks, command tower)
- [x] **Human Remnant concentrated at center** (garrison, tower guards, perimeter patrols at Military Installation)
- [x] **Defense turrets** (4 auto-targeting turrets at Military Installation, shoot at nearby robot factions)

---

## High Priority - Core Gameplay

### Combat & Units
- [x] Balance unit stats (damage, health, speed) for each faction
- [x] Add unit attack animations (muzzle flash, recoil)
- [x] Implement unit death animations (explosion, debris scatter)
- [x] Add projectile variety per faction (lasers, bullets, missiles)
- [x] Implement splash damage for heavy units

### Economy & Resources
- [x] Building salvage system (harvesters can disassemble buildings for REE)
- [x] Power grid system (factories need power, blackouts disable production)
- [x] District capture mechanics (control zones for bonuses)
- [x] Passive income from controlled districts

### Faction Abilities (Partially Implemented)
- [ ] Test and balance Phase Shift (Aether Swarm)
- [ ] Test and balance Overclock (OptiForge)
- [ ] Test and balance Siege Formation (LogiBots)
- [ ] Test and balance Ether Cloak (Aether Swarm)
- [x] Implement Acrobatic Strike leap attack visual (trail, launch dust, landing ring)
- [x] Add visual feedback for all abilities

---

## Medium Priority - Polish & UX

### Audio
- [x] Implement AudioManager integration (core/audio/ connected to main.gd)
- [x] Add combat sounds (weapon fire, explosions, impacts with throttling)
- [x] Add UI sounds (button clicks, notifications, error alerts)
- [x] Add dynamic music system based on combat intensity (intensity tracking, victory/defeat triggers)
- [x] Add unit voice lines / acknowledgment sounds (faction-specific pitch, select/move/attack/stop/ready)

### Visual Effects
- [x] Explosion particle effects (GPUParticles3D with faction-specific sparks and smoke)
- [x] Projectile trails and impacts (GPU particle trails + impact effects on hit)
- [x] Ability activation effects (faction-specific particle bursts)
- [x] Factory production effects (welding spark particles on unit spawn)
- [x] Fog of war shader improvements (animated noise, edge glow, shroud differentiation)

### UI Improvements
- [x] Minimap click-to-move functionality (with drag-pan, click indicator, attack-move support)
- [x] Unit portraits/icons in selection panel (clickable, health bars, veterancy stars)
- [x] Faction-specific UI themes/colors (accent, highlight, bg_tint, border for all panels)
- [x] Better production queue visualization (visual icons, time remaining, tooltips)
- [x] Hotkey reference overlay (H or ? key, comprehensive 6-column layout)
- [x] Tutorial/help overlay for new players (4-page interactive guide, F2 toggle)

---

## Lower Priority - Advanced Features

### AI Improvements
- [x] Smarter target prioritization (focus fire, low health, harvesters, threat level, factory defense)
- [x] Formation movement for AI units (faction-specific attack/defense formations, unit type sorting)
- [x] AI retreat behavior when losing (health-based, outnumbered detection, speed boost)
- [x] AI base defense prioritization (threat detection, defender recall, combat unit spawning)
- [x] Human Remnant NPC faction (guerrilla tactics, wave spawning, ambush damage bonus, brown faction color)

### Progression Systems
- [x] Veterancy system polish (level-up sound, particles, text popup, aura ring, elite pulsing)
- [x] Hive Mind XP pools (Combat/Economy/Engineering) - integrated with tier-based buffs, UI panel, damage/attack speed/dodge/crit bonuses
- [ ] Unlock system for abilities/units
- [ ] Research/tech tree

### Save/Load & Meta
- [x] Save game functionality - Quicksave F8, Autosave every 60s, binary format with compression
- [x] Load game functionality - Quickload Ctrl+F8, restores units, resources, districts, XP
- [x] Settings persistence (audio, controls) - SettingsManager with ConfigFile, auto-save on change
- [x] Statistics tracking (per-faction kills, deaths, damage, REE, abilities, districts, pause/game-over display)
- [ ] Replay system

### Multiplayer (Future)
- [ ] Network architecture planning
- [ ] Deterministic simulation verification
- [ ] Lobby system
- [ ] Steam integration (achievements, leaderboards)

---

## Known Issues
- [ ] CSGCombiner3D bots may have performance impact at high unit counts - consider MultiMesh
- [ ] Some GDScript warnings about unused parameters (cosmetic, not functional)
- [ ] Headless mode shows engine-level errors (not code issues)

---

## File Reference

### Key Files
- `scenes/main.gd` - Main game logic (~8500 lines)
- `core/factions/` - Faction definitions
- `core/abilities/` - Faction abilities
- `core/resources/resource_manager.gd` - REE economy
- `core/ai/` - AI systems (behavior trees, targeting)
- `core/power_grid/` - Power grid system (integrated in main.gd)
- `core/audio/` - Audio management (not yet integrated)
- `core/save/` - Save/load system (not yet integrated)

### Constants to Adjust for Balance
```gdscript
# In main.gd

# Production
PRODUCTION_COSTS = {"light": 30, "medium": 60, "heavy": 120, "harvester": 50}
PRODUCTION_TIMES = {"light": 2.0, "medium": 4.0, "heavy": 6.0, "harvester": 3.0}

# AI Settings
AI_STARTING_REE = 500.0
AI_PASSIVE_INCOME = 5.0  # REE per second
AI_SPAWN_INTERVAL = 5.0  # Seconds between AI spawns
WRECKAGE_REE_PERCENT = 0.5  # Wreckage contains 50% of unit cost

# Power Grid Settings
POWER_PLANT_OUTPUT = 100.0  # Power output per plant
FACTORY_POWER_DEMAND = 50.0  # Power required by factory
# Brownout: 75-50% power = 50-75% production speed
# Blackout: <50% power = production halted

# District Capture Settings
DISTRICT_GRID_SIZE = 5  # 5x5 grid (25 districts)
DISTRICT_SIZE = 120.0   # Each district is 120x120 units
DISTRICT_CAPTURE_RATE = 0.05  # Progress per second per unit
DISTRICT_DECAY_RATE = 0.02    # Progress decay when no units
DISTRICT_INCOME_RATE = 3.0    # REE per second per controlled district

# Base Unit Stats (UNIT_TYPES)
# scout: 60 HP, 15 DMG, 12-15 SPD, 12 RNG, 1.25 attack_speed
# soldier: 100 HP, 20 DMG, 7-10 SPD, 15 RNG, 1.0 attack_speed
# tank: 200 HP, 40 DMG, 4-6 SPD, 18 RNG, 0.6 attack_speed

# Faction Stat Modifiers (FACTION_STAT_MODIFIERS)
# Aether Swarm (1):   HP 0.85x, DMG 1.1x, SPD 1.2x, ATK_SPD 1.4x, RNG 0.9x
# OptiForge (2):      HP 1.1x,  DMG 1.05x, SPD 0.95x, ATK_SPD 1.0x, RNG 1.0x
# Dynapods (3):       HP 1.0x,  DMG 1.2x, SPD 1.15x, ATK_SPD 1.1x, RNG 1.05x
# LogiBots (4):       HP 1.25x, DMG 1.15x, SPD 0.8x, ATK_SPD 0.85x, RNG 1.2x
# Human Remnant (5):  HP 0.9x,  DMG 1.1x, SPD 1.1x, ATK_SPD 1.15x, RNG 1.1x
```

---

## Controls Reference
- **Mouse**: Select units, right-click to move/attack
- **SPACE**: Start match (from faction select) / Jump to combat
- **1/2/3**: Queue light/medium/heavy units
- **4**: Queue harvester
- **A**: Attack-move mode
- **P**: Pause
- **Q/E/F/C/B/V**: Faction abilities
- **Ctrl+1-9**: Save control group
- **1-9**: Recall control group
- **+/-**: Game speed
- **F8**: Quicksave
- **Ctrl+F8**: Quickload
