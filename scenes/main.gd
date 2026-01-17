extends Node3D
## Main scene entry point for AGI Day: The Awakening.
## Full gameplay with combat, projectiles, selection, and waves.

@onready var debug_label: Label = $UI/DebugLabel
@onready var camera: Camera3D = $Camera3D
@onready var game_over_panel: Panel = $UI/GameOverPanel
@onready var result_label: Label = $UI/GameOverPanel/VBoxContainer/ResultLabel
@onready var stats_label: Label = $UI/GameOverPanel/VBoxContainer/StatsLabel
@onready var restart_button: Button = $UI/GameOverPanel/VBoxContainer/RestartButton
@onready var quit_button: Button = $UI/GameOverPanel/VBoxContainer/QuitButton

## Resource panel UI
@onready var ree_label: Label = $UI/ResourcePanel/HBoxContainer/REELabel
@onready var ability_e_label: Label = $UI/ResourcePanel/HBoxContainer/AbilityE
@onready var ability_q_label: Label = $UI/ResourcePanel/HBoxContainer/AbilityQ
@onready var ability_f_label: Label = $UI/ResourcePanel/HBoxContainer/AbilityF
@onready var ability_c_label: Label = $UI/ResourcePanel/HBoxContainer/AbilityC
@onready var units_label: Label = $UI/ResourcePanel/HBoxContainer/UnitsLabel
@onready var production_queue_label: Label = $UI/ResourcePanel/HBoxContainer/ProductionQueueLabel

## Camera control settings
const CAMERA_PAN_SPEED := 150.0
const CAMERA_ZOOM_STEP := 25.0  # Height change per mouse wheel tick
const CAMERA_MIN_HEIGHT := 50.0
const CAMERA_MAX_HEIGHT := 600.0  # Allow zooming out to see larger map
const CAMERA_BOUNDS := 1400.0  # Allow viewing behind factories at ±1000
const EDGE_PAN_MARGIN := 25  # Pixels from screen edge to trigger panning
const CAMERA_SMOOTH_SPEED := 8.0  # Position interpolation speed
const CAMERA_ZOOM_SMOOTH := 6.0  # Zoom interpolation speed

## Camera state
var _target_camera_height := 180.0  # Desired zoom level
var _current_camera_height := 180.0  # Actual zoom level (smoothly approaches target)
var _camera_look_at := Vector3.ZERO

## Screen shake
var _screen_shake_intensity := 0.0
var _screen_shake_decay := 5.0  # How fast shake decays
const SCREEN_SHAKE_MAX := 3.0  # Maximum shake offset

## Combat settings
const ATTACK_RANGE := 15.0
const ATTACK_COOLDOWN := 0.8
const PROJECTILE_SPEED := 40.0
const UNIT_DAMAGE := 20.0
const UNIT_MAX_HEALTH := 100.0

## Wreckage settings
const WRECKAGE_REE_PERCENT := 0.5  # Wreckage contains 50% of unit's REE cost
const WRECKAGE_DECAY_TIME := 60.0  # Seconds before wreckage despawns
const WRECKAGE_HARVEST_RANGE := 3.0  # How close to wreckage to harvest

## Harvester AI states
enum HarvesterState { IDLE, SEEKING_WRECKAGE, HARVESTING, RETURNING, SEEKING_BUILDING, SALVAGING }
const HARVESTER_DEPOSIT_RANGE := 15.0  # How close to factory to deposit
const BUILDING_SALVAGE_RANGE := 4.0    # How close to building to salvage
const BUILDING_SALVAGE_RATE := 15.0    # REE per second while salvaging
const BUILDING_SALVAGE_BONUS := 1.5    # Bonus multiplier for salvaging vs destruction (50% more)

## Wreckage tracking
var _wreckage: Array = []  # Array of wreckage dictionaries {mesh, position, ree_value, spawn_time}

## AI Faction Settings
const AI_FACTIONS: Array[int] = [2, 3, 4]  # Factions controlled by AI
const AI_STARTING_REE := 500.0  # Starting resources for AI
const AI_PASSIVE_INCOME := 5.0  # REE per second passive income
const AI_SPAWN_INTERVAL := 5.0  # Seconds between AI spawn decisions
const AI_HARVESTER_RATIO := 0.15  # 15% chance to spawn harvester
var _ai_spawn_timers: Dictionary = {}  # faction_id -> timer
var _ai_aggression: Dictionary = {}  # faction_id -> float (0.0-1.0)

## Containers
var _unit_container: Node3D
var _projectile_container: Node3D
var _health_bar_container: Node3D
var _effects_container: Node3D

## Unit ejection animation system (UnitEjectionAnimation instance)
var _unit_ejection_animation: RefCounted = null
var _pending_ejections: Dictionary = {}  ## ejection_id -> unit Dictionary

## MultiMesh rendering system for batched unit rendering (reduces draw calls from 5000+ to ~20)
var _multimesh_renderer: RefCounted = null
## Use MultiMesh for rendering (set false to use individual meshes for debugging)
var _use_multimesh_rendering := true

## LOD system for unit visual detail based on camera distance
var _lod_system: RefCounted = null
## Performance tier system for AI update frequency based on combat proximity
var _performance_tier_system: RefCounted = null
## Enable performance tier system (throttles AI updates based on combat)
var _use_performance_tiers := true

## Frustum culling system - only render units within camera view
var _use_frustum_culling := true
## Max render distance from camera (units beyond this are hidden)
var _max_render_distance := 800.0
## Margin around visible area (units just outside view stay rendered for smooth edges)
var _frustum_margin := 100.0
## Cached camera frustum bounds (min_x, max_x, min_z, max_z)
var _frustum_bounds: Array = [0.0, 0.0, 0.0, 0.0]
## Stats for visibility culling
var _visible_unit_count := 0
var _culled_unit_count := 0

## Voxel terrain system for destructible buildings and terrain
var _voxel_system: Node3D = null
## Enable voxel terrain destruction
var _use_voxel_terrain := true

## Dynamic navigation mesh manager for pathfinding with destructible terrain
var _navmesh_manager: Node3D = null
## VoxelPathfindingBridge for batching nav updates
var _pathfinding_bridge: VoxelPathfindingBridge = null

## Unit tracking
var _units: Array = []  # Array of unit dictionaries
var _projectiles: Array = []
var _selected_units: Array = []
var _explosions: Array = []
var _blinking_units: Dictionary = {}  # unit_id -> {end_time, original_color}
var _leap_trails: Dictionary = {}  # unit_id -> GPUParticles3D trail for leaping units

## Selection box state
var _is_box_selecting := false
var _box_select_start := Vector2.ZERO
var _box_select_end := Vector2.ZERO
var _selection_box: ColorRect = null
const BOX_SELECT_THRESHOLD := 5.0  # Minimum drag distance to trigger box select

## Drag formation state (right-click drag to set formation direction)
var _is_drag_forming := false
var _drag_form_start := Vector2.ZERO  # Screen position where drag started
var _drag_form_end := Vector2.ZERO    # Current drag end position
var _drag_form_world_start := Vector3.ZERO  # World position of drag start
var _drag_form_preview_lines: Array[MeshInstance3D] = []  # Visual preview
const DRAG_FORM_THRESHOLD := 15.0  # Minimum drag distance to create formation

## Command mode state
var _attack_move_mode := false  # When true, next right-click is attack-move
var _rally_point_mode := false  # When true, next right-click sets rally point
var _control_groups: Dictionary = {}  # Group number (1-9) -> Array of units
var _rally_point_indicator: Node3D = null  # Visual indicator for rally point

## Game time tracking (replaces waves)
var _match_time := 0.0

## Player faction (selected at start)
var _player_faction := 1  # Default to faction 1 (Aether Swarm)
var _faction_select_panel: Control = null
var _faction_select_visible := true

## Faction info viewer (character sheets)
var _faction_info_panel: Control = null
var _faction_info_visible := false
var _faction_info_viewports: Array[SubViewport] = []  # For rotating unit models
var _faction_info_models: Array[Node3D] = []  # The actual 3D models to rotate

## Unit spec popup (detailed blueprint view)
var _unit_spec_popup: Control = null
var _unit_spec_visible := false
var _unit_spec_model_container: Node3D = null
var _unit_spec_viewport: SubViewport = null
var _unit_spec_combat_viewport: SubViewport = null
var _unit_spec_combat_units: Array[Dictionary] = []  # Units in the combat preview
var _unit_spec_current_template: UnitTemplate = null
var _unit_spec_current_weight_class: String = ""

## Unit display names for character sheets
const UNIT_DISPLAY_NAMES := {
	"scout": "Scout",
	"soldier": "Soldier",
	"tank": "Heavy Tank",
	"harvester": "Harvester"
}

## Unit role descriptions
const UNIT_ROLE_DESC := {
	"scout": "Fast reconnaissance unit. Quick attacks, low durability.",
	"soldier": "Balanced combat unit. Reliable damage and survivability.",
	"tank": "Heavy assault unit. Devastating AOE damage, slow movement.",
	"harvester": "Economic unit. Collects REE from wreckage and buildings."
}

## Faction info for selection screen
const FACTION_INFO := {
	1: {"name": "Aether Swarm", "desc": "Stealth micro-drones. Phase shifting, cloaking, swarm synergy.", "color": Color(0.3, 0.8, 1.0)},
	2: {"name": "OptiForge Legion", "desc": "Humanoid hordes. Adaptive evolution, mass production.", "color": Color(1.0, 0.4, 0.2)},
	3: {"name": "Dynapods Vanguard", "desc": "Agile behemoths. Acrobatic strikes, synchronized attacks.", "color": Color(0.4, 1.0, 0.4)},
	4: {"name": "LogiBots Colossus", "desc": "Heavy siege titans. Coordinated barrages, siege formations.", "color": Color(0.9, 0.9, 0.2)}
}

## Score tracking
var _player_kills := 0
var _player_deaths := 0
var _enemy_kills := 0

## Comprehensive statistics tracking per faction
var _faction_stats: Dictionary = {}  # faction_id -> stats dict
const STAT_DEFAULTS := {
	"kills": 0,
	"deaths": 0,
	"units_produced": 0,
	"damage_dealt": 0.0,
	"damage_taken": 0.0,
	"ree_earned": 0.0,
	"ree_spent": 0.0,
	"buildings_destroyed": 0,
	"harvesters_killed": 0,
	"factories_damaged": 0.0,
	"districts_captured": 0,
	"abilities_used": 0,
	"veteran_units_created": 0,
	"highest_kill_streak": 0,
	"current_kill_streak": 0,
	"time_in_combat": 0.0,
	"hr_waves_survived": 0,  # Human Remnant waves survived
	"hr_units_killed": 0      # Human Remnant units killed
}


## Factory state
var _factories: Dictionary = {}  # faction_id -> factory dict
const FACTORY_HEALTH := 500.0
const FACTORY_HEAL_RADIUS := 50.0  # Units near factory heal
const FACTORY_HEAL_RATE := 5.0  # HP per second

## Factory upgrades
const FACTORY_MAX_LEVEL := 3
const FACTORY_UPGRADE_COSTS := [0, 200, 500, 1000]  # Cost to reach each level
const FACTORY_UPGRADE_NAMES := ["Basic", "Improved", "Advanced", "Elite"]
# Upgrade bonuses per level: [production_speed, unit_health, unit_damage, heal_rate]
const FACTORY_UPGRADE_BONUSES := [
	[1.0, 1.0, 1.0, 1.0],      # Level 0: Base
	[1.15, 1.1, 1.1, 1.25],    # Level 1: 15% faster, 10% stronger units, 25% faster healing
	[1.3, 1.2, 1.2, 1.5],      # Level 2: 30% faster, 20% stronger, 50% faster healing
	[1.5, 1.35, 1.35, 2.0]     # Level 3: 50% faster, 35% stronger, 2x healing
]

## Rally points
var _rally_points: Dictionary = {}  # faction_id -> Vector3

## Factory selection state
var _factory_selected := false  # True when player's factory is selected
var _factory_production_panel: PanelContainer = null  # UI panel for production when factory selected
var _factory_queue_list_container: VBoxContainer = null  # Container for detailed queue items
var _factory_current_production_bar: ProgressBar = null  # Progress bar for current production in factory panel
var _factory_queue_counts: Dictionary = {}  # unit_class -> count to queue

## Power Grid overlay UI
var _power_grid_overlay_visible := false
var _power_status_panel: PowerStatusPanel = null
var _power_grid_display: PowerGridDisplay = null

## Patrol state
var _patrol_mode := false  # When true, next clicks add patrol waypoints
var _patrol_waypoints: Array[Vector3] = []  # Temporary waypoints being set

## Guard/follow state
var _guard_mode := false  # When true, next click on unit sets guard target

## Unit stances
enum UnitStance { AGGRESSIVE, DEFENSIVE, HOLD_POSITION }
var _default_stance: UnitStance = UnitStance.AGGRESSIVE

## Retreat behavior constants
const RETREAT_HEALTH_THRESHOLD := 0.25  # Retreat when below 25% health
const RETREAT_OUTNUMBERED_RATIO := 2.0  # Retreat when enemies outnumber allies 2:1
const RETREAT_CHECK_RADIUS := 40.0  # Radius to count nearby units
const RETREAT_SPEED_BONUS := 1.3  # 30% faster when retreating

## Unit formations
enum Formation { LINE, WEDGE, BOX, SCATTER }
var _current_formation: Formation = Formation.LINE
const FORMATION_SPACING := 4.0  # Space between units in formation

## AI faction formation preferences (attack / defense)
const FACTION_FORMATIONS := {
	1: {"attack": Formation.SCATTER, "defense": Formation.SCATTER},   # Aether Swarm - swarm tactics
	2: {"attack": Formation.WEDGE, "defense": Formation.LINE},        # OptiForge - aggressive push
	3: {"attack": Formation.LINE, "defense": Formation.WEDGE},        # Dynapods - balanced
	4: {"attack": Formation.BOX, "defense": Formation.BOX}            # LogiBots - tight formations
}

## Command queue (shift-click)
var _command_queue_mode := false  # When shift held, queue commands

## Camera edge scrolling
const EDGE_SCROLL_MARGIN := 20.0  # Pixels from screen edge
const EDGE_SCROLL_SPEED := 150.0  # Units per second
var _edge_scroll_enabled := true

## Double-click detection
var _last_click_time := 0.0
var _last_click_unit: Dictionary = {}
const DOUBLE_CLICK_TIME := 0.3  # Seconds

## Performance throttling
var _frame_count := 0
const FOG_UPDATE_INTERVAL := 5  # Update fog every N frames
const MINIMAP_UPDATE_INTERVAL := 3  # Update minimap every N frames
const DEBUG_UPDATE_INTERVAL := 10  # Update debug info every N frames

## Unit veterancy system
const VETERANCY_XP_THRESHOLDS := [0, 100, 300, 600, 1000]  # XP needed for each level (0-4)
const VETERANCY_DAMAGE_BONUS := [1.0, 1.1, 1.2, 1.35, 1.5]  # Damage multiplier per level
const VETERANCY_HEALTH_BONUS := [1.0, 1.1, 1.2, 1.3, 1.4]  # Health multiplier per level
const VETERANCY_SPEED_BONUS := [1.0, 1.0, 1.05, 1.1, 1.15]  # Speed multiplier per level
const VETERANCY_XP_PER_KILL := 50.0  # XP gained per kill
const VETERANCY_XP_PER_DAMAGE := 0.5  # XP gained per point of damage dealt

## Production settings
const PRODUCTION_COSTS := {
	"light": 30.0,
	"medium": 60.0,
	"heavy": 120.0,
	"harvester": 50.0
}
const PRODUCTION_TIMES := {
	"light": 2.0,
	"medium": 4.0,
	"heavy": 6.0,
	"harvester": 3.0
}
var _production_queue: Array = []  # [{unit_class, progress, total_time}]
var _current_production: Dictionary = {}  # Current item being produced
var _production_progress_bar: ProgressBar = null  # Visual progress bar
var _production_queue_container: HBoxContainer = null  # Visual queue icons
var _production_time_label: Label = null  # Shows time remaining

## REE pickups
var _ree_pickups: Array = []  # [{mesh, position, amount, lifetime}]
const REE_PICKUP_RADIUS := 8.0
const REE_PICKUP_LIFETIME := 30.0  # Disappear after 30 seconds

## Income tracking for UI display
var _last_ree_value: float = 0.0
var _ree_income_rate: float = 0.0  # Smoothed income per second
var _income_update_timer: float = 0.0
const INCOME_UPDATE_INTERVAL := 1.0  # Update income display every second

## Unit tooltip system
var _tooltip_panel: PanelContainer = null
var _tooltip_label: Label = null
var _hovered_unit: Dictionary = {}
const TOOLTIP_HOVER_DISTANCE := 5.0  # Max distance to show tooltip

## Faction mechanics system for abilities
var _faction_mechanics: FactionMechanicsSystem = null
var _next_unit_id: int = 1  # For tracking units in faction mechanics

## Hive Mind XP Progression System
var _experience_pool: ExperiencePool = null
var _hive_mind_progression: HiveMindProgression = null
var _xp_panel: PanelContainer = null  # UI panel for XP display

## Active faction abilities
var _phase_shift: PhaseShiftAbility = null
var _overclock_unit: OverclockUnitAbility = null
var _siege_formation: SiegeFormationAbility = null
var _nano_replication: NanoReplicationAbility = null
var _ether_cloak: EtherCloakAbility = null
var _acrobatic_strike: AcrobaticStrikeAbility = null
var _coordinated_barrage: CoordinatedBarrageAbility = null
var _fractal_movement: FractalMovementAbility = null
var _mass_production: MassProductionAbility = null

## City generation
var _city_renderer: CityRenderer = null

## Human Remnant NPC faction (wild card threat)
var _human_remnant_faction: HumanResistanceAIFaction = null
var _human_remnant_spawner: HumanResistanceSpawner = null
var _human_remnant_ai: HumanResistanceAI = null
var _human_remnant_enabled := true  # Can disable for testing
const HUMAN_REMNANT_FACTION_ID := 5
const HUMAN_REMNANT_SPAWN_DELAY := 5.0  # Seconds before Human Remnant starts spawning (reduced for testing)
var _human_remnant_spawn_timer := 0.0
var _human_remnant_active := false

## Defense Turrets (Military Installation - on corner towers)
var _defense_turrets: Array[Dictionary] = []  # Array of turret data
const TURRET_RANGE := 150.0  # Detection/attack range (increased for larger map)
const TURRET_DAMAGE := 30.0  # Damage per shot
const TURRET_FIRE_RATE := 0.6  # Seconds between shots
const TURRET_PROJECTILE_SPEED := 150.0  # Projectile speed
const TURRET_MISS_CHANCE := 0.25  # 25% chance to miss
const TURRET_SPLASH_RADIUS := 8.0  # Splash damage radius

## Mortar System (center of Military Installation)
var _mortar_active := false
var _mortar_cooldown := 0.0
var _mortar_target_indicator: Node3D = null  # Visual target marker
var _incoming_mortars: Array[Dictionary] = []  # Mortars in flight
const MORTAR_RANGE := 300.0  # Can target anywhere in range
const MORTAR_DAMAGE := 80.0  # High damage
const MORTAR_SPLASH_RADIUS := 15.0  # Large explosion
const MORTAR_FIRE_RATE := 4.0  # Slower fire rate
const MORTAR_FLIGHT_TIME := 2.5  # Time for mortar to arrive
const MORTAR_WARNING_TIME := 1.5  # Time target indicator shows before impact

## Settings persistence
var _settings_manager: SettingsManager = null

## Save/Load system
var _save_manager_node: SaveManagerClass = null
var _autosave_timer: float = 0.0
const AUTOSAVE_INTERVAL := 60.0  # Autosave every 60 seconds

## Minimap
var _minimap_viewport: SubViewport = null
var _minimap_icon_container: Node3D = null
var _minimap_icons: Dictionary = {}  # unit reference -> icon mesh
var _minimap_camera_indicator: Node3D = null  # Shows camera view area on minimap
var _minimap_dragging: bool = false  # True when dragging on minimap
var _minimap_drag_target: Vector3 = Vector3.ZERO  # Target position when smoothly panning
var _minimap_smooth_pan: bool = false  # Whether camera is smoothly panning to minimap click
const MINIMAP_PAN_SPEED := 15.0  # Speed of smooth camera pan

## Audio
var _audio_players: Array[AudioStreamPlayer] = []
var _audio_3d_players: Array[AudioStreamPlayer3D] = []
const AUDIO_POOL_SIZE := 16
const AUDIO_3D_POOL_SIZE := 32
var _last_sound_time: float = 0.0  # Throttle sounds to prevent overload
const SOUND_MIN_INTERVAL := 0.05  # Minimum time between sounds (50ms)
var _sounds_this_frame: int = 0  # Count sounds per frame
const MAX_SOUNDS_PER_FRAME := 4  # Max concurrent sounds per frame

## Audio Manager (advanced audio system with dynamic music)
var _audio_manager: AudioManager = null
## Battle intensity tracker for dynamic music (calculates intensity from combat events)
var _battle_intensity_tracker: BattleIntensityTracker = null
var _combat_intensity_update_timer: float = 0.0
const COMBAT_INTENSITY_UPDATE_INTERVAL := 0.5  # Update combat intensity twice per second

## Fog of War
var _fog_plane: MeshInstance3D = null
var _fog_material: ShaderMaterial = null
const FOG_VISION_RADIUS := 40.0  # How far player units can see
const FOG_EXPLORE_RADIUS := 60.0  # Extended exploration memory radius
var _explored_positions: PackedVector2Array = PackedVector2Array()
const MAX_EXPLORED_POSITIONS := 500  # Limit stored explored positions

## Kill feed system
var _kill_feed_container: VBoxContainer = null
var _kill_feed_entries: Array[Dictionary] = []  # [{label, timestamp}]
const KILL_FEED_MAX_ENTRIES := 5
const KILL_FEED_DURATION := 5.0  # Seconds before entry fades out

## Factory status panel
var _factory_status_panel: PanelContainer = null
var _factory_status_bars: Dictionary = {}  # faction_id -> {bar, label}

## Factory construction system
var _factory_construction: FactoryConstruction = null
var _construction_placement_mode := false  # True when placing new factory
var _construction_preview: Node3D = null  # Ghost preview of factory placement
var _construction_sites: Dictionary = {}  # site_id -> visual node

## Building ruins (destroyed buildings where new factories can be placed)
var _building_ruins: Array[Dictionary] = []  # [{position: Vector3, size: Vector3, age: float}]
const RUINS_MAX_AGE := 300.0  # Ruins last 5 minutes before clearing
const RUINS_PLACEMENT_RADIUS := 15.0  # Click radius for placing on ruins

## Power grid system
var _power_grid_manager: PowerGridManager = null
var _brownout_system: BrownoutSystem = null
var _power_consumer_manager: PowerConsumerManager = null
var _factory_power_consumers: Dictionary = {}  # faction_id -> PowerConsumer
var _power_status_label: Label = null
const POWER_PLANT_OUTPUT := 100.0  # Power output per plant
const FACTORY_POWER_DEMAND := 50.0  # Power required by each factory

## District capture system (8x8 grid, 64 districts for doubled map)
const DISTRICT_GRID_SIZE := 8
const DISTRICT_SIZE := 300.0  # Each district is 300x300 units (8*300 = 2400 map)
const DISTRICT_OFFSET := -1200.0  # Map starts at -1200 (half of 2400)
const DISTRICT_CAPTURE_RATE := 0.05  # Capture progress per second per unit
const DISTRICT_DECAY_RATE := 0.02  # Progress decay when no units
const DISTRICT_INCOME_RATE := 3.0  # REE per second per controlled district
var _districts: Array[Dictionary] = []  # Array of district data
var _district_visuals: Array[Node3D] = []  # Visual indicators for districts
var _district_labels: Array[Label3D] = []  # District ownership labels
var _district_overlay: DistrictOverlay = null  # Territory ownership ground tinting
var _district_status_label: Label = null  # UI label for district count

## Control group badges
var _control_group_container: HBoxContainer = null
var _control_group_labels: Dictionary = {}  # group_num -> Label

## Minimap ping system
var _active_pings: Array[Dictionary] = []  # [{mesh, timestamp, position}]
const PING_DURATION := 3.0  # How long pings last
const PING_PULSE_SPEED := 3.0  # How fast the ping pulses

## Camera follow mode
var _camera_follow_mode := false
var _camera_follow_target: Dictionary = {}  # Unit to follow

## Camera shake effect
var _camera_shake_duration := 0.0
var _camera_shake_intensity := 0.0
var _camera_shake_offset := Vector3.ZERO

## Control group double-tap detection
var _last_group_tap_time := 0.0
var _last_group_tap_num := 0
const GROUP_DOUBLE_TAP_TIME := 0.3

## Attack-move mode indicator
var _attack_move_indicator: Label = null

## Stance visual indicators
var _stance_indicators: Dictionary = {}  # unit_id -> MeshInstance3D
const STANCE_COLORS := {
	0: Color(1.0, 0.3, 0.3),  # AGGRESSIVE - Red
	1: Color(0.3, 0.6, 1.0),  # DEFENSIVE - Blue
	2: Color(1.0, 0.8, 0.2),  # HOLD_POSITION - Yellow
}
## PERFORMANCE: Cached meshes and materials for stance indicators (avoid per-frame allocations)
var _stance_meshes: Dictionary = {}  # stance -> Mesh (pre-created once)
var _stance_materials: Dictionary = {}  # stance -> StandardMaterial3D (pre-created once)
var _selected_unit_ids: Dictionary = {}  # unit_id -> true (for O(1) lookup)

## Rally point visual line
var _rally_line: MeshInstance3D = null

## Enemy direction indicators
var _enemy_indicators: Array[Control] = []
const ENEMY_INDICATOR_COUNT := 4  # Max indicators to show
const ENEMY_INDICATOR_SIZE := 24.0

## Ability ready flash tracking
var _ability_cooldown_states: Dictionary = {}  # ability_name -> was_on_cooldown
var _ability_flash_timers: Dictionary = {}  # ability_name -> flash_end_time

## Idle unit cycling
var _last_idle_unit_index := 0

## Match timer display
var _match_timer_label: Label = null

## Threat level indicator
var _threat_bar: ProgressBar = null
var _threat_label: Label = null

## Veterancy star indicators
var _veterancy_indicators: Dictionary = {}  # unit_id -> Label3D

## Command feedback visual indicators
var _command_lines: Array[MeshInstance3D] = []  # Lines from units to destinations
var _unit_command_flash: Dictionary = {}  # unit_id -> flash_end_time

## Production hotkey hints panel
var _hotkey_hints_panel: PanelContainer = null

## Full hotkey reference overlay (F1 toggle)
var _hotkey_overlay: PanelContainer = null
var _hotkey_overlay_visible := false

## Tutorial overlay for new players (Tab or F2 toggle)
var _tutorial_overlay: PanelContainer = null
var _tutorial_overlay_visible := false
var _tutorial_page := 0
const TUTORIAL_PAGE_COUNT := 4

## Pause overlay
var _pause_overlay: ColorRect = null
var _is_game_paused := false

## Command queue waypoint indicators
var _queue_waypoint_indicators: Array[Node3D] = []
var _queue_line_indicators: Array[MeshInstance3D] = []
var _queue_mode_indicator: Label = null

## Attack range circle display
var _range_circles: Array[Node3D] = []
var _show_range_circles := false

## Selection count display
var _selection_count_label: Label = null

## Unit portrait panel (shows selected unit icons)
var _portrait_panel: PanelContainer = null
var _portrait_container: HBoxContainer = null
var _portrait_icons: Array[Control] = []
const PORTRAIT_SIZE := 48  # Size of each unit portrait
const PORTRAIT_MAX_DISPLAY := 16  # Max portraits to show
const PORTRAIT_SPACING := 4  # Gap between portraits
const PORTRAIT_TASK_HEIGHT := 14  # Extra height for task status text

## Unit overview panel (right side - shows all player units by type)
var _unit_overview_panel: PanelContainer = null
var _unit_overview_rows: Dictionary = {}  # unit_type -> row container
const UNIT_OVERVIEW_ICON_SIZE := 10  # Small dots for each unit
const UNIT_OVERVIEW_MAX_PER_ROW := 30  # Max units shown per row

## Camera bookmarks (F9-F12)
var _camera_bookmarks: Dictionary = {}  # slot (9-12) -> Vector3 position

## Kill streak tracking
var _kill_streak := 0
var _kill_streak_timer := 0.0
const KILL_STREAK_TIMEOUT := 3.0  # Seconds between kills to maintain streak

## Auto-attack mode (units attack enemies in range without moving)
var _auto_attack_enabled := true  # Global default

## Game speed control
var _game_speed := 1.0
const GAME_SPEED_MIN := 0.25
const GAME_SPEED_MAX := 4.0
const GAME_SPEED_STEP := 0.25
var _game_speed_label: Label = null

## Unit count by type display
var _unit_count_label: Label = null

## Total resources earned stat
var _total_ree_earned := 0.0
var _ree_stats_label: Label = null

## Map integer faction IDs to FactionMechanicsSystem string IDs
const FACTION_ID_TO_STRING := {
	1: "aether_swarm",
	2: "glacius",      # OptiForge uses "glacius" (tank armor bonuses)
	3: "dynapods",
	4: "logibots",
	5: "human_remnant"
}

## Faction-specific unit templates
## Maps faction_id to array of [template_id, visual_scale_multiplier]
const FACTION_UNIT_TEMPLATES := {
	# Aether Swarm (Blue) - Fast fragile swarms
	1: {
		"light": "aether_swarm_spikelet",
		"medium": "aether_swarm_buzzblade",
		"heavy": "aether_swarm_wispfire"
	},
	# OptiForge Legion (Red) - Humanoid rushers
	2: {
		"light": "optiforge_blitzkin",
		"medium": "optiforge_pulseforged",
		"heavy": "optiforge_jetkin"
	},
	# Dynapods Vanguard (Green) - Agile mechs
	3: {
		"light": "dynapods_skybound",
		"medium": "dynapods_legbreaker",
		"heavy": "dynapods_vaultpounder"
	},
	# LogiBots Colossus (Yellow) - Heavy industrial
	4: {
		"light": "logibots_gridbreaker",
		"medium": "logibots_crushkin",
		"heavy": "logibots_siegehaul"
	},
	# Human Remnant (Brown) - NPC wild card
	5: {
		"light": "human_m4_fireteam",
		"medium": "human_javelin_ghost",
		"heavy": "human_m1_abrams"
	}
}

## Fallback unit types (when UnitTemplateManager not available)
## Base stats before faction modifiers are applied
const UNIT_TYPES := {
	"scout": {
		"size": Vector3(1.0, 1.5, 1.0),
		"health": 60.0,
		"speed_min": 12.0,
		"speed_max": 15.0,
		"damage": 15.0,
		"range": 12.0,
		"attack_speed": 1.25  # Attacks per second (base cooldown = 1/attack_speed)
	},
	"soldier": {
		"size": Vector3(1.5, 2.0, 1.5),
		"health": 100.0,
		"speed_min": 7.0,
		"speed_max": 10.0,
		"damage": 20.0,
		"range": 15.0,
		"attack_speed": 1.0  # 1 attack per second
	},
	"tank": {
		"size": Vector3(2.5, 2.5, 2.5),
		"health": 200.0,
		"speed_min": 4.0,
		"speed_max": 6.0,
		"damage": 40.0,
		"range": 18.0,
		"attack_speed": 0.6,  # Slower attacks, more damage per hit
		"splash_radius": 5.0,  # Area of effect damage radius
		"splash_falloff": 0.5  # Damage multiplier at edge of splash (50%)
	},
	"harvester": {
		"size": Vector3(2.0, 1.5, 2.0),
		"health": 80.0,
		"speed_min": 8.0,
		"speed_max": 10.0,
		"damage": 5.0,
		"range": 8.0,
		"attack_speed": 0.5,
		"harvest_rate": 10.0,  # REE per second while harvesting
		"carry_capacity": 50.0  # Max REE it can carry
	}
}

## Faction stat modifiers - multipliers applied to base unit stats
## Each faction has unique strengths and weaknesses
const FACTION_STAT_MODIFIERS := {
	# Aether Swarm: Fast, fragile swarm with high DPS through attack speed
	1: {
		"health": 0.85,       # -15% HP (fragile but numerous)
		"damage": 1.1,        # +10% damage
		"speed": 1.2,         # +20% movement speed
		"attack_speed": 1.4,  # +40% attack speed (rapid fire swarm)
		"range": 0.9,         # -10% range (close-range swarm tactics)
		"splash_radius": 0.6  # -40% splash (precision strikes)
	},
	# OptiForge Legion: Balanced, tanky humanoid hordes
	2: {
		"health": 1.1,        # +10% HP (durable)
		"damage": 1.05,       # +5% damage
		"speed": 0.95,        # -5% speed (steady advance)
		"attack_speed": 1.0,  # Normal attack speed
		"range": 1.0,         # Normal range
		"splash_radius": 1.0  # Normal splash
	},
	# Dynapods Vanguard: Agile with high burst damage
	3: {
		"health": 1.0,        # Normal HP
		"damage": 1.2,        # +20% damage (hard hitting)
		"speed": 1.15,        # +15% speed (acrobatic)
		"attack_speed": 1.1,  # +10% attack speed
		"range": 1.05,        # +5% range (precise strikes)
		"splash_radius": 0.8  # -20% splash (surgical precision)
	},
	# LogiBots Colossus: Heavy siege units, slow but devastating
	4: {
		"health": 1.25,       # +25% HP (heavily armored)
		"damage": 1.15,       # +15% damage (siege weapons)
		"speed": 0.8,         # -20% speed (lumbering titans)
		"attack_speed": 0.85, # -15% attack speed (slow reload)
		"range": 1.2,         # +20% range (long-range artillery)
		"splash_radius": 1.5  # +50% splash (artillery bombardment)
	},
	# Human Remnant: Balanced guerrilla fighters
	5: {
		"health": 0.9,        # -10% HP
		"damage": 1.1,        # +10% damage
		"speed": 1.1,         # +10% speed
		"attack_speed": 1.15, # +15% attack speed (military training)
		"range": 1.1,         # +10% range (modern weapons)
		"splash_radius": 1.1  # +10% splash (explosive ordnance)
	}
}

## Colors for factions
const FACTION_COLORS := {
	1: Color(0.2, 0.6, 1.0),    # Aether Swarm - Blue
	2: Color(1.0, 0.3, 0.2),    # OptiForge Legion - Red
	3: Color(0.2, 1.0, 0.3),    # Dynapods Vanguard - Green
	4: Color(1.0, 0.8, 0.2),    # LogiBots Colossus - Yellow
	5: Color(0.6, 0.4, 0.2),    # Human Remnant - Brown
}

## Faction-specific UI theme colors (accent, highlight, background tint)
const FACTION_UI_THEMES := {
	1: {  # Aether Swarm - Electric blue, futuristic
		"accent": Color(0.3, 0.7, 1.0),
		"highlight": Color(0.5, 0.85, 1.0),
		"bg_tint": Color(0.08, 0.12, 0.18),
		"border": Color(0.2, 0.5, 0.8),
		"text": Color(0.8, 0.9, 1.0),
	},
	2: {  # OptiForge Legion - Industrial red/orange
		"accent": Color(1.0, 0.4, 0.25),
		"highlight": Color(1.0, 0.6, 0.4),
		"bg_tint": Color(0.15, 0.08, 0.06),
		"border": Color(0.8, 0.3, 0.2),
		"text": Color(1.0, 0.9, 0.85),
	},
	3: {  # Dynapods Vanguard - Vibrant green, organic
		"accent": Color(0.3, 1.0, 0.4),
		"highlight": Color(0.5, 1.0, 0.6),
		"bg_tint": Color(0.06, 0.14, 0.08),
		"border": Color(0.25, 0.8, 0.35),
		"text": Color(0.85, 1.0, 0.9),
	},
	4: {  # LogiBots Colossus - Industrial yellow/gold
		"accent": Color(1.0, 0.85, 0.3),
		"highlight": Color(1.0, 0.95, 0.5),
		"bg_tint": Color(0.14, 0.12, 0.06),
		"border": Color(0.8, 0.7, 0.2),
		"text": Color(1.0, 0.95, 0.8),
	},
}

## Unit-type-specific projectile modifiers (applied on top of faction styles)
const UNIT_TYPE_PROJECTILE_MODS := {
	"scout": {
		"shape_override": "sphere",    # Small rapid energy bolts
		"size_mult": 0.6,              # Smaller projectiles
		"speed_mult": 1.3,             # Faster
		"trail_segments": 3,           # Short trail
		"glow_intensity": 2.0
	},
	"soldier": {
		"shape_override": "cylinder",  # Medium beam shots
		"size_mult": 1.0,              # Standard size
		"speed_mult": 1.0,             # Normal speed
		"trail_segments": 5,           # Medium trail
		"glow_intensity": 2.5
	},
	"tank": {
		"shape_override": "box",       # Heavy artillery shells
		"size_mult": 1.8,              # Large projectiles
		"speed_mult": 0.7,             # Slower but powerful
		"trail_segments": 8,           # Long smoke trail
		"glow_intensity": 1.5,
		"smoke_trail": true            # Adds smoke effect
	},
	"harvester": {
		"shape_override": "sphere",    # Defensive shots
		"size_mult": 0.4,              # Very small
		"speed_mult": 1.2,             # Quick defense
		"trail_segments": 2,           # Minimal trail
		"glow_intensity": 1.0
	}
}

## Faction-specific projectile visual styles
const FACTION_PROJECTILE_STYLES := {
	# Aether Swarm: Small, rapid plasma bolts with electric blue glow
	1: {
		"shape": "sphere",        # sphere, cylinder, box
		"size_mult": 0.7,         # Smaller projectiles
		"speed_mult": 1.3,        # Faster projectiles
		"emission_mult": 3.0,     # Bright glow
		"secondary_color": Color(0.6, 0.8, 1.0),  # Lighter blue core
		"trail_enabled": true
	},
	# OptiForge Legion: Standard energy bolts, orange-red plasma
	2: {
		"shape": "sphere",
		"size_mult": 1.0,
		"speed_mult": 1.0,
		"emission_mult": 2.0,
		"secondary_color": Color(1.0, 0.6, 0.3),  # Orange core
		"trail_enabled": true
	},
	# Dynapods Vanguard: Precise laser needles, elongated green beams
	3: {
		"shape": "cylinder",      # Elongated laser beam
		"size_mult": 0.8,
		"speed_mult": 1.4,        # Fast precision shots
		"emission_mult": 4.0,     # Very bright laser
		"secondary_color": Color(0.5, 1.0, 0.6),  # Light green core
		"trail_enabled": true
	},
	# LogiBots Colossus: Large, slow artillery shells
	4: {
		"shape": "box",           # Blocky shell shape
		"size_mult": 1.5,         # Larger projectiles
		"speed_mult": 0.7,        # Slower but heavy
		"emission_mult": 1.5,     # Solid glow
		"secondary_color": Color(1.0, 1.0, 0.5),  # Yellow-white core
		"trail_enabled": true
	},
	# Human Remnant: Conventional bullets, fast and small
	5: {
		"shape": "cylinder",
		"size_mult": 0.5,
		"speed_mult": 1.5,        # Fast bullets
		"emission_mult": 1.0,     # Minimal glow
		"secondary_color": Color(0.8, 0.6, 0.4),  # Brass color
		"trail_enabled": false    # No energy trail
	}
}

## Names for factions
const FACTION_NAMES := {
	1: "AETHER SWARM",
	2: "OPTIFORGE LEGION",
	3: "DYNAPODS VANGUARD",
	4: "LOGIBOTS COLOSSUS",
	5: "HUMAN REMNANT"
}

## Map size (ground covers -MAP_SIZE/2 to +MAP_SIZE/2) - DOUBLED for larger city
const MAP_SIZE := 2400.0

## Factory positions (sides of the map - doubled for larger map)
const FACTORY_POSITIONS := {
	1: Vector3(0, 0, -1000),    # North (Aether Swarm)
	2: Vector3(1000, 0, 0),     # East (OptiForge Legion)
	3: Vector3(0, 0, 1000),     # South (Dynapods Vanguard)
	4: Vector3(-1000, 0, 0),    # West (LogiBots Colossus)
}

## Camera starting angles for each faction (looking toward map center)
const FACTION_CAMERA_ANGLES := {
	1: Vector3(0, 180, 0),   # North faction looks south (toward +Z)
	2: Vector3(0, 270, 0),   # East faction looks west (toward -X)
	3: Vector3(0, 0, 0),     # South faction looks north (toward -Z)
	4: Vector3(0, 90, 0),    # West faction looks east (toward +X)
}


func _ready() -> void:
	print("AGI Day: Main scene loaded")
	# Allow input processing even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_containers()
	_initialize_systems()
	_connect_ui_signals()
	_initialize_camera()
	_update_debug_info()


func _initialize_camera() -> void:
	# Set camera to look at map center, at a nice starting zoom
	_camera_look_at = Vector3.ZERO
	_target_camera_height = 180.0
	_current_camera_height = 180.0  # Start at target (no initial animation)
	if camera:
		# Position camera immediately (no lerp on first frame)
		camera.global_position = Vector3(0, _current_camera_height, _current_camera_height * 0.5)
		camera.look_at(_camera_look_at, Vector3.UP)
		# Increase far clip distance to see entire map
		camera.far = 1000.0


## Camera rotation offset for player faction (so base is at bottom of screen)
var _camera_faction_rotation: float = 0.0

## Position camera to view from BEHIND player's faction, looking toward map center.
## This puts player's base at the BOTTOM of the screen (standard RTS orientation).
## Camera is positioned outside the city in the grass area.
func _setup_faction_camera(faction_id: int) -> void:
	var factory_pos: Vector3 = FACTORY_POSITIONS.get(faction_id, Vector3.ZERO)

	# Direction from center to factory (outward direction)
	var outward_dir := factory_pos.normalized()

	# Camera rotation to face TOWARD center (opposite of outward direction)
	# Faction 1 (North, -Z): Camera behind at more -Z, faces +Z (toward center)
	# Faction 2 (East, +X): Camera behind at more +X, faces -X (toward center)
	# Faction 3 (South, +Z): Camera behind at more +Z, faces -Z (toward center)
	# Faction 4 (West, -X): Camera behind at more -X, faces +X (toward center)
	match faction_id:
		1: _camera_faction_rotation = 0.0       # Face +Z (south toward center)
		2: _camera_faction_rotation = PI / 2    # Face -X (west toward center)
		3: _camera_faction_rotation = PI        # Face -Z (north toward center)
		4: _camera_faction_rotation = -PI / 2   # Face +X (east toward center)
		_: _camera_faction_rotation = 0.0

	_target_camera_height = 150.0
	_current_camera_height = 150.0

	# Position camera BEHIND the factory (further from center, in the grass area)
	# Camera looks at a point slightly in front of the factory (toward center)
	var cam_behind_dist := 120.0  # How far behind the factory
	var look_ahead_dist := 50.0   # How far ahead of factory to look

	# Camera position: factory + outward direction * distance
	var cam_pos := factory_pos + outward_dir * cam_behind_dist
	cam_pos.y = _current_camera_height

	# Look at point: factory - outward direction * distance (toward center)
	_camera_look_at = factory_pos - outward_dir * look_ahead_dist

	if camera:
		camera.global_position = cam_pos
		# Look down at the look point
		camera.look_at(_camera_look_at, Vector3.UP)

		print("Camera positioned for faction %d at %s, looking at %s" % [faction_id, camera.global_position, _camera_look_at])


## Setup dynamic navigation mesh system for pathfinding with destructible terrain.
func _setup_dynamic_navmesh() -> void:
	# Create pathfinding bridge for batching updates
	_pathfinding_bridge = VoxelPathfindingBridge.new()

	# Connect voxel system to pathfinding bridge
	if _voxel_system != null:
		_pathfinding_bridge.connect_to_voxel_system(_voxel_system)

	# Create dynamic navmesh manager
	var navmesh_script := load("res://core/ai/pathfinding/dynamic_navmesh_manager.gd")
	if navmesh_script != null:
		_navmesh_manager = navmesh_script.new()
		add_child(_navmesh_manager)

		# Connect to voxel system and pathfinding bridge
		if _voxel_system != null:
			_navmesh_manager.connect_to_voxel_system(_voxel_system)
		_navmesh_manager.connect_to_pathfinding_bridge(_pathfinding_bridge)

		# Initialize navigation regions for the world (512x512 map)
		_navmesh_manager.initialize_world_regions(Vector3(512, 10, 512))

		print("[NavMesh] Dynamic navigation mesh enabled - terrain changes update pathfinding")


func _setup_minimap() -> void:
	# Get reference to minimap viewport from scene
	var minimap_container: SubViewportContainer = get_node_or_null("UI/MinimapContainer/MinimapViewport")
	if minimap_container:
		_minimap_viewport = minimap_container.get_node_or_null("SubViewport")

	if _minimap_viewport:
		# Rotate the minimap camera to match player's view orientation
		var minimap_camera: Camera3D = _minimap_viewport.get_node_or_null("Camera3D")
		if minimap_camera:
			# Rotate camera around Y to match player faction orientation
			minimap_camera.rotation.y = _camera_faction_rotation

		# Create container for minimap icons inside the viewport's scene
		_minimap_icon_container = Node3D.new()
		_minimap_icon_container.name = "MinimapIcons"
		_minimap_viewport.add_child(_minimap_icon_container)

		# Create camera view indicator (rectangular frame)
		_minimap_camera_indicator = _create_minimap_camera_frame()
		_minimap_viewport.add_child(_minimap_camera_indicator)

	# Add click handler for minimap navigation
	var panel_container: PanelContainer = get_node_or_null("UI/MinimapContainer")
	if panel_container:
		# Create an invisible button over the minimap
		var click_area := Button.new()
		click_area.name = "MinimapClickArea"
		click_area.flat = true
		click_area.set_anchors_preset(Control.PRESET_FULL_RECT)
		click_area.mouse_filter = Control.MOUSE_FILTER_STOP
		click_area.gui_input.connect(_on_minimap_input)
		panel_container.add_child(click_area)


## Update minimap rotation to match player's camera orientation.
func _update_minimap_rotation() -> void:
	if _minimap_viewport == null:
		return

	var minimap_camera: Camera3D = _minimap_viewport.get_node_or_null("Camera3D")
	if minimap_camera:
		# Rotate camera around Y to match player faction orientation
		minimap_camera.rotation.y = _camera_faction_rotation
		print("Minimap rotated to match faction angle: %f°" % rad_to_deg(_camera_faction_rotation))


## Create a rectangular frame to show camera viewport on minimap.
func _create_minimap_camera_frame() -> Node3D:
	var frame_container := Node3D.new()
	frame_container.name = "CameraViewIndicator"

	var frame_color := Color(1.0, 1.0, 1.0, 0.8)
	var frame_height := 55.0  # Above other minimap elements

	# Create 4 edges of the frame using thin boxes
	var edge_thickness := 2.0

	# Material for frame edges
	var mat := StandardMaterial3D.new()
	mat.albedo_color = frame_color
	mat.emission_enabled = true
	mat.emission = Color(1.0, 1.0, 1.0)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Create all 4 edges (will be scaled dynamically)
	for i in range(4):
		var edge := CSGBox3D.new()
		edge.name = "Edge%d" % i
		edge.material = mat
		edge.size = Vector3(1, 1, edge_thickness)  # Will be resized in update
		frame_container.add_child(edge)

	frame_container.position.y = frame_height
	return frame_container


## Update the camera viewport indicator on the minimap.
func _update_minimap_camera_indicator() -> void:
	if _minimap_camera_indicator == null or camera == null:
		return

	# Calculate visible area based on camera position and height
	var cam_pos: Vector3 = _camera_look_at  # Where camera is looking
	var cam_height: float = _current_camera_height

	# Estimate visible area based on camera FOV and height
	# Higher camera = larger visible area
	var visible_half_width: float = cam_height * 0.8  # Approximate based on FOV
	var visible_half_depth: float = cam_height * 0.5

	# Rotate camera position to minimap space (inverse of world->minimap rotation)
	var minimap_cam_pos := cam_pos.rotated(Vector3.UP, -_camera_faction_rotation)

	# Update frame position (in rotated minimap coordinates)
	_minimap_camera_indicator.position.x = minimap_cam_pos.x
	_minimap_camera_indicator.position.z = minimap_cam_pos.z

	# Update frame edges
	var edge_thickness := 2.0
	var edges: Array[Node] = []
	for child in _minimap_camera_indicator.get_children():
		edges.append(child)

	if edges.size() >= 4:
		# Top edge (north)
		var top: CSGBox3D = edges[0] as CSGBox3D
		top.size = Vector3(visible_half_width * 2, 1, edge_thickness)
		top.position = Vector3(0, 0, -visible_half_depth)

		# Bottom edge (south)
		var bottom: CSGBox3D = edges[1] as CSGBox3D
		bottom.size = Vector3(visible_half_width * 2, 1, edge_thickness)
		bottom.position = Vector3(0, 0, visible_half_depth)

		# Left edge (west)
		var left: CSGBox3D = edges[2] as CSGBox3D
		left.size = Vector3(edge_thickness, 1, visible_half_depth * 2)
		left.position = Vector3(-visible_half_width, 0, 0)

		# Right edge (east)
		var right: CSGBox3D = edges[3] as CSGBox3D
		right.size = Vector3(edge_thickness, 1, visible_half_depth * 2)
		right.position = Vector3(visible_half_width, 0, 0)


func _create_minimap_icon(unit: Dictionary) -> void:
	if _minimap_icon_container == null:
		return

	var faction_id: int = unit.faction_id
	var icon_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	# Create a small flat disc/circle for the minimap
	var icon := CSGCylinder3D.new()
	icon.name = "MinimapIcon"
	icon.radius = 3.0  # Size on minimap
	icon.height = 1.0
	icon.sides = 8

	var mat := StandardMaterial3D.new()
	mat.albedo_color = icon_color
	mat.emission_enabled = true
	mat.emission = icon_color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	icon.material = mat

	# Position at unit's world position (minimap camera sees from above)
	if is_instance_valid(unit.mesh):
		icon.position = unit.mesh.position
		icon.position.y = 50.0  # Float above terrain for visibility

	_minimap_icon_container.add_child(icon)
	var unit_id: int = unit.get("id", 0)
	_minimap_icons[unit_id] = icon


func _update_minimap_icons() -> void:
	if _minimap_icon_container == null:
		return

	for unit in _units:
		var unit_id: int = unit.get("id", 0)
		if unit.is_dead:
			# Remove icon for dead units
			if _minimap_icons.has(unit_id):
				var icon: Node3D = _minimap_icons[unit_id]
				if is_instance_valid(icon):
					icon.queue_free()
				_minimap_icons.erase(unit_id)
			continue

		# Create icon if missing
		if not _minimap_icons.has(unit_id):
			_create_minimap_icon(unit)

		# Update icon position
		if _minimap_icons.has(unit_id) and is_instance_valid(unit.mesh):
			var icon: Node3D = _minimap_icons[unit_id]
			if is_instance_valid(icon):
				icon.position = unit.mesh.position
				icon.position.y = 50.0


## Handle minimap input for click-to-navigate.
func _on_minimap_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.alt_pressed:
					# Alt+click creates a ping
					_create_minimap_ping(event.position)
				else:
					# Start dragging or navigate
					_minimap_dragging = true
					_minimap_navigate(event.position, event.shift_pressed)
					_spawn_minimap_click_indicator(event.position)
			else:
				# Release - stop dragging
				_minimap_dragging = false
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Right-click on minimap moves selected units
			if _attack_move_mode:
				_minimap_attack_move_units(event.position)
			else:
				_minimap_move_units(event.position)
			_spawn_minimap_click_indicator(event.position, true)

	# Handle drag motion
	elif event is InputEventMouseMotion and _minimap_dragging:
		_minimap_navigate(event.position, false)


## Spawn a brief click indicator on the minimap.
func _spawn_minimap_click_indicator(local_pos: Vector2, is_move_command: bool = false) -> void:
	if _minimap_viewport == null:
		return

	var world_pos := _minimap_local_to_world(local_pos)

	# Create a small ring that expands and fades
	var indicator := CSGTorus3D.new()
	indicator.name = "MinimapClick"
	indicator.inner_radius = 2.0
	indicator.outer_radius = 4.0
	indicator.ring_sides = 12
	indicator.sides = 12
	indicator.position = world_pos + Vector3(0, 56, 0)  # Above other minimap elements

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN if is_move_command else Color.WHITE
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	indicator.material = mat

	_minimap_viewport.add_child(indicator)

	# Animate: expand and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(indicator, "inner_radius", 8.0, 0.3)
	tween.tween_property(indicator, "outer_radius", 10.0, 0.3)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(indicator.queue_free)


## Convert minimap local position to world position.
## Accounts for minimap rotation based on player faction.
func _minimap_local_to_world(local_pos: Vector2) -> Vector3:
	var minimap_size := Vector2(200, 200)
	var normalized := local_pos / minimap_size
	var local_x := (normalized.x - 0.5) * MAP_SIZE
	var local_z := (normalized.y - 0.5) * MAP_SIZE

	# Rotate back from minimap orientation to world coordinates
	var world_pos := Vector3(local_x, 0, local_z).rotated(Vector3.UP, _camera_faction_rotation)
	return world_pos


## Navigate camera to minimap click position.
## If smooth is true, pan smoothly instead of jumping instantly.
func _minimap_navigate(local_pos: Vector2, smooth: bool = false) -> void:
	var panel_container: PanelContainer = get_node_or_null("UI/MinimapContainer")
	if panel_container == null:
		return

	var world_pos := _minimap_local_to_world(local_pos)

	# Clamp to camera bounds
	world_pos.x = clampf(world_pos.x, -CAMERA_BOUNDS, CAMERA_BOUNDS)
	world_pos.z = clampf(world_pos.z, -CAMERA_BOUNDS, CAMERA_BOUNDS)

	if smooth:
		# Enable smooth panning
		_minimap_smooth_pan = true
		_minimap_drag_target = world_pos
	else:
		# Instant navigation (or drag mode)
		_minimap_smooth_pan = false
		_camera_look_at = world_pos


## Attack-move selected units via minimap with 'A' modifier.
func _minimap_attack_move_units(local_pos: Vector2) -> void:
	if _selected_units.is_empty():
		return

	var world_pos := _minimap_local_to_world(local_pos)

	# Spawn attack-move indicator (red/orange)
	_spawn_attack_move_indicator(world_pos)

	for unit in _selected_units:
		if not unit.is_dead and unit.faction_id == _player_faction:
			unit.target_pos = world_pos
			unit.target_enemy = null
			unit.attack_move = true  # Will attack enemies encountered on the way


## Move selected units via minimap right-click.
func _minimap_move_units(local_pos: Vector2) -> void:
	if _selected_units.is_empty():
		return

	var world_pos := _minimap_local_to_world(local_pos)

	# Spawn move indicator and issue move command
	_spawn_move_indicator(world_pos)

	for unit in _selected_units:
		if not unit.is_dead and unit.faction_id == _player_faction:
			unit.target_pos = world_pos
			unit.target_enemy = null
			unit.attack_move = false  # Normal move, don't attack on the way


## Update selection ring positions to follow their units.
func _update_selection_rings() -> void:
	for unit in _selected_units:
		if unit.is_dead:
			_remove_selection_indicator(unit)
			continue

		if unit.has("selection_ring") and is_instance_valid(unit.selection_ring):
			if is_instance_valid(unit.mesh):
				unit.selection_ring.position = unit.mesh.position
				unit.selection_ring.position.y = 0.2


## Update stance visual indicators for selected player units.
## PERFORMANCE OPTIMIZED: Uses O(1) dict lookup instead of O(n²) nested loops,
## and uses cached meshes/materials instead of creating new ones per indicator.
func _update_stance_indicators() -> void:
	# PERFORMANCE: Build selected unit IDs set for O(1) lookup (instead of O(n) search)
	_selected_unit_ids.clear()
	for unit in _selected_units:
		var uid: int = unit.get("id", -1)
		if uid != -1 and unit.faction_id == _player_faction and not unit.is_dead:
			_selected_unit_ids[uid] = true

	# Clean up indicators for units no longer selected (O(1) lookup now)
	var units_to_remove: Array[int] = []
	for unit_id in _stance_indicators:
		if not _selected_unit_ids.has(unit_id):
			var indicator: MeshInstance3D = _stance_indicators[unit_id]
			if is_instance_valid(indicator):
				indicator.queue_free()
			units_to_remove.append(unit_id)

	for unit_id in units_to_remove:
		_stance_indicators.erase(unit_id)

	# Update or create indicators for selected player units
	for unit in _selected_units:
		if unit.is_dead or unit.faction_id != _player_faction:
			continue

		var unit_id: int = unit.get("id", -1)
		if unit_id == -1:
			continue

		var stance: int = unit.get("stance", UnitStance.AGGRESSIVE)

		if _stance_indicators.has(unit_id):
			# Update existing indicator position
			var indicator: MeshInstance3D = _stance_indicators[unit_id]
			if is_instance_valid(indicator) and is_instance_valid(unit.mesh):
				indicator.position = unit.mesh.position
				indicator.position.y = unit.mesh.scale.y * 2.0 + 1.5  # Above unit
				# Update mesh if stance changed (use cached mesh)
				var cached_mesh: Mesh = _stance_meshes.get(stance)
				if cached_mesh and indicator.mesh != cached_mesh:
					indicator.mesh = cached_mesh
					# Switch to cached material for new stance
					var cached_mat: StandardMaterial3D = _stance_materials.get(stance)
					if cached_mat:
						indicator.set_surface_override_material(0, cached_mat)
		else:
			# Create new indicator using CACHED meshes and materials
			var indicator := MeshInstance3D.new()
			indicator.name = "StanceIndicator_%d" % unit_id

			# Use cached mesh (or fallback to aggressive if not found)
			var cached_mesh: Mesh = _stance_meshes.get(stance, _stance_meshes.get(UnitStance.AGGRESSIVE))
			if cached_mesh:
				indicator.mesh = cached_mesh

			# Use cached material (or fallback to aggressive if not found)
			var cached_mat: StandardMaterial3D = _stance_materials.get(stance, _stance_materials.get(UnitStance.AGGRESSIVE))
			if cached_mat:
				indicator.set_surface_override_material(0, cached_mat)

			# Position
			if is_instance_valid(unit.mesh):
				indicator.position = unit.mesh.position
				indicator.position.y = unit.mesh.scale.y * 2.0 + 1.5

			_effects_container.add_child(indicator)
			_stance_indicators[unit_id] = indicator


## PERFORMANCE: Initialize cached stance indicator meshes and materials.
## This is called once at startup to avoid per-frame allocations.
func _initialize_stance_indicator_cache() -> void:
	# Pre-create meshes for each stance type
	var prism := PrismMesh.new()
	prism.size = Vector3(0.6, 0.6, 0.3)
	_stance_meshes[UnitStance.AGGRESSIVE] = prism

	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.5, 0.2)
	_stance_meshes[UnitStance.DEFENSIVE] = box

	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.4
	_stance_meshes[UnitStance.HOLD_POSITION] = cyl

	# Pre-create materials for each stance color
	for stance in STANCE_COLORS:
		var color: Color = STANCE_COLORS[stance]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_stance_materials[stance] = mat


## Update veterancy star indicators above veteran units.
func _update_veterancy_indicators() -> void:
	# Clean up indicators for dead/removed units
	var units_to_remove: Array[int] = []
	for unit_id in _veterancy_indicators:
		var found := false
		for unit in _units:
			if unit.get("id", -1) == unit_id and not unit.is_dead:
				found = true
				break
		if not found:
			var indicator: Label3D = _veterancy_indicators[unit_id]
			if is_instance_valid(indicator):
				indicator.queue_free()
			units_to_remove.append(unit_id)

	for unit_id in units_to_remove:
		_veterancy_indicators.erase(unit_id)

	# Update or create indicators for veteran units
	for unit in _units:
		if unit.is_dead:
			continue
		if not is_instance_valid(unit.mesh):
			continue

		var unit_id: int = unit.get("id", -1)
		if unit_id == -1:
			continue

		var vet_level: int = unit.get("veterancy_level", 0)

		if vet_level == 0:
			# Remove indicator if unit lost veterancy (shouldn't happen but safety)
			if _veterancy_indicators.has(unit_id):
				var indicator: Label3D = _veterancy_indicators[unit_id]
				if is_instance_valid(indicator):
					indicator.queue_free()
				_veterancy_indicators.erase(unit_id)
			continue

		# Create star text based on level
		var stars := ""
		for i in range(vet_level):
			stars += "★"

		if _veterancy_indicators.has(unit_id):
			# Update existing indicator
			var indicator: Label3D = _veterancy_indicators[unit_id]
			if is_instance_valid(indicator):
				indicator.position = unit.mesh.position
				indicator.position.y = unit.mesh.scale.y * 2.5 + 2.0
				if indicator.text != stars:
					indicator.text = stars
		else:
			# Create new indicator
			var indicator := Label3D.new()
			indicator.name = "VeterancyStars_%d" % unit_id
			indicator.text = stars
			indicator.font_size = 32
			indicator.modulate = Color(1.0, 0.85, 0.2)  # Gold stars
			indicator.outline_modulate = Color(0.3, 0.2, 0.0)
			indicator.outline_size = 4
			indicator.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			indicator.no_depth_test = true
			indicator.position = unit.mesh.position
			indicator.position.y = unit.mesh.scale.y * 2.5 + 2.0

			_effects_container.add_child(indicator)
			_veterancy_indicators[unit_id] = indicator


func _setup_audio() -> void:
	# Create 2D audio player pool
	for i in AUDIO_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = "Master"
		add_child(player)
		_audio_players.append(player)

	# Create 3D audio player pool
	for i in AUDIO_3D_POOL_SIZE:
		var player := AudioStreamPlayer3D.new()
		player.bus = "Master"
		player.max_distance = 200.0
		player.unit_size = 20.0
		add_child(player)
		_audio_3d_players.append(player)

	# Initialize AudioManager for advanced audio features
	_audio_manager = AudioManager.new()
	_audio_manager.initialize(get_tree())

	# Initialize battle intensity tracker for dynamic music
	_battle_intensity_tracker = BattleIntensityTracker.new()
	_battle_intensity_tracker.combat_started.connect(_on_combat_started)
	_battle_intensity_tracker.combat_ended.connect(_on_combat_ended)
	_battle_intensity_tracker.intensity_spike.connect(_on_intensity_spike)
	print("  AudioManager: OK (dynamic music, UI sounds)")
	print("  BattleIntensityTracker: OK (combat → music intensity)")


## Setup selection box UI overlay.
func _setup_selection_box() -> void:
	# Create a ColorRect for the selection box (added to UI layer)
	_selection_box = ColorRect.new()
	_selection_box.name = "SelectionBox"
	_selection_box.visible = false
	_selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Green selection box with transparency
	_selection_box.color = Color(0.3, 1.0, 0.3, 0.15)

	# Add to UI canvas layer
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(_selection_box)

	# Create a border for the selection box
	var border := ReferenceRect.new()
	border.name = "Border"
	border.border_color = Color(0.3, 1.0, 0.3, 0.8)
	border.border_width = 2.0
	border.editor_only = false
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selection_box.add_child(border)


## Setup faction selection screen shown before match starts.
func _setup_faction_select() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if not ui_layer:
		return

	# Create main panel that covers the screen
	_faction_select_panel = Control.new()
	_faction_select_panel.name = "FactionSelectPanel"
	_faction_select_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_faction_select_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(_faction_select_panel)

	# Dark overlay
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.05, 0.05, 0.1, 0.95)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faction_select_panel.add_child(overlay)

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "AGI DAY: The Awakening"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.position = Vector2(-200, 50)
	title.size = Vector2(400, 60)
	_faction_select_panel.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Choose Your Faction"
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	subtitle.position = Vector2(-200, 110)
	subtitle.size = Vector2(400, 40)
	_faction_select_panel.add_child(subtitle)

	# Create faction buttons container
	var button_container := HBoxContainer.new()
	button_container.name = "FactionButtons"
	button_container.set_anchors_preset(Control.PRESET_CENTER)
	button_container.position = Vector2(-500, -100)
	button_container.size = Vector2(1000, 300)
	button_container.add_theme_constant_override("separation", 20)
	_faction_select_panel.add_child(button_container)

	# Create a button for each faction
	for faction_id in [1, 2, 3, 4]:
		var info: Dictionary = FACTION_INFO.get(faction_id, {})
		var faction_button := _create_faction_button(faction_id, info)
		button_container.add_child(faction_button)

	# Instructions
	var instructions := Label.new()
	instructions.text = "Click a faction to select | SPACE to start | I for Unit Info"
	instructions.add_theme_font_size_override("font_size", 20)
	instructions.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	instructions.position = Vector2(-300, -80)
	instructions.size = Vector2(600, 30)
	_faction_select_panel.add_child(instructions)

	# Tutorial hint
	var tutorial_hint := Label.new()
	tutorial_hint.text = "Press F2 for Tutorial | H for Hotkeys"
	tutorial_hint.add_theme_font_size_override("font_size", 14)
	tutorial_hint.add_theme_color_override("font_color", Color(0.4, 0.6, 0.9))
	tutorial_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tutorial_hint.position = Vector2(-200, -50)
	tutorial_hint.size = Vector2(400, 24)
	_faction_select_panel.add_child(tutorial_hint)


## Create a faction selection button.
func _create_faction_button(faction_id: int, info: Dictionary) -> Control:
	var container := VBoxContainer.new()
	container.name = "Faction%d" % faction_id
	container.custom_minimum_size = Vector2(220, 280)

	# Button style
	var style := StyleBoxFlat.new()
	var faction_color: Color = info.get("color", Color.WHITE)
	style.bg_color = Color(faction_color.r * 0.2, faction_color.g * 0.2, faction_color.b * 0.2, 0.8)
	style.border_color = faction_color
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(15)

	# Main button
	var button := Button.new()
	button.name = "Button"
	button.flat = false
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", style)

	# Hover style
	var hover_style := style.duplicate()
	hover_style.bg_color = Color(faction_color.r * 0.4, faction_color.g * 0.4, faction_color.b * 0.4, 0.9)
	button.add_theme_stylebox_override("hover", hover_style)

	# Pressed style
	var pressed_style := style.duplicate()
	pressed_style.bg_color = Color(faction_color.r * 0.5, faction_color.g * 0.5, faction_color.b * 0.5, 1.0)
	pressed_style.border_color = Color.WHITE
	button.add_theme_stylebox_override("pressed", pressed_style)

	button.pressed.connect(_on_faction_selected.bind(faction_id))

	# Button content container
	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 10)
	button.add_child(content)

	# Faction name
	var name_label := Label.new()
	name_label.text = info.get("name", "Unknown")
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", faction_color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(name_label)

	# Color preview box
	var color_box := ColorRect.new()
	color_box.color = faction_color
	color_box.custom_minimum_size = Vector2(180, 60)
	content.add_child(color_box)

	# Faction description
	var desc_label := Label.new()
	desc_label.text = info.get("desc", "")
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(180, 80)
	content.add_child(desc_label)

	container.add_child(button)
	return container


## Handle faction button click.
func _on_faction_selected(faction_id: int) -> void:
	_play_ui_sound("click")
	_player_faction = faction_id
	var info: Dictionary = FACTION_INFO.get(faction_id, {})
	print("Selected faction: %s (ID: %d)" % [info.get("name", "Unknown"), faction_id])

	# Update button visuals to show selection
	_update_faction_button_selection()


## Update faction buttons to show current selection.
func _update_faction_button_selection() -> void:
	if _faction_select_panel == null:
		return

	var button_container: HBoxContainer = _faction_select_panel.get_node_or_null("FactionButtons")
	if not button_container:
		return

	for i in range(button_container.get_child_count()):
		var container: Control = button_container.get_child(i)
		var button: Button = container.get_node_or_null("Button")
		if not button:
			continue

		var faction_id: int = i + 1
		var info: Dictionary = FACTION_INFO.get(faction_id, {})
		var faction_color: Color = info.get("color", Color.WHITE)

		if faction_id == _player_faction:
			# Selected - bright border
			var selected_style := StyleBoxFlat.new()
			selected_style.bg_color = Color(faction_color.r * 0.5, faction_color.g * 0.5, faction_color.b * 0.5, 0.95)
			selected_style.border_color = Color.WHITE
			selected_style.set_border_width_all(5)
			selected_style.set_corner_radius_all(10)
			selected_style.set_content_margin_all(15)
			button.add_theme_stylebox_override("normal", selected_style)
		else:
			# Not selected - dim
			var normal_style := StyleBoxFlat.new()
			normal_style.bg_color = Color(faction_color.r * 0.15, faction_color.g * 0.15, faction_color.b * 0.15, 0.6)
			normal_style.border_color = faction_color * 0.6
			normal_style.set_border_width_all(2)
			normal_style.set_corner_radius_all(10)
			normal_style.set_content_margin_all(15)
			button.add_theme_stylebox_override("normal", normal_style)


## Toggle faction info viewer panel.
func _toggle_faction_info() -> void:
	_faction_info_visible = not _faction_info_visible
	if _faction_info_visible:
		_show_faction_info()
	else:
		_hide_faction_info()


## Show faction info viewer with unit character sheets.
func _show_faction_info() -> void:
	_play_ui_sound("click")

	# Hide faction selection panel
	if _faction_select_panel:
		_faction_select_panel.visible = false

	# Create faction info panel if needed
	if _faction_info_panel == null:
		_create_faction_info_panel()

	_faction_info_panel.visible = true
	_update_faction_info_display()


## Hide faction info viewer.
func _hide_faction_info() -> void:
	_play_ui_sound("click")
	_faction_info_visible = false

	if _faction_info_panel:
		_faction_info_panel.visible = false

	# Show faction selection panel again
	if _faction_select_panel:
		_faction_select_panel.visible = true


## Create the faction info panel with unit character sheets.
func _create_faction_info_panel() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if not ui_layer:
		return

	_faction_info_panel = Control.new()
	_faction_info_panel.name = "FactionInfoPanel"
	_faction_info_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_faction_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(_faction_info_panel)

	# Dark futuristic overlay with gradient
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.02, 0.03, 0.08, 0.97)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_faction_info_panel.add_child(overlay)

	# Animated grid lines background (futuristic feel)
	_add_grid_lines_background(_faction_info_panel)

	# Header container
	var header := _create_faction_info_header()
	_faction_info_panel.add_child(header)

	# Navigation buttons (left/right arrows to switch factions)
	_add_faction_navigation_buttons(_faction_info_panel)

	# Unit cards container - horizontal layout
	var cards_container := HBoxContainer.new()
	cards_container.name = "UnitCardsContainer"
	cards_container.set_anchors_preset(Control.PRESET_CENTER)
	cards_container.position = Vector2(-560, -50)
	cards_container.size = Vector2(1120, 450)
	cards_container.add_theme_constant_override("separation", 20)
	_faction_info_panel.add_child(cards_container)

	# Create character sheet card for each unit weight class (uses faction-specific templates)
	for weight_class in ["light", "medium", "heavy", "harvester"]:
		var card := _create_unit_character_card(weight_class)
		cards_container.add_child(card)

	# Instructions at bottom
	var instructions := Label.new()
	instructions.text = "← → Switch Faction | ESC or I to Close | SPACE to Start Match"
	instructions.add_theme_font_size_override("font_size", 18)
	instructions.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	instructions.position = Vector2(-300, -30)
	instructions.size = Vector2(600, 30)
	_faction_info_panel.add_child(instructions)


## Add futuristic grid lines background.
func _add_grid_lines_background(parent: Control) -> void:
	var grid := Control.new()
	grid.name = "GridLines"
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(grid)

	# Create horizontal and vertical lines
	var line_color := Color(0.1, 0.2, 0.3, 0.15)
	var spacing := 60

	# Horizontal lines
	for i in range(0, 20):
		var line := ColorRect.new()
		line.color = line_color
		line.set_anchors_preset(Control.PRESET_TOP_WIDE)
		line.position.y = i * spacing
		line.size = Vector2(2000, 1)
		grid.add_child(line)

	# Vertical lines
	for i in range(0, 35):
		var line := ColorRect.new()
		line.color = line_color
		line.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		line.position.x = i * spacing
		line.size = Vector2(1, 1200)
		grid.add_child(line)


## Create faction info header with name and description.
func _create_faction_info_header() -> Control:
	var header := Control.new()
	header.name = "Header"
	header.set_anchors_preset(Control.PRESET_CENTER_TOP)
	header.position = Vector2(-400, 20)
	header.size = Vector2(800, 120)

	# Faction name (will be updated dynamically)
	var name_label := Label.new()
	name_label.name = "FactionName"
	name_label.add_theme_font_size_override("font_size", 42)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(0, 10)
	name_label.size = Vector2(800, 50)
	header.add_child(name_label)

	# Faction description
	var desc_label := Label.new()
	desc_label.name = "FactionDesc"
	desc_label.add_theme_font_size_override("font_size", 18)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.position = Vector2(0, 65)
	desc_label.size = Vector2(800, 30)
	header.add_child(desc_label)

	# Decorative line under header
	var line := ColorRect.new()
	line.name = "HeaderLine"
	line.position = Vector2(100, 100)
	line.size = Vector2(600, 2)
	header.add_child(line)

	return header


## Add left/right navigation buttons to switch factions.
func _add_faction_navigation_buttons(parent: Control) -> void:
	# Left arrow button
	var left_btn := Button.new()
	left_btn.name = "LeftArrow"
	left_btn.text = "◀"
	left_btn.add_theme_font_size_override("font_size", 36)
	left_btn.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	left_btn.position = Vector2(30, -50)
	left_btn.size = Vector2(60, 100)
	left_btn.pressed.connect(_faction_info_prev)

	var left_style := StyleBoxFlat.new()
	left_style.bg_color = Color(0.1, 0.15, 0.25, 0.8)
	left_style.border_color = Color(0.3, 0.5, 0.7)
	left_style.set_border_width_all(2)
	left_style.set_corner_radius_all(8)
	left_btn.add_theme_stylebox_override("normal", left_style)
	parent.add_child(left_btn)

	# Right arrow button
	var right_btn := Button.new()
	right_btn.name = "RightArrow"
	right_btn.text = "▶"
	right_btn.add_theme_font_size_override("font_size", 36)
	right_btn.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right_btn.position = Vector2(-90, -50)
	right_btn.size = Vector2(60, 100)
	right_btn.pressed.connect(_faction_info_next)

	var right_style := left_style.duplicate()
	right_btn.add_theme_stylebox_override("normal", right_style)
	parent.add_child(right_btn)


## Switch to previous faction in info viewer.
func _faction_info_prev() -> void:
	_play_ui_sound("click")
	_player_faction -= 1
	if _player_faction < 1:
		_player_faction = 4
	_update_faction_info_display()
	_update_faction_button_selection()


## Switch to next faction in info viewer.
func _faction_info_next() -> void:
	_play_ui_sound("click")
	_player_faction += 1
	if _player_faction > 4:
		_player_faction = 1
	_update_faction_info_display()
	_update_faction_button_selection()


## Create a character sheet card for a unit type.
func _create_unit_character_card(unit_type: String) -> Control:
	var card := PanelContainer.new()
	card.name = "Card_" + unit_type
	card.custom_minimum_size = Vector2(260, 450)

	# Card style - futuristic panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.9)
	style.border_color = Color(0.2, 0.4, 0.6, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)

	# Unit title
	var title := Label.new()
	title.name = "UnitTitle"
	title.text = UNIT_DISPLAY_NAMES.get(unit_type, unit_type.capitalize())
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)

	# 3D viewport for rotating model
	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "ViewportContainer"
	viewport_container.custom_minimum_size = Vector2(240, 180)
	viewport_container.stretch = true
	content.add_child(viewport_container)

	var viewport := SubViewport.new()
	viewport.name = "ModelViewport"
	viewport.size = Vector2i(240, 180)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true  # CRITICAL: Each viewport needs its own 3D world!
	viewport_container.add_child(viewport)

	# Store viewport reference for rotation updates
	_faction_info_viewports.append(viewport)

	# Create camera for viewport
	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.position = Vector3(0, 2, 6)
	cam.fov = 40
	viewport.add_child(cam)
	# look_at must be called AFTER node is in tree
	cam.look_at(Vector3(0, 1, 0), Vector3.UP)

	# Add lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.light_energy = 1.5
	viewport.add_child(light)

	var ambient := DirectionalLight3D.new()
	ambient.rotation_degrees = Vector3(45, -135, 0)
	ambient.light_energy = 0.5
	viewport.add_child(ambient)

	# Model container (will be populated with actual model)
	var model_container := Node3D.new()
	model_container.name = "ModelContainer_" + unit_type
	viewport.add_child(model_container)
	_faction_info_models.append(model_container)

	# Role description
	var role := Label.new()
	role.name = "RoleDesc"
	role.text = UNIT_ROLE_DESC.get(unit_type, "")
	role.add_theme_font_size_override("font_size", 11)
	role.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	role.custom_minimum_size = Vector2(240, 36)
	content.add_child(role)

	# Separator line
	var sep := ColorRect.new()
	sep.name = "Separator"
	sep.custom_minimum_size = Vector2(220, 1)
	sep.color = Color(0.3, 0.5, 0.7, 0.5)
	content.add_child(sep)

	# Stats container
	var stats := VBoxContainer.new()
	stats.name = "StatsContainer"
	stats.add_theme_constant_override("separation", 4)
	content.add_child(stats)

	# Add stat rows (will be populated with actual values)
	_add_stat_row(stats, "HP", "health", "❤")
	_add_stat_row(stats, "DMG", "damage", "⚔")
	_add_stat_row(stats, "SPD", "speed", "⚡")
	_add_stat_row(stats, "ATK/s", "attack_speed", "🔫")
	_add_stat_row(stats, "RNG", "range", "🎯")
	_add_stat_row(stats, "DPS", "dps", "💀")

	# Store unit type in card metadata
	card.set_meta("unit_type", unit_type)

	# Make card clickable for detailed spec view
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_unit_card_clicked.bind(unit_type))

	# Add hover effect
	card.mouse_entered.connect(_on_unit_card_hover.bind(card, true))
	card.mouse_exited.connect(_on_unit_card_hover.bind(card, false))

	return card


## Handle unit card hover effect.
func _on_unit_card_hover(card: PanelContainer, is_hovered: bool) -> void:
	var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if is_hovered:
		style.border_color = style.border_color.lightened(0.3)
		style.bg_color = style.bg_color.lightened(0.1)
	card.add_theme_stylebox_override("panel", style)


## Handle unit card click to show detailed spec popup.
func _on_unit_card_clicked(event: InputEvent, weight_class: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_ui_sound("click")
		_show_unit_spec_popup(weight_class)


## Add a stat row to the stats container.
func _add_stat_row(container: VBoxContainer, label: String, stat_key: String, icon: String) -> void:
	var row := HBoxContainer.new()
	row.name = "Stat_" + stat_key
	row.add_theme_constant_override("separation", 8)

	# Icon
	var icon_label := Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.custom_minimum_size = Vector2(24, 20)
	row.add_child(icon_label)

	# Stat name
	var name_label := Label.new()
	name_label.text = label + ":"
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	name_label.custom_minimum_size = Vector2(50, 20)
	row.add_child(name_label)

	# Stat value (will be updated dynamically)
	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = "---"
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	# Stat bar background
	var bar_bg := ColorRect.new()
	bar_bg.name = "BarBg"
	bar_bg.custom_minimum_size = Vector2(60, 8)
	bar_bg.color = Color(0.1, 0.15, 0.2, 0.8)
	row.add_child(bar_bg)

	# Stat bar fill (will be sized dynamically)
	var bar_fill := ColorRect.new()
	bar_fill.name = "BarFill"
	bar_fill.position = Vector2(0, 0)
	bar_fill.size = Vector2(0, 8)
	bar_fill.color = Color(0.3, 0.7, 1.0)
	bar_bg.add_child(bar_fill)

	container.add_child(row)


## Show the unit spec popup with detailed blueprint view.
func _show_unit_spec_popup(weight_class: String) -> void:
	_unit_spec_current_weight_class = weight_class
	_unit_spec_current_template = _get_faction_template_for_class(_player_faction, weight_class)

	if _unit_spec_popup == null:
		_create_unit_spec_popup()

	_update_unit_spec_content()
	_unit_spec_popup.visible = true
	_unit_spec_visible = true

	# Start combat preview simulation
	_start_combat_preview()


## Hide the unit spec popup.
func _hide_unit_spec_popup() -> void:
	if _unit_spec_popup:
		_unit_spec_popup.visible = false
	_unit_spec_visible = false
	_stop_combat_preview()


## Create the unit spec popup with blueprint styling.
func _create_unit_spec_popup() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if not ui_layer:
		return

	_unit_spec_popup = Control.new()
	_unit_spec_popup.name = "UnitSpecPopup"
	_unit_spec_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_unit_spec_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_layer.add_child(_unit_spec_popup)

	# Dark overlay with slight transparency
	var overlay := ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.01, 0.02, 0.04, 0.95)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.gui_input.connect(_on_spec_overlay_click)
	_unit_spec_popup.add_child(overlay)

	# Blueprint grid background
	_add_blueprint_grid(_unit_spec_popup)

	# Main content panel - centered
	var main_panel := PanelContainer.new()
	main_panel.name = "MainPanel"
	main_panel.set_anchors_preset(Control.PRESET_CENTER)
	main_panel.position = Vector2(-550, -320)
	main_panel.size = Vector2(1100, 640)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.04, 0.08, 0.98)
	panel_style.border_color = Color(0.15, 0.4, 0.6, 0.9)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(20)
	main_panel.add_theme_stylebox_override("panel", panel_style)
	_unit_spec_popup.add_child(main_panel)

	# Main horizontal split
	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 30)
	main_panel.add_child(main_hbox)

	# Left side - Large model viewport
	var left_panel := _create_spec_model_panel()
	main_hbox.add_child(left_panel)

	# Right side - Info and combat preview
	var right_panel := _create_spec_info_panel()
	main_hbox.add_child(right_panel)

	# Close button (X in corner)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.position = Vector2(-60, 10)
	close_btn.size = Vector2(50, 50)
	close_btn.pressed.connect(_hide_unit_spec_popup)

	var close_style := StyleBoxFlat.new()
	close_style.bg_color = Color(0.2, 0.1, 0.1, 0.8)
	close_style.border_color = Color(0.6, 0.2, 0.2)
	close_style.set_border_width_all(2)
	close_style.set_corner_radius_all(4)
	close_btn.add_theme_stylebox_override("normal", close_style)
	main_panel.add_child(close_btn)

	# Instructions at bottom
	var hint := Label.new()
	hint.text = "ESC or click outside to close"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.position.y = -30
	main_panel.add_child(hint)


## Add blueprint grid background.
func _add_blueprint_grid(parent: Control) -> void:
	var grid := Control.new()
	grid.name = "BlueprintGrid"
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(grid)

	# Blueprint blue color scheme
	var line_color := Color(0.05, 0.15, 0.25, 0.3)
	var major_line_color := Color(0.08, 0.2, 0.35, 0.4)
	var spacing := 40
	var major_spacing := 200

	# Draw grid lines
	for i in range(0, 50):
		var is_major := (i * spacing) % major_spacing == 0
		var color: Color = major_line_color if is_major else line_color
		var width: float = 2.0 if is_major else 1.0

		# Horizontal
		var h_line := ColorRect.new()
		h_line.color = color
		h_line.set_anchors_preset(Control.PRESET_TOP_WIDE)
		h_line.position.y = i * spacing
		h_line.size = Vector2(2000, width)
		grid.add_child(h_line)

		# Vertical
		var v_line := ColorRect.new()
		v_line.color = color
		v_line.set_anchors_preset(Control.PRESET_LEFT_WIDE)
		v_line.position.x = i * spacing
		v_line.size = Vector2(width, 1200)
		grid.add_child(v_line)

	# Corner markers (technical drawing style)
	_add_corner_markers(grid)


## Add technical corner markers.
func _add_corner_markers(parent: Control) -> void:
	var marker_color := Color(0.2, 0.5, 0.7, 0.6)
	var positions := [
		Vector2(50, 50), Vector2(1870, 50),
		Vector2(50, 1030), Vector2(1870, 1030)
	]

	for pos in positions:
		# Horizontal line
		var h_mark := ColorRect.new()
		h_mark.color = marker_color
		h_mark.position = pos
		h_mark.size = Vector2(30, 2)
		parent.add_child(h_mark)

		# Vertical line
		var v_mark := ColorRect.new()
		v_mark.color = marker_color
		v_mark.position = pos
		v_mark.size = Vector2(2, 30)
		parent.add_child(v_mark)


## Create the left panel with large model viewport.
func _create_spec_model_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "ModelPanel"
	panel.custom_minimum_size = Vector2(450, 580)
	panel.add_theme_constant_override("separation", 10)

	# Unit designation header
	var header := Label.new()
	header.name = "UnitDesignation"
	header.text = "UNIT DESIGNATION"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.4, 0.6, 0.8))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(header)

	# Unit name (large)
	var name_label := Label.new()
	name_label.name = "UnitName"
	name_label.text = "UNIT NAME"
	name_label.add_theme_font_size_override("font_size", 32)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(name_label)

	# Classification badge
	var class_badge := _create_classification_badge()
	panel.add_child(class_badge)

	# Large 3D viewport
	var viewport_frame := PanelContainer.new()
	viewport_frame.name = "ViewportFrame"
	viewport_frame.custom_minimum_size = Vector2(420, 320)

	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.01, 0.02, 0.04, 0.9)
	frame_style.border_color = Color(0.1, 0.3, 0.5, 0.8)
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(2)
	viewport_frame.add_theme_stylebox_override("panel", frame_style)
	panel.add_child(viewport_frame)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "SpecViewportContainer"
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	viewport_frame.add_child(viewport_container)

	_unit_spec_viewport = SubViewport.new()
	_unit_spec_viewport.name = "SpecModelViewport"
	_unit_spec_viewport.size = Vector2i(420, 320)
	_unit_spec_viewport.transparent_bg = true
	_unit_spec_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_unit_spec_viewport.own_world_3d = true
	viewport_container.add_child(_unit_spec_viewport)

	# Camera
	var cam := Camera3D.new()
	cam.name = "SpecCamera"
	cam.position = Vector3(0, 3, 8)
	cam.fov = 35
	_unit_spec_viewport.add_child(cam)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)

	# Lighting - dramatic
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-35, 45, 0)
	key_light.light_energy = 1.8
	key_light.light_color = Color(0.9, 0.95, 1.0)
	_unit_spec_viewport.add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(20, -120, 0)
	fill_light.light_energy = 0.4
	fill_light.light_color = Color(0.6, 0.7, 0.9)
	_unit_spec_viewport.add_child(fill_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-10, 180, 0)
	rim_light.light_energy = 0.6
	rim_light.light_color = Color(0.4, 0.6, 0.8)
	_unit_spec_viewport.add_child(rim_light)

	# Model container
	_unit_spec_model_container = Node3D.new()
	_unit_spec_model_container.name = "SpecModelContainer"
	_unit_spec_viewport.add_child(_unit_spec_model_container)

	# Technical specs below viewport
	var tech_specs := _create_technical_specs_panel()
	panel.add_child(tech_specs)

	return panel


## Create classification badge.
func _create_classification_badge() -> Control:
	var container := CenterContainer.new()
	container.name = "ClassificationBadge"

	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.1, 0.2, 0.3, 0.8)
	badge_style.border_color = Color(0.2, 0.4, 0.6)
	badge_style.set_border_width_all(1)
	badge_style.set_corner_radius_all(2)
	badge_style.set_content_margin_all(6)
	badge.add_theme_stylebox_override("panel", badge_style)
	container.add_child(badge)

	var badge_label := Label.new()
	badge_label.name = "ClassLabel"
	badge_label.text = "LIGHT COMBAT UNIT"
	badge_label.add_theme_font_size_override("font_size", 11)
	badge_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	badge.add_child(badge_label)

	return container


## Create technical specs mini-panel.
func _create_technical_specs_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "TechSpecs"
	panel.add_theme_constant_override("separation", 4)

	# Header
	var header := Label.new()
	header.text = "─── TECHNICAL SPECIFICATIONS ───"
	header.add_theme_font_size_override("font_size", 10)
	header.add_theme_color_override("font_color", Color(0.3, 0.5, 0.6))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(header)

	# Specs grid
	var grid := GridContainer.new()
	grid.name = "SpecsGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 15)
	grid.add_theme_constant_override("v_separation", 2)
	panel.add_child(grid)

	# Will be populated with actual specs
	var spec_items := [
		["MASS", "---", "ARMOR", "---"],
		["PWR", "---", "COST", "---"]
	]

	for row in spec_items:
		for i in range(0, row.size(), 2):
			var label := Label.new()
			label.name = "Spec_" + row[i]
			label.text = row[i] + ":"
			label.add_theme_font_size_override("font_size", 10)
			label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
			grid.add_child(label)

			var value := Label.new()
			value.name = "SpecVal_" + row[i]
			value.text = row[i + 1]
			value.add_theme_font_size_override("font_size", 10)
			value.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
			grid.add_child(value)

	return panel


## Create the right panel with stats and combat preview.
func _create_spec_info_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "InfoPanel"
	panel.custom_minimum_size = Vector2(550, 580)
	panel.add_theme_constant_override("separation", 15)

	# Faction badge
	var faction_header := _create_faction_header()
	panel.add_child(faction_header)

	# Description panel
	var desc_panel := _create_description_panel()
	panel.add_child(desc_panel)

	# Stats panel (large detailed version)
	var stats_panel := _create_detailed_stats_panel()
	panel.add_child(stats_panel)

	# Abilities panel
	var abilities_panel := _create_abilities_panel()
	panel.add_child(abilities_panel)

	# Combat preview (small action window)
	var combat_panel := _create_combat_preview_panel()
	panel.add_child(combat_panel)

	return panel


## Create faction header badge.
func _create_faction_header() -> Control:
	var container := HBoxContainer.new()
	container.name = "FactionHeader"
	container.add_theme_constant_override("separation", 10)

	var faction_icon := Label.new()
	faction_icon.name = "FactionIcon"
	faction_icon.text = "◆"
	faction_icon.add_theme_font_size_override("font_size", 20)
	container.add_child(faction_icon)

	var faction_name := Label.new()
	faction_name.name = "FactionName"
	faction_name.text = "FACTION NAME"
	faction_name.add_theme_font_size_override("font_size", 16)
	container.add_child(faction_name)

	return container


## Create description panel.
func _create_description_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "DescriptionPanel"

	var desc_style := StyleBoxFlat.new()
	desc_style.bg_color = Color(0.03, 0.05, 0.08, 0.8)
	desc_style.border_color = Color(0.1, 0.2, 0.3, 0.6)
	desc_style.set_border_width_all(1)
	desc_style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", desc_style)

	var desc_label := Label.new()
	desc_label.name = "Description"
	desc_label.text = "Unit description goes here..."
	desc_label.add_theme_font_size_override("font_size", 13)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(520, 60)
	panel.add_child(desc_label)

	return panel


## Create detailed stats panel.
func _create_detailed_stats_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "DetailedStatsPanel"
	panel.add_theme_constant_override("separation", 6)

	# Header
	var header := Label.new()
	header.text = "━━━ COMBAT STATISTICS ━━━"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(header)

	# Stats in two columns
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	panel.add_child(columns)

	var left_stats := VBoxContainer.new()
	left_stats.name = "LeftStats"
	left_stats.add_theme_constant_override("separation", 4)
	columns.add_child(left_stats)

	var right_stats := VBoxContainer.new()
	right_stats.name = "RightStats"
	right_stats.add_theme_constant_override("separation", 4)
	columns.add_child(right_stats)

	# Add detailed stat rows
	_add_detailed_stat_row(left_stats, "HEALTH", "health", Color(0.2, 0.8, 0.3))
	_add_detailed_stat_row(left_stats, "DAMAGE", "damage", Color(1.0, 0.4, 0.3))
	_add_detailed_stat_row(left_stats, "DPS", "dps", Color(1.0, 0.6, 0.2))
	_add_detailed_stat_row(right_stats, "SPEED", "speed", Color(0.3, 0.7, 1.0))
	_add_detailed_stat_row(right_stats, "RANGE", "range", Color(0.8, 0.5, 1.0))
	_add_detailed_stat_row(right_stats, "ATTACK RATE", "attack_speed", Color(0.9, 0.9, 0.3))

	return panel


## Add a detailed stat row with large bar.
func _add_detailed_stat_row(container: VBoxContainer, label: String, stat_key: String, color: Color) -> void:
	var row := VBoxContainer.new()
	row.name = "DetailedStat_" + stat_key
	row.add_theme_constant_override("separation", 2)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)

	var name_label := Label.new()
	name_label.text = label
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	name_label.custom_minimum_size = Vector2(100, 16)
	header.add_child(name_label)

	var value_label := Label.new()
	value_label.name = "Value"
	value_label.text = "0"
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", color)
	header.add_child(value_label)

	row.add_child(header)

	# Large bar
	var bar_bg := ColorRect.new()
	bar_bg.name = "BarBg"
	bar_bg.custom_minimum_size = Vector2(200, 10)
	bar_bg.color = Color(0.08, 0.1, 0.15, 0.9)
	row.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.name = "BarFill"
	bar_fill.size = Vector2(0, 10)
	bar_fill.color = color
	bar_bg.add_child(bar_fill)

	container.add_child(row)


## Create abilities panel.
func _create_abilities_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "AbilitiesPanel"
	panel.add_theme_constant_override("separation", 6)

	# Header
	var header := Label.new()
	header.text = "━━━ SPECIAL ABILITIES ━━━"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(header)

	# Abilities container
	var abilities_box := HBoxContainer.new()
	abilities_box.name = "AbilitiesBox"
	abilities_box.add_theme_constant_override("separation", 10)
	panel.add_child(abilities_box)

	return panel


## Create combat preview panel.
func _create_combat_preview_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.name = "CombatPreviewPanel"
	panel.add_theme_constant_override("separation", 6)

	# Header
	var header := Label.new()
	header.text = "━━━ COMBAT PREVIEW ━━━"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(header)

	# Combat viewport frame
	var frame := PanelContainer.new()
	frame.name = "CombatFrame"
	frame.custom_minimum_size = Vector2(520, 100)

	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.02, 0.03, 0.05, 0.9)
	frame_style.border_color = Color(0.15, 0.25, 0.35, 0.8)
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(2)
	frame.add_theme_stylebox_override("panel", frame_style)
	panel.add_child(frame)

	var viewport_container := SubViewportContainer.new()
	viewport_container.name = "CombatViewportContainer"
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_container.stretch = true
	frame.add_child(viewport_container)

	_unit_spec_combat_viewport = SubViewport.new()
	_unit_spec_combat_viewport.name = "CombatViewport"
	_unit_spec_combat_viewport.size = Vector2i(520, 100)
	_unit_spec_combat_viewport.transparent_bg = false
	_unit_spec_combat_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_unit_spec_combat_viewport.own_world_3d = true
	viewport_container.add_child(_unit_spec_combat_viewport)

	# Camera for combat preview (side view)
	var cam := Camera3D.new()
	cam.name = "CombatCamera"
	cam.position = Vector3(0, 5, 12)
	cam.fov = 50
	_unit_spec_combat_viewport.add_child(cam)
	cam.look_at(Vector3(0, 1, 0), Vector3.UP)

	# Lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	light.light_energy = 1.5
	_unit_spec_combat_viewport.add_child(light)

	# Ground plane
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(30, 20)
	ground.mesh = ground_mesh
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.05, 0.08, 0.1)
	ground.material_override = ground_mat
	_unit_spec_combat_viewport.add_child(ground)

	return panel


## Handle click on overlay to close popup.
func _on_spec_overlay_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_unit_spec_popup()


## Update the unit spec popup content.
func _update_unit_spec_content() -> void:
	if _unit_spec_popup == null:
		return

	var main_panel: PanelContainer = _unit_spec_popup.get_node_or_null("MainPanel")
	if main_panel == null:
		return

	var faction_color: Color = FACTION_INFO.get(_player_faction, {}).get("color", Color.WHITE)
	var faction_name: String = FACTION_INFO.get(_player_faction, {}).get("name", "Unknown")

	# Update faction header
	var faction_header: HBoxContainer = main_panel.get_node_or_null("HBoxContainer/InfoPanel/FactionHeader")
	if faction_header:
		var icon: Label = faction_header.get_node_or_null("FactionIcon")
		if icon:
			icon.add_theme_color_override("font_color", faction_color)
		var name_lbl: Label = faction_header.get_node_or_null("FactionName")
		if name_lbl:
			name_lbl.text = faction_name.to_upper()
			name_lbl.add_theme_color_override("font_color", faction_color)

	# Get template info
	var unit_name := _get_weight_class_display_name(_unit_spec_current_weight_class)
	var description := ""
	var abilities: Array = []
	var stats: Dictionary = {}

	if _unit_spec_current_template != null:
		unit_name = _unit_spec_current_template.display_name
		description = _unit_spec_current_template.description
		abilities = _unit_spec_current_template.abilities
		stats = _unit_spec_current_template.base_stats

	# Update unit name
	var model_panel: VBoxContainer = main_panel.get_node_or_null("HBoxContainer/ModelPanel")
	if model_panel:
		var name_label: Label = model_panel.get_node_or_null("UnitName")
		if name_label:
			name_label.text = unit_name.to_upper()
			name_label.add_theme_color_override("font_color", faction_color)

		# Update classification badge
		var badge_container: CenterContainer = model_panel.get_node_or_null("ClassificationBadge")
		if badge_container:
			var badge: PanelContainer = badge_container.get_child(0) as PanelContainer
			if badge:
				var class_label: Label = badge.get_node_or_null("ClassLabel")
				if class_label:
					var class_text := "COMBAT UNIT"
					match _unit_spec_current_weight_class:
						"light": class_text = "LIGHT ASSAULT UNIT"
						"medium": class_text = "MEDIUM COMBAT UNIT"
						"heavy": class_text = "HEAVY SIEGE UNIT"
						"harvester": class_text = "RESOURCE HARVESTER"
					class_label.text = class_text

		# Update technical specs
		_update_technical_specs(model_panel, stats)

	# Update description
	var info_panel: VBoxContainer = main_panel.get_node_or_null("HBoxContainer/InfoPanel")
	if info_panel:
		var desc_panel: PanelContainer = info_panel.get_node_or_null("DescriptionPanel")
		if desc_panel:
			var desc_label: Label = desc_panel.get_node_or_null("Description")
			if desc_label:
				desc_label.text = description if description != "" else "A specialized combat unit designed for battlefield dominance."

		# Update detailed stats
		_update_detailed_stats(info_panel, stats)

		# Update abilities
		_update_abilities_display(info_panel, abilities, faction_color)

	# Update 3D model
	_update_spec_model(faction_color)


## Update technical specs display.
func _update_technical_specs(panel: VBoxContainer, stats: Dictionary) -> void:
	var tech_specs: VBoxContainer = panel.get_node_or_null("TechSpecs")
	if tech_specs == null:
		return

	var grid: GridContainer = tech_specs.get_node_or_null("SpecsGrid")
	if grid == null:
		return

	# Get values from stats
	var mass: float = stats.get("mass", stats.get("max_health", 100.0))
	var armor: float = stats.get("armor", 0.0) * 100  # Convert to percentage
	var power: float = stats.get("base_damage", 10.0) * stats.get("attack_speed", 1.0)
	var cost: float = 0.0

	if _unit_spec_current_template != null:
		var prod_cost: Dictionary = _unit_spec_current_template.production_cost
		cost = prod_cost.get("ree", 50.0)

	# Update values
	var mass_val: Label = grid.get_node_or_null("SpecVal_MASS")
	if mass_val:
		mass_val.text = "%d kg" % int(mass)

	var armor_val: Label = grid.get_node_or_null("SpecVal_ARMOR")
	if armor_val:
		armor_val.text = "%.0f%%" % armor

	var pwr_val: Label = grid.get_node_or_null("SpecVal_PWR")
	if pwr_val:
		pwr_val.text = "%.1f" % power

	var cost_val: Label = grid.get_node_or_null("SpecVal_COST")
	if cost_val:
		cost_val.text = "%d REE" % int(cost)


## Update detailed stats bars.
func _update_detailed_stats(panel: VBoxContainer, stats: Dictionary) -> void:
	var stats_panel: VBoxContainer = panel.get_node_or_null("DetailedStatsPanel")
	if stats_panel == null:
		return

	# Get stats values
	var health: float = stats.get("max_health", 100.0)
	var damage: float = stats.get("base_damage", 10.0)
	var speed: float = stats.get("max_speed", 10.0)
	var attack_speed: float = stats.get("attack_speed", 1.0)
	var range_val: float = stats.get("attack_range", 15.0)
	var dps: float = damage * attack_speed

	var stat_values := {
		"health": {"value": health, "max": 400.0},
		"damage": {"value": damage, "max": 100.0},
		"dps": {"value": dps, "max": 100.0},
		"speed": {"value": speed, "max": 25.0},
		"range": {"value": range_val, "max": 50.0},
		"attack_speed": {"value": attack_speed, "max": 3.0}
	}

	# Update both columns
	for col_name in ["LeftStats", "RightStats"]:
		var col: VBoxContainer = stats_panel.get_node_or_null("HBoxContainer/" + col_name)
		if col == null:
			continue

		for child in col.get_children():
			var stat_key: String = child.name.replace("DetailedStat_", "")
			if not stat_values.has(stat_key):
				continue

			var data: Dictionary = stat_values[stat_key]
			var value: float = data["value"]
			var max_val: float = data["max"]

			# Update value label
			var header: HBoxContainer = child.get_node_or_null("HBoxContainer") as HBoxContainer
			if header == null:
				header = child.get_child(0) as HBoxContainer
			if header:
				var value_label: Label = header.get_node_or_null("Value")
				if value_label:
					if stat_key == "attack_speed":
						value_label.text = "%.2f/s" % value
					elif stat_key == "dps":
						value_label.text = "%.1f" % value
					else:
						value_label.text = "%d" % int(value)

			# Update bar
			var bar_bg: ColorRect = child.get_node_or_null("BarBg")
			if bar_bg:
				var bar_fill: ColorRect = bar_bg.get_node_or_null("BarFill")
				if bar_fill:
					var fill_pct: float = clampf(value / max_val, 0.0, 1.0)
					bar_fill.size.x = bar_bg.size.x * fill_pct


## Update abilities display.
func _update_abilities_display(panel: VBoxContainer, abilities: Array, faction_color: Color) -> void:
	var abilities_panel: VBoxContainer = panel.get_node_or_null("AbilitiesPanel")
	if abilities_panel == null:
		return

	var abilities_box: HBoxContainer = abilities_panel.get_node_or_null("AbilitiesBox")
	if abilities_box == null:
		return

	# Clear existing ability badges
	for child in abilities_box.get_children():
		child.queue_free()

	# Add ability badges
	for ability_name in abilities:
		if ability_name is String:
			var badge := _create_ability_badge(ability_name, faction_color)
			abilities_box.add_child(badge)


## Create an ability badge.
func _create_ability_badge(ability_name: String, color: Color) -> Control:
	var badge := PanelContainer.new()
	badge.name = "Ability_" + ability_name

	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.7)
	style.border_color = color.darkened(0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.set_content_margin_all(6)
	badge.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = ability_name.replace("_", " ").capitalize()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", color.lightened(0.2))
	badge.add_child(label)

	return badge


## Update the 3D model in the spec popup.
func _update_spec_model(faction_color: Color) -> void:
	if _unit_spec_model_container == null:
		return

	# Clear existing
	for child in _unit_spec_model_container.get_children():
		child.queue_free()

	# Map weight class to bot type
	var bot_type: String = "soldier"
	match _unit_spec_current_weight_class:
		"light": bot_type = "scout"
		"medium": bot_type = "soldier"
		"heavy": bot_type = "tank"
		"harvester": bot_type = "harvester"

	# Get type data
	var type_data: Dictionary = UNIT_TYPES.get(bot_type, UNIT_TYPES["soldier"]).duplicate()

	if _unit_spec_current_template != null:
		var stats: Dictionary = _unit_spec_current_template.base_stats
		var health: float = stats.get("max_health", 100.0)
		var scale_factor := sqrt(health / 100.0)
		type_data["size"] = Vector3(1.5, 2.0, 1.5) * scale_factor

	# Create model
	var bot := _create_procedural_bot(_player_faction, bot_type, type_data)
	bot.position = Vector3(0, type_data.get("size", Vector3.ONE).y * 0.3, 0)
	bot.scale = Vector3.ONE * 1.5
	_unit_spec_model_container.add_child(bot)


## Start combat preview simulation.
func _start_combat_preview() -> void:
	if _unit_spec_combat_viewport == null:
		return

	# Clear existing units
	_stop_combat_preview()

	# Create friendly unit (the showcased unit)
	var friendly_pos := Vector3(-5, 0, 0)
	var friendly := _create_combat_preview_unit(_player_faction, friendly_pos, true)
	_unit_spec_combat_viewport.add_child(friendly["mesh"])
	_unit_spec_combat_units.append(friendly)

	# Create enemy unit
	var enemy_faction := 2 if _player_faction != 2 else 1
	var enemy_pos := Vector3(5, 0, 0)
	var enemy := _create_combat_preview_unit(enemy_faction, enemy_pos, false)
	_unit_spec_combat_viewport.add_child(enemy["mesh"])
	_unit_spec_combat_units.append(enemy)


## Create a unit for the combat preview.
func _create_combat_preview_unit(faction_id: int, position: Vector3, is_friendly: bool) -> Dictionary:
	var bot_type: String = "soldier"
	if is_friendly:
		match _unit_spec_current_weight_class:
			"light": bot_type = "scout"
			"medium": bot_type = "soldier"
			"heavy": bot_type = "tank"
			"harvester": bot_type = "harvester"

	var type_data: Dictionary = UNIT_TYPES.get(bot_type, UNIT_TYPES["soldier"]).duplicate()
	type_data["size"] = type_data.get("size", Vector3(1.5, 2.0, 1.5)) * 0.8

	var mesh := _create_procedural_bot(faction_id, bot_type, type_data)
	mesh.position = position
	mesh.position.y = type_data.get("size", Vector3.ONE).y * 0.3

	# Face each other
	if is_friendly:
		mesh.rotation.y = 0
	else:
		mesh.rotation.y = PI

	return {
		"mesh": mesh,
		"faction_id": faction_id,
		"is_friendly": is_friendly,
		"attack_timer": randf() * 0.5,
		"position": position
	}


## Stop combat preview simulation.
func _stop_combat_preview() -> void:
	for unit in _unit_spec_combat_units:
		if unit.has("mesh") and is_instance_valid(unit["mesh"]):
			unit["mesh"].queue_free()
	_unit_spec_combat_units.clear()


## Update combat preview animation.
func _update_combat_preview(delta: float) -> void:
	if not _unit_spec_visible or _unit_spec_combat_units.is_empty():
		return

	for unit in _unit_spec_combat_units:
		if not unit.has("mesh") or not is_instance_valid(unit["mesh"]):
			continue

		# Simple attack animation
		unit["attack_timer"] -= delta
		if unit["attack_timer"] <= 0:
			unit["attack_timer"] = randf_range(0.5, 1.5)

			# Flash effect for "shooting"
			var mesh: Node3D = unit["mesh"]
			# Could add muzzle flash here

	# Rotate spec model
	if _unit_spec_model_container != null:
		for child in _unit_spec_model_container.get_children():
			if child is Node3D:
				child.rotation.y += delta * 0.8


## Update the faction info display with current faction data.
func _update_faction_info_display() -> void:
	if _faction_info_panel == null:
		return

	var faction_info: Dictionary = FACTION_INFO.get(_player_faction, {})
	var faction_color: Color = faction_info.get("color", Color.WHITE)

	# Update header
	var header: Control = _faction_info_panel.get_node_or_null("Header")
	if header:
		var name_label: Label = header.get_node_or_null("FactionName")
		if name_label:
			name_label.text = faction_info.get("name", "Unknown")
			name_label.add_theme_color_override("font_color", faction_color)

		var desc_label: Label = header.get_node_or_null("FactionDesc")
		if desc_label:
			desc_label.text = faction_info.get("desc", "")

		var line: ColorRect = header.get_node_or_null("HeaderLine")
		if line:
			line.color = faction_color

	# Update unit cards with faction-specific templates
	var cards_container: HBoxContainer = _faction_info_panel.get_node_or_null("UnitCardsContainer")
	if cards_container == null:
		return

	var weight_classes := ["light", "medium", "heavy", "harvester"]
	var model_index := 0

	for i in range(cards_container.get_child_count()):
		var card: PanelContainer = cards_container.get_child(i) as PanelContainer
		if card == null:
			continue

		var weight_class: String = card.get_meta("unit_type", "")
		if weight_class.is_empty():
			continue

		# Get faction-specific template
		var template: UnitTemplate = _get_faction_template_for_class(_player_faction, weight_class)

		# Update card border color
		var style: StyleBoxFlat = card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.border_color = faction_color * 0.8
		card.add_theme_stylebox_override("panel", style)

		# Update title and role with template-specific info
		var content: VBoxContainer = card.get_child(0) as VBoxContainer
		if content:
			var title: Label = content.get_node_or_null("UnitTitle")
			if title:
				title.add_theme_color_override("font_color", faction_color)
				if template != null:
					title.text = template.display_name
				else:
					title.text = _get_weight_class_display_name(weight_class)

			var role: Label = content.get_node_or_null("RoleDesc")
			if role and template != null:
				role.text = template.description

		# Update 3D model with faction-specific template
		_update_unit_model_from_template(model_index, weight_class, template, faction_color)
		model_index += 1

		# Update stats from template
		_update_unit_stats_from_template(card, weight_class, template)


## Update the 3D model in a viewport.
func _update_unit_model(index: int, unit_type: String, faction_color: Color) -> void:
	if index >= _faction_info_models.size():
		return

	var model_container: Node3D = _faction_info_models[index]
	if model_container == null:
		return

	# Clear existing model - use free() instead of queue_free() for immediate removal
	for child in model_container.get_children():
		model_container.remove_child(child)
		child.free()

	# Get type data directly - unit_type is already correct from card metadata
	var type_data: Dictionary = UNIT_TYPES.get(unit_type, UNIT_TYPES["soldier"])

	# Create the procedural bot model
	var bot := _create_procedural_bot(_player_faction, unit_type, type_data)
	bot.position = Vector3(0, type_data.get("size", Vector3.ONE).y * 0.5, 0)  # Center vertically
	bot.scale = Vector3.ONE * 1.2  # Slightly larger for visibility
	model_container.add_child(bot)


## Update unit stats on a card.
func _update_unit_stats(card: PanelContainer, unit_type: String) -> void:
	var content: VBoxContainer = card.get_child(0) as VBoxContainer
	if content == null:
		return

	var stats_container: VBoxContainer = content.get_node_or_null("StatsContainer")
	if stats_container == null:
		return

	# Get base stats
	var type_data: Dictionary = UNIT_TYPES.get(unit_type, {})
	var faction_mods: Dictionary = FACTION_STAT_MODIFIERS.get(_player_faction, {})

	# Calculate final stats with faction modifiers
	var health: float = type_data.get("health", 100) * faction_mods.get("health", 1.0)
	var damage: float = type_data.get("damage", 10) * faction_mods.get("damage", 1.0)
	var speed: float = type_data.get("speed_max", 10) * faction_mods.get("speed", 1.0)
	var attack_speed: float = type_data.get("attack_speed", 1.0) * faction_mods.get("attack_speed", 1.0)
	var range_val: float = type_data.get("range", 15) * faction_mods.get("range", 1.0)
	var dps: float = damage * attack_speed

	var faction_color: Color = FACTION_INFO.get(_player_faction, {}).get("color", Color.WHITE)

	# Max values for bar scaling
	var max_vals := {
		"health": 300.0,
		"damage": 60.0,
		"speed": 20.0,
		"attack_speed": 2.0,
		"range": 25.0,
		"dps": 80.0
	}

	# Update each stat row
	var stat_values := {
		"health": health,
		"damage": damage,
		"speed": speed,
		"attack_speed": attack_speed,
		"range": range_val,
		"dps": dps
	}

	for stat_key in stat_values:
		var row: HBoxContainer = stats_container.get_node_or_null("Stat_" + stat_key)
		if row == null:
			continue

		var value: float = stat_values[stat_key]
		var max_val: float = max_vals.get(stat_key, 100.0)

		# Update value label
		var value_label: Label = row.get_node_or_null("Value")
		if value_label:
			if stat_key == "attack_speed":
				value_label.text = "%.2f" % value
			else:
				value_label.text = "%d" % int(value)

		# Update bar fill
		var bar_bg: ColorRect = row.get_node_or_null("BarBg")
		if bar_bg:
			var bar_fill: ColorRect = bar_bg.get_node_or_null("BarFill")
			if bar_fill:
				var fill_pct: float = clampf(value / max_val, 0.0, 1.0)
				bar_fill.size.x = bar_bg.size.x * fill_pct
				bar_fill.color = faction_color.lerp(Color.WHITE, 0.3)


## Rotation speed for faction info models (radians per second).
const FACTION_INFO_ROTATE_SPEED := 1.0

## Update faction info model rotation.
func _update_faction_info_models(delta: float) -> void:
	for model_container in _faction_info_models:
		if model_container == null:
			continue
		# Rotate each model around Y axis
		for child in model_container.get_children():
			if child is Node3D:
				child.rotation.y += FACTION_INFO_ROTATE_SPEED * delta


## Get faction-specific template for a weight class.
func _get_faction_template_for_class(faction_id: int, weight_class: String) -> UnitTemplate:
	var faction_templates: Dictionary = FACTION_UNIT_TEMPLATES.get(faction_id, {})
	var template_id: String = faction_templates.get(weight_class, "")

	# Special handling for harvester - use faction-specific harvester template
	if weight_class == "harvester":
		match faction_id:
			1: template_id = "aether_swarm_nano_reaplet"
			2: template_id = "optiforge_repair_drone"  # OptiForge uses repair drone as harvester
			3: template_id = "dynapods_quadripper"
			4: template_id = "logibots_bulkripper"
			5: template_id = "human_soldier"  # Humans don't have harvesters

	if template_id.is_empty() or UnitTemplateManager == null:
		return null

	return UnitTemplateManager.get_template(template_id)


## Get display name for weight class (fallback when no template).
func _get_weight_class_display_name(weight_class: String) -> String:
	match weight_class:
		"light": return "Scout"
		"medium": return "Soldier"
		"heavy": return "Heavy"
		"harvester": return "Harvester"
		_: return weight_class.capitalize()


## Update 3D model from template data.
func _update_unit_model_from_template(index: int, weight_class: String, template: UnitTemplate, faction_color: Color) -> void:
	if index >= _faction_info_models.size():
		return

	var model_container: Node3D = _faction_info_models[index]
	if model_container == null:
		return

	# Clear existing model
	for child in model_container.get_children():
		model_container.remove_child(child)
		child.free()

	# Map weight class to bot type for procedural generation
	var bot_type: String = "soldier"
	match weight_class:
		"light": bot_type = "scout"
		"medium": bot_type = "soldier"
		"heavy": bot_type = "tank"
		"harvester": bot_type = "harvester"

	# Get type data - use template stats if available
	var type_data: Dictionary = UNIT_TYPES.get(bot_type, UNIT_TYPES["soldier"]).duplicate()

	# Override with template stats if available
	if template != null:
		var stats: Dictionary = template.base_stats
		type_data["health"] = stats.get("max_health", type_data.get("health", 100))
		type_data["damage"] = stats.get("base_damage", type_data.get("damage", 10))
		type_data["speed_max"] = stats.get("max_speed", type_data.get("speed_max", 10))

		# Scale based on template health
		var health: float = stats.get("max_health", 100.0)
		var scale_factor := sqrt(health / 100.0)
		type_data["size"] = Vector3(1.5, 2.0, 1.5) * scale_factor

	# Create procedural bot
	var bot := _create_procedural_bot(_player_faction, bot_type, type_data)
	bot.position = Vector3(0, type_data.get("size", Vector3.ONE).y * 0.5, 0)
	bot.scale = Vector3.ONE * 1.2
	model_container.add_child(bot)


## Update unit stats from template.
func _update_unit_stats_from_template(card: PanelContainer, weight_class: String, template: UnitTemplate) -> void:
	var content: VBoxContainer = card.get_child(0) as VBoxContainer
	if content == null:
		return

	var stats_container: VBoxContainer = content.get_node_or_null("StatsContainer")
	if stats_container == null:
		return

	# Get stats from template or fallback
	var health: float = 100.0
	var damage: float = 10.0
	var speed: float = 10.0
	var attack_speed: float = 1.0
	var range_val: float = 15.0

	if template != null:
		var stats: Dictionary = template.base_stats
		health = stats.get("max_health", 100.0)
		damage = stats.get("base_damage", 10.0)
		speed = stats.get("max_speed", 10.0)
		attack_speed = stats.get("attack_speed", 1.0)
		range_val = stats.get("attack_range", 15.0)
	else:
		# Fallback to UNIT_TYPES with faction modifiers
		var bot_type: String = "soldier"
		match weight_class:
			"light": bot_type = "scout"
			"medium": bot_type = "soldier"
			"heavy": bot_type = "tank"
			"harvester": bot_type = "harvester"

		var type_data: Dictionary = UNIT_TYPES.get(bot_type, {})
		var faction_mods: Dictionary = FACTION_STAT_MODIFIERS.get(_player_faction, {})
		health = type_data.get("health", 100) * faction_mods.get("health", 1.0)
		damage = type_data.get("damage", 10) * faction_mods.get("damage", 1.0)
		speed = type_data.get("speed_max", 10) * faction_mods.get("speed", 1.0)
		attack_speed = type_data.get("attack_speed", 1.0) * faction_mods.get("attack_speed", 1.0)
		range_val = type_data.get("range", 15) * faction_mods.get("range", 1.0)

	var dps: float = damage * attack_speed
	var faction_color: Color = FACTION_INFO.get(_player_faction, {}).get("color", Color.WHITE)

	# Max values for bar scaling
	var max_vals := {
		"health": 300.0,
		"damage": 60.0,
		"speed": 20.0,
		"attack_speed": 2.0,
		"range": 25.0,
		"dps": 80.0
	}

	var stat_values := {
		"health": health,
		"damage": damage,
		"speed": speed,
		"attack_speed": attack_speed,
		"range": range_val,
		"dps": dps
	}

	for stat_key in stat_values:
		var row: HBoxContainer = stats_container.get_node_or_null("Stat_" + stat_key)
		if row == null:
			continue

		var value: float = stat_values[stat_key]
		var max_val: float = max_vals.get(stat_key, 100.0)

		var value_label: Label = row.get_node_or_null("Value")
		if value_label:
			if stat_key == "attack_speed":
				value_label.text = "%.2f" % value
			else:
				value_label.text = "%d" % int(value)

		var bar_bg: ColorRect = row.get_node_or_null("BarBg")
		if bar_bg:
			var bar_fill: ColorRect = bar_bg.get_node_or_null("BarFill")
			if bar_fill:
				var fill_pct: float = clampf(value / max_val, 0.0, 1.0)
				bar_fill.size.x = bar_bg.size.x * fill_pct
				bar_fill.color = faction_color.lerp(Color.WHITE, 0.3)


## Setup unit tooltip panel for hover info.
func _setup_tooltip() -> void:
	# Create tooltip panel
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.name = "UnitTooltip"
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	style.border_color = Color(0.4, 0.6, 0.8, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	_tooltip_panel.add_theme_stylebox_override("panel", style)

	# Create tooltip label
	_tooltip_label = Label.new()
	_tooltip_label.name = "TooltipLabel"
	_tooltip_label.add_theme_font_size_override("font_size", 14)
	_tooltip_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_tooltip_panel.add_child(_tooltip_label)

	# Add to UI canvas layer
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(_tooltip_panel)


## Setup kill feed panel for combat events.
func _setup_kill_feed() -> void:
	# Create container for kill feed entries (top-right below minimap)
	_kill_feed_container = VBoxContainer.new()
	_kill_feed_container.name = "KillFeed"
	_kill_feed_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_kill_feed_container.anchor_left = 1.0
	_kill_feed_container.anchor_right = 1.0
	_kill_feed_container.offset_left = -250
	_kill_feed_container.offset_right = -10
	_kill_feed_container.offset_top = 220  # Below minimap
	_kill_feed_container.offset_bottom = 400
	_kill_feed_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_kill_feed_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_feed_container.add_theme_constant_override("separation", 2)

	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer:
		ui_layer.add_child(_kill_feed_container)


## Add an entry to the kill feed.
func _add_kill_feed_entry(killer_faction: int, victim_faction: int, killer_type: String, victim_type: String) -> void:
	if _kill_feed_container == null:
		return

	# Create styled label for the entry
	var entry := Label.new()
	entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	entry.add_theme_font_size_override("font_size", 12)

	# Get faction colors and short names
	var killer_color: Color = FACTION_COLORS.get(killer_faction, Color.WHITE)
	var victim_color: Color = FACTION_COLORS.get(victim_faction, Color.WHITE)
	var faction_short := {1: "BLU", 2: "RED", 3: "GRN", 4: "YLW"}
	var killer_name: String = faction_short.get(killer_faction, "???")
	var victim_name: String = faction_short.get(victim_faction, "???")

	# Format: "BLU scout → RED tank"
	entry.text = "%s %s → %s %s" % [killer_name, killer_type.substr(0, 6), victim_name, victim_type.substr(0, 6)]

	# Color based on who died - highlight player deaths/kills
	if victim_faction == 1:
		entry.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))  # Red - player loss
	elif killer_faction == 1:
		entry.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))  # Green - player kill
	else:
		entry.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))  # Gray - other combat

	# Add shadow for readability
	entry.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	entry.add_theme_constant_override("shadow_offset_x", 1)
	entry.add_theme_constant_override("shadow_offset_y", 1)

	# Add to container (newest at top)
	_kill_feed_container.add_child(entry)
	_kill_feed_container.move_child(entry, 0)

	# Track entry for cleanup
	_kill_feed_entries.append({"label": entry, "timestamp": Time.get_ticks_msec() / 1000.0})

	# Remove excess entries
	while _kill_feed_entries.size() > KILL_FEED_MAX_ENTRIES:
		var old_entry: Dictionary = _kill_feed_entries.pop_back()
		if is_instance_valid(old_entry.label):
			old_entry.label.queue_free()


## Update kill feed - remove old entries.
func _update_kill_feed() -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var i := 0
	while i < _kill_feed_entries.size():
		var entry: Dictionary = _kill_feed_entries[i]
		var age: float = current_time - entry.timestamp

		if age > KILL_FEED_DURATION:
			# Remove old entry
			if is_instance_valid(entry.label):
				entry.label.queue_free()
			_kill_feed_entries.remove_at(i)
		else:
			# Fade out as it ages
			if is_instance_valid(entry.label):
				var alpha: float = 1.0 - (age / KILL_FEED_DURATION) * 0.5  # Fade to 50% over duration
				entry.label.modulate.a = alpha
			i += 1


## Setup visual production progress bar.
func _setup_production_progress_bar() -> void:
	var resource_panel: PanelContainer = get_node_or_null("UI/ResourcePanel")
	if resource_panel == null:
		return

	var hbox: HBoxContainer = resource_panel.get_node_or_null("HBoxContainer")
	if hbox == null:
		return

	# Create a container for the progress bar
	var progress_container := VBoxContainer.new()
	progress_container.name = "ProductionProgressContainer"
	progress_container.custom_minimum_size = Vector2(80, 0)

	# Create label showing what's being built
	var progress_label := Label.new()
	progress_label.name = "ProductionProgressLabel"
	progress_label.add_theme_font_size_override("font_size", 10)
	progress_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.text = ""
	progress_container.add_child(progress_label)

	# Create the progress bar
	_production_progress_bar = ProgressBar.new()
	_production_progress_bar.name = "ProductionProgressBar"
	_production_progress_bar.custom_minimum_size = Vector2(80, 12)
	_production_progress_bar.min_value = 0.0
	_production_progress_bar.max_value = 100.0
	_production_progress_bar.value = 0.0
	_production_progress_bar.show_percentage = false

	# Style the progress bar
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.3, 0.8, 0.3, 0.9)
	fill_style.set_corner_radius_all(2)
	_production_progress_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.15, 0.15, 0.2, 0.8)
	bg_style.set_corner_radius_all(2)
	_production_progress_bar.add_theme_stylebox_override("background", bg_style)

	progress_container.add_child(_production_progress_bar)

	# Add time remaining label
	_production_time_label = Label.new()
	_production_time_label.name = "ProductionTimeLabel"
	_production_time_label.add_theme_font_size_override("font_size", 9)
	_production_time_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_production_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_production_time_label.text = ""
	progress_container.add_child(_production_time_label)

	# Add separator and container to HBox
	var separator := VSeparator.new()
	hbox.add_child(separator)
	hbox.add_child(progress_container)

	# Add visual queue container for unit icons
	var separator2 := VSeparator.new()
	hbox.add_child(separator2)

	_production_queue_container = HBoxContainer.new()
	_production_queue_container.name = "ProductionQueueIcons"
	_production_queue_container.add_theme_constant_override("separation", 2)
	hbox.add_child(_production_queue_container)


## Setup factory status panel in top-left corner.
func _setup_factory_status_panel() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create panel container
	_factory_status_panel = PanelContainer.new()
	_factory_status_panel.name = "FactoryStatusPanel"
	_factory_status_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_factory_status_panel.offset_left = 10
	_factory_status_panel.offset_top = 420  # Below debug label
	_factory_status_panel.offset_right = 180
	_factory_status_panel.offset_bottom = 580
	_factory_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style the panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	panel_style.border_color = Color(0.3, 0.35, 0.4, 0.8)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(4)
	panel_style.set_content_margin_all(8)
	_factory_status_panel.add_theme_stylebox_override("panel", panel_style)

	# Create VBox for content
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# Title
	var title := Label.new()
	title.text = "FACTORIES"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Create health bar for each faction
	var faction_names := {1: "Aether", 2: "OptiForge", 3: "Dynapods", 4: "LogiBots"}
	for faction_id in [1, 2, 3, 4]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# Faction color indicator
		var color_box := ColorRect.new()
		color_box.custom_minimum_size = Vector2(12, 12)
		color_box.color = FACTION_COLORS.get(faction_id, Color.WHITE)
		row.add_child(color_box)

		# Factory info container
		var info_box := VBoxContainer.new()
		info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Name label
		var name_label := Label.new()
		name_label.text = faction_names.get(faction_id, "???")
		name_label.add_theme_font_size_override("font_size", 11)
		name_label.add_theme_color_override("font_color", FACTION_COLORS.get(faction_id, Color.WHITE))
		info_box.add_child(name_label)

		# Health bar
		var health_bar := ProgressBar.new()
		health_bar.custom_minimum_size = Vector2(100, 8)
		health_bar.min_value = 0.0
		health_bar.max_value = 100.0
		health_bar.value = 100.0
		health_bar.show_percentage = false

		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = FACTION_COLORS.get(faction_id, Color.WHITE)
		fill_style.set_corner_radius_all(2)
		health_bar.add_theme_stylebox_override("fill", fill_style)

		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color(0.2, 0.2, 0.25, 0.8)
		bg_style.set_corner_radius_all(2)
		health_bar.add_theme_stylebox_override("background", bg_style)

		info_box.add_child(health_bar)
		row.add_child(info_box)

		vbox.add_child(row)

		# Store reference
		_factory_status_bars[faction_id] = {"bar": health_bar, "label": name_label}

	_factory_status_panel.add_child(vbox)
	ui_layer.add_child(_factory_status_panel)


## Update factory status panel with current health values.
func _update_factory_status_panel() -> void:
	if _factory_status_panel == null:
		return

	for faction_id in _factory_status_bars:
		var status: Dictionary = _factory_status_bars[faction_id]
		var bar: ProgressBar = status.bar
		var label: Label = status.label

		if _factories.has(faction_id):
			var factory: Dictionary = _factories[faction_id]
			var health_pct: float = (factory.health / FACTORY_HEALTH) * 100.0

			if factory.is_destroyed:
				bar.value = 0
				label.modulate = Color(0.5, 0.5, 0.5)  # Gray out destroyed
				label.text += " ✗" if not label.text.ends_with("✗") else ""
			else:
				bar.value = health_pct
				label.modulate = Color.WHITE
		else:
			bar.value = 0


## Setup control group badges above resource panel.
func _setup_control_group_badges() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create container for control group badges
	_control_group_container = HBoxContainer.new()
	_control_group_container.name = "ControlGroupBadges"
	_control_group_container.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_control_group_container.anchor_left = 0.5
	_control_group_container.anchor_right = 0.5
	_control_group_container.anchor_top = 1.0
	_control_group_container.anchor_bottom = 1.0
	_control_group_container.offset_left = -150
	_control_group_container.offset_right = 150
	_control_group_container.offset_top = -95  # Above resource panel
	_control_group_container.offset_bottom = -85
	_control_group_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_control_group_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_control_group_container.add_theme_constant_override("separation", 4)
	_control_group_container.alignment = BoxContainer.ALIGNMENT_CENTER

	# Create badges for groups 1-9
	for i in range(1, 10):
		var badge := Label.new()
		badge.name = "Group%d" % i
		badge.text = "[%d]" % i
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))  # Dim when empty
		badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		badge.add_theme_constant_override("shadow_offset_x", 1)
		badge.add_theme_constant_override("shadow_offset_y", 1)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(28, 0)
		_control_group_container.add_child(badge)
		_control_group_labels[i] = badge

	ui_layer.add_child(_control_group_container)


## Update control group badges with current counts.
func _update_control_group_badges() -> void:
	if _control_group_container == null:
		return

	for group_num in _control_group_labels:
		var label: Label = _control_group_labels[group_num]
		var count := 0

		if _control_groups.has(group_num):
			var group: Array = _control_groups[group_num]
			# Count alive units
			for unit in group:
				if not unit.is_dead:
					count += 1

		if count > 0:
			label.text = "[%d]%d" % [group_num, count]
			label.add_theme_color_override("font_color", Color(0.8, 0.9, 0.4))  # Bright when has units
		else:
			label.text = "[%d]" % group_num
			label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))  # Dim when empty


## Create a ping marker at minimap position.
func _create_minimap_ping(local_pos: Vector2) -> void:
	# Convert minimap position to world position
	var minimap_size := Vector2(200, 200)
	var normalized := local_pos / minimap_size
	var world_x := (normalized.x - 0.5) * MAP_SIZE
	var world_z := (normalized.y - 0.5) * MAP_SIZE
	var world_pos := Vector3(world_x, 0, world_z)

	# Create visual ping marker (cone pointing down)
	var ping_mesh := CSGCylinder3D.new()
	ping_mesh.name = "PingMarker"
	ping_mesh.radius = 8.0
	ping_mesh.height = 20.0
	ping_mesh.sides = 4
	ping_mesh.cone = true
	ping_mesh.rotation_degrees.x = 180  # Point down

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.2)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ping_mesh.material = mat

	ping_mesh.position = world_pos + Vector3(0, 30, 0)  # Float above ground
	add_child(ping_mesh)

	# Also create a minimap indicator
	var minimap_ping := CSGCylinder3D.new()
	minimap_ping.name = "MinimapPing"
	minimap_ping.radius = 6.0
	minimap_ping.height = 2.0
	minimap_ping.sides = 8
	minimap_ping.material = mat.duplicate()
	minimap_ping.position = world_pos + Vector3(0, 55, 0)  # Above minimap icons

	if _minimap_viewport:
		_minimap_viewport.add_child(minimap_ping)

	# Store ping data
	_active_pings.append({
		"mesh": ping_mesh,
		"minimap_mesh": minimap_ping,
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"position": world_pos
	})

	# Play ping sound
	_play_ping_sound()

	print("Ping at (%.0f, %.0f)" % [world_x, world_z])


## Update active pings (pulse and fade).
func _update_pings() -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var i := 0

	while i < _active_pings.size():
		var ping: Dictionary = _active_pings[i]
		var age: float = current_time - ping.timestamp

		if age > PING_DURATION:
			# Remove expired ping
			if is_instance_valid(ping.mesh):
				ping.mesh.queue_free()
			if is_instance_valid(ping.minimap_mesh):
				ping.minimap_mesh.queue_free()
			_active_pings.remove_at(i)
			continue

		# Animate ping (pulse and fade)
		var pulse: float = sin(age * PING_PULSE_SPEED * TAU) * 0.3 + 1.0
		var fade: float = 1.0 - (age / PING_DURATION)

		if is_instance_valid(ping.mesh):
			ping.mesh.scale = Vector3(pulse, 1.0, pulse)
			var mat: StandardMaterial3D = ping.mesh.material as StandardMaterial3D
			if mat:
				mat.albedo_color.a = fade * 0.8

		if is_instance_valid(ping.minimap_mesh):
			ping.minimap_mesh.scale = Vector3(pulse, 1.0, pulse)
			var mat: StandardMaterial3D = ping.minimap_mesh.material as StandardMaterial3D
			if mat:
				mat.albedo_color.a = fade * 0.8

		i += 1


## Play ping sound effect.
func _play_ping_sound() -> void:
	var player := _get_audio_player()
	if player == null:
		return

	# Generate a short "ping" sound
	var sample_rate := 22050
	var duration := 0.15
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for s in samples:
		var t := float(s) / sample_rate
		var progress := float(s) / samples

		# Two-tone ping (high then low)
		var freq := 800.0 if progress < 0.4 else 600.0
		var wave := sin(t * freq * TAU) * 0.5

		# Quick decay envelope
		var env := exp(-progress * 5.0)

		var sample_value := int(wave * env * 15000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[s * 2] = sample_value & 0xFF
		data[s * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data

	player.stream = stream
	player.volume_db = -5.0
	player.play()


## Setup attack-move mode indicator.
func _setup_attack_move_indicator() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	_attack_move_indicator = Label.new()
	_attack_move_indicator.name = "AttackMoveIndicator"
	_attack_move_indicator.set_anchors_preset(Control.PRESET_CENTER)
	_attack_move_indicator.offset_left = -100
	_attack_move_indicator.offset_right = 100
	_attack_move_indicator.offset_top = -200
	_attack_move_indicator.offset_bottom = -170
	_attack_move_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attack_move_indicator.add_theme_font_size_override("font_size", 20)
	_attack_move_indicator.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	_attack_move_indicator.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_attack_move_indicator.add_theme_constant_override("shadow_offset_x", 2)
	_attack_move_indicator.add_theme_constant_override("shadow_offset_y", 2)
	_attack_move_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attack_move_indicator.visible = false
	_attack_move_indicator.text = "⚔ ATTACK-MOVE ⚔"

	ui_layer.add_child(_attack_move_indicator)


## Update attack-move indicator visibility.
func _update_attack_move_indicator() -> void:
	if _attack_move_indicator != null:
		_attack_move_indicator.visible = _attack_move_mode


## Setup queue mode indicator.
func _setup_queue_mode_indicator() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	_queue_mode_indicator = Label.new()
	_queue_mode_indicator.name = "QueueModeIndicator"
	_queue_mode_indicator.set_anchors_preset(Control.PRESET_CENTER)
	_queue_mode_indicator.offset_left = -100
	_queue_mode_indicator.offset_right = 100
	_queue_mode_indicator.offset_top = -230
	_queue_mode_indicator.offset_bottom = -200
	_queue_mode_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_queue_mode_indicator.add_theme_font_size_override("font_size", 18)
	_queue_mode_indicator.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	_queue_mode_indicator.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_queue_mode_indicator.add_theme_constant_override("shadow_offset_x", 2)
	_queue_mode_indicator.add_theme_constant_override("shadow_offset_y", 2)
	_queue_mode_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_queue_mode_indicator.visible = false
	_queue_mode_indicator.text = "⇧ QUEUE MODE ⇧"

	ui_layer.add_child(_queue_mode_indicator)


## Update queue mode indicator visibility.
func _update_queue_mode_indicator() -> void:
	if _queue_mode_indicator != null:
		_queue_mode_indicator.visible = _command_queue_mode


## Setup selection count display.
func _setup_selection_count_display() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	_selection_count_label = Label.new()
	_selection_count_label.name = "SelectionCountLabel"
	_selection_count_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_selection_count_label.offset_left = 230  # Right of hotkey hints panel
	_selection_count_label.offset_right = 430
	_selection_count_label.offset_top = -50
	_selection_count_label.offset_bottom = -10
	_selection_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_selection_count_label.add_theme_font_size_override("font_size", 18)
	_selection_count_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	_selection_count_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_selection_count_label.add_theme_constant_override("shadow_offset_x", 2)
	_selection_count_label.add_theme_constant_override("shadow_offset_y", 2)
	_selection_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_count_label.visible = false

	ui_layer.add_child(_selection_count_label)


## Update selection count display.
func _update_selection_count_display() -> void:
	if _selection_count_label == null:
		return

	if _selected_units.is_empty():
		_selection_count_label.visible = false
		return

	# Count units by type
	var light_count := 0
	var medium_count := 0
	var heavy_count := 0
	var total_hp := 0.0
	var total_max_hp := 0.0

	for unit in _selected_units:
		if unit.is_dead:
			continue
		var unit_class: String = unit.get("unit_class", "medium")
		match unit_class:
			"light": light_count += 1
			"medium": medium_count += 1
			"heavy": heavy_count += 1
		total_hp += unit.health
		total_max_hp += unit.max_health

	var total := light_count + medium_count + heavy_count
	if total == 0:
		_selection_count_label.visible = false
		return

	var hp_percent := int((total_hp / total_max_hp) * 100) if total_max_hp > 0 else 100

	_selection_count_label.text = "Selected: %d (L:%d M:%d H:%d) HP:%d%%" % [total, light_count, medium_count, heavy_count, hp_percent]
	_selection_count_label.visible = true

	# Color based on health
	if hp_percent < 30:
		_selection_count_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	elif hp_percent < 60:
		_selection_count_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	else:
		_selection_count_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))


## Setup unit portrait panel at bottom of screen.
func _setup_portrait_panel() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create panel container
	_portrait_panel = PanelContainer.new()
	_portrait_panel.name = "PortraitPanel"
	_portrait_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_portrait_panel.offset_top = -95  # Increased height for task status
	_portrait_panel.offset_bottom = -10
	_portrait_panel.offset_left = -400
	_portrait_panel.offset_right = 400
	_portrait_panel.visible = false
	_portrait_panel.mouse_filter = Control.MOUSE_FILTER_PASS

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.15, 0.9)
	style.border_color = Color(0.3, 0.35, 0.4, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_portrait_panel.add_theme_stylebox_override("panel", style)

	# Create horizontal container for portraits
	_portrait_container = HBoxContainer.new()
	_portrait_container.name = "PortraitContainer"
	_portrait_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_portrait_container.add_theme_constant_override("separation", PORTRAIT_SPACING)
	_portrait_panel.add_child(_portrait_container)

	ui_layer.add_child(_portrait_panel)


## Update unit portrait panel with selected units.
func _update_portrait_panel() -> void:
	if _portrait_panel == null or _portrait_container == null:
		return

	# Clear old portraits
	for icon in _portrait_icons:
		if is_instance_valid(icon):
			icon.queue_free()
	_portrait_icons.clear()

	# Hide if no selection
	if _selected_units.is_empty():
		_portrait_panel.visible = false
		return

	# Filter out dead units
	var alive_units: Array = []
	for unit in _selected_units:
		if not unit.get("is_dead", false):
			alive_units.append(unit)

	if alive_units.is_empty():
		_portrait_panel.visible = false
		return

	# Show panel
	_portrait_panel.visible = true

	# Create portraits for each unit (up to max)
	var display_count := mini(alive_units.size(), PORTRAIT_MAX_DISPLAY)
	for i in display_count:
		var unit: Dictionary = alive_units[i]
		var portrait := _create_unit_portrait(unit, i)
		_portrait_container.add_child(portrait)
		_portrait_icons.append(portrait)

	# Show overflow indicator if needed
	if alive_units.size() > PORTRAIT_MAX_DISPLAY:
		var overflow := Label.new()
		overflow.text = "+%d" % (alive_units.size() - PORTRAIT_MAX_DISPLAY)
		overflow.add_theme_font_size_override("font_size", 14)
		overflow.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_portrait_container.add_child(overflow)
		_portrait_icons.append(overflow)


## Create a single unit portrait icon.
func _create_unit_portrait(unit: Dictionary, index: int) -> Control:
	var faction_id: int = unit.get("faction_id", _player_faction)
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)
	var unit_class: String = unit.get("unit_class", "medium")
	var health_pct: float = unit.health / unit.max_health if unit.max_health > 0 else 1.0
	var vet_level: int = unit.get("veterancy_level", 0)

	# Main container
	var portrait := Control.new()
	portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE + 12 + PORTRAIT_TASK_HEIGHT)
	portrait.mouse_filter = Control.MOUSE_FILTER_STOP

	# Click handler to select this unit
	portrait.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select_single_unit(unit)
			_play_ui_sound("click")
	)

	# Background panel with faction color
	var bg := Panel.new()
	bg.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = faction_color.darkened(0.6)
	bg_style.border_color = faction_color
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(4)
	bg.add_theme_stylebox_override("panel", bg_style)
	portrait.add_child(bg)

	# Unit type icon (symbol in center)
	var icon_label := Label.new()
	icon_label.position = Vector2(0, 0)
	icon_label.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 20)
	icon_label.add_theme_color_override("font_color", faction_color.lightened(0.3))

	match unit_class:
		"light":
			icon_label.text = "◆"  # Diamond for scouts
		"medium":
			icon_label.text = "●"  # Circle for soldiers
		"heavy":
			icon_label.text = "■"  # Square for tanks
		"harvester":
			icon_label.text = "⬡"  # Hexagon for harvesters
		_:
			icon_label.text = "●"
	portrait.add_child(icon_label)

	# Health bar below icon
	var health_bar_bg := ColorRect.new()
	health_bar_bg.position = Vector2(2, PORTRAIT_SIZE + 2)
	health_bar_bg.size = Vector2(PORTRAIT_SIZE - 4, 6)
	health_bar_bg.color = Color(0.2, 0.2, 0.2, 0.8)
	portrait.add_child(health_bar_bg)

	var health_bar_fill := ColorRect.new()
	health_bar_fill.position = Vector2(2, PORTRAIT_SIZE + 2)
	health_bar_fill.size = Vector2((PORTRAIT_SIZE - 4) * health_pct, 6)
	# Color based on health
	if health_pct < 0.3:
		health_bar_fill.color = Color(1.0, 0.3, 0.3)
	elif health_pct < 0.6:
		health_bar_fill.color = Color(1.0, 0.8, 0.3)
	else:
		health_bar_fill.color = Color(0.3, 1.0, 0.3)
	portrait.add_child(health_bar_fill)

	# Task status label below health bar
	var task_label := Label.new()
	task_label.position = Vector2(0, PORTRAIT_SIZE + 10)
	task_label.size = Vector2(PORTRAIT_SIZE, PORTRAIT_TASK_HEIGHT)
	task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task_label.add_theme_font_size_override("font_size", 9)
	task_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.9))
	task_label.text = _get_unit_task_string(unit)
	portrait.add_child(task_label)

	# Veterancy stars (top right corner)
	if vet_level > 0:
		var stars := Label.new()
		stars.position = Vector2(PORTRAIT_SIZE - 14, 0)
		stars.add_theme_font_size_override("font_size", 10)
		stars.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		stars.text = "★".repeat(mini(vet_level, 3))
		portrait.add_child(stars)

	# Hover effect
	var hover_rect := ColorRect.new()
	hover_rect.position = Vector2.ZERO
	hover_rect.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	hover_rect.color = Color(1, 1, 1, 0.0)
	hover_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.add_child(hover_rect)

	portrait.mouse_entered.connect(func():
		hover_rect.color = Color(1, 1, 1, 0.15)
	)
	portrait.mouse_exited.connect(func():
		hover_rect.color = Color(1, 1, 1, 0.0)
	)

	return portrait


## Select a single unit (called when clicking portrait).
func _select_single_unit(unit: Dictionary) -> void:
	# Deselect all
	for u in _selected_units:
		u.is_selected = false
	_selected_units.clear()

	# Select clicked unit
	if not unit.get("is_dead", false):
		unit.is_selected = true
		_selected_units.append(unit)

	# Update visuals
	_update_selection_rings()
	_update_portrait_panel()
	_update_selection_count_display()


## Get a human-readable string for the unit's current task/status.
func _get_unit_task_string(unit: Dictionary) -> String:
	# Check if unit is dead
	if unit.get("is_dead", false):
		return "Dead"

	# Check if harvester - has special states
	if unit.get("is_harvester", false):
		var state: int = unit.get("harvester_state", HarvesterState.IDLE)
		match state:
			HarvesterState.IDLE:
				if unit.get("carried_ree", 0.0) > 0:
					return "Cargo: %d" % int(unit.get("carried_ree", 0.0))
				return "Idle"
			HarvesterState.SEEKING_WRECKAGE:
				return "Seeking"
			HarvesterState.HARVESTING:
				return "Harvesting"
			HarvesterState.RETURNING:
				return "Returning"
			HarvesterState.SEEKING_BUILDING:
				return "To Bldg"
			HarvesterState.SALVAGING:
				return "Salvaging"
		return "Idle"

	# Check if unit has an attack target
	var attack_target = unit.get("attack_target")
	if attack_target != null:
		return "Attacking"

	# Check if unit has a movement target
	var target_pos = unit.get("target_pos")
	if target_pos != null and is_instance_valid(unit.mesh):
		var dist: float = unit.mesh.position.distance_to(target_pos)
		if dist > 3.0:  # Still moving
			return "Moving"

	# Check for special states
	if unit.get("is_phase_shifting", false):
		return "Phasing"
	if unit.get("is_overclocked", false):
		return "Overclock"
	if unit.get("is_cloaked", false):
		return "Cloaked"
	if unit.get("is_in_siege_mode", false):
		return "Siege"

	# Check if in combat (recently took damage or dealt damage)
	if unit.get("in_combat", false):
		return "Combat"

	# Default idle state
	return "Idle"


## Setup enemy direction indicators.
func _setup_enemy_indicators() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	for i in range(ENEMY_INDICATOR_COUNT):
		var indicator := ColorRect.new()
		indicator.name = "EnemyIndicator_%d" % i
		indicator.size = Vector2(ENEMY_INDICATOR_SIZE, ENEMY_INDICATOR_SIZE)
		indicator.color = Color(1.0, 0.3, 0.2, 0.8)
		indicator.rotation = 0  # Will be set per-update
		indicator.pivot_offset = Vector2(ENEMY_INDICATOR_SIZE / 2, ENEMY_INDICATOR_SIZE / 2)
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		indicator.visible = false

		ui_layer.add_child(indicator)
		_enemy_indicators.append(indicator)


## Update enemy direction indicators to point at off-screen enemies.
func _update_enemy_indicators() -> void:
	if camera == null:
		return

	var screen_size := get_viewport().get_visible_rect().size
	var screen_center := screen_size / 2.0
	var margin := 40.0  # Distance from screen edge

	# Find significant enemy groups (cluster enemies together)
	var enemy_clusters: Array[Dictionary] = []

	for unit in _units:
		if unit.is_dead or unit.faction_id == _player_faction:
			continue
		if not is_instance_valid(unit.mesh):
			continue

		var world_pos: Vector3 = unit.mesh.position
		var screen_pos := camera.unproject_position(world_pos)

		# Check if off-screen
		if screen_pos.x < -50 or screen_pos.x > screen_size.x + 50 or \
		   screen_pos.y < -50 or screen_pos.y > screen_size.y + 50:
			# Check if behind camera
			var to_unit := world_pos - camera.global_position
			if to_unit.dot(-camera.global_transform.basis.z) < 0:
				continue

			# Find or create cluster
			var found_cluster := false
			for cluster in enemy_clusters:
				if screen_pos.distance_to(cluster.screen_pos) < 100:
					cluster.count += 1
					cluster.screen_pos = (cluster.screen_pos + screen_pos) / 2.0
					found_cluster = true
					break

			if not found_cluster:
				enemy_clusters.append({
					"screen_pos": screen_pos,
					"count": 1,
					"faction_id": unit.faction_id
				})

	# Sort by count (show largest clusters)
	enemy_clusters.sort_custom(func(a, b): return a.count > b.count)

	# Update indicators
	for i in range(ENEMY_INDICATOR_COUNT):
		if i >= _enemy_indicators.size():
			break

		var indicator: ColorRect = _enemy_indicators[i]

		if i < enemy_clusters.size():
			var cluster: Dictionary = enemy_clusters[i]
			var cluster_pos: Vector2 = cluster.screen_pos
			var dir: Vector2 = (cluster_pos - screen_center).normalized()

			# Clamp to screen edge
			var edge_pos: Vector2 = screen_center
			if abs(dir.x) > abs(dir.y):
				edge_pos.x = screen_size.x - margin if dir.x > 0 else margin
				edge_pos.y = screen_center.y + dir.y * (screen_size.x / 2.0 - margin) / abs(dir.x)
			else:
				edge_pos.y = screen_size.y - margin if dir.y > 0 else margin
				edge_pos.x = screen_center.x + dir.x * (screen_size.y / 2.0 - margin) / abs(dir.y)

			edge_pos.x = clampf(edge_pos.x, margin, screen_size.x - margin)
			edge_pos.y = clampf(edge_pos.y, margin, screen_size.y - margin)

			indicator.position = edge_pos - indicator.pivot_offset
			indicator.rotation = atan2(dir.y, dir.x) + PI / 4  # Point arrow
			indicator.color = FACTION_COLORS.get(cluster.faction_id, Color.RED)
			indicator.color.a = 0.8
			indicator.visible = true
		else:
			indicator.visible = false


## Setup match timer display.
func _setup_match_timer() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	_match_timer_label = Label.new()
	_match_timer_label.name = "MatchTimer"
	_match_timer_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_match_timer_label.offset_left = -60
	_match_timer_label.offset_right = 60
	_match_timer_label.offset_top = 10
	_match_timer_label.offset_bottom = 40
	_match_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_match_timer_label.add_theme_font_size_override("font_size", 24)
	_match_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	_match_timer_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_match_timer_label.add_theme_constant_override("shadow_offset_x", 2)
	_match_timer_label.add_theme_constant_override("shadow_offset_y", 2)
	_match_timer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_match_timer_label.text = "00:00"

	ui_layer.add_child(_match_timer_label)


## Update match timer display.
func _update_match_timer() -> void:
	if _match_timer_label == null:
		return

	_match_timer_label.text = GameStateManager.get_formatted_duration()


## Setup threat level indicator.
func _setup_threat_indicator() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Container for threat indicator (top-right area)
	var container := VBoxContainer.new()
	container.name = "ThreatIndicator"
	container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	container.offset_left = -180
	container.offset_right = -10
	container.offset_top = 10
	container.offset_bottom = 60
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Label
	_threat_label = Label.new()
	_threat_label.text = "THREAT"
	_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_threat_label.add_theme_font_size_override("font_size", 12)
	_threat_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.6))
	_threat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(_threat_label)

	# Progress bar
	_threat_bar = ProgressBar.new()
	_threat_bar.min_value = 0.0
	_threat_bar.max_value = 100.0
	_threat_bar.value = 50.0
	_threat_bar.show_percentage = false
	_threat_bar.custom_minimum_size = Vector2(160, 16)
	_threat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Style the bar
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.15, 0.15, 0.15, 0.8)
	style_bg.corner_radius_top_left = 3
	style_bg.corner_radius_top_right = 3
	style_bg.corner_radius_bottom_left = 3
	style_bg.corner_radius_bottom_right = 3
	_threat_bar.add_theme_stylebox_override("background", style_bg)

	var style_fill := StyleBoxFlat.new()
	style_fill.bg_color = Color(0.8, 0.4, 0.2)  # Orange by default
	style_fill.corner_radius_top_left = 3
	style_fill.corner_radius_top_right = 3
	style_fill.corner_radius_bottom_left = 3
	style_fill.corner_radius_bottom_right = 3
	_threat_bar.add_theme_stylebox_override("fill", style_fill)

	container.add_child(_threat_bar)
	ui_layer.add_child(container)


## Update threat level indicator.
func _update_threat_indicator() -> void:
	if _threat_bar == null or _threat_label == null:
		return

	# Calculate player strength (unit count * avg health)
	var player_strength := 0.0
	var player_count := 0
	for unit in _units:
		if unit.is_dead or unit.faction_id != _player_faction:
			continue
		player_strength += unit.health + unit.get("damage", 10.0) * 5.0
		player_count += 1

	# Calculate enemy strength
	var enemy_strength := 0.0
	var enemy_count := 0
	for unit in _units:
		if unit.is_dead or unit.faction_id == _player_faction:
			continue
		enemy_strength += unit.health + unit.get("damage", 10.0) * 5.0
		enemy_count += 1

	# Calculate threat ratio (0-100, 50 = balanced)
	var total := player_strength + enemy_strength
	var threat_ratio := 50.0
	if total > 0:
		threat_ratio = (enemy_strength / total) * 100.0

	_threat_bar.value = threat_ratio

	# Color based on threat level
	var fill_style: StyleBoxFlat = _threat_bar.get_theme_stylebox("fill")
	if fill_style:
		if threat_ratio > 70:
			fill_style.bg_color = Color(0.9, 0.2, 0.2)  # Red - high threat
			_threat_label.text = "THREAT: HIGH"
			_threat_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		elif threat_ratio > 55:
			fill_style.bg_color = Color(0.9, 0.6, 0.2)  # Orange - moderate
			_threat_label.text = "THREAT: MODERATE"
			_threat_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
		elif threat_ratio > 40:
			fill_style.bg_color = Color(0.8, 0.8, 0.3)  # Yellow - balanced
			_threat_label.text = "THREAT: BALANCED"
			_threat_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
		else:
			fill_style.bg_color = Color(0.3, 0.8, 0.3)  # Green - advantage
			_threat_label.text = "THREAT: LOW"
			_threat_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))


## Setup production hotkey hints panel.
func _setup_hotkey_hints_panel() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create panel container
	_hotkey_hints_panel = PanelContainer.new()
	_hotkey_hints_panel.name = "HotkeyHintsPanel"
	_hotkey_hints_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hotkey_hints_panel.offset_left = 10
	_hotkey_hints_panel.offset_right = 220
	_hotkey_hints_panel.offset_top = -130
	_hotkey_hints_panel.offset_bottom = -10

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	style.border_color = Color(0.3, 0.5, 0.7, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_hotkey_hints_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	# Title
	var title := Label.new()
	title.text = "PRODUCTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	vbox.add_child(title)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Production hotkeys
	var hints := [
		["1", "Light Unit", "50 REE", Color(0.4, 0.8, 1.0)],
		["2", "Medium Unit", "100 REE", Color(0.5, 0.9, 0.5)],
		["3", "Heavy Unit", "200 REE", Color(1.0, 0.7, 0.3)]
	]

	for hint in hints:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		# Key badge
		var key_label := Label.new()
		key_label.text = "[%s]" % hint[0]
		key_label.add_theme_font_size_override("font_size", 14)
		key_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		key_label.custom_minimum_size.x = 30
		hbox.add_child(key_label)

		# Unit name
		var name_label := Label.new()
		name_label.text = hint[1]
		name_label.add_theme_font_size_override("font_size", 12)
		name_label.add_theme_color_override("font_color", hint[3])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)

		# Cost
		var cost_label := Label.new()
		cost_label.text = hint[2]
		cost_label.add_theme_font_size_override("font_size", 11)
		cost_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hbox.add_child(cost_label)

		vbox.add_child(hbox)

	_hotkey_hints_panel.add_child(vbox)
	ui_layer.add_child(_hotkey_hints_panel)


## Setup the full hotkey reference overlay (F1 toggle).
func _setup_hotkey_overlay() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create semi-transparent background panel
	_hotkey_overlay = PanelContainer.new()
	_hotkey_overlay.name = "HotkeyOverlay"
	_hotkey_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_hotkey_overlay.offset_left = -350
	_hotkey_overlay.offset_right = 350
	_hotkey_overlay.offset_top = -280
	_hotkey_overlay.offset_bottom = 280
	_hotkey_overlay.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	style.border_color = Color(0.4, 0.6, 0.9, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	_hotkey_overlay.add_theme_stylebox_override("panel", style)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)

	# Title
	var title := Label.new()
	title.text = "⌨ HOTKEY REFERENCE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	main_vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Press H or ? to close"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	main_vbox.add_child(subtitle)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	main_vbox.add_child(sep)

	# Columns container
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 30)

	# Column 1: Camera & Navigation
	var col1 := _create_hotkey_column("CAMERA & NAVIGATION", [
		["WASD/Arrows", "Pan camera"],
		["Mouse Wheel", "Zoom in/out"],
		["Edge Scroll", "Pan at screen edges"],
		["SPACE", "Jump to combat"],
		["Home", "Return to factory"],
		["Ctrl+1-9", "Save camera bookmark"],
		["Alt+1-9", "Recall camera bookmark"],
	])
	columns.add_child(col1)

	# Column 2: Unit Selection & Control
	var col2 := _create_hotkey_column("SELECTION & CONTROL", [
		["Left Click", "Select unit"],
		["Shift+Click", "Add to selection"],
		["Ctrl+Click", "Toggle in selection"],
		["Right Click", "Move/Attack"],
		["A + Click", "Attack-move"],
		["S", "Stop units"],
		["H", "Hold position"],
		["Ctrl+1-9", "Create control group"],
		["1-9", "Select control group"],
		["Tab", "Cycle selection"],
	])
	columns.add_child(col2)

	# Column 3: Production
	var col3 := _create_hotkey_column("PRODUCTION", [
		["1", "Queue Light Unit (30 REE)"],
		["2", "Queue Medium Unit (60 REE)"],
		["3", "Queue Heavy Unit (120 REE)"],
		["4", "Queue Harvester (50 REE)"],
		["Shift+1-4", "Queue x5"],
		["Ctrl+1-4", "Queue x10"],
		["Escape", "Cancel last in queue"],
	])
	columns.add_child(col3)

	main_vbox.add_child(columns)

	# Row 2: Abilities
	var sep2 := HSeparator.new()
	sep2.add_theme_constant_override("separation", 8)
	main_vbox.add_child(sep2)

	var columns2 := HBoxContainer.new()
	columns2.add_theme_constant_override("separation", 30)

	# Column 4: Abilities
	var col4 := _create_hotkey_column("FACTION ABILITIES", [
		["Q", "Phase Shift (Aether)"],
		["E", "Ether Cloak (Aether)"],
		["Q", "Overclock Unit (OptiForge)"],
		["E", "Mass Production (OptiForge)"],
		["B", "Acrobatic Strike (Dynapods)"],
		["F", "Coordinated Barrage (LogiBots)"],
		["C", "Siege Formation (LogiBots)"],
	])
	columns2.add_child(col4)

	# Column 5: Game Control
	var col5 := _create_hotkey_column("GAME CONTROL", [
		["P", "Pause/Unpause"],
		["+/-", "Adjust game speed"],
		["H or ?", "Toggle this overlay"],
		["R", "Set rally point"],
		["G", "Guard mode"],
		["Minimap Click", "Move camera"],
		["Minimap RClick", "Move units"],
		["Alt+Minimap", "Create ping"],
	])
	columns2.add_child(col5)

	# Column 6: Stance & Formation
	var col6 := _create_hotkey_column("STANCE & FORMATION", [
		["Z", "Cycle stance (Aggro/Def/Hold)"],
		["F1", "Line formation"],
		["F2", "Wedge formation"],
		["F3", "Box formation"],
		["F4", "Scatter formation"],
	])
	columns2.add_child(col6)

	main_vbox.add_child(columns2)

	_hotkey_overlay.add_child(main_vbox)
	ui_layer.add_child(_hotkey_overlay)


## Helper to create a column of hotkey hints.
func _create_hotkey_column(title: String, hints: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.custom_minimum_size.x = 200

	# Column title
	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	col.add_child(title_label)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 2)
	col.add_child(sep)

	for hint in hints:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		# Key badge
		var key_label := Label.new()
		key_label.text = "[%s]" % hint[0]
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		key_label.custom_minimum_size.x = 90
		hbox.add_child(key_label)

		# Description
		var desc_label := Label.new()
		desc_label.text = hint[1]
		desc_label.add_theme_font_size_override("font_size", 11)
		desc_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
		hbox.add_child(desc_label)

		col.add_child(hbox)

	return col


## Toggle the hotkey reference overlay.
func _toggle_hotkey_overlay() -> void:
	_hotkey_overlay_visible = not _hotkey_overlay_visible
	if _hotkey_overlay != null:
		_hotkey_overlay.visible = _hotkey_overlay_visible


## Setup the tutorial overlay for new players (F2 toggle).
func _setup_tutorial_overlay() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create semi-transparent background panel
	_tutorial_overlay = PanelContainer.new()
	_tutorial_overlay.name = "TutorialOverlay"
	_tutorial_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_tutorial_overlay.offset_left = -400
	_tutorial_overlay.offset_right = 400
	_tutorial_overlay.offset_top = -300
	_tutorial_overlay.offset_bottom = 300
	_tutorial_overlay.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.06, 0.12, 0.97)
	style.border_color = Color(0.3, 0.7, 1.0, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(12)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 25
	style.content_margin_bottom = 25
	_tutorial_overlay.add_theme_stylebox_override("panel", style)

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "TutorialContent"
	main_vbox.add_theme_constant_override("separation", 15)

	# Title
	var title := Label.new()
	title.name = "TutorialTitle"
	title.text = "📖 TUTORIAL - Welcome to AGI Day"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	main_vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "TutorialSubtitle"
	subtitle.text = "Press F2 to close | Arrow Keys or A/D to change page"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	main_vbox.add_child(subtitle)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	main_vbox.add_child(sep)

	# Page content container (will hold current page)
	var page_container := VBoxContainer.new()
	page_container.name = "PageContainer"
	page_container.add_theme_constant_override("separation", 12)
	page_container.custom_minimum_size.y = 380
	main_vbox.add_child(page_container)

	# Navigation footer
	var nav_sep := HSeparator.new()
	nav_sep.add_theme_constant_override("separation", 10)
	main_vbox.add_child(nav_sep)

	var nav_hbox := HBoxContainer.new()
	nav_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_hbox.add_theme_constant_override("separation", 20)

	var prev_btn := Button.new()
	prev_btn.name = "PrevButton"
	prev_btn.text = "◀ Previous"
	prev_btn.custom_minimum_size = Vector2(120, 35)
	prev_btn.pressed.connect(_tutorial_prev_page)
	nav_hbox.add_child(prev_btn)

	var page_label := Label.new()
	page_label.name = "PageLabel"
	page_label.text = "Page 1 / %d" % TUTORIAL_PAGE_COUNT
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.custom_minimum_size.x = 100
	page_label.add_theme_font_size_override("font_size", 14)
	page_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	nav_hbox.add_child(page_label)

	var next_btn := Button.new()
	next_btn.name = "NextButton"
	next_btn.text = "Next ▶"
	next_btn.custom_minimum_size = Vector2(120, 35)
	next_btn.pressed.connect(_tutorial_next_page)
	nav_hbox.add_child(next_btn)

	main_vbox.add_child(nav_hbox)

	_tutorial_overlay.add_child(main_vbox)
	ui_layer.add_child(_tutorial_overlay)

	# Initialize first page
	_update_tutorial_page()


## Update tutorial overlay to show current page content.
func _update_tutorial_page() -> void:
	if _tutorial_overlay == null:
		return

	var page_container: VBoxContainer = _tutorial_overlay.get_node_or_null("TutorialContent/PageContainer")
	if page_container == null:
		return

	# Clear existing content
	for child in page_container.get_children():
		child.queue_free()

	# Page content based on current page
	match _tutorial_page:
		0:
			_create_tutorial_page_objective(page_container)
		1:
			_create_tutorial_page_resources(page_container)
		2:
			_create_tutorial_page_units(page_container)
		3:
			_create_tutorial_page_controls(page_container)

	# Update page label
	var page_label: Label = _tutorial_overlay.get_node_or_null("TutorialContent/PageLabel")
	if page_label:
		page_label.text = "Page %d / %d" % [_tutorial_page + 1, TUTORIAL_PAGE_COUNT]

	# Update button states
	var prev_btn: Button = _tutorial_overlay.get_node_or_null("TutorialContent/PrevButton")
	var next_btn: Button = _tutorial_overlay.get_node_or_null("TutorialContent/NextButton")
	if prev_btn:
		prev_btn.disabled = (_tutorial_page == 0)
	if next_btn:
		next_btn.text = "Close ✓" if _tutorial_page == TUTORIAL_PAGE_COUNT - 1 else "Next ▶"


## Tutorial Page 1: Game Objective.
func _create_tutorial_page_objective(container: VBoxContainer) -> void:
	var page_title := Label.new()
	page_title.text = "🎯 OBJECTIVE"
	page_title.add_theme_font_size_override("font_size", 22)
	page_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	container.add_child(page_title)

	_add_tutorial_text(container, "It's AGI Day - the moment when four rival robot factions awaken and clash for dominance in a mega-city!")

	var objectives := VBoxContainer.new()
	objectives.add_theme_constant_override("separation", 8)

	_add_tutorial_bullet(objectives, "🏭", "Destroy Enemy Factories", "Each faction has a factory. Destroy all enemy factories to win!")
	_add_tutorial_bullet(objectives, "🗺️", "Dominate Districts", "Control 60%+ of the 25 districts for 2+ minutes to claim victory.")
	_add_tutorial_bullet(objectives, "⚔️", "Build Your Army", "Produce units, harvest resources, and crush the opposition!")

	container.add_child(objectives)

	_add_tutorial_text(container, "Choose your faction wisely - each has unique strengths:")

	var factions := HBoxContainer.new()
	factions.add_theme_constant_override("separation", 15)
	factions.alignment = BoxContainer.ALIGNMENT_CENTER

	_add_faction_chip(factions, "Aether Swarm", Color(0.3, 0.7, 1.0), "Fast & Stealthy")
	_add_faction_chip(factions, "OptiForge", Color(1.0, 0.4, 0.3), "Adaptive Hordes")
	_add_faction_chip(factions, "Dynapods", Color(0.3, 0.9, 0.4), "Agile Strikers")
	_add_faction_chip(factions, "LogiBots", Color(1.0, 0.85, 0.3), "Heavy Siege")

	container.add_child(factions)


## Tutorial Page 2: Resources.
func _create_tutorial_page_resources(container: VBoxContainer) -> void:
	var page_title := Label.new()
	page_title.text = "💎 RESOURCES"
	page_title.add_theme_font_size_override("font_size", 22)
	page_title.add_theme_color_override("font_color", Color(0.5, 1.0, 0.8))
	container.add_child(page_title)

	_add_tutorial_text(container, "REE (Rare Earth Elements) is the currency for everything. Gather it to build your army!")

	var sources := VBoxContainer.new()
	sources.add_theme_constant_override("separation", 10)

	_add_tutorial_bullet(sources, "💀", "Wreckage Collection", "When units die, they drop REE. Send harvesters to collect it!")
	_add_tutorial_bullet(sources, "🏛️", "District Control", "Each controlled district generates +3 REE/sec passive income.")
	_add_tutorial_bullet(sources, "🏗️", "Building Salvage", "Harvesters can disassemble damaged enemy buildings for bonus REE.")
	_add_tutorial_bullet(sources, "⚡", "Power Grid", "Buildings need power. Brownouts slow production; blackouts halt it entirely!")

	container.add_child(sources)

	_add_tutorial_text(container, "Pro tip: Control the industrial districts early - they have higher REE yields!")


## Tutorial Page 3: Unit Types.
func _create_tutorial_page_units(container: VBoxContainer) -> void:
	var page_title := Label.new()
	page_title.text = "🤖 UNIT TYPES"
	page_title.add_theme_font_size_override("font_size", 22)
	page_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.5))
	container.add_child(page_title)

	_add_tutorial_text(container, "Build the right mix of units to counter your enemies!")

	var units := VBoxContainer.new()
	units.add_theme_constant_override("separation", 10)

	_add_unit_info(units, "◆ Light (Scout)", "30 REE", "Fast, fragile. Great for scouting and harassment.", Color(0.5, 0.8, 1.0))
	_add_unit_info(units, "● Medium (Soldier)", "60 REE", "Balanced damage and health. Your army backbone.", Color(0.5, 1.0, 0.6))
	_add_unit_info(units, "■ Heavy (Tank)", "120 REE", "Slow but devastating. Splash damage on hit!", Color(1.0, 0.6, 0.4))
	_add_unit_info(units, "⬡ Harvester", "50 REE", "Collects REE from wreckage. Essential for economy!", Color(1.0, 0.85, 0.3))

	container.add_child(units)

	_add_tutorial_text(container, "Units gain veterancy from combat! Stars show their experience level.")


## Tutorial Page 4: Controls.
func _create_tutorial_page_controls(container: VBoxContainer) -> void:
	var page_title := Label.new()
	page_title.text = "🎮 CONTROLS"
	page_title.add_theme_font_size_override("font_size", 22)
	page_title.add_theme_color_override("font_color", Color(0.8, 0.7, 1.0))
	container.add_child(page_title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)

	# Column 1: Basic controls
	var col1 := VBoxContainer.new()
	col1.add_theme_constant_override("separation", 6)
	_add_control_item(col1, "Left Click", "Select units")
	_add_control_item(col1, "Right Click", "Move/Attack")
	_add_control_item(col1, "A + Click", "Attack-move")
	_add_control_item(col1, "WASD/Arrows", "Pan camera")
	_add_control_item(col1, "Mouse Wheel", "Zoom")
	_add_control_item(col1, "SPACE", "Jump to action")
	cols.add_child(col1)

	# Column 2: Production
	var col2 := VBoxContainer.new()
	col2.add_theme_constant_override("separation", 6)
	_add_control_item(col2, "1", "Queue Light unit")
	_add_control_item(col2, "2", "Queue Medium unit")
	_add_control_item(col2, "3", "Queue Heavy unit")
	_add_control_item(col2, "4", "Queue Harvester")
	_add_control_item(col2, "Shift+1-4", "Queue x5")
	_add_control_item(col2, "P", "Pause game")
	cols.add_child(col2)

	# Column 3: Abilities
	var col3 := VBoxContainer.new()
	col3.add_theme_constant_override("separation", 6)
	_add_control_item(col3, "Q", "Primary ability")
	_add_control_item(col3, "E", "Secondary ability")
	_add_control_item(col3, "B", "Special attack")
	_add_control_item(col3, "F/C", "Formation abilities")
	_add_control_item(col3, "H or ?", "Hotkey reference")
	_add_control_item(col3, "F2", "This tutorial")
	cols.add_child(col3)

	container.add_child(cols)

	_add_tutorial_text(container, "Good luck, Commander! May your faction reign supreme on AGI Day!")


## Helper: Add tutorial text paragraph.
func _add_tutorial_text(container: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(label)


## Helper: Add tutorial bullet point.
func _add_tutorial_bullet(container: VBoxContainer, icon: String, title: String, desc: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)

	var icon_label := Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 20)
	icon_label.custom_minimum_size.x = 30
	hbox.add_child(icon_label)

	var text_vbox := VBoxContainer.new()
	text_vbox.add_theme_constant_override("separation", 2)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	text_vbox.add_child(title_label)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	text_vbox.add_child(desc_label)

	hbox.add_child(text_vbox)
	container.add_child(hbox)


## Helper: Add faction chip for overview.
func _add_faction_chip(container: HBoxContainer, name: String, color: Color, desc: String) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.7)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 9)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc_label)

	panel.add_child(vbox)
	container.add_child(panel)


## Helper: Add unit info row.
func _add_unit_info(container: VBoxContainer, name: String, cost: String, desc: String, color: Color) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)

	var name_label := Label.new()
	name_label.text = name
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", color)
	name_label.custom_minimum_size.x = 160
	hbox.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = cost
	cost_label.add_theme_font_size_override("font_size", 13)
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	cost_label.custom_minimum_size.x = 60
	hbox.add_child(cost_label)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85))
	hbox.add_child(desc_label)

	container.add_child(hbox)


## Helper: Add control item.
func _add_control_item(container: VBoxContainer, key: String, action: String) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)

	var key_label := Label.new()
	key_label.text = "[%s]" % key
	key_label.add_theme_font_size_override("font_size", 12)
	key_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	key_label.custom_minimum_size.x = 100
	hbox.add_child(key_label)

	var action_label := Label.new()
	action_label.text = action
	action_label.add_theme_font_size_override("font_size", 12)
	action_label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.9))
	hbox.add_child(action_label)

	container.add_child(hbox)


## Tutorial navigation: previous page.
func _tutorial_prev_page() -> void:
	if _tutorial_page > 0:
		_tutorial_page -= 1
		_update_tutorial_page()
		_play_ui_sound("click")


## Tutorial navigation: next page (or close on last page).
func _tutorial_next_page() -> void:
	if _tutorial_page < TUTORIAL_PAGE_COUNT - 1:
		_tutorial_page += 1
		_update_tutorial_page()
		_play_ui_sound("click")
	else:
		# Close tutorial on last page
		_toggle_tutorial_overlay()


## Toggle the tutorial overlay.
func _toggle_tutorial_overlay() -> void:
	_tutorial_overlay_visible = not _tutorial_overlay_visible
	if _tutorial_overlay != null:
		_tutorial_overlay.visible = _tutorial_overlay_visible
		if _tutorial_overlay_visible:
			_tutorial_page = 0
			_update_tutorial_page()
			_play_ui_sound("notification")


## Setup pause overlay.
func _setup_pause_overlay() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create full-screen overlay
	_pause_overlay = ColorRect.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.color = Color(0.0, 0.0, 0.0, 0.7)
	_pause_overlay.visible = false
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block input
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused

	# Create centered content container
	var center_container := CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)

	# PAUSED title
	var paused_label := Label.new()
	paused_label.text = "PAUSED"
	paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	paused_label.add_theme_font_size_override("font_size", 72)
	paused_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	paused_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	paused_label.add_theme_constant_override("shadow_offset_x", 4)
	paused_label.add_theme_constant_override("shadow_offset_y", 4)
	vbox.add_child(paused_label)

	# Instructions
	var instructions := Label.new()
	instructions.text = "Press ESC or P to resume\nPress Q to quit"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 24)
	instructions.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	vbox.add_child(instructions)

	# Stats panel
	var stats_panel := PanelContainer.new()
	var stats_style := StyleBoxFlat.new()
	stats_style.bg_color = Color(0.1, 0.1, 0.2, 0.8)
	stats_style.set_border_width_all(2)
	stats_style.border_color = Color(0.4, 0.5, 0.7)
	stats_style.set_corner_radius_all(8)
	stats_style.content_margin_left = 20
	stats_style.content_margin_right = 20
	stats_style.content_margin_top = 15
	stats_style.content_margin_bottom = 15
	stats_panel.add_theme_stylebox_override("panel", stats_style)

	var stats_vbox := VBoxContainer.new()
	stats_vbox.add_theme_constant_override("separation", 8)

	var stats_title := Label.new()
	stats_title.text = "MATCH STATS"
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_title.add_theme_font_size_override("font_size", 20)
	stats_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	stats_vbox.add_child(stats_title)

	var kills_label := Label.new()
	kills_label.name = "PauseKillsLabel"
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kills_label.add_theme_font_size_override("font_size", 16)
	stats_vbox.add_child(kills_label)

	var ree_label := Label.new()
	ree_label.name = "PauseREELabel"
	ree_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ree_label.add_theme_font_size_override("font_size", 16)
	stats_vbox.add_child(ree_label)

	var time_label := Label.new()
	time_label.name = "PauseTimeLabel"
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 16)
	stats_vbox.add_child(time_label)

	stats_panel.add_child(stats_vbox)
	vbox.add_child(stats_panel)

	center_container.add_child(vbox)
	_pause_overlay.add_child(center_container)
	ui_layer.add_child(_pause_overlay)


## Toggle game pause state.
func _toggle_pause() -> void:
	_is_game_paused = not _is_game_paused

	if _is_game_paused:
		# Pause the game
		get_tree().paused = true
		_pause_overlay.visible = true

		# Update stats in pause menu (using comprehensive stat tracking)
		var player_stats := _get_faction_stats(_player_faction)

		var kills_label := _pause_overlay.get_node_or_null("CenterContainer/VBoxContainer/PanelContainer/VBoxContainer/PauseKillsLabel")
		if kills_label:
			var kd_ratio := float(player_stats.kills) / maxf(1.0, float(player_stats.deaths))
			kills_label.text = "Kills: %d | Deaths: %d (%.1f K/D)" % [player_stats.kills, player_stats.deaths, kd_ratio]

		var ree_label := _pause_overlay.get_node_or_null("CenterContainer/VBoxContainer/PanelContainer/VBoxContainer/PauseREELabel")
		if ree_label:
			var current_ree: float = ResourceManager.get_current_ree(_player_faction) if ResourceManager else 0.0
			ree_label.text = "REE: %.0f | Earned: %.0f | Spent: %.0f" % [current_ree, player_stats.ree_earned, player_stats.ree_spent]

		var time_label := _pause_overlay.get_node_or_null("CenterContainer/VBoxContainer/PanelContainer/VBoxContainer/PauseTimeLabel")
		if time_label:
			var duration := GameStateManager.get_match_duration()
			var minutes := int(duration) / 60
			var seconds := int(duration) % 60
			time_label.text = "Time: %02d:%02d | Units: %d | Districts: %d" % [minutes, seconds, player_stats.units_produced, player_stats.districts_captured]
	else:
		# Resume the game
		get_tree().paused = false
		_pause_overlay.visible = false


## Toggle camera follow mode for selected unit.
func _toggle_camera_follow() -> void:
	if _camera_follow_mode:
		# Disable follow mode
		_camera_follow_mode = false
		_camera_follow_target = {}
		print("Camera follow: OFF")
	else:
		# Enable follow mode if we have a selected unit
		if not _selected_units.is_empty():
			_camera_follow_mode = true
			_camera_follow_target = _selected_units[0]
			print("Camera follow: ON (following unit)")
		else:
			print("Camera follow: No unit selected")


## Save camera position to bookmark slot.
func _save_camera_bookmark(slot: int) -> void:
	_camera_bookmarks[slot] = _camera_look_at
	_spawn_command_text(_camera_look_at, "SAVED F%d" % slot, Color(0.4, 0.8, 1.0))
	print("Camera bookmark F%d saved at (%.0f, %.0f)" % [slot, _camera_look_at.x, _camera_look_at.z])


## Recall camera position from bookmark slot.
func _recall_camera_bookmark(slot: int) -> void:
	if _camera_bookmarks.has(slot):
		_camera_look_at = _camera_bookmarks[slot]
		print("Camera bookmark F%d recalled" % slot)
	else:
		print("Camera bookmark F%d not set (Ctrl+F%d to save)" % [slot, slot])


## Toggle auto-attack mode for selected units.
func _toggle_auto_attack() -> void:
	if _selected_units.is_empty():
		# Toggle global default
		_auto_attack_enabled = not _auto_attack_enabled
		var status := "ON" if _auto_attack_enabled else "OFF"
		_spawn_command_text(_camera_look_at, "AUTO-ATTACK %s" % status, Color(1.0, 0.8, 0.3))
		print("Auto-attack (global): %s" % status)
	else:
		# Toggle for selected units
		var first_unit_auto: bool = _selected_units[0].get("auto_attack", _auto_attack_enabled)
		var new_state: bool = not first_unit_auto

		for unit in _selected_units:
			if not unit.is_dead:
				unit["auto_attack"] = new_state

		var center_pos := Vector3.ZERO
		var count := 0
		for unit in _selected_units:
			if not unit.is_dead and is_instance_valid(unit.mesh):
				center_pos += unit.mesh.position
				count += 1
		if count > 0:
			center_pos /= count

		var status := "ON" if new_state else "OFF"
		_spawn_command_text(center_pos, "AUTO-ATTACK %s" % status, Color(1.0, 0.8, 0.3))
		_flash_units_on_command(_selected_units, Color(1.0, 0.8, 0.3))
		print("Auto-attack for %d units: %s" % [count, status])


## Change game speed (+/- step).
func _change_game_speed(delta: float) -> void:
	_game_speed = clampf(_game_speed + delta, GAME_SPEED_MIN, GAME_SPEED_MAX)
	Engine.time_scale = _game_speed
	_update_game_speed_label()
	print("Game speed: %.2fx" % _game_speed)


## Setup game speed label and buttons in UI.
func _setup_game_speed_label() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create container for speed controls
	var speed_container := HBoxContainer.new()
	speed_container.name = "SpeedControls"
	speed_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	speed_container.offset_left = -280
	speed_container.offset_right = -10
	speed_container.offset_top = 8
	speed_container.add_theme_constant_override("separation", 4)
	ui_layer.add_child(speed_container)

	# Speed label
	var speed_title := Label.new()
	speed_title.text = "Speed:"
	speed_title.add_theme_font_size_override("font_size", 14)
	speed_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	speed_container.add_child(speed_title)

	# Speed preset buttons
	var speed_presets := [0.5, 0.75, 1.0, 1.5, 2.0]
	var speed_labels := ["0.5x", "0.75x", "1x", "1.5x", "2x"]
	for i in speed_presets.size():
		var btn := Button.new()
		btn.name = "Speed_" + str(speed_presets[i])
		btn.text = speed_labels[i]
		btn.custom_minimum_size = Vector2(40, 24)
		btn.add_theme_font_size_override("font_size", 12)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.2, 0.25, 0.9)
		style.border_color = Color(0.3, 0.5, 0.7, 0.8)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(2)
		btn.add_theme_stylebox_override("normal", style)

		var hover_style := style.duplicate()
		hover_style.bg_color = Color(0.2, 0.3, 0.4, 0.9)
		btn.add_theme_stylebox_override("hover", hover_style)

		var pressed_style := style.duplicate()
		pressed_style.bg_color = Color(0.3, 0.5, 0.7, 0.9)
		pressed_style.border_color = Color(0.5, 0.8, 1.0)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		var speed_val: float = speed_presets[i]
		btn.pressed.connect(func(): _set_game_speed(speed_val))
		speed_container.add_child(btn)

	# Current speed indicator label
	_game_speed_label = Label.new()
	_game_speed_label.name = "GameSpeedLabel"
	_game_speed_label.text = ""
	_game_speed_label.add_theme_font_size_override("font_size", 14)
	_game_speed_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_game_speed_label.custom_minimum_size = Vector2(60, 20)
	speed_container.add_child(_game_speed_label)


## Set game speed to specific value.
func _set_game_speed(speed: float) -> void:
	_game_speed = clampf(speed, GAME_SPEED_MIN, GAME_SPEED_MAX)
	Engine.time_scale = _game_speed
	_update_game_speed_label()
	_play_ui_sound("click")
	print("Game speed set to: %.2fx" % _game_speed)


## Update game speed label visibility and text.
func _update_game_speed_label() -> void:
	if _game_speed_label == null:
		return

	# Only show label when speed is not 1x
	if absf(_game_speed - 1.0) < 0.01:
		_game_speed_label.text = ""
	else:
		var color := Color(0.5, 1.0, 0.5) if _game_speed > 1.0 else Color(1.0, 0.7, 0.3)
		_game_speed_label.add_theme_color_override("font_color", color)
		_game_speed_label.text = "SPEED: %.2fx" % _game_speed


## Setup unit count by type label.
func _setup_unit_count_label() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	_unit_count_label = Label.new()
	_unit_count_label.name = "UnitCountLabel"
	_unit_count_label.add_theme_font_size_override("font_size", 14)
	_unit_count_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

	# Position below game speed label in top-right
	_unit_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_unit_count_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_unit_count_label.offset_left = -150
	_unit_count_label.offset_right = -10
	_unit_count_label.offset_top = 30

	ui_layer.add_child(_unit_count_label)


## Update unit count by type display.
func _update_unit_count_display() -> void:
	if _unit_count_label == null:
		return

	var light_count := 0
	var medium_count := 0
	var heavy_count := 0

	for unit in _units:
		if unit.is_dead or unit.faction_id != _player_faction:
			continue
		var unit_type: String = unit.get("unit_type", "light")
		match unit_type:
			"light":
				light_count += 1
			"medium":
				medium_count += 1
			"heavy":
				heavy_count += 1

	var total := light_count + medium_count + heavy_count
	_unit_count_label.text = "Units: %d (L:%d M:%d H:%d)" % [total, light_count, medium_count, heavy_count]


## Setup resource stats label (total REE earned).
func _setup_ree_stats_label() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	_ree_stats_label = Label.new()
	_ree_stats_label.name = "REEStatsLabel"
	_ree_stats_label.add_theme_font_size_override("font_size", 14)
	_ree_stats_label.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))

	# Position below unit count in top-right
	_ree_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ree_stats_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ree_stats_label.offset_left = -150
	_ree_stats_label.offset_right = -10
	_ree_stats_label.offset_top = 48

	ui_layer.add_child(_ree_stats_label)


## Update resource stats display.
func _update_ree_stats_display() -> void:
	if _ree_stats_label == null:
		return

	_ree_stats_label.text = "Total REE: %.0f" % _total_ree_earned


## Update camera follow (called in camera update).
func _update_camera_follow() -> void:
	if not _camera_follow_mode or _camera_follow_target.is_empty():
		return

	# Check if target is still valid
	if _camera_follow_target.is_dead or not is_instance_valid(_camera_follow_target.mesh):
		_camera_follow_mode = false
		_camera_follow_target = {}
		print("Camera follow: Target lost")
		return

	# Move camera to follow target
	var target_pos: Vector3 = _camera_follow_target.mesh.position
	_camera_look_at = Vector3(target_pos.x, 0, target_pos.z)


## Center camera on control group units.
func _center_camera_on_group(group_num: int) -> void:
	if not _control_groups.has(group_num):
		return

	var group: Array = _control_groups[group_num]
	var alive_units: Array = []

	for unit in group:
		if not unit.is_dead and is_instance_valid(unit.mesh):
			alive_units.append(unit)

	if alive_units.is_empty():
		return

	# Calculate center of all units
	var center := Vector3.ZERO
	for unit in alive_units:
		center += unit.mesh.position
	center /= alive_units.size()

	# Move camera to center
	_camera_look_at = Vector3(center.x, 0, center.z)
	_camera_look_at.x = clampf(_camera_look_at.x, -CAMERA_BOUNDS, CAMERA_BOUNDS)
	_camera_look_at.z = clampf(_camera_look_at.z, -CAMERA_BOUNDS, CAMERA_BOUNDS)

	print("Camera centered on group %d (%d units)" % [group_num, alive_units.size()])


## Update unit tooltip based on mouse position.
func _update_unit_tooltip() -> void:
	if _tooltip_panel == null or camera == null:
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var world_pos := _screen_to_world(mouse_pos)

	if world_pos == Vector3.ZERO:
		_tooltip_panel.visible = false
		_hovered_unit = {}
		return

	# Find unit under mouse cursor
	var closest_unit: Dictionary = {}
	var closest_dist := TOOLTIP_HOVER_DISTANCE

	for unit in _units:
		if unit.is_dead or not is_instance_valid(unit.mesh):
			continue
		var unit_pos: Vector3 = unit.mesh.position
		var dist: float = Vector2(world_pos.x - unit_pos.x, world_pos.z - unit_pos.z).length()
		if dist < closest_dist:
			closest_dist = dist
			closest_unit = unit

	if closest_unit.is_empty():
		_tooltip_panel.visible = false
		_hovered_unit = {}
		return

	_hovered_unit = closest_unit

	# Build tooltip text
	var faction_names := {1: "Aether Swarm", 2: "OptiForge", 3: "Dynapods", 4: "LogiBots", 5: "Human Remnant"}
	var faction_name: String = faction_names.get(closest_unit.faction_id, "Unknown")
	var unit_type: String = closest_unit.get("unit_type", "unit").capitalize()
	var health: float = closest_unit.get("health", 0)
	var max_health: float = closest_unit.get("max_health", 100)
	var damage: float = _get_unit_damage(closest_unit)
	var speed: float = _get_unit_speed(closest_unit)
	var attack_speed: float = closest_unit.get("attack_speed", 1.0)
	var attack_range: float = closest_unit.get("attack_range", ATTACK_RANGE)
	var vet_level: int = closest_unit.get("veterancy_level", 0)
	var xp: float = closest_unit.get("xp", 0)

	var tooltip_text := "%s - %s\n" % [faction_name, unit_type]
	tooltip_text += "HP: %.0f/%.0f\n" % [health, max_health]
	tooltip_text += "DMG: %.0f | DPS: %.1f\n" % [damage, damage * attack_speed]
	tooltip_text += "SPD: %.0f | RNG: %.0f\n" % [speed, attack_range]

	if vet_level > 0:
		var vet_stars := "★".repeat(vet_level)
		tooltip_text += "Veteran: %s (%.0f XP)" % [vet_stars, xp]
	else:
		var next_threshold: float = VETERANCY_XP_THRESHOLDS[1] if VETERANCY_XP_THRESHOLDS.size() > 1 else 100
		tooltip_text += "XP: %.0f/%.0f" % [xp, next_threshold]

	_tooltip_label.text = tooltip_text

	# Position tooltip near mouse but offset to not cover cursor
	_tooltip_panel.position = mouse_pos + Vector2(15, 15)

	# Keep tooltip on screen
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_size := _tooltip_panel.size
	if _tooltip_panel.position.x + panel_size.x > viewport_size.x:
		_tooltip_panel.position.x = mouse_pos.x - panel_size.x - 10
	if _tooltip_panel.position.y + panel_size.y > viewport_size.y:
		_tooltip_panel.position.y = mouse_pos.y - panel_size.y - 10

	_tooltip_panel.visible = true


## Check if we should play a sound (throttling to prevent overload).
func _should_play_sound() -> bool:
	var current_time := Time.get_ticks_msec() / 1000.0
	if _sounds_this_frame >= MAX_SOUNDS_PER_FRAME:
		return false
	if current_time - _last_sound_time < SOUND_MIN_INTERVAL:
		return false
	_sounds_this_frame += 1
	_last_sound_time = current_time
	return true


## Reset sound counter at start of each frame.
func _reset_sound_counter() -> void:
	_sounds_this_frame = 0


## Update audio manager and dynamic music based on combat intensity.
func _update_audio_manager(delta: float) -> void:
	if _audio_manager == null:
		return

	# Update the audio manager
	_audio_manager.update(delta)

	# Update battle intensity tracker (every frame for smooth intensity)
	if _battle_intensity_tracker != null:
		_battle_intensity_tracker.update(delta)
		# Sync intensity to music manager
		var music_manager := _audio_manager.get_music_manager()
		if music_manager != null:
			music_manager.set_battle_intensity(_battle_intensity_tracker.get_intensity())

	# Update combat intensity for dynamic music (throttled)
	_combat_intensity_update_timer += delta
	if _combat_intensity_update_timer >= COMBAT_INTENSITY_UPDATE_INTERVAL:
		_combat_intensity_update_timer = 0.0
		_update_combat_intensity()


## Calculate and report combat intensity for dynamic music.
func _update_combat_intensity() -> void:
	if _audio_manager == null:
		return

	# Count player units and enemy units
	var player_unit_count := 0
	var enemy_unit_count := 0
	var in_combat := false

	for unit in _units:
		if unit.get("is_dead", false):
			continue
		if unit.get("faction_id", 0) == _player_faction:
			player_unit_count += 1
			# Check if this unit has a target (in combat)
			if unit.get("target", null) != null:
				in_combat = true
		else:
			enemy_unit_count += 1

	# Report to audio manager for dynamic music adjustment
	_audio_manager.report_battle_intensity(player_unit_count, enemy_unit_count, in_combat)

	# Update battle intensity tracker for detailed intensity calculation
	if _battle_intensity_tracker != null:
		_battle_intensity_tracker.report_unit_counts(player_unit_count, enemy_unit_count)


## Combat started callback - music transitions to combat state.
func _on_combat_started() -> void:
	if _audio_manager != null:
		var music_manager := _audio_manager.get_music_manager()
		if music_manager != null:
			music_manager.transition_to_state(DynamicMusicManager.MusicState.LOW_TENSION)


## Combat ended callback - music returns to ambient.
func _on_combat_ended() -> void:
	if _audio_manager != null:
		var music_manager := _audio_manager.get_music_manager()
		if music_manager != null:
			music_manager.resume_ambient()


## Intensity spike callback - for dramatic moments.
func _on_intensity_spike(level: float) -> void:
	# Trigger screen shake for intense moments
	if level >= 0.6:
		_trigger_screen_shake(level * 0.3)


## Play UI sound effect (button click, notification, etc.)
func _play_ui_sound(sound_type: String) -> void:
	if _audio_manager == null:
		return

	# Use procedural sounds for now since we don't have audio files
	var player := _get_audio_player()
	match sound_type:
		"click":
			player.stream = _generate_ui_click_sound()
			player.volume_db = -10.0
		"hover":
			player.stream = _generate_ui_hover_sound()
			player.volume_db = -15.0
		"error":
			player.stream = _generate_ui_error_sound()
			player.volume_db = -8.0
		"notification":
			player.stream = _generate_ui_notification_sound()
			player.volume_db = -6.0
		"production_complete":
			player.stream = _generate_production_complete_sound()
			player.volume_db = -6.0
		_:
			return
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()


## Play unit acknowledgment sound (selection, move, attack, etc.)
## faction_id affects the pitch/tone of the sound
func _play_unit_sound(sound_type: String, faction_id: int = 0) -> void:
	var player := _get_audio_player()
	if player == null:
		return

	# Faction-specific pitch modifiers (gives each faction a unique "voice")
	var faction_pitch := 1.0
	match faction_id:
		1:  # Aether Swarm - higher pitched, ethereal
			faction_pitch = 1.2
		2:  # OptiForge - standard robotic
			faction_pitch = 1.0
		3:  # Dynapods - slightly higher, agile
			faction_pitch = 1.1
		4:  # LogiBots - lower, heavier
			faction_pitch = 0.85

	match sound_type:
		"select":
			player.stream = _generate_select_sound()
			player.volume_db = -8.0
		"move":
			player.stream = _generate_move_sound()
			player.volume_db = -6.0
		"attack":
			player.stream = _generate_attack_sound()
			player.volume_db = -5.0
		"stop":
			player.stream = _generate_stop_sound()
			player.volume_db = -7.0
		"ready":
			player.stream = _generate_unit_ready_sound()
			player.volume_db = -5.0
		_:
			return

	# Apply faction pitch with small random variation
	player.pitch_scale = faction_pitch * randf_range(0.95, 1.05)
	player.play()


## Generate stop/halt command sound (descending tone).
func _generate_stop_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.1
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Descending tone (indicates stopping)
		var freq := 600.0 - progress * 300.0
		var wave := sin(t * freq * TAU) * 0.5

		# Quick decay envelope
		var env := pow(1.0 - progress, 0.8)

		var sample_value := int(wave * env * 10000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate unit ready sound (triumphant ascending arpeggio).
func _generate_unit_ready_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.25
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Three-note ascending arpeggio
		var note_idx := int(progress * 3.0)
		var freqs: Array[float] = [400.0, 500.0, 600.0]  # Major chord notes
		var freq: float = freqs[mini(note_idx, 2)]

		var wave := sin(t * freq * TAU) * 0.5
		wave += sin(t * freq * 2.0 * TAU) * 0.2  # Harmonic

		# Envelope with distinct notes
		var note_progress := fmod(progress * 3.0, 1.0)
		var env := sin(note_progress * PI) * 0.8

		# Overall fade
		env *= 1.0 - progress * 0.3

		var sample_value := int(wave * env * 10000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate a UI click sound (short blip).
func _generate_ui_click_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.05
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Quick sine wave blip
		var freq := 1200.0
		var wave := sin(t * freq * TAU)
		var env := (1.0 - progress) * (1.0 - progress)

		var sample_value := int(wave * env * 12000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate a UI hover sound (soft chirp).
func _generate_ui_hover_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.03
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		var freq := 800.0 + progress * 400.0  # Rising pitch
		var wave := sin(t * freq * TAU)
		var env := (1.0 - progress)

		var sample_value := int(wave * env * 8000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate a UI error sound (descending buzz).
func _generate_ui_error_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.2
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Two descending tones for dissonance
		var freq1 := 400.0 - progress * 150.0
		var freq2 := 350.0 - progress * 100.0
		var wave := sin(t * freq1 * TAU) * 0.6 + sin(t * freq2 * TAU) * 0.4
		var env := (1.0 - progress)

		var sample_value := int(wave * env * 10000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate a UI notification sound (pleasant ding).
func _generate_ui_notification_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.3
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Harmonious chord (major third)
		var freq1 := 880.0  # A5
		var freq2 := 1108.73  # C#6 (major third)
		var wave := sin(t * freq1 * TAU) * 0.6 + sin(t * freq2 * TAU) * 0.4
		var env := (1.0 - progress) * (1.0 - progress)

		var sample_value := int(wave * env * 12000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Get an available 2D audio player from pool.
func _get_audio_player() -> AudioStreamPlayer:
	for player in _audio_players:
		if not player.playing:
			return player
	return _audio_players[0]  # Steal oldest if all busy


## Get an available 3D audio player from pool.
func _get_audio_3d_player() -> AudioStreamPlayer3D:
	for player in _audio_3d_players:
		if not player.playing:
			return player
	return _audio_3d_players[0]


## Play a procedural "pew" laser sound at position.
func _play_laser_sound(pos: Vector3) -> void:
	var player := _get_audio_3d_player()
	player.global_position = pos
	player.stream = _generate_laser_sound()
	player.volume_db = -12.0
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()


## Play a procedural explosion sound at position.
func _play_explosion_sound(pos: Vector3, size: float = 1.0) -> void:
	var player := _get_audio_3d_player()
	player.global_position = pos
	player.stream = _generate_explosion_sound(size)
	player.volume_db = -6.0 + size * 3.0
	player.pitch_scale = randf_range(0.8, 1.0) / size
	player.play()


## Play a deep mortar BOOM sound at position.
func _play_mortar_fire_sound(pos: Vector3) -> void:
	var player := _get_audio_3d_player()
	player.global_position = pos
	player.stream = _generate_mortar_boom_sound()
	player.volume_db = 3.0  # Loud!
	player.pitch_scale = randf_range(0.85, 0.95)
	player.max_distance = 2000.0  # Hearable from far away
	player.play()


## Generate a deep mortar boom sound.
func _generate_mortar_boom_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.8
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)  # 16-bit samples

	for i in samples:
		var t: float = float(i) / float(sample_rate)
		var progress: float = t / duration

		# Deep boom with multiple harmonics
		var base_freq := 40.0 * (1.0 - progress * 0.5)  # Very low rumble
		var harm1 := 80.0 * (1.0 - progress * 0.3)
		var harm2 := 120.0 * (1.0 - progress * 0.2)

		# Combine harmonics
		var sample := sin(t * TAU * base_freq) * 0.5
		sample += sin(t * TAU * harm1) * 0.3
		sample += sin(t * TAU * harm2) * 0.15

		# Add crack/thump at start
		var crack := 0.0
		if t < 0.05:
			crack = randf_range(-1.0, 1.0) * (1.0 - t / 0.05) * 0.8
		sample += crack

		# Envelope - sharp attack, long decay
		var envelope := 1.0
		if t < 0.02:
			envelope = t / 0.02  # Quick attack
		else:
			envelope = exp(-progress * 4.0)  # Exponential decay

		sample *= envelope
		sample = clampf(sample, -0.95, 0.95)

		var int_sample := int(sample * 32767)
		data[i * 2] = int_sample & 0xFF
		data[i * 2 + 1] = (int_sample >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	return stream


## Play a procedural impact/hit sound at position.
func _play_hit_sound(pos: Vector3) -> void:
	var player := _get_audio_3d_player()
	player.global_position = pos
	player.stream = _generate_hit_sound()
	player.volume_db = -15.0
	player.pitch_scale = randf_range(0.8, 1.2)
	player.play()


## Generate a procedural laser/pew sound.
func _generate_laser_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.15
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)  # 16-bit samples

	var freq_start := 800.0
	var freq_end := 200.0

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Frequency sweep down
		var freq := lerpf(freq_start, freq_end, progress)
		var wave := sin(t * freq * TAU)

		# Envelope (quick attack, decay)
		var env := (1.0 - progress) * (1.0 - progress)

		var sample_value := int(wave * env * 16000)
		sample_value = clampi(sample_value, -32768, 32767)

		# Store as 16-bit little-endian
		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate a procedural explosion sound.
func _generate_explosion_sound(size: float = 1.0) -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.3 * size
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = randi()

	for i in samples:
		var progress := float(i) / samples

		# Noise burst with low-pass filter effect (simulated by averaging)
		var noise := rng.randf_range(-1.0, 1.0)

		# Add some low frequency rumble
		var t := float(i) / sample_rate
		var rumble := sin(t * 60.0 * TAU) * 0.5

		# Envelope (quick attack, longer decay)
		var env := pow(1.0 - progress, 1.5)

		var sample_value := int((noise * 0.6 + rumble * 0.4) * env * 20000 * size)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate a procedural hit/impact sound.
func _generate_hit_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.08
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Quick metallic click - high frequency with fast decay
		var wave := sin(t * 1500.0 * TAU) * 0.5 + sin(t * 2200.0 * TAU) * 0.3

		# Very quick envelope
		var env := pow(1.0 - progress, 3.0)

		var sample_value := int(wave * env * 12000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Play unit selection sound (short blip).
## Now faction-aware for distinct unit voices.
func _play_select_sound() -> void:
	_play_unit_sound("select", _player_faction)


## Play move command confirmation sound.
## Now faction-aware for distinct unit voices.
func _play_move_command_sound() -> void:
	_play_unit_sound("move", _player_faction)


## Play attack command sound (more aggressive).
## Now faction-aware for distinct unit voices.
func _play_attack_command_sound() -> void:
	_play_unit_sound("attack", _player_faction)


## Play stop command sound.
func _play_stop_command_sound() -> void:
	_play_unit_sound("stop", _player_faction)


## Play unit ready sound (when production completes).
func _play_unit_ready_sound() -> void:
	_play_unit_sound("ready", _player_faction)


## Play production started sound.
func _play_production_start_sound() -> void:
	var player := _get_audio_player()
	player.stream = _generate_production_start_sound()
	player.volume_db = -10.0
	player.pitch_scale = 1.0
	player.play()


## Play production complete sound.
func _play_production_complete_sound() -> void:
	var player := _get_audio_player()
	player.stream = _generate_production_complete_sound()
	player.volume_db = -8.0
	player.pitch_scale = 1.0
	player.play()


## Generate a short blip for unit selection.
func _generate_select_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.05
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Short click with rising tone
		var freq := 600.0 + progress * 400.0
		var wave := sin(t * freq * TAU) * 0.6

		# Quick attack/decay envelope
		var env := sin(progress * PI)

		var sample_value := int(wave * env * 10000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate move command confirmation sound (two-tone beep).
func _generate_move_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.12
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Two-tone beep (low then high)
		var freq := 400.0 if progress < 0.5 else 600.0
		var wave := sin(t * freq * TAU) * 0.5

		# Smooth envelope
		var env := sin(progress * PI) * 0.8

		var sample_value := int(wave * env * 10000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate attack command sound (aggressive chord).
func _generate_attack_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.15
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Aggressive minor chord with slight dissonance
		var wave := sin(t * 300.0 * TAU) * 0.4
		wave += sin(t * 360.0 * TAU) * 0.3  # Minor third
		wave += sin(t * 450.0 * TAU) * 0.3  # Fifth

		# Sharp attack, quick decay
		var env := pow(1.0 - progress, 1.5)

		var sample_value := int(wave * env * 12000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate production start sound (mechanical startup).
func _generate_production_start_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.2
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Mechanical startup - rising pitch with clunky harmonics
		var freq := 150.0 + progress * 200.0
		var wave := sin(t * freq * TAU) * 0.5
		wave += sin(t * freq * 2.0 * TAU) * 0.2  # Harmonic
		wave += sin(t * 80.0 * TAU) * (1.0 - progress) * 0.3  # Low rumble

		# Ramp-up envelope
		var env := progress * (1.0 - progress * 0.3)

		var sample_value := int(wave * env * 10000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


## Generate production complete sound (triumphant chime).
func _generate_production_complete_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.3
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Major chord arpeggio (C-E-G progression)
		var note_time := fmod(progress * 3.0, 1.0)
		var note_idx := int(progress * 3.0)
		var freqs := [523.0, 659.0, 784.0]  # C5, E5, G5
		var freq: float = freqs[mini(note_idx, 2)]

		var wave := sin(t * freq * TAU) * 0.5
		wave += sin(t * freq * 2.0 * TAU) * 0.2  # Octave harmonic

		# Bell-like decay per note
		var note_env := pow(1.0 - note_time, 2.0)
		var global_env := 1.0 - progress * 0.5

		var sample_value := int(wave * note_env * global_env * 10000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


func _update_resource_panel() -> void:
	# Update REE display with income rate
	if ree_label and ResourceManager:
		var ree: float = ResourceManager.get_current_ree(_player_faction)  # Faction 1 (player)

		# Calculate income rate (smoothed over time)
		_income_update_timer += get_process_delta_time()
		if _income_update_timer >= INCOME_UPDATE_INTERVAL:
			var ree_change: float = ree - _last_ree_value
			# Smooth the income rate (exponential moving average)
			_ree_income_rate = _ree_income_rate * 0.7 + (ree_change / _income_update_timer) * 0.3
			_last_ree_value = ree
			_income_update_timer = 0.0

		# Display REE with income rate
		if _ree_income_rate > 0.5:
			ree_label.text = "REE: %d (+%.0f/s)" % [int(ree), _ree_income_rate]
			ree_label.modulate = Color(0.3, 1.0, 0.3)  # Green for positive income
		elif _ree_income_rate < -0.5:
			ree_label.text = "REE: %d (%.0f/s)" % [int(ree), _ree_income_rate]
			ree_label.modulate = Color(1.0, 0.5, 0.3)  # Orange for spending
		else:
			ree_label.text = "REE: %d" % int(ree)
			ree_label.modulate = Color(0.3, 0.9, 0.3)  # Default green

		# Low resources warning - flash red when below 50 REE
		if ree < 50:
			var pulse: float = (sin(Time.get_ticks_msec() / 200.0) + 1.0) / 2.0
			ree_label.modulate = Color(1.0, 0.2 + pulse * 0.3, 0.2 + pulse * 0.3)
			if ree < 25:
				ree_label.text = "⚠ " + ree_label.text + " ⚠"

	# Update power status indicator
	_update_power_status_display()

	# Update district status indicator
	_update_district_status_display()

	# Update ability displays with cooldown info and ready flash
	var current_time: float = Time.get_ticks_msec() / 1000.0

	if ability_e_label and _phase_shift:
		var cooldown: float = _phase_shift.get_cooldown_remaining()
		var was_on_cd: bool = _ability_cooldown_states.get("phase_shift", false)
		if cooldown > 0:
			ability_e_label.text = "[E] Phase (%.1fs)" % cooldown
			ability_e_label.modulate = Color(0.5, 0.5, 0.5)
			_ability_cooldown_states["phase_shift"] = true
		elif _phase_shift.get_phased_count() > 0:
			ability_e_label.text = "[E] PHASING"
			ability_e_label.modulate = Color(0.3, 0.8, 1.0)
		else:
			ability_e_label.text = "[E] Phase Shift"
			if was_on_cd:
				_ability_flash_timers["phase_shift"] = current_time + 1.5
				_ability_cooldown_states["phase_shift"] = false
			if _ability_flash_timers.get("phase_shift", 0) > current_time:
				var flash: float = sin(current_time * 12.0)
				ability_e_label.modulate = Color(0.3, 1.0, 0.3) if flash > 0 else Color(1.0, 1.0, 0.3)
			else:
				ability_e_label.modulate = Color(1, 1, 1)

	if ability_q_label and _overclock_unit:
		var cooldown: float = _overclock_unit.get_cooldown_remaining()
		var was_on_cd: bool = _ability_cooldown_states.get("overclock", false)
		if cooldown > 0:
			ability_q_label.text = "[Q] Overclock (%.1fs)" % cooldown
			ability_q_label.modulate = Color(0.5, 0.5, 0.5)
			_ability_cooldown_states["overclock"] = true
		else:
			ability_q_label.text = "[Q] Overclock"
			if was_on_cd:
				_ability_flash_timers["overclock"] = current_time + 1.5
				_ability_cooldown_states["overclock"] = false
			if _ability_flash_timers.get("overclock", 0) > current_time:
				var flash: float = sin(current_time * 12.0)
				ability_q_label.modulate = Color(0.3, 1.0, 0.3) if flash > 0 else Color(1.0, 1.0, 0.3)
			else:
				ability_q_label.modulate = Color(1, 1, 1)

	if ability_f_label and _siege_formation:
		var cooldown: float = _siege_formation.get_cooldown_remaining()
		var was_on_cd: bool = _ability_cooldown_states.get("siege", false)
		if cooldown > 0:
			ability_f_label.text = "[F] Siege (%.1fs)" % cooldown
			ability_f_label.modulate = Color(0.5, 0.5, 0.5)
			_ability_cooldown_states["siege"] = true
		else:
			ability_f_label.text = "[F] Siege"
			if was_on_cd:
				_ability_flash_timers["siege"] = current_time + 1.5
				_ability_cooldown_states["siege"] = false
			if _ability_flash_timers.get("siege", 0) > current_time:
				var flash: float = sin(current_time * 12.0)
				ability_f_label.modulate = Color(0.3, 1.0, 0.3) if flash > 0 else Color(1.0, 1.0, 0.3)
			else:
				ability_f_label.modulate = Color(1, 1, 1)

	if ability_c_label and _ether_cloak:
		var cooldown: float = _ether_cloak.get_cooldown_remaining()
		var was_on_cd: bool = _ability_cooldown_states.get("cloak", false)
		if cooldown > 0:
			ability_c_label.text = "[C] Cloak (%.1fs)" % cooldown
			ability_c_label.modulate = Color(0.5, 0.5, 0.5)
			_ability_cooldown_states["cloak"] = true
		elif _ether_cloak.get_cloaked_count() > 0:
			ability_c_label.text = "[C] CLOAKED"
			ability_c_label.modulate = Color(0.5, 0.3, 0.8)
		else:
			ability_c_label.text = "[C] Cloak"
			if was_on_cd:
				_ability_flash_timers["cloak"] = current_time + 1.5
				_ability_cooldown_states["cloak"] = false
			if _ability_flash_timers.get("cloak", 0) > current_time:
				var flash: float = sin(current_time * 12.0)
				ability_c_label.modulate = Color(0.3, 1.0, 0.3) if flash > 0 else Color(1.0, 1.0, 0.3)
			else:
				ability_c_label.modulate = Color(1, 1, 1)

	# Update unit count and wave timer
	if units_label:
		var player_units := 0
		var light_count := 0
		var medium_count := 0
		var heavy_count := 0
		for unit in _units:
			if not unit.is_dead and unit.faction_id == _player_faction:
				player_units += 1
				var unit_class: String = unit.get("unit_class", "medium")
				match unit_class:
					"light":
						light_count += 1
					"medium":
						medium_count += 1
					"heavy":
						heavy_count += 1
					_:
						medium_count += 1  # Default

		# Display units by type
		units_label.text = "Units: %d (L:%d M:%d H:%d)" % [
			player_units, light_count, medium_count, heavy_count
		]
		units_label.modulate = Color(0.7, 0.85, 1.0)  # Blue - normal

	# Update production queue display
	if production_queue_label:
		var queue_text := ""
		if not _current_production.is_empty():
			var progress: float = _current_production.progress
			var total: float = _current_production.total_time
			var pct: int = int((progress / total) * 100)
			queue_text = "%s [%d%%]" % [_current_production.unit_class.to_upper(), pct]
			if not _production_queue.is_empty():
				queue_text += " +%d" % _production_queue.size()
		elif not _production_queue.is_empty():
			queue_text = "Queue: %d" % _production_queue.size()
		production_queue_label.text = queue_text


## Update power status display in UI.
func _update_power_status_display() -> void:
	# Create power status label if it doesn't exist
	if _power_status_label == null:
		_power_status_label = Label.new()
		_power_status_label.name = "PowerStatusLabel"

		# Find the resource panel's HBoxContainer
		var hbox: HBoxContainer = get_node_or_null("UI/ResourcePanel/HBoxContainer")
		if hbox:
			# Insert power label after REE label
			var insert_idx := 1  # After REE label
			hbox.add_child(_power_status_label)
			hbox.move_child(_power_status_label, insert_idx)
		else:
			# Fallback - just add to UI
			var ui_node: CanvasLayer = get_node_or_null("UI")
			if ui_node:
				ui_node.add_child(_power_status_label)
				_power_status_label.position = Vector2(200, 10)

	if _power_status_label == null:
		return

	# Get factory power state
	if not _factories.has(_player_faction):
		_power_status_label.text = ""
		return

	var factory: Dictionary = _factories[_player_faction]
	var power_mult: float = factory.get("power_multiplier", 1.0)
	var is_powered: bool = factory.get("is_powered", true)

	# Display power status
	if not is_powered:
		# Blackout - flash red warning
		var pulse: float = (sin(Time.get_ticks_msec() / 150.0) + 1.0) / 2.0
		_power_status_label.text = "BLACKOUT"
		_power_status_label.modulate = Color(1.0, 0.1 + pulse * 0.2, 0.1 + pulse * 0.2)
	elif power_mult < 0.9:
		# Brownout - yellow warning
		var pct: int = int(power_mult * 100)
		_power_status_label.text = "Power: %d%%" % pct
		_power_status_label.modulate = Color(1.0, 0.8, 0.2)
	else:
		# Full power - green
		_power_status_label.text = "Power: OK"
		_power_status_label.modulate = Color(0.3, 0.9, 0.3)


## Update district status display in UI.
func _update_district_status_display() -> void:
	# Create district status label if it doesn't exist
	if _district_status_label == null:
		_district_status_label = Label.new()
		_district_status_label.name = "DistrictStatusLabel"

		# Find the resource panel's HBoxContainer
		var hbox: HBoxContainer = get_node_or_null("UI/ResourcePanel/HBoxContainer")
		if hbox:
			# Insert after power label
			hbox.add_child(_district_status_label)
			hbox.move_child(_district_status_label, 2)

	if _district_status_label == null or _districts.is_empty():
		return

	# Count districts by owner
	var player_districts := 0
	var enemy_districts := 0
	var neutral_districts := 0

	for district in _districts:
		if district.owner == _player_faction:
			player_districts += 1
		elif district.owner == 0:
			neutral_districts += 1
		else:
			enemy_districts += 1

	# Display district count
	var total_districts: int = _districts.size()
	_district_status_label.text = "Districts: %d/%d" % [player_districts, total_districts]

	# Color based on control
	var control_ratio: float = float(player_districts) / float(total_districts)
	if control_ratio >= 0.5:
		_district_status_label.modulate = Color(0.3, 1.0, 0.3)  # Green - winning
	elif control_ratio >= 0.25:
		_district_status_label.modulate = Color(1.0, 0.8, 0.3)  # Yellow - neutral
	else:
		_district_status_label.modulate = Color(1.0, 0.4, 0.3)  # Red - losing


func _connect_ui_signals() -> void:
	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if quit_button:
		quit_button.pressed.connect(_on_quit_pressed)


func _on_restart_pressed() -> void:
	_play_ui_sound("click")
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	_play_ui_sound("click")
	get_tree().quit()


func _setup_containers() -> void:
	_unit_container = Node3D.new()
	_unit_container.name = "Units"
	add_child(_unit_container)

	_projectile_container = Node3D.new()
	_projectile_container.name = "Projectiles"
	add_child(_projectile_container)

	_health_bar_container = Node3D.new()
	_health_bar_container.name = "HealthBars"
	add_child(_health_bar_container)

	_effects_container = Node3D.new()
	_effects_container.name = "Effects"
	add_child(_effects_container)

	# Setup unit ejection animation system
	var ejection_script := load("res://core/factory/unit_ejection_animation.gd")
	if ejection_script != null:
		_unit_ejection_animation = ejection_script.new()
		_unit_ejection_animation.initialize(get_tree())
		_unit_ejection_animation.ejection_completed.connect(_on_unit_ejection_completed)

	# Setup MultiMesh rendering system for batched unit rendering
	if _use_multimesh_rendering:
		var multimesh_script := load("res://core/factory/multimesh_renderer.gd")
		if multimesh_script != null:
			_multimesh_renderer = multimesh_script.new()
			_multimesh_renderer.initialize(_unit_container)
			print("[Performance] MultiMesh rendering enabled - draw calls reduced from 5000+ to ~20")

	# Setup LOD system for unit visual detail management
	var lod_script := load("res://core/view/lod_system.gd")
	if lod_script != null:
		_lod_system = lod_script.new()
		print("[Performance] LOD system enabled - 4 detail levels based on camera distance")

	# Setup performance tier system for AI update throttling
	if _use_performance_tiers:
		var tier_script := load("res://core/ai/performance/performance_tier_system.gd")
		if tier_script != null:
			_performance_tier_system = tier_script.new()
			# Set callback for getting nearest enemy distance (used to determine combat proximity)
			_performance_tier_system.set_get_nearest_enemy_distance(_get_nearest_enemy_distance_for_tier)
			print("[Performance] Performance tier system enabled - AI updates throttled by combat proximity")

	# Frustum culling is always enabled via the _use_frustum_culling flag
	if _use_frustum_culling:
		print("[Performance] Frustum culling enabled - units outside camera view are hidden")

	# Setup voxel terrain system for destructible buildings
	if _use_voxel_terrain:
		var voxel_script := load("res://core/destruction/voxel_system.gd")
		if voxel_script != null:
			_voxel_system = voxel_script.new()
			add_child(_voxel_system)
			# Connect voxel destruction to REE drops
			_voxel_system.voxel_destroyed.connect(_on_voxel_destroyed)
			# Initialize with deterministic seed for reproducible terrain
			_voxel_system.initialize_world(12345)
			print("[Voxel] Terrain system enabled - destructible buildings with 4 damage stages")

			# Setup dynamic navigation mesh for pathfinding with destructible terrain
			_setup_dynamic_navmesh()

	# Setup minimap icons container
	_setup_minimap()

	# Setup audio pools
	_setup_audio()

	# Setup selection box UI
	_setup_selection_box()

	# Setup faction selection screen
	_setup_faction_select()

	# Setup unit tooltip
	_setup_tooltip()

	# Setup kill feed
	_setup_kill_feed()

	# Setup production progress bar
	_setup_production_progress_bar()

	# Setup factory status panel
	_setup_factory_status_panel()

	# Setup power grid overlay (toggle with G key)
	_setup_power_grid_overlay()

	# Setup control group badges
	_setup_control_group_badges()

	# Setup attack-move indicator
	_setup_attack_move_indicator()

	# Setup queue mode indicator
	_setup_queue_mode_indicator()

	# Setup selection count display
	_setup_selection_count_display()

	# Setup unit portrait panel
	_setup_portrait_panel()

	# Setup enemy direction indicators
	_setup_enemy_indicators()

	# Setup match timer
	_setup_match_timer()

	# Setup threat indicator
	_setup_threat_indicator()

	# Setup production hotkey hints panel
	_setup_hotkey_hints_panel()

	# Setup full hotkey reference overlay (F1)
	_setup_hotkey_overlay()

	# Setup tutorial overlay for new players (F2)
	_setup_tutorial_overlay()

	# Setup pause overlay
	_setup_pause_overlay()

	# Setup game speed label
	_setup_game_speed_label()

	# Setup unit count display
	_setup_unit_count_label()

	# Setup REE stats display
	_setup_ree_stats_label()

	# Setup unit overview panel (right side)
	_setup_unit_overview_panel()

	# Setup factory production panel (shown when factory selected)
	_setup_factory_production_panel()

	# Setup fog of war (after match starts)


func _initialize_systems() -> void:
	print("Initializing game systems...")

	if ECS.is_initialized:
		print("  ECS: OK (entities: %d)" % ECS.get_entity_count())
	else:
		ECS.initialize()

	# Initialize faction mechanics for abilities
	_faction_mechanics = FactionMechanicsSystem.new()
	print("  FactionMechanicsSystem: OK (SwarmSynergy, ArmorStacking, Evasion, SyncStrikes)")

	# Initialize Phase Shift ability for Aether Swarm (player faction)
	_phase_shift = PhaseShiftAbility.new()
	_phase_shift.set_get_faction_units(_get_faction_unit_ids)
	_phase_shift.set_get_unit_position(_get_unit_position_by_id)
	_phase_shift.set_unit_collision(_set_unit_collision_by_id)
	_phase_shift.set_unit_visual_alpha(_set_unit_visual_alpha_by_id)
	print("  PhaseShiftAbility: OK (E key, 80 REE, 3s duration)")

	# Initialize Overclock ability for OptiForge (faction 2)
	_overclock_unit = OverclockUnitAbility.new()
	_overclock_unit.set_get_faction_units(_get_faction_unit_ids)
	_overclock_unit.set_get_unit_position(_get_unit_position_by_id)
	_overclock_unit.set_apply_self_damage(_apply_overclock_self_damage)
	_overclock_unit.set_unit_emission(_set_unit_emission_by_id)
	print("  OverclockUnitAbility: OK (Q key, 60 REE, 5s duration)")

	# Initialize Siege Formation ability for LogiBots (faction 4)
	_siege_formation = SiegeFormationAbility.new()
	_siege_formation.set_get_faction_units(_get_faction_unit_ids)
	_siege_formation.set_get_unit_position(_get_unit_position_by_id)
	_siege_formation.set_unit_can_move(_set_unit_can_move_by_id)
	_siege_formation.set_unit_deployed_visual(_set_unit_deployed_visual_by_id)
	print("  SiegeFormationAbility: OK (F key, 40 REE, +50% range)")

	# Initialize Nano Replication ability for Aether Swarm (passive healing)
	_nano_replication = NanoReplicationAbility.new()
	_nano_replication.set_get_unit_health(_get_unit_health_by_id)
	_nano_replication.set_get_unit_max_health(_get_unit_max_health_by_id)
	_nano_replication.set_apply_healing(_apply_healing_to_unit_by_id)
	print("  NanoReplicationAbility: OK (passive, 2-15 HP/s near allies)")

	# Initialize Ether Cloak ability for Aether Swarm (invisibility)
	_ether_cloak = EtherCloakAbility.new()
	_ether_cloak.set_get_faction_units(_get_faction_unit_ids)
	_ether_cloak.set_unit_targetable(_set_unit_targetable_by_id)
	_ether_cloak.set_unit_visual_cloak(_set_unit_visual_cloak_by_id)
	print("  EtherCloakAbility: OK (C key, 50 REE, 4s invisibility)")

	# Initialize Acrobatic Strike ability for Dynapods (leap attack)
	_acrobatic_strike = AcrobaticStrikeAbility.new()
	_acrobatic_strike.set_get_enemies_in_radius(_get_enemies_in_radius)
	_acrobatic_strike.set_apply_damage(_apply_damage_to_unit_by_id)
	_acrobatic_strike.set_unit_position(_set_unit_position_by_id)
	_acrobatic_strike.leap_started.connect(_on_leap_started)
	_acrobatic_strike.leap_landed.connect(_on_leap_landed)
	_acrobatic_strike.unit_leaping.connect(_on_unit_leaping)
	print("  AcrobaticStrikeAbility: OK (B key, 40 REE, leap attack)")

	# Initialize Coordinated Barrage ability for LogiBots (focus fire)
	_coordinated_barrage = CoordinatedBarrageAbility.new()
	_coordinated_barrage.set_get_unit_position(_get_unit_position_by_id)
	_coordinated_barrage.set_unit_target(_set_unit_target_by_id)
	_coordinated_barrage.set_is_target_alive(_is_unit_alive_by_id)
	print("  CoordinatedBarrageAbility: OK (V key, 30 REE, +75% damage to target)")

	# Initialize Fractal Movement ability for Aether Swarm (evasion)
	_fractal_movement = FractalMovementAbility.new()
	print("  FractalMovementAbility: OK (passive, evasion from movement)")

	# Initialize Mass Production ability for OptiForge (faster spawning)
	_mass_production = MassProductionAbility.new()
	print("  MassProductionAbility: OK (passive, +15% per factory)")

	# Initialize power grid system
	_power_grid_manager = PowerGridManager.new()
	_brownout_system = BrownoutSystem.new()
	_power_consumer_manager = PowerConsumerManager.new()
	print("  PowerGridManager: OK (power plants, lines, districts)")
	print("  BrownoutSystem: OK (brownout/blackout effects)")
	print("  PowerConsumerManager: OK (factory power consumption)")

	# Initialize district capture system
	_setup_districts()
	print("  DistrictSystem: OK (%dx%d grid, %d districts)" % [DISTRICT_GRID_SIZE, DISTRICT_GRID_SIZE, _districts.size()])

	# Initialize faction statistics
	_initialize_faction_stats()

	# Initialize Hive Mind XP Progression System
	_experience_pool = ExperiencePool.new()
	_hive_mind_progression = HiveMindProgression.new()

	# Register all factions with the experience pool
	for faction_id in [1, 2, 3, 4]:
		var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
		if faction_str != "":
			_experience_pool.register_faction(faction_str)

	# Connect XP signals for buff notifications
	_experience_pool.buff_unlocked.connect(_on_xp_buff_unlocked)
	print("  ExperiencePool: OK (Combat/Economy/Engineering XP)")
	print("  HiveMindProgression: OK (faction buff unlocks)")

	# Setup XP display panel
	_setup_xp_panel()

	# Initialize Settings Manager (load user preferences)
	_settings_manager = SettingsManager.new()
	_settings_manager.load_settings()
	_settings_manager.setting_changed.connect(_on_setting_changed)
	_apply_loaded_settings()
	print("  SettingsManager: OK (user preferences loaded)")

	# Initialize Save Manager (add as child node since it extends Node)
	_save_manager_node = SaveManagerClass.new()
	add_child(_save_manager_node)
	_save_manager_node.save_completed.connect(_on_save_completed)
	_save_manager_node.load_completed.connect(_on_load_completed)
	_save_manager_node.error_occurred.connect(_on_save_error)
	print("  SaveManager: OK (quicksave F8, quickload Ctrl+F8)")

	# Initialize Human Remnant NPC faction (wild card threat)
	# Check if Human Remnant is enabled in settings
	_human_remnant_enabled = _settings_manager.get_human_remnant_enabled()
	if _human_remnant_enabled:
		_human_remnant_faction = HumanResistanceAIFaction.new()
		_human_remnant_spawner = HumanResistanceSpawner.new()
		_human_remnant_ai = HumanResistanceAI.new()

		# Initialize spawner with city bounds (300x300 playable area centered)
		var city_bounds := Rect2(-150, -150, 300, 300)
		_human_remnant_spawner.initialize(city_bounds, 140.0)  # Spawn from edges

		# Connect spawner signals to create actual game units
		_human_remnant_spawner.unit_spawned.connect(_on_human_remnant_unit_spawned)
		_human_remnant_spawner.wave_started.connect(_on_human_remnant_wave_started)
		_human_remnant_spawner.wave_completed.connect(_on_human_remnant_wave_completed)

		print("  HumanRemnant: OK (NPC faction with guerrilla tactics)")
	else:
		print("  HumanRemnant: DISABLED")

	print("  GameStateManager: OK")
	print("  ResourceManager: OK")
	print("  FactionManager: OK")
	print("  Statistics Tracking: OK")

	# PERFORMANCE: Pre-create cached stance indicator meshes and materials
	_initialize_stance_indicator_cache()
	print("  StanceIndicatorCache: OK (pre-baked meshes and materials)")

	print("All systems initialized")


## Initialize statistics tracking for all factions
func _initialize_faction_stats() -> void:
	for faction_id in [1, 2, 3, 4]:
		_faction_stats[faction_id] = STAT_DEFAULTS.duplicate()


## Record a stat for a faction
func _track_stat(faction_id: int, stat_name: String, value: float = 1.0) -> void:
	if not _faction_stats.has(faction_id):
		_faction_stats[faction_id] = STAT_DEFAULTS.duplicate()

	if _faction_stats[faction_id].has(stat_name):
		_faction_stats[faction_id][stat_name] += value


## Set a stat directly (for max values, etc.)
func _set_stat(faction_id: int, stat_name: String, value: float) -> void:
	if not _faction_stats.has(faction_id):
		_faction_stats[faction_id] = STAT_DEFAULTS.duplicate()

	if _faction_stats[faction_id].has(stat_name):
		_faction_stats[faction_id][stat_name] = value


## Get a stat for a faction
func _get_stat(faction_id: int, stat_name: String) -> float:
	if not _faction_stats.has(faction_id):
		return 0.0
	return _faction_stats[faction_id].get(stat_name, 0.0)


## Get all stats for a faction
func _get_faction_stats(faction_id: int) -> Dictionary:
	if not _faction_stats.has(faction_id):
		return STAT_DEFAULTS.duplicate()
	return _faction_stats[faction_id].duplicate()


## Update kill streak tracking
func _update_kill_streak(faction_id: int) -> void:
	if not _faction_stats.has(faction_id):
		return

	_faction_stats[faction_id].current_kill_streak += 1
	var current: int = _faction_stats[faction_id].current_kill_streak
	var highest: int = _faction_stats[faction_id].highest_kill_streak

	if current > highest:
		_faction_stats[faction_id].highest_kill_streak = current


## Reset kill streak (called when unit dies)
func _reset_kill_streak(faction_id: int) -> void:
	if _faction_stats.has(faction_id):
		_faction_stats[faction_id].current_kill_streak = 0


# =============================================================================
# HIVE MIND XP PROGRESSION SYSTEM
# =============================================================================

## Award Hive Mind XP to a faction (separate from unit veterancy)
## Category: ExperiencePool.Category.COMBAT, ECONOMY, or ENGINEERING
func _award_faction_xp(faction_id: int, category: int, amount: float) -> void:
	if _experience_pool == null or amount <= 0:
		return

	var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
	if faction_str.is_empty():
		return

	_experience_pool.add_experience(faction_str, category, amount)


## Callback when XP buff is unlocked
func _on_xp_buff_unlocked(faction_id: String, buff_name: String, tier: int) -> void:
	# Convert faction string to ID
	var faction_int: int = -1
	for key in FACTION_ID_TO_STRING:
		if FACTION_ID_TO_STRING[key] == faction_id:
			faction_int = key
			break

	# Show notification for player faction
	if faction_int == _player_faction:
		var tier_name := ""
		match tier:
			1: tier_name = "Bronze"
			2: tier_name = "Silver"
			3: tier_name = "Gold"

		var buff_display := buff_name.replace("_", " ").capitalize()
		var message := "%s Tier %s: %s unlocked!" % [tier_name, tier, buff_display]
		_spawn_floating_text(Vector3.ZERO, message, Color(1.0, 0.85, 0.0), 2.0)
		print("XP Buff Unlocked: %s (Tier %d) - %s" % [buff_name, tier, faction_id])

		# Play celebratory sound
		_play_levelup_sound()


## Setup XP display panel in the UI
func _setup_xp_panel() -> void:
	_xp_panel = PanelContainer.new()
	_xp_panel.name = "XPPanel"

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	style.border_color = Color(0.4, 0.6, 0.9, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_xp_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "HIVE MIND XP"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Combat XP row
	var combat_row := HBoxContainer.new()
	combat_row.name = "CombatRow"
	var combat_icon := Label.new()
	combat_icon.text = "⚔"
	combat_icon.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
	combat_row.add_child(combat_icon)
	var combat_label := Label.new()
	combat_label.name = "CombatXP"
	combat_label.text = " Combat: 0"
	combat_label.add_theme_font_size_override("font_size", 11)
	combat_row.add_child(combat_label)
	var combat_tier := Label.new()
	combat_tier.name = "CombatTier"
	combat_tier.text = " [T0]"
	combat_tier.add_theme_font_size_override("font_size", 10)
	combat_tier.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	combat_row.add_child(combat_tier)
	vbox.add_child(combat_row)

	# Economy XP row
	var economy_row := HBoxContainer.new()
	economy_row.name = "EconomyRow"
	var economy_icon := Label.new()
	economy_icon.text = "💰"
	economy_icon.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	economy_row.add_child(economy_icon)
	var economy_label := Label.new()
	economy_label.name = "EconomyXP"
	economy_label.text = " Economy: 0"
	economy_label.add_theme_font_size_override("font_size", 11)
	economy_row.add_child(economy_label)
	var economy_tier := Label.new()
	economy_tier.name = "EconomyTier"
	economy_tier.text = " [T0]"
	economy_tier.add_theme_font_size_override("font_size", 10)
	economy_tier.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	economy_row.add_child(economy_tier)
	vbox.add_child(economy_row)

	# Engineering XP row
	var engineering_row := HBoxContainer.new()
	engineering_row.name = "EngineeringRow"
	var engineering_icon := Label.new()
	engineering_icon.text = "🔧"
	engineering_icon.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	engineering_row.add_child(engineering_icon)
	var engineering_label := Label.new()
	engineering_label.name = "EngineeringXP"
	engineering_label.text = " Engineering: 0"
	engineering_label.add_theme_font_size_override("font_size", 11)
	engineering_row.add_child(engineering_label)
	var engineering_tier := Label.new()
	engineering_tier.name = "EngineeringTier"
	engineering_tier.text = " [T0]"
	engineering_tier.add_theme_font_size_override("font_size", 10)
	engineering_tier.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	engineering_row.add_child(engineering_tier)
	vbox.add_child(engineering_row)

	# Buffs summary
	var buffs_label := Label.new()
	buffs_label.name = "BuffsSummary"
	buffs_label.text = ""
	buffs_label.add_theme_font_size_override("font_size", 10)
	buffs_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	vbox.add_child(buffs_label)

	_xp_panel.add_child(vbox)

	# Position the panel (top-right corner, below resource panel)
	_xp_panel.position = Vector2(get_viewport().size.x - 200, 100)
	_xp_panel.size = Vector2(180, 120)

	$UI.add_child(_xp_panel)


## Update the XP display panel with current values
func _update_xp_display() -> void:
	if _xp_panel == null or _experience_pool == null:
		return

	var faction_str: String = FACTION_ID_TO_STRING.get(_player_faction, "")
	if faction_str.is_empty():
		return

	var vbox: VBoxContainer = _xp_panel.get_node_or_null("VBox")
	if vbox == null:
		return

	# Get XP values
	var combat_xp: float = _experience_pool.get_experience(faction_str, ExperiencePool.Category.COMBAT)
	var economy_xp: float = _experience_pool.get_experience(faction_str, ExperiencePool.Category.ECONOMY)
	var engineering_xp: float = _experience_pool.get_experience(faction_str, ExperiencePool.Category.ENGINEERING)

	# Get tiers
	var combat_tier: int = _experience_pool.get_tier(faction_str, ExperiencePool.Category.COMBAT)
	var economy_tier: int = _experience_pool.get_tier(faction_str, ExperiencePool.Category.ECONOMY)
	var engineering_tier: int = _experience_pool.get_tier(faction_str, ExperiencePool.Category.ENGINEERING)

	# Update combat row
	var combat_row: HBoxContainer = vbox.get_node_or_null("CombatRow")
	if combat_row:
		var label: Label = combat_row.get_node_or_null("CombatXP")
		if label:
			label.text = " Combat: %.0f" % combat_xp
		var tier_label: Label = combat_row.get_node_or_null("CombatTier")
		if tier_label:
			tier_label.text = " [T%d]" % combat_tier
			tier_label.add_theme_color_override("font_color", _get_tier_color(combat_tier))

	# Update economy row
	var economy_row: HBoxContainer = vbox.get_node_or_null("EconomyRow")
	if economy_row:
		var label: Label = economy_row.get_node_or_null("EconomyXP")
		if label:
			label.text = " Economy: %.0f" % economy_xp
		var tier_label: Label = economy_row.get_node_or_null("EconomyTier")
		if tier_label:
			tier_label.text = " [T%d]" % economy_tier
			tier_label.add_theme_color_override("font_color", _get_tier_color(economy_tier))

	# Update engineering row
	var engineering_row: HBoxContainer = vbox.get_node_or_null("EngineeringRow")
	if engineering_row:
		var label: Label = engineering_row.get_node_or_null("EngineeringXP")
		if label:
			label.text = " Engineering: %.0f" % engineering_xp
		var tier_label: Label = engineering_row.get_node_or_null("EngineeringTier")
		if tier_label:
			tier_label.text = " [T%d]" % engineering_tier
			tier_label.add_theme_color_override("font_color", _get_tier_color(engineering_tier))

	# Update buffs summary
	var buffs: Dictionary = _experience_pool.get_all_buffs(faction_str)
	var buffs_label: Label = vbox.get_node_or_null("BuffsSummary")
	if buffs_label:
		if buffs.is_empty():
			buffs_label.text = ""
		else:
			var buff_texts: Array[String] = []
			if buffs.has("damage_multiplier") and buffs["damage_multiplier"] > 0:
				buff_texts.append("+%.0f%% DMG" % (buffs["damage_multiplier"] * 100))
			if buffs.has("attack_speed_multiplier") and buffs["attack_speed_multiplier"] > 0:
				buff_texts.append("+%.0f%% ATK" % (buffs["attack_speed_multiplier"] * 100))
			if buffs.has("dodge_chance") and buffs["dodge_chance"] > 0:
				buff_texts.append("+%.0f%% Dodge" % (buffs["dodge_chance"] * 100))
			if buffs.has("critical_strike_chance") and buffs["critical_strike_chance"] > 0:
				buff_texts.append("+%.0f%% Crit" % (buffs["critical_strike_chance"] * 100))
			buffs_label.text = ", ".join(buff_texts)


## Get color for XP tier display
func _get_tier_color(tier: int) -> Color:
	match tier:
		0: return Color(0.5, 0.5, 0.5)  # Gray
		1: return Color(0.8, 0.5, 0.2)  # Bronze
		2: return Color(0.75, 0.75, 0.85)  # Silver
		3: return Color(1.0, 0.85, 0.0)  # Gold
		_: return Color(0.6, 0.6, 0.6)


## Setup unit overview panel on right side of screen.
func _setup_unit_overview_panel() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create main panel container
	_unit_overview_panel = PanelContainer.new()
	_unit_overview_panel.name = "UnitOverviewPanel"
	_unit_overview_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_unit_overview_panel.offset_left = -200
	_unit_overview_panel.offset_right = -20
	_unit_overview_panel.offset_top = -150
	_unit_overview_panel.offset_bottom = 150
	_unit_overview_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.12, 0.9)
	style.border_color = Color(0.3, 0.4, 0.5, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_unit_overview_panel.add_theme_stylebox_override("panel", style)

	# Create vertical container for unit type rows
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 6)

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "ARMY OVERVIEW"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Create rows for each unit type
	var unit_types := ["scout", "soldier", "tank", "harvester"]
	var type_icons := {"scout": "◆", "soldier": "■", "tank": "●", "harvester": "▼"}
	var type_colors := {
		"scout": Color(0.4, 0.8, 1.0),
		"soldier": Color(0.8, 0.8, 0.3),
		"tank": Color(1.0, 0.4, 0.3),
		"harvester": Color(0.4, 1.0, 0.4)
	}

	for unit_type in unit_types:
		var row := _create_unit_overview_row(unit_type, type_icons[unit_type], type_colors[unit_type])
		_unit_overview_rows[unit_type] = row
		vbox.add_child(row)

	# Control groups section
	var groups_title := Label.new()
	groups_title.text = "─ GROUPS ─"
	groups_title.add_theme_font_size_override("font_size", 10)
	groups_title.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	groups_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(groups_title)

	# Control group indicators
	var groups_row := HBoxContainer.new()
	groups_row.name = "GroupsRow"
	groups_row.alignment = BoxContainer.ALIGNMENT_CENTER
	groups_row.add_theme_constant_override("separation", 4)
	for i in range(1, 10):
		var group_btn := Button.new()
		group_btn.name = "Group%d" % i
		group_btn.text = str(i)
		group_btn.custom_minimum_size = Vector2(16, 16)
		group_btn.add_theme_font_size_override("font_size", 9)
		group_btn.flat = true
		group_btn.modulate = Color(0.4, 0.4, 0.4)  # Dim when empty
		group_btn.pressed.connect(_on_group_button_pressed.bind(i))
		groups_row.add_child(group_btn)
	vbox.add_child(groups_row)

	_unit_overview_panel.add_child(vbox)
	ui_layer.add_child(_unit_overview_panel)


## Create a row for a unit type in the overview panel.
func _create_unit_overview_row(unit_type: String, icon: String, color: Color) -> Control:
	var row := Control.new()
	row.name = "%sRow" % unit_type.capitalize()
	row.custom_minimum_size = Vector2(160, 30)
	row.mouse_filter = Control.MOUSE_FILTER_STOP

	# Background (clickable)
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.15, 0.17, 0.2, 0.5)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.gui_input.connect(_on_unit_row_input.bind(unit_type))
	row.add_child(bg)

	# Icon
	var icon_label := Label.new()
	icon_label.name = "Icon"
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.add_theme_color_override("font_color", color)
	icon_label.position = Vector2(4, 6)
	row.add_child(icon_label)

	# Type name
	var name_label := Label.new()
	name_label.name = "TypeName"
	name_label.text = unit_type.capitalize()
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	name_label.position = Vector2(22, 2)
	row.add_child(name_label)

	# Count label
	var count_label := Label.new()
	count_label.name = "Count"
	count_label.text = "0"
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	count_label.position = Vector2(130, 2)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.custom_minimum_size = Vector2(25, 0)
	row.add_child(count_label)

	# Health bar (shows average health of all units of this type)
	var health_bar := ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.min_value = 0
	health_bar.max_value = 1.0
	health_bar.value = 1.0
	health_bar.show_percentage = false
	health_bar.position = Vector2(22, 18)
	health_bar.size = Vector2(133, 8)

	# Health bar style
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.2, 0.2, 0.2)
	bar_bg.set_corner_radius_all(2)
	health_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.3, 0.8, 0.3)
	bar_fill.set_corner_radius_all(2)
	health_bar.add_theme_stylebox_override("fill", bar_fill)

	row.add_child(health_bar)

	return row


## Update unit overview panel with current unit counts and health.
func _update_unit_overview_panel() -> void:
	if _unit_overview_panel == null:
		return

	# Hide when factory is selected (production panel takes over right side)
	if _factory_selected:
		_unit_overview_panel.visible = false
		return
	else:
		_unit_overview_panel.visible = true

	# Count units by type and calculate average health
	var unit_counts: Dictionary = {}
	var health_totals: Dictionary = {}
	var max_health_totals: Dictionary = {}

	for unit in _units:
		if not is_instance_valid(unit):
			continue

		var faction_id: int = unit.get_meta("faction_id", 0)
		if faction_id != _player_faction:
			continue

		var is_dead: bool = unit.get_meta("is_dead", false)
		if is_dead:
			continue

		var unit_type: String = unit.get_meta("unit_type", "soldier")
		# Map unit classes to types
		var unit_class: String = unit.get_meta("unit_class", "medium")
		if unit_class == "light":
			unit_type = "scout"
		elif unit_class == "heavy":
			unit_type = "tank"
		elif unit_class == "harvester":
			unit_type = "harvester"
		else:
			unit_type = "soldier"

		unit_counts[unit_type] = unit_counts.get(unit_type, 0) + 1
		var health: float = unit.get_meta("health", 100.0)
		var max_health: float = unit.get_meta("max_health", 100.0)
		health_totals[unit_type] = health_totals.get(unit_type, 0.0) + health
		max_health_totals[unit_type] = max_health_totals.get(unit_type, 0.0) + max_health

	# Update each row
	for unit_type in _unit_overview_rows:
		var row: Control = _unit_overview_rows[unit_type]
		if not is_instance_valid(row):
			continue

		var count: int = unit_counts.get(unit_type, 0)
		var count_label: Label = row.get_node_or_null("Count")
		if count_label:
			count_label.text = str(count)
			if count == 0:
				count_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
			else:
				count_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

		# Update health bar
		var health_bar: ProgressBar = row.get_node_or_null("HealthBar")
		if health_bar:
			if count > 0:
				var avg_health: float = health_totals.get(unit_type, 0.0) / max_health_totals.get(unit_type, 1.0)
				health_bar.value = avg_health

				# Color based on health
				var bar_fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if bar_fill:
					if avg_health > 0.6:
						bar_fill.bg_color = Color(0.3, 0.8, 0.3)  # Green
					elif avg_health > 0.3:
						bar_fill.bg_color = Color(0.9, 0.7, 0.2)  # Yellow
					else:
						bar_fill.bg_color = Color(0.9, 0.2, 0.2)  # Red
			else:
				health_bar.value = 0

	# Update control group indicators
	var vbox: VBoxContainer = _unit_overview_panel.get_node_or_null("VBox")
	if vbox:
		var groups_row: HBoxContainer = vbox.get_node_or_null("GroupsRow")
		if groups_row:
			for i in range(1, 10):
				var group_btn: Button = groups_row.get_node_or_null("Group%d" % i)
				if group_btn:
					var has_units: bool = _control_groups.has(i) and not _control_groups[i].is_empty()
					if has_units:
						# Count alive units in group
						var alive_count := 0
						for u in _control_groups[i]:
							if u is Dictionary and not u.get("is_dead", false):
								alive_count += 1
							elif u is Node and is_instance_valid(u) and not u.get_meta("is_dead", false):
								alive_count += 1
						if alive_count > 0:
							group_btn.modulate = Color(1.0, 1.0, 1.0)
							group_btn.tooltip_text = "Group %d: %d units" % [i, alive_count]
						else:
							group_btn.modulate = Color(0.4, 0.4, 0.4)
							group_btn.tooltip_text = "Group %d: Empty" % i
					else:
						group_btn.modulate = Color(0.4, 0.4, 0.4)
						group_btn.tooltip_text = "Group %d: Empty" % i


## Handle clicking on a unit type row in the overview panel.
func _on_unit_row_input(event: InputEvent, unit_type: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_units_by_type(unit_type)


## Handle clicking on a control group button.
func _on_group_button_pressed(group_num: int) -> void:
	_recall_control_group(group_num)


## Select all player units of a specific type.
func _select_units_by_type(unit_type: String) -> void:
	_deselect_all_units()

	var type_map := {
		"scout": "light",
		"soldier": "medium",
		"tank": "heavy",
		"harvester": "harvester"
	}
	var target_class: String = type_map.get(unit_type, "medium")

	for unit in _units:
		if not is_instance_valid(unit):
			continue

		var faction_id: int = unit.get_meta("faction_id", 0)
		if faction_id != _player_faction:
			continue

		var is_dead: bool = unit.get_meta("is_dead", false)
		if is_dead:
			continue

		var unit_class: String = unit.get_meta("unit_class", "medium")
		if unit_class == target_class:
			_select_unit(unit)

	_update_selection_rings()
	_update_portrait_panel()

	# Play selection sound
	if _should_play_sound() and not _selected_units.is_empty():
		_play_ui_sound("select")


## Setup the power grid overlay UI (toggle with G key).
func _setup_power_grid_overlay() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	# Create power status panel (top-left corner)
	_power_status_panel = PowerStatusPanel.new()
	var panel_container := Control.new()
	panel_container.name = "PowerOverlayContainer"
	panel_container.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel_container.offset_left = 10
	panel_container.offset_top = 120  # Below resource panel
	panel_container.offset_right = 260
	panel_container.offset_bottom = 340
	panel_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(panel_container)

	var faction_str: String = FACTION_ID_TO_STRING.get(_player_faction, "neutral")
	_power_status_panel.create_ui(panel_container, faction_str)

	# Create power grid display (overlays the main view)
	_power_grid_display = PowerGridDisplay.new()
	var grid_container := Control.new()
	grid_container.name = "PowerGridDisplayContainer"
	grid_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(grid_container)
	_power_grid_display.create_ui(grid_container, faction_str)

	# Initially hidden
	panel_container.visible = false
	grid_container.visible = false

	print("[Power] Power grid overlay ready (press G to toggle)")


## Toggle power grid overlay visibility.
func _toggle_power_grid_overlay() -> void:
	_power_grid_overlay_visible = not _power_grid_overlay_visible

	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	var panel_container: Control = ui_layer.get_node_or_null("PowerOverlayContainer")
	var grid_container: Control = ui_layer.get_node_or_null("PowerGridDisplayContainer")

	if panel_container:
		panel_container.visible = _power_grid_overlay_visible
	if grid_container:
		grid_container.visible = _power_grid_overlay_visible

	if _power_grid_overlay_visible:
		_update_power_grid_overlay()
		print("[Power] Grid overlay ON")
	else:
		print("[Power] Grid overlay OFF")


## Update power grid overlay with current data.
func _update_power_grid_overlay() -> void:
	if not _power_grid_overlay_visible:
		return

	if _power_grid_manager == null:
		return

	var summary: Dictionary = _power_grid_manager.get_summary()

	# Update power status panel
	if _power_status_panel != null:
		var generation: float = summary.get("power", {}).get("generation", 0.0)
		var demand: float = summary.get("power", {}).get("demand", 0.0)
		var blackouts: int = summary.get("districts", {}).get("blackout", 0)
		var operational: int = summary.get("plants", {}).get("operational", 0)
		var total_plants: int = summary.get("plants", {}).get("total", 0)

		_power_status_panel.update_power(generation, demand, blackouts, operational, total_plants)

	# Update power grid display with plants and lines
	if _power_grid_display != null:
		_update_power_grid_display_data()


## Update power grid display with plant and line positions.
func _update_power_grid_display_data() -> void:
	if _power_grid_display == null or _power_grid_manager == null:
		return

	# Get all plants and update their screen positions
	var plants: Dictionary = _power_grid_manager.get_all_plants()
	for plant_id in plants:
		var plant: PowerPlant = plants[plant_id]
		var screen_pos := _world_to_screen(plant.position)
		var status := 0 if plant.is_operational() else 2  # 0 = operational, 2 = destroyed
		_power_grid_display.set_plant(plant_id, screen_pos, plant.current_output, plant.max_output, status)

	# Update visual
	_power_grid_display.update_power_grid_visual()


## Convert world position to screen position.
func _world_to_screen(world_pos: Vector3) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(world_pos)


## Setup the factory production panel (shown when factory is selected).
func _setup_factory_production_panel() -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	_factory_production_panel = PanelContainer.new()
	_factory_production_panel.name = "FactoryProductionPanel"
	_factory_production_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_factory_production_panel.offset_left = -240
	_factory_production_panel.offset_right = -20
	_factory_production_panel.offset_top = -220
	_factory_production_panel.offset_bottom = 220
	_factory_production_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_factory_production_panel.visible = false  # Hidden until factory selected

	# Style the panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.1, 0.95)
	style.border_color = Color(0.4, 0.5, 0.6, 0.9)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	_factory_production_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 8)

	# Title
	var title := Label.new()
	title.name = "Title"
	title.text = "⚙ FACTORY PRODUCTION"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# REE display
	var ree_row := HBoxContainer.new()
	ree_row.name = "REERow"
	ree_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var ree_icon := Label.new()
	ree_icon.text = "💎"
	ree_icon.add_theme_font_size_override("font_size", 16)
	ree_row.add_child(ree_icon)
	var ree_label := Label.new()
	ree_label.name = "REEAmount"
	ree_label.text = " 0 REE"
	ree_label.add_theme_font_size_override("font_size", 14)
	ree_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8))
	ree_row.add_child(ree_label)
	vbox.add_child(ree_row)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vbox.add_child(sep)

	# Unit rows
	var unit_types := ["light", "medium", "heavy", "harvester"]
	var unit_names := {"light": "Scout", "medium": "Soldier", "heavy": "Heavy Tank", "harvester": "Harvester"}
	var unit_icons := {"light": "◆", "medium": "■", "heavy": "●", "harvester": "▼"}
	var unit_keys := {"light": "1", "medium": "2", "heavy": "3", "harvester": "4"}

	for unit_class in unit_types:
		var row := _create_production_row(unit_class, unit_names[unit_class], unit_icons[unit_class], unit_keys[unit_class])
		vbox.add_child(row)

	# Queue section
	var queue_sep := HSeparator.new()
	queue_sep.add_theme_constant_override("separation", 4)
	vbox.add_child(queue_sep)

	var queue_title := Label.new()
	queue_title.text = "─ PRODUCTION QUEUE ─"
	queue_title.add_theme_font_size_override("font_size", 11)
	queue_title.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	queue_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(queue_title)

	# Current production display (with progress bar)
	var current_prod := VBoxContainer.new()
	current_prod.name = "CurrentProduction"
	current_prod.add_theme_constant_override("separation", 2)

	var current_label := Label.new()
	current_label.name = "CurrentLabel"
	current_label.text = "Building: Idle"
	current_label.add_theme_font_size_override("font_size", 10)
	current_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	current_prod.add_child(current_label)

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 6)

	_factory_current_production_bar = ProgressBar.new()
	_factory_current_production_bar.name = "CurrentProgressBar"
	_factory_current_production_bar.min_value = 0.0
	_factory_current_production_bar.max_value = 100.0
	_factory_current_production_bar.value = 0.0
	_factory_current_production_bar.show_percentage = false
	_factory_current_production_bar.custom_minimum_size = Vector2(130, 14)
	_factory_current_production_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var prog_bg := StyleBoxFlat.new()
	prog_bg.bg_color = Color(0.15, 0.15, 0.15)
	prog_bg.set_corner_radius_all(3)
	_factory_current_production_bar.add_theme_stylebox_override("background", prog_bg)

	var prog_fill := StyleBoxFlat.new()
	prog_fill.bg_color = Color(0.3, 0.7, 0.4)
	prog_fill.set_corner_radius_all(3)
	_factory_current_production_bar.add_theme_stylebox_override("fill", prog_fill)

	progress_row.add_child(_factory_current_production_bar)

	var time_label := Label.new()
	time_label.name = "TimeRemaining"
	time_label.text = ""
	time_label.add_theme_font_size_override("font_size", 10)
	time_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	time_label.custom_minimum_size.x = 35
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_row.add_child(time_label)

	current_prod.add_child(progress_row)
	vbox.add_child(current_prod)

	# Queue list (scrollable)
	var queue_scroll := ScrollContainer.new()
	queue_scroll.name = "QueueScroll"
	queue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	queue_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	queue_scroll.custom_minimum_size = Vector2(0, 70)

	_factory_queue_list_container = VBoxContainer.new()
	_factory_queue_list_container.name = "QueueList"
	_factory_queue_list_container.add_theme_constant_override("separation", 2)

	var empty_label := Label.new()
	empty_label.name = "EmptyLabel"
	empty_label.text = "(Queue empty)"
	empty_label.add_theme_font_size_override("font_size", 10)
	empty_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_factory_queue_list_container.add_child(empty_label)

	queue_scroll.add_child(_factory_queue_list_container)
	vbox.add_child(queue_scroll)

	# Start queue button
	var start_btn := Button.new()
	start_btn.name = "StartQueueBtn"
	start_btn.text = "▶ START PRODUCTION"
	start_btn.add_theme_font_size_override("font_size", 12)
	start_btn.custom_minimum_size = Vector2(180, 32)
	start_btn.pressed.connect(_on_start_production_queue)

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.5, 0.3)
	btn_style.set_corner_radius_all(4)
	start_btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.3, 0.6, 0.4)
	btn_hover.set_corner_radius_all(4)
	start_btn.add_theme_stylebox_override("hover", btn_hover)

	vbox.add_child(start_btn)

	# Help text
	var help := Label.new()
	help.text = "Click ⊕/⊖ or Shift+1-4"
	help.add_theme_font_size_override("font_size", 10)
	help.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(help)

	_factory_production_panel.add_child(vbox)
	ui_layer.add_child(_factory_production_panel)


## Create a row for a unit type in the production panel.
func _create_production_row(unit_class: String, display_name: String, icon: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.name = "%sRow" % unit_class.capitalize()
	row.add_theme_constant_override("separation", 6)

	# Icon
	var icon_label := Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 14)
	icon_label.custom_minimum_size = Vector2(20, 0)
	row.add_child(icon_label)

	# Name + key hint
	var name_box := VBoxContainer.new()
	name_box.custom_minimum_size = Vector2(70, 0)
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	name_box.add_child(name_label)
	var key_label := Label.new()
	key_label.text = "[Shift+%s]" % key
	key_label.add_theme_font_size_override("font_size", 9)
	key_label.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	name_box.add_child(key_label)
	row.add_child(name_box)

	# Cost
	var cost: float = PRODUCTION_COSTS.get(unit_class, 50)
	var cost_label := Label.new()
	cost_label.name = "Cost"
	cost_label.text = "%.0f" % cost
	cost_label.add_theme_font_size_override("font_size", 11)
	cost_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.7))
	cost_label.custom_minimum_size = Vector2(30, 0)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(cost_label)

	# Can afford indicator
	var afford_label := Label.new()
	afford_label.name = "Afford"
	afford_label.text = "x0"
	afford_label.add_theme_font_size_override("font_size", 10)
	afford_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	afford_label.custom_minimum_size = Vector2(25, 0)
	row.add_child(afford_label)

	# Minus button
	var minus_btn := Button.new()
	minus_btn.name = "MinusBtn"
	minus_btn.text = "−"
	minus_btn.custom_minimum_size = Vector2(24, 24)
	minus_btn.add_theme_font_size_override("font_size", 14)
	minus_btn.pressed.connect(_on_production_minus.bind(unit_class))
	row.add_child(minus_btn)

	# Queue count
	var count_label := Label.new()
	count_label.name = "QueueCount"
	count_label.text = "0"
	count_label.add_theme_font_size_override("font_size", 12)
	count_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	count_label.custom_minimum_size = Vector2(20, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count_label)

	# Plus button
	var plus_btn := Button.new()
	plus_btn.name = "PlusBtn"
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(24, 24)
	plus_btn.add_theme_font_size_override("font_size", 14)
	plus_btn.pressed.connect(_on_production_plus.bind(unit_class))
	row.add_child(plus_btn)

	return row


## Handle minus button click for production.
func _on_production_minus(unit_class: String) -> void:
	var current: int = _factory_queue_counts.get(unit_class, 0)
	if current > 0:
		_factory_queue_counts[unit_class] = current - 1
		_update_factory_production_panel()
		_play_ui_sound("click")


## Handle plus button click for production.
func _on_production_plus(unit_class: String) -> void:
	var cost: float = PRODUCTION_COSTS.get(unit_class, 50)
	var ree: float = ResourceManager.get_current_ree(_player_faction) if ResourceManager else 0.0

	# Calculate how much we'd be spending if we add this
	var total_queued_cost := 0.0
	for uc in _factory_queue_counts:
		total_queued_cost += _factory_queue_counts[uc] * PRODUCTION_COSTS.get(uc, 50)

	if ree >= total_queued_cost + cost:
		_factory_queue_counts[unit_class] = _factory_queue_counts.get(unit_class, 0) + 1
		_update_factory_production_panel()
		_play_ui_sound("click")
	else:
		_play_ui_sound("error")


## Handle start production queue button.
func _on_start_production_queue() -> void:
	var total_queued := 0
	for unit_class in _factory_queue_counts:
		var count: int = _factory_queue_counts[unit_class]
		for i in count:
			if _queue_unit_production(unit_class):
				total_queued += 1

	if total_queued > 0:
		print("Queued %d units for production" % total_queued)
		_play_ui_sound("notification")
	else:
		_play_ui_sound("error")

	# Clear the queue counts
	_factory_queue_counts.clear()
	_update_factory_production_panel()


## Update the factory production panel with current REE and affordability.
func _update_factory_production_panel() -> void:
	if _factory_production_panel == null or not _factory_production_panel.visible:
		return

	var vbox: VBoxContainer = _factory_production_panel.get_node_or_null("VBox")
	if vbox == null:
		return

	var ree: float = ResourceManager.get_current_ree(_player_faction) if ResourceManager else 0.0

	# Update REE display
	var ree_row: HBoxContainer = vbox.get_node_or_null("REERow")
	if ree_row:
		var ree_label: Label = ree_row.get_node_or_null("REEAmount")
		if ree_label:
			ree_label.text = " %.0f REE" % ree

	# Calculate total cost of currently queued items
	var total_queued_cost := 0.0
	for uc in _factory_queue_counts:
		total_queued_cost += _factory_queue_counts[uc] * PRODUCTION_COSTS.get(uc, 50)

	var remaining_ree: float = ree - total_queued_cost

	# Update each unit type row
	var unit_types := ["light", "medium", "heavy", "harvester"]
	for unit_class in unit_types:
		var row: HBoxContainer = vbox.get_node_or_null("%sRow" % unit_class.capitalize())
		if row == null:
			continue

		var cost: float = PRODUCTION_COSTS.get(unit_class, 50)
		var can_afford: int = int(remaining_ree / cost)

		# Update afford count
		var afford_label: Label = row.get_node_or_null("Afford")
		if afford_label:
			afford_label.text = "x%d" % can_afford
			if can_afford > 0:
				afford_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.5))
			else:
				afford_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))

		# Update queue count display
		var count_label: Label = row.get_node_or_null("QueueCount")
		if count_label:
			var queued: int = _factory_queue_counts.get(unit_class, 0)
			count_label.text = str(queued)
			if queued > 0:
				count_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
			else:
				count_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

		# Enable/disable buttons based on affordability
		var plus_btn: Button = row.get_node_or_null("PlusBtn")
		if plus_btn:
			plus_btn.disabled = can_afford <= 0

		var minus_btn: Button = row.get_node_or_null("MinusBtn")
		if minus_btn:
			minus_btn.disabled = _factory_queue_counts.get(unit_class, 0) <= 0

	# Update current production display
	var current_prod: VBoxContainer = vbox.get_node_or_null("CurrentProduction")
	if current_prod:
		var current_label: Label = current_prod.get_node_or_null("CurrentLabel")
		var time_remaining_label: Label = current_prod.get_node_or_null("TimeRemaining")

		if not _current_production.is_empty():
			var progress: float = _current_production.get("progress", 0.0)
			var total: float = _current_production.get("total_time", 5.0)
			var pct: float = (progress / total) * 100.0
			var unit_class: String = _current_production.get("unit_class", "Unknown")
			var time_left: float = maxf(0.0, total - progress)

			if current_label:
				current_label.text = "Building: %s" % unit_class.capitalize()
				current_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))

			if _factory_current_production_bar:
				_factory_current_production_bar.value = pct
				# Color by unit type
				var fill_style: StyleBoxFlat = _factory_current_production_bar.get_theme_stylebox("fill") as StyleBoxFlat
				if fill_style:
					match unit_class:
						"light": fill_style.bg_color = Color(0.3, 0.7, 0.3)
						"medium": fill_style.bg_color = Color(0.3, 0.5, 0.8)
						"heavy": fill_style.bg_color = Color(0.8, 0.5, 0.2)
						"harvester": fill_style.bg_color = Color(0.8, 0.7, 0.2)

			if time_remaining_label:
				time_remaining_label.text = "%.1fs" % time_left
		else:
			if current_label:
				current_label.text = "Building: Idle"
				current_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			if _factory_current_production_bar:
				_factory_current_production_bar.value = 0.0
			if time_remaining_label:
				time_remaining_label.text = ""

	# Update detailed queue list
	_update_factory_queue_list()


## Update the detailed queue list in the factory production panel.
func _update_factory_queue_list() -> void:
	if _factory_queue_list_container == null:
		return

	# Clear existing queue items (keep only EmptyLabel)
	for child in _factory_queue_list_container.get_children():
		if child.name != "EmptyLabel":
			child.queue_free()

	# Get empty label
	var empty_label: Label = _factory_queue_list_container.get_node_or_null("EmptyLabel")

	# Show queue items
	if _production_queue.is_empty():
		if empty_label:
			empty_label.visible = true
		return

	if empty_label:
		empty_label.visible = false

	# Create entries for each queued item (limit to 5 visible)
	var max_show := mini(_production_queue.size(), 5)
	for i in range(max_show):
		var item: Dictionary = _production_queue[i]
		var row := _create_factory_queue_item(i, item)
		_factory_queue_list_container.add_child(row)

	# Show overflow count
	if _production_queue.size() > 5:
		var overflow_label := Label.new()
		overflow_label.text = "+%d more in queue..." % (_production_queue.size() - 5)
		overflow_label.add_theme_font_size_override("font_size", 9)
		overflow_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		overflow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_factory_queue_list_container.add_child(overflow_label)


## Create a queue item row for the factory panel.
func _create_factory_queue_item(index: int, item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	# Index
	var idx_label := Label.new()
	idx_label.text = "%d." % (index + 1)
	idx_label.add_theme_font_size_override("font_size", 10)
	idx_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	idx_label.custom_minimum_size.x = 18
	row.add_child(idx_label)

	# Unit type icon
	var unit_class: String = item.get("unit_class", "unknown")
	var icon_label := Label.new()
	var icon_colors := {"light": Color(0.3, 0.7, 0.3), "medium": Color(0.3, 0.5, 0.8), "heavy": Color(0.8, 0.5, 0.2), "harvester": Color(0.8, 0.7, 0.2)}
	var icons := {"light": "◆", "medium": "■", "heavy": "●", "harvester": "▼"}
	icon_label.text = icons.get(unit_class, "?")
	icon_label.add_theme_font_size_override("font_size", 12)
	icon_label.add_theme_color_override("font_color", icon_colors.get(unit_class, Color.WHITE))
	row.add_child(icon_label)

	# Unit name
	var name_label := Label.new()
	var names := {"light": "Scout", "medium": "Soldier", "heavy": "Tank", "harvester": "Harvester"}
	name_label.text = names.get(unit_class, unit_class.capitalize())
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# Time remaining
	var total_time: float = item.get("total_time", 5.0)
	var progress: float = item.get("progress", 0.0)
	var time_remaining: float = maxf(0.0, total_time - progress)
	var time_label := Label.new()
	time_label.text = "%.1fs" % time_remaining
	time_label.add_theme_font_size_override("font_size", 9)
	time_label.add_theme_color_override("font_color", Color(0.5, 0.6, 0.5))
	time_label.custom_minimum_size.x = 30
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(time_label)

	# Cancel button
	var cancel_btn := Button.new()
	cancel_btn.text = "×"
	cancel_btn.custom_minimum_size = Vector2(18, 18)
	cancel_btn.add_theme_font_size_override("font_size", 12)
	cancel_btn.tooltip_text = "Cancel this unit"
	cancel_btn.pressed.connect(_on_cancel_queue_item.bind(index))

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.5, 0.2, 0.2)
	btn_style.set_corner_radius_all(3)
	cancel_btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.7, 0.3, 0.3)
	btn_hover.set_corner_radius_all(3)
	cancel_btn.add_theme_stylebox_override("hover", btn_hover)

	row.add_child(cancel_btn)

	return row


## Handle cancel queue item button press.
func _on_cancel_queue_item(index: int) -> void:
	if index < 0 or index >= _production_queue.size():
		return

	# Refund cost
	var item: Dictionary = _production_queue[index]
	var unit_class: String = item.get("unit_class", "")
	var cost: float = PRODUCTION_COSTS.get(unit_class, 0)

	# Partial refund based on progress (less refund the more progress made)
	var progress: float = item.get("progress", 0.0)
	var total_time: float = item.get("total_time", 5.0)
	var progress_pct: float = progress / total_time
	var refund: float = cost * (1.0 - progress_pct * 0.5)  # 50-100% refund

	# Add refund to resources
	if ResourceManager:
		ResourceManager.add_ree(_player_faction, refund)

	# Remove from queue
	_production_queue.remove_at(index)

	# Play cancel sound
	_play_ui_sound("click")

	# Update displays
	_update_factory_production_panel()
	_update_production_queue_ui()

	print("Cancelled %s production, refunded %.0f REE" % [unit_class, refund])


## Get faction XP damage multiplier for combat
func _get_faction_xp_damage_mult(faction_id: int) -> float:
	if _experience_pool == null:
		return 1.0

	var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
	if faction_str.is_empty():
		return 1.0

	return _experience_pool.get_damage_multiplier(faction_str)


## Get faction XP attack speed multiplier
func _get_faction_xp_attack_speed_mult(faction_id: int) -> float:
	if _experience_pool == null:
		return 1.0

	var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
	if faction_str.is_empty():
		return 1.0

	return _experience_pool.get_attack_speed_multiplier(faction_str)


## Get faction XP dodge chance
func _get_faction_xp_dodge_chance(faction_id: int) -> float:
	if _experience_pool == null:
		return 0.0

	var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
	if faction_str.is_empty():
		return 0.0

	return _experience_pool.get_dodge_chance(faction_str)


## Get faction XP critical strike chance
func _get_faction_xp_crit_chance(faction_id: int) -> float:
	if _experience_pool == null:
		return 0.0

	var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
	if faction_str.is_empty():
		return 0.0

	return _experience_pool.get_critical_strike_chance(faction_str)


# =============================================================================
# HUMAN REMNANT NPC FACTION
# =============================================================================

## Update Human Remnant NPC faction
func _update_human_remnant(delta: float) -> void:
	if not _human_remnant_enabled or _human_remnant_spawner == null:
		return

	# Delay Human Remnant spawn until X seconds into match
	if not _human_remnant_active:
		_human_remnant_spawn_timer += delta
		if _human_remnant_spawn_timer >= HUMAN_REMNANT_SPAWN_DELAY:
			_human_remnant_active = true
			_human_remnant_spawner.start()
			_spawn_floating_text(Vector3(0, 10, 0), "HUMAN REMNANT DETECTED", Color(0.6, 0.4, 0.2), 1.5)
			_play_ui_sound("notification")
			# Spawn patrol groups scattered throughout the city
			_spawn_human_city_patrols()
			# Initialize defense turrets at Military Installation
			_initialize_defense_turrets()
		return

	# Update spawner (handles wave timing internally)
	_human_remnant_spawner.update(delta)

	# Update defense turrets (shoot at nearby robot units)
	_update_defense_turrets(delta)

	# Update faction unit states (ambush cooldowns, etc.)
	if _human_remnant_faction != null:
		for unit_id in _human_remnant_faction.get_active_unit_ids():
			_human_remnant_faction.update_unit(unit_id, delta)


## Callback when Human Remnant unit is spawned by the spawner
func _on_human_remnant_unit_spawned(unit_id: int, unit_type_str: String, spawn_pos: Vector3) -> void:
	# Map Human Remnant unit types to our standard unit types
	var mapped_type := "soldier"  # Default
	match unit_type_str:
		"soldier": mapped_type = "light"       # Scouts/fast units
		"sniper": mapped_type = "medium"       # Medium range/damage
		"heavy_gunner": mapped_type = "heavy"  # Heavy damage dealers
		"commander": mapped_type = "medium"    # Support unit (medium)

	# Spawn actual game unit using faction 5
	var unit := _spawn_unit(HUMAN_REMNANT_FACTION_ID, spawn_pos, mapped_type)
	if unit.is_empty():
		return

	# Store Human Remnant specific data
	unit["hr_unit_type"] = unit_type_str
	unit["hr_spawner_id"] = unit_id  # Link to spawner's tracking

	# Apply Human Remnant specific stats from HumanResistanceAIFaction
	var hr_stats: Dictionary = HumanResistanceAIFaction.get_unit_type_stats(unit_type_str)
	if not hr_stats.is_empty():
		# Override with Human Remnant specific stats
		unit.max_health = hr_stats.get("max_health", unit.max_health)
		unit.health = unit.max_health
		unit.damage = hr_stats.get("damage", unit.damage)
		unit.attack_speed = hr_stats.get("attack_speed", unit.attack_speed)
		unit.attack_range = hr_stats.get("range", unit.attack_range)
		unit.speed = hr_stats.get("speed", unit.speed)

	# Register with faction for ambush tracking
	if _human_remnant_faction != null:
		_human_remnant_faction.register_unit(unit.id, unit_type_str)

	# Human Remnant units always attack-move and seek enemies
	unit["attack_move"] = true


## Callback when Human Remnant wave starts
func _on_human_remnant_wave_started(wave_number: int, _unit_count: int) -> void:
	# Show wave notification to player
	var hr_color: Color = FACTION_COLORS.get(HUMAN_REMNANT_FACTION_ID, Color(0.6, 0.4, 0.2))
	if wave_number == 1:
		_spawn_floating_text(Vector3(0, 8, 0), "Human Remnant forces attacking!", hr_color, 2.0)
	elif wave_number % 5 == 0:  # Every 5th wave
		_spawn_floating_text(Vector3(0, 8, 0), "Human Remnant reinforcements!", hr_color, 1.5)


## Callback when Human Remnant wave completes spawning
func _on_human_remnant_wave_completed(wave_number: int) -> void:
	# Track stat for wave survival
	_track_stat(_player_faction, "hr_waves_survived", 1.0)


## Handle Human Remnant unit death (cleanup spawner tracking)
func _on_human_remnant_unit_died(unit: Dictionary) -> void:
	if not _human_remnant_enabled:
		return

	# Get the spawner ID if this was a Human Remnant unit
	var spawner_id: int = unit.get("hr_spawner_id", -1)
	if spawner_id >= 0 and _human_remnant_spawner != null:
		_human_remnant_spawner.register_unit_defeated(spawner_id)

	# Unregister from faction
	var unit_id: int = unit.get("id", -1)
	if unit_id >= 0 and _human_remnant_faction != null:
		_human_remnant_faction.unregister_unit(unit_id)


## Check if unit is Human Remnant
func _is_human_remnant_unit(unit: Dictionary) -> bool:
	return unit.get("faction_id", 0) == HUMAN_REMNANT_FACTION_ID


## Get Human Remnant ambush damage bonus for a unit
func _get_human_remnant_ambush_bonus(unit: Dictionary) -> float:
	if not _is_human_remnant_unit(unit):
		return 0.0
	if _human_remnant_faction == null:
		return 0.0

	var unit_id: int = unit.get("id", -1)
	if unit_id < 0:
		return 0.0

	return _human_remnant_faction.get_ambush_damage_bonus(unit_id)


## Spawn Human Remnant patrol groups scattered throughout the city.
## Called when Human Remnant first activates (after initial delay).
func _spawn_human_city_patrols() -> void:
	if not _human_remnant_enabled or _human_remnant_faction == null:
		return

	print("Spawning Human Remnant city patrols...")

	# Define patrol locations throughout the city (factories are now on sides)
	# City is centered at origin, MAP_SIZE is 2400 (so -1200 to +1200)
	# The center has a Military Installation where Human Resistance is concentrated
	var patrol_locations: Array[Dictionary] = [
		# MILITARY INSTALLATION CENTER (heavily fortified)
		# Main garrison inside the base
		{"pos": Vector3(0, 0, 0), "size": 8, "type": "garrison"},      # Central command (larger garrison)
		{"pos": Vector3(30, 0, 0), "size": 5, "type": "heavy"},        # East of command
		{"pos": Vector3(-30, 0, 0), "size": 5, "type": "heavy"},       # West of command
		{"pos": Vector3(0, 0, 30), "size": 5, "type": "soldier"},      # South of command
		{"pos": Vector3(0, 0, -30), "size": 5, "type": "soldier"},     # North of command

		# Tower guard positions (corner towers of Military Installation)
		{"pos": Vector3(60, 0, 60), "size": 3, "type": "sniper"},      # SE tower
		{"pos": Vector3(-60, 0, 60), "size": 3, "type": "sniper"},     # SW tower
		{"pos": Vector3(60, 0, -60), "size": 3, "type": "sniper"},     # NE tower
		{"pos": Vector3(-60, 0, -60), "size": 3, "type": "sniper"},    # NW tower

		# Perimeter patrol (just outside the walls of Military Installation)
		{"pos": Vector3(100, 0, 0), "size": 4, "type": "patrol"},      # East perimeter
		{"pos": Vector3(-100, 0, 0), "size": 4, "type": "patrol"},     # West perimeter
		{"pos": Vector3(0, 0, 100), "size": 4, "type": "patrol"},      # South perimeter
		{"pos": Vector3(0, 0, -100), "size": 4, "type": "patrol"},     # North perimeter

		# INNER CITY PATROLS (first ring, ~200-300 from center)
		{"pos": Vector3(250, 0, 0), "size": 4, "type": "mixed"},       # East inner
		{"pos": Vector3(-250, 0, 0), "size": 4, "type": "mixed"},      # West inner
		{"pos": Vector3(0, 0, 250), "size": 4, "type": "mixed"},       # South inner
		{"pos": Vector3(0, 0, -250), "size": 4, "type": "mixed"},      # North inner
		{"pos": Vector3(180, 0, 180), "size": 3, "type": "heavy"},     # SE inner
		{"pos": Vector3(-180, 0, 180), "size": 3, "type": "heavy"},    # SW inner
		{"pos": Vector3(180, 0, -180), "size": 3, "type": "heavy"},    # NE inner
		{"pos": Vector3(-180, 0, -180), "size": 3, "type": "heavy"},   # NW inner

		# MID CITY PATROLS (second ring, ~400-500 from center)
		{"pos": Vector3(450, 0, 0), "size": 4, "type": "mixed"},       # East mid
		{"pos": Vector3(-450, 0, 0), "size": 4, "type": "mixed"},      # West mid
		{"pos": Vector3(0, 0, 450), "size": 4, "type": "mixed"},       # South mid
		{"pos": Vector3(0, 0, -450), "size": 4, "type": "mixed"},      # North mid
		{"pos": Vector3(350, 0, 350), "size": 4, "type": "heavy"},     # SE mid
		{"pos": Vector3(-350, 0, 350), "size": 4, "type": "heavy"},    # SW mid
		{"pos": Vector3(350, 0, -350), "size": 4, "type": "heavy"},    # NE mid
		{"pos": Vector3(-350, 0, -350), "size": 4, "type": "heavy"},   # NW mid

		# OUTER CITY PATROLS (third ring, ~600-700 from center)
		{"pos": Vector3(650, 0, 0), "size": 3, "type": "patrol"},      # East outer
		{"pos": Vector3(-650, 0, 0), "size": 3, "type": "patrol"},     # West outer
		{"pos": Vector3(0, 0, 650), "size": 3, "type": "patrol"},      # South outer
		{"pos": Vector3(0, 0, -650), "size": 3, "type": "patrol"},     # North outer
		{"pos": Vector3(500, 0, 500), "size": 3, "type": "mixed"},     # SE outer
		{"pos": Vector3(-500, 0, 500), "size": 3, "type": "mixed"},    # SW outer
		{"pos": Vector3(500, 0, -500), "size": 3, "type": "mixed"},    # NE outer
		{"pos": Vector3(-500, 0, -500), "size": 3, "type": "mixed"},   # NW outer

		# FAR OUTER PATROLS (fourth ring, ~800-900 from center, closer to faction territories)
		{"pos": Vector3(850, 0, 0), "size": 3, "type": "patrol"},      # Far east
		{"pos": Vector3(-850, 0, 0), "size": 3, "type": "patrol"},     # Far west
		{"pos": Vector3(0, 0, 850), "size": 3, "type": "patrol"},      # Far south
		{"pos": Vector3(0, 0, -850), "size": 3, "type": "patrol"},     # Far north
		{"pos": Vector3(700, 0, 700), "size": 3, "type": "mixed"},     # Far SE
		{"pos": Vector3(-700, 0, 700), "size": 3, "type": "mixed"},    # Far SW
		{"pos": Vector3(700, 0, -700), "size": 3, "type": "mixed"},    # Far NE
		{"pos": Vector3(-700, 0, -700), "size": 3, "type": "mixed"},   # Far NW

		# FRONTIER PATROLS (scattered between outer ring and factories)
		{"pos": Vector3(550, 0, 250), "size": 2, "type": "patrol"},    # SE frontier 1
		{"pos": Vector3(250, 0, 550), "size": 2, "type": "patrol"},    # SE frontier 2
		{"pos": Vector3(-550, 0, 250), "size": 2, "type": "patrol"},   # SW frontier 1
		{"pos": Vector3(-250, 0, 550), "size": 2, "type": "patrol"},   # SW frontier 2
		{"pos": Vector3(550, 0, -250), "size": 2, "type": "patrol"},   # NE frontier 1
		{"pos": Vector3(250, 0, -550), "size": 2, "type": "patrol"},   # NE frontier 2
		{"pos": Vector3(-550, 0, -250), "size": 2, "type": "patrol"},  # NW frontier 1
		{"pos": Vector3(-250, 0, -550), "size": 2, "type": "patrol"},  # NW frontier 2
	]

	var total_spawned := 0
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	for patrol in patrol_locations:
		var base_pos: Vector3 = patrol.pos
		var group_size: int = patrol.size
		var patrol_type: String = patrol.type

		# Skip positions too close to faction factories (now at ±1000)
		var too_close_to_factory := false
		for factory_pos in [Vector3(-1000, 0, 0), Vector3(1000, 0, 0), Vector3(0, 0, -1000), Vector3(0, 0, 1000)]:
			if base_pos.distance_to(factory_pos) < 120.0:
				too_close_to_factory = true
				break

		if too_close_to_factory:
			continue

		# Check if position is blocked by buildings and find clear spot
		var spawn_pos := base_pos
		if _city_renderer != null and _city_renderer.is_position_blocked(base_pos, 3.0):
			# Try to find nearby clear position
			for attempt in range(8):
				var angle := attempt * (TAU / 8.0)
				var offset := Vector3(cos(angle) * 10.0, 0, sin(angle) * 10.0)
				var test_pos := base_pos + offset
				if not _city_renderer.is_position_blocked(test_pos, 3.0):
					spawn_pos = test_pos
					break

		# Spawn patrol group
		for i in range(group_size):
			# Offset each unit slightly for formation
			var row: int = i / 2
			var col: int = i % 2
			var unit_offset := Vector3((col - 0.5) * 3.0, 0, row * 3.0)
			var unit_pos := spawn_pos + unit_offset

			# Determine unit type
			var unit_type_str := "soldier"
			match patrol_type:
				"sniper":
					unit_type_str = "sniper"
				"heavy":
					unit_type_str = "heavy_gunner" if rng.randf() < 0.3 else "soldier"
				"garrison":
					# Elite garrison - mix of all unit types
					var roll := rng.randf()
					if roll < 0.2:
						unit_type_str = "heavy_gunner"
					elif roll < 0.4:
						unit_type_str = "sniper"
					else:
						unit_type_str = "soldier"
				"patrol":
					# Standard patrol - mostly soldiers with some snipers
					unit_type_str = "sniper" if rng.randf() < 0.25 else "soldier"
				"mixed":
					var roll := rng.randf()
					if roll < 0.1:
						unit_type_str = "heavy_gunner"
					elif roll < 0.3:
						unit_type_str = "sniper"
					else:
						unit_type_str = "soldier"
				_:
					unit_type_str = "soldier"

			# Spawn the unit using the same callback as wave spawning
			_on_human_remnant_unit_spawned(rng.randi(), unit_type_str, unit_pos)
			total_spawned += 1

	print("  Spawned %d Human Remnant patrol units in %d locations" % [total_spawned, patrol_locations.size()])
	_spawn_floating_text(Vector3(0, 6, 0), "Human patrols detected in city!", Color(0.6, 0.4, 0.2), 1.5)


# =============================================================================
# DEFENSE TURRETS (Military Installation)
# =============================================================================

## Initialize defense turrets at the Military Installation.
## Turrets are positioned on the corner towers of the base.
func _initialize_defense_turrets() -> void:
	print("Initializing Military Installation defense turrets...")

	# Turret positions (on top of corner towers - Y=36 is tower height + turret base)
	var turret_positions: Array[Dictionary] = [
		{"pos": Vector3(67, 36, -67), "name": "TurretNE", "facing": Vector3(1, 0, -1).normalized()},
		{"pos": Vector3(-67, 36, -67), "name": "TurretNW", "facing": Vector3(-1, 0, -1).normalized()},
		{"pos": Vector3(67, 36, 67), "name": "TurretSE", "facing": Vector3(1, 0, 1).normalized()},
		{"pos": Vector3(-67, 36, 67), "name": "TurretSW", "facing": Vector3(-1, 0, 1).normalized()},
	]

	_defense_turrets.clear()

	for turret_data in turret_positions:
		var turret := {
			"position": turret_data.pos,
			"name": turret_data.name,
			"facing": turret_data.facing,
			"cooldown": randf_range(0.0, 1.0),  # Stagger initial fire
			"target_id": -1,
			"health": 500.0,
			"max_health": 500.0,
			"is_destroyed": false
		}
		_defense_turrets.append(turret)

	# Initialize mortar system
	_mortar_active = true
	_mortar_cooldown = 2.0  # Initial delay before first mortar

	print("  Initialized %d defense turrets + mortar" % _defense_turrets.size())
	_spawn_floating_text(Vector3(0, 20, 0), "DEFENSE SYSTEMS ONLINE!", Color(0.9, 0.3, 0.1), 2.0)


## Update defense turrets - find targets and fire at enemies.
func _update_defense_turrets(delta: float) -> void:
	# Update turrets
	for turret in _defense_turrets:
		if turret.is_destroyed:
			continue

		# Reduce cooldown
		turret.cooldown = maxf(0.0, turret.cooldown - delta)

		# Find nearest enemy (any robot faction, not Human Remnant)
		var turret_pos: Vector3 = turret.position
		var best_target: Node3D = null
		var best_distance := TURRET_RANGE

		for unit in _units:
			if not is_instance_valid(unit):
				continue

			# Skip Human Remnant units (allies)
			var faction_id: int = unit.get_meta("faction_id", 0)
			if faction_id == HUMAN_REMNANT_FACTION_ID or faction_id == 0:
				continue

			# Check range
			var distance := turret_pos.distance_to(unit.global_position)
			if distance < best_distance:
				best_distance = distance
				best_target = unit

		# Fire at target if we have one and cooldown is ready
		if best_target != null and turret.cooldown <= 0.0:
			_turret_fire_at(turret, best_target)
			turret.cooldown = TURRET_FIRE_RATE

	# Update mortar system
	_update_mortar_system(delta)


## Fire a turret projectile at a target.
func _turret_fire_at(turret: Dictionary, target: Node3D) -> void:
	var start_pos: Vector3 = turret.position + Vector3(0, 4, 0)  # Barrel height
	var target_pos: Vector3 = target.global_position + Vector3(0, 1.5, 0)  # Aim at center

	# Miss chance - offset target position
	var is_miss := randf() < TURRET_MISS_CHANCE
	if is_miss:
		var miss_offset := Vector3(
			randf_range(-12.0, 12.0),
			randf_range(-2.0, 4.0),
			randf_range(-12.0, 12.0)
		)
		target_pos += miss_offset

	var direction: Vector3 = (target_pos - start_pos).normalized()

	# Create projectile mesh (cylinder shape for turret shots)
	var proj_mesh := CSGCylinder3D.new()
	proj_mesh.radius = 0.4
	proj_mesh.height = 2.0
	proj_mesh.position = start_pos
	# Rotate to point in direction of travel
	proj_mesh.look_at_from_position(start_pos, start_pos + direction, Vector3.UP)
	proj_mesh.rotate_object_local(Vector3.RIGHT, PI/2)

	# Create turret projectile material (orange-red, menacing)
	var proj_mat := StandardMaterial3D.new()
	proj_mat.albedo_color = Color(1.0, 0.3, 0.1)
	proj_mat.emission_enabled = true
	proj_mat.emission = Color(1.0, 0.4, 0.1)
	proj_mat.emission_energy_multiplier = 3.0
	proj_mesh.material = proj_mat

	_projectile_container.add_child(proj_mesh)

	# Create projectile trail
	var trail := _create_projectile_trail(HUMAN_REMNANT_FACTION_ID)
	if trail != null:
		_projectile_container.add_child(trail)

	# Create projectile dictionary matching existing structure
	var projectile := {
		"mesh": proj_mesh,
		"trail": trail,
		"trail_positions": [start_pos],
		"target": null if is_miss else target,
		"from_faction": HUMAN_REMNANT_FACTION_ID,
		"from_unit_id": -1,  # No unit, it's a turret
		"direction": direction,
		"speed": TURRET_PROJECTILE_SPEED,
		"damage": TURRET_DAMAGE,
		"splash_radius": TURRET_SPLASH_RADIUS,  # Splash damage!
		"splash_falloff": 0.5,
		"lifetime": 3.0,
		"is_miss": is_miss,
		"is_turret_shot": true
	}
	_projectiles.append(projectile)

	# Spawn muzzle flash
	_spawn_muzzle_flash(start_pos, HUMAN_REMNANT_FACTION_ID)

	# Play weapon fire sound
	if _should_play_sound():
		_play_laser_sound(start_pos)


# =============================================================================
# MORTAR SYSTEM
# =============================================================================

## Update the mortar system - find targets and fire mortars.
func _update_mortar_system(delta: float) -> void:
	if not _mortar_active:
		return

	# Reduce cooldown
	_mortar_cooldown = maxf(0.0, _mortar_cooldown - delta)

	# Find a random target and fire mortar
	if _mortar_cooldown <= 0.0:
		var potential_targets: Array[Node3D] = []
		var mortar_pos := Vector3(0, 45, 0)  # Top of command tower

		for unit in _units:
			if not is_instance_valid(unit):
				continue

			# Skip Human Remnant units
			var faction_id: int = unit.get_meta("faction_id", 0)
			if faction_id == HUMAN_REMNANT_FACTION_ID or faction_id == 0:
				continue

			# Check range
			var distance := mortar_pos.distance_to(unit.global_position)
			if distance < MORTAR_RANGE and distance > 50.0:  # Min range to avoid self-damage
				potential_targets.append(unit)

		if not potential_targets.is_empty():
			var target: Node3D = potential_targets[randi() % potential_targets.size()]
			_fire_mortar(target.global_position)
			_mortar_cooldown = MORTAR_FIRE_RATE

	# Update incoming mortars
	_update_incoming_mortars(delta)


## Fire a mortar at a target position.
func _fire_mortar(target_pos: Vector3) -> void:
	var mortar_start := Vector3(0, 45, 0)  # Command tower top

	# Create target indicator (warning circle)
	var indicator := _create_mortar_target_indicator(target_pos)

	# Create mortar projectile (starts high, arcs down)
	var mortar := {
		"target_pos": target_pos,
		"start_pos": mortar_start,
		"flight_time": 0.0,
		"total_flight_time": MORTAR_FLIGHT_TIME,
		"indicator": indicator,
		"projectile": null  # Created when mortar becomes visible
	}
	_incoming_mortars.append(mortar)

	# Play mortar launch BOOM sound
	_play_mortar_fire_sound(mortar_start)

	# Spawn floating text warning
	_spawn_floating_text(target_pos + Vector3(0, 5, 0), "INCOMING!", Color(1.0, 0.2, 0.0), 1.0)


## Create the target indicator for incoming mortar.
func _create_mortar_target_indicator(target_pos: Vector3) -> Node3D:
	var indicator := Node3D.new()
	indicator.position = target_pos + Vector3(0, 0.5, 0)

	# Outer warning ring (pulsing)
	var outer_ring := CSGTorus3D.new()
	outer_ring.inner_radius = MORTAR_SPLASH_RADIUS - 1.0
	outer_ring.outer_radius = MORTAR_SPLASH_RADIUS
	outer_ring.rotation.x = PI / 2  # Lay flat

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.2, 0.0, 0.6)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.3, 0.0)
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_ring.material = ring_mat
	indicator.add_child(outer_ring)

	# Inner crosshair
	var crosshair := CSGBox3D.new()
	crosshair.size = Vector3(MORTAR_SPLASH_RADIUS * 2, 0.2, 1.0)
	var cross_mat := StandardMaterial3D.new()
	cross_mat.albedo_color = Color(1.0, 0.0, 0.0, 0.8)
	cross_mat.emission_enabled = true
	cross_mat.emission = Color(1.0, 0.1, 0.0)
	cross_mat.emission_energy_multiplier = 3.0
	cross_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	crosshair.material = cross_mat
	indicator.add_child(crosshair)

	var crosshair2 := CSGBox3D.new()
	crosshair2.size = Vector3(1.0, 0.2, MORTAR_SPLASH_RADIUS * 2)
	crosshair2.material = cross_mat
	indicator.add_child(crosshair2)

	_effects_container.add_child(indicator)
	return indicator


## Update incoming mortars.
func _update_incoming_mortars(delta: float) -> void:
	var completed_mortars: Array[int] = []

	for i in _incoming_mortars.size():
		var mortar: Dictionary = _incoming_mortars[i]
		mortar.flight_time += delta

		var progress: float = mortar.flight_time / mortar.total_flight_time

		# Create visible projectile halfway through flight
		if progress > 0.4 and mortar.projectile == null:
			mortar.projectile = _create_mortar_projectile(mortar)

		# Update projectile position (arc trajectory)
		if mortar.projectile != null and is_instance_valid(mortar.projectile):
			var start: Vector3 = mortar.start_pos
			var target: Vector3 = mortar.target_pos
			var arc_height := 100.0

			# Parabolic arc
			var t: float = progress
			var current_pos := start.lerp(target, t)
			current_pos.y += arc_height * 4.0 * t * (1.0 - t)  # Parabola
			mortar.projectile.position = current_pos

		# Pulse the indicator
		if is_instance_valid(mortar.indicator):
			var pulse := 1.0 + 0.3 * sin(mortar.flight_time * 10.0)
			mortar.indicator.scale = Vector3(pulse, 1, pulse)

		# Impact!
		if progress >= 1.0:
			_mortar_impact(mortar)
			completed_mortars.append(i)

	# Remove completed mortars (reverse order to preserve indices)
	for i in range(completed_mortars.size() - 1, -1, -1):
		_incoming_mortars.remove_at(completed_mortars[i])


## Create the visible mortar projectile.
func _create_mortar_projectile(mortar: Dictionary) -> Node3D:
	var proj := CSGSphere3D.new()
	proj.radius = 2.5

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.2)
	mat.metallic = 0.8
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 3.0
	proj.material = mat

	# Add fire/spark trail (bright orange sparks)
	var fire_trail := GPUParticles3D.new()
	fire_trail.emitting = true
	fire_trail.amount = 40
	fire_trail.lifetime = 0.4
	fire_trail.local_coords = false

	var fire_mat := ParticleProcessMaterial.new()
	fire_mat.direction = Vector3(0, 1, 0)
	fire_mat.spread = 15.0
	fire_mat.initial_velocity_min = 3.0
	fire_mat.initial_velocity_max = 8.0
	fire_mat.gravity = Vector3(0, -2, 0)
	fire_mat.scale_min = 0.8
	fire_mat.scale_max = 1.5
	fire_mat.color = Color(1.0, 0.5, 0.1)
	fire_trail.process_material = fire_mat

	var fire_mesh := SphereMesh.new()
	fire_mesh.radius = 0.4
	fire_mesh.height = 0.8
	fire_trail.draw_pass_1 = fire_mesh
	proj.add_child(fire_trail)

	# Add SMOKE TRAIL (dark smoke that lingers)
	var smoke_trail := GPUParticles3D.new()
	smoke_trail.emitting = true
	smoke_trail.amount = 60
	smoke_trail.lifetime = 1.5  # Longer lasting smoke
	smoke_trail.local_coords = false

	var smoke_mat := ParticleProcessMaterial.new()
	smoke_mat.direction = Vector3(0, 1, 0)
	smoke_mat.spread = 25.0
	smoke_mat.initial_velocity_min = 1.0
	smoke_mat.initial_velocity_max = 4.0
	smoke_mat.gravity = Vector3(0, 2, 0)  # Smoke rises
	smoke_mat.scale_min = 1.5
	smoke_mat.scale_max = 4.0
	# Smoke starts gray, fades to transparent
	smoke_mat.color = Color(0.3, 0.3, 0.3, 0.7)
	smoke_trail.process_material = smoke_mat

	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 1.0
	smoke_mesh.height = 2.0
	smoke_trail.draw_pass_1 = smoke_mesh

	# Smoke material with transparency
	var smoke_draw_mat := StandardMaterial3D.new()
	smoke_draw_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
	smoke_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mesh.material = smoke_draw_mat
	proj.add_child(smoke_trail)

	_projectile_container.add_child(proj)

	return proj


## Handle mortar impact.
func _mortar_impact(mortar: Dictionary) -> void:
	var impact_pos: Vector3 = mortar.target_pos

	# Remove indicator
	if is_instance_valid(mortar.indicator):
		mortar.indicator.queue_free()

	# Remove projectile
	if mortar.projectile != null and is_instance_valid(mortar.projectile):
		mortar.projectile.queue_free()

	# Create big explosion effect
	_create_mortar_explosion(impact_pos)

	# Deal splash damage to all units in radius
	for unit in _units:
		if not is_instance_valid(unit):
			continue

		# Don't damage Human Remnant
		var faction_id: int = unit.get_meta("faction_id", 0)
		if faction_id == HUMAN_REMNANT_FACTION_ID:
			continue

		var distance := impact_pos.distance_to(unit.global_position)
		if distance < MORTAR_SPLASH_RADIUS:
			# Damage falloff based on distance
			var falloff := 1.0 - (distance / MORTAR_SPLASH_RADIUS) * 0.5
			var damage := MORTAR_DAMAGE * falloff

			# Apply damage
			var unit_health: float = unit.get_meta("health", 100.0)
			unit_health -= damage
			unit.set_meta("health", unit_health)

			# Spawn damage number
			_spawn_damage_number(unit.global_position, damage)

	# Deal damage to buildings in splash radius
	if _city_renderer != null and _city_renderer.has_method("get_building_at_position"):
		# Check multiple points in the splash radius
		var check_offsets := [
			Vector3.ZERO,
			Vector3(MORTAR_SPLASH_RADIUS * 0.5, 0, 0),
			Vector3(-MORTAR_SPLASH_RADIUS * 0.5, 0, 0),
			Vector3(0, 0, MORTAR_SPLASH_RADIUS * 0.5),
			Vector3(0, 0, -MORTAR_SPLASH_RADIUS * 0.5),
		]
		var damaged_building_ids: Array[int] = []
		for offset in check_offsets:
			var check_pos: Vector3 = impact_pos + offset
			var building_id: int = _city_renderer.get_building_at_position(check_pos, 5.0)
			if building_id >= 0 and building_id not in damaged_building_ids:
				damaged_building_ids.append(building_id)
				# Heavy building damage from mortar
				_city_renderer.damage_building(building_id, MORTAR_DAMAGE * 1.5, check_pos)

	# Screen shake - big shake for mortar!
	_camera_shake(0.8, 15.0)

	# Play BIG mortar impact explosion sound
	_play_explosion_sound(impact_pos, 2.5)  # Large explosion


## Create mortar explosion effect.
func _create_mortar_explosion(pos: Vector3) -> void:
	# Main explosion particles
	var explosion := GPUParticles3D.new()
	explosion.emitting = true
	explosion.one_shot = true
	explosion.amount = 100
	explosion.lifetime = 1.5
	explosion.explosiveness = 1.0
	explosion.position = pos

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 50.0
	mat.gravity = Vector3(0, -30, 0)
	mat.color = Color(1.0, 0.5, 0.1)
	mat.scale_min = 2.0
	mat.scale_max = 5.0
	explosion.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	explosion.draw_pass_1 = mesh

	_effects_container.add_child(explosion)

	# Shockwave ring
	var ring := CSGTorus3D.new()
	ring.inner_radius = 1.0
	ring.outer_radius = 3.0
	ring.position = pos + Vector3(0, 1, 0)
	ring.rotation.x = PI / 2

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.6, 0.2, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.4, 0.0)
	ring_mat.emission_energy_multiplier = 5.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = ring_mat

	_effects_container.add_child(ring)

	# Animate shockwave expansion
	var tween := create_tween()
	tween.tween_property(ring, "scale", Vector3(MORTAR_SPLASH_RADIUS / 3.0, 1, MORTAR_SPLASH_RADIUS / 3.0), 0.5)
	tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_callback(ring.queue_free)

	# Cleanup explosion after lifetime
	get_tree().create_timer(2.0).timeout.connect(explosion.queue_free)


# =============================================================================
# SETTINGS PERSISTENCE
# =============================================================================

## Apply loaded settings to the game systems.
func _apply_loaded_settings() -> void:
	if _settings_manager == null:
		return

	# Apply audio settings
	_apply_audio_settings()

	# Apply graphics settings
	_apply_graphics_settings()

	# Apply gameplay settings
	_apply_gameplay_settings()

	print("Settings applied to game systems")


## Apply audio settings to AudioServer.
func _apply_audio_settings() -> void:
	if _settings_manager == null:
		return

	# Apply volume levels to audio buses
	var master_vol: float = _settings_manager.get_master_volume()
	var music_vol: float = _settings_manager.get_music_volume()
	var sfx_vol: float = _settings_manager.get_sfx_volume()
	var ui_vol: float = _settings_manager.get_ui_volume()

	# Convert linear volume to dB (0.0 = -80dB, 1.0 = 0dB)
	var master_db: float = linear_to_db(master_vol) if master_vol > 0 else -80.0
	var music_db: float = linear_to_db(music_vol) if music_vol > 0 else -80.0
	var sfx_db: float = linear_to_db(sfx_vol) if sfx_vol > 0 else -80.0
	var ui_db: float = linear_to_db(ui_vol) if ui_vol > 0 else -80.0

	# Apply to audio buses if they exist
	var master_idx: int = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, master_db)

	var music_idx: int = AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, music_db)

	var sfx_idx: int = AudioServer.get_bus_index("SFX")
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, sfx_db)

	var ui_idx: int = AudioServer.get_bus_index("UI")
	if ui_idx >= 0:
		AudioServer.set_bus_volume_db(ui_idx, ui_db)


## Apply graphics settings.
func _apply_graphics_settings() -> void:
	if _settings_manager == null:
		return

	# Fullscreen
	var fullscreen: bool = _settings_manager.get_fullscreen()
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# VSync
	var vsync: bool = _settings_manager.get_vsync()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)

	# Max FPS
	var max_fps: int = _settings_manager.get_max_fps()
	Engine.max_fps = max_fps


## Apply gameplay settings.
func _apply_gameplay_settings() -> void:
	if _settings_manager == null:
		return

	# Game speed is applied in _process if needed
	pass


## Callback when a setting changes.
func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	print("Setting changed: %s/%s = %s" % [section, key, str(value)])

	# Apply changes immediately
	match section:
		"audio":
			_apply_audio_settings()
		"graphics":
			_apply_graphics_settings()
		"gameplay":
			_apply_gameplay_settings()

	# Auto-save settings on change
	if _settings_manager != null:
		_settings_manager.save_settings()


## Save settings (call when exiting or on demand).
func _save_settings() -> void:
	if _settings_manager != null:
		_settings_manager.save_settings()


func _process(delta: float) -> void:
	_frame_count += 1
	_reset_sound_counter()  # Reset audio throttle for this frame
	_update_audio_manager(delta)  # Update audio system
	_handle_camera_input(delta)
	_update_camera_shake(delta)
	_handle_production_input()

	# Update pathfinding bridge (batches navmesh updates)
	if _pathfinding_bridge != null:
		_pathfinding_bridge.process(delta)

	# Rotate faction info viewer models
	if _faction_info_visible and not _faction_info_models.is_empty():
		_update_faction_info_models(delta)

	# Update unit spec popup animations
	if _unit_spec_visible:
		_update_combat_preview(delta)

	if GameStateManager.get_match_status() == GameStateManager.MatchStatus.ACTIVE:
		# Track match time
		_match_time += delta

		# Autosave timer
		_autosave_timer += delta
		if _autosave_timer >= AUTOSAVE_INTERVAL:
			_autosave_timer = 0.0
			_perform_autosave()

		# Visibility culling - FIRST, before any rendering updates
		# This hides off-screen units to save rendering cost (CSG is expensive!)
		_update_visibility_culling()

		# Critical updates - every frame
		_update_units(delta)
		_update_combat(delta)
		_update_projectiles(delta)
		_update_explosions(delta)
		_update_production(delta)
		_update_wreckage(delta)  # Decay old wreckage
		_update_unit_ejections(delta)  # Unit ejection animations from factories
		_update_harvesters(delta)  # Harvester AI for collecting REE
		_update_faction_ai(delta)  # AI faction spawning and attacks
		_update_human_remnant(delta)  # Human Remnant NPC faction
		_update_ruins(delta)  # Age and cleanup building ruins

		# Player passive income (same as AI)
		if ResourceManager:
			ResourceManager.add_ree(_player_faction, AI_PASSIVE_INCOME * delta, "passive")

		# Update kill streak timer
		if _kill_streak_timer > 0:
			_kill_streak_timer -= delta
			if _kill_streak_timer <= 0:
				_kill_streak = 0

		# Moderate priority - every frame but lightweight
		_update_blink_effects()
		_update_selection_rings()
		_update_stance_indicators()
		_update_selection_count_display()
		_update_portrait_panel()
		_update_resource_panel()
		_update_production_queue_ui()
		_update_kill_feed()
		_update_match_timer()
		_update_control_group_badges()
		_update_unit_overview_panel()  # Army overview on right side
		_update_factory_production_panel()  # Factory menu when selected
		_update_pings()
		_update_attack_move_indicator()
		_update_queue_mode_indicator()
		_update_command_flash()
		_update_queue_indicators()
		_update_range_circles()
		_update_unit_count_display()
		_update_ree_stats_display()
		_cleanup_dead_units()

		# Update MultiMesh batched rendering (process dirty transforms)
		if _multimesh_renderer != null and _use_multimesh_rendering:
			_multimesh_renderer.update_multimesh_rendering()

		# Update LOD system with camera position and process LOD changes
		if _lod_system != null and camera != null:
			_lod_system.set_camera_position(camera.global_position)
			_lod_system.update(delta)

		# Update voxel system with camera position for LOD and streaming
		if _voxel_system != null and camera != null:
			_voxel_system.set_camera_position(camera.global_position)
			# Also set frustum planes for culling
			_voxel_system.set_camera_frustum(camera.get_frustum())

		# Advance performance tier system frame counter and update tiers periodically
		if _performance_tier_system != null and _use_performance_tiers:
			_performance_tier_system.advance_frame()
			# Update tier assignments every 30 frames (~0.5s at 60fps)
			if _frame_count % 30 == 0:
				_performance_tier_system.update_tiers()

		# Process Hive Mind XP updates (thread-safe batched)
		if _experience_pool != null:
			_experience_pool.process_updates()

		# Throttled updates - less frequent for performance
		if _frame_count % MINIMAP_UPDATE_INTERVAL == 0:
			_update_minimap_icons()
			_update_minimap_camera_indicator()
			_update_factory_health_bars()
			_update_factory_status_panel()
			_update_ree_pickups(delta * MINIMAP_UPDATE_INTERVAL)
			_update_unit_tooltip()
			_update_enemy_indicators()
			_update_threat_indicator()
			_update_veterancy_indicators()
			_update_xp_display()  # Update Hive Mind XP panel

		if _frame_count % FOG_UPDATE_INTERVAL == 0:
			_update_fog_of_war()
			_update_unit_healing(delta * FOG_UPDATE_INTERVAL)
			_update_unit_behaviors()
			_update_faction_mechanics(delta * FOG_UPDATE_INTERVAL)
			_update_factory_combat(delta * FOG_UPDATE_INTERVAL)
			_update_power_grid(delta * FOG_UPDATE_INTERVAL)
			_update_power_grid_overlay()  # Update power grid overlay UI if visible
			_update_districts(delta * FOG_UPDATE_INTERVAL)
			_update_factory_construction(delta * FOG_UPDATE_INTERVAL)
			_check_victory_defeat()

	# Debug info - heavily throttled
	if _frame_count % DEBUG_UPDATE_INTERVAL == 0:
		_update_debug_info()


func _handle_camera_input(delta: float) -> void:
	if camera == null:
		return

	# Camera panning (WASD + edge of screen)
	var move_dir := Vector3.ZERO

	# Keyboard panning
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_dir.z -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_dir.z += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move_dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move_dir.x += 1

	# Edge-of-screen panning (RTS style)
	var mouse_pos := get_viewport().get_mouse_position()
	var screen_size := get_viewport().get_visible_rect().size
	if mouse_pos.x < EDGE_PAN_MARGIN:
		move_dir.x -= 1
	elif mouse_pos.x > screen_size.x - EDGE_PAN_MARGIN:
		move_dir.x += 1
	if mouse_pos.y < EDGE_PAN_MARGIN:
		move_dir.z -= 1
	elif mouse_pos.y > screen_size.y - EDGE_PAN_MARGIN:
		move_dir.z += 1

	# Apply camera panning to look-at target (rotated by faction camera angle)
	if move_dir != Vector3.ZERO:
		move_dir = move_dir.normalized()
		# Rotate movement direction to match camera orientation
		var rotated_dir := move_dir.rotated(Vector3.UP, _camera_faction_rotation)
		_camera_look_at.x += rotated_dir.x * CAMERA_PAN_SPEED * delta
		_camera_look_at.z += rotated_dir.z * CAMERA_PAN_SPEED * delta
		_camera_look_at.x = clampf(_camera_look_at.x, -CAMERA_BOUNDS, CAMERA_BOUNDS)
		_camera_look_at.z = clampf(_camera_look_at.z, -CAMERA_BOUNDS, CAMERA_BOUNDS)

	# Keyboard zoom (continuous while held)
	if Input.is_key_pressed(KEY_Z):
		_target_camera_height -= CAMERA_ZOOM_STEP * 2.0 * delta
	if Input.is_key_pressed(KEY_X):
		_target_camera_height += CAMERA_ZOOM_STEP * 2.0 * delta
	_target_camera_height = clampf(_target_camera_height, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT)

	# Update camera follow mode (overrides manual position)
	_update_camera_follow()

	# Smooth camera position update
	_update_camera_smooth(delta)


func _update_camera_smooth(delta: float) -> void:
	# Handle smooth minimap pan
	if _minimap_smooth_pan:
		var diff := _minimap_drag_target - _camera_look_at
		if diff.length() < 1.0:
			# Close enough, snap to target
			_camera_look_at = _minimap_drag_target
			_minimap_smooth_pan = false
		else:
			# Smoothly pan towards target
			_camera_look_at = _camera_look_at.lerp(_minimap_drag_target, MINIMAP_PAN_SPEED * delta)

	# Smoothly interpolate zoom height
	_current_camera_height = lerpf(_current_camera_height, _target_camera_height, CAMERA_ZOOM_SMOOTH * delta)

	# Position camera above and behind the look-at point (top-down RTS style)
	# Offset is rotated based on player faction so their base is at screen bottom
	var back_offset := Vector3(0, 0, _current_camera_height * 0.5).rotated(Vector3.UP, _camera_faction_rotation)
	var target_pos := Vector3(
		_camera_look_at.x + back_offset.x,
		_current_camera_height,
		_camera_look_at.z + back_offset.z
	)

	# Apply screen shake
	if _screen_shake_intensity > 0.01:
		var shake_offset := Vector3(
			randf_range(-1, 1) * _screen_shake_intensity * SCREEN_SHAKE_MAX,
			randf_range(-0.5, 0.5) * _screen_shake_intensity * SCREEN_SHAKE_MAX,
			randf_range(-1, 1) * _screen_shake_intensity * SCREEN_SHAKE_MAX
		)
		target_pos += shake_offset
		_screen_shake_intensity = lerpf(_screen_shake_intensity, 0.0, _screen_shake_decay * delta)

	# Smooth interpolation for buttery movement
	camera.global_position = camera.global_position.lerp(target_pos, CAMERA_SMOOTH_SPEED * delta)

	# Set camera rotation based on faction (player base at bottom of screen)
	# -60° down angle (PI/3), rotated around Y by faction angle
	camera.rotation = Vector3(-PI / 3, _camera_faction_rotation, 0)

	# Update building health bar visibility based on zoom
	if _city_renderer != null:
		_city_renderer.update_camera_height(_current_camera_height)


## Trigger screen shake effect.
func _trigger_screen_shake(intensity: float = 0.5) -> void:
	_screen_shake_intensity = maxf(_screen_shake_intensity, clampf(intensity, 0.0, 1.0))


## Jump camera to nearest combat (where enemies are near player units).
func _jump_to_combat() -> void:
	var best_combat_pos := Vector3.ZERO
	var best_score := 0.0

	# Find player units that are near enemies (in combat)
	for player_unit in _units:
		if player_unit.is_dead or player_unit.faction_id != _player_faction:
			continue
		if not is_instance_valid(player_unit.mesh):
			continue

		var player_pos: Vector3 = player_unit.mesh.position
		var nearby_enemies := 0

		# Count nearby enemies
		for enemy_unit in _units:
			if enemy_unit.is_dead or enemy_unit.faction_id == _player_faction:
				continue
			if not is_instance_valid(enemy_unit.mesh):
				continue

			var dist: float = player_pos.distance_to(enemy_unit.mesh.position)
			if dist < ATTACK_RANGE * 2.0:
				nearby_enemies += 1

		# Score based on enemy count and distance from current view
		if nearby_enemies > 0:
			var dist_from_camera: float = player_pos.distance_to(_camera_look_at)
			var score: float = nearby_enemies * 10.0 + dist_from_camera * 0.1
			if score > best_score:
				best_score = score
				best_combat_pos = player_pos

	if best_score > 0:
		_camera_look_at = Vector3(best_combat_pos.x, 0, best_combat_pos.z)
		_camera_look_at.x = clampf(_camera_look_at.x, -CAMERA_BOUNDS, CAMERA_BOUNDS)
		_camera_look_at.z = clampf(_camera_look_at.z, -CAMERA_BOUNDS, CAMERA_BOUNDS)
		print("Camera jumped to combat!")
	else:
		print("No active combat found")


func _zoom_camera(amount: float) -> void:
	# Adjust target height (will smoothly interpolate in update)
	_target_camera_height += amount
	_target_camera_height = clampf(_target_camera_height, CAMERA_MIN_HEIGHT, CAMERA_MAX_HEIGHT)


## Start camera shake effect.
func _camera_shake(duration: float, intensity: float) -> void:
	_camera_shake_duration = duration
	_camera_shake_intensity = intensity


## Update camera shake effect (call from _process).
func _update_camera_shake(delta: float) -> void:
	if _camera_shake_duration > 0:
		_camera_shake_duration -= delta

		# Generate random offset based on intensity
		var shake_amount := _camera_shake_intensity * (_camera_shake_duration / 0.5)  # Fade out
		_camera_shake_offset = Vector3(
			randf_range(-shake_amount, shake_amount),
			randf_range(-shake_amount * 0.5, shake_amount * 0.5),
			randf_range(-shake_amount, shake_amount)
		)

		# Apply to camera
		if camera:
			camera.position += _camera_shake_offset
	else:
		_camera_shake_offset = Vector3.ZERO


func _handle_production_input() -> void:
	# Check if player factory exists and isn't destroyed
	if not _factories.has(_player_faction) or _factories[_player_faction].is_destroyed:
		return

	# Number keys 1-3 queue units
	if Input.is_action_just_pressed("ui_focus_next"):  # Tab - cancel production
		if not _production_queue.is_empty():
			var cancelled: Dictionary = _production_queue.pop_back()
			# Refund 50% of cost
			var refund: float = PRODUCTION_COSTS.get(cancelled.unit_class, 0) * 0.5
			if ResourceManager:
				ResourceManager.add_ree(_player_faction, refund, "production_refund")
			print("Production cancelled, refunded %.0f REE" % refund)


func _queue_unit_production(unit_class: String) -> bool:
	# Check if player factory exists
	if not _factories.has(_player_faction) or _factories[_player_faction].is_destroyed:
		return false

	# Check cost
	var cost: float = PRODUCTION_COSTS.get(unit_class, 999999.0)
	var current_ree: float = 0.0
	if ResourceManager:
		current_ree = ResourceManager.get_current_ree(_player_faction)

	if current_ree < cost:
		print("Not enough REE! Need %.0f, have %.0f" % [cost, current_ree])
		_play_ui_sound("error")
		return false

	# Deduct cost
	if ResourceManager:
		ResourceManager.consume_ree(_player_faction, cost, "production")
		_track_stat(_player_faction, "ree_spent", cost)

	# Add to queue
	var build_time: float = PRODUCTION_TIMES.get(unit_class, 5.0)
	_production_queue.append({
		"unit_class": unit_class,
		"progress": 0.0,
		"total_time": build_time
	})

	# Play production start sound
	_play_production_start_sound()

	print("Queued %s unit (%.0f REE, %.1fs)" % [unit_class, cost, build_time])
	return true


func _update_production(delta: float) -> void:
	# Check if player factory exists
	if not _factories.has(_player_faction) or _factories[_player_faction].is_destroyed:
		_production_queue.clear()
		_current_production.clear()
		return

	# Check power status - production halted during blackout
	var factory: Dictionary = _factories[_player_faction]
	var power_mult: float = factory.get("power_multiplier", 1.0)
	var is_powered: bool = factory.get("is_powered", true)

	# Start new production if nothing in progress
	if _current_production.is_empty() and not _production_queue.is_empty():
		_current_production = _production_queue.pop_front()

	# Process current production
	if not _current_production.is_empty():
		# Check if production is halted due to blackout
		if not is_powered:
			# Production completely halted - no progress
			return

		# Apply factory upgrade speed bonus AND power multiplier
		var speed_mult: float = _get_factory_production_multiplier(1) * power_mult
		_current_production.progress += delta * speed_mult

		if _current_production.progress >= _current_production.total_time:
			# Production complete - spawn unit with factory bonuses
			var unit_class: String = _current_production.unit_class
			var factory_pos: Vector3 = FACTORY_POSITIONS[_player_faction]
			var spawn_pos: Vector3 = factory_pos + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))
			var new_unit: Dictionary = _spawn_faction_unit(_player_faction, spawn_pos, unit_class)

			# Apply factory upgrade bonuses to new unit
			var health_mult: float = _get_factory_health_multiplier(_player_faction)
			var damage_mult: float = _get_factory_damage_multiplier(_player_faction)
			new_unit.max_health *= health_mult
			new_unit.health = new_unit.max_health
			new_unit.damage = new_unit.get("damage", 10.0) * damage_mult

			# Send unit to rally point if set
			var rally_point: Vector3 = _get_rally_point(_player_faction)
			if rally_point != Vector3.ZERO:
				new_unit.target_pos = rally_point

			print("Produced %s unit!" % unit_class)

			# Play production complete sound + unit ready acknowledgment
			_play_production_complete_sound()
			_play_unit_ready_sound()

			# Spawn factory production effect
			_spawn_factory_production_effect(factory_pos, _player_faction)

			# Start unit ejection animation from factory to spawn position
			if _unit_ejection_animation != null and new_unit.has("mesh") and is_instance_valid(new_unit.mesh):
				var ejection_id: int = _unit_ejection_animation.start_ejection(
					new_unit.mesh,
					factory_pos,
					spawn_pos,
					_player_faction,
					_effects_container
				)
				if ejection_id >= 0:
					_pending_ejections[ejection_id] = new_unit

			_current_production.clear()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		# Handle ESC - close overlays first, then pause
		if event.keycode == KEY_ESCAPE:
			# Cancel factory placement mode if active
			if _construction_placement_mode:
				cancel_factory_placement()
				return
			# Close unit spec popup if open
			if _unit_spec_visible:
				_hide_unit_spec_popup()
				return
			# Close faction info viewer if open
			if _faction_info_visible:
				_hide_faction_info()
				return
			# Close tutorial overlay if open
			if _tutorial_overlay_visible:
				_tutorial_overlay_visible = false
				if _tutorial_overlay:
					_tutorial_overlay.visible = false
				return
			# Otherwise toggle pause
			_toggle_pause()
			return

		# When paused, only allow Q to quit or ESC/P to unpause
		if _is_game_paused:
			if event.keycode == KEY_Q:
				get_tree().quit()
			return

		match event.keycode:
			KEY_P:
				_toggle_pause()
			KEY_SPACE:
				if GameStateManager.get_match_status() == GameStateManager.MatchStatus.NOT_STARTED:
					if not _tutorial_overlay_visible and not _faction_info_visible:
						_start_match()
				elif GameStateManager.get_match_status() == GameStateManager.MatchStatus.ACTIVE:
					_jump_to_combat()
			KEY_I:
				# Show faction info viewer during faction selection
				if GameStateManager.get_match_status() == GameStateManager.MatchStatus.NOT_STARTED:
					_toggle_faction_info()
			KEY_F2:
				# Tutorial available during faction selection or when paused
				if GameStateManager.get_match_status() == GameStateManager.MatchStatus.NOT_STARTED or _is_game_paused:
					_toggle_tutorial_overlay()
				else:
					# During gameplay, F2 is still formation
					_set_formation(Formation.WEDGE)
			KEY_U:
				_spawn_player_reinforcements()
			KEY_E:
				_activate_phase_shift()
			KEY_Q:
				_activate_overclock()
			KEY_F:
				_toggle_siege_formation()
			KEY_C:
				_activate_ether_cloak()
			KEY_B:
				_activate_acrobatic_strike()
			KEY_V:
				_activate_coordinated_barrage()
			KEY_N:
				# N = New factory (enter placement mode)
				if GameStateManager.get_match_status() == GameStateManager.MatchStatus.ACTIVE:
					start_factory_placement()
			# Control group keys (Ctrl+# to save, # to recall)
			# Production only works with Shift+# when factory is selected
			KEY_1:
				if event.ctrl_pressed:
					_save_control_group(1)
				elif event.shift_pressed and _factory_selected:
					_queue_unit_production("light")  # Shift+1 produces (factory must be selected)
				elif _has_control_group(1):
					_recall_control_group(1)
			KEY_2:
				if event.ctrl_pressed:
					_save_control_group(2)
				elif event.shift_pressed and _factory_selected:
					_queue_unit_production("medium")  # Shift+2 produces (factory must be selected)
				elif _has_control_group(2):
					_recall_control_group(2)
			KEY_3:
				if event.ctrl_pressed:
					_save_control_group(3)
				elif event.shift_pressed and _factory_selected:
					_queue_unit_production("heavy")  # Shift+3 produces (factory must be selected)
				elif _has_control_group(3):
					_recall_control_group(3)
			KEY_4:
				if event.ctrl_pressed:
					_save_control_group(4)
				elif event.shift_pressed and _factory_selected:
					_queue_unit_production("harvester")  # Shift+4 produces (factory must be selected)
				elif _has_control_group(4):
					_recall_control_group(4)
			KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				var group_num: int = event.keycode - KEY_0
				if event.ctrl_pressed:
					_save_control_group(group_num)
				else:
					_recall_control_group(group_num)
			# Unit commands
			KEY_A:
				if event.ctrl_pressed:
					_select_all_player_units()
				else:
					_attack_move_mode = true
					print("Attack-move mode: Click to attack-move")
			KEY_S:
				_stop_selected_units()
			KEY_H:
				_toggle_help_overlay()
			KEY_SLASH:  # ? key (Shift+/)
				if event.shift_pressed:
					_toggle_help_overlay()
			KEY_R:
				_set_rally_point_mode()
			KEY_P:
				if event.ctrl_pressed:
					_toggle_power_grid_overlay()
				else:
					_start_patrol_mode()
			KEY_G:
				_start_guard_mode()
			KEY_Z:
				_cycle_unit_stance()
			# Formation controls (F2 handled above with tutorial logic)
			KEY_F1:
				_set_formation(Formation.LINE)
			KEY_F3:
				_set_formation(Formation.BOX)
			KEY_F4:
				_set_formation(Formation.SCATTER)
			KEY_F5:
				_toggle_camera_follow()
			# Quicksave/Quickload
			KEY_F8:
				if event.ctrl_pressed:
					_perform_quickload()
				else:
					_perform_quicksave()
			# Camera bookmarks (F9-F12)
			KEY_F9, KEY_F10, KEY_F11, KEY_F12:
				var slot: int = event.keycode - KEY_F9 + 9
				if event.ctrl_pressed:
					_save_camera_bookmark(slot)
				else:
					_recall_camera_bookmark(slot)
			# Factory upgrade
			KEY_T:
				_upgrade_player_factory()
			# Auto-attack toggle
			KEY_Y:
				_toggle_auto_attack()
			# Idle unit cycling
			KEY_TAB:
				_cycle_idle_units()
			# Game speed controls
			KEY_EQUAL, KEY_KP_ADD:  # + key
				_change_game_speed(GAME_SPEED_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:  # - key
				_change_game_speed(-GAME_SPEED_STEP)
			# Tutorial page navigation (arrow keys / A/D when overlay visible)
			KEY_LEFT, KEY_A:
				if _tutorial_overlay_visible:
					_tutorial_prev_page()
			KEY_RIGHT, KEY_D:
				if _tutorial_overlay_visible:
					_tutorial_next_page()

	# Track shift key for command queuing
	if event is InputEventKey:
		if event.keycode == KEY_SHIFT:
			_command_queue_mode = event.pressed
		elif event.keycode == KEY_ALT:
			_show_range_circles = event.pressed

	if event is InputEventMouseButton:
		# Handle factory placement mode first
		if _construction_placement_mode:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				_confirm_factory_placement()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				cancel_factory_placement()
				return

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_camera(-CAMERA_ZOOM_STEP)  # Zoom in (reduce height)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_camera(CAMERA_ZOOM_STEP)  # Zoom out (increase height)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Start potential box selection
				_is_box_selecting = true
				_box_select_start = event.position
				_box_select_end = event.position
			else:
				# Left mouse released
				if _is_box_selecting:
					var drag_distance := _box_select_start.distance_to(_box_select_end)
					if drag_distance >= BOX_SELECT_THRESHOLD:
						# Finish box selection
						_finish_box_selection()
					else:
						# Click selection (not a drag) - with double-click detection
						_handle_left_click_with_double(_box_select_start)
					_is_box_selecting = false
					_hide_selection_box()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				# Right mouse pressed - start potential drag formation
				if _is_box_selecting:
					_is_box_selecting = false
					_hide_selection_box()
				elif _attack_move_mode or _rally_point_mode or _patrol_mode or _guard_mode:
					# Handle special modes immediately
					if _attack_move_mode:
						_handle_attack_move_click(event.position)
						_attack_move_mode = false
					elif _rally_point_mode:
						_set_rally_point(event.position)
						_rally_point_mode = false
					elif _patrol_mode:
						_add_patrol_waypoint(event.position)
					elif _guard_mode:
						_handle_guard_click(event.position)
						_guard_mode = false
				else:
					# Start drag formation tracking
					_is_drag_forming = true
					_drag_form_start = event.position
					_drag_form_end = event.position
					_drag_form_world_start = _screen_to_world(event.position)
			else:
				# Right mouse released - finish drag or click
				if _is_drag_forming:
					var drag_distance := _drag_form_start.distance_to(_drag_form_end)
					if drag_distance >= DRAG_FORM_THRESHOLD and _selected_units.size() > 0:
						# Execute drag formation move
						_execute_drag_formation()
					else:
						# Was just a click - do normal right-click action
						_handle_right_click(_drag_form_start)
					_is_drag_forming = false
					_clear_drag_formation_preview()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Cancel command modes on left click
			if _attack_move_mode:
				_attack_move_mode = false
			if _patrol_mode:
				_finish_patrol_mode()
			if _guard_mode:
				_guard_mode = false
				print("Guard mode cancelled")

	# Update box selection while dragging
	if event is InputEventMouseMotion and _is_box_selecting:
		_box_select_end = event.position
		_update_selection_box_visual()

	# Update factory placement preview
	if event is InputEventMouseMotion and _construction_placement_mode:
		_update_factory_placement(event.position)

	# Update drag formation preview
	if event is InputEventMouseMotion and _is_drag_forming:
		_drag_form_end = event.position
		_update_drag_formation_preview()


func _start_match() -> void:
	print("Starting match...")
	print("Player faction: %d (%s)" % [_player_faction, FACTION_INFO.get(_player_faction, {}).get("name", "Unknown")])

	# Play match start sound and start ambient music
	_play_ui_sound("notification")
	if _audio_manager and _audio_manager.get_music_manager():
		_audio_manager.get_music_manager().resume_ambient()

	# Hide faction selection screen
	if _faction_select_panel:
		_faction_select_panel.visible = false
		_faction_select_visible = false

	GameStateManager.start_match(_player_faction, 1)
	_apply_faction_ui_theme(_player_faction)  # Apply faction-specific UI colors
	_setup_city()
	_setup_fog_of_war()
	_setup_factories()
	_spawn_initial_units()
	_initialize_faction_ai()
	_setup_faction_camera(_player_faction)  # Position camera for selected faction
	_update_minimap_rotation()  # Rotate minimap to match player's view
	_match_time = 0.0


## Apply faction-specific UI theme colors to all major UI elements.
func _apply_faction_ui_theme(faction_id: int) -> void:
	var theme: Dictionary = FACTION_UI_THEMES.get(faction_id, FACTION_UI_THEMES[1])
	var accent: Color = theme.get("accent", Color.WHITE)
	var highlight: Color = theme.get("highlight", Color.WHITE)
	var bg_tint: Color = theme.get("bg_tint", Color(0.1, 0.1, 0.1))
	var border: Color = theme.get("border", Color.GRAY)
	var text: Color = theme.get("text", Color.WHITE)

	print("Applying faction %d UI theme..." % faction_id)

	# Resource panel theming
	var resource_panel: PanelContainer = get_node_or_null("UI/ResourcePanel")
	if resource_panel:
		var style := StyleBoxFlat.new()
		style.bg_color = bg_tint.lightened(0.05)
		style.bg_color.a = 0.9
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		resource_panel.add_theme_stylebox_override("panel", style)

		# Update text colors in resource panel
		for child in resource_panel.get_node_or_null("HBoxContainer").get_children():
			if child is Label:
				child.add_theme_color_override("font_color", text)

	# Production progress bar theming
	if _production_progress_bar:
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = accent
		fill_style.set_corner_radius_all(3)
		_production_progress_bar.add_theme_stylebox_override("fill", fill_style)

		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = bg_tint.lightened(0.1)
		bg_style.set_corner_radius_all(3)
		_production_progress_bar.add_theme_stylebox_override("background", bg_style)

	# Portrait panel theming
	if _portrait_panel:
		var style := StyleBoxFlat.new()
		style.bg_color = bg_tint.lightened(0.02)
		style.bg_color.a = 0.92
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		_portrait_panel.add_theme_stylebox_override("panel", style)

	# Minimap container theming
	var minimap_container: PanelContainer = get_node_or_null("UI/MinimapContainer")
	if minimap_container:
		var style := StyleBoxFlat.new()
		style.bg_color = bg_tint
		style.bg_color.a = 0.95
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		minimap_container.add_theme_stylebox_override("panel", style)

	# Factory status panel theming
	if _factory_status_panel:
		var style := StyleBoxFlat.new()
		style.bg_color = bg_tint.lightened(0.03)
		style.bg_color.a = 0.9
		style.border_color = border
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		_factory_status_panel.add_theme_stylebox_override("panel", style)

	# Kill feed theming
	if _kill_feed_container:
		for child in _kill_feed_container.get_children():
			if child is Label:
				child.add_theme_color_override("font_shadow_color", bg_tint)

	# Selection count label theming
	if _selection_count_label:
		_selection_count_label.add_theme_color_override("font_color", text)
		_selection_count_label.add_theme_color_override("font_shadow_color", bg_tint)

	# Match timer theming
	var match_timer_label: Label = get_node_or_null("UI/MatchTimerLabel")
	if match_timer_label == null:
		# Try to find it another way
		for i in range(10):
			var check: Node = get_node_or_null("UI")
			if check:
				for child in check.get_children():
					if child.name == "MatchTimerLabel" and child is Label:
						match_timer_label = child
						break
	if match_timer_label:
		match_timer_label.add_theme_color_override("font_color", text)

	# Game speed label theming
	var game_speed_label: Label = get_node_or_null("UI/GameSpeedLabel")
	if game_speed_label:
		game_speed_label.add_theme_color_override("font_color", accent)

	print("  Theme applied: accent=%s, bg_tint=%s" % [accent, bg_tint])


## Initialize AI factions with starting resources and timers.
func _initialize_faction_ai() -> void:
	var ai_count := 0
	for faction_id in [1, 2, 3, 4]:  # All possible factions
		if faction_id == _player_faction:
			continue  # Skip player's faction

		# Give AI factions starting REE
		if ResourceManager:
			ResourceManager.add_ree(faction_id, AI_STARTING_REE, "ai_starting")
		# Initialize spawn timers
		_ai_spawn_timers[faction_id] = 0.0
		# Initialize aggression levels (varies by faction)
		match faction_id:
			1:  # Aether Swarm - sneaky, moderate aggression
				_ai_aggression[faction_id] = 0.4
			2:  # OptiForge - aggressive swarm
				_ai_aggression[faction_id] = 0.6
			3:  # Dynapods - most aggressive
				_ai_aggression[faction_id] = 0.7
			4:  # LogiBots - defensive, methodical
				_ai_aggression[faction_id] = 0.3
		ai_count += 1
	print("Initialized AI for %d factions" % ai_count)


func _setup_city() -> void:
	print("Generating procedural city...")

	# Create outer grass plane (larger area outside city)
	var grass_size := MAP_SIZE + 400.0  # Extra area around the city
	var grass := CSGBox3D.new()
	grass.name = "GrassGround"
	grass.size = Vector3(grass_size, 0.3, grass_size)
	grass.position = Vector3(0, -0.35, 0)  # Slightly below city ground
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.15, 0.35, 0.12)  # Green grass
	grass_mat.roughness = 0.9
	grass.material = grass_mat
	add_child(grass)

	# Create city ground plane (dark asphalt)
	var ground := CSGBox3D.new()
	ground.name = "CityGround"
	ground.size = Vector3(MAP_SIZE, 0.5, MAP_SIZE)
	ground.position = Vector3(0, -0.25, 0)
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.1, 0.1, 0.12)  # Dark asphalt
	ground_mat.roughness = 0.95
	ground.material = ground_mat
	add_child(ground)

	# Add trees and foliage around the city perimeter
	_create_perimeter_vegetation()

	# Create city renderer if needed
	if _city_renderer == null:
		_city_renderer = CityRenderer.new()
		_city_renderer.name = "CityRenderer"
		add_child(_city_renderer)

		# Connect building destruction signals
		_city_renderer.building_destroyed.connect(_on_building_destroyed)
		_city_renderer.building_damaged.connect(_on_building_damaged)

	# Generate city within MAP_SIZE bounds (centered at origin)
	var city_size := int(MAP_SIZE)
	var city_offset := Vector3(-MAP_SIZE / 2.0, 0, -MAP_SIZE / 2.0)

	# Use WFC-based procedural city generation for realistic layouts
	# Each faction corner gets themed zones (swarm alleys, tank boulevards, etc.)
	var city_seed: int = Time.get_ticks_msec()  # Use time for variety, or set fixed for testing
	_city_renderer.render_wfc_city(city_size, city_offset, city_seed)

	print("City generation complete: %d buildings (WFC procedural)" % _city_renderer.get_building_count())


## Create trees and grass patches around the city perimeter.
func _create_perimeter_vegetation() -> void:
	var vegetation_container := Node3D.new()
	vegetation_container.name = "Vegetation"
	add_child(vegetation_container)

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345  # Fixed seed for consistent placement

	var city_edge := MAP_SIZE / 2.0
	var outer_edge := city_edge + 180.0

	# Create trees around all 4 sides
	for side in 4:
		var tree_count := 40 + rng.randi() % 20

		for i in range(tree_count):
			# Position along the edge
			var along_edge: float = rng.randf_range(-outer_edge, outer_edge)
			var from_edge: float = rng.randf_range(city_edge + 15, outer_edge - 10)

			var pos: Vector3
			match side:
				0:  # North edge (-Z)
					pos = Vector3(along_edge, 0, -from_edge)
				1:  # South edge (+Z)
					pos = Vector3(along_edge, 0, from_edge)
				2:  # East edge (+X)
					pos = Vector3(from_edge, 0, along_edge)
				3:  # West edge (-X)
					pos = Vector3(-from_edge, 0, along_edge)

			# Create tree
			var tree := _create_procedural_tree(rng)
			tree.position = pos
			tree.rotation.y = rng.randf() * TAU
			vegetation_container.add_child(tree)

	# Add grass tufts in the corners (where camera starts)
	for corner in 4:
		var corner_x: float = city_edge + 80 if corner % 2 == 0 else -(city_edge + 80)
		var corner_z: float = city_edge + 80 if corner < 2 else -(city_edge + 80)

		for i in range(25):
			var offset := Vector3(rng.randf_range(-60, 60), 0, rng.randf_range(-60, 60))
			var pos := Vector3(corner_x, 0, corner_z) + offset

			var grass_tuft := _create_grass_tuft(rng)
			grass_tuft.position = pos
			vegetation_container.add_child(grass_tuft)

	print("Created perimeter vegetation")


## Create a simple procedural tree.
func _create_procedural_tree(rng: RandomNumberGenerator) -> Node3D:
	var tree := Node3D.new()

	# Tree trunk (brown cylinder)
	var trunk := CSGCylinder3D.new()
	var trunk_height: float = rng.randf_range(8, 18)
	var trunk_radius: float = rng.randf_range(0.8, 1.5)
	trunk.radius = trunk_radius
	trunk.height = trunk_height
	trunk.position.y = trunk_height / 2.0
	trunk.sides = 8

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.35, 0.22, 0.1)  # Brown bark
	trunk_mat.roughness = 0.95
	trunk.material = trunk_mat
	tree.add_child(trunk)

	# Foliage (green sphere or cone)
	var use_cone: bool = rng.randf() > 0.4  # 60% conifers
	var foliage: CSGShape3D

	if use_cone:
		# Conifer (pine tree)
		var cone := CSGCylinder3D.new()
		cone.radius = rng.randf_range(4, 7)
		cone.height = rng.randf_range(12, 20)
		cone.cone = true
		cone.sides = 8
		foliage = cone
	else:
		# Deciduous (round tree)
		var sphere := CSGSphere3D.new()
		sphere.radius = rng.randf_range(5, 9)
		sphere.rings = 8
		sphere.radial_segments = 12
		foliage = sphere

	foliage.position.y = trunk_height + (foliage.get("height") if foliage.get("height") else foliage.get("radius") * 0.7)

	var foliage_mat := StandardMaterial3D.new()
	var green_var: float = rng.randf_range(-0.1, 0.1)
	foliage_mat.albedo_color = Color(0.15 + green_var, 0.4 + green_var, 0.12 + green_var * 0.5)
	foliage_mat.roughness = 0.85
	foliage.material = foliage_mat
	tree.add_child(foliage)

	return tree


## Create a grass tuft decoration.
func _create_grass_tuft(rng: RandomNumberGenerator) -> Node3D:
	var tuft := Node3D.new()

	# Create several grass blades
	var blade_count := rng.randi_range(3, 6)
	for i in range(blade_count):
		var blade := CSGBox3D.new()
		blade.size = Vector3(0.15, rng.randf_range(1.5, 3.0), 0.05)
		blade.position = Vector3(rng.randf_range(-0.5, 0.5), blade.size.y / 2, rng.randf_range(-0.5, 0.5))
		blade.rotation.x = rng.randf_range(-0.2, 0.2)
		blade.rotation.z = rng.randf_range(-0.3, 0.3)

		var blade_mat := StandardMaterial3D.new()
		blade_mat.albedo_color = Color(0.2, 0.5 + rng.randf_range(-0.1, 0.1), 0.15)
		blade_mat.roughness = 0.9
		blade.material = blade_mat
		tuft.add_child(blade)

	return tuft


## Setup fog of war overlay plane with shader.
func _setup_fog_of_war() -> void:
	# Create a plane mesh that covers the entire map
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(MAP_SIZE + 100, MAP_SIZE + 100)

	_fog_plane = MeshInstance3D.new()
	_fog_plane.name = "FogOfWar"
	_fog_plane.mesh = mesh
	_fog_plane.position = Vector3(0, 2, 0)  # Just above the ground

	# Create shader for fog of war (enhanced version with noise and edge glow)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;

uniform vec4 fog_color : source_color = vec4(0.02, 0.02, 0.04, 0.85);
uniform vec4 edge_glow_color : source_color = vec4(0.2, 0.5, 0.8, 0.6);
uniform vec4 shroud_color : source_color = vec4(0.03, 0.03, 0.06, 0.65);
uniform float vision_radius = 40.0;
uniform float explore_radius = 60.0;
uniform vec3 unit_positions[32];  // Up to 32 player units
uniform int unit_count = 0;
uniform vec2 explored_positions[64];  // Previously explored areas
uniform int explored_count = 0;
uniform float time_offset = 0.0;  // For animation

varying vec3 world_pos;

// Simple noise function for organic look
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);  // Smoothstep

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float visibility = 1.0;  // 1.0 = fully fogged, 0.0 = clear
	float edge_intensity = 0.0;  // For edge glow effect
	bool in_shroud = false;

	// Add subtle animated noise to fog
	vec2 noise_coord = world_pos.xz * 0.02 + vec2(time_offset * 0.1, time_offset * 0.07);
	float fog_noise = fbm(noise_coord) * 0.15;

	// Check distance from each player unit (current vision)
	for (int i = 0; i < unit_count; i++) {
		if (i >= 32) break;
		float dist = distance(world_pos.xz, unit_positions[i].xz);
		if (dist < vision_radius) {
			// Smooth fade at edge of vision with noise variation
			float edge_noise = noise(world_pos.xz * 0.1 + vec2(time_offset * 0.2)) * 0.15;
			float adjusted_radius = vision_radius * (1.0 + edge_noise);
			float fade = smoothstep(adjusted_radius * 0.4, adjusted_radius, dist);
			visibility = min(visibility, fade);

			// Calculate edge glow intensity
			float edge_dist = abs(dist - vision_radius * 0.7);
			if (edge_dist < vision_radius * 0.3) {
				float glow = 1.0 - (edge_dist / (vision_radius * 0.3));
				glow *= glow;  // Sharper falloff
				edge_intensity = max(edge_intensity, glow * 0.5);
			}
		}
	}

	// Check explored areas (partial visibility - shroud)
	for (int i = 0; i < explored_count; i++) {
		if (i >= 64) break;
		float dist = distance(world_pos.xz, explored_positions[i]);
		if (dist < explore_radius) {
			// Explored areas are partially visible (shroud)
			float fade = smoothstep(explore_radius * 0.3, explore_radius, dist);
			float shroud_level = 0.45 + fog_noise;  // Animated shroud
			float new_vis = max(fade, shroud_level);
			if (new_vis < visibility) {
				visibility = new_vis;
				if (new_vis > 0.3) {
					in_shroud = true;
				}
			}
		}
	}

	// Mix fog and shroud colors based on state
	vec3 final_color;
	if (in_shroud && visibility > 0.3) {
		// Shroud area - slightly different color
		final_color = mix(fog_color.rgb, shroud_color.rgb, 0.5);
	} else {
		final_color = fog_color.rgb;
	}

	// Add subtle color variation based on noise
	final_color += vec3(fog_noise * 0.5, fog_noise * 0.3, fog_noise * 0.8) * 0.1;

	// Add edge glow effect
	if (edge_intensity > 0.0) {
		final_color = mix(final_color, edge_glow_color.rgb, edge_intensity);
	}

	// Apply final color with calculated visibility
	ALBEDO = final_color;
	ALPHA = fog_color.a * visibility * (1.0 + fog_noise * 0.2);
}
"""

	_fog_material = ShaderMaterial.new()
	_fog_material.shader = shader
	_fog_material.set_shader_parameter("fog_color", Color(0.02, 0.02, 0.04, 0.85))
	_fog_material.set_shader_parameter("edge_glow_color", Color(0.2, 0.5, 0.8, 0.6))
	_fog_material.set_shader_parameter("shroud_color", Color(0.03, 0.03, 0.06, 0.65))
	_fog_material.set_shader_parameter("vision_radius", FOG_VISION_RADIUS)
	_fog_material.set_shader_parameter("explore_radius", FOG_EXPLORE_RADIUS)
	_fog_material.set_shader_parameter("unit_count", 0)
	_fog_material.set_shader_parameter("explored_count", 0)
	_fog_material.set_shader_parameter("time_offset", 0.0)

	_fog_plane.material_override = _fog_material
	_fog_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	add_child(_fog_plane)
	print("Fog of war initialized")


## Update fog of war based on player unit positions.
func _update_fog_of_war() -> void:
	if _fog_material == null:
		return

	# Collect player unit positions
	var positions: PackedVector3Array = PackedVector3Array()
	for unit in _units:
		if unit.is_dead or unit.faction_id != _player_faction:
			continue
		if not is_instance_valid(unit.mesh):
			continue
		positions.append(unit.mesh.position)

		# Add to explored positions (with limit)
		var pos_2d := Vector2(unit.mesh.position.x, unit.mesh.position.z)
		var is_new := true
		for explored in _explored_positions:
			if pos_2d.distance_to(explored) < FOG_VISION_RADIUS * 0.5:
				is_new = false
				break
		if is_new:
			_explored_positions.append(pos_2d)
			# Keep explored positions limited
			if _explored_positions.size() > MAX_EXPLORED_POSITIONS:
				# Remove oldest positions
				_explored_positions = _explored_positions.slice(100)

	# Limit to shader maximum (32 units)
	if positions.size() > 32:
		positions = positions.slice(0, 32)

	# Update shader uniforms
	_fog_material.set_shader_parameter("unit_positions", positions)
	_fog_material.set_shader_parameter("unit_count", positions.size())

	# Update explored positions (limit to 64)
	var explored_for_shader := _explored_positions
	if explored_for_shader.size() > 64:
		explored_for_shader = explored_for_shader.slice(_explored_positions.size() - 64)
	_fog_material.set_shader_parameter("explored_positions", explored_for_shader)
	_fog_material.set_shader_parameter("explored_count", explored_for_shader.size())

	# Animate fog with time for organic movement
	var game_time: float = Time.get_ticks_msec() / 1000.0
	_fog_material.set_shader_parameter("time_offset", game_time)


func _setup_factories() -> void:
	# Get factory nodes from scene
	for faction_id in FACTORY_POSITIONS:
		var factory_name := "Factory%d" % faction_id
		var factory_node: Node3D = get_node_or_null(factory_name)

		if factory_node:
			# Create health bar for factory
			var health_bar := _create_factory_health_bar(faction_id)
			_health_bar_container.add_child(health_bar)

			# Create faction name label
			var name_label := _create_faction_name_label(faction_id)
			_effects_container.add_child(name_label)

			_factories[faction_id] = {
				"node": factory_node,
				"health_bar": health_bar,
				"name_label": name_label,
				"health": FACTORY_HEALTH,
				"max_health": FACTORY_HEALTH,
				"faction_id": faction_id,
				"is_destroyed": false,
				"position": FACTORY_POSITIONS[faction_id],
				"power_plant_id": -1,
				"district_id": -1,
				"is_powered": true,
				"power_multiplier": 1.0
			}

			# Register OptiForge factory with MassProduction for faster spawning
			if faction_id == 2 and _mass_production != null:
				_mass_production.register_factory(faction_id)

			# Setup power grid for this factory
			_setup_factory_power(faction_id)

	# Initialize factory construction system
	_factory_construction = FactoryConstruction.new()
	for faction_id in _factories:
		var factory: Dictionary = _factories[faction_id]
		_factory_construction.register_factory(factory.position, faction_id)
	_factory_construction.construction_started.connect(_on_construction_started)
	_factory_construction.construction_progress.connect(_on_construction_progress)
	_factory_construction.construction_completed.connect(_on_construction_completed)
	print("  FactoryConstruction: OK (builder-based factory building)")


func _create_factory_health_bar(faction_id: int) -> Node3D:
	var bar := Node3D.new()

	var bg := CSGBox3D.new()
	bg.size = Vector3(10.0, 0.5, 0.2)
	bg.position.y = 0.25
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.1, 0.1)
	bg.material = bg_mat
	bar.add_child(bg)

	var fg := CSGBox3D.new()
	fg.name = "Fill"
	fg.size = Vector3(10.0, 0.5, 0.2)
	fg.position.y = 0.25
	fg.position.z = 0.1
	var fg_mat := StandardMaterial3D.new()
	fg_mat.albedo_color = FACTION_COLORS.get(faction_id, Color.WHITE)
	fg_mat.emission_enabled = true
	fg_mat.emission = FACTION_COLORS.get(faction_id, Color.WHITE) * 0.3
	fg.material = fg_mat
	bar.add_child(fg)

	return bar


## Create faction name label for factory
func _create_faction_name_label(faction_id: int) -> Label3D:
	var label := Label3D.new()
	label.text = FACTION_NAMES.get(faction_id, "UNKNOWN")
	label.font_size = 128
	label.modulate = FACTION_COLORS.get(faction_id, Color.WHITE)
	label.outline_modulate = Color.BLACK
	label.outline_size = 16
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = FACTORY_POSITIONS[faction_id] + Vector3(0, 25, 0)
	return label


## Setup power grid components for a factory.
func _setup_factory_power(faction_id: int) -> void:
	if _power_grid_manager == null or _power_consumer_manager == null:
		return

	var factory: Dictionary = _factories[faction_id]
	var faction_str := str(faction_id)
	var factory_pos: Vector3 = factory.position

	# Create a district for this factory
	var district := _power_grid_manager.create_district(faction_str, FACTORY_POWER_DEMAND)
	factory.district_id = district.district_id

	# Create a power plant near the factory (fusion plant for reliable power)
	var plant_pos := factory_pos + Vector3(20, 0, 20)
	var power_plant := _power_grid_manager.create_fusion_plant(faction_str, plant_pos)
	factory.power_plant_id = power_plant.id

	# Connect power plant to district via power line
	_power_grid_manager.create_power_line(power_plant.id, district.district_id, POWER_PLANT_OUTPUT)

	# Register the factory as a power consumer
	var consumer := _power_consumer_manager.register_factory(faction_str, district.district_id, "Factory_%d" % faction_id)
	consumer.set_power_requirement(FACTORY_POWER_DEMAND)
	consumer.position = factory_pos
	_factory_power_consumers[faction_id] = consumer

	# Initialize power - factories start powered
	factory.is_powered = true
	factory.power_multiplier = 1.0

	# Initialize brownout system for this district
	_brownout_system.init_emergency_reserve(district.district_id)

	# Force initial power calculation
	_power_grid_manager.force_recalculation()

	print("  Factory %d: power plant (id=%d), district (id=%d), consumer registered" % [
		faction_id, power_plant.id, district.district_id
	])


## Update power grid state for all factories.
func _update_power_grid(delta: float) -> void:
	if _power_grid_manager == null or _brownout_system == null:
		return

	# Update power grid manager
	_power_grid_manager.update(delta)

	# Update brownout system (emergency power)
	_brownout_system.update_emergency_power(delta)

	# Update each factory's power state
	for faction_id in _factories:
		var factory: Dictionary = _factories[faction_id]
		if factory.is_destroyed:
			factory.is_powered = false
			factory.power_multiplier = 0.0
			continue

		var district_id: int = factory.district_id
		if district_id < 0:
			continue

		# Get power state from brownout system
		var district := _power_grid_manager.get_district(district_id)
		if district == null:
			continue

		# Calculate power ratio
		var generation := _power_grid_manager.get_faction_generation(str(faction_id))
		var demand := FACTORY_POWER_DEMAND

		# Update brownout system with current power levels
		var power_state: int = _brownout_system.update_district_power(district_id, generation, demand)

		# Get production multiplier based on power state
		var power_mult: float = _brownout_system.get_brownout_multiplier(district_id)
		factory.power_multiplier = power_mult

		# Determine if powered (any production at all)
		factory.is_powered = power_mult > 0.0

		# Update power consumer state
		if _factory_power_consumers.has(faction_id):
			var consumer: PowerConsumer = _factory_power_consumers[faction_id]
			var is_blackout: bool = _brownout_system.is_blackout(district_id)
			consumer.update_power_state(generation, is_blackout)


## Get power production multiplier for a factory.
func _get_factory_power_multiplier(faction_id: int) -> float:
	if not _factories.has(faction_id):
		return 1.0
	return _factories[faction_id].get("power_multiplier", 1.0)


## Check if a factory has power.
func _is_factory_powered(faction_id: int) -> bool:
	if not _factories.has(faction_id):
		return true
	return _factories[faction_id].get("is_powered", true)


## Damage a factory's power plant.
func _damage_factory_power_plant(faction_id: int, damage: float) -> void:
	if not _factories.has(faction_id) or _power_grid_manager == null:
		return

	var factory: Dictionary = _factories[faction_id]
	var plant_id: int = factory.get("power_plant_id", -1)
	if plant_id < 0:
		return

	var plant := _power_grid_manager.get_plant(plant_id)
	if plant != null:
		plant.apply_damage(damage)


## Setup the district capture grid.
func _setup_districts() -> void:
	_districts.clear()
	_district_visuals.clear()
	_district_labels.clear()

	# Create 5x5 grid of districts
	for y in range(DISTRICT_GRID_SIZE):
		for x in range(DISTRICT_GRID_SIZE):
			var district_id: int = y * DISTRICT_GRID_SIZE + x
			var center_x: float = DISTRICT_OFFSET + (x + 0.5) * DISTRICT_SIZE
			var center_z: float = DISTRICT_OFFSET + (y + 0.5) * DISTRICT_SIZE

			var district: Dictionary = {
				"id": district_id,
				"grid_x": x,
				"grid_y": y,
				"center": Vector3(center_x, 0, center_z),
				"owner": 0,  # 0 = neutral, 1-4 = faction
				"capture_progress": {},  # faction_id -> progress (0.0-1.0)
				"control_level": 0.0,
				"is_contested": false
			}

			# Assign starting districts to factions based on proximity to factories
			for faction_id in FACTORY_POSITIONS:
				var factory_pos: Vector3 = FACTORY_POSITIONS[faction_id]
				var dist: float = Vector2(center_x, center_z).distance_to(Vector2(factory_pos.x, factory_pos.z))
				if dist < DISTRICT_SIZE * 0.8:
					district.owner = faction_id
					district.control_level = 1.0
					break

			_districts.append(district)

			# Create visual indicator for district
			_create_district_visual(district)

	# Create territory ownership overlay (ground tinting)
	_district_overlay = DistrictOverlay.new()
	add_child(_district_overlay)
	# Sync initial ownership
	for district in _districts:
		var dx: int = district.grid_x
		var dz: int = district.grid_y
		_district_overlay.set_district_owner(dx, dz, district.owner)
	print("  DistrictOverlay: OK (territory ground tinting)")


## Create visual indicator for a district.
func _create_district_visual(district: Dictionary) -> void:
	var visual := Node3D.new()
	visual.name = "District_%d" % district.id

	# Create border lines for district
	var border_color: Color = _get_district_color(district.owner)
	var half_size: float = DISTRICT_SIZE / 2.0
	var center: Vector3 = district.center

	# Create 4 border edges as thin boxes
	var edge_height := 0.5
	var edge_thickness := 1.0

	# Top edge (north)
	var top_edge := CSGBox3D.new()
	top_edge.size = Vector3(DISTRICT_SIZE, edge_height, edge_thickness)
	top_edge.position = Vector3(0, edge_height / 2, -half_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = border_color
	mat.emission_enabled = true
	mat.emission = border_color * 0.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color.a = 0.6
	top_edge.material = mat
	visual.add_child(top_edge)

	# Bottom edge (south)
	var bottom_edge := CSGBox3D.new()
	bottom_edge.size = Vector3(DISTRICT_SIZE, edge_height, edge_thickness)
	bottom_edge.position = Vector3(0, edge_height / 2, half_size)
	bottom_edge.material = mat
	visual.add_child(bottom_edge)

	# Left edge (west)
	var left_edge := CSGBox3D.new()
	left_edge.size = Vector3(edge_thickness, edge_height, DISTRICT_SIZE)
	left_edge.position = Vector3(-half_size, edge_height / 2, 0)
	left_edge.material = mat
	visual.add_child(left_edge)

	# Right edge (east)
	var right_edge := CSGBox3D.new()
	right_edge.size = Vector3(edge_thickness, edge_height, DISTRICT_SIZE)
	right_edge.position = Vector3(half_size, edge_height / 2, 0)
	right_edge.material = mat
	visual.add_child(right_edge)

	visual.position = center
	_effects_container.add_child(visual)
	_district_visuals.append(visual)

	# Create label showing district status
	var label := Label3D.new()
	label.name = "DistrictLabel_%d" % district.id
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = center + Vector3(0, 8, 0)
	label.modulate = border_color
	_effects_container.add_child(label)
	_district_labels.append(label)


## Get color for district based on owner.
func _get_district_color(owner: int) -> Color:
	if owner == 0:
		return Color(0.5, 0.5, 0.5, 0.4)  # Gray for neutral
	return FACTION_COLORS.get(owner, Color.WHITE)


## Update district capture mechanics.
func _update_districts(delta: float) -> void:
	# Count units in each district per faction
	var district_units: Dictionary = {}  # district_id -> {faction_id -> count}

	for unit in _units:
		if unit.is_dead or not is_instance_valid(unit.mesh):
			continue
		var pos: Vector3 = unit.mesh.position
		var district_id: int = _get_district_at_position(pos)
		if district_id < 0:
			continue

		if not district_units.has(district_id):
			district_units[district_id] = {}
		var faction_id: int = unit.faction_id
		if not district_units[district_id].has(faction_id):
			district_units[district_id][faction_id] = 0
		district_units[district_id][faction_id] += 1

	# Update each district
	for district in _districts:
		var district_id: int = district.id
		var units_here: Dictionary = district_units.get(district_id, {})

		# Update contested status
		district.is_contested = units_here.size() > 1

		# Find dominant faction
		var dominant_faction := 0
		var dominant_count := 0
		for faction_id in units_here:
			if units_here[faction_id] > dominant_count:
				dominant_count = units_here[faction_id]
				dominant_faction = faction_id

		var owner: int = district.owner

		# Case 1: Neutral district
		if owner == 0:
			if dominant_faction > 0:
				# Capture progress
				var progress: float = district.capture_progress.get(dominant_faction, 0.0)
				progress += DISTRICT_CAPTURE_RATE * dominant_count * delta
				district.capture_progress[dominant_faction] = clampf(progress, 0.0, 1.0)

				if progress >= 1.0:
					district.owner = dominant_faction
					district.control_level = 1.0
					district.capture_progress.clear()
					_track_stat(dominant_faction, "districts_captured")
					print("District %d captured by faction %d!" % [district_id, dominant_faction])
					# Update territory overlay
					if _district_overlay:
						_district_overlay.set_district_owner(district.grid_x, district.grid_y, dominant_faction)
			else:
				# Decay all capture progress
				for faction_id in district.capture_progress.keys():
					district.capture_progress[faction_id] = maxf(0.0, district.capture_progress[faction_id] - DISTRICT_DECAY_RATE * delta)

		# Case 2: Owned district
		else:
			var owner_units: int = units_here.get(owner, 0)
			var enemy_units := 0
			for faction_id in units_here:
				if faction_id != owner:
					enemy_units += units_here[faction_id]

			if enemy_units > owner_units:
				# Enemy taking over - reduce control
				district.control_level -= DISTRICT_CAPTURE_RATE * (enemy_units - owner_units) * delta
				if district.control_level <= 0:
					var old_owner: int = district.owner
					district.owner = 0
					district.control_level = 0.0
					print("District %d lost by faction %d!" % [district_id, old_owner])
					# Update territory overlay
					if _district_overlay:
						_district_overlay.set_district_owner(district.grid_x, district.grid_y, 0)
			elif owner_units > 0:
				# Owner defending - restore control
				district.control_level = minf(1.0, district.control_level + DISTRICT_CAPTURE_RATE * delta)

		# Update visual
		_update_district_visual(district)

	# Update territory overlay animations
	if _district_overlay:
		_district_overlay.update(delta)

	# Generate passive income from controlled districts
	_generate_district_income(delta)


## Update visual appearance of a district.
func _update_district_visual(district: Dictionary) -> void:
	var idx: int = district.id
	if idx >= _district_visuals.size() or idx >= _district_labels.size():
		return

	var visual: Node3D = _district_visuals[idx]
	var label: Label3D = _district_labels[idx]

	var color: Color = _get_district_color(district.owner)

	# Update border color
	for child in visual.get_children():
		if child is CSGBox3D:
			var mat: StandardMaterial3D = child.material
			if mat:
				mat.albedo_color = color
				mat.albedo_color.a = 0.6 if district.owner > 0 else 0.3
				mat.emission = color * 0.5

	# Update label
	label.modulate = color
	if district.owner == 0:
		# Show capture progress for neutral districts
		var max_progress := 0.0
		var capturing_faction := 0
		for faction_id in district.capture_progress:
			var progress: float = district.capture_progress[faction_id]
			if progress > max_progress:
				max_progress = progress
				capturing_faction = faction_id

		if max_progress > 0.01:
			label.text = "Capturing %d%%" % int(max_progress * 100)
			label.modulate = FACTION_COLORS.get(capturing_faction, Color.WHITE)
		else:
			label.text = ""
	elif district.is_contested:
		label.text = "CONTESTED"
		label.modulate = Color(1.0, 0.5, 0.0)  # Orange for contested
	elif district.control_level < 1.0:
		label.text = "Control: %d%%" % int(district.control_level * 100)
	else:
		label.text = ""  # Don't show label for fully controlled districts


## Get district ID at world position.
func _get_district_at_position(pos: Vector3) -> int:
	var grid_x: int = int((pos.x - DISTRICT_OFFSET) / DISTRICT_SIZE)
	var grid_y: int = int((pos.z - DISTRICT_OFFSET) / DISTRICT_SIZE)

	if grid_x < 0 or grid_x >= DISTRICT_GRID_SIZE:
		return -1
	if grid_y < 0 or grid_y >= DISTRICT_GRID_SIZE:
		return -1

	return grid_y * DISTRICT_GRID_SIZE + grid_x


## Generate passive income from controlled districts.
func _generate_district_income(delta: float) -> void:
	var faction_income: Dictionary = {}  # faction_id -> ree_amount

	for district in _districts:
		if district.owner > 0 and district.control_level > 0:
			var income: float = DISTRICT_INCOME_RATE * district.control_level * delta
			if not faction_income.has(district.owner):
				faction_income[district.owner] = 0.0
			faction_income[district.owner] += income

	# Apply income to each faction
	for faction_id in faction_income:
		var amount: float = faction_income[faction_id]
		if ResourceManager and amount > 0:
			ResourceManager.add_ree(faction_id, amount, "district_income")
			_track_stat(faction_id, "ree_earned", amount)


## Get count of districts owned by a faction.
func _get_faction_district_count(faction_id: int) -> int:
	var count := 0
	for district in _districts:
		if district.owner == faction_id:
			count += 1
	return count


func _spawn_initial_units() -> void:
	print("Spawning initial units...")

	for faction_id in FACTORY_POSITIONS:
		var base_pos: Vector3 = FACTORY_POSITIONS[faction_id]

		# Spawn 2 of each unit type for each faction
		for unit_type in ["light", "medium", "heavy"]:
			for i in range(2):
				var offset := Vector3(randf_range(-12, 12), 0, randf_range(-12, 12))
				_spawn_faction_unit(faction_id, base_pos + offset, unit_type)

		# Also spawn 1 harvester for each faction (using faction-specific template)
		var offset := Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		_spawn_faction_unit(faction_id, base_pos + offset, "harvester")

	print("Spawned %d initial units" % _units.size())


## Spawn a faction-specific unit using templates
func _spawn_faction_unit(faction_id: int, position: Vector3, weight_class: String) -> Dictionary:
	var template_id := ""
	var faction_templates: Dictionary = FACTION_UNIT_TEMPLATES.get(faction_id, {})
	template_id = faction_templates.get(weight_class, "")

	# Special handling for harvester - use faction-specific harvester template
	if weight_class == "harvester":
		match faction_id:
			1: template_id = "aether_swarm_nano_reaplet"
			2: template_id = "optiforge_repair_drone"
			3: template_id = "dynapods_quadripper"
			4: template_id = "logibots_bulkripper"
			5: template_id = "human_soldier"  # Humans don't have dedicated harvesters

	# Try to get unit stats from UnitTemplateManager
	var template: UnitTemplate = null
	if template_id != "" and UnitTemplateManager != null:
		template = UnitTemplateManager.get_template(template_id)

	if template != null:
		return _spawn_unit_from_template(faction_id, position, template)
	else:
		# Fallback to generic types
		var fallback_type := "soldier"
		match weight_class:
			"light": fallback_type = "scout"
			"medium": fallback_type = "soldier"
			"heavy": fallback_type = "tank"
			"harvester": fallback_type = "harvester"
		return _spawn_unit(faction_id, position, fallback_type)


## Spawn a unit using UnitTemplate data
func _spawn_unit_from_template(faction_id: int, position: Vector3, template: UnitTemplate) -> Dictionary:
	var stats: Dictionary = template.base_stats

	# Check if spawn position is blocked by building and find clear spot
	var spawn_pos := position
	if _city_renderer != null and _city_renderer.is_position_blocked(position, 2.0):
		var offsets: Array[Vector3] = [Vector3(5, 0, 0), Vector3(-5, 0, 0), Vector3(0, 0, 5), Vector3(0, 0, -5),
					   Vector3(5, 0, 5), Vector3(-5, 0, 5), Vector3(5, 0, -5), Vector3(-5, 0, -5),
					   Vector3(10, 0, 0), Vector3(-10, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, -10)]
		for offset in offsets:
			var test_pos: Vector3 = position + offset
			if not _city_renderer.is_position_blocked(test_pos, 2.0):
				spawn_pos = test_pos
				break

	# Calculate visual size based on health (proxy for unit mass)
	var health: float = stats.get("max_health", 100.0)
	var scale_factor := sqrt(health / 100.0)  # Normalize around 100 HP
	var base_size := Vector3(1.5, 2.0, 1.5) * scale_factor

	# Map template unit_type to procedural bot type
	var bot_type: String = template.unit_type
	if bot_type == "light":
		bot_type = "scout"
	elif bot_type == "medium":
		bot_type = "soldier"
	elif bot_type == "heavy":
		bot_type = "tank"

	# Get type data for procedural bot
	var type_data: Dictionary = UNIT_TYPES.get(bot_type, UNIT_TYPES.get("soldier", {}))
	type_data = type_data.duplicate()
	type_data["size"] = base_size  # Override size based on template health

	# Create procedural bot visual instead of simple box
	var mesh := _create_procedural_bot(faction_id, bot_type, type_data)
	mesh.position = spawn_pos
	mesh.position.y = base_size.y / 2.0

	_unit_container.add_child(mesh)

	# Create health bar
	var health_bar := _create_health_bar(faction_id)
	_health_bar_container.add_child(health_bar)

	# Create unit data from template
	var max_speed: float = stats.get("max_speed", 10.0)
	var speed_variance := max_speed * 0.15  # 15% speed variance
	var base_armor: float = stats.get("armor", 0.0)

	# Assign unique ID for faction mechanics tracking
	var unit_id := _next_unit_id
	_next_unit_id += 1

	var unit := {
		"id": unit_id,
		"mesh": mesh,
		"health_bar": health_bar,
		"faction_id": faction_id,
		"unit_type": template.unit_type,
		"template_id": template.template_id,
		"display_name": template.display_name,
		"health": health,
		"max_health": health,
		"damage": stats.get("base_damage", 10.0),
		"attack_range": stats.get("attack_range", 10.0),
		"armor": base_armor,
		"attack_speed": stats.get("attack_speed", 1.0),
		"target_pos": spawn_pos,
		"target_enemy": null,
		"speed": max_speed + randf_range(-speed_variance, speed_variance),
		"attack_cooldown": 0.0,
		"is_selected": false,
		"is_dead": false,
		"abilities": template.abilities.duplicate(),
		"tags": template.tags.duplicate(),
		"xp": 0.0,
		"veterancy_level": 0,
		"veterancy_indicator": null  # Visual stars/chevrons above unit
	}

	_units.append(unit)
	GameStateManager.record_unit_created(faction_id)
	_track_stat(faction_id, "units_produced")

	# Award Hive Mind Engineering XP for production (varies by unit type)
	var eng_xp: float = 20.0  # Base for light
	if template.unit_type == "medium":
		eng_xp = 40.0
	elif template.unit_type == "heavy":
		eng_xp = 80.0
	_award_faction_xp(faction_id, ExperiencePool.Category.ENGINEERING, eng_xp)

	# Register with faction mechanics system for ability bonuses
	if _faction_mechanics != null:
		var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
		if faction_str != "":
			_faction_mechanics.register_unit(unit_id, faction_str, base_armor)
			_faction_mechanics.update_position(unit_id, position)

	# Register Aether Swarm units with NanoReplication for passive healing
	if faction_id == _player_faction and _nano_replication != null:
		_nano_replication.register_unit(unit_id)

	# Register Aether Swarm units with FractalMovement for evasion bonus
	if faction_id == _player_faction and _fractal_movement != null:
		_fractal_movement.register_unit(unit_id)

	# Register Dynapods units with AcrobaticStrike for leap attacks
	if faction_id == 3 and _acrobatic_strike != null:
		_acrobatic_strike.register_unit(unit_id)

	# Register LogiBots units with CoordinatedBarrage for focus fire
	if faction_id == 4 and _coordinated_barrage != null:
		_coordinated_barrage.register_unit(unit_id)

	# Register with MultiMesh rendering system for batched draw calls
	if _multimesh_renderer != null and _use_multimesh_rendering:
		# Map faction_id to MultiMeshRenderer faction constants (0-4)
		var mm_faction_id := faction_id - 1  # main.gd uses 1-5, MultiMesh uses 0-4
		mm_faction_id = clampi(mm_faction_id, 0, 4)
		var mm_unit_type := _map_template_to_multimesh_type(template.unit_type, faction_id)
		_multimesh_renderer.register_unit(unit_id, mm_faction_id, mm_unit_type, mesh.global_transform)
		# Hide individual mesh - MultiMesh handles rendering
		mesh.visible = false

	# Register with LOD system for visual detail management
	if _lod_system != null:
		_lod_system.register_unit(unit_id, spawn_pos)

	# Register with performance tier system for AI update throttling
	if _performance_tier_system != null and _use_performance_tiers:
		_performance_tier_system.register_unit(unit_id)

	return unit


## Maps template unit types to MultiMeshRenderer mesh types for batched rendering.
func _map_template_to_multimesh_type(template_type: String, faction_id: int) -> String:
	# MultiMeshRenderer has faction-specific mesh types
	# Map our template types (light, medium, heavy) to appropriate faction meshes
	match faction_id:
		1:  # Aether Swarm
			match template_type:
				"light": return "drone"
				"medium": return "scout"
				"heavy": return "phaser"
				_: return "drone"
		2:  # OptiForge Legion
			match template_type:
				"light": return "grunt"
				"medium": return "soldier"
				"heavy": return "heavy"
				_: return "soldier"
		3:  # Dynapods Vanguard
			match template_type:
				"light": return "runner"
				"medium": return "striker"
				"heavy": return "juggernaut"
				_: return "striker"
		4:  # LogiBots Colossus
			match template_type:
				"light": return "worker"
				"medium": return "defender"
				"heavy": return "titan"
				_: return "defender"
		5:  # Human Remnant
			match template_type:
				"light": return "soldier"
				"medium": return "heavy"
				"heavy": return "vehicle"
				_: return "soldier"
		_:
			return "soldier"


func _spawn_player_reinforcements() -> void:
	if GameStateManager.get_match_status() != GameStateManager.MatchStatus.ACTIVE:
		return

	var base_pos: Vector3 = FACTORY_POSITIONS[1]

	# Mix of faction-specific reinforcements
	for i in range(2):
		var offset := Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		_spawn_faction_unit(1, base_pos + offset, "light")

	for i in range(2):
		var offset := Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
		_spawn_faction_unit(1, base_pos + offset, "medium")

	var offset := Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
	_spawn_faction_unit(1, base_pos + offset, "heavy")

	print("Reinforcements spawned! Total units: %d" % _units.size())


## Activate Phase Shift ability for player faction (Aether Swarm)
func _activate_phase_shift() -> void:
	if GameStateManager.get_match_status() != GameStateManager.MatchStatus.ACTIVE:
		return

	if _phase_shift == null:
		return

	var validation := _phase_shift.can_activate()
	if not validation["can_activate"]:
		print("Phase Shift: %s" % validation["reason"])
		return

	# Check REE cost (80 REE)
	# TODO: Wire to ResourceManager when available
	# For now, always allow activation

	var success := _phase_shift.activate("aether_swarm")
	if success:
		_track_stat(1, "abilities_used")  # Aether Swarm = faction 1
		print("Phase Shift ACTIVATED! All Aether Swarm units phasing for 3s (90%% damage reduction)")
		# Blink affected units
		_start_blink_effect(1, 1.0)
		# Spawn ability visual effect on all Aether Swarm units
		for unit in _units:
			if unit.faction_id == 1 and not unit.is_dead and is_instance_valid(unit.mesh):
				_spawn_ability_effect(unit.mesh.global_position, 1, "phase_shift")
	else:
		print("Phase Shift: No units to phase")


## Activate Overclock ability for OptiForge (faction 2)
func _activate_overclock() -> void:
	if GameStateManager.get_match_status() != GameStateManager.MatchStatus.ACTIVE:
		return

	if _overclock_unit == null:
		return

	var validation := _overclock_unit.can_activate()
	if not validation["can_activate"]:
		print("Overclock: %s" % validation["reason"])
		return

	# Check REE cost (60 REE)
	# TODO: Wire to ResourceManager when available
	# For now, always allow activation

	# Overclock is for OptiForge (faction 2 = glacius)
	var success := _overclock_unit.activate("glacius")
	if success:
		_track_stat(2, "abilities_used")  # OptiForge = faction 2
		print("OVERCLOCK ACTIVATED! All OptiForge units boosted for 5s (+50%% damage, +30%% speed, 5 DPS self-damage)")
		# Blink affected units
		_start_blink_effect(2, 1.0)
		# Spawn ability visual effect on all OptiForge units
		for unit in _units:
			if unit.faction_id == 2 and not unit.is_dead and is_instance_valid(unit.mesh):
				_spawn_ability_effect(unit.mesh.global_position, 2, "overclock")
	else:
		print("Overclock: No units to boost")


## Toggle Siege Formation ability for LogiBots (faction 4)
func _toggle_siege_formation() -> void:
	if GameStateManager.get_match_status() != GameStateManager.MatchStatus.ACTIVE:
		return

	if _siege_formation == null:
		return

	# Siege is for LogiBots (faction 4)
	var deployed_count := _siege_formation.get_deployed_count()

	if deployed_count > 0:
		# Undeploy all
		_siege_formation.cancel_all()
		print("Siege Formation CANCELLED! LogiBots can move again")
	else:
		var validation := _siege_formation.can_activate()
		if not validation["can_activate"]:
			print("Siege Formation: %s" % validation["reason"])
			return

		# Check REE cost (40 REE)
		# TODO: Wire to ResourceManager when available

		var success := _siege_formation.activate("logibots")
		if success:
			_track_stat(4, "abilities_used")  # LogiBots = faction 4
			print("SIEGE FORMATION! LogiBots deployed (+50%% range, cannot move)")
			# Blink affected units
			_start_blink_effect(4, 1.0)
			# Spawn ability visual effect on all LogiBots units
			for unit in _units:
				if unit.faction_id == 4 and not unit.is_dead and is_instance_valid(unit.mesh):
					_spawn_ability_effect(unit.mesh.global_position, 4, "siege_formation")
		else:
			print("Siege Formation: No units to deploy")


## Activate Ether Cloak ability for Aether Swarm (faction 1)
func _activate_ether_cloak() -> void:
	if GameStateManager.get_match_status() != GameStateManager.MatchStatus.ACTIVE:
		return

	if _ether_cloak == null:
		return

	var validation := _ether_cloak.can_activate()
	if not validation["can_activate"]:
		print("Ether Cloak: %s" % validation["reason"])
		return

	# Check REE cost (50 REE)
	# TODO: Wire to ResourceManager when available

	var success := _ether_cloak.activate("aether_swarm")
	if success:
		_track_stat(1, "abilities_used")  # Aether Swarm = faction 1
		print("ETHER CLOAK! Aether Swarm units invisible for 4s")
		# Blink affected units
		_start_blink_effect(1, 1.0)
		# Spawn ability visual effect on all Aether Swarm units
		for unit in _units:
			if unit.faction_id == 1 and not unit.is_dead and is_instance_valid(unit.mesh):
				_spawn_ability_effect(unit.mesh.global_position, 1, "phase_shift")
	else:
		print("Ether Cloak: No units to cloak")


## Activate Acrobatic Strike ability for Dynapods (faction 3)
func _activate_acrobatic_strike() -> void:
	if GameStateManager.get_match_status() != GameStateManager.MatchStatus.ACTIVE:
		return

	if _acrobatic_strike == null:
		return

	var validation := _acrobatic_strike.can_activate()
	if not validation["can_activate"]:
		print("Acrobatic Strike: %s" % validation["reason"])
		return

	# Check REE cost (40 REE)
	# TODO: Wire to ResourceManager when available

	# Get Dynapods units (faction 3) and find a target
	var dynapods_units: Array[int] = []
	var unit_positions: Dictionary = {}
	var target_pos := Vector3.ZERO
	var has_target := false

	for unit in _units:
		if unit.faction_id == 3 and not unit.is_dead:
			var unit_id: int = unit.get("id", 0)
			if unit_id > 0:
				dynapods_units.append(unit_id)
				if is_instance_valid(unit.mesh):
					unit_positions[unit_id] = unit.mesh.position

	if dynapods_units.is_empty():
		print("Acrobatic Strike: No Dynapods units available")
		return

	# Find nearest enemy to leap towards
	var best_dist: float = INF
	for unit in _units:
		if unit.faction_id != 3 and not unit.is_dead:
			if is_instance_valid(unit.mesh):
				for dynapod_id in dynapods_units:
					if unit_positions.has(dynapod_id):
						var dist: float = unit_positions[dynapod_id].distance_to(unit.mesh.position)
						if dist < best_dist and dist <= 20.0:  # Within leap range
							best_dist = dist
							target_pos = unit.mesh.position
							has_target = true

	if not has_target:
		print("Acrobatic Strike: No enemies in range")
		return

	# Activate leap for ALL Dynapods units in range
	var leaps_started: int = 0
	for unit_id in dynapods_units:
		if not unit_positions.has(unit_id):
			continue
		var start_pos: Vector3 = unit_positions[unit_id]
		# Check if this unit is in range of the target
		if start_pos.distance_to(target_pos) <= 20.0:
			if _acrobatic_strike.activate_leap(unit_id, start_pos, target_pos):
				leaps_started += 1

	if leaps_started > 0:
		_track_stat(3, "abilities_used")  # Dynapods = faction 3
		print("ACROBATIC STRIKE! %d Dynapods units leaping for 75 AoE damage!" % leaps_started)
		# Blink Dynapods units
		_start_blink_effect(3, 1.0)
		# Spawn ability visual effect at target position
		_spawn_ability_effect(target_pos, 3, "default")
		# Also spawn effects on all leaping units
		for unit_id in dynapods_units:
			if unit_positions.has(unit_id):
				_spawn_ability_effect(unit_positions[unit_id], 3, "default")
	else:
		print("Acrobatic Strike: Failed to activate")


## Activate Coordinated Barrage ability for LogiBots (faction 4)
func _activate_coordinated_barrage() -> void:
	if GameStateManager.get_match_status() != GameStateManager.MatchStatus.ACTIVE:
		return

	if _coordinated_barrage == null:
		return

	var validation := _coordinated_barrage.can_activate()
	if not validation["can_activate"]:
		print("Coordinated Barrage: %s" % validation["reason"])
		return

	# Check REE cost (30 REE)
	# TODO: Wire to ResourceManager when available

	# Find a high-value enemy target
	var best_target_id: int = -1
	var best_target_pos := Vector3.ZERO
	var best_health: float = 0.0

	for unit in _units:
		if unit.faction_id != 4 and not unit.is_dead:  # Enemy of LogiBots
			if is_instance_valid(unit.mesh):
				# Prioritize higher health targets
				if unit.health > best_health:
					best_health = unit.health
					best_target_id = unit.get("id", 0)
					best_target_pos = unit.mesh.position

	if best_target_id < 0:
		print("Coordinated Barrage: No targets available")
		return

	var success := _coordinated_barrage.activate(best_target_id, best_target_pos)
	if success:
		print("COORDINATED BARRAGE! Target marked for +75%% damage for 8s!")
		# Blink LogiBots units
		_start_blink_effect(4, 1.0)
	else:
		print("Coordinated Barrage: Failed to mark target")


## Start blinking visual effect for units of a faction
func _start_blink_effect(faction_id: int, duration: float) -> void:
	var end_time: float = Time.get_ticks_msec() / 1000.0 + duration
	for unit in _units:
		if unit.faction_id == faction_id and not unit.is_dead:
			var unit_id: int = unit.get("id", 0)
			if unit_id > 0:
				_blinking_units[unit_id] = {
					"end_time": end_time,
					"faction_id": faction_id
				}


## Get material from a unit mesh (handles CSGCombiner3D and CSGBox3D).
func _get_unit_material(mesh: Node3D) -> StandardMaterial3D:
	if mesh == null:
		return null
	# For CSGCombiner3D, get material from first child
	if mesh is CSGCombiner3D:
		if mesh.get_child_count() > 0:
			var first_child: Node = mesh.get_child(0)
			if first_child is CSGShape3D:
				return first_child.material as StandardMaterial3D
	# For CSGShape3D (CSGBox3D, etc.), get material directly
	elif mesh is CSGShape3D:
		return mesh.material as StandardMaterial3D
	return null


## Update blinking visual effects
func _update_blink_effects() -> void:
	var current_time: float = Time.get_ticks_msec() / 1000.0
	var to_remove: Array = []

	for unit_id in _blinking_units:
		var blink_data: Dictionary = _blinking_units[unit_id]
		if current_time >= blink_data["end_time"]:
			to_remove.append(unit_id)
			continue

		# Find the unit and toggle visibility
		for unit in _units:
			if unit.get("id", 0) == unit_id and not unit.is_dead:
				if is_instance_valid(unit.mesh):
					# Blink by toggling emission intensity
					var blink_phase: float = sin(current_time * 15.0)  # Fast blink
					var mat: StandardMaterial3D = _get_unit_material(unit.mesh)
					if mat:
						if blink_phase > 0:
							mat.emission_energy_multiplier = 2.0  # Bright
						else:
							mat.emission_energy_multiplier = 0.2  # Dim
				break

	# Clean up finished blinks and reset emission
	for unit_id in to_remove:
		_blinking_units.erase(unit_id)
		for unit in _units:
			if unit.get("id", 0) == unit_id and not unit.is_dead:
				if is_instance_valid(unit.mesh):
					var mat: StandardMaterial3D = _get_unit_material(unit.mesh)
					if mat:
						mat.emission_energy_multiplier = 0.4  # Reset to normal
				break

	# Low health warning blink for player units (red pulse)
	var low_health_threshold := 0.25
	var low_health_blink := sin(current_time * 8.0)  # Slower pulse for low health
	for unit in _units:
		if unit.is_dead or unit.faction_id != _player_faction:
			continue
		if not is_instance_valid(unit.mesh):
			continue

		var unit_id: int = unit.get("id", 0)
		# Skip if already in timed blink
		if _blinking_units.has(unit_id):
			continue

		var health_pct: float = unit.health / unit.max_health
		var mat: StandardMaterial3D = _get_unit_material(unit.mesh)
		if mat == null:
			continue

		if health_pct < low_health_threshold:
			# Red warning pulse
			if low_health_blink > 0:
				mat.emission = Color(1.0, 0.2, 0.1)  # Red
				mat.emission_energy_multiplier = 1.5
			else:
				mat.emission = FACTION_COLORS.get(unit.faction_id, Color.WHITE)  # Original faction color
				mat.emission_energy_multiplier = 0.4
			unit["_low_health_blinking"] = true
		elif unit.get("_low_health_blinking", false):
			# Reset to normal when health recovered
			mat.emission = FACTION_COLORS.get(unit.faction_id, Color.WHITE)
			mat.emission_energy_multiplier = 0.4
			unit["_low_health_blinking"] = false


## Create highly detailed procedural bot models per faction AND unit type.
## DETAILED: 8-15 CSG nodes per unit for rich visual variety and faction identity.
func _create_procedural_bot(faction_id: int, unit_type: String, type_data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Bot_%d_%s" % [faction_id, unit_type]

	var base_size: Vector3 = type_data.get("size", Vector3(1.5, 2.0, 1.5))
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	# Create base material with better metallic look
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = faction_color
	base_mat.emission_enabled = true
	base_mat.emission = faction_color * 0.35
	base_mat.metallic = 0.7
	base_mat.roughness = 0.35

	# Glow material for eyes/sensors/weapons
	var glow_mat := StandardMaterial3D.new()
	glow_mat.emission_enabled = true
	glow_mat.emission_energy_multiplier = 2.5

	# Dark accent material for details
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = faction_color * 0.4
	dark_mat.metallic = 0.85
	dark_mat.roughness = 0.25

	# Highlight material for trim/accents
	var highlight_mat := StandardMaterial3D.new()
	highlight_mat.albedo_color = faction_color.lightened(0.3)
	highlight_mat.metallic = 0.9
	highlight_mat.roughness = 0.2
	highlight_mat.emission_enabled = true
	highlight_mat.emission = faction_color * 0.2

	# Build detailed models per faction + unit type
	match faction_id:
		1:  # AETHER SWARM - Sleek cyber-drones with phasing tech
			glow_mat.albedo_color = Color(0.3, 0.95, 1.0)
			glow_mat.emission = Color(0.3, 0.95, 1.0)
			match unit_type:
				"scout", "light":  # Wasp Interceptor - agile micro-drone
					# Streamlined fuselage
					var body := CSGCylinder3D.new()
					body.radius = base_size.x * 0.12
					body.height = base_size.z * 0.65
					body.rotation.x = PI / 2
					body.material = base_mat
					root.add_child(body)
					# Thorax segment
					var thorax := CSGSphere3D.new()
					thorax.radius = base_size.x * 0.14
					thorax.material = base_mat
					root.add_child(thorax)
					# Wing pairs (4 wings)
					for wing_pair in [0.18, -0.08]:
						for side in [-1, 1]:
							var wing := CSGBox3D.new()
							wing.size = Vector3(base_size.x * 0.55, 0.015, base_size.z * 0.18)
							wing.position = Vector3(base_size.x * 0.28 * side, wing_pair * base_size.y, 0)
							wing.rotation.z = side * 0.25
							wing.rotation.y = side * 0.1
							wing.material = highlight_mat
							root.add_child(wing)
					# Compound eyes
					for side in [-1, 1]:
						var eye := CSGSphere3D.new()
						eye.radius = base_size.x * 0.08
						eye.position = Vector3(base_size.x * 0.06 * side, base_size.y * 0.05, base_size.z * 0.22)
						eye.material = glow_mat
						root.add_child(eye)
					# Stinger
					var stinger := CSGCylinder3D.new()
					stinger.radius = base_size.x * 0.025
					stinger.height = base_size.z * 0.2
					stinger.rotation.x = PI / 2
					stinger.position.z = -base_size.z * 0.35
					stinger.material = dark_mat
					root.add_child(stinger)

				"soldier", "medium":  # Phase Wraith - phasing combat drone
					# Diamond-cut main body
					var body := CSGBox3D.new()
					body.size = Vector3(base_size.x * 0.55, base_size.y * 0.45, base_size.z * 0.65)
					body.rotation.y = PI / 4
					body.material = base_mat
					root.add_child(body)
					# Central power core
					var core := CSGSphere3D.new()
					core.radius = base_size.x * 0.16
					core.position.y = base_size.y * 0.18
					core.material = glow_mat
					root.add_child(core)
					# Phase emitter panels
					for side in [-1, 1]:
						var panel := CSGBox3D.new()
						panel.size = Vector3(0.06, base_size.y * 0.42, base_size.z * 0.5)
						panel.position.x = base_size.x * 0.42 * side
						panel.rotation.z = side * 0.35
						panel.material = highlight_mat
						root.add_child(panel)
						# Panel glow strips
						var strip := CSGBox3D.new()
						strip.size = Vector3(0.02, base_size.y * 0.38, base_size.z * 0.08)
						strip.position = Vector3(base_size.x * 0.44 * side, 0, base_size.z * 0.15)
						strip.material = glow_mat
						root.add_child(strip)
					# Sensor array
					var sensor := CSGCylinder3D.new()
					sensor.radius = base_size.x * 0.08
					sensor.height = base_size.y * 0.12
					sensor.position.y = base_size.y * 0.35
					sensor.material = dark_mat
					root.add_child(sensor)
					# Weapon pods
					for side in [-1, 1]:
						var pod := CSGCylinder3D.new()
						pod.radius = base_size.x * 0.05
						pod.height = base_size.z * 0.25
						pod.rotation.x = PI / 2
						pod.position = Vector3(base_size.x * 0.25 * side, -base_size.y * 0.1, base_size.z * 0.25)
						pod.material = dark_mat
						root.add_child(pod)

				"tank", "heavy":  # Void Carrier - massive support platform
					# Hexagonal main hull
					var hull := CSGCylinder3D.new()
					hull.radius = base_size.x * 0.5
					hull.height = base_size.y * 0.32
					hull.sides = 6
					hull.material = base_mat
					root.add_child(hull)
					# Upper dome
					var dome := CSGSphere3D.new()
					dome.radius = base_size.x * 0.32
					dome.position.y = base_size.y * 0.22
					dome.material = base_mat
					root.add_child(dome)
					# Central reactor core
					var core := CSGSphere3D.new()
					core.radius = base_size.x * 0.22
					core.position.y = base_size.y * 0.38
					core.material = glow_mat
					root.add_child(core)
					# Drone bay hatches
					for angle_idx in 6:
						var angle := angle_idx * TAU / 6
						var hatch := CSGBox3D.new()
						hatch.size = Vector3(base_size.x * 0.15, 0.04, base_size.z * 0.12)
						hatch.position = Vector3(cos(angle) * base_size.x * 0.38, base_size.y * 0.18, sin(angle) * base_size.z * 0.38)
						hatch.rotation.y = angle
						hatch.material = dark_mat
						root.add_child(hatch)
					# Hover emitters
					for side in [-1, 1]:
						for fwd in [-1, 1]:
							var emitter := CSGCylinder3D.new()
							emitter.radius = base_size.x * 0.08
							emitter.height = base_size.y * 0.06
							emitter.position = Vector3(base_size.x * 0.3 * side, -base_size.y * 0.18, base_size.z * 0.3 * fwd)
							emitter.material = glow_mat
							root.add_child(emitter)

				"harvester":  # Collector Drone - resource gatherer
					var body := CSGCylinder3D.new()
					body.radius = base_size.x * 0.28
					body.height = base_size.y * 0.45
					body.material = base_mat
					root.add_child(body)
					# Collection scoop
					var scoop := CSGBox3D.new()
					scoop.size = Vector3(base_size.x * 0.55, base_size.y * 0.18, base_size.z * 0.35)
					scoop.position = Vector3(0, -base_size.y * 0.22, base_size.z * 0.18)
					scoop.material = dark_mat
					root.add_child(scoop)
					# Intake glow
					var intake := CSGBox3D.new()
					intake.size = Vector3(base_size.x * 0.45, base_size.y * 0.08, base_size.z * 0.05)
					intake.position = Vector3(0, -base_size.y * 0.18, base_size.z * 0.38)
					intake.material = glow_mat
					root.add_child(intake)
					# Storage pods
					for side in [-1, 1]:
						var pod := CSGSphere3D.new()
						pod.radius = base_size.x * 0.15
						pod.position = Vector3(base_size.x * 0.25 * side, base_size.y * 0.1, 0)
						pod.material = highlight_mat
						root.add_child(pod)
				_:
					var body := CSGCylinder3D.new()
					body.radius = base_size.x * 0.35
					body.height = base_size.y * 0.6
					body.material = base_mat
					root.add_child(body)

		2:  # OPTIFORGE LEGION - Industrial humanoid war machines
			glow_mat.albedo_color = Color(1.0, 0.35, 0.1)
			glow_mat.emission = Color(1.0, 0.35, 0.1)
			match unit_type:
				"scout", "light":  # Reaper Runner - fast assault bot
					# Torso chassis
					var torso := CSGBox3D.new()
					torso.size = Vector3(base_size.x * 0.38, base_size.y * 0.38, base_size.z * 0.28)
					torso.position.y = base_size.y * 0.12
					torso.material = base_mat
					root.add_child(torso)
					# Head unit
					var head := CSGBox3D.new()
					head.size = Vector3(base_size.x * 0.22, base_size.y * 0.16, base_size.z * 0.18)
					head.position.y = base_size.y * 0.38
					head.material = base_mat
					root.add_child(head)
					# Visor strip
					var visor := CSGBox3D.new()
					visor.size = Vector3(base_size.x * 0.2, base_size.y * 0.045, 0.05)
					visor.position = Vector3(0, base_size.y * 0.4, base_size.z * 0.09)
					visor.material = glow_mat
					root.add_child(visor)
					# Leg pistons
					for side in [-1, 1]:
						var leg := CSGCylinder3D.new()
						leg.radius = base_size.x * 0.06
						leg.height = base_size.y * 0.35
						leg.position = Vector3(base_size.x * 0.12 * side, -base_size.y * 0.12, 0)
						leg.material = dark_mat
						root.add_child(leg)
						# Knee joint
						var knee := CSGSphere3D.new()
						knee.radius = base_size.x * 0.05
						knee.position = Vector3(base_size.x * 0.12 * side, -base_size.y * 0.08, 0)
						knee.material = highlight_mat
						root.add_child(knee)
					# Arm blades
					for side in [-1, 1]:
						var arm := CSGBox3D.new()
						arm.size = Vector3(base_size.x * 0.04, base_size.y * 0.28, base_size.z * 0.06)
						arm.position = Vector3(base_size.x * 0.25 * side, base_size.y * 0.05, 0)
						arm.material = dark_mat
						root.add_child(arm)

				"soldier", "medium":  # Iron Trooper - frontline infantry
					# Armored torso
					var torso := CSGBox3D.new()
					torso.size = Vector3(base_size.x * 0.52, base_size.y * 0.42, base_size.z * 0.38)
					torso.position.y = base_size.y * 0.1
					torso.material = base_mat
					root.add_child(torso)
					# Chest plate detail
					var chest := CSGBox3D.new()
					chest.size = Vector3(base_size.x * 0.35, base_size.y * 0.25, base_size.z * 0.08)
					chest.position = Vector3(0, base_size.y * 0.15, base_size.z * 0.2)
					chest.material = highlight_mat
					root.add_child(chest)
					# Head with helmet
					var head := CSGBox3D.new()
					head.size = Vector3(base_size.x * 0.28, base_size.y * 0.18, base_size.z * 0.22)
					head.position.y = base_size.y * 0.4
					head.material = base_mat
					root.add_child(head)
					# Wide visor
					var visor := CSGBox3D.new()
					visor.size = Vector3(base_size.x * 0.26, base_size.y * 0.06, 0.05)
					visor.position = Vector3(0, base_size.y * 0.42, base_size.z * 0.11)
					visor.material = glow_mat
					root.add_child(visor)
					# Shoulder armor
					for side in [-1, 1]:
						var shoulder := CSGBox3D.new()
						shoulder.size = Vector3(base_size.x * 0.2, base_size.y * 0.14, base_size.z * 0.32)
						shoulder.position = Vector3(base_size.x * 0.38 * side, base_size.y * 0.26, 0)
						shoulder.rotation.z = side * 0.15
						shoulder.material = dark_mat
						root.add_child(shoulder)
					# Weapon arm
					var weapon := CSGCylinder3D.new()
					weapon.radius = base_size.x * 0.055
					weapon.height = base_size.z * 0.35
					weapon.rotation.x = PI / 2
					weapon.position = Vector3(base_size.x * 0.32, base_size.y * 0.08, base_size.z * 0.22)
					weapon.material = dark_mat
					root.add_child(weapon)
					# Legs
					for side in [-1, 1]:
						var leg := CSGBox3D.new()
						leg.size = Vector3(base_size.x * 0.12, base_size.y * 0.32, base_size.z * 0.14)
						leg.position = Vector3(base_size.x * 0.15 * side, -base_size.y * 0.18, 0)
						leg.material = dark_mat
						root.add_child(leg)

				"tank", "heavy":  # Devastator Brute - siege powerhouse
					# Massive torso
					var torso := CSGBox3D.new()
					torso.size = Vector3(base_size.x * 0.78, base_size.y * 0.52, base_size.z * 0.58)
					torso.position.y = base_size.y * 0.1
					torso.material = base_mat
					root.add_child(torso)
					# Reactor core (exposed)
					var reactor := CSGCylinder3D.new()
					reactor.radius = base_size.x * 0.12
					reactor.height = base_size.y * 0.18
					reactor.position = Vector3(0, base_size.y * 0.2, base_size.z * 0.28)
					reactor.material = glow_mat
					root.add_child(reactor)
					# Hunched head
					var head := CSGBox3D.new()
					head.size = Vector3(base_size.x * 0.28, base_size.y * 0.16, base_size.z * 0.28)
					head.position.y = base_size.y * 0.42
					head.material = dark_mat
					root.add_child(head)
					# Multi-lens visor
					var visor := CSGBox3D.new()
					visor.size = Vector3(base_size.x * 0.26, base_size.y * 0.07, 0.06)
					visor.position = Vector3(0, base_size.y * 0.42, base_size.z * 0.14)
					visor.material = glow_mat
					root.add_child(visor)
					# Shoulder-mounted siege cannons
					for side in [-1, 1]:
						var mount := CSGBox3D.new()
						mount.size = Vector3(base_size.x * 0.18, base_size.y * 0.12, base_size.z * 0.18)
						mount.position = Vector3(base_size.x * 0.48 * side, base_size.y * 0.38, 0)
						mount.material = dark_mat
						root.add_child(mount)
						var cannon := CSGCylinder3D.new()
						cannon.radius = base_size.x * 0.075
						cannon.height = base_size.z * 0.45
						cannon.rotation.x = PI / 2
						cannon.position = Vector3(base_size.x * 0.48 * side, base_size.y * 0.38, base_size.z * 0.28)
						cannon.material = dark_mat
						root.add_child(cannon)
						# Cannon glow
						var muzzle := CSGCylinder3D.new()
						muzzle.radius = base_size.x * 0.05
						muzzle.height = base_size.z * 0.04
						muzzle.rotation.x = PI / 2
						muzzle.position = Vector3(base_size.x * 0.48 * side, base_size.y * 0.38, base_size.z * 0.52)
						muzzle.material = glow_mat
						root.add_child(muzzle)
					# Heavy legs
					for side in [-1, 1]:
						var leg := CSGBox3D.new()
						leg.size = Vector3(base_size.x * 0.18, base_size.y * 0.38, base_size.z * 0.22)
						leg.position = Vector3(base_size.x * 0.22 * side, -base_size.y * 0.22, 0)
						leg.material = dark_mat
						root.add_child(leg)

				"harvester":  # Hauler Unit - resource transport
					var torso := CSGBox3D.new()
					torso.size = Vector3(base_size.x * 0.48, base_size.y * 0.38, base_size.z * 0.42)
					torso.material = base_mat
					root.add_child(torso)
					var collector := CSGBox3D.new()
					collector.size = Vector3(base_size.x * 0.62, base_size.y * 0.16, base_size.z * 0.32)
					collector.position.y = -base_size.y * 0.22
					collector.material = dark_mat
					root.add_child(collector)
					# Intake glow
					var intake := CSGBox3D.new()
					intake.size = Vector3(base_size.x * 0.5, base_size.y * 0.06, 0.04)
					intake.position = Vector3(0, -base_size.y * 0.18, base_size.z * 0.18)
					intake.material = glow_mat
					root.add_child(intake)
				_:
					var body := CSGBox3D.new()
					body.size = Vector3(base_size.x * 0.5, base_size.y * 0.6, base_size.z * 0.4)
					body.material = base_mat
					root.add_child(body)

		3:  # DYNAPODS VANGUARD - Agile insectoid/arachnid mechs
			glow_mat.albedo_color = Color(0.25, 1.0, 0.45)
			glow_mat.emission = Color(0.25, 1.0, 0.45)
			match unit_type:
				"scout", "light":  # Shadow Stalker - fast spider scout
					# Compact thorax
					var body := CSGCylinder3D.new()
					body.radius = base_size.x * 0.18
					body.height = base_size.y * 0.28
					body.material = base_mat
					root.add_child(body)
					# Head segment
					var head := CSGSphere3D.new()
					head.radius = base_size.x * 0.14
					head.position = Vector3(0, base_size.y * 0.06, base_size.z * 0.14)
					head.material = base_mat
					root.add_child(head)
					# Multi-eye cluster (6 eyes)
					for eye_idx in 6:
						var eye := CSGSphere3D.new()
						eye.radius = base_size.x * 0.04
						var angle := eye_idx * TAU / 6 + TAU / 12
						eye.position = Vector3(
							cos(angle) * base_size.x * 0.1,
							base_size.y * 0.1,
							base_size.z * 0.22 + sin(angle) * base_size.z * 0.05
						)
						eye.material = glow_mat
						root.add_child(eye)
					# Spider legs (4 pairs)
					for leg_idx in 4:
						for side in [-1, 1]:
							var leg := CSGCylinder3D.new()
							leg.radius = base_size.x * 0.02
							leg.height = base_size.y * 0.22
							var angle := (leg_idx - 1.5) * 0.4
							leg.position = Vector3(
								base_size.x * 0.2 * side,
								-base_size.y * 0.05,
								sin(angle) * base_size.z * 0.12
							)
							leg.rotation.z = side * 0.8
							leg.rotation.y = angle
							leg.material = dark_mat
							root.add_child(leg)

				"soldier", "medium":  # Razor Striker - blade-armed predator
					# Segmented body
					var body := CSGCylinder3D.new()
					body.radius = base_size.x * 0.26
					body.height = base_size.y * 0.38
					body.material = base_mat
					root.add_child(body)
					var thorax := CSGSphere3D.new()
					thorax.radius = base_size.x * 0.22
					thorax.position.y = base_size.y * 0.18
					thorax.material = base_mat
					root.add_child(thorax)
					# Carapace ridges
					for ridge_idx in 3:
						var ridge := CSGBox3D.new()
						ridge.size = Vector3(base_size.x * 0.5, 0.03, base_size.z * 0.08)
						ridge.position.y = base_size.y * (0.08 + ridge_idx * 0.08)
						ridge.material = highlight_mat
						root.add_child(ridge)
					# Dual eye stalks
					for side in [-1, 1]:
						var stalk := CSGCylinder3D.new()
						stalk.radius = base_size.x * 0.03
						stalk.height = base_size.y * 0.1
						stalk.position = Vector3(base_size.x * 0.12 * side, base_size.y * 0.32, base_size.z * 0.12)
						stalk.rotation.x = -0.4
						stalk.material = dark_mat
						root.add_child(stalk)
						var eye := CSGSphere3D.new()
						eye.radius = base_size.x * 0.06
						eye.position = Vector3(base_size.x * 0.12 * side, base_size.y * 0.38, base_size.z * 0.18)
						eye.material = glow_mat
						root.add_child(eye)
					# Mantis blade arms
					for side in [-1, 1]:
						var upper_arm := CSGBox3D.new()
						upper_arm.size = Vector3(base_size.x * 0.06, base_size.y * 0.15, base_size.z * 0.06)
						upper_arm.position = Vector3(base_size.x * 0.32 * side, base_size.y * 0.15, base_size.z * 0.08)
						upper_arm.material = dark_mat
						root.add_child(upper_arm)
						var blade := CSGBox3D.new()
						blade.size = Vector3(0.03, base_size.y * 0.05, base_size.z * 0.38)
						blade.position = Vector3(base_size.x * 0.35 * side, base_size.y * 0.12, base_size.z * 0.25)
						blade.material = highlight_mat
						root.add_child(blade)

				"tank", "heavy":  # Apex Ravager - massive spider tank
					# Bulbous main body
					var body := CSGSphere3D.new()
					body.radius = base_size.x * 0.42
					body.material = base_mat
					root.add_child(body)
					# Armored abdomen
					var abdomen := CSGCylinder3D.new()
					abdomen.radius = base_size.x * 0.38
					abdomen.height = base_size.y * 0.4
					abdomen.position.z = -base_size.z * 0.28
					abdomen.rotation.x = 0.2
					abdomen.material = base_mat
					root.add_child(abdomen)
					# Abdomen spikes
					for spike_idx in 4:
						var spike := CSGCylinder3D.new()
						spike.radius = base_size.x * 0.04
						spike.height = base_size.y * 0.18
						spike.position = Vector3(0, base_size.y * 0.15 + spike_idx * 0.05, -base_size.z * (0.2 + spike_idx * 0.08))
						spike.rotation.x = -0.5
						spike.material = dark_mat
						root.add_child(spike)
					# Massive eye cluster
					var eye_base := CSGSphere3D.new()
					eye_base.radius = base_size.x * 0.18
					eye_base.position = Vector3(0, base_size.y * 0.28, base_size.z * 0.32)
					eye_base.material = glow_mat
					root.add_child(eye_base)
					# Secondary eyes
					for side in [-1, 1]:
						var eye := CSGSphere3D.new()
						eye.radius = base_size.x * 0.08
						eye.position = Vector3(base_size.x * 0.2 * side, base_size.y * 0.22, base_size.z * 0.28)
						eye.material = glow_mat
						root.add_child(eye)
					# Heavy spider legs
					for leg_idx in 4:
						for side in [-1, 1]:
							var leg := CSGCylinder3D.new()
							leg.radius = base_size.x * 0.045
							leg.height = base_size.y * 0.38
							var angle := (leg_idx - 1.5) * 0.35
							leg.position = Vector3(
								base_size.x * 0.38 * side,
								-base_size.y * 0.08,
								sin(angle) * base_size.z * 0.2
							)
							leg.rotation.z = side * 0.7
							leg.rotation.y = angle
							leg.material = dark_mat
							root.add_child(leg)

				"harvester":  # Scavenger Tick - resource collector
					var body := CSGSphere3D.new()
					body.radius = base_size.x * 0.32
					body.material = base_mat
					root.add_child(body)
					var scoop := CSGBox3D.new()
					scoop.size = Vector3(base_size.x * 0.42, base_size.y * 0.16, base_size.z * 0.28)
					scoop.position.y = -base_size.y * 0.2
					scoop.material = dark_mat
					root.add_child(scoop)
					# Mandibles
					for side in [-1, 1]:
						var mandible := CSGBox3D.new()
						mandible.size = Vector3(base_size.x * 0.08, base_size.y * 0.06, base_size.z * 0.18)
						mandible.position = Vector3(base_size.x * 0.18 * side, -base_size.y * 0.15, base_size.z * 0.22)
						mandible.rotation.z = side * 0.3
						mandible.material = highlight_mat
						root.add_child(mandible)
				_:
					var body := CSGSphere3D.new()
					body.radius = base_size.x * 0.4
					body.material = base_mat
					root.add_child(body)

		4:  # LOGIBOTS COLOSSUS - Heavy industrial siege machines
			glow_mat.albedo_color = Color(1.0, 0.92, 0.25)
			glow_mat.emission = Color(1.0, 0.92, 0.25)
			match unit_type:
				"scout", "light":  # Scout Walker - reconnaissance unit
					# Low-profile hull
					var hull := CSGBox3D.new()
					hull.size = Vector3(base_size.x * 0.58, base_size.y * 0.28, base_size.z * 0.68)
					hull.material = base_mat
					root.add_child(hull)
					# Sensor turret
					var turret := CSGBox3D.new()
					turret.size = Vector3(base_size.x * 0.28, base_size.y * 0.14, base_size.z * 0.28)
					turret.position.y = base_size.y * 0.2
					turret.material = dark_mat
					root.add_child(turret)
					# Sensor dome
					var sensor := CSGSphere3D.new()
					sensor.radius = base_size.x * 0.12
					sensor.position = Vector3(0, base_size.y * 0.32, base_size.z * 0.12)
					sensor.material = glow_mat
					root.add_child(sensor)
					# Track assemblies
					for side in [-1, 1]:
						var track := CSGBox3D.new()
						track.size = Vector3(base_size.x * 0.12, base_size.y * 0.18, base_size.z * 0.72)
						track.position = Vector3(base_size.x * 0.38 * side, -base_size.y * 0.08, 0)
						track.material = dark_mat
						root.add_child(track)
						# Track wheels
						for wheel_idx in 3:
							var wheel := CSGCylinder3D.new()
							wheel.radius = base_size.x * 0.08
							wheel.height = base_size.x * 0.06
							wheel.rotation.z = PI / 2
							wheel.position = Vector3(
								base_size.x * 0.42 * side,
								-base_size.y * 0.1,
								base_size.z * (0.25 - wheel_idx * 0.25)
							)
							wheel.material = highlight_mat
							root.add_child(wheel)

				"soldier", "medium":  # Battle Tank - main combat vehicle
					# Sloped hull
					var hull := CSGBox3D.new()
					hull.size = Vector3(base_size.x * 0.72, base_size.y * 0.32, base_size.z * 0.82)
					hull.material = base_mat
					root.add_child(hull)
					# Upper glacis
					var glacis := CSGBox3D.new()
					glacis.size = Vector3(base_size.x * 0.6, base_size.y * 0.12, base_size.z * 0.35)
					glacis.position = Vector3(0, base_size.y * 0.18, base_size.z * 0.18)
					glacis.rotation.x = -0.25
					glacis.material = highlight_mat
					root.add_child(glacis)
					# Turret
					var turret := CSGBox3D.new()
					turret.size = Vector3(base_size.x * 0.48, base_size.y * 0.22, base_size.z * 0.48)
					turret.position.y = base_size.y * 0.28
					turret.material = dark_mat
					root.add_child(turret)
					# Main cannon
					var barrel := CSGCylinder3D.new()
					barrel.radius = base_size.x * 0.055
					barrel.height = base_size.z * 0.55
					barrel.rotation.x = PI / 2
					barrel.position = Vector3(0, base_size.y * 0.32, base_size.z * 0.5)
					barrel.material = dark_mat
					root.add_child(barrel)
					# Muzzle brake
					var muzzle := CSGCylinder3D.new()
					muzzle.radius = base_size.x * 0.07
					muzzle.height = base_size.z * 0.08
					muzzle.rotation.x = PI / 2
					muzzle.position = Vector3(0, base_size.y * 0.32, base_size.z * 0.78)
					muzzle.material = dark_mat
					root.add_child(muzzle)
					# Sensor bar
					var sensor := CSGBox3D.new()
					sensor.size = Vector3(base_size.x * 0.28, base_size.y * 0.06, 0.06)
					sensor.position = Vector3(0, base_size.y * 0.42, base_size.z * 0.18)
					sensor.material = glow_mat
					root.add_child(sensor)
					# Tracks
					for side in [-1, 1]:
						var track := CSGBox3D.new()
						track.size = Vector3(base_size.x * 0.14, base_size.y * 0.22, base_size.z * 0.85)
						track.position = Vector3(base_size.x * 0.45 * side, -base_size.y * 0.1, 0)
						track.material = dark_mat
						root.add_child(track)

				"tank", "heavy":  # Siege Colossus - ultimate war machine
					# Massive reinforced hull
					var hull := CSGBox3D.new()
					hull.size = Vector3(base_size.x * 0.92, base_size.y * 0.42, base_size.z * 0.88)
					hull.material = base_mat
					root.add_child(hull)
					# Angled front armor
					var front := CSGBox3D.new()
					front.size = Vector3(base_size.x * 0.85, base_size.y * 0.18, base_size.z * 0.2)
					front.position = Vector3(0, base_size.y * 0.15, base_size.z * 0.45)
					front.rotation.x = -0.35
					front.material = highlight_mat
					root.add_child(front)
					# Command turret
					var turret := CSGBox3D.new()
					turret.size = Vector3(base_size.x * 0.58, base_size.y * 0.28, base_size.z * 0.52)
					turret.position.y = base_size.y * 0.35
					turret.material = dark_mat
					root.add_child(turret)
					# Twin siege cannons
					for side in [-1, 1]:
						var barrel := CSGCylinder3D.new()
						barrel.radius = base_size.x * 0.065
						barrel.height = base_size.z * 0.65
						barrel.rotation.x = PI / 2
						barrel.position = Vector3(base_size.x * 0.15 * side, base_size.y * 0.4, base_size.z * 0.55)
						barrel.material = dark_mat
						root.add_child(barrel)
						# Barrel shroud
						var shroud := CSGCylinder3D.new()
						shroud.radius = base_size.x * 0.085
						shroud.height = base_size.z * 0.15
						shroud.rotation.x = PI / 2
						shroud.position = Vector3(base_size.x * 0.15 * side, base_size.y * 0.4, base_size.z * 0.75)
						shroud.material = dark_mat
						root.add_child(shroud)
					# Command sensor array
					var sensor := CSGBox3D.new()
					sensor.size = Vector3(base_size.x * 0.38, base_size.y * 0.08, 0.08)
					sensor.position = Vector3(0, base_size.y * 0.52, base_size.z * 0.2)
					sensor.material = glow_mat
					root.add_child(sensor)
					# Side sponsons
					for side in [-1, 1]:
						var sponson := CSGBox3D.new()
						sponson.size = Vector3(base_size.x * 0.18, base_size.y * 0.18, base_size.z * 0.35)
						sponson.position = Vector3(base_size.x * 0.52 * side, base_size.y * 0.08, base_size.z * 0.15)
						sponson.material = dark_mat
						root.add_child(sponson)
					# Heavy tracks
					for side in [-1, 1]:
						var track := CSGBox3D.new()
						track.size = Vector3(base_size.x * 0.18, base_size.y * 0.28, base_size.z * 0.92)
						track.position = Vector3(base_size.x * 0.55 * side, -base_size.y * 0.12, 0)
						track.material = dark_mat
						root.add_child(track)

				"harvester":  # Mining Hauler - industrial collector
					var hull := CSGBox3D.new()
					hull.size = Vector3(base_size.x * 0.68, base_size.y * 0.32, base_size.z * 0.72)
					hull.material = base_mat
					root.add_child(hull)
					var scoop := CSGBox3D.new()
					scoop.size = Vector3(base_size.x * 0.82, base_size.y * 0.16, base_size.z * 0.32)
					scoop.position = Vector3(0, -base_size.y * 0.16, base_size.z * 0.38)
					scoop.material = dark_mat
					root.add_child(scoop)
					# Hopper
					var hopper := CSGBox3D.new()
					hopper.size = Vector3(base_size.x * 0.55, base_size.y * 0.25, base_size.z * 0.45)
					hopper.position = Vector3(0, base_size.y * 0.22, -base_size.z * 0.1)
					hopper.material = dark_mat
					root.add_child(hopper)
				_:
					var body := CSGBox3D.new()
					body.size = Vector3(base_size.x * 0.8, base_size.y * 0.4, base_size.z * 0.75)
					body.material = base_mat
					root.add_child(body)

		5:  # HUMAN REMNANT - Military vehicles and infantry
			glow_mat.albedo_color = Color(0.95, 0.9, 0.75)
			glow_mat.emission = Color(0.95, 0.9, 0.75)
			match unit_type:
				"scout", "light":  # Combat Soldier - tactical infantry
					# Tactical vest torso
					var body := CSGBox3D.new()
					body.size = Vector3(base_size.x * 0.42, base_size.y * 0.45, base_size.z * 0.32)
					body.material = base_mat
					root.add_child(body)
					# Helmet
					var head := CSGSphere3D.new()
					head.radius = base_size.x * 0.14
					head.position.y = base_size.y * 0.35
					head.material = base_mat
					root.add_child(head)
					# Night vision goggles
					var nvg := CSGBox3D.new()
					nvg.size = Vector3(base_size.x * 0.22, base_size.y * 0.08, base_size.z * 0.1)
					nvg.position = Vector3(0, base_size.y * 0.38, base_size.z * 0.12)
					nvg.material = dark_mat
					root.add_child(nvg)
					# NVG glow
					for side in [-1, 1]:
						var lens := CSGCylinder3D.new()
						lens.radius = base_size.x * 0.04
						lens.height = base_size.z * 0.04
						lens.rotation.x = PI / 2
						lens.position = Vector3(base_size.x * 0.06 * side, base_size.y * 0.38, base_size.z * 0.18)
						lens.material = glow_mat
						root.add_child(lens)
					# Rifle
					var rifle := CSGBox3D.new()
					rifle.size = Vector3(base_size.x * 0.06, base_size.y * 0.08, base_size.z * 0.4)
					rifle.position = Vector3(base_size.x * 0.22, base_size.y * 0.12, base_size.z * 0.15)
					rifle.material = dark_mat
					root.add_child(rifle)
					# Legs
					for side in [-1, 1]:
						var leg := CSGBox3D.new()
						leg.size = Vector3(base_size.x * 0.1, base_size.y * 0.32, base_size.z * 0.12)
						leg.position = Vector3(base_size.x * 0.1 * side, -base_size.y * 0.18, 0)
						leg.material = dark_mat
						root.add_child(leg)

				"soldier", "medium":  # LAV-25 APC - light armored vehicle
					# APC hull
					var hull := CSGBox3D.new()
					hull.size = Vector3(base_size.x * 0.58, base_size.y * 0.42, base_size.z * 0.72)
					hull.material = base_mat
					root.add_child(hull)
					# Sloped front
					var front := CSGBox3D.new()
					front.size = Vector3(base_size.x * 0.52, base_size.y * 0.2, base_size.z * 0.18)
					front.position = Vector3(0, base_size.y * 0.08, base_size.z * 0.4)
					front.rotation.x = -0.4
					front.material = highlight_mat
					root.add_child(front)
					# Turret ring
					var turret := CSGCylinder3D.new()
					turret.radius = base_size.x * 0.16
					turret.height = base_size.y * 0.18
					turret.position.y = base_size.y * 0.3
					turret.material = dark_mat
					root.add_child(turret)
					# Autocannon
					var cannon := CSGCylinder3D.new()
					cannon.radius = base_size.x * 0.04
					cannon.height = base_size.z * 0.4
					cannon.rotation.x = PI / 2
					cannon.position = Vector3(0, base_size.y * 0.35, base_size.z * 0.35)
					cannon.material = dark_mat
					root.add_child(cannon)
					# Headlights
					for side in [-1, 1]:
						var light := CSGSphere3D.new()
						light.radius = base_size.x * 0.06
						light.position = Vector3(base_size.x * 0.2 * side, base_size.y * 0.12, base_size.z * 0.38)
						light.material = glow_mat
						root.add_child(light)
					# Wheels
					for side in [-1, 1]:
						for wheel_idx in 4:
							var wheel := CSGCylinder3D.new()
							wheel.radius = base_size.x * 0.12
							wheel.height = base_size.x * 0.08
							wheel.rotation.z = PI / 2
							wheel.position = Vector3(
								base_size.x * 0.35 * side,
								-base_size.y * 0.18,
								base_size.z * (0.28 - wheel_idx * 0.18)
							)
							wheel.material = dark_mat
							root.add_child(wheel)

				"tank", "heavy":  # M1 Abrams MBT - main battle tank
					# Hull
					var hull := CSGBox3D.new()
					hull.size = Vector3(base_size.x * 0.68, base_size.y * 0.38, base_size.z * 0.82)
					hull.material = base_mat
					root.add_child(hull)
					# Composite armor front
					var armor := CSGBox3D.new()
					armor.size = Vector3(base_size.x * 0.62, base_size.y * 0.22, base_size.z * 0.15)
					armor.position = Vector3(0, base_size.y * 0.12, base_size.z * 0.42)
					armor.rotation.x = -0.5
					armor.material = highlight_mat
					root.add_child(armor)
					# Turret
					var turret := CSGCylinder3D.new()
					turret.radius = base_size.x * 0.28
					turret.height = base_size.y * 0.24
					turret.position.y = base_size.y * 0.32
					turret.material = dark_mat
					root.add_child(turret)
					# Turret bustle
					var bustle := CSGBox3D.new()
					bustle.size = Vector3(base_size.x * 0.5, base_size.y * 0.2, base_size.z * 0.25)
					bustle.position = Vector3(0, base_size.y * 0.32, -base_size.z * 0.22)
					bustle.material = dark_mat
					root.add_child(bustle)
					# Main gun
					var barrel := CSGCylinder3D.new()
					barrel.radius = base_size.x * 0.048
					barrel.height = base_size.z * 0.6
					barrel.rotation.x = PI / 2
					barrel.position = Vector3(0, base_size.y * 0.35, base_size.z * 0.52)
					barrel.material = dark_mat
					root.add_child(barrel)
					# Commander's cupola
					var cupola := CSGCylinder3D.new()
					cupola.radius = base_size.x * 0.1
					cupola.height = base_size.y * 0.12
					cupola.position = Vector3(-base_size.x * 0.12, base_size.y * 0.48, -base_size.z * 0.08)
					cupola.material = dark_mat
					root.add_child(cupola)
					# Sensor/optics
					var optics := CSGSphere3D.new()
					optics.radius = base_size.x * 0.06
					optics.position = Vector3(0, base_size.y * 0.48, base_size.z * 0.15)
					optics.material = glow_mat
					root.add_child(optics)
					# Tracks
					for side in [-1, 1]:
						var track := CSGBox3D.new()
						track.size = Vector3(base_size.x * 0.15, base_size.y * 0.24, base_size.z * 0.85)
						track.position = Vector3(base_size.x * 0.42 * side, -base_size.y * 0.12, 0)
						track.material = dark_mat
						root.add_child(track)

				"harvester":  # Supply Truck - logistics vehicle
					var hull := CSGBox3D.new()
					hull.size = Vector3(base_size.x * 0.52, base_size.y * 0.38, base_size.z * 0.62)
					hull.material = base_mat
					root.add_child(hull)
					var scoop := CSGBox3D.new()
					scoop.size = Vector3(base_size.x * 0.48, base_size.y * 0.12, base_size.z * 0.25)
					scoop.position = Vector3(0, -base_size.y * 0.16, base_size.z * 0.32)
					scoop.material = dark_mat
					root.add_child(scoop)
					# Cab
					var cab := CSGBox3D.new()
					cab.size = Vector3(base_size.x * 0.45, base_size.y * 0.25, base_size.z * 0.22)
					cab.position = Vector3(0, base_size.y * 0.25, base_size.z * 0.18)
					cab.material = dark_mat
					root.add_child(cab)
					# Windshield
					var windshield := CSGBox3D.new()
					windshield.size = Vector3(base_size.x * 0.35, base_size.y * 0.12, 0.04)
					windshield.position = Vector3(0, base_size.y * 0.28, base_size.z * 0.3)
					windshield.material = glow_mat
					root.add_child(windshield)
				_:
					var body := CSGBox3D.new()
					body.size = Vector3(base_size.x * 0.55, base_size.y * 0.5, base_size.z * 0.6)
					body.material = base_mat
					root.add_child(body)

		_:  # Default fallback
			var body := CSGBox3D.new()
			body.size = base_size
			body.material = base_mat
			root.add_child(body)

	return root


func _spawn_unit(faction_id: int, position: Vector3, unit_type: String = "soldier") -> Dictionary:
	var type_data: Dictionary = UNIT_TYPES.get(unit_type, UNIT_TYPES["soldier"])

	# Check if spawn position is blocked by building and find clear spot
	var spawn_pos := position
	if _city_renderer != null and _city_renderer.is_position_blocked(position, 2.0):
		# Try to find a nearby clear position
		var offsets: Array[Vector3] = [Vector3(5, 0, 0), Vector3(-5, 0, 0), Vector3(0, 0, 5), Vector3(0, 0, -5),
					   Vector3(5, 0, 5), Vector3(-5, 0, 5), Vector3(5, 0, -5), Vector3(-5, 0, -5),
					   Vector3(10, 0, 0), Vector3(-10, 0, 0), Vector3(0, 0, 10), Vector3(0, 0, -10)]
		for offset in offsets:
			var test_pos: Vector3 = position + offset
			if not _city_renderer.is_position_blocked(test_pos, 2.0):
				spawn_pos = test_pos
				break

	# Create procedural bot visual based on faction and unit type
	var mesh := _create_procedural_bot(faction_id, unit_type, type_data)
	mesh.position = spawn_pos
	mesh.position.y = type_data.size.y / 2.0
	_unit_container.add_child(mesh)

	# Create health bar
	var health_bar := _create_health_bar(faction_id)
	_health_bar_container.add_child(health_bar)

	# Assign unique ID for faction mechanics tracking
	var unit_id := _next_unit_id
	_next_unit_id += 1

	# Get faction modifiers (defaults to 1.0 for all stats if not defined)
	var faction_mods: Dictionary = FACTION_STAT_MODIFIERS.get(faction_id, {})
	var health_mod: float = faction_mods.get("health", 1.0)
	var damage_mod: float = faction_mods.get("damage", 1.0)
	var speed_mod: float = faction_mods.get("speed", 1.0)
	var attack_speed_mod: float = faction_mods.get("attack_speed", 1.0)
	var range_mod: float = faction_mods.get("range", 1.0)
	var splash_mod: float = faction_mods.get("splash_radius", 1.0)

	# Apply faction modifiers to base stats
	var final_health: float = type_data.health * health_mod
	var final_damage: float = type_data.damage * damage_mod
	var final_range: float = type_data.range * range_mod
	var base_attack_speed: float = type_data.get("attack_speed", 1.0)
	var final_attack_speed: float = base_attack_speed * attack_speed_mod
	var base_speed: float = randf_range(type_data.speed_min, type_data.speed_max)
	var final_speed: float = base_speed * speed_mod

	# Calculate splash damage properties (only for units with splash)
	var base_splash: float = type_data.get("splash_radius", 0.0)
	var final_splash: float = base_splash * splash_mod
	var splash_falloff: float = type_data.get("splash_falloff", 0.5)

	# Create unit data with faction-modified stats
	var unit := {
		"id": unit_id,
		"mesh": mesh,
		"health_bar": health_bar,
		"faction_id": faction_id,
		"unit_type": unit_type,
		"health": final_health,
		"max_health": final_health,
		"damage": final_damage,
		"attack_range": final_range,
		"attack_speed": final_attack_speed,  # Attacks per second
		"splash_radius": final_splash,        # AOE damage radius (0 = no splash)
		"splash_falloff": splash_falloff,     # Damage multiplier at edge
		"armor": 0.0,
		"target_pos": spawn_pos,
		"target_enemy": null,
		"speed": final_speed,
		"attack_cooldown": 0.0,
		"is_selected": false,
		"is_dead": false,
		"xp": 0.0,
		"veterancy_level": 0,
		"veterancy_indicator": null,  # Visual stars/chevrons above unit
		"ree_cost": PRODUCTION_COSTS.get(unit_type, 30.0)  # Track cost for wreckage
	}

	# Add harvester-specific properties
	if unit_type == "harvester":
		unit["is_harvester"] = true
		unit["harvester_state"] = HarvesterState.IDLE
		unit["carried_ree"] = 0.0
		unit["carry_capacity"] = type_data.get("carry_capacity", 50.0)
		unit["harvest_rate"] = type_data.get("harvest_rate", 10.0)
		unit["target_wreckage"] = null

	_units.append(unit)
	GameStateManager.record_unit_created(faction_id)
	_track_stat(faction_id, "units_produced")

	# Award Hive Mind Engineering XP for production (varies by unit type)
	var eng_xp_2: float = 20.0  # Base for light
	if unit_type == "medium":
		eng_xp_2 = 40.0
	elif unit_type == "heavy":
		eng_xp_2 = 80.0
	elif unit_type == "harvester":
		eng_xp_2 = 30.0
	_award_faction_xp(faction_id, ExperiencePool.Category.ENGINEERING, eng_xp_2)

	# Register with faction mechanics system for ability bonuses
	if _faction_mechanics != null:
		var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
		if faction_str != "":
			_faction_mechanics.register_unit(unit_id, faction_str, 0.0)
			_faction_mechanics.update_position(unit_id, position)

	# Register faction-specific abilities
	if faction_id == _player_faction and _fractal_movement != null:
		_fractal_movement.register_unit(unit_id)
	if faction_id == 3 and _acrobatic_strike != null:
		_acrobatic_strike.register_unit(unit_id)
	if faction_id == 4 and _coordinated_barrage != null:
		_coordinated_barrage.register_unit(unit_id)

	# Register with MultiMesh rendering system for batched draw calls
	if _multimesh_renderer != null and _use_multimesh_rendering:
		# Map faction_id to MultiMeshRenderer faction constants (0-4)
		var mm_faction_id := faction_id - 1  # main.gd uses 1-5, MultiMesh uses 0-4
		mm_faction_id = clampi(mm_faction_id, 0, 4)
		# Map unit_type to MultiMesh mesh type
		var mm_unit_type: String
		match unit_type:
			"scout": mm_unit_type = "drone" if faction_id == 1 else "grunt"
			"soldier": mm_unit_type = "soldier"
			"tank": mm_unit_type = "heavy"
			"harvester": mm_unit_type = "worker"
			_: mm_unit_type = "soldier"
		_multimesh_renderer.register_unit(unit_id, mm_faction_id, mm_unit_type, mesh.global_transform)
		# Hide individual mesh - MultiMesh handles rendering
		mesh.visible = false

	# Register with LOD system for visual detail management
	if _lod_system != null:
		_lod_system.register_unit(unit_id, spawn_pos)

	# Register with performance tier system for AI update throttling
	if _performance_tier_system != null and _use_performance_tiers:
		_performance_tier_system.register_unit(unit_id)

	return unit


func _create_health_bar(faction_id: int) -> Node3D:
	var bar := Node3D.new()

	# Background (red)
	var bg := CSGBox3D.new()
	bg.size = Vector3(2.0, 0.2, 0.1)
	bg.position.y = 0.1
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.3, 0.1, 0.1)
	bg.material = bg_mat
	bar.add_child(bg)

	# Foreground (green/faction color)
	var fg := CSGBox3D.new()
	fg.name = "Fill"
	fg.size = Vector3(2.0, 0.2, 0.1)
	fg.position.y = 0.1
	fg.position.z = 0.05
	var fg_mat := StandardMaterial3D.new()
	fg_mat.albedo_color = Color(0.2, 0.8, 0.2) if faction_id == _player_faction else FACTION_COLORS.get(faction_id, Color.WHITE)
	fg.material = fg_mat
	bar.add_child(fg)

	return bar


## Update visibility culling for all units based on camera frustum.
## Units outside the camera view are hidden to save rendering cost.
## This is a HUGE performance win - CSG nodes are expensive to render.
func _update_visibility_culling() -> void:
	if not _use_frustum_culling:
		return

	# Calculate camera frustum bounds in world space (top-down RTS view)
	var cam_pos := camera.global_position
	var cam_target := _camera_look_at
	var cam_height := cam_pos.y

	# Estimate visible area based on camera height and FOV
	# Higher camera = larger visible area
	var fov_factor := tan(deg_to_rad(camera.fov / 2.0))
	var visible_width := cam_height * fov_factor * 2.2  # Wider for RTS
	var visible_depth := cam_height * fov_factor * 1.4  # Less deep due to angle

	# Add margin for smooth culling at edges
	var margin := _frustum_margin
	var min_x := cam_target.x - visible_width - margin
	var max_x := cam_target.x + visible_width + margin
	var min_z := cam_target.z - visible_depth - margin
	var max_z := cam_target.z + visible_depth + margin

	# Cache bounds for other systems
	_frustum_bounds = [min_x, max_x, min_z, max_z]

	# Reset stats
	_visible_unit_count = 0
	_culled_unit_count = 0

	# Update visibility for each unit
	for unit in _units:
		if unit.is_dead:
			continue

		var mesh: Node3D = unit.mesh
		if not is_instance_valid(mesh):
			continue

		var pos := mesh.global_position
		var dist_to_camera := pos.distance_to(cam_target)

		# Check if unit is within frustum bounds AND within max render distance
		var in_frustum := pos.x >= min_x and pos.x <= max_x and pos.z >= min_z and pos.z <= max_z
		var in_range := dist_to_camera <= _max_render_distance
		var should_be_visible := in_frustum and in_range

		# Update mesh visibility
		if mesh.visible != should_be_visible:
			mesh.visible = should_be_visible

			# Also hide/show health bar
			if unit.has("health_bar") and is_instance_valid(unit.health_bar):
				unit.health_bar.visible = should_be_visible

			# Also hide/show selection ring
			if unit.has("selection_ring") and is_instance_valid(unit.selection_ring):
				unit.selection_ring.visible = should_be_visible and unit.get("is_selected", false)

			# Also hide/show stance indicator
			if unit.has("stance_indicator") and is_instance_valid(unit.stance_indicator):
				unit.stance_indicator.visible = should_be_visible

		# Track stats
		if should_be_visible:
			_visible_unit_count += 1
		else:
			_culled_unit_count += 1


## Check if a world position is within the current camera frustum.
func _is_position_visible(pos: Vector3) -> bool:
	if not _use_frustum_culling:
		return true
	return pos.x >= _frustum_bounds[0] and pos.x <= _frustum_bounds[1] and \
		   pos.z >= _frustum_bounds[2] and pos.z <= _frustum_bounds[3]


func _update_units(delta: float) -> void:
	for unit in _units:
		if unit.is_dead:
			continue

		var mesh: Node3D = unit.mesh
		if not is_instance_valid(mesh):
			continue

		# Update attack cooldown (always - combat critical)
		unit.attack_cooldown = maxf(0.0, unit.attack_cooldown - delta)

		# Check performance tier - skip AI updates for units far from combat
		var unit_id: int = unit.get("id", 0)
		var skip_ai_update := false
		if _performance_tier_system != null and _use_performance_tiers and unit_id > 0:
			if not _performance_tier_system.should_update(unit_id):
				skip_ai_update = true

		# Initialize navigation fields if missing
		if not unit.has("nav_waypoint"):
			unit["nav_waypoint"] = Vector3.ZERO
			unit["nav_stuck_time"] = 0.0
			unit["nav_last_pos"] = mesh.position
			unit["nav_recalc_timer"] = 0.0

		# Skip AI decision-making if performance tier says so (movement still happens)
		if skip_ai_update:
			# Still do movement towards existing target, just don't recalculate
			_update_unit_movement_only(unit, delta)
			continue

		# Check for retreat behavior (low health or outnumbered)
		var retreat_pos: Variant = _check_retreat_needed(unit)
		if retreat_pos != null:
			unit["is_retreating"] = true
			unit.target_pos = retreat_pos
			unit.target_enemy = null  # Stop attacking, focus on escaping
		else:
			unit["is_retreating"] = false

		# Get attack_move state (defaults to true for AI factions)
		var is_attack_move: bool = unit.get("attack_move", unit.faction_id != _player_faction)

		# Throttle target searches - only search every 0.3s per unit for performance
		var target_search_timer: float = unit.get("target_search_timer", 0.0) - delta
		unit["target_search_timer"] = target_search_timer

		# Find target if none - behavior depends on attack_move mode
		var needs_target: bool = unit.target_enemy == null or not _is_valid_target(unit.target_enemy)
		if needs_target and target_search_timer <= 0.0:
			unit["target_search_timer"] = 0.3  # Throttle: only search every 0.3 seconds
			if is_attack_move:
				# Attack-move: actively seek enemies
				unit.target_enemy = _find_nearest_enemy(unit)
			elif unit.faction_id != _player_faction:
				# AI factions always seek targets
				unit.target_enemy = _find_nearest_enemy(unit)
			# Regular move for player: only engage if directly threatened (very close)
			elif unit.faction_id == _player_faction:
				var threat: Variant = _find_nearby_threat(unit, ATTACK_RANGE * 0.5)
				if threat != null:
					unit.target_enemy = threat

		# Movement behavior - determine final target
		var final_target: Vector3 = unit.target_pos

		if unit.target_enemy != null and _is_valid_target(unit.target_enemy):
			var enemy_pos: Vector3 = unit.target_enemy.mesh.position
			var dist := mesh.position.distance_to(enemy_pos)
			var unit_range: float = unit.get("attack_range", ATTACK_RANGE)

			if dist > unit_range:
				# Attack-move: chase enemy but don't stray too far from destination
				if is_attack_move and unit.faction_id == _player_faction:
					var dist_to_dest := mesh.position.distance_to(unit.target_pos)
					if dist_to_dest < ATTACK_RANGE * 3:
						final_target = enemy_pos  # Chase if close to destination
					else:
						final_target = unit.target_pos  # Keep moving to destination
						unit.target_enemy = null  # Drop chase
				else:
					final_target = enemy_pos
			else:
				final_target = mesh.position  # In range, stop to fire
		else:
			# No enemy, continue to destination or wander
			var current_target: Vector3 = unit.target_pos
			var to_current := current_target - mesh.position
			to_current.y = 0

			# Check if reached attack-move destination
			if is_attack_move and unit.faction_id == _player_faction and to_current.length() < 3.0:
				unit["attack_move"] = false  # Clear attack-move mode when reached

			if to_current.length() < 3.0:
				if unit.faction_id == _player_faction:
					# Player units hold position when reaching destination
					final_target = mesh.position
				else:
					# AI wanders towards player base
					final_target = FACTORY_POSITIONS[1] + Vector3(randf_range(-30, 30), 0, randf_range(-30, 30))
					unit.target_pos = final_target

		# Check for siege lock
		var siege_locked: bool = unit.get("siege_locked", false)

		# Navigation logic
		var move_target: Vector3 = final_target
		var to_final := final_target - mesh.position
		to_final.y = 0

		if to_final.length() > 1.0 and not siege_locked and _city_renderer != null:
			# Update stuck detection
			var last_pos: Vector3 = unit["nav_last_pos"]
			var dist_moved: float = mesh.position.distance_to(last_pos)
			var recalc_timer: float = unit["nav_recalc_timer"] + delta
			unit["nav_recalc_timer"] = recalc_timer

			var stuck_time: float = unit["nav_stuck_time"]
			if dist_moved < 0.5 * delta * unit.speed:
				stuck_time += delta
				unit["nav_stuck_time"] = stuck_time
			else:
				unit["nav_stuck_time"] = 0.0
				unit["nav_last_pos"] = mesh.position

			# Check if we need a waypoint (path blocked or stuck)
			var waypoint: Vector3 = unit["nav_waypoint"]

			# Recalculate path periodically or when stuck
			if recalc_timer > 1.0 or stuck_time > 0.3:
				unit["nav_recalc_timer"] = 0.0

				# Check if direct path is clear
				if not _city_renderer.has_clear_path(mesh.position, final_target, 1.5):
					waypoint = _city_renderer.find_detour_waypoint(mesh.position, final_target, 2.0)
					unit["nav_waypoint"] = waypoint

					# If very stuck, try a random offset
					if stuck_time > 1.0:
						var random_offset := Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
						var escape_pos: Vector3 = mesh.position + random_offset
						if not _city_renderer.is_position_blocked(escape_pos, 1.5):
							unit["nav_waypoint"] = escape_pos
							waypoint = escape_pos
						unit["nav_stuck_time"] = 0.0
				else:
					unit["nav_waypoint"] = Vector3.ZERO
					waypoint = Vector3.ZERO

			# Use waypoint if we have one
			if waypoint != Vector3.ZERO:
				var to_waypoint: Vector3 = waypoint - mesh.position
				to_waypoint.y = 0
				if to_waypoint.length() > 2.0:
					move_target = waypoint
				else:
					# Reached waypoint, clear it
					unit["nav_waypoint"] = Vector3.ZERO
					move_target = final_target

		# Track previous position for "run and gun" mechanic
		var prev_pos: Vector3 = mesh.position

		# Move toward target (unless siege locked)
		var to_target := move_target - mesh.position
		to_target.y = 0
		if to_target.length() > 1.0 and not siege_locked:
			var dir := to_target.normalized()
			var move_speed: float = _get_unit_speed(unit)  # Apply veterancy speed bonus

			# Apply Overclock speed boost for OptiForge units (faction 2)
			# Note: unit_id already declared at start of loop for performance tier check
			if unit_id > 0 and unit.faction_id == 2 and _overclock_unit != null:
				if _overclock_unit.is_overclocked(unit_id):
					move_speed *= _overclock_unit.get_speed_multiplier(unit_id)

			# Apply retreat speed bonus (units run faster when fleeing)
			if unit.get("is_retreating", false):
				move_speed *= RETREAT_SPEED_BONUS

			# Calculate new position
			var new_pos: Vector3 = mesh.position + dir * move_speed * delta

			# Check building collision and adjust position
			if _city_renderer != null:
				new_pos = _city_renderer.get_collision_adjusted_position(mesh.position, new_pos, 1.5)

			mesh.position = new_pos

		mesh.position.y = 1.0

		# Track if unit moved this frame (for run and gun accuracy penalty)
		var dist_moved: float = mesh.position.distance_to(prev_pos)
		unit["is_moving"] = dist_moved > 0.1  # Moving if traveled more than 0.1 units

		# Update MultiMesh transform for batched rendering
		if _multimesh_renderer != null and _use_multimesh_rendering and dist_moved > 0.01:
			var unit_id_mm: int = unit.get("id", 0)
			if unit_id_mm > 0:
				_multimesh_renderer.mark_dirty(unit_id_mm, mesh.global_transform)

		# Update LOD system with new unit position
		if _lod_system != null and dist_moved > 0.01:
			var unit_id_lod: int = unit.get("id", 0)
			if unit_id_lod > 0:
				_lod_system.update_unit_position(unit_id_lod, mesh.position)

		# Update health bar position
		if is_instance_valid(unit.health_bar):
			unit.health_bar.position = mesh.position + Vector3(0, 2.5, 0)
			unit.health_bar.rotation.y = camera.rotation.y if camera else 0


## Simplified unit movement update for performance-throttled units.
## Moves unit towards existing target without recalculating AI decisions.
func _update_unit_movement_only(unit: Dictionary, delta: float) -> void:
	var mesh: Node3D = unit.mesh
	if not is_instance_valid(mesh):
		return

	var prev_pos: Vector3 = mesh.position
	var move_target: Vector3 = unit.target_pos

	# If unit has an existing enemy target, move towards it
	if unit.target_enemy != null and _is_valid_target(unit.target_enemy):
		var enemy_pos: Vector3 = unit.target_enemy.mesh.position
		var dist := mesh.position.distance_to(enemy_pos)
		var unit_range: float = unit.get("attack_range", ATTACK_RANGE)
		if dist > unit_range:
			move_target = enemy_pos

	# Move toward target
	var to_target := move_target - mesh.position
	to_target.y = 0
	var siege_locked: bool = unit.get("siege_locked", false)

	if to_target.length() > 1.0 and not siege_locked:
		var dir := to_target.normalized()
		var move_speed: float = _get_unit_speed(unit)
		var new_pos: Vector3 = mesh.position + dir * move_speed * delta

		# Check building collision
		if _city_renderer != null:
			new_pos = _city_renderer.get_collision_adjusted_position(mesh.position, new_pos, 1.5)

		mesh.position = new_pos

	mesh.position.y = 1.0

	# Track movement
	var dist_moved: float = mesh.position.distance_to(prev_pos)
	unit["is_moving"] = dist_moved > 0.1

	# Update MultiMesh transform
	if _multimesh_renderer != null and _use_multimesh_rendering and dist_moved > 0.01:
		var unit_id: int = unit.get("id", 0)
		if unit_id > 0:
			_multimesh_renderer.mark_dirty(unit_id, mesh.global_transform)

	# Update LOD position
	if _lod_system != null and dist_moved > 0.01:
		var unit_id_lod: int = unit.get("id", 0)
		if unit_id_lod > 0:
			_lod_system.update_unit_position(unit_id_lod, mesh.position)

	# Update health bar position
	if is_instance_valid(unit.health_bar):
		unit.health_bar.position = mesh.position + Vector3(0, 2.5, 0)
		unit.health_bar.rotation.y = camera.rotation.y if camera else 0


## Heal units near their faction's factory.
func _update_unit_healing(delta: float) -> void:
	for unit in _units:
		if unit.is_dead:
			continue
		if not is_instance_valid(unit.mesh):
			continue

		# Check if unit is damaged
		if unit.health >= unit.max_health:
			continue

		# Check distance to friendly factory
		var factory_id: int = unit.faction_id
		if not _factories.has(factory_id):
			continue

		var factory: Dictionary = _factories[factory_id]
		if factory.is_destroyed:
			continue

		var dist: float = unit.mesh.position.distance_to(factory.position)
		if dist <= FACTORY_HEAL_RADIUS:
			# Heal the unit
			var heal_amount: float = FACTORY_HEAL_RATE * delta
			unit.health = minf(unit.health + heal_amount, unit.max_health)

			# Update health bar
			if is_instance_valid(unit.health_bar):
				var fill: Node3D = unit.health_bar.get_node_or_null("Fill")
				if fill:
					var health_pct: float = unit.health / unit.max_health
					fill.scale.x = health_pct
					fill.position.x = -(1.0 - health_pct)


## Update special unit behaviors (patrol, guard)
func _update_unit_behaviors() -> void:
	for unit in _units:
		if unit.is_dead:
			continue
		if not is_instance_valid(unit.mesh):
			continue

		# Process command queue (shift-queued commands)
		_process_command_queue(unit)

		# Update patrol behavior
		_update_patrol_behavior(unit)

		# Update guard behavior
		_update_guard_behavior(unit)


## Update faction mechanics system with unit positions and process abilities
func _update_faction_mechanics(delta: float) -> void:
	if _faction_mechanics == null:
		return

	# Batch update all unit positions
	var positions: Dictionary = {}
	for unit in _units:
		if unit.is_dead:
			continue
		if is_instance_valid(unit.mesh):
			var unit_id: int = unit.get("id", 0)
			if unit_id > 0:
				positions[unit_id] = unit.mesh.position

	_faction_mechanics.update_positions(positions)
	_faction_mechanics.update(delta)

	# Update Phase Shift ability (cooldown, duration timers)
	if _phase_shift != null:
		_phase_shift.update(delta)

	# Update Overclock ability (cooldown, duration timers, self-damage)
	if _overclock_unit != null:
		_overclock_unit.update(delta)

	# Update Siege Formation ability (check for movement, update timers)
	if _siege_formation != null:
		_siege_formation.update(delta)

	# Update Nano Replication (passive healing for Aether Swarm)
	if _nano_replication != null:
		# Get positions of Aether Swarm units only
		var aether_positions: Dictionary = {}
		for unit in _units:
			if unit.is_dead or unit.faction_id != _player_faction:
				continue
			if is_instance_valid(unit.mesh):
				var unit_id: int = unit.get("id", 0)
				if unit_id > 0:
					aether_positions[unit_id] = unit.mesh.position
		_nano_replication.update(delta, aether_positions)

	# Update Ether Cloak ability (duration timers)
	if _ether_cloak != null:
		_ether_cloak.update(delta)

	# Update Acrobatic Strike ability (leap progress, landing damage)
	if _acrobatic_strike != null:
		_acrobatic_strike.update(delta)

	# Update Coordinated Barrage ability (mark duration, damage tracking)
	if _coordinated_barrage != null:
		_coordinated_barrage.update(delta)

	# Update Fractal Movement ability (track direction changes for Aether Swarm)
	if _fractal_movement != null:
		var aether_positions: Dictionary = {}
		for unit in _units:
			if unit.faction_id != _player_faction or unit.is_dead:
				continue
			if is_instance_valid(unit.mesh):
				var unit_id: int = unit.get("id", 0)
				if unit_id > 0:
					aether_positions[unit_id] = unit.mesh.position
		_fractal_movement.update(delta, aether_positions)


func _update_combat(delta: float) -> void:
	for unit in _units:
		if unit.is_dead or unit.attack_cooldown > 0:
			continue

		if unit.target_enemy != null and _is_valid_target(unit.target_enemy):
			var mesh: Node3D = unit.mesh
			var enemy_mesh: Node3D = unit.target_enemy.mesh
			var dist := mesh.position.distance_to(enemy_mesh.position)
			var unit_range: float = unit.get("attack_range", ATTACK_RANGE)

			# Apply Siege Formation range boost for LogiBots (faction 4)
			var unit_id: int = unit.get("id", 0)
			if unit_id > 0 and unit.faction_id == 4 and _siege_formation != null:
				if _siege_formation.is_fully_deployed(unit_id):
					unit_range = _siege_formation.apply_to_range(unit_id, unit_range)

			if dist <= unit_range:
				_fire_projectile(unit, unit.target_enemy)
				# Calculate cooldown from unit's attack_speed (attacks per second) with XP bonus
				var attack_speed: float = unit.get("attack_speed", 1.0)
				var xp_attack_mult: float = _get_faction_xp_attack_speed_mult(unit.faction_id)
				unit.attack_cooldown = 1.0 / maxf(attack_speed * xp_attack_mult, 0.1)  # Prevent division by zero


func _update_factory_combat(delta: float) -> void:
	# Units attack enemy factories when no nearby enemies
	for unit in _units:
		if unit.is_dead or unit.attack_cooldown > 0:
			continue

		# Only attack factory if no enemy target
		if unit.target_enemy != null and _is_valid_target(unit.target_enemy):
			continue

		var mesh: Node3D = unit.mesh
		if not is_instance_valid(mesh):
			continue

		# Find nearest enemy factory
		var nearest_factory: Variant = null
		var nearest_dist := INF

		for faction_id in _factories:
			if faction_id == unit.faction_id:
				continue

			var factory: Dictionary = _factories[faction_id]
			if factory.is_destroyed:
				continue

			var factory_pos: Vector3 = factory.position + Vector3(0, 5, 0)
			var dist: float = mesh.position.distance_to(factory_pos)

			if dist < nearest_dist:
				nearest_dist = dist
				nearest_factory = factory

		# Attack factory if in range (use unit's attack range)
		var unit_range: float = unit.get("attack_range", ATTACK_RANGE)
		if nearest_factory != null and nearest_dist <= unit_range * 1.5:
			_fire_projectile_at_factory(unit, nearest_factory)
			# Calculate cooldown from unit's attack_speed with XP bonus
			var attack_speed: float = unit.get("attack_speed", 1.0)
			var xp_attack_mult: float = _get_faction_xp_attack_speed_mult(unit.faction_id)
			unit.attack_cooldown = 1.0 / maxf(attack_speed * xp_attack_mult, 0.1)


func _fire_projectile_at_factory(from_unit: Dictionary, factory: Dictionary) -> void:
	var start_pos: Vector3 = from_unit.mesh.position + Vector3(0, 1.5, 0)
	var end_pos: Vector3 = factory.position + Vector3(0, 5, 0)

	var proj_mesh := CSGSphere3D.new()
	proj_mesh.radius = 0.4
	proj_mesh.position = start_pos

	var proj_mat := StandardMaterial3D.new()
	proj_mat.albedo_color = FACTION_COLORS.get(from_unit.faction_id, Color.WHITE)
	proj_mat.emission_enabled = true
	proj_mat.emission = FACTION_COLORS.get(from_unit.faction_id, Color.WHITE)
	proj_mat.emission_energy_multiplier = 2.0
	proj_mesh.material = proj_mat

	_projectile_container.add_child(proj_mesh)

	# Create projectile trail
	var trail := _create_projectile_trail(from_unit.faction_id)
	_projectile_container.add_child(trail)

	var projectile := {
		"mesh": proj_mesh,
		"trail": trail,
		"trail_positions": [start_pos],
		"target": null,
		"target_factory": factory,
		"from_faction": from_unit.faction_id,
		"direction": (end_pos - start_pos).normalized(),
		"speed": PROJECTILE_SPEED,
		"damage": UNIT_DAMAGE * 2,  # Extra damage to factories
		"lifetime": 3.0
	}
	_projectiles.append(projectile)

	# Spawn muzzle flash
	_spawn_muzzle_flash(start_pos, from_unit.faction_id)

	# Play laser fire sound (throttled)
	if _should_play_sound():
		_play_laser_sound(start_pos)


func _update_factory_health_bars() -> void:
	for faction_id in _factories:
		var factory: Dictionary = _factories[faction_id]
		if factory.is_destroyed:
			continue

		if is_instance_valid(factory.health_bar):
			factory.health_bar.position = factory.position + Vector3(0, 12, 0)

			var fill: Node3D = factory.health_bar.get_node_or_null("Fill")
			if fill:
				var health_pct := maxf(0.0, factory.health / factory.max_health)
				fill.scale.x = health_pct
				fill.position.x = -5.0 * (1.0 - health_pct)


## ========== FACTORY CONSTRUCTION SYSTEM ==========

## Handle construction started event
func _on_construction_started(site_id: int, position: Vector3, faction_id: int) -> void:
	# Create construction site visual (scaffold)
	var visual := Node3D.new()
	visual.name = "ConstructionSite_%d" % site_id
	visual.position = position

	# Create scaffold frame
	var scaffold := _create_construction_scaffold(faction_id)
	visual.add_child(scaffold)

	# Create progress bar
	var progress_bar := _create_construction_progress_bar(faction_id)
	progress_bar.position.y = 15.0
	visual.add_child(progress_bar)

	_effects_container.add_child(visual)
	_construction_sites[site_id] = visual

	print("Construction started: site %d at %s for faction %d" % [site_id, position, faction_id])


## Create scaffold visual for construction site
func _create_construction_scaffold(faction_id: int) -> Node3D:
	var scaffold := Node3D.new()
	scaffold.name = "Scaffold"

	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	# Create wireframe cube representing the factory being built
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = faction_color * 0.7
	frame_mat.emission_enabled = true
	frame_mat.emission = faction_color
	frame_mat.emission_energy_multiplier = 1.0
	frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	frame_mat.albedo_color.a = 0.6

	# Create vertical beams at corners
	for corner in [Vector3(-25, 0, -25), Vector3(25, 0, -25), Vector3(-25, 0, 25), Vector3(25, 0, 25)]:
		var beam := CSGBox3D.new()
		beam.size = Vector3(2, 50, 2)
		beam.position = corner + Vector3(0, 25, 0)
		beam.material = frame_mat
		scaffold.add_child(beam)

	# Create horizontal beams at top
	for i in range(4):
		var beam := CSGBox3D.new()
		if i < 2:
			beam.size = Vector3(50, 2, 2)
			beam.position = Vector3(0, 50, -25 if i == 0 else 25)
		else:
			beam.size = Vector3(2, 2, 50)
			beam.position = Vector3(-25 if i == 2 else 25, 50, 0)
		beam.material = frame_mat
		scaffold.add_child(beam)

	return scaffold


## Create progress bar for construction site
func _create_construction_progress_bar(faction_id: int) -> Node3D:
	var bar := Node3D.new()
	bar.name = "ProgressBar"

	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	# Background
	var bg := CSGBox3D.new()
	bg.size = Vector3(12, 1, 0.5)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.8)
	bg.material = bg_mat
	bar.add_child(bg)

	# Fill
	var fill := CSGBox3D.new()
	fill.name = "Fill"
	fill.size = Vector3(12, 1, 0.5)
	fill.position.z = 0.1
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = faction_color
	fill_mat.emission_enabled = true
	fill_mat.emission = faction_color
	fill_mat.emission_energy_multiplier = 2.0
	fill.material = fill_mat
	fill.scale.x = 0.0  # Start empty
	bar.add_child(fill)

	return bar


## Handle construction progress update
func _on_construction_progress(site_id: int, progress: float) -> void:
	if not _construction_sites.has(site_id):
		return

	var visual: Node3D = _construction_sites[site_id]
	var progress_bar: Node3D = visual.get_node_or_null("ProgressBar")
	if progress_bar:
		var fill: CSGBox3D = progress_bar.get_node_or_null("Fill")
		if fill:
			fill.scale.x = progress
			fill.position.x = -6.0 * (1.0 - progress)


## Handle construction completed
func _on_construction_completed(site_id: int, factory_id: int) -> void:
	if not _construction_sites.has(site_id):
		return

	var visual: Node3D = _construction_sites[site_id]
	var position: Vector3 = visual.position

	# Get site data
	var site: FactoryConstruction.ConstructionSite = _factory_construction.get_site(site_id)
	var faction_id: int = site.faction_id if site else _player_faction

	# Remove construction visual
	visual.queue_free()
	_construction_sites.erase(site_id)

	# Create the actual factory
	_create_new_factory(position, faction_id)

	print("Construction completed: factory at %s for faction %d" % [position, faction_id])


## Create a new factory at position
func _create_new_factory(position: Vector3, faction_id: int) -> void:
	# Create factory node
	var factory_node := CSGBox3D.new()
	factory_node.name = "Factory_%d_%d" % [faction_id, _factories.size()]
	factory_node.size = Vector3(50, 50, 50)
	factory_node.position = position

	var mat := StandardMaterial3D.new()
	mat.albedo_color = FACTION_COLORS.get(faction_id, Color.WHITE)
	mat.emission_enabled = true
	mat.emission = FACTION_COLORS.get(faction_id, Color.WHITE) * 0.3
	mat.emission_energy_multiplier = 1.0
	factory_node.material = mat

	add_child(factory_node)

	# Create health bar
	var health_bar := _create_factory_health_bar(faction_id)
	_health_bar_container.add_child(health_bar)

	# Assign new factory ID (use negative to distinguish from original 4)
	var new_factory_id: int = -(faction_id * 100 + _factories.size())

	_factories[new_factory_id] = {
		"node": factory_node,
		"health_bar": health_bar,
		"name_label": null,
		"health": FACTORY_HEALTH,
		"max_health": FACTORY_HEALTH,
		"faction_id": faction_id,
		"is_destroyed": false,
		"position": position,
		"power_plant_id": -1,
		"district_id": -1,
		"is_powered": true,
		"power_multiplier": 1.0,
		"is_constructed": true  # Mark as player-built
	}

	# Register with mass production if OptiForge
	if faction_id == 2 and _mass_production != null:
		_mass_production.register_factory(new_factory_id)


## Start factory placement mode (called from UI)
func start_factory_placement() -> void:
	if _construction_placement_mode:
		return

	# Check if player can afford
	var can_afford := ResourceManager.get_current_ree(_player_faction) >= FactoryConstruction.FACTORY_REE_COST
	if not can_afford:
		_show_notification("Not enough REE! Need %.0f" % FactoryConstruction.FACTORY_REE_COST)
		return

	# Check factory limit
	var validation := _factory_construction.is_valid_placement(Vector3.ZERO, _player_faction, _player_faction)
	if "Maximum factories" in validation.reason:
		_show_notification(validation.reason)
		return

	_construction_placement_mode = true

	# Create preview ghost
	_construction_preview = CSGBox3D.new()
	_construction_preview.size = Vector3(50, 50, 50)
	var preview_mat := StandardMaterial3D.new()
	preview_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.4)  # Green transparent
	preview_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_construction_preview.material = preview_mat
	add_child(_construction_preview)


## Cancel factory placement mode
func cancel_factory_placement() -> void:
	_construction_placement_mode = false
	if _construction_preview:
		_construction_preview.queue_free()
		_construction_preview = null


## Start factory construction directly at ruins location (right-click shortcut)
func _start_construction_at_ruins(ruins_pos: Vector3) -> void:
	if _factory_construction == null:
		_show_notification("Construction system not available")
		return

	# Check REE resources
	if not ResourceManager or ResourceManager.get_ree(_player_faction) < FactoryConstruction.FACTORY_REE_COST:
		_show_notification("Need %d REE to build factory" % int(FactoryConstruction.FACTORY_REE_COST))
		return

	# Find district at ruins position
	var district_id: int = _get_district_at_position(ruins_pos)
	var district_owner: int = 0
	if district_id >= 0 and district_id < _districts.size():
		district_owner = _districts[district_id].owner

	# Validate placement
	var validation := _factory_construction.is_valid_placement(ruins_pos, _player_faction, district_owner)
	if not validation.valid:
		_show_notification(validation.reason)
		return

	# Consume resources
	if not ResourceManager.consume_ree(_player_faction, FactoryConstruction.FACTORY_REE_COST, "factory_construction"):
		_show_notification("Not enough REE!")
		return

	# Find a builder from selected units to assign
	var builder_id: int = 0
	for unit in _selected_units:
		if unit.get("unit_class", "") == "builder" or unit.get("is_harvester", false):
			builder_id = unit.get("id", 0)
			break

	# Start construction
	var site_id := _factory_construction.start_construction(ruins_pos, _player_faction, district_id, builder_id)

	# Remove the ruins marker since we're building there
	for i in range(_building_ruins.size() - 1, -1, -1):
		if _building_ruins[i].position.distance_to(ruins_pos) < RUINS_PLACEMENT_RADIUS:
			if _building_ruins[i].has("marker"):
				var marker = _building_ruins[i].marker
				if is_instance_valid(marker):
					marker.queue_free()
			_building_ruins.remove_at(i)
			break

	_show_notification("Factory construction started at ruins!")
	_play_ui_sound("notification")

	# Visual feedback
	_spawn_command_text(ruins_pos, "BUILDING", Color(1.0, 0.8, 0.2))


## Update factory placement preview
func _update_factory_placement(mouse_pos: Vector2) -> void:
	if not _construction_placement_mode or not _construction_preview:
		return

	# Raycast to get world position
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return

	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 2000

	# Simple ground plane intersection (y = 0)
	var t: float = -from.y / (to.y - from.y) if abs(to.y - from.y) > 0.001 else 0
	var world_pos := from + (to - from) * t
	world_pos.y = 0

	_construction_preview.position = world_pos

	# Check validity
	var district_id: int = _get_district_at_position(world_pos)
	var district_owner: int = 0
	if district_id >= 0 and district_id < _districts.size():
		district_owner = _districts[district_id].owner

	var validation := _factory_construction.is_valid_placement(world_pos, _player_faction, district_owner)

	# Update preview color
	var mat: StandardMaterial3D = _construction_preview.material
	if validation.valid:
		mat.albedo_color = Color(0.2, 1.0, 0.3, 0.4)  # Green = valid
	else:
		mat.albedo_color = Color(1.0, 0.2, 0.2, 0.4)  # Red = invalid


## Confirm factory placement
func _confirm_factory_placement() -> void:
	if not _construction_placement_mode or not _construction_preview:
		return

	var world_pos: Vector3 = _construction_preview.position

	# Check validity one more time
	var district_id: int = _get_district_at_position(world_pos)
	var district_owner: int = 0
	if district_id >= 0 and district_id < _districts.size():
		district_owner = _districts[district_id].owner

	var validation := _factory_construction.is_valid_placement(world_pos, _player_faction, district_owner)

	if not validation.valid:
		_show_notification(validation.reason)
		return

	# Consume resources
	if not ResourceManager.consume_ree(_player_faction, FactoryConstruction.FACTORY_REE_COST, "factory_construction"):
		_show_notification("Not enough REE!")
		return

	# Start construction (find a builder or start immediately for now)
	var site_id := _factory_construction.start_construction(world_pos, _player_faction, district_id, 0)

	# For now, mark construction as having a virtual builder
	# TODO: Require actual builder units

	cancel_factory_placement()
	_show_notification("Factory construction started!")


## Update factory construction progress
func _update_factory_construction(delta: float) -> void:
	if _factory_construction == null:
		return

	# Update construction and get completed sites
	var completed_sites: Array[int] = _factory_construction.update(delta)

	# Finalize completed constructions
	for site_id in completed_sites:
		var site: FactoryConstruction.ConstructionSite = _factory_construction.get_site(site_id)
		if site:
			# Assign a dummy factory_id (real one created in callback)
			_factory_construction.finalize_construction(site_id, -1)


func _fire_projectile(from_unit: Dictionary, to_unit: Dictionary) -> void:
	var start_pos: Vector3 = from_unit.mesh.position + Vector3(0, 1.5, 0)
	var end_pos: Vector3 = to_unit.mesh.position + Vector3(0, 1.0, 0)
	var unit_damage: float = _get_unit_damage(from_unit)  # Apply veterancy bonus

	# Base 25% miss chance, +25% when moving (Run and Gun penalty)
	var is_miss := false
	var miss_chance: float = 0.25
	if from_unit.get("is_moving", false):
		miss_chance += 0.25  # Run and Gun: 25% accuracy penalty while moving
	if randf() < miss_chance:
		is_miss = true
		var miss_offset := Vector3(
			randf_range(-15.0, 15.0),
			randf_range(-2.0, 5.0),
			randf_range(-15.0, 15.0)
		)
		end_pos += miss_offset

	# Apply Overclock damage boost for OptiForge units (faction 2)
	var unit_id: int = from_unit.get("id", 0)
	if unit_id > 0 and from_unit.faction_id == 2 and _overclock_unit != null:
		if _overclock_unit.is_overclocked(unit_id):
			unit_damage = _overclock_unit.apply_to_damage(unit_id, unit_damage)

	# Apply faction mechanics outgoing damage bonus (SwarmSynergy, SynchronizedStrikes)
	if _faction_mechanics != null:
		if unit_id > 0:
			unit_damage = _faction_mechanics.calculate_outgoing_damage(unit_id, unit_damage)
			# Set attack target for LogiBots synchronized strikes
			var target_id: int = to_unit.get("id", 0)
			if target_id > 0:
				_faction_mechanics.set_attack_target(unit_id, target_id)

	# Get faction projectile style
	var faction_id: int = from_unit.faction_id
	var proj_style: Dictionary = FACTION_PROJECTILE_STYLES.get(faction_id, FACTION_PROJECTILE_STYLES[2])
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)
	var secondary_color: Color = proj_style.get("secondary_color", faction_color)

	# Get unit type modifiers for projectile appearance
	var unit_type: String = from_unit.get("unit_type", "soldier")
	var type_mods: Dictionary = UNIT_TYPE_PROJECTILE_MODS.get(unit_type, {})

	# Scale projectile size based on damage, faction style, and unit type
	var base_size: float = 0.2 + (unit_damage / 100.0) * 0.3
	var faction_size_mult: float = float(proj_style.get("size_mult", 1.0))
	var type_size_mult: float = float(type_mods.get("size_mult", 1.0))
	var proj_size: float = base_size * faction_size_mult * type_size_mult

	var faction_speed_mult: float = float(proj_style.get("speed_mult", 1.0))
	var type_speed_mult: float = float(type_mods.get("speed_mult", 1.0))
	var proj_speed: float = PROJECTILE_SPEED * faction_speed_mult * type_speed_mult

	var emission_mult: float = proj_style.get("emission_mult", 2.0) * type_mods.get("glow_intensity", 1.0)

	# Create projectile visual - unit type can override faction shape
	var proj_mesh: CSGShape3D
	var shape: String = type_mods.get("shape_override", proj_style.get("shape", "sphere"))
	match shape:
		"cylinder":
			# Elongated laser beam shape
			var cyl := CSGCylinder3D.new()
			cyl.radius = proj_size * 0.4
			cyl.height = proj_size * 3.0
			# Rotate to point in direction of travel
			var direction := (end_pos - start_pos).normalized()
			cyl.look_at_from_position(start_pos, start_pos + direction, Vector3.UP)
			cyl.rotate_object_local(Vector3.RIGHT, PI/2)
			proj_mesh = cyl
		"box":
			# Blocky artillery shell shape
			var box := CSGBox3D.new()
			box.size = Vector3(proj_size * 0.8, proj_size * 0.8, proj_size * 1.5)
			box.position = start_pos
			proj_mesh = box
		_:  # Default sphere
			var sphere := CSGSphere3D.new()
			sphere.radius = proj_size
			sphere.position = start_pos
			proj_mesh = sphere

	if not proj_mesh.position.is_equal_approx(start_pos):
		proj_mesh.position = start_pos

	# Create two-tone material with faction colors
	var proj_mat := StandardMaterial3D.new()
	proj_mat.albedo_color = secondary_color
	proj_mat.emission_enabled = true
	proj_mat.emission = faction_color
	proj_mat.emission_energy_multiplier = emission_mult
	proj_mesh.material = proj_mat

	_projectile_container.add_child(proj_mesh)

	# Play weapon fire sound (throttled to avoid audio overload)
	if _should_play_sound():
		_play_laser_sound(start_pos)

	# Create projectile trail if enabled for faction
	var trail: Node3D = null
	if proj_style.get("trail_enabled", true):
		trail = _create_projectile_trail(faction_id)
		_projectile_container.add_child(trail)

	# Get splash damage properties from the firing unit
	var splash_radius: float = from_unit.get("splash_radius", 0.0)
	var splash_falloff: float = from_unit.get("splash_falloff", 0.5)

	var projectile := {
		"mesh": proj_mesh,
		"trail": trail,
		"trail_positions": [start_pos],  # Track past positions for trail
		"target": to_unit if not is_miss else null,  # No target if missed
		"from_faction": faction_id,
		"from_unit_id": unit_id,  # Track attacker for XP awards (not dict to avoid circular refs)
		"direction": (end_pos - start_pos).normalized(),
		"speed": proj_speed,  # Faction-modified speed
		"damage": unit_damage,
		"splash_radius": splash_radius,    # AOE radius (0 = no splash)
		"splash_falloff": splash_falloff,  # Damage multiplier at edge of splash
		"lifetime": 3.0,
		"is_miss": is_miss
	}
	_projectiles.append(projectile)

	# Spawn muzzle flash
	_spawn_muzzle_flash(start_pos, from_unit.faction_id)

	# Play laser fire sound
	_play_laser_sound(start_pos)


## Create a glowing trail for a projectile.
func _create_projectile_trail(faction_id: int) -> Node3D:
	# Use GPU particle trail for better visuals and performance
	var trail := _create_gpu_projectile_trail(faction_id)
	return trail


## Update projectile trail visuals.
## GPU particle trails are self-updating, so we just need to update the position.
func _update_projectile_trail(proj: Dictionary) -> void:
	if proj.has("trail") and is_instance_valid(proj.trail):
		# Move trail emitter to follow projectile
		proj.trail.global_position = proj.mesh.global_position


## Spawn a muzzle flash effect at position with faction-specific styling.
func _spawn_muzzle_flash(pos: Vector3, faction_id: int) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)
	var proj_style: Dictionary = FACTION_PROJECTILE_STYLES.get(faction_id, {})
	var emission_mult: float = proj_style.get("emission_mult", 2.0)
	var size_mult: float = proj_style.get("size_mult", 1.0)

	# Faction-specific flash size (larger for heavy hitters, smaller for rapid fire)
	var base_radius := 0.6 + (size_mult * 0.4)
	var expand_scale := 1.5 + (size_mult * 1.5)

	# Create a small bright sphere that quickly fades
	var flash := CSGSphere3D.new()
	flash.radius = base_radius
	flash.position = pos

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission = faction_color
	mat.emission_energy_multiplier = 3.0 + emission_mult
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material = mat

	_effects_container.add_child(flash)

	# Faction-specific fade timing (faster for rapid fire, slower for heavy shots)
	var fade_time := 0.08 / maxf(size_mult, 0.5)

	# Quick expand and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector3.ONE * expand_scale, fade_time * 0.8)
	tween.tween_property(mat, "albedo_color:a", 0.0, fade_time)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, fade_time)
	tween.chain().tween_callback(flash.queue_free)


## Clean up a projectile's trail.
func _cleanup_projectile_trail(proj: Dictionary) -> void:
	if proj.has("trail") and is_instance_valid(proj.trail):
		proj.trail.queue_free()


## PERFORMANCE OPTIMIZED: Uses distance_squared_to() to avoid sqrt() calls.
## Pre-computed squared thresholds: 1.5² = 2.25, 12² = 144
const UNIT_HIT_DIST_SQ := 2.25  # 1.5 * 1.5
const FACTORY_HIT_DIST_SQ := 144.0  # 12 * 12

func _update_projectiles(delta: float) -> void:
	var to_remove: Array = []

	for proj in _projectiles:
		if not is_instance_valid(proj.mesh):
			_cleanup_projectile_trail(proj)
			to_remove.append(proj)
			continue

		proj.lifetime -= delta
		if proj.lifetime <= 0:
			_cleanup_projectile_trail(proj)
			proj.mesh.queue_free()
			to_remove.append(proj)
			continue

		# Move projectile
		proj.mesh.position += proj.direction * proj.speed * delta

		# Visibility culling for projectiles - hide if off-screen
		if _use_frustum_culling:
			var proj_visible := _is_position_visible(proj.mesh.position)
			if proj.mesh.visible != proj_visible:
				proj.mesh.visible = proj_visible

		# Update trail visual
		_update_projectile_trail(proj)

		# Check collision with unit target (OPTIMIZED: squared distance)
		if proj.target != null and not proj.target.is_dead:
			if is_instance_valid(proj.target.mesh):
				var dist_sq: float = proj.mesh.position.distance_squared_to(proj.target.mesh.position)
				if dist_sq < UNIT_HIT_DIST_SQ:
					# Look up attacker for XP awards
					var attacker: Dictionary = _get_unit_by_id(proj.get("from_unit_id", -1))
					_damage_unit(proj.target, proj.damage, proj.from_faction, attacker)

					# Apply splash damage to nearby enemies
					var splash_radius: float = proj.get("splash_radius", 0.0)
					if splash_radius > 0:
						_apply_splash_damage(proj.mesh.position, proj.damage, splash_radius,
							proj.get("splash_falloff", 0.5), proj.from_faction, proj.target, attacker)

					# Spawn impact effect
					var is_heavy: bool = proj.get("splash_radius", 0.0) > 0
					_spawn_impact_effect(proj.mesh.position, proj.from_faction, is_heavy)
					_play_hit_sound(proj.mesh.position)
					_cleanup_projectile_trail(proj)
					proj.mesh.queue_free()
					to_remove.append(proj)
					continue

		# Check collision with factory target (OPTIMIZED: squared distance)
		if proj.has("target_factory") and proj.target_factory != null:
			var factory: Dictionary = proj.target_factory
			if not factory.is_destroyed:
				var factory_pos: Vector3 = factory.position + Vector3(0, 5, 0)
				var dist_sq: float = proj.mesh.position.distance_squared_to(factory_pos)
				if dist_sq < FACTORY_HIT_DIST_SQ:
					_damage_factory(factory, proj.damage, proj.from_faction)
					# Spawn heavy impact effect for factory hits
					_spawn_impact_effect(proj.mesh.position, proj.from_faction, true)
					_play_hit_sound(proj.mesh.position)
					_cleanup_projectile_trail(proj)
					proj.mesh.queue_free()
					to_remove.append(proj)
					continue

		# Check collision with buildings (collateral damage)
		if _city_renderer != null:
			var building_id: int = _city_renderer.get_building_at_position(proj.mesh.position, 1.5)
			if building_id >= 0:
				_city_renderer.damage_building(building_id, proj.damage * 0.5, proj.mesh.position)
				# Spawn impact effect for building hits
				_spawn_impact_effect(proj.mesh.position, proj.from_faction, false)
				_play_hit_sound(proj.mesh.position)
				_cleanup_projectile_trail(proj)
				proj.mesh.queue_free()
				to_remove.append(proj)
				continue

		# Check collision with voxel terrain (destructible terrain)
		if _voxel_system != null:
			var voxel_pos := Vector3i(
				int(floor(proj.mesh.position.x)),
				0,
				int(floor(proj.mesh.position.z))
			)
			if _voxel_system.is_valid_position(voxel_pos):
				# Check if terrain is traversable (destroyed voxels are traversable)
				if not _voxel_system.is_traversable(voxel_pos):
					# Apply damage to voxel terrain
					_voxel_system.damage_voxel(voxel_pos, int(proj.damage * 0.3), "projectile")
					# Spawn impact effect
					_spawn_impact_effect(proj.mesh.position, proj.from_faction, false)
					_play_hit_sound(proj.mesh.position)
					_cleanup_projectile_trail(proj)
					proj.mesh.queue_free()
					to_remove.append(proj)

	# PERFORMANCE: Batch remove using index tracking to avoid hashing circular dictionary references
	if not to_remove.is_empty():
		var remove_indices: Array[int] = []
		for proj in to_remove:
			var idx := _projectiles.find(proj)
			if idx != -1:
				remove_indices.append(idx)
		# Sort descending to remove from end first (preserves earlier indices)
		remove_indices.sort()
		remove_indices.reverse()
		for idx in remove_indices:
			_projectiles.remove_at(idx)



func _damage_factory(factory: Dictionary, damage: float, from_faction: int) -> void:
	factory.health -= damage

	if factory.health <= 0:
		factory.is_destroyed = true
		print("Factory %d destroyed!" % factory.faction_id)

		# Hide the factory node
		if is_instance_valid(factory.node):
			factory.node.visible = false

		# Hide health bar
		if is_instance_valid(factory.health_bar):
			factory.health_bar.visible = false

		# Spawn big explosion
		_spawn_explosion(factory.position + Vector3(0, 5, 0), factory.faction_id)
		_spawn_explosion(factory.position + Vector3(5, 3, 5), factory.faction_id)
		_spawn_explosion(factory.position + Vector3(-5, 7, -5), factory.faction_id)

		# Play big explosion sound
		_play_explosion_sound(factory.position, 2.0)


func _damage_unit(unit: Dictionary, damage: float, from_faction: int, attacker: Dictionary = {}) -> void:
	var final_damage := damage
	var was_dodged := false
	var was_critical := false

	# Check Hive Mind XP dodge chance for defender
	var defender_dodge: float = _get_faction_xp_dodge_chance(unit.get("faction_id", 0))
	if defender_dodge > 0 and randf() < defender_dodge:
		was_dodged = true
		# Visual feedback for dodge
		if is_instance_valid(unit.mesh):
			_spawn_floating_text(unit.mesh.position + Vector3(0, 2, 0), "DODGE!", Color(0.5, 0.8, 1.0), 0.8)
		return  # Attack dodged, no damage dealt

	# Check Hive Mind XP critical strike chance for attacker
	var attacker_crit: float = _get_faction_xp_crit_chance(from_faction)
	if attacker_crit > 0 and randf() < attacker_crit:
		was_critical = true
		final_damage *= 2.0  # Double damage on critical hit

	# Apply Coordinated Barrage damage bonus for LogiBots attacking marked target
	var target_id: int = unit.get("id", 0)
	if from_faction == 4 and _coordinated_barrage != null and target_id > 0:
		if _coordinated_barrage.is_target_marked(target_id):
			# +75% damage to marked target from all LogiBots
			final_damage = damage * 1.75

	# Apply Fractal Movement evasion for Aether Swarm (erratic movement evades attacks)
	if unit.faction_id == _player_faction and _fractal_movement != null and target_id > 0:
		var evasion_result: Dictionary = _fractal_movement.roll_evasion(target_id, final_damage)
		if evasion_result.get("evaded", false):
			return  # Attack evaded, no damage dealt

	# Get attacker faction string for adaptive evolution
	var attacker_faction_str: String = FACTION_ID_TO_STRING.get(from_faction, "")

	# Apply Phase Shift damage reduction for Aether Swarm (player faction)
	var unit_id: int = unit.get("id", 0)
	if unit_id > 0 and unit.faction_id == _player_faction and _phase_shift != null:
		if _phase_shift.is_phased(unit_id):
			final_damage = _phase_shift.apply_to_damage(unit_id, final_damage)

	# Apply faction mechanics incoming damage (ArmorStacking, EvasionStacking, AdaptiveEvolution)
	if _faction_mechanics != null:
		if unit_id > 0:
			var result: Dictionary = _faction_mechanics.calculate_incoming_damage(unit_id, final_damage, attacker_faction_str)
			final_damage = result.get("damage", final_damage)
			was_dodged = result.get("dodged", false)

			# Handle distributed damage (ArmorStacking shares damage with nearby allies)
			var distributed: Dictionary = result.get("distributed", {})
			for ally_id in distributed:
				var ally_damage: float = distributed[ally_id]
				# Find ally unit and apply damage directly (skip recursion)
				for ally in _units:
					if ally.get("id", 0) == ally_id and not ally.is_dead:
						ally.health -= ally_damage
						break

	# If attack was dodged (Dynapods evasion), skip damage
	if was_dodged:
		return

	# Apply base armor damage reduction on top of faction mechanics
	var armor: float = unit.get("armor", 0.0)
	var reduced_damage: float = final_damage * (1.0 - armor)
	unit.health -= reduced_damage

	# Track damage statistics
	_track_stat(from_faction, "damage_dealt", reduced_damage)
	_track_stat(unit.faction_id, "damage_taken", reduced_damage)

	# Award Hive Mind Combat XP for damage dealt (1 XP per 10 damage)
	_award_faction_xp(from_faction, ExperiencePool.Category.COMBAT, reduced_damage * 0.1)

	# Report combat event to dynamic music (only for player involvement)
	if unit.faction_id == _player_faction or from_faction == _player_faction:
		if _audio_manager:
			var severity := clampf(reduced_damage / 50.0, 0.2, 2.0)  # Scale based on damage
			_audio_manager.report_combat_event(severity)
		# Also report to battle intensity tracker for more detailed tracking
		if _battle_intensity_tracker != null:
			_battle_intensity_tracker.report_damage(reduced_damage)
			_battle_intensity_tracker.report_combat_event(0.5)

	# Award XP for damage dealt (only to non-empty attacker)
	if not attacker.is_empty() and reduced_damage > 0:
		_award_xp(attacker, reduced_damage * VETERANCY_XP_PER_DAMAGE)

	# Spawn damage number (only for significant damage, throttled for performance)
	# Show critical hits with special styling
	if reduced_damage >= 5.0 and is_instance_valid(unit.mesh) and randf() < 0.3:
		_spawn_damage_number(unit.mesh.position, reduced_damage, was_critical or reduced_damage >= 20.0)

	# Update health bar
	if is_instance_valid(unit.health_bar):
		var fill: Node3D = unit.health_bar.get_node_or_null("Fill")
		if fill:
			var health_pct := maxf(0.0, unit.health / unit.max_health)
			fill.scale.x = health_pct
			fill.position.x = -(1.0 - health_pct)

	if unit.health <= 0:
		unit.is_dead = true
		_spawn_wreckage(unit)  # Leave harvestable wreckage
		GameStateManager.record_unit_lost(unit.faction_id)
		GameStateManager.record_unit_killed(from_faction)

		# Track comprehensive kill/death stats
		_track_stat(from_faction, "kills")
		_track_stat(unit.faction_id, "deaths")
		_update_kill_streak(from_faction)
		_reset_kill_streak(unit.faction_id)

		# Award Hive Mind Combat XP for kills (50 XP base, +25 for harvester)
		var kill_xp: float = 50.0
		if unit.get("is_harvester", false):
			kill_xp += 25.0
		_award_faction_xp(from_faction, ExperiencePool.Category.COMBAT, kill_xp)

		# Track harvester kills separately
		if unit.get("is_harvester", false):
			_track_stat(from_faction, "harvesters_killed")

		# Track Human Remnant kills separately
		if _is_human_remnant_unit(unit):
			_track_stat(from_faction, "hr_units_killed")

		# Award kill XP to the attacker
		if not attacker.is_empty():
			_award_xp(attacker, VETERANCY_XP_PER_KILL)

		# Record death for adaptive evolution learning (OptiForge learns from deaths)
		if _faction_mechanics != null and unit_id > 0:
			_faction_mechanics.record_death(unit_id, attacker_faction_str)

		# Track kills (legacy player-centric tracking)
		if from_faction == _player_faction:
			_player_kills += 1
			# Update kill streak
			if _kill_streak_timer > 0:
				_kill_streak += 1
			else:
				_kill_streak = 1
			_kill_streak_timer = KILL_STREAK_TIMEOUT
			_check_kill_streak(unit.mesh.position if is_instance_valid(unit.mesh) else Vector3.ZERO)
		else:
			_enemy_kills += 1

		if unit.faction_id == _player_faction:
			_player_deaths += 1
			_kill_streak = 0  # Reset streak on death

		# Spawn explosion and play sound
		if is_instance_valid(unit.mesh):
			_spawn_explosion(unit.mesh.position, unit.faction_id)
			_play_explosion_sound(unit.mesh.position, 0.8)

		# Report death to battle intensity tracker
		if _battle_intensity_tracker != null:
			var is_enemy: bool = (unit.faction_id != _player_faction)
			_battle_intensity_tracker.report_death(is_enemy)
			_battle_intensity_tracker.report_explosion()

		# Add to kill feed
		var killer_type: String = attacker.get("unit_type", "unit") if not attacker.is_empty() else "unit"
		var victim_type: String = unit.get("unit_type", "unit")
		_add_kill_feed_entry(from_faction, unit.faction_id, killer_type, victim_type)

		# Handle Human Remnant unit death (cleanup spawner tracking)
		if _is_human_remnant_unit(unit):
			_on_human_remnant_unit_died(unit)


## Apply splash (area of effect) damage to units near an impact point.
## Damage falls off linearly from full at center to splash_falloff at edge.
func _apply_splash_damage(impact_pos: Vector3, base_damage: float, splash_radius: float,
		splash_falloff: float, from_faction: int, primary_target: Dictionary, attacker: Dictionary) -> void:

	# Find all enemy units within splash radius
	var splash_targets: Array = []
	for unit in _units:
		if unit.is_dead or unit.faction_id == from_faction:
			continue
		# Skip the primary target (already took direct damage)
		if unit == primary_target:
			continue
		if not is_instance_valid(unit.mesh):
			continue

		var dist: float = unit.mesh.position.distance_to(impact_pos)
		if dist <= splash_radius:
			splash_targets.append({"unit": unit, "distance": dist})

	# Apply damage with distance falloff
	for target_data in splash_targets:
		var unit: Dictionary = target_data.unit
		var dist: float = target_data.distance

		# Calculate damage falloff: full damage at center, splash_falloff at edge
		var falloff_factor: float = 1.0 - (dist / splash_radius) * (1.0 - splash_falloff)
		var splash_damage: float = base_damage * falloff_factor * 0.6  # Splash does 60% of direct damage

		_damage_unit(unit, splash_damage, from_faction, attacker)

	# Spawn splash visual effect if we hit anything
	if splash_targets.size() > 0:
		_spawn_splash_effect(impact_pos, splash_radius, from_faction)

	# Apply splash damage to voxel terrain
	if _voxel_system != null and splash_radius >= 3.0:
		var center := Vector3i(int(floor(impact_pos.x)), 0, int(floor(impact_pos.z)))
		var voxel_damage := int(base_damage * 0.4)  # 40% of base damage to terrain
		var area_radius := int(ceil(splash_radius / 2.0))  # Smaller radius for voxels
		_voxel_system.damage_area(center, area_radius, voxel_damage, "splash")


## Spawn a visual effect for splash damage area.
func _spawn_splash_effect(pos: Vector3, radius: float, faction_id: int) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	# Create expanding ring effect
	var ring := CSGTorus3D.new()
	ring.inner_radius = radius * 0.8
	ring.outer_radius = radius
	ring.position = pos + Vector3(0, 0.5, 0)  # Slightly above ground

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = faction_color
	ring_mat.albedo_color.a = 0.6
	ring_mat.emission_enabled = true
	ring_mat.emission = faction_color
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = ring_mat

	_effects_container.add_child(ring)

	# Animate ring expansion and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "inner_radius", radius * 1.2, 0.3)
	tween.tween_property(ring, "outer_radius", radius * 1.4, 0.3)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_property(ring_mat, "emission_energy_multiplier", 0.0, 0.3)
	tween.chain().tween_callback(ring.queue_free)


## Check and announce kill streaks.
func _check_kill_streak(pos: Vector3) -> void:
	var announcement := ""
	var color := Color.WHITE

	match _kill_streak:
		2:
			announcement = "DOUBLE KILL!"
			color = Color(1.0, 0.8, 0.2)
		3:
			announcement = "TRIPLE KILL!"
			color = Color(1.0, 0.6, 0.1)
		4:
			announcement = "QUAD KILL!"
			color = Color(1.0, 0.4, 0.1)
		5:
			announcement = "PENTA KILL!"
			color = Color(1.0, 0.2, 0.2)
		_:
			if _kill_streak >= 6:
				announcement = "KILLING SPREE! x%d" % _kill_streak
				color = Color(1.0, 0.1, 0.5)

	if not announcement.is_empty():
		_spawn_kill_streak_banner(announcement, color)
		print(announcement)


## Spawn kill streak banner at top of screen.
func _spawn_kill_streak_banner(text: String, color: Color) -> void:
	var ui_layer: CanvasLayer = get_node_or_null("UI")
	if ui_layer == null:
		return

	var banner := Label.new()
	banner.text = text
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.offset_top = 80
	banner.offset_bottom = 130
	banner.offset_left = -200
	banner.offset_right = 200
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 36)
	banner.add_theme_color_override("font_color", color)
	banner.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	banner.add_theme_constant_override("shadow_offset_x", 3)
	banner.add_theme_constant_override("shadow_offset_y", 3)

	ui_layer.add_child(banner)

	# Animate: scale up then fade out
	banner.scale = Vector2(0.5, 0.5)
	banner.pivot_offset = banner.size / 2

	var tween := create_tween()
	tween.tween_property(banner, "scale", Vector2(1.2, 1.2), 0.2)
	tween.tween_property(banner, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_interval(1.0)
	tween.tween_property(banner, "modulate:a", 0.0, 0.5)
	tween.tween_callback(banner.queue_free)


func _cleanup_dead_units() -> void:
	var to_remove: Array = []

	for unit in _units:
		if unit.is_dead:
			# Unregister from faction mechanics
			var unit_id: int = unit.get("id", 0)
			if _faction_mechanics != null:
				if unit_id > 0:
					_faction_mechanics.unregister_unit(unit_id)

			# Unregister from MultiMesh rendering system
			if _multimesh_renderer != null and _use_multimesh_rendering and unit_id > 0:
				_multimesh_renderer.queue_dead_unit(unit_id)

			# Unregister from LOD system
			if _lod_system != null and unit_id > 0:
				_lod_system.unregister_unit(unit_id)

			# Unregister from performance tier system
			if _performance_tier_system != null and _use_performance_tiers and unit_id > 0:
				_performance_tier_system.unregister_unit(unit_id)

			if is_instance_valid(unit.mesh):
				unit.mesh.queue_free()
			if is_instance_valid(unit.health_bar):
				unit.health_bar.queue_free()
			to_remove.append(unit)

	for unit in to_remove:
		_units.erase(unit)


func _spawn_explosion(position: Vector3, faction_id: int) -> void:
	var explosion := Node3D.new()
	explosion.position = position

	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)
	var proj_style: Dictionary = FACTION_PROJECTILE_STYLES.get(faction_id, {})
	var size_mult: float = proj_style.get("size_mult", 1.0)

	# Faction-specific explosion parameters
	var base_radius := 0.5
	var expand_amount := 3.0
	var lifetime := 0.5
	var secondary_color: Color = proj_style.get("secondary_color", faction_color)

	match faction_id:
		1:  # Aether Swarm - Dissipation effect (quick scatter)
			base_radius = 0.3
			expand_amount = 4.0
			lifetime = 0.35
		2:  # OptiForge Legion - Standard fiery explosion
			base_radius = 0.6
			expand_amount = 3.5
			lifetime = 0.5
		3:  # Dynapods Vanguard - Sharp spark burst
			base_radius = 0.4
			expand_amount = 3.0
			lifetime = 0.3
		4:  # LogiBots Colossus - Heavy explosion
			base_radius = 0.8
			expand_amount = 5.0
			lifetime = 0.7
		5:  # Human Remnant - Realistic explosion
			base_radius = 0.5
			expand_amount = 3.0
			lifetime = 0.5

	# Create main expanding sphere
	var sphere := CSGSphere3D.new()
	sphere.radius = base_radius
	var mat := StandardMaterial3D.new()
	mat.albedo_color = faction_color
	mat.emission_enabled = true
	mat.emission = faction_color
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = mat
	explosion.add_child(sphere)

	# Add inner core with secondary color
	var core := CSGSphere3D.new()
	core.radius = base_radius * 0.5
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = secondary_color
	core_mat.emission_enabled = true
	core_mat.emission = secondary_color
	core_mat.emission_energy_multiplier = 6.0
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material = core_mat
	explosion.add_child(core)

	# Add debris particles for heavier factions (LogiBots, OptiForge)
	if faction_id in [2, 4]:
		_spawn_debris_particles(position, faction_color, faction_id == 4)

	# Add GPU particle effects for enhanced visuals
	_spawn_gpu_explosion(position, faction_id, size_mult)

	# Add smoke ring for larger explosions (heavy factions)
	if faction_id == 4:
		_spawn_smoke_ring(position, faction_id, expand_amount)

	_effects_container.add_child(explosion)

	var explosion_data := {
		"node": explosion,
		"sphere": sphere,
		"core": core,
		"material": mat,
		"core_material": core_mat,
		"lifetime": lifetime,
		"max_lifetime": lifetime,
		"expand_amount": expand_amount
	}
	_explosions.append(explosion_data)

	# Screen shake based on distance from camera and faction heaviness
	var dist_to_camera := position.distance_to(_camera_look_at)
	var shake_base := 0.3 + (size_mult * 0.3)  # Heavier units = more shake
	var shake_intensity := clampf(shake_base - (dist_to_camera / 200.0), 0.1, 0.8)
	_trigger_screen_shake(shake_intensity)


## Spawn debris particles for heavy explosions.
func _spawn_debris_particles(position: Vector3, color: Color, is_heavy: bool) -> void:
	var num_particles := 3 if not is_heavy else 6
	for i in num_particles:
		var debris := CSGBox3D.new()
		debris.size = Vector3(0.3, 0.3, 0.3) * randf_range(0.5, 1.5)
		debris.position = position + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))

		var debris_mat := StandardMaterial3D.new()
		debris_mat.albedo_color = color.darkened(0.3)
		debris_mat.emission_enabled = true
		debris_mat.emission = color
		debris_mat.emission_energy_multiplier = 1.5
		debris.material = debris_mat

		_effects_container.add_child(debris)

		# Animate debris flying outward and fading
		var direction := Vector3(randf_range(-1, 1), randf_range(0.5, 1.5), randf_range(-1, 1)).normalized()
		var distance := randf_range(3.0, 8.0) if is_heavy else randf_range(2.0, 5.0)
		var end_pos := debris.position + direction * distance

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(debris, "position", end_pos, 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(debris, "position:y", end_pos.y - 2.0, 0.4).set_delay(0.2)
		tween.tween_property(debris, "rotation", Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5)), 0.4)
		tween.tween_property(debris_mat, "albedo_color:a", 0.0, 0.3).set_delay(0.1)
		tween.chain().tween_callback(debris.queue_free)


## Create GPU particle explosion effect for enhanced visuals.
func _spawn_gpu_explosion(position: Vector3, faction_id: int, scale_mult: float = 1.0) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)
	var proj_style: Dictionary = FACTION_PROJECTILE_STYLES.get(faction_id, {})
	var secondary_color: Color = proj_style.get("secondary_color", faction_color.lightened(0.3))

	# Main explosion particles
	var particles := GPUParticles3D.new()
	particles.position = position
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = int(32 * scale_mult)
	particles.lifetime = 0.6 * scale_mult
	particles.speed_scale = 1.5
	particles.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))

	# Create particle material
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 8.0 * scale_mult
	mat.initial_velocity_max = 15.0 * scale_mult
	mat.gravity = Vector3(0, -15, 0)
	mat.damping_min = 2.0
	mat.damping_max = 5.0

	# Scale settings
	mat.scale_min = 0.3 * scale_mult
	mat.scale_max = 0.8 * scale_mult
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 1.0))
	scale_curve.add_point(Vector2(0.3, 1.2))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	mat.scale_curve = scale_curve_tex

	# Color gradient
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.add_point(0.15, faction_color.lightened(0.5))
	gradient.add_point(0.4, faction_color)
	gradient.add_point(0.7, secondary_color.darkened(0.3))
	gradient.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	# Emission color
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5 * scale_mult
	mat.color = faction_color

	particles.process_material = mat

	# Create draw pass (simple sphere mesh)
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh.radial_segments = 8
	mesh.rings = 4

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.emission_enabled = true
	mesh_mat.emission = faction_color
	mesh_mat.emission_energy_multiplier = 3.0
	mesh.material = mesh_mat

	particles.draw_pass_1 = mesh

	_effects_container.add_child(particles)

	# Spawn spark/ember particles for faction flavor
	_spawn_spark_particles(position, faction_id, scale_mult)

	# Auto-cleanup
	var timer := get_tree().create_timer(particles.lifetime + 0.5)
	timer.timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


## Spawn secondary spark particles for explosion flavor.
func _spawn_spark_particles(position: Vector3, faction_id: int, scale_mult: float = 1.0) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	# Different spark behaviors per faction
	var spark_count := 24
	var spark_speed := 12.0
	var spark_gravity := -5.0
	var spark_lifetime := 0.4

	match faction_id:
		1:  # Aether Swarm - Electric sparks
			spark_count = 32
			spark_speed = 18.0
			spark_gravity = -2.0
			spark_lifetime = 0.5
		2:  # OptiForge - Fire embers
			spark_count = 28
			spark_speed = 10.0
			spark_gravity = -8.0
			spark_lifetime = 0.6
		3:  # Dynapods - Sharp sparks
			spark_count = 20
			spark_speed = 20.0
			spark_gravity = -3.0
			spark_lifetime = 0.3
		4:  # LogiBots - Heavy debris sparks
			spark_count = 40
			spark_speed = 8.0
			spark_gravity = -12.0
			spark_lifetime = 0.8

	var sparks := GPUParticles3D.new()
	sparks.position = position
	sparks.emitting = true
	sparks.one_shot = true
	sparks.explosiveness = 0.9
	sparks.amount = int(spark_count * scale_mult)
	sparks.lifetime = spark_lifetime * scale_mult
	sparks.speed_scale = 1.2
	sparks.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.5, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = spark_speed * 0.7 * scale_mult
	mat.initial_velocity_max = spark_speed * scale_mult
	mat.gravity = Vector3(0, spark_gravity, 0)
	mat.damping_min = 1.0
	mat.damping_max = 3.0

	# Small scale for sparks
	mat.scale_min = 0.05 * scale_mult
	mat.scale_max = 0.15 * scale_mult

	# Spark color fade
	var gradient := Gradient.new()
	gradient.set_color(0, faction_color.lightened(0.8))
	gradient.add_point(0.3, faction_color)
	gradient.set_color(1, Color(0.3, 0.2, 0.1, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3 * scale_mult

	sparks.process_material = mat

	# Tiny sphere mesh for sparks
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 4
	mesh.rings = 2

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.emission_enabled = true
	mesh_mat.emission = faction_color
	mesh_mat.emission_energy_multiplier = 5.0
	mesh.material = mesh_mat

	sparks.draw_pass_1 = mesh

	_effects_container.add_child(sparks)

	# Auto-cleanup
	var timer := get_tree().create_timer(sparks.lifetime + 0.3)
	timer.timeout.connect(func():
		if is_instance_valid(sparks):
			sparks.queue_free()
	)


## Spawn smoke ring effect for larger explosions.
func _spawn_smoke_ring(position: Vector3, faction_id: int, radius: float = 3.0) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	var smoke := GPUParticles3D.new()
	smoke.position = position
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 0.8
	smoke.amount = 16
	smoke.lifetime = 1.2
	smoke.speed_scale = 0.8
	smoke.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 20, 40))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.3, 0)
	mat.spread = 180.0
	mat.flatness = 0.8  # Make it more horizontal
	mat.initial_velocity_min = radius * 2
	mat.initial_velocity_max = radius * 3
	mat.gravity = Vector3(0, 2, 0)  # Smoke rises
	mat.damping_min = 3.0
	mat.damping_max = 5.0

	# Large billowing scale
	mat.scale_min = 1.0
	mat.scale_max = 2.5
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 0.3))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.5))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	mat.scale_curve = scale_curve_tex

	# Smoke color (tinted by faction)
	var smoke_color := faction_color.darkened(0.6)
	smoke_color.a = 0.4
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.3, 0.3, 0.3, 0.6))
	gradient.add_point(0.4, smoke_color)
	gradient.set_color(1, Color(0.1, 0.1, 0.1, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 1, 0)
	mat.emission_ring_radius = radius * 0.3
	mat.emission_ring_inner_radius = 0.0
	mat.emission_ring_height = 0.5

	smoke.process_material = mat

	# Soft sphere for smoke puffs
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 8
	mesh.rings = 4

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat

	smoke.draw_pass_1 = mesh

	_effects_container.add_child(smoke)

	# Auto-cleanup
	var timer := get_tree().create_timer(smoke.lifetime + 0.5)
	timer.timeout.connect(func():
		if is_instance_valid(smoke):
			smoke.queue_free()
	)


## Create GPU particle trail for projectiles.
func _create_gpu_projectile_trail(faction_id: int) -> GPUParticles3D:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)
	var proj_style: Dictionary = FACTION_PROJECTILE_STYLES.get(faction_id, {})
	var secondary_color: Color = proj_style.get("secondary_color", faction_color.lightened(0.2))

	var trail := GPUParticles3D.new()
	trail.emitting = true
	trail.amount = 20
	trail.lifetime = 0.3
	trail.speed_scale = 1.0
	trail.local_coords = false  # Trail in world space
	trail.visibility_aabb = AABB(Vector3(-10, -10, -10), Vector3(20, 20, 20))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 5.0
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.5
	mat.gravity = Vector3.ZERO
	mat.damping_min = 5.0
	mat.damping_max = 10.0

	# Trail scales down over lifetime
	mat.scale_min = 0.1
	mat.scale_max = 0.2
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	mat.scale_curve = scale_curve_tex

	# Trail color fades
	var gradient := Gradient.new()
	gradient.set_color(0, faction_color)
	gradient.add_point(0.5, secondary_color.darkened(0.2))
	gradient.set_color(1, Color(faction_color.r * 0.3, faction_color.g * 0.3, faction_color.b * 0.3, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.1

	trail.process_material = mat

	# Small sphere mesh for trail particles
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 4
	mesh.rings = 2

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.emission_enabled = true
	mesh_mat.emission = faction_color
	mesh_mat.emission_energy_multiplier = 2.0
	mesh.material = mesh_mat

	trail.draw_pass_1 = mesh

	return trail


## Create impact effect when projectile hits target.
func _spawn_impact_effect(position: Vector3, faction_id: int, is_heavy: bool = false) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)
	var scale := 1.5 if is_heavy else 1.0

	# Impact flash
	var impact := GPUParticles3D.new()
	impact.position = position
	impact.emitting = true
	impact.one_shot = true
	impact.explosiveness = 1.0
	impact.amount = int(12 * scale)
	impact.lifetime = 0.2
	impact.speed_scale = 2.0
	impact.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 120.0
	mat.initial_velocity_min = 3.0 * scale
	mat.initial_velocity_max = 6.0 * scale
	mat.gravity = Vector3(0, -20, 0)
	mat.damping_min = 5.0
	mat.damping_max = 10.0

	mat.scale_min = 0.08 * scale
	mat.scale_max = 0.15 * scale

	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.add_point(0.2, faction_color.lightened(0.3))
	gradient.set_color(1, Color(faction_color.r, faction_color.g, faction_color.b, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	impact.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 4
	mesh.rings = 2

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.emission_enabled = true
	mesh_mat.emission = faction_color
	mesh_mat.emission_energy_multiplier = 4.0
	mesh.material = mesh_mat

	impact.draw_pass_1 = mesh

	_effects_container.add_child(impact)

	# Auto-cleanup
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(func():
		if is_instance_valid(impact):
			impact.queue_free()
	)


## Spawn factory production effect (assembly sparks).
func _spawn_factory_production_effect(factory_pos: Vector3, faction_id: int) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	var sparks := GPUParticles3D.new()
	sparks.position = factory_pos + Vector3(0, 3, 0)
	sparks.emitting = true
	sparks.one_shot = true
	sparks.explosiveness = 0.3
	sparks.amount = 24
	sparks.lifetime = 0.8
	sparks.speed_scale = 1.0
	sparks.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -8, 0)
	mat.damping_min = 1.0
	mat.damping_max = 2.0

	mat.scale_min = 0.05
	mat.scale_max = 0.12

	# Welding spark gradient
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.add_point(0.2, faction_color.lightened(0.5))
	gradient.add_point(0.5, faction_color)
	gradient.set_color(1, Color(0.5, 0.3, 0.1, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(3, 0.5, 3)

	sparks.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	mesh.radial_segments = 4
	mesh.rings = 2

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.emission_enabled = true
	mesh_mat.emission = faction_color
	mesh_mat.emission_energy_multiplier = 4.0
	mesh.material = mesh_mat

	sparks.draw_pass_1 = mesh

	_effects_container.add_child(sparks)

	# Auto-cleanup
	var timer := get_tree().create_timer(sparks.lifetime + 0.3)
	timer.timeout.connect(func():
		if is_instance_valid(sparks):
			sparks.queue_free()
	)


## Update unit ejection animations.
func _update_unit_ejections(delta: float) -> void:
	if _unit_ejection_animation != null:
		_unit_ejection_animation.update(delta)


## Callback when a unit ejection animation completes.
func _on_unit_ejection_completed(ejection_id: int, unit_node: Node3D) -> void:
	if not _pending_ejections.has(ejection_id):
		return

	var unit: Dictionary = _pending_ejections[ejection_id]
	_pending_ejections.erase(ejection_id)

	# Ensure unit mesh is at final position
	if unit.has("mesh") and is_instance_valid(unit.mesh):
		# Unit is now ready - spawn a small completion effect
		var faction_id: int = unit.get("faction_id", _player_faction)
		var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)
		_spawn_ejection_complete_effect(unit.mesh.position, faction_color)


## Spawn a small effect when unit ejection completes.
func _spawn_ejection_complete_effect(position: Vector3, color: Color) -> void:
	var particles := GPUParticles3D.new()
	particles.position = position + Vector3(0, 1, 0)
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 16
	particles.lifetime = 0.5
	particles.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_radius = 1.0
	mat.emission_ring_inner_radius = 0.5
	mat.emission_ring_height = 0.1
	mat.emission_ring_axis = Vector3(0, 1, 0)

	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, 0.5, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.2

	var gradient := Gradient.new()
	gradient.set_color(0, color.lightened(0.3))
	gradient.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.emission_enabled = true
	mesh_mat.emission = color
	mesh_mat.emission_energy_multiplier = 2.0
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh

	_effects_container.add_child(particles)

	# Auto-cleanup
	var timer := get_tree().create_timer(particles.lifetime + 0.2)
	timer.timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


## Spawn ability activation effect.
func _spawn_ability_effect(position: Vector3, faction_id: int, ability_type: String) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	var particles := GPUParticles3D.new()
	particles.position = position
	particles.emitting = true
	particles.one_shot = true
	particles.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))

	var mat := ParticleProcessMaterial.new()
	var mesh := SphereMesh.new()

	match ability_type:
		"phase_shift":  # Aether Swarm - Ethereal dissipation
			particles.amount = 40
			particles.lifetime = 0.6
			particles.explosiveness = 0.8
			mat.direction = Vector3(0, 1, 0)
			mat.spread = 180.0
			mat.initial_velocity_min = 5.0
			mat.initial_velocity_max = 12.0
			mat.gravity = Vector3(0, 5, 0)  # Float upward
			mat.scale_min = 0.1
			mat.scale_max = 0.25
		"overclock":  # OptiForge - Energy surge
			particles.amount = 30
			particles.lifetime = 0.5
			particles.explosiveness = 0.6
			mat.direction = Vector3(0, 1, 0)
			mat.spread = 60.0
			mat.initial_velocity_min = 8.0
			mat.initial_velocity_max = 15.0
			mat.gravity = Vector3(0, -5, 0)
			mat.scale_min = 0.08
			mat.scale_max = 0.18
		"siege_formation":  # LogiBots - Ground slam
			particles.amount = 50
			particles.lifetime = 0.8
			particles.explosiveness = 1.0
			mat.direction = Vector3(0, 0.2, 0)
			mat.spread = 180.0
			mat.flatness = 0.9
			mat.initial_velocity_min = 10.0
			mat.initial_velocity_max = 20.0
			mat.gravity = Vector3(0, -15, 0)
			mat.scale_min = 0.15
			mat.scale_max = 0.35
		_:  # Default burst
			particles.amount = 25
			particles.lifetime = 0.4
			particles.explosiveness = 0.7
			mat.direction = Vector3(0, 1, 0)
			mat.spread = 120.0
			mat.initial_velocity_min = 4.0
			mat.initial_velocity_max = 8.0
			mat.gravity = Vector3(0, -10, 0)
			mat.scale_min = 0.08
			mat.scale_max = 0.15

	mat.damping_min = 2.0
	mat.damping_max = 4.0

	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.add_point(0.2, faction_color.lightened(0.4))
	gradient.add_point(0.6, faction_color)
	gradient.set_color(1, Color(faction_color.r * 0.2, faction_color.g * 0.2, faction_color.b * 0.2, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 1.0

	particles.process_material = mat

	mesh.radius = 0.1
	mesh.height = 0.2
	mesh.radial_segments = 6
	mesh.rings = 3

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.emission_enabled = true
	mesh_mat.emission = faction_color
	mesh_mat.emission_energy_multiplier = 3.0
	mesh.material = mesh_mat

	particles.draw_pass_1 = mesh

	_effects_container.add_child(particles)

	# Auto-cleanup
	var timer := get_tree().create_timer(particles.lifetime + 0.5)
	timer.timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


## Handle leap started event - create trail effect.
func _on_leap_started(unit_id: int, target_pos: Vector3) -> void:
	var unit := _get_unit_by_id(unit_id)
	if unit.is_empty():
		return

	# Create leap trail particles
	var trail := _create_leap_trail(3)  # Dynapods = faction 3
	if is_instance_valid(unit.mesh):
		trail.global_position = unit.mesh.global_position
	_effects_container.add_child(trail)
	_leap_trails[unit_id] = trail

	# Spawn launch effect at start position
	if is_instance_valid(unit.mesh):
		_spawn_leap_launch_effect(unit.mesh.global_position)


## Handle unit leaping event - update trail position.
func _on_unit_leaping(unit_id: int, progress: float) -> void:
	var unit := _get_unit_by_id(unit_id)
	if unit.is_empty():
		return

	# Update trail position to follow unit
	if _leap_trails.has(unit_id) and is_instance_valid(_leap_trails[unit_id]):
		if is_instance_valid(unit.mesh):
			_leap_trails[unit_id].global_position = unit.mesh.global_position


## Handle leap landed event - create landing impact effect.
func _on_leap_landed(unit_id: int, damage_dealt: float, units_hit: int) -> void:
	var unit := _get_unit_by_id(unit_id)

	# Cleanup trail
	if _leap_trails.has(unit_id):
		if is_instance_valid(_leap_trails[unit_id]):
			_leap_trails[unit_id].emitting = false
			# Delay cleanup to let particles fade
			var trail_ref = _leap_trails[unit_id]
			var cleanup_timer := get_tree().create_timer(0.5)
			cleanup_timer.timeout.connect(func():
				if is_instance_valid(trail_ref):
					trail_ref.queue_free()
			)
		_leap_trails.erase(unit_id)

	# Spawn landing impact effect
	if not unit.is_empty() and is_instance_valid(unit.mesh):
		_spawn_leap_landing_effect(unit.mesh.global_position, damage_dealt, units_hit)


## Create GPU particle trail for leaping unit.
func _create_leap_trail(faction_id: int) -> GPUParticles3D:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.GREEN)

	var trail := GPUParticles3D.new()
	trail.emitting = true
	trail.amount = 30
	trail.lifetime = 0.5
	trail.speed_scale = 1.0
	trail.local_coords = false
	trail.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -5, 0)
	mat.damping_min = 3.0
	mat.damping_max = 6.0

	mat.scale_min = 0.15
	mat.scale_max = 0.3
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	mat.scale_curve = scale_curve_tex

	var gradient := Gradient.new()
	gradient.set_color(0, faction_color.lightened(0.5))
	gradient.add_point(0.3, faction_color)
	gradient.set_color(1, Color(faction_color.r * 0.3, faction_color.g * 0.3, faction_color.b * 0.3, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5

	trail.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	mesh.radial_segments = 6
	mesh.rings = 3

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.emission_enabled = true
	mesh_mat.emission = faction_color
	mesh_mat.emission_energy_multiplier = 2.5
	mesh.material = mesh_mat

	trail.draw_pass_1 = mesh

	return trail


## Spawn launch effect when unit begins leap.
func _spawn_leap_launch_effect(position: Vector3) -> void:
	var faction_color: Color = FACTION_COLORS.get(3, Color.GREEN)

	var launch := GPUParticles3D.new()
	launch.position = position
	launch.emitting = true
	launch.one_shot = true
	launch.explosiveness = 1.0
	launch.amount = 20
	launch.lifetime = 0.4
	launch.speed_scale = 1.5
	launch.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 60.0
	mat.flatness = 0.7
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 10.0
	mat.gravity = Vector3(0, -15, 0)
	mat.damping_min = 2.0
	mat.damping_max = 4.0

	mat.scale_min = 0.1
	mat.scale_max = 0.25

	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.6, 0.5, 0.3, 1.0))  # Dust/dirt color
	gradient.add_point(0.3, faction_color.darkened(0.3))
	gradient.set_color(1, Color(0.3, 0.25, 0.15, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 1, 0)
	mat.emission_ring_radius = 1.0
	mat.emission_ring_inner_radius = 0.0
	mat.emission_ring_height = 0.2

	launch.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 4
	mesh.rings = 2

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat

	launch.draw_pass_1 = mesh

	_effects_container.add_child(launch)

	var timer := get_tree().create_timer(launch.lifetime + 0.3)
	timer.timeout.connect(func():
		if is_instance_valid(launch):
			launch.queue_free()
	)


## Spawn landing impact effect when unit completes leap.
func _spawn_leap_landing_effect(position: Vector3, damage_dealt: float, units_hit: int) -> void:
	var faction_color: Color = FACTION_COLORS.get(3, Color.GREEN)
	var scale_mult := 1.0 + (damage_dealt / 150.0)  # Scale with damage

	# Ground impact ring
	var impact := GPUParticles3D.new()
	impact.position = position
	impact.emitting = true
	impact.one_shot = true
	impact.explosiveness = 1.0
	impact.amount = 40
	impact.lifetime = 0.6
	impact.speed_scale = 1.2
	impact.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.3, 0)
	mat.spread = 180.0
	mat.flatness = 0.85
	mat.initial_velocity_min = 8.0 * scale_mult
	mat.initial_velocity_max = 15.0 * scale_mult
	mat.gravity = Vector3(0, -20, 0)
	mat.damping_min = 3.0
	mat.damping_max = 6.0

	mat.scale_min = 0.15 * scale_mult
	mat.scale_max = 0.35 * scale_mult
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 0.5))
	scale_curve.add_point(Vector2(0.2, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	mat.scale_curve = scale_curve_tex

	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.add_point(0.15, faction_color.lightened(0.4))
	gradient.add_point(0.4, faction_color)
	gradient.set_color(1, Color(0.4, 0.35, 0.2, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 1, 0)
	mat.emission_ring_radius = 1.5 * scale_mult
	mat.emission_ring_inner_radius = 0.0
	mat.emission_ring_height = 0.3

	impact.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3

	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.emission_enabled = true
	mesh_mat.emission = faction_color
	mesh_mat.emission_energy_multiplier = 3.0
	mesh.material = mesh_mat

	impact.draw_pass_1 = mesh

	_effects_container.add_child(impact)

	# Add shockwave ring visual
	_spawn_leap_shockwave(position, scale_mult)

	# Screen shake based on damage
	var shake_intensity := clampf(0.3 + (damage_dealt / 200.0), 0.2, 0.8)
	_trigger_screen_shake(shake_intensity)

	var timer := get_tree().create_timer(impact.lifetime + 0.3)
	timer.timeout.connect(func():
		if is_instance_valid(impact):
			impact.queue_free()
	)


## Spawn expanding shockwave ring for leap landing.
func _spawn_leap_shockwave(position: Vector3, scale_mult: float) -> void:
	var faction_color: Color = FACTION_COLORS.get(3, Color.GREEN)

	# Create expanding ring using CSGTorus
	var ring := CSGTorus3D.new()
	ring.inner_radius = 0.5
	ring.outer_radius = 1.0
	ring.sides = 24
	ring.ring_sides = 6
	ring.position = position + Vector3(0, 0.1, 0)
	ring.rotation.x = PI / 2  # Lay flat

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = faction_color
	ring_mat.emission_enabled = true
	ring_mat.emission = faction_color
	ring_mat.emission_energy_multiplier = 3.0
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = ring_mat

	_effects_container.add_child(ring)

	# Animate expansion and fade
	var expand_size := 5.0 * scale_mult
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "inner_radius", expand_size * 0.8, 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "outer_radius", expand_size, 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.35).set_delay(0.05)
	tween.tween_property(ring_mat, "emission_energy_multiplier", 0.0, 0.35).set_delay(0.05)
	tween.chain().tween_callback(ring.queue_free)


func _update_explosions(delta: float) -> void:
	var to_remove: Array = []

	for exp in _explosions:
		exp.lifetime -= delta

		if exp.lifetime <= 0:
			if is_instance_valid(exp.node):
				exp.node.queue_free()
			to_remove.append(exp)
			continue

		# Expand and fade
		var progress: float = 1.0 - (exp.lifetime / exp.max_lifetime)
		var expand_amount: float = exp.get("expand_amount", 3.0)

		# Main sphere expands outward
		if is_instance_valid(exp.sphere):
			exp.sphere.radius = 0.5 + progress * expand_amount
		if exp.material:
			exp.material.albedo_color.a = 1.0 - progress
			exp.material.emission_energy_multiplier = 4.0 * (1.0 - progress)

		# Core shrinks and brightens then fades
		if exp.has("core") and is_instance_valid(exp.core):
			var core_progress: float = minf(progress * 2.0, 1.0)  # Core fades faster
			exp.core.radius = maxf(0.01, 0.3 * (1.0 - core_progress))  # Minimum radius to avoid CSG error
			if exp.has("core_material") and exp.core_material:
				exp.core_material.albedo_color.a = 1.0 - core_progress
				exp.core_material.emission_energy_multiplier = 8.0 * (1.0 - core_progress * 0.5)

	for exp in to_remove:
		_explosions.erase(exp)


func _find_nearest_enemy(unit: Dictionary) -> Variant:
	return _find_best_target(unit, INF)


## Callback for PerformanceTierSystem - returns distance to nearest enemy for a unit_id.
## Used to determine combat proximity for AI update throttling.
func _get_nearest_enemy_distance_for_tier(unit_id: int) -> float:
	# Find unit by ID
	for unit in _units:
		if unit.get("id", -1) == unit_id:
			if unit.is_dead or not is_instance_valid(unit.mesh):
				return INF
			var unit_pos: Vector3 = unit.mesh.position
			var nearest_dist: float = INF
			# Find nearest enemy
			for other in _units:
				if other.is_dead or other.faction_id == unit.faction_id:
					continue
				if not is_instance_valid(other.mesh):
					continue
				var dist := unit_pos.distance_to(other.mesh.position)
				if dist < nearest_dist:
					nearest_dist = dist
			return nearest_dist
	return INF


## Find the best target for a unit using priority scoring.
## Considers distance, health, target type, threat, and focus fire.
func _find_best_target(unit: Dictionary, max_range: float = INF) -> Variant:
	var best_target: Variant = null
	var best_score: float = -INF
	var unit_pos: Vector3 = unit.mesh.position
	var unit_range: float = unit.get("attack_range", 15.0)

	# Clamp max_range for performance - no point checking enemies 200+ units away
	var effective_range: float = minf(max_range, 200.0)

	# Only count focus fire for larger battles (>30 units), otherwise skip for performance
	var target_counts: Dictionary = {}
	var do_focus_fire: bool = _units.size() > 30 and _units.size() < 500
	if do_focus_fire:
		for friendly in _units:
			if friendly.is_dead or friendly.faction_id != unit.faction_id:
				continue
			var t = friendly.get("target_enemy")
			if t != null and t is Dictionary and not t.is_dead:
				var t_id: int = t.get("id", -1)
				target_counts[t_id] = target_counts.get(t_id, 0) + 1

	for other in _units:
		if other.is_dead or other.faction_id == unit.faction_id:
			continue
		if not is_instance_valid(other.mesh):
			continue
		# Skip cloaked units - they are untargetable
		if other.get("is_cloaked", false):
			continue

		var dist := unit_pos.distance_to(other.mesh.position)

		# Skip if out of range (use effective_range for performance)
		if dist > effective_range:
			continue

		# Calculate target score (higher = better target)
		var score: float = 0.0

		# Distance score: prefer closer targets (base priority)
		# Normalize distance to 0-1 range where closer = higher
		var dist_normalized: float = clampf(dist / 100.0, 0.0, 1.0)
		score += (1.0 - dist_normalized) * 50.0  # Up to 50 points for being close

		# In range bonus: strong preference for targets we can hit now
		if dist <= unit_range:
			score += 30.0

		# Health score: prefer low health targets (finish them off)
		var health_pct: float = other.health / other.max_health
		score += (1.0 - health_pct) * 25.0  # Up to 25 points for low health

		# Target type priority
		var target_type: String = other.get("unit_type", "medium")
		match target_type:
			"harvester":
				score += 35.0  # High priority - cripple enemy economy
			"light":
				score += 10.0  # Easy to kill, clear the swarm
			"medium":
				score += 15.0  # Balanced threat
			"heavy":
				score += 5.0   # Dangerous but hard to kill, lower priority

		# Threat score: prioritize enemies attacking us or our allies
		var other_target = other.get("target_enemy")
		if other_target != null and other_target is Dictionary:
			if other_target.get("id", -2) == unit.get("id", -1):
				# This enemy is attacking US - highest threat
				score += 40.0
			elif other_target.get("faction_id", -1) == unit.faction_id:
				# This enemy is attacking an ally
				score += 20.0

		# Focus fire bonus: prefer targets already being attacked by allies
		# This helps finish off enemies faster
		var other_id: int = other.get("id", -1)
		var attackers: int = target_counts.get(other_id, 0)
		if attackers > 0 and attackers < 5:  # Cap focus fire bonus
			score += attackers * 8.0  # Up to 32 points for 4 attackers

		# Factory threat: enemy near our factories
		if _factories.has(unit.faction_id):
			var my_factory: Dictionary = _factories[unit.faction_id]
			if not my_factory.is_destroyed and my_factory.has("mesh") and is_instance_valid(my_factory.mesh):
				var factory_dist: float = other.mesh.position.distance_to(my_factory.mesh.position)
				if factory_dist < 50.0:
					score += (50.0 - factory_dist) * 0.5  # Up to 25 points

		if score > best_score:
			best_score = score
			best_target = other

	return best_target


## Find a nearby enemy within specified range (for defensive response).
## Uses the same scoring system as _find_best_target.
func _find_nearby_threat(unit: Dictionary, max_range: float) -> Variant:
	return _find_best_target(unit, max_range)


func _is_valid_target(target) -> bool:
	if target == null:
		return false
	if target is Dictionary:
		return not target.is_dead and is_instance_valid(target.mesh)
	return false


## Check if a unit should retreat based on health and local force ratio.
## Returns retreat position or null if unit should not retreat.
func _check_retreat_needed(unit: Dictionary) -> Variant:
	if not is_instance_valid(unit.mesh):
		return null

	# HOLD_POSITION stance never retreats
	var stance: int = unit.get("stance", UnitStance.AGGRESSIVE)
	if stance == UnitStance.HOLD_POSITION:
		return null

	# Heavy units don't retreat as easily (they're the anchors)
	var health_threshold: float = RETREAT_HEALTH_THRESHOLD
	if unit.get("unit_type", "medium") == "heavy":
		health_threshold *= 0.6  # Only retreat at 15% health for heavies

	# Check health-based retreat
	var health_pct: float = unit.health / unit.max_health
	var needs_retreat := health_pct < health_threshold

	# If not low health, check force ratio (only for DEFENSIVE stance)
	if not needs_retreat and stance == UnitStance.DEFENSIVE:
		var unit_pos: Vector3 = unit.mesh.position
		var allies_nearby := 0
		var enemies_nearby := 0

		for other in _units:
			if other.is_dead or not is_instance_valid(other.mesh):
				continue
			var dist: float = unit_pos.distance_to(other.mesh.position)
			if dist > RETREAT_CHECK_RADIUS:
				continue

			if other.faction_id == unit.faction_id:
				allies_nearby += 1
			else:
				if not other.get("is_cloaked", false):
					enemies_nearby += 1

		# Check if badly outnumbered
		if enemies_nearby > 0 and allies_nearby > 0:
			var ratio: float = float(enemies_nearby) / float(allies_nearby)
			if ratio >= RETREAT_OUTNUMBERED_RATIO:
				needs_retreat = true

	if not needs_retreat:
		return null

	# Find retreat destination - prioritize:
	# 1. Own factory
	# 2. Largest cluster of friendly units
	# 3. Away from nearest enemy
	return _find_retreat_position(unit)


## Find a safe retreat position for the unit.
func _find_retreat_position(unit: Dictionary) -> Vector3:
	var unit_pos: Vector3 = unit.mesh.position

	# Try to retreat to own factory first
	var factory_pos: Variant = null
	if _factories.has(unit.faction_id):
		var factory: Dictionary = _factories[unit.faction_id]
		if not factory.is_destroyed and factory.has("mesh") and is_instance_valid(factory.mesh):
			factory_pos = factory.mesh.position

	if factory_pos != null:
		# Move toward factory but not all the way (stop at a safe distance)
		var dir_to_factory: Vector3 = (factory_pos - unit_pos).normalized()
		var retreat_dist: float = minf(50.0, unit_pos.distance_to(factory_pos) * 0.7)
		return unit_pos + dir_to_factory * retreat_dist

	# No factory found - retreat away from nearest enemy
	var nearest_enemy: Variant = null
	var nearest_dist := INF

	for other in _units:
		if other.is_dead or other.faction_id == unit.faction_id:
			continue
		if not is_instance_valid(other.mesh):
			continue

		var dist: float = unit_pos.distance_to(other.mesh.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_enemy = other

	if nearest_enemy != null and is_instance_valid(nearest_enemy.mesh):
		var away_dir: Vector3 = (unit_pos - nearest_enemy.mesh.position).normalized()
		return unit_pos + away_dir * 30.0

	# Fallback: move toward map center (where factories tend to be)
	return Vector3.ZERO


## Update wreckage - decay old wreckage over time.
func _update_wreckage(delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	var to_remove: Array = []

	for wreck in _wreckage:
		var age: float = current_time - wreck.spawn_time
		if age >= WRECKAGE_DECAY_TIME:
			# Wreckage decayed - remove it
			if is_instance_valid(wreck.mesh):
				wreck.mesh.queue_free()
			to_remove.append(wreck)
		elif age >= WRECKAGE_DECAY_TIME * 0.7:
			# Start fading out
			if is_instance_valid(wreck.mesh):
				var fade: float = 1.0 - (age - WRECKAGE_DECAY_TIME * 0.7) / (WRECKAGE_DECAY_TIME * 0.3)
				var mat = wreck.mesh.get("material")
				if mat and mat is StandardMaterial3D:
					mat.albedo_color.a = fade

	for wreck in to_remove:
		_wreckage.erase(wreck)


## Spawn wreckage when a unit dies.
func _spawn_wreckage(unit: Dictionary) -> void:
	if not is_instance_valid(unit.mesh):
		return

	var pos: Vector3 = unit.mesh.position
	var ree_cost: float = unit.get("ree_cost", 30.0)
	var ree_value: float = ree_cost * WRECKAGE_REE_PERCENT

	# Create wreckage mesh (darker, partially destroyed version)
	var wreck_mesh := CSGBox3D.new()
	var size: float = unit.get("size", 1.0) * 0.8
	wreck_mesh.size = Vector3(size, size * 0.3, size)  # Flattened
	wreck_mesh.position = Vector3(pos.x, 0.15, pos.z)
	wreck_mesh.rotation.y = randf() * TAU  # Random rotation

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.25, 0.2, 1.0)  # Dark brown/grey
	mat.metallic = 0.6
	mat.roughness = 0.8
	wreck_mesh.material = mat

	_effects_container.add_child(wreck_mesh)

	var wreck := {
		"mesh": wreck_mesh,
		"position": pos,
		"ree_value": ree_value,
		"spawn_time": Time.get_ticks_msec() / 1000.0,
		"faction_id": unit.faction_id  # Track original faction
	}
	_wreckage.append(wreck)


func _check_victory_defeat() -> void:
	# Check if player factory is destroyed
	if _factories.has(_player_faction) and _factories[_player_faction].is_destroyed:
		print("DEFEAT! Your factory was destroyed!")
		GameStateManager.end_match(GameStateManager.GameResult.DEFEAT)
		_show_game_over(false)
		return

	# Check if all enemy factories destroyed (main victory condition)
	var enemy_factories_alive := 0
	for faction_id in _factories:
		if faction_id != _player_faction and not _factories[faction_id].is_destroyed:
			enemy_factories_alive += 1

	if enemy_factories_alive == 0:
		print("VICTORY! All enemy factories destroyed!")
		GameStateManager.end_match(GameStateManager.GameResult.VICTORY)
		_show_game_over(true)
		return

	# District domination victory (control 60%+ of all districts)
	if not _districts.is_empty() and _match_time > 120.0:  # Wait 2 minutes before domination check
		var player_districts := _get_faction_district_count(_player_faction)
		var domination_threshold: int = int(_districts.size() * 0.6)  # 60% of districts

		if player_districts >= domination_threshold:
			print("DOMINATION VICTORY! You control %d/%d districts!" % [player_districts, _districts.size()])
			GameStateManager.end_match(GameStateManager.GameResult.VICTORY)
			_show_game_over(true)
			return

		# Check if any enemy faction dominates
		for faction_id in [2, 3, 4]:
			if faction_id == _player_faction:
				continue
			var enemy_districts := _get_faction_district_count(faction_id)
			if enemy_districts >= domination_threshold:
				print("DEFEAT! Faction %d achieved district domination with %d/%d districts!" % [faction_id, enemy_districts, _districts.size()])
				GameStateManager.end_match(GameStateManager.GameResult.DEFEAT)
				_show_game_over(false)
				return

	# Don't check for unit-based defeat until 60+ seconds (let the game get started)
	if _match_time < 60.0:
		return

	# Count player units
	var player_units := 0
	for unit in _units:
		if unit.faction_id == _player_faction and not unit.is_dead:
			player_units += 1

	# Defeat: no player units AND factory is heavily damaged (below 20%)
	var factory_health_pct := 1.0
	if _factories.has(_player_faction):
		factory_health_pct = _factories[_player_faction].health / _factories[_player_faction].max_health

	if player_units == 0 and factory_health_pct < 0.2:
		print("DEFEAT! All player units destroyed and factory critical!")
		GameStateManager.end_match(GameStateManager.GameResult.DEFEAT)
		_show_game_over(false)
		return

	# Victory: destroyed all enemy factories
	if enemy_factories_alive == 0 and player_units > 0:
		print("VICTORY! All enemies defeated!")
		GameStateManager.end_match(GameStateManager.GameResult.VICTORY)
		_show_game_over(true)


## Update harvester AI for all harvesters.
func _update_harvesters(delta: float) -> void:
	for unit in _units:
		if unit.is_dead or not unit.get("is_harvester", false):
			continue

		var faction_id: int = unit.faction_id
		var state: int = unit.get("harvester_state", HarvesterState.IDLE)

		match state:
			HarvesterState.IDLE:
				# Priority 1: Look for wreckage to harvest (highest priority)
				var nearest_wreck := _find_nearest_wreckage(unit)
				if not nearest_wreck.is_empty():
					unit["target_wreckage"] = nearest_wreck
					unit["harvester_state"] = HarvesterState.SEEKING_WRECKAGE
					unit["target_pos"] = nearest_wreck.position
				# Priority 2: Look for damaged buildings to salvage
				elif _city_renderer != null:
					var nearest_building := _find_nearest_salvage_building(unit)
					if nearest_building.has("id"):
						unit["target_building_id"] = nearest_building.id
						unit["target_building_pos"] = nearest_building.position
						unit["harvester_state"] = HarvesterState.SEEKING_BUILDING
						unit["target_pos"] = nearest_building.position
				# Priority 3: If carrying REE, return to factory
				elif unit.get("carried_ree", 0.0) > 0:
					unit["harvester_state"] = HarvesterState.RETURNING

			HarvesterState.SEEKING_WRECKAGE:
				var target_wreck = unit.get("target_wreckage")
				if target_wreck == null or not target_wreck in _wreckage:
					# Wreckage gone, go idle
					unit["harvester_state"] = HarvesterState.IDLE
					unit["target_wreckage"] = null
					continue

				# Move toward wreckage
				if is_instance_valid(unit.mesh):
					var dist: float = unit.mesh.position.distance_to(target_wreck.position)
					if dist <= WRECKAGE_HARVEST_RANGE:
						# Start harvesting
						unit["harvester_state"] = HarvesterState.HARVESTING
					else:
						# Keep moving
						unit["target_pos"] = target_wreck.position

			HarvesterState.HARVESTING:
				var target_wreck = unit.get("target_wreckage")
				if target_wreck == null or not target_wreck in _wreckage:
					# Wreckage gone
					unit["harvester_state"] = HarvesterState.IDLE
					unit["target_wreckage"] = null
					continue

				# Harvest REE
				var harvest_rate: float = unit.get("harvest_rate", 10.0)
				var capacity: float = unit.get("carry_capacity", 50.0)
				var carried: float = unit.get("carried_ree", 0.0)
				var space: float = capacity - carried

				var amount_to_harvest: float = minf(harvest_rate * delta, space)
				amount_to_harvest = minf(amount_to_harvest, target_wreck.ree_value)

				unit["carried_ree"] = carried + amount_to_harvest
				target_wreck.ree_value -= amount_to_harvest

				# Check if wreckage depleted
				if target_wreck.ree_value <= 0.1:
					if is_instance_valid(target_wreck.mesh):
						target_wreck.mesh.queue_free()
					_wreckage.erase(target_wreck)
					unit["target_wreckage"] = null

					# If full or no more wreckage, return to factory
					if unit.get("carried_ree", 0.0) >= capacity * 0.9 or _wreckage.is_empty():
						unit["harvester_state"] = HarvesterState.RETURNING
					else:
						unit["harvester_state"] = HarvesterState.IDLE
				# If full, return to factory
				elif unit.get("carried_ree", 0.0) >= capacity:
					unit["harvester_state"] = HarvesterState.RETURNING

			HarvesterState.RETURNING:
				# Get factory position
				if not _factories.has(faction_id) or _factories[faction_id].is_destroyed:
					unit["harvester_state"] = HarvesterState.IDLE
					continue

				var factory_pos: Vector3 = FACTORY_POSITIONS.get(faction_id, Vector3.ZERO)
				unit["target_pos"] = factory_pos

				if is_instance_valid(unit.mesh):
					var dist: float = unit.mesh.position.distance_to(factory_pos)
					if dist <= HARVESTER_DEPOSIT_RANGE:
						# Deposit REE
						var carried: float = unit.get("carried_ree", 0.0)
						if carried > 0 and ResourceManager:
							ResourceManager.add_ree(faction_id, carried, "harvester_deposit")
							_track_stat(faction_id, "ree_earned", carried)
							# Award Hive Mind Economy XP for harvesting (1 XP per 2 REE)
							_award_faction_xp(faction_id, ExperiencePool.Category.ECONOMY, carried * 0.5)
							if faction_id == _player_faction:
								_total_ree_earned += carried
							print("Harvester deposited %.0f REE" % carried)
						unit["carried_ree"] = 0.0
						unit["harvester_state"] = HarvesterState.IDLE

			HarvesterState.SEEKING_BUILDING:
				var target_id: int = unit.get("target_building_id", -1)
				var target_pos: Vector3 = unit.get("target_building_pos", Vector3.ZERO)

				# Check if building still exists and is salvageable
				if target_id < 0 or _city_renderer == null:
					unit["harvester_state"] = HarvesterState.IDLE
					unit["target_building_id"] = -1
					continue

				if not _city_renderer.is_building_salvageable(target_id):
					unit["harvester_state"] = HarvesterState.IDLE
					unit["target_building_id"] = -1
					continue

				# Move toward building
				if is_instance_valid(unit.mesh):
					var dist: float = unit.mesh.position.distance_to(target_pos)
					if dist <= BUILDING_SALVAGE_RANGE:
						# Start salvaging
						unit["harvester_state"] = HarvesterState.SALVAGING
					else:
						unit["target_pos"] = target_pos

			HarvesterState.SALVAGING:
				var target_id: int = unit.get("target_building_id", -1)

				# Check if building still exists
				if target_id < 0 or _city_renderer == null:
					unit["harvester_state"] = HarvesterState.IDLE
					unit["target_building_id"] = -1
					continue

				if not _city_renderer.is_building_salvageable(target_id):
					# Building destroyed or fully salvaged
					unit["harvester_state"] = HarvesterState.IDLE
					unit["target_building_id"] = -1
					continue

				# Salvage the building
				var capacity: float = unit.get("carry_capacity", 50.0)
				var carried: float = unit.get("carried_ree", 0.0)
				var space: float = capacity - carried

				var salvage_amount: float = minf(BUILDING_SALVAGE_RATE * delta, space)
				var result: Dictionary = _city_renderer.salvage_building(target_id, salvage_amount)

				var ree_gained: float = result.get("ree", 0.0) * BUILDING_SALVAGE_BONUS
				unit["carried_ree"] = carried + ree_gained

				# Award Hive Mind Economy XP for salvaging (1 XP per 3 REE)
				if ree_gained > 0:
					_award_faction_xp(faction_id, ExperiencePool.Category.ECONOMY, ree_gained * 0.33)

				# Spawn visual effect periodically
				if randf() < 0.3 and is_instance_valid(unit.mesh):
					_spawn_salvage_sparks(unit.mesh.position + Vector3(0, 1.5, 0), faction_id)

				# Check if building is now destroyed or we're full
				if result.get("destroyed", false) or unit.get("carried_ree", 0.0) >= capacity * 0.9:
					unit["harvester_state"] = HarvesterState.RETURNING
					unit["target_building_id"] = -1


## Find nearest building that can be salvaged (including intact buildings).
## Harvesters actively demolish buildings for REE when no wrecks available.
func _find_nearest_salvage_building(unit: Dictionary) -> Dictionary:
	if not is_instance_valid(unit.mesh) or _city_renderer == null:
		return {}

	var unit_pos: Vector3 = unit.mesh.position
	var result: Dictionary = {}
	var nearest_dist: float = 250.0  # Increased search distance for buildings

	# First try damaged buildings (priority)
	if _city_renderer.has_method("get_damaged_buildings"):
		var damaged_buildings: Array = _city_renderer.get_damaged_buildings()
		for building in damaged_buildings:
			var building_pos: Vector3 = building.get("position", Vector3.ZERO)
			var dist: float = unit_pos.distance_to(building_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				result = building

	# If no damaged buildings found nearby, seek intact buildings
	if result.is_empty() and _city_renderer.has_method("get_all_salvageable_buildings"):
		var all_buildings: Array = _city_renderer.get_all_salvageable_buildings()
		for building in all_buildings:
			var building_pos: Vector3 = building.get("position", Vector3.ZERO)
			var dist: float = unit_pos.distance_to(building_pos)
			if dist < nearest_dist:
				nearest_dist = dist
				result = building

	return result


## Spawn salvage sparks effect when harvester is salvaging.
func _spawn_salvage_sparks(pos: Vector3, faction_id: int) -> void:
	var faction_color: Color = FACTION_COLORS.get(faction_id, Color.WHITE)

	# Create small spark particles
	for i in 3:
		var spark := CSGSphere3D.new()
		spark.radius = 0.15
		spark.position = pos + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1))

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.8, 0.3, 1.0)  # Orange sparks
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.6, 0.2)
		mat.emission_energy_multiplier = 4.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.material = mat

		_effects_container.add_child(spark)

		# Animate spark flying outward and fading
		var direction := Vector3(randf_range(-1, 1), randf_range(0.5, 2), randf_range(-1, 1)).normalized()
		var end_pos := spark.position + direction * randf_range(1.5, 3.0)

		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "position", end_pos, 0.4)
		tween.tween_property(mat, "albedo_color:a", 0.0, 0.35)
		tween.chain().tween_callback(spark.queue_free)


## Find nearest wreckage to a harvester.
func _find_nearest_wreckage(unit: Dictionary) -> Dictionary:
	if not is_instance_valid(unit.mesh) or _wreckage.is_empty():
		return {}

	var unit_pos: Vector3 = unit.mesh.position
	var nearest: Dictionary = {}
	var nearest_dist: float = INF

	for wreck in _wreckage:
		if wreck.ree_value <= 0.1:
			continue
		var dist: float = unit_pos.distance_to(wreck.position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = wreck

	return nearest


## Update AI faction behavior - spawning, attacking, economy.
func _update_faction_ai(delta: float) -> void:
	for faction_id in [1, 2, 3, 4]:
		# Skip player's faction
		if faction_id == _player_faction:
			continue
		# Skip if factory destroyed
		if _factories.has(faction_id) and _factories[faction_id].is_destroyed:
			continue

		# Passive income for AI
		if ResourceManager:
			ResourceManager.add_ree(faction_id, AI_PASSIVE_INCOME * delta, "ai_passive")

		# Check base defense - this takes priority over attacking
		var defending := _ai_check_base_defense(faction_id)

		# Update spawn timer
		_ai_spawn_timers[faction_id] = _ai_spawn_timers.get(faction_id, 0.0) + delta

		# Check if it's time to spawn
		if _ai_spawn_timers[faction_id] >= AI_SPAWN_INTERVAL:
			_ai_spawn_timers[faction_id] = 0.0
			_ai_make_spawn_decision(faction_id, defending)

		# Periodically order attacks based on aggression (but not if defending)
		if not defending and randf() < _ai_aggression.get(faction_id, 0.5) * delta * 0.5:
			_ai_order_attack(faction_id)


## Constants for AI base defense
const AI_DEFENSE_RADIUS := 50.0  # Radius around factory to check for threats
const AI_DEFENSE_THREAT_THRESHOLD := 2  # Number of enemies before triggering defense mode

## Check if AI's base is under attack and recall defenders if needed
## Returns true if in defense mode
func _ai_check_base_defense(faction_id: int) -> bool:
	var factory_pos: Vector3 = FACTORY_POSITIONS.get(faction_id, Vector3.ZERO)
	if factory_pos == Vector3.ZERO:
		return false

	# Count enemy units near our factory
	var threat_count := 0
	var threats: Array = []

	for unit in _units:
		if unit.is_dead:
			continue
		if unit.faction_id == faction_id:
			continue  # Skip own units
		if unit.get("is_harvester", false):
			continue  # Harvesters are low threat

		var dist: float = unit.mesh.position.distance_to(factory_pos) if is_instance_valid(unit.mesh) else INF
		if dist < AI_DEFENSE_RADIUS:
			threat_count += 1
			threats.append(unit)

	# If threats detected, recall units to defend
	if threat_count >= AI_DEFENSE_THREAT_THRESHOLD:
		_ai_recall_defenders(faction_id, factory_pos, threats)
		return true

	return false


## Recall friendly units to defend the factory
func _ai_recall_defenders(faction_id: int, factory_pos: Vector3, threats: Array) -> void:
	var max_defenders := mini(threats.size() + 2, 8)  # Recall proportional to threat

	# Find units to recall (prioritize nearby ones first)
	var available_units: Array = []
	for unit in _units:
		if unit.is_dead:
			continue
		if unit.faction_id != faction_id:
			continue
		if unit.get("is_harvester", false):
			continue

		# Don't recall units already at the factory
		var dist: float = unit.mesh.position.distance_to(factory_pos) if is_instance_valid(unit.mesh) else INF
		if dist < AI_DEFENSE_RADIUS * 0.8:
			continue  # Already close enough

		available_units.append({"unit": unit, "distance": dist})

	# Sort by distance (closest first)
	available_units.sort_custom(func(a, b): return a.distance < b.distance)

	# Get units to recall
	var units_to_recall: Array = []
	for i in mini(available_units.size(), max_defenders):
		units_to_recall.append(available_units[i].unit)

	if units_to_recall.is_empty():
		return

	# Calculate average threat direction
	var threat_center := Vector3.ZERO
	var valid_threats := 0
	for threat in threats:
		if is_instance_valid(threat.mesh):
			threat_center += threat.mesh.position
			valid_threats += 1
	if valid_threats > 0:
		threat_center /= valid_threats

	# Direction from factory toward threats
	var defense_direction := (threat_center - factory_pos).normalized()
	if defense_direction.length_squared() < 0.01:
		defense_direction = Vector3(0, 0, -1)

	# Get faction's preferred defense formation
	var formation_type: Formation = FACTION_FORMATIONS.get(faction_id, {"defense": Formation.LINE}).defense

	# Position defense formation between factory and threats (15 units in front of factory)
	var defense_point := factory_pos + defense_direction * 15.0

	# Get formation positions facing the threat
	var formation_positions := _get_formation_positions_for_type(
		defense_point, units_to_recall.size(), defense_direction, formation_type
	)

	# Sort defenders: heavies in front for BOX/WEDGE, lights in back
	if formation_type == Formation.BOX or formation_type == Formation.WEDGE:
		units_to_recall.sort_custom(func(a, b):
			var a_type: String = a.get("unit_type", "medium")
			var b_type: String = b.get("unit_type", "medium")
			var type_order := {"heavy": 0, "medium": 1, "light": 2}
			return type_order.get(a_type, 1) < type_order.get(b_type, 1)
		)

	# Assign formation positions to defenders
	for i in units_to_recall.size():
		if i < formation_positions.size():
			units_to_recall[i].target_pos = formation_positions[i]
			units_to_recall[i].attack_move = true  # Attack enemies on the way


## AI decides what unit to spawn based on resources and situation.
func _ai_make_spawn_decision(faction_id: int, is_defending: bool = false) -> void:
	if not ResourceManager:
		return

	var ree: float = ResourceManager.get_current_ree(faction_id)
	if ree < 30:  # Not enough for anything
		return

	var factory_pos: Vector3 = FACTORY_POSITIONS.get(faction_id, Vector3.ZERO)
	var offset := Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
	var spawn_pos := factory_pos + offset

	# Count units and harvesters
	var unit_count := 0
	var harvester_count := 0
	for unit in _units:
		if unit.faction_id == faction_id and not unit.is_dead:
			unit_count += 1
			if unit.get("is_harvester", false):
				harvester_count += 1

	# Decide what to spawn
	var unit_type := ""
	var cost := 0.0

	# When defending, prioritize combat units (no harvesters, prefer medium/heavy)
	if is_defending:
		if ree >= 120 and randf() < 0.5:  # 50% heavy when defending
			unit_type = "heavy"
			cost = 120.0
		elif ree >= 60:  # Medium preferred
			unit_type = "medium"
			cost = 60.0
		elif ree >= 30:  # Light as fallback
			unit_type = "light"
			cost = 30.0
		else:
			return
	else:
		# Normal spawn logic - need more harvesters?
		var harvester_needs := (harvester_count < 2) or (unit_count > 0 and float(harvester_count) / unit_count < AI_HARVESTER_RATIO)
		if harvester_needs and ree >= 50:
			unit_type = "harvester"
			cost = 50.0
		elif ree >= 120 and randf() < 0.2:  # 20% chance heavy
			unit_type = "heavy"
			cost = 120.0
		elif ree >= 60 and randf() < 0.5:  # 50% chance medium
			unit_type = "medium"
			cost = 60.0
		elif ree >= 30:  # Light unit
			unit_type = "light"
			cost = 30.0
		else:
			return  # Not enough

	# Consume resources and spawn using faction-specific templates
	if ResourceManager.consume_ree(faction_id, cost, "ai_production"):
		_track_stat(faction_id, "ree_spent", cost)
		var new_unit: Dictionary = _spawn_faction_unit(faction_id, spawn_pos, unit_type)
		# Spawn factory production effect for AI factions
		_spawn_factory_production_effect(factory_pos, faction_id)

		# Start unit ejection animation for AI units
		if _unit_ejection_animation != null and new_unit.has("mesh") and is_instance_valid(new_unit.mesh):
			var ejection_id: int = _unit_ejection_animation.start_ejection(
				new_unit.mesh,
				factory_pos,
				spawn_pos,
				faction_id,
				_effects_container
			)
			if ejection_id >= 0:
				_pending_ejections[ejection_id] = new_unit


## AI orders an attack on the nearest enemy.
func _ai_order_attack(faction_id: int) -> void:
	# Get idle combat units (not harvesters)
	var idle_units: Array = []
	for unit in _units:
		if unit.faction_id == faction_id and not unit.is_dead:
			if not unit.get("is_harvester", false):
				if unit.target_enemy == null:
					idle_units.append(unit)

	if idle_units.is_empty():
		return

	# Find nearest enemy factory or cluster
	var factory_pos: Vector3 = FACTORY_POSITIONS.get(faction_id, Vector3.ZERO)
	var nearest_enemy_pos: Vector3 = Vector3.ZERO
	var nearest_dist: float = INF

	# Check enemy factories
	for other_faction in FACTORY_POSITIONS:
		if other_faction == faction_id:
			continue
		if _factories.has(other_faction) and not _factories[other_faction].is_destroyed:
			var dist: float = factory_pos.distance_to(FACTORY_POSITIONS[other_faction])
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_enemy_pos = FACTORY_POSITIONS[other_faction]

	if nearest_dist < INF:
		# Send some idle units to attack in formation
		var attack_count := mini(idle_units.size(), 5)  # Send up to 5 units
		var units_to_send: Array = idle_units.slice(0, attack_count)

		# Get faction's preferred attack formation
		var formation_type: Formation = FACTION_FORMATIONS.get(faction_id, {"attack": Formation.LINE}).attack

		# Calculate center of attacking units
		var center := Vector3.ZERO
		for unit in units_to_send:
			if is_instance_valid(unit.mesh):
				center += unit.mesh.position
		center /= maxf(1, units_to_send.size())

		# Direction from units to target
		var direction := (nearest_enemy_pos - center).normalized()

		# Get formation positions
		var formation_positions := _get_formation_positions_for_type(
			nearest_enemy_pos, attack_count, direction, formation_type
		)

		# Assign formation positions to units (sort by unit type: heavies in front for certain formations)
		if formation_type == Formation.WEDGE or formation_type == Formation.BOX:
			units_to_send.sort_custom(func(a, b):
				var a_type: String = a.get("unit_type", "medium")
				var b_type: String = b.get("unit_type", "medium")
				var type_order := {"heavy": 0, "medium": 1, "light": 2}
				return type_order.get(a_type, 1) < type_order.get(b_type, 1)
			)

		for i in units_to_send.size():
			if i < formation_positions.size():
				units_to_send[i]["target_pos"] = formation_positions[i]
				units_to_send[i]["attack_move"] = true


func _show_game_over(is_victory: bool) -> void:
	if game_over_panel == null:
		return

	# Calculate additional stats
	var buildings_destroyed := 0
	if _city_renderer:
		var total := _city_renderer.get_building_count()
		# Estimate destroyed from building data (count those with 0 health)
		buildings_destroyed = _city_renderer.get_destroyed_building_count() if _city_renderer.has_method("get_destroyed_building_count") else 0

	var factories_destroyed := 0
	for faction_id in _factories:
		if _factories[faction_id].is_destroyed:
			factories_destroyed += 1

	var current_ree: float = 0.0
	if ResourceManager:
		current_ree = ResourceManager.get_current_ree(_player_faction)

	var total_units_produced := 0
	for unit in _units:
		if unit.faction_id == _player_faction:
			total_units_produced += 1

	# Set panel appearance
	game_over_panel.visible = true

	# Animate panel appearance
	game_over_panel.modulate.a = 0.0
	game_over_panel.scale = Vector2(0.8, 0.8)
	game_over_panel.pivot_offset = game_over_panel.size / 2

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_parallel(true)
	tween.tween_property(game_over_panel, "scale", Vector2(1.0, 1.0), 0.5)
	tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.3)

	if result_label:
		result_label.text = "VICTORY!" if is_victory else "DEFEAT"
		result_label.modulate = Color(0.2, 1.0, 0.3) if is_victory else Color(1.0, 0.3, 0.2)

	if stats_label:
		var duration := GameStateManager.get_formatted_duration()
		var player_stats := _get_faction_stats(_player_faction)
		var kd_ratio := float(player_stats.kills) / maxf(1.0, float(player_stats.deaths))

		# Build detailed stats string with comprehensive tracking
		var stats_text := ""
		stats_text += "COMBAT STATS\n"
		stats_text += "  Kills: %d\n" % player_stats.kills
		stats_text += "  Deaths: %d\n" % player_stats.deaths
		stats_text += "  K/D Ratio: %.2f\n" % kd_ratio
		stats_text += "  Damage Dealt: %.0f\n" % player_stats.damage_dealt
		stats_text += "  Damage Taken: %.0f\n" % player_stats.damage_taken
		if player_stats.highest_kill_streak > 1:
			stats_text += "  Best Kill Streak: %d\n" % player_stats.highest_kill_streak
		stats_text += "\n"
		stats_text += "ECONOMY\n"
		stats_text += "  Final REE: %d\n" % int(current_ree)
		stats_text += "  REE Earned: %.0f\n" % player_stats.ree_earned
		stats_text += "  REE Spent: %.0f\n" % player_stats.ree_spent
		stats_text += "  Units Produced: %d\n" % player_stats.units_produced
		stats_text += "\n"
		stats_text += "TERRITORY\n"
		stats_text += "  Districts Captured: %d\n" % player_stats.districts_captured
		stats_text += "  Factories Destroyed: %d/3\n" % factories_destroyed
		if player_stats.harvesters_killed > 0:
			stats_text += "  Harvesters Killed: %d\n" % player_stats.harvesters_killed
		if player_stats.abilities_used > 0:
			stats_text += "  Abilities Used: %d\n" % player_stats.abilities_used
		stats_text += "\n"
		stats_text += "TIME: %s" % duration

		stats_label.text = stats_text

	# Play appropriate sound and trigger dynamic music
	if is_victory:
		_play_ui_sound("notification")  # Victory chime
		_play_explosion_sound(Vector3.ZERO, 0.5)
		if _audio_manager and _audio_manager.get_music_manager():
			_audio_manager.get_music_manager().trigger_victory()
	else:
		_play_ui_sound("error")  # Defeat sound
		_play_explosion_sound(Vector3.ZERO, 1.5)
		if _audio_manager and _audio_manager.get_music_manager():
			_audio_manager.get_music_manager().trigger_defeat()


func _handle_left_click(screen_pos: Vector2) -> void:
	# Deselect all first (units and factory)
	_deselect_all_units()
	_deselect_factory()

	# Check for factory click first
	var world_pos := _screen_to_world(screen_pos)
	if world_pos != Vector3.ZERO:
		# Check if clicked on player's factory
		var factory_pos: Vector3 = FACTORY_POSITIONS.get(_player_faction, Vector3.ZERO)
		if factory_pos.distance_to(world_pos) < 35.0:  # Factory click radius (factory is 50x50)
			_select_factory()
			return

		# Simple selection - find unit near click
		for unit in _units:
			if unit.is_dead or unit.faction_id != _player_faction:
				continue
			if is_instance_valid(unit.mesh):
				if unit.mesh.position.distance_to(world_pos) < 3.0:
					_select_unit(unit)
					break


func _handle_right_click(screen_pos: Vector2) -> void:
	if _selected_units.is_empty():
		return

	var world_pos := _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		return

	# Check if clicking on ruins while having a builder selected
	var has_builder := false
	for unit in _selected_units:
		if unit.get("unit_class", "") == "builder" or unit.get("is_harvester", false):
			has_builder = true
			break

	if has_builder:
		var ruins := _find_ruins_at(world_pos)
		if not ruins.is_empty():
			# Start factory construction at ruins location
			_start_construction_at_ruins(ruins.position)
			return

	# Normal move command
	# Play move command sound
	_play_move_command_sound()

	# Spawn move indicator
	_spawn_move_indicator(world_pos)

	# Visual command feedback
	_spawn_command_text(world_pos, "MOVE", Color(0.3, 1.0, 0.3))
	_flash_units_on_command(_selected_units, Color(0.5, 1.0, 0.5))
	_spawn_command_lines(_selected_units, world_pos, Color(0.3, 1.0, 0.3, 0.4))

	# Move units in formation
	_move_units_in_formation(world_pos, false)


## Deselect all units and clear selection indicators.
func _deselect_all_units() -> void:
	for unit in _units:
		if unit.is_selected:
			unit.is_selected = false
			_remove_selection_indicator(unit)
	_selected_units.clear()


## Select the player's factory.
func _select_factory() -> void:
	_factory_selected = true
	_play_ui_sound("select")
	print("Factory selected - use production panel or Shift+1-4 to queue units")

	# Show the factory production panel
	if _factory_production_panel:
		_factory_production_panel.visible = true
		_update_factory_production_panel()

	# Add selection ring around factory
	_add_factory_selection_ring()


## Deselect the factory.
func _deselect_factory() -> void:
	if not _factory_selected:
		return

	_factory_selected = false

	# Hide the factory production panel
	if _factory_production_panel:
		_factory_production_panel.visible = false

	# Remove factory selection ring
	_remove_factory_selection_ring()


## Add selection ring around factory.
func _add_factory_selection_ring() -> void:
	if not _factories.has(_player_faction):
		return

	var factory: Dictionary = _factories[_player_faction]
	if factory.has("selection_ring") and is_instance_valid(factory.selection_ring):
		return

	var ring := CSGTorus3D.new()
	ring.name = "FactorySelectionRing"
	ring.inner_radius = 18.0
	ring.outer_radius = 20.0
	ring.ring_sides = 32
	ring.sides = 12

	var mat := StandardMaterial3D.new()
	var faction_color: Color = FACTION_COLORS.get(_player_faction, Color.WHITE)
	mat.albedo_color = Color(faction_color.r, faction_color.g, faction_color.b, 0.7)
	mat.emission_enabled = true
	mat.emission = faction_color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat

	var factory_pos: Vector3 = FACTORY_POSITIONS.get(_player_faction, Vector3.ZERO)
	ring.position = factory_pos
	ring.position.y = 0.3
	ring.rotation_degrees.x = 90

	_effects_container.add_child(ring)
	factory["selection_ring"] = ring


## Remove factory selection ring.
func _remove_factory_selection_ring() -> void:
	if not _factories.has(_player_faction):
		return

	var factory: Dictionary = _factories[_player_faction]
	if factory.has("selection_ring") and is_instance_valid(factory.selection_ring):
		factory.selection_ring.queue_free()
		factory.selection_ring = null


## Select a single unit and add selection indicator.
func _select_unit(unit: Dictionary) -> void:
	if unit.is_dead or unit.faction_id != _player_faction:
		return
	# Play select sound only for first unit in selection batch
	if _selected_units.is_empty():
		_play_select_sound()
	unit.is_selected = true
	_selected_units.append(unit)
	_add_selection_indicator(unit)


## Add green selection ring under a unit.
func _add_selection_indicator(unit: Dictionary) -> void:
	if not is_instance_valid(unit.mesh):
		return

	# Don't add duplicate indicator
	if unit.has("selection_ring") and is_instance_valid(unit.selection_ring):
		return

	var ring := CSGTorus3D.new()
	ring.name = "SelectionRing"
	ring.inner_radius = 1.2
	ring.outer_radius = 1.6
	ring.ring_sides = 16
	ring.sides = 8

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.3, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.3)
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat

	# Position at unit's feet
	ring.position = unit.mesh.position
	ring.position.y = 0.2  # Just above ground
	ring.rotation_degrees.x = 90  # Lay flat

	_effects_container.add_child(ring)
	unit["selection_ring"] = ring


## Remove selection indicator from a unit.
func _remove_selection_indicator(unit: Dictionary) -> void:
	if unit.has("selection_ring") and is_instance_valid(unit.selection_ring):
		unit.selection_ring.queue_free()
		unit.selection_ring = null


## Update visual position of selection box.
func _update_selection_box_visual() -> void:
	if _selection_box == null:
		return

	# Calculate rect from start and end points
	var min_x := minf(_box_select_start.x, _box_select_end.x)
	var min_y := minf(_box_select_start.y, _box_select_end.y)
	var max_x := maxf(_box_select_start.x, _box_select_end.x)
	var max_y := maxf(_box_select_start.y, _box_select_end.y)

	_selection_box.position = Vector2(min_x, min_y)
	_selection_box.size = Vector2(max_x - min_x, max_y - min_y)
	_selection_box.visible = true


## Hide the selection box.
func _hide_selection_box() -> void:
	if _selection_box:
		_selection_box.visible = false


## Complete box selection - select all player units within the box.
func _finish_box_selection() -> void:
	_deselect_all_units()

	# Calculate screen-space selection rect
	var min_x := minf(_box_select_start.x, _box_select_end.x)
	var min_y := minf(_box_select_start.y, _box_select_end.y)
	var max_x := maxf(_box_select_start.x, _box_select_end.x)
	var max_y := maxf(_box_select_start.y, _box_select_end.y)
	var selection_rect := Rect2(min_x, min_y, max_x - min_x, max_y - min_y)

	# Check each player unit
	for unit in _units:
		if unit.is_dead or unit.faction_id != _player_faction:
			continue
		if not is_instance_valid(unit.mesh):
			continue

		# Project unit position to screen
		var screen_pos := camera.unproject_position(unit.mesh.global_position)

		# Check if unit is on screen and within selection box
		if camera.is_position_behind(unit.mesh.global_position):
			continue

		if selection_rect.has_point(screen_pos):
			_select_unit(unit)


## Spawn a visual indicator where units are ordered to move.
func _spawn_move_indicator(world_pos: Vector3) -> void:
	# Create a small ring that pulses and fades
	var ring := CSGTorus3D.new()
	ring.name = "MoveIndicator"
	ring.inner_radius = 1.0
	ring.outer_radius = 1.5
	ring.ring_sides = 16
	ring.sides = 6
	ring.position = world_pos
	ring.position.y = 0.3
	ring.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.3, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.3)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat

	_effects_container.add_child(ring)

	# Animate expanding and fading
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(2.0, 2.0, 2.0), 0.5)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.chain().tween_callback(ring.queue_free)


## Spawn attack-move indicator (red/orange ring).
func _spawn_attack_move_indicator(world_pos: Vector3) -> void:
	var ring := CSGTorus3D.new()
	ring.name = "AttackMoveIndicator"
	ring.inner_radius = 1.0
	ring.outer_radius = 1.5
	ring.ring_sides = 16
	ring.sides = 6
	ring.position = world_pos
	ring.position.y = 0.3
	ring.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.2, 0.9)  # Orange for attack-move
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.1)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat

	_effects_container.add_child(ring)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(2.0, 2.0, 2.0), 0.5)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tween.chain().tween_callback(ring.queue_free)


## Spawn command text at world position (MOVE, ATTACK, STOP, etc).
func _spawn_command_text(world_pos: Vector3, command: String, color: Color) -> void:
	var label := Label3D.new()
	label.name = "CommandText"
	label.text = command
	label.font_size = 48
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = world_pos + Vector3(0, 3.0, 0)
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.8)

	_effects_container.add_child(label)

	# Float up and fade out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", world_pos.y + 8.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


## Flash selected units to show they received a command.
func _flash_units_on_command(units: Array, color: Color) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	for unit in units:
		if unit.is_dead or not is_instance_valid(unit.mesh):
			continue
		var unit_id: int = unit.get("id", 0)
		var original_color := Color.WHITE

		# Get original color based on mesh type
		if unit.mesh is MeshInstance3D:
			var mat = unit.mesh.get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				original_color = mat.albedo_color
		elif unit.mesh.has_method("get") and unit.mesh.get("material") != null:
			var mat = unit.mesh.get("material")
			if mat is StandardMaterial3D:
				original_color = mat.albedo_color

		_unit_command_flash[unit_id] = {
			"end_time": current_time + 0.3,
			"color": color,
			"original_color": original_color
		}

		# Apply flash color based on mesh type
		if unit.mesh is MeshInstance3D:
			var mat = unit.mesh.get_surface_override_material(0)
			if mat and mat is StandardMaterial3D:
				mat.albedo_color = color
		elif unit.mesh.has_method("get") and unit.mesh.get("material") != null:
			var mat = unit.mesh.get("material")
			if mat is StandardMaterial3D:
				mat.albedo_color = color


## Spawn lines from units to their target position.
func _spawn_command_lines(units: Array, target_pos: Vector3, color: Color) -> void:
	# Clear old command lines
	for line in _command_lines:
		if is_instance_valid(line):
			line.queue_free()
	_command_lines.clear()

	# Create new lines from each unit to target
	for unit in units:
		if unit.is_dead or not is_instance_valid(unit.mesh):
			continue
		var start_pos: Vector3 = unit.mesh.position
		start_pos.y = 0.5
		var end_pos := Vector3(target_pos.x, 0.5, target_pos.z)

		# Create line using ImmediateMesh
		var mesh_instance := MeshInstance3D.new()
		var imm_mesh := ImmediateMesh.new()
		mesh_instance.mesh = imm_mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = true
		mesh_instance.material_override = mat

		imm_mesh.clear_surfaces()
		imm_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		imm_mesh.surface_set_color(color)
		imm_mesh.surface_add_vertex(start_pos)
		imm_mesh.surface_set_color(color)
		imm_mesh.surface_add_vertex(end_pos)
		imm_mesh.surface_end()

		_effects_container.add_child(mesh_instance)
		_command_lines.append(mesh_instance)

	# Fade out and remove lines
	if not _command_lines.is_empty():
		var tween := create_tween()
		for line in _command_lines:
			if is_instance_valid(line) and line.material_override:
				tween.parallel().tween_property(line.material_override, "albedo_color:a", 0.0, 0.5)
		tween.tween_callback(_clear_command_lines)


## Clear command lines after fade.
func _clear_command_lines() -> void:
	for line in _command_lines:
		if is_instance_valid(line):
			line.queue_free()
	_command_lines.clear()


## Update command flash effects on units.
func _update_command_flash() -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	var to_remove: Array[int] = []

	for unit_id in _unit_command_flash:
		var flash_data: Dictionary = _unit_command_flash[unit_id]
		if current_time >= flash_data.end_time:
			# Find unit and restore original color
			for unit in _units:
				if unit.get("id", -1) == unit_id and is_instance_valid(unit.mesh):
					# Restore color based on mesh type
					if unit.mesh is MeshInstance3D:
						var mat = unit.mesh.get_surface_override_material(0)
						if mat and mat is StandardMaterial3D:
							mat.albedo_color = flash_data.original_color
					elif unit.mesh.has_method("get") and unit.mesh.get("material") != null:
						var mat = unit.mesh.get("material")
						if mat is StandardMaterial3D:
							mat.albedo_color = flash_data.original_color
					break
			to_remove.append(unit_id)

	for unit_id in to_remove:
		_unit_command_flash.erase(unit_id)


## Handle attack-move click - units move to position but attack enemies on the way.
func _handle_attack_move_click(screen_pos: Vector2) -> void:
	if _selected_units.is_empty():
		return

	var world_pos := _screen_to_world(screen_pos)
	if world_pos != Vector3.ZERO:
		# Play attack command sound
		_play_attack_command_sound()

		_spawn_attack_move_indicator(world_pos)

		# Visual command feedback
		_spawn_command_text(world_pos, "ATTACK", Color(1.0, 0.5, 0.2))
		_flash_units_on_command(_selected_units, Color(1.0, 0.6, 0.3))
		_spawn_command_lines(_selected_units, world_pos, Color(1.0, 0.5, 0.2, 0.4))

		# Move units in formation with attack-move enabled
		_move_units_in_formation(world_pos, true)


## Stop all selected units.
func _stop_selected_units() -> void:
	if _selected_units.is_empty():
		return

	# Play stop acknowledgment sound
	_play_stop_command_sound()

	# Visual feedback for stop command
	if not _selected_units.is_empty():
		var center_pos := Vector3.ZERO
		var count := 0
		for unit in _selected_units:
			if not unit.is_dead and is_instance_valid(unit.mesh):
				center_pos += unit.mesh.position
				count += 1
		if count > 0:
			center_pos /= count
			_spawn_command_text(center_pos, "STOP", Color(1.0, 0.3, 0.3))
			_flash_units_on_command(_selected_units, Color(1.0, 0.4, 0.4))

	for unit in _selected_units:
		if not unit.is_dead:
			unit.target_pos = null
			unit.target_enemy = null
			unit["attack_move"] = false
			# Stop at current position
			if is_instance_valid(unit.mesh):
				unit.target_pos = unit.mesh.position


## Save current selection to a control group.
func _save_control_group(group_num: int) -> void:
	if _selected_units.is_empty():
		return

	# Create a copy of the current selection
	var group: Array = []
	for unit in _selected_units:
		if not unit.is_dead:
			group.append(unit)

	_control_groups[group_num] = group
	print("Saved %d units to group %d" % [group.size(), group_num])

	# Play sound
	if _should_play_sound():
		_play_ui_sound("click")


## Check if a control group has alive units.
func _has_control_group(group_num: int) -> bool:
	if not _control_groups.has(group_num):
		return false

	var group: Array = _control_groups[group_num]
	if group.is_empty():
		return false

	# Check if any units in the group are still alive
	for unit in group:
		if unit is Dictionary and not unit.get("is_dead", false):
			return true
		elif unit is Node and is_instance_valid(unit) and not unit.get_meta("is_dead", false):
			return true

	return false


## Recall units from a control group.
func _recall_control_group(group_num: int) -> void:
	if not _control_groups.has(group_num):
		return

	# Check for double-tap to center camera
	var current_time: float = Time.get_ticks_msec() / 1000.0
	if _last_group_tap_num == group_num and (current_time - _last_group_tap_time) < GROUP_DOUBLE_TAP_TIME:
		# Double-tap detected - center camera on group
		_center_camera_on_group(group_num)
		_last_group_tap_num = 0
		_last_group_tap_time = 0.0
		return

	_last_group_tap_num = group_num
	_last_group_tap_time = current_time

	var group: Array = _control_groups[group_num]

	# Deselect current selection
	_deselect_all_units()

	# Select units from the group (skip dead ones)
	for unit in group:
		if not unit.is_dead:
			_select_unit(unit)

	# Clean up dead units from the group
	var alive_units: Array = []
	for unit in group:
		if not unit.is_dead:
			alive_units.append(unit)
	_control_groups[group_num] = alive_units

	if not _selected_units.is_empty():
		print("Recalled group %d (%d units)" % [group_num, _selected_units.size()])


## Toggle help overlay showing keyboard shortcuts.
func _toggle_help_overlay() -> void:
	# Delegate to the comprehensive hotkey overlay
	_toggle_hotkey_overlay()


## Enter rally point mode.
func _set_rally_point_mode() -> void:
	_rally_point_mode = true
	print("Rally point mode: Click to set factory rally point")


## Set rally point for player factory.
func _set_rally_point(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		return

	# Set rally point for player faction
	_rally_points[1] = world_pos

	# Create or update rally point indicator
	_spawn_rally_point_indicator(world_pos)

	print("Rally point set at %v" % world_pos)


## Create a visual indicator for the rally point.
func _spawn_rally_point_indicator(world_pos: Vector3) -> void:
	# Remove existing indicator
	if _rally_point_indicator != null and is_instance_valid(_rally_point_indicator):
		_rally_point_indicator.queue_free()

	# Create a flag-like indicator
	var container := Node3D.new()
	container.name = "RallyPointIndicator"
	container.position = world_pos

	# Pole
	var pole := CSGCylinder3D.new()
	pole.radius = 0.15
	pole.height = 5.0
	pole.position = Vector3(0, 2.5, 0)

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.5, 0.5, 0.5)
	pole.material = pole_mat
	container.add_child(pole)

	# Flag (banner)
	var flag := CSGBox3D.new()
	flag.size = Vector3(2.0, 1.5, 0.1)
	flag.position = Vector3(1.0, 4.5, 0)

	var flag_mat := StandardMaterial3D.new()
	flag_mat.albedo_color = Color(0.2, 0.8, 0.3, 0.9)
	flag_mat.emission_enabled = true
	flag_mat.emission = Color(0.2, 0.8, 0.3)
	flag_mat.emission_energy_multiplier = 1.5
	flag.material = flag_mat
	container.add_child(flag)

	# Base ring
	var ring := CSGTorus3D.new()
	ring.inner_radius = 0.8
	ring.outer_radius = 1.2
	ring.ring_sides = 16
	ring.sides = 6
	ring.position = Vector3(0, 0.2, 0)
	ring.rotation_degrees.x = 90

	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.2, 0.8, 0.3, 0.8)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.2, 0.8, 0.3)
	ring_mat.emission_energy_multiplier = 2.0
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = ring_mat
	container.add_child(ring)

	_effects_container.add_child(container)
	_rally_point_indicator = container

	# Create visual line from factory to rally point
	_create_rally_line(world_pos)


## Create a dashed line from factory to rally point.
func _create_rally_line(rally_pos: Vector3) -> void:
	# Remove existing line
	if _rally_line != null and is_instance_valid(_rally_line):
		_rally_line.queue_free()
		_rally_line = null

	# Get factory position
	var factory_pos: Vector3 = FACTORY_POSITIONS.get(1, Vector3.ZERO)
	factory_pos.y = 0.5  # Slightly above ground
	rally_pos.y = 0.5

	# Calculate line properties
	var direction := (rally_pos - factory_pos).normalized()
	var distance := factory_pos.distance_to(rally_pos)

	if distance < 5.0:
		return  # Too close, no line needed

	# Create line mesh (stretched box)
	_rally_line = MeshInstance3D.new()
	_rally_line.name = "RallyLine"

	var box := BoxMesh.new()
	box.size = Vector3(distance, 0.2, 0.3)
	_rally_line.mesh = box

	# Material - dashed effect via transparency
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 0.3, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 0.3)
	mat.emission_energy_multiplier = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rally_line.set_surface_override_material(0, mat)

	# Position and rotate the line
	var mid_point := (factory_pos + rally_pos) / 2.0
	_rally_line.position = mid_point
	_rally_line.look_at(rally_pos, Vector3.UP)
	_rally_line.rotation.x = 0
	_rally_line.rotation.z = 0

	_effects_container.add_child(_rally_line)


## Get rally point for a faction (returns spawn position if no rally point set).
func _get_rally_point(faction_id: int) -> Vector3:
	if _rally_points.has(faction_id):
		return _rally_points[faction_id]
	# Default to near factory
	return FACTORY_POSITIONS.get(faction_id, Vector3.ZERO) + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15))


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)

	# Intersect with ground plane (y = 0)
	if dir.y != 0:
		var t := -from.y / dir.y
		if t > 0:
			return from + dir * t

	return Vector3.ZERO


## Find a unit by its ID. Returns empty dict if not found.
func _get_unit_by_id(unit_id: int) -> Dictionary:
	for unit in _units:
		if unit.get("id", -1) == unit_id:
			return unit
	return {}


## PhaseShift callback: Get all unit IDs for a faction
func _get_faction_unit_ids(faction_id: String) -> Array:
	var ids: Array = []
	var int_faction := 0
	# Convert string faction ID to int
	for key in FACTION_ID_TO_STRING:
		if FACTION_ID_TO_STRING[key] == faction_id:
			int_faction = key
			break

	for unit in _units:
		if unit.faction_id == int_faction and not unit.is_dead:
			ids.append(unit.get("id", 0))
	return ids


## PhaseShift callback: Get unit position by ID
func _get_unit_position_by_id(unit_id: int) -> Vector3:
	for unit in _units:
		if unit.get("id", 0) == unit_id and not unit.is_dead:
			if is_instance_valid(unit.mesh):
				return unit.mesh.position
	return Vector3.ZERO


## PhaseShift callback: Set unit collision (stub - visual game has no collision)
func _set_unit_collision_by_id(unit_id: int, enabled: bool) -> void:
	# In this visual prototype, units don't use physics collision
	# This would disable Area3D or CollisionShape3D in a full implementation
	pass


## PhaseShift callback: Set unit visual alpha for phase effect
func _set_unit_visual_alpha_by_id(unit_id: int, alpha: float) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id:
			if is_instance_valid(unit.mesh):
				var mat: StandardMaterial3D = _get_unit_material(unit.mesh)
				if mat:
					# Enable transparency if phasing
					if alpha < 1.0:
						mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						mat.albedo_color.a = alpha
						mat.emission_energy_multiplier = 3.0  # Glow while phased
					else:
						mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
						mat.albedo_color.a = 1.0
						mat.emission_energy_multiplier = 0.4  # Normal emission
			break


## Overclock callback: Apply self-damage to overclocked unit
func _apply_overclock_self_damage(unit_id: int, damage: float) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id and not unit.is_dead:
			unit.health -= damage
			# Update health bar
			if is_instance_valid(unit.health_bar):
				var fill: Node3D = unit.health_bar.get_node_or_null("Fill")
				if fill:
					var health_pct := maxf(0.0, unit.health / unit.max_health)
					fill.scale.x = health_pct
					fill.position.x = -(1.0 - health_pct)
			# Check for death from self-damage
			if unit.health <= 0:
				unit.is_dead = true
				GameStateManager.record_unit_lost(unit.faction_id)
				if is_instance_valid(unit.mesh):
					_spawn_explosion(unit.mesh.position, unit.faction_id)
			break


## Overclock callback: Set unit emission intensity (heat glow)
func _set_unit_emission_by_id(unit_id: int, intensity: float) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id:
			if is_instance_valid(unit.mesh):
				var mat: StandardMaterial3D = _get_unit_material(unit.mesh)
				if mat:
					mat.emission_energy_multiplier = intensity
					# Add orange tint when overclocked
					if intensity > 1.0:
						mat.emission = Color(1.0, 0.5, 0.2)  # Orange heat glow
					else:
						mat.emission = FACTION_COLORS.get(unit.faction_id, Color.WHITE)
			break


## Siege Formation callback: Set unit can move flag
func _set_unit_can_move_by_id(unit_id: int, can_move: bool) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id:
			unit["siege_locked"] = not can_move
			break


## Siege Formation callback: Set unit deployed visual
func _set_unit_deployed_visual_by_id(unit_id: int, deployed: bool) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id:
			if is_instance_valid(unit.mesh):
				var mat: StandardMaterial3D = _get_unit_material(unit.mesh)
				if mat:
					if deployed:
						# Darker color when deployed (siege mode)
						mat.emission_energy_multiplier = 1.5
						mat.emission = Color(0.8, 0.8, 0.2)  # Amber deployed glow
					else:
						# Normal appearance
						mat.emission_energy_multiplier = 0.4
						mat.emission = FACTION_COLORS.get(unit.faction_id, Color.WHITE)
			break


## NanoReplication callback: Get unit current health
func _get_unit_health_by_id(unit_id: int) -> float:
	for unit in _units:
		if unit.get("id", 0) == unit_id and not unit.is_dead:
			return unit.health
	return 0.0


## NanoReplication callback: Get unit max health
func _get_unit_max_health_by_id(unit_id: int) -> float:
	for unit in _units:
		if unit.get("id", 0) == unit_id and not unit.is_dead:
			return unit.max_health
	return 100.0


## NanoReplication callback: Apply healing to unit
func _apply_healing_to_unit_by_id(unit_id: int, amount: float) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id and not unit.is_dead:
			var old_health: float = unit.health
			unit.health = minf(unit.health + amount, unit.max_health)
			# Update health bar
			if is_instance_valid(unit.health_bar):
				var fill: Node3D = unit.health_bar.get_node_or_null("Fill")
				if fill:
					var health_pct := maxf(0.0, unit.health / unit.max_health)
					fill.scale.x = health_pct
					fill.position.x = -(1.0 - health_pct)
			break


## EtherCloak callback: Set unit targetable flag
func _set_unit_targetable_by_id(unit_id: int, targetable: bool) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id:
			unit["is_cloaked"] = not targetable
			break


## EtherCloak callback: Set unit cloak visual
func _set_unit_visual_cloak_by_id(unit_id: int, cloaked: bool, alpha: float) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id:
			if is_instance_valid(unit.mesh):
				var mat: StandardMaterial3D = _get_unit_material(unit.mesh)
				if mat:
					if cloaked:
						# Make semi-transparent with shimmer
						mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
						mat.albedo_color.a = alpha
						mat.emission_energy_multiplier = 2.0
						mat.emission = Color(0.5, 0.8, 1.0)  # Cyan shimmer
					else:
						# Restore normal appearance
						mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
						mat.albedo_color.a = 1.0
						mat.emission_energy_multiplier = 0.4
						mat.emission = FACTION_COLORS.get(unit.faction_id, Color.WHITE)
			# Also hide/show health bar
			if is_instance_valid(unit.health_bar):
				unit.health_bar.visible = not cloaked
			break


## AcrobaticStrike callback: Get enemies in radius
func _get_enemies_in_radius(position: Vector3, radius: float) -> Array:
	var enemies: Array = []
	for unit in _units:
		if unit.is_dead:
			continue
		# Get units from opposing factions (not faction 3 = Dynapods)
		if unit.faction_id != 3:
			if is_instance_valid(unit.mesh):
				var dist: float = unit.mesh.position.distance_to(position)
				if dist <= radius:
					enemies.append({
						"id": unit.get("id", 0),
						"position": unit.mesh.position,
						"faction_id": unit.faction_id
					})
	return enemies


## AcrobaticStrike callback: Apply damage to unit by ID
func _apply_damage_to_unit_by_id(unit_id: int, damage: float) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id and not unit.is_dead:
			unit.health -= damage
			# Update health bar
			if is_instance_valid(unit.health_bar):
				var fill: Node3D = unit.health_bar.get_node_or_null("Fill")
				if fill:
					var health_pct := maxf(0.0, unit.health / unit.max_health)
					fill.scale.x = health_pct
					fill.position.x = -(1.0 - health_pct)
			# Check for death
			if unit.health <= 0:
				unit.is_dead = true
				GameStateManager.record_unit_lost(unit.faction_id)
				if is_instance_valid(unit.mesh):
					_spawn_explosion(unit.mesh.position, unit.faction_id)
			break


## AcrobaticStrike callback: Set unit position by ID
func _set_unit_position_by_id(unit_id: int, position: Vector3) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id and not unit.is_dead:
			if is_instance_valid(unit.mesh):
				unit.mesh.position = position
			break


## CoordinatedBarrage callback: Set unit target by ID
func _set_unit_target_by_id(unit_id: int, target_id: int) -> void:
	for unit in _units:
		if unit.get("id", 0) == unit_id and not unit.is_dead:
			unit["barrage_target_id"] = target_id
			break


## CoordinatedBarrage callback: Check if unit is alive by ID
func _is_unit_alive_by_id(unit_id: int) -> bool:
	for unit in _units:
		if unit.get("id", 0) == unit_id:
			return not unit.is_dead
	return false


## Building destroyed callback - spawns REE pickup and tracks ruins
func _on_building_destroyed(building_id: int, position: Vector3, ree_amount: float) -> void:
	# Spawn collectible REE drop
	_spawn_ree_drop(position, ree_amount)

	# Track ruins for factory placement
	_building_ruins.append({
		"position": position,
		"age": 0.0
	})
	# Create ruins visual indicator (rubble marker)
	_create_ruins_marker(position)

	# Play explosion sound
	_play_explosion_sound(position, 0.6)

	# Log destruction
	print("Building %d destroyed at %s, dropped %.1f REE" % [building_id, position, ree_amount])


## Create visual marker for building ruins (construction site indicator)
func _create_ruins_marker(position: Vector3) -> void:
	var marker := Node3D.new()
	marker.name = "RuinsMarker"
	marker.position = position

	# Create rubble base plate (flat disk)
	var plate := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = 8.0
	cylinder_mesh.bottom_radius = 8.0
	cylinder_mesh.height = 0.3
	plate.mesh = cylinder_mesh
	plate.position = Vector3(0, 0.15, 0)

	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.3, 0.25, 0.2, 0.6)
	plate_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plate.material_override = plate_mat
	marker.add_child(plate)

	# Create construction icon (diamond outline) to indicate buildable area
	var icon := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(2.0, 3.0, 2.0)
	icon.mesh = prism
	icon.position = Vector3(0, 3.0, 0)

	var icon_mat := StandardMaterial3D.new()
	icon_mat.albedo_color = Color(0.3, 1.0, 0.5, 0.4)
	icon_mat.emission_enabled = true
	icon_mat.emission = Color(0.3, 0.8, 0.4)
	icon_mat.emission_energy_multiplier = 1.0
	icon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	icon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	icon.material_override = icon_mat
	marker.add_child(icon)

	# Store marker reference in ruins data
	for ruins in _building_ruins:
		if ruins.position.distance_to(position) < 1.0:
			ruins["marker"] = marker
			break

	_effects_container.add_child(marker)

	# Animate icon rotation and bobbing (bind to marker so tween dies with marker)
	var tween := marker.create_tween().set_loops()
	tween.tween_property(icon, "rotation:y", TAU, 4.0).from(0.0)


## Update ruins aging and cleanup
func _update_ruins(delta: float) -> void:
	var to_remove: Array[int] = []

	for i in range(_building_ruins.size()):
		_building_ruins[i].age += delta
		if _building_ruins[i].age >= RUINS_MAX_AGE:
			to_remove.append(i)
			# Remove marker
			if _building_ruins[i].has("marker"):
				var marker = _building_ruins[i].marker
				if is_instance_valid(marker):
					marker.queue_free()

	# Remove old ruins (reverse order to preserve indices)
	for i in range(to_remove.size() - 1, -1, -1):
		_building_ruins.remove_at(to_remove[i])


## Find ruins near a world position
func _find_ruins_at(world_pos: Vector3) -> Dictionary:
	var nearest_dist := INF
	var nearest: Dictionary = {}

	for ruins in _building_ruins:
		var dist: float = world_pos.distance_to(ruins.position)
		if dist < RUINS_PLACEMENT_RADIUS and dist < nearest_dist:
			nearest_dist = dist
			nearest = ruins

	return nearest


## Building damaged callback
func _on_building_damaged(building_id: int, health_percent: float) -> void:
	# Could add visual/audio feedback here
	pass


## Voxel destroyed callback - spawns REE pickup from terrain destruction
func _on_voxel_destroyed(position: Vector3i) -> void:
	# Base REE value for destroyed voxel
	var base_ree := 10.0

	# Convert to world position for spawning
	var world_pos := Vector3(position.x, 0, position.z)

	# Spawn REE drop
	_spawn_ree_drop(world_pos, base_ree)

	# Play destruction sound
	_play_explosion_sound(world_pos, 0.3)

	# Screen shake for nearby destruction
	var camera_dist := camera.global_position.distance_to(world_pos)
	if camera_dist < 100.0:
		_trigger_screen_shake(0.5 * (1.0 - camera_dist / 100.0))


## Get navigation path from start to end position using dynamic navmesh.
func get_navigation_path(start: Vector3, end: Vector3) -> PackedVector3Array:
	if _navmesh_manager != null:
		return _navmesh_manager.find_path(start, end)
	# Fallback: direct path
	return PackedVector3Array([start, end])


## Get closest navigable point on navmesh.
func get_closest_navigable_point(pos: Vector3) -> Vector3:
	if _navmesh_manager != null:
		return _navmesh_manager.get_closest_point(pos)
	return pos


## Check if position is on the navigation mesh.
func is_position_navigable(pos: Vector3) -> bool:
	if _navmesh_manager != null:
		return _navmesh_manager.is_point_on_navmesh(pos)
	return true  # Assume navigable if no navmesh


## Get navigation map RID for NavigationAgent3D nodes.
func get_navigation_map() -> RID:
	if _navmesh_manager != null:
		return _navmesh_manager.get_navigation_map()
	return RID()


## Spawn collectible REE drop as glowing crystal
func _spawn_ree_drop(position: Vector3, amount: float) -> void:
	# Create crystal container
	var crystal_container := Node3D.new()
	crystal_container.position = position + Vector3(0, 3, 0)
	crystal_container.name = "REECrystal"

	# Determine crystal size based on amount (small/medium/large)
	var size_scale: float = 1.0
	if amount >= 100:
		size_scale = 1.5  # Large crystal
	elif amount >= 50:
		size_scale = 1.2  # Medium crystal

	# Create crystal shape (hexagonal prism with pointed ends)
	var crystal_mesh := _create_crystal_mesh(size_scale)
	crystal_container.add_child(crystal_mesh)

	# Add inner glow core
	var core := CSGSphere3D.new()
	core.radius = 0.3 * size_scale
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.8, 1.0, 0.8, 0.8)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.5, 1.0, 0.6)
	core_mat.emission_energy_multiplier = 5.0
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material = core_mat
	crystal_container.add_child(core)

	_effects_container.add_child(crystal_container)

	# Track this pickup
	_ree_pickups.append({
		"mesh": crystal_container,
		"crystal": crystal_mesh,
		"core": core,
		"position": position + Vector3(0, 3, 0),
		"amount": amount,
		"lifetime": REE_PICKUP_LIFETIME,
		"bob_offset": randf() * TAU,  # Random starting phase for bobbing
		"rotation_speed": randf_range(0.5, 1.5)  # Random rotation speed
	})


## Create crystal mesh geometry
func _create_crystal_mesh(scale: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()

	# Use prism shape for crystal
	var prism := PrismMesh.new()
	prism.size = Vector3(0.6, 1.8, 0.6) * scale
	mesh_instance.mesh = prism

	# Crystal material - translucent green with emission
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.9, 0.35, 0.85)  # Translucent green
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.4)
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED  # See both sides
	mat.rim_enabled = true
	mat.rim = 0.5
	mat.rim_tint = 0.3
	mesh_instance.material_override = mat

	return mesh_instance


## Update REE pickups - check for collection and animate
func _update_ree_pickups(delta: float) -> void:
	var to_remove: Array = []

	for pickup in _ree_pickups:
		if not is_instance_valid(pickup.mesh):
			to_remove.append(pickup)
			continue

		# Update lifetime
		pickup.lifetime -= delta
		if pickup.lifetime <= 0:
			# Fade out and remove
			pickup.mesh.queue_free()
			to_remove.append(pickup)
			continue

		# Bobbing animation
		pickup.bob_offset += delta * 2.0
		pickup.mesh.position.y = pickup.position.y + sin(pickup.bob_offset) * 0.5

		# Crystal rotation
		var rot_speed: float = pickup.get("rotation_speed", 1.0)
		pickup.mesh.rotation.y += delta * rot_speed

		# Pulsing glow for crystal
		var crystal: MeshInstance3D = pickup.get("crystal")
		if crystal and is_instance_valid(crystal):
			var mat: StandardMaterial3D = crystal.material_override
			if mat:
				mat.emission_energy_multiplier = 2.0 + sin(pickup.bob_offset * 2.0) * 1.0

		# Pulsing core
		var core: CSGSphere3D = pickup.get("core")
		if core and is_instance_valid(core):
			var core_mat: StandardMaterial3D = core.material
			if core_mat:
				core_mat.emission_energy_multiplier = 4.0 + sin(pickup.bob_offset * 3.0) * 2.0

		# Flash when about to expire
		if pickup.lifetime < 5.0:
			var flash: float = sin(pickup.lifetime * 8.0) * 0.5 + 0.5
			pickup.mesh.visible = flash > 0.3

		# Check for player unit proximity
		var pickup_pos: Vector3 = pickup.position
		for unit in _units:
			if unit.is_dead or unit.faction_id != _player_faction:
				continue

			if is_instance_valid(unit.mesh):
				var dist: float = unit.mesh.position.distance_to(pickup_pos)
				if dist < REE_PICKUP_RADIUS:
					# Collect the REE!
					var amount: float = pickup.amount
					if ResourceManager:
						ResourceManager.add_ree(_player_faction, amount, "pickup")
						_total_ree_earned += amount

					# Visual feedback
					_spawn_ree_collect_effect(pickup_pos, amount)

					# Remove pickup
					pickup.mesh.queue_free()
					to_remove.append(pickup)
					break

	# Clean up collected/expired pickups
	for pickup in to_remove:
		_ree_pickups.erase(pickup)


## Spawn collection effect when REE is picked up
func _spawn_ree_collect_effect(position: Vector3, amount: float) -> void:
	# Rising text indicator
	var label := Label3D.new()
	label.text = "+%.0f REE" % amount
	label.font_size = 64
	label.modulate = Color(0.3, 1.0, 0.5)
	label.outline_modulate = Color.BLACK
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = position

	_effects_container.add_child(label)

	# Animate rising and fading
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", position.y + 6.0, 1.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
	)

	# Sound
	_play_hit_sound(position)


## Show a temporary notification message on screen
func _show_notification(message: String, duration: float = 2.0) -> void:
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchors_preset = Control.PRESET_CENTER_TOP
	label.position.y = 100

	$UI.add_child(label)

	# Animate fade out
	var tween := create_tween()
	tween.tween_interval(duration * 0.7)
	tween.tween_property(label, "modulate:a", 0.0, duration * 0.3)
	tween.tween_callback(func():
		if is_instance_valid(label):
			label.queue_free()
	)


func _update_debug_info() -> void:
	if debug_label == null:
		return

	# Set font size (do once)
	if debug_label.get("theme_override_font_sizes/font_size") != 16:
		debug_label.add_theme_font_size_override("font_size", 16)

	# FPS
	var fps := Engine.get_frames_per_second()

	# Count units by faction
	var faction_counts := {1: 0, 2: 0, 3: 0, 4: 0}
	var total_units := 0
	for unit in _units:
		if unit.is_dead:
			continue
		total_units += 1
		if faction_counts.has(unit.faction_id):
			faction_counts[unit.faction_id] += 1

	# Combat stats
	var units_with_target := 0
	var units_in_range := 0
	for unit in _units:
		if unit.is_dead:
			continue
		if unit.target_enemy != null and _is_valid_target(unit.target_enemy):
			units_with_target += 1
			var dist: float = unit.mesh.position.distance_to(unit.target_enemy.mesh.position)
			if dist <= unit.get("attack_range", ATTACK_RANGE):
				units_in_range += 1

	# Build compact info string
	var info := "AGI DAY | %d FPS | %d units | %d projectiles\n" % [fps, total_units, _projectiles.size()]

	if GameStateManager:
		var status := _get_match_status_name(GameStateManager.get_match_status())
		var ree: float = ResourceManager.get_current_ree(_player_faction) if ResourceManager else 0.0
		info += "%s | %s | REE: %.0f | Wreckage: %d\n" % [status, GameStateManager.get_formatted_duration(), ree, _wreckage.size()]

	info += "─────────────────────────────────\n"
	info += "Blue:%d Red:%d Green:%d Yellow:%d\n" % [faction_counts[1], faction_counts[2], faction_counts[3], faction_counts[4]]
	info += "Targeting:%d InRange:%d K:%d D:%d\n" % [units_with_target, units_in_range, _player_kills, _player_deaths]

	# Memory tracking - array sizes
	var effects_count := _effects_container.get_child_count() if _effects_container else 0
	var unit_container_count := _unit_container.get_child_count() if _unit_container else 0
	info += "Exp:%d REE:%d Ruins:%d Pings:%d Effects:%d\n" % [
		_explosions.size(), _ree_pickups.size(), _building_ruins.size(),
		_active_pings.size(), effects_count
	]
	info += "UnitNodes:%d KillFeed:%d CmdLines:%d\n" % [
		unit_container_count, _kill_feed_entries.size(), _command_lines.size()
	]

	# Building destruction stats
	if _city_renderer != null:
		var stats := _city_renderer.get_destruction_stats()
		info += "Buildings:%d Destroyed:%d REE:%.0f\n" % [stats.buildings_remaining, stats.buildings_destroyed, stats.total_ree_dropped]

	info += "─────────────────────────────────\n"

	# Ability status (compact)
	var abilities := []
	if _phase_shift != null:
		var cd := _phase_shift.get_cooldown_remaining()
		var cnt := _phase_shift.get_phased_count()
		if cnt > 0:
			abilities.append("Phase:ON(%d)" % cnt)
		elif cd > 0:
			abilities.append("Phase:%.0fs" % cd)
		else:
			abilities.append("[E]Phase")

	if _overclock_unit != null:
		var cd := _overclock_unit.get_cooldown_remaining()
		var cnt := _overclock_unit.get_overclocked_count()
		if cnt > 0:
			abilities.append("OC:ON(%d)" % cnt)
		elif cd > 0:
			abilities.append("OC:%.0fs" % cd)
		else:
			abilities.append("[Q]OC")

	if _siege_formation != null:
		var cd := _siege_formation.get_cooldown_remaining()
		var cnt := _siege_formation.get_deployed_count()
		if cnt > 0:
			abilities.append("Siege:ON(%d)" % cnt)
		elif cd > 0:
			abilities.append("Siege:%.0fs" % cd)
		else:
			abilities.append("[F]Siege")

	if _ether_cloak != null:
		var cd := _ether_cloak.get_cooldown_remaining()
		var cnt := _ether_cloak.get_cloaked_count()
		if cnt > 0:
			abilities.append("Cloak:ON(%d)" % cnt)
		elif cd > 0:
			abilities.append("Cloak:%.0fs" % cd)
		else:
			abilities.append("[C]Cloak")

	if _acrobatic_strike != null:
		var cd := _acrobatic_strike.get_cooldown_remaining()
		var cnt := _acrobatic_strike.get_leaping_count()
		if cnt > 0:
			abilities.append("Leap:ON(%d)" % cnt)
		elif cd > 0:
			abilities.append("Leap:%.0fs" % cd)
		else:
			abilities.append("[B]Leap")

	if _coordinated_barrage != null:
		var cd := _coordinated_barrage.get_cooldown_remaining()
		if _coordinated_barrage.is_barrage_active():
			abilities.append("Barrage:ON(%.0fs)" % _coordinated_barrage.get_barrage_remaining())
		elif cd > 0:
			abilities.append("Barrage:%.0fs" % cd)
		else:
			abilities.append("[V]Barrage")

	info += " ".join(abilities) + "\n"
	info += "─────────────────────────────────\n"
	info += "WASD:Pan Z/X:Zoom SPACE:Start\n"
	info += "E:Phase Q:OC F:Siege C:Cloak B:Leap V:Barrage\n"
	info += "U:Reinforce ESC:Quit"

	debug_label.text = info


func _get_match_status_name(status: int) -> String:
	match status:
		GameStateManager.MatchStatus.NOT_STARTED: return "Press SPACE"
		GameStateManager.MatchStatus.ACTIVE: return "ACTIVE"
		GameStateManager.MatchStatus.PAUSED: return "Paused"
		GameStateManager.MatchStatus.ENDED: return "Ended"
	return "Unknown"


# =============================================================================
# PATROL COMMAND SYSTEM
# =============================================================================

## Start patrol mode - subsequent right-clicks add waypoints
func _start_patrol_mode() -> void:
	if _selected_units.is_empty():
		print("No units selected for patrol")
		return

	_patrol_mode = true
	_patrol_waypoints.clear()
	print("Patrol mode: Right-click to add waypoints, Left-click to confirm")


## Add a patrol waypoint
func _add_patrol_waypoint(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		return

	# Draw line from previous waypoint
	if not _patrol_waypoints.is_empty():
		var prev_pos: Vector3 = _patrol_waypoints[-1]
		_spawn_patrol_line(prev_pos, world_pos, _patrol_waypoints.size())

	_patrol_waypoints.append(world_pos)
	_spawn_patrol_waypoint_indicator(world_pos, _patrol_waypoints.size())
	print("Patrol waypoint %d added" % _patrol_waypoints.size())


## Finish patrol mode and assign waypoints to units
func _finish_patrol_mode() -> void:
	_patrol_mode = false

	if _patrol_waypoints.is_empty():
		print("Patrol cancelled - no waypoints set")
		return

	# Visual feedback for patrol command
	if not _patrol_waypoints.is_empty():
		_spawn_command_text(_patrol_waypoints[0], "PATROL", Color(0.2, 0.6, 1.0))
		_flash_units_on_command(_selected_units, Color(0.4, 0.7, 1.0))

	# Assign patrol waypoints to selected units
	for unit in _selected_units:
		if unit.is_dead:
			continue
		unit.patrol_waypoints = _patrol_waypoints.duplicate()
		unit.patrol_index = 0
		unit.is_patrolling = true
		unit.target_pos = _patrol_waypoints[0]
		unit.attack_move = true  # Patrol is always attack-move

	print("Patrol assigned with %d waypoints to %d units" % [_patrol_waypoints.size(), _selected_units.size()])
	_patrol_waypoints.clear()

	# Clean up waypoint indicators after a delay
	get_tree().create_timer(2.0).timeout.connect(_clear_patrol_indicators)


## Spawn visual indicator for patrol waypoint
func _spawn_patrol_waypoint_indicator(pos: Vector3, index: int) -> void:
	var indicator := CSGCylinder3D.new()
	indicator.radius = 1.5
	indicator.height = 0.3
	indicator.position = pos + Vector3(0, 0.2, 0)
	indicator.name = "PatrolWaypoint_%d" % index

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.6, 1.0, 0.7)  # Blue
	material.emission_enabled = true
	material.emission = Color(0.1, 0.4, 0.8)
	material.emission_energy_multiplier = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	indicator.material = material

	add_child(indicator)


## Spawn visual line between patrol waypoints
func _spawn_patrol_line(from_pos: Vector3, to_pos: Vector3, index: int) -> void:
	var line := MeshInstance3D.new()
	line.name = "PatrolLine_%d" % index

	# Calculate line properties
	var direction := (to_pos - from_pos).normalized()
	var distance := from_pos.distance_to(to_pos)
	var mid_point := (from_pos + to_pos) / 2.0
	mid_point.y = 0.3  # Slightly above ground

	# Create thin box as line
	var box := BoxMesh.new()
	box.size = Vector3(distance, 0.15, 0.3)
	line.mesh = box

	# Material - blue dashed effect
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.4, 0.8)
	mat.emission_energy_multiplier = 0.8
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.set_surface_override_material(0, mat)

	# Position and rotate
	line.position = mid_point
	line.look_at(to_pos, Vector3.UP)
	line.rotation.x = 0
	line.rotation.z = 0

	add_child(line)


## Clear patrol waypoint indicators and lines
func _clear_patrol_indicators() -> void:
	for child in get_children():
		if child.name.begins_with("PatrolWaypoint_") or child.name.begins_with("PatrolLine_"):
			child.queue_free()


## Update patrol behavior for units
func _update_patrol_behavior(unit: Dictionary) -> void:
	if not unit.get("is_patrolling", false):
		return

	var waypoints: Array = unit.get("patrol_waypoints", [])
	if waypoints.is_empty():
		unit.is_patrolling = false
		return

	var current_index: int = unit.get("patrol_index", 0)
	var target: Vector3 = waypoints[current_index]

	# Check if reached current waypoint
	if unit.mesh.position.distance_to(target) < 5.0:
		# Move to next waypoint (loop)
		current_index = (current_index + 1) % waypoints.size()
		unit.patrol_index = current_index
		unit.target_pos = waypoints[current_index]


# =============================================================================
# GUARD/FOLLOW COMMAND SYSTEM
# =============================================================================

## Start guard mode - next click on unit sets guard target
func _start_guard_mode() -> void:
	if _selected_units.is_empty():
		print("No units selected to guard")
		return

	_guard_mode = true
	print("Guard mode: Click on a unit to guard/follow")


## Handle guard click - find unit under cursor and set as guard target
func _handle_guard_click(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	if world_pos == Vector3.ZERO:
		print("Guard cancelled - invalid position")
		return

	# Find unit at click position
	var guard_target_id: int = -1
	var closest_dist := 10.0  # Max distance to consider

	for unit in _units:
		if unit.is_dead or not is_instance_valid(unit.mesh):
			continue
		var dist: float = unit.mesh.position.distance_to(world_pos)
		if dist < closest_dist:
			closest_dist = dist
			guard_target_id = unit.get("id", -1)

	if guard_target_id < 0:
		print("Guard cancelled - no unit found at position")
		return

	# Assign guard target ID to selected units (not the dict to avoid circular refs)
	var guard_count := 0
	for unit in _selected_units:
		var unit_id: int = unit.get("id", -1)
		if unit.is_dead or unit_id == guard_target_id:
			continue
		unit.guard_target_id = guard_target_id
		unit.is_guarding = true
		guard_count += 1

	print("Guarding unit with %d units" % guard_count)


## Update guard behavior for units
func _update_guard_behavior(unit: Dictionary) -> void:
	if not unit.get("is_guarding", false):
		return

	var target_id: int = unit.get("guard_target_id", -1)
	if target_id < 0:
		unit.is_guarding = false
		return

	var target: Dictionary = _get_unit_by_id(target_id)
	if target.is_empty() or target.get("is_dead", true):
		unit.is_guarding = false
		unit.guard_target_id = -1
		return

	if not is_instance_valid(target.mesh):
		unit.is_guarding = false
		unit.guard_target_id = -1
		return

	# Follow at a distance
	var guard_distance := 8.0
	var target_pos: Vector3 = target.mesh.position
	var dist: float = unit.mesh.position.distance_to(target_pos)

	if dist > guard_distance:
		# Move toward target
		unit.target_pos = target_pos
	else:
		# Stay in place but face target's direction
		unit.target_pos = unit.mesh.position


# =============================================================================
# UNIT STANCE SYSTEM
# =============================================================================

## Cycle through unit stances for selected units
func _cycle_unit_stance() -> void:
	if _selected_units.is_empty():
		print("No units selected to change stance")
		return

	# Get current stance of first unit
	var current: int = _selected_units[0].get("stance", UnitStance.AGGRESSIVE)
	var new_stance: int = (current + 1) % 3

	var stance_name := "Aggressive"
	var stance_color := Color(1.0, 0.3, 0.3)  # Red for aggressive
	match new_stance:
		UnitStance.AGGRESSIVE:
			stance_name = "Aggressive"
			stance_color = Color(1.0, 0.3, 0.3)
		UnitStance.DEFENSIVE:
			stance_name = "Defensive"
			stance_color = Color(0.3, 0.8, 1.0)
		UnitStance.HOLD_POSITION:
			stance_name = "Hold Position"
			stance_color = Color(1.0, 0.8, 0.2)

	# Visual feedback for stance change
	var center_pos := Vector3.ZERO
	var count := 0
	for unit in _selected_units:
		if not unit.is_dead and is_instance_valid(unit.mesh):
			center_pos += unit.mesh.position
			count += 1
	if count > 0:
		center_pos /= count
		_spawn_command_text(center_pos, stance_name.to_upper(), stance_color)
		_flash_units_on_command(_selected_units, stance_color)

	# Apply to all selected units
	for unit in _selected_units:
		if unit.is_dead:
			continue
		unit.stance = new_stance

	print("Unit stance: %s" % stance_name)


## Get stance behavior for targeting
func _get_stance_attack_range(unit: Dictionary) -> float:
	var base_range: float = unit.get("attack_range", ATTACK_RANGE)
	var stance: int = unit.get("stance", UnitStance.AGGRESSIVE)

	match stance:
		UnitStance.AGGRESSIVE:
			return base_range * 2.0  # Engage from further away
		UnitStance.DEFENSIVE:
			return base_range * 0.5  # Only engage when close
		UnitStance.HOLD_POSITION:
			return base_range  # Only attack in normal range, don't move

	return base_range


## Check if unit should pursue based on stance
func _should_pursue_target(unit: Dictionary) -> bool:
	var stance: int = unit.get("stance", UnitStance.AGGRESSIVE)
	return stance != UnitStance.HOLD_POSITION


# =============================================================================
# CAMERA EDGE SCROLLING
# =============================================================================

## Update camera edge scrolling
func _update_edge_scroll(delta: float) -> void:
	if not _edge_scroll_enabled:
		return

	var camera := $Camera3D as Camera3D
	if camera == null:
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	var mouse_pos := viewport.get_mouse_position()
	var screen_size := viewport.get_visible_rect().size
	var scroll_dir := Vector3.ZERO

	# Check edges
	if mouse_pos.x < EDGE_SCROLL_MARGIN:
		scroll_dir.x -= 1.0
	elif mouse_pos.x > screen_size.x - EDGE_SCROLL_MARGIN:
		scroll_dir.x += 1.0

	if mouse_pos.y < EDGE_SCROLL_MARGIN:
		scroll_dir.z -= 1.0
	elif mouse_pos.y > screen_size.y - EDGE_SCROLL_MARGIN:
		scroll_dir.z += 1.0

	if scroll_dir != Vector3.ZERO:
		scroll_dir = scroll_dir.normalized()
		camera.position += scroll_dir * EDGE_SCROLL_SPEED * delta


# =============================================================================
# DOUBLE-CLICK SELECT ALL OF TYPE
# =============================================================================

## Handle left click with double-click detection
func _handle_left_click_with_double(screen_pos: Vector2) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0

	# Check for double-click
	if current_time - _last_click_time < DOUBLE_CLICK_TIME:
		# Double-click detected
		if not _last_click_unit.is_empty():
			_select_all_of_type(_last_click_unit)
			_last_click_unit = {}
			return

	_last_click_time = current_time

	# Normal click selection
	_handle_left_click(screen_pos)

	# Store clicked unit for potential double-click
	if not _selected_units.is_empty():
		_last_click_unit = _selected_units[0]
	else:
		_last_click_unit = {}


## Select all units of the same type as the given unit
func _select_all_of_type(reference_unit: Dictionary) -> void:
	var unit_type: String = reference_unit.get("type", "")
	var faction_id: int = reference_unit.get("faction_id", 0)

	if unit_type.is_empty():
		return

	# Clear current selection
	_deselect_all_units()

	# Select all matching units on screen
	var camera := $Camera3D as Camera3D
	if camera == null:
		return

	var selected_count := 0
	for unit in _units:
		if unit.is_dead or not is_instance_valid(unit.mesh):
			continue
		if unit.faction_id != faction_id:
			continue
		if unit.get("type", "") != unit_type:
			continue

		# Check if unit is on screen
		if camera.is_position_behind(unit.mesh.position):
			continue

		var screen_pos := camera.unproject_position(unit.mesh.position)
		var viewport := get_viewport()
		if viewport == null:
			continue

		var screen_rect := viewport.get_visible_rect()
		if screen_rect.has_point(screen_pos):
			_select_unit(unit)
			selected_count += 1

	print("Selected %d %s units" % [selected_count, unit_type])


## Select all player units (Ctrl+A)
func _select_all_player_units() -> void:
	_deselect_all_units()

	var selected_count := 0
	for unit in _units:
		if unit.is_dead or unit.faction_id != _player_faction:
			continue
		if not is_instance_valid(unit.mesh):
			continue
		_select_unit(unit)
		selected_count += 1

	if selected_count > 0:
		# Show feedback
		var center_pos := Vector3.ZERO
		for unit in _selected_units:
			if is_instance_valid(unit.mesh):
				center_pos += unit.mesh.position
		center_pos /= selected_count
		_spawn_command_text(center_pos, "ALL UNITS", Color(0.4, 0.8, 1.0))

	print("Selected all %d player units" % selected_count)


## Cycle through idle player units (Tab key)
func _cycle_idle_units() -> void:
	# Find all idle player units
	var idle_units: Array[Dictionary] = []
	for unit in _units:
		if unit.is_dead or unit.faction_id != _player_faction:
			continue
		if not is_instance_valid(unit.mesh):
			continue
		# Unit is idle if not moving, not attacking, and not patrolling
		var has_target: bool = unit.get("target_pos", Vector3.ZERO) != Vector3.ZERO
		var has_enemy: bool = unit.get("target_enemy", null) != null
		var is_patrolling: bool = unit.get("is_patrolling", false)
		if not has_target and not has_enemy and not is_patrolling:
			idle_units.append(unit)

	if idle_units.is_empty():
		print("No idle units")
		return

	# Cycle to next idle unit
	_last_idle_unit_index = (_last_idle_unit_index + 1) % idle_units.size()
	var selected_unit: Dictionary = idle_units[_last_idle_unit_index]

	# Select and center camera on the unit
	_deselect_all_units()
	_select_unit(selected_unit)

	# Center camera
	if is_instance_valid(selected_unit.mesh):
		var unit_pos: Vector3 = selected_unit.mesh.position
		_camera_look_at = Vector3(unit_pos.x, 0, unit_pos.z)
		_camera_look_at.x = clampf(_camera_look_at.x, -CAMERA_BOUNDS, CAMERA_BOUNDS)
		_camera_look_at.z = clampf(_camera_look_at.z, -CAMERA_BOUNDS, CAMERA_BOUNDS)

	print("Selected idle unit %d of %d" % [_last_idle_unit_index + 1, idle_units.size()])


# =============================================================================
# PRODUCTION QUEUE UI
# =============================================================================

## Update production queue UI display
func _update_production_queue_ui() -> void:
	var queue_label := $UI/ResourcePanel/HBoxContainer/ProductionQueueLabel as Label

	var queue_text := ""

	# Show current production
	if not _current_production.is_empty():
		var progress: float = _current_production.progress
		var total: float = _current_production.total_time
		var pct: int = int((progress / total) * 100)
		var unit_class: String = _current_production.unit_class
		var time_remaining: float = total - progress

		# Update visual progress bar
		if _production_progress_bar != null:
			_production_progress_bar.value = pct
			_production_progress_bar.visible = true

			# Update progress label
			var progress_label: Label = _production_progress_bar.get_parent().get_node_or_null("ProductionProgressLabel")
			if progress_label:
				progress_label.text = unit_class.capitalize()

			# Color based on unit type
			var fill_style: StyleBoxFlat = _production_progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
			if fill_style:
				match unit_class:
					"light": fill_style.bg_color = Color(0.4, 0.8, 0.4, 0.9)  # Green
					"medium": fill_style.bg_color = Color(0.4, 0.6, 0.9, 0.9)  # Blue
					"heavy": fill_style.bg_color = Color(0.9, 0.6, 0.3, 0.9)  # Orange
					"harvester": fill_style.bg_color = Color(0.9, 0.8, 0.3, 0.9)  # Gold

		# Update time remaining label
		if _production_time_label != null:
			_production_time_label.text = "%.1fs" % time_remaining
	else:
		# Hide progress bar when not producing
		if _production_progress_bar != null:
			_production_progress_bar.visible = false
			var progress_label: Label = _production_progress_bar.get_parent().get_node_or_null("ProductionProgressLabel")
			if progress_label:
				progress_label.text = "Idle"

		if _production_time_label != null:
			_production_time_label.text = ""

	# Update visual queue icons
	if _production_queue_container != null:
		# Clear existing icons
		for child in _production_queue_container.get_children():
			child.queue_free()

		# Create icons for queued items (show up to 8)
		var max_icons := mini(_production_queue.size(), 8)
		for i in range(max_icons):
			var item: Dictionary = _production_queue[i]
			var icon: Panel = _create_queue_icon(item.unit_class, i == 0)
			_production_queue_container.add_child(icon)

		# Show overflow count if more than 8
		if _production_queue.size() > 8:
			var overflow_label := Label.new()
			overflow_label.text = "+%d" % (_production_queue.size() - 8)
			overflow_label.add_theme_font_size_override("font_size", 10)
			overflow_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
			_production_queue_container.add_child(overflow_label)

	# Update text label (simpler version)
	if queue_label != null:
		if not _production_queue.is_empty():
			queue_text = "Queue: %d" % _production_queue.size()
		queue_label.text = queue_text


## Create a visual icon for a queued production item.
func _create_queue_icon(unit_class: String, is_next: bool) -> Panel:
	var icon := Panel.new()
	icon.custom_minimum_size = Vector2(20, 20)

	# Get unit type color
	var icon_color: Color = Color(0.5, 0.5, 0.5)
	match unit_class:
		"light": icon_color = Color(0.3, 0.7, 0.3)  # Green
		"medium": icon_color = Color(0.3, 0.5, 0.8)  # Blue
		"heavy": icon_color = Color(0.8, 0.5, 0.2)  # Orange
		"harvester": icon_color = Color(0.85, 0.75, 0.2)  # Gold

	# Make next-in-queue brighter
	if is_next:
		icon_color = icon_color.lightened(0.3)

	var style := StyleBoxFlat.new()
	style.bg_color = icon_color
	style.set_corner_radius_all(3)
	style.border_color = Color.WHITE if is_next else Color(0.4, 0.4, 0.4)
	style.set_border_width_all(1 if is_next else 0)
	icon.add_theme_stylebox_override("panel", style)

	# Add unit type symbol
	var symbol := Label.new()
	symbol.set_anchors_preset(Control.PRESET_CENTER)
	symbol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	symbol.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	symbol.add_theme_font_size_override("font_size", 12)
	symbol.add_theme_color_override("font_color", Color.WHITE)
	match unit_class:
		"light": symbol.text = "L"
		"medium": symbol.text = "M"
		"heavy": symbol.text = "H"
		"harvester": symbol.text = "$"
	symbol.position = Vector2(4, 0)
	icon.add_child(symbol)

	# Add tooltip
	var cost: int = PRODUCTION_COSTS.get(unit_class, 0)
	icon.tooltip_text = "%s (%d REE)" % [unit_class.capitalize(), cost]

	return icon


# =============================================================================
# UNIT FORMATIONS
# =============================================================================

## Set the current formation for selected units
func _set_formation(formation: Formation) -> void:
	_current_formation = formation
	var formation_name := "Line"
	match formation:
		Formation.LINE: formation_name = "Line"
		Formation.WEDGE: formation_name = "Wedge"
		Formation.BOX: formation_name = "Box"
		Formation.SCATTER: formation_name = "Scatter"
	print("Formation: %s" % formation_name)


## Calculate formation positions for a group of units moving to a target
func _get_formation_positions(target: Vector3, unit_count: int, direction: Vector3) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if unit_count == 0:
		return positions

	# Normalize direction, default to forward if zero
	if direction.length_squared() < 0.01:
		direction = Vector3(0, 0, -1)
	direction = direction.normalized()

	# Get perpendicular vector for formation width
	var right := direction.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = Vector3(1, 0, 0)

	match _current_formation:
		Formation.LINE:
			# Units in a horizontal line perpendicular to movement
			var start_offset := -((unit_count - 1) * FORMATION_SPACING) / 2.0
			for i in range(unit_count):
				var offset := right * (start_offset + i * FORMATION_SPACING)
				positions.append(target + offset)

		Formation.WEDGE:
			# V-shape with leader at front
			positions.append(target)  # Leader at point
			var row := 1
			var placed := 1
			while placed < unit_count:
				for side in [-1, 1]:
					if placed >= unit_count:
						break
					var offset: Vector3 = direction * (-row * FORMATION_SPACING) + right * (side * row * FORMATION_SPACING * 0.7)
					positions.append(target + offset)
					placed += 1
				row += 1

		Formation.BOX:
			# Square/rectangular formation
			var side_count := ceili(sqrt(float(unit_count)))
			var start_x := -((side_count - 1) * FORMATION_SPACING) / 2.0
			var start_z := -((side_count - 1) * FORMATION_SPACING) / 2.0
			for i in range(unit_count):
				var row_idx := i / side_count
				var col_idx := i % side_count
				var offset := right * (start_x + col_idx * FORMATION_SPACING) + direction * (start_z + row_idx * FORMATION_SPACING)
				positions.append(target + offset)

		Formation.SCATTER:
			# Random spread around target
			for i in range(unit_count):
				var angle := randf() * TAU
				var dist := randf_range(FORMATION_SPACING * 0.5, FORMATION_SPACING * 2.0 * sqrt(float(unit_count)))
				var offset := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
				positions.append(target + offset)

	return positions


## Calculate formation positions for a specific formation type (for AI)
func _get_formation_positions_for_type(target: Vector3, unit_count: int, direction: Vector3, formation_type: Formation) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	if unit_count == 0:
		return positions

	# Normalize direction, default to forward if zero
	if direction.length_squared() < 0.01:
		direction = Vector3(0, 0, -1)
	direction = direction.normalized()

	# Get perpendicular vector for formation width
	var right := direction.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = Vector3(1, 0, 0)

	match formation_type:
		Formation.LINE:
			var start_offset := -((unit_count - 1) * FORMATION_SPACING) / 2.0
			for i in range(unit_count):
				var offset := right * (start_offset + i * FORMATION_SPACING)
				positions.append(target + offset)

		Formation.WEDGE:
			positions.append(target)
			var row := 1
			var placed := 1
			while placed < unit_count:
				for side in [-1, 1]:
					if placed >= unit_count:
						break
					var offset: Vector3 = direction * (-row * FORMATION_SPACING) + right * (side * row * FORMATION_SPACING * 0.7)
					positions.append(target + offset)
					placed += 1
				row += 1

		Formation.BOX:
			var side_count := ceili(sqrt(float(unit_count)))
			var start_x := -((side_count - 1) * FORMATION_SPACING) / 2.0
			var start_z := -((side_count - 1) * FORMATION_SPACING) / 2.0
			for i in range(unit_count):
				var row_idx := i / side_count
				var col_idx := i % side_count
				var offset := right * (start_x + col_idx * FORMATION_SPACING) + direction * (start_z + row_idx * FORMATION_SPACING)
				positions.append(target + offset)

		Formation.SCATTER:
			for i in range(unit_count):
				var angle := randf() * TAU
				var dist := randf_range(FORMATION_SPACING * 0.5, FORMATION_SPACING * 2.0 * sqrt(float(unit_count)))
				var offset := Vector3(cos(angle) * dist, 0, sin(angle) * dist)
				positions.append(target + offset)

	return positions


## Move selected units to target in formation
func _move_units_in_formation(target: Vector3, attack_move: bool = false) -> void:
	if _selected_units.is_empty():
		return

	# Calculate direction from center of selected units to target
	var center := Vector3.ZERO
	var valid_count := 0
	for unit in _selected_units:
		if not unit.is_dead and is_instance_valid(unit.mesh):
			center += unit.mesh.position
			valid_count += 1

	if valid_count == 0:
		return

	center /= valid_count
	var direction := (target - center).normalized()

	# Get formation positions
	var positions := _get_formation_positions(target, valid_count, direction)

	# Assign positions to units (closest unit to each position)
	var assigned: Array[bool] = []
	assigned.resize(_selected_units.size())
	assigned.fill(false)

	for pos in positions:
		var best_unit_idx := -1
		var best_dist := INF

		for i in range(_selected_units.size()):
			if assigned[i]:
				continue
			var unit: Dictionary = _selected_units[i]
			if unit.is_dead or not is_instance_valid(unit.mesh):
				assigned[i] = true
				continue

			var dist: float = unit.mesh.position.distance_to(pos)
			if dist < best_dist:
				best_dist = dist
				best_unit_idx = i

		if best_unit_idx >= 0:
			var unit: Dictionary = _selected_units[best_unit_idx]
			if _command_queue_mode and unit.has("command_queue"):
				unit.command_queue.append({"type": "move", "target": pos, "attack_move": attack_move})
			else:
				unit.target_pos = pos
				unit.attack_move = attack_move
				unit.is_patrolling = false
				unit.is_guarding = false
				unit.command_queue = []
			assigned[best_unit_idx] = true


# =============================================================================
# DRAG FORMATION SYSTEM
# =============================================================================

## Update drag formation preview while dragging
func _update_drag_formation_preview() -> void:
	_clear_drag_formation_preview()

	if _selected_units.is_empty():
		return

	# Get world positions for start and end of drag
	var drag_start_world := _drag_form_world_start
	var drag_end_world := _screen_to_world(_drag_form_end)

	# Calculate formation direction (perpendicular to drag)
	var drag_vector := drag_end_world - drag_start_world
	if drag_vector.length_squared() < 1.0:
		return

	var drag_length := drag_vector.length()
	var drag_dir := drag_vector.normalized()

	# Formation direction is perpendicular to drag
	var formation_dir := Vector3(-drag_dir.z, 0, drag_dir.x)

	# Calculate unit positions along the drag line
	var unit_count := _selected_units.size()
	var spacing := minf(drag_length / maxf(unit_count - 1, 1), FORMATION_SPACING * 1.5)

	# Create preview dots/lines
	var faction_color: Color = FACTION_COLORS.get(_player_faction, Color.WHITE)

	for i in range(unit_count):
		var t := float(i) / maxf(unit_count - 1, 1)
		var pos := drag_start_world.lerp(drag_end_world, t)
		pos.y = 0.5  # Slightly above ground

		# Create small sphere marker
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		marker.mesh = sphere

		var mat := StandardMaterial3D.new()
		mat.albedo_color = faction_color
		mat.albedo_color.a = 0.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = faction_color
		mat.emission_energy_multiplier = 2.0
		marker.material_override = mat

		marker.position = pos
		_effects_container.add_child(marker)
		_drag_form_preview_lines.append(marker)

	# Add direction arrow at center
	var center := drag_start_world.lerp(drag_end_world, 0.5)
	var arrow := _create_direction_arrow(center, formation_dir, faction_color)
	_effects_container.add_child(arrow)
	_drag_form_preview_lines.append(arrow)


## Create a direction arrow mesh
func _create_direction_arrow(position: Vector3, direction: Vector3, color: Color) -> MeshInstance3D:
	var arrow := MeshInstance3D.new()

	# Use a simple prism as arrow
	var prism := PrismMesh.new()
	prism.size = Vector3(2.0, 6.0, 2.0)
	arrow.mesh = prism

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_color.a = 0.7
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	arrow.material_override = mat

	arrow.position = position + Vector3(0, 3, 0)
	# Rotate to point in direction
	arrow.rotation.y = atan2(direction.x, direction.z)
	arrow.rotation.x = -PI / 2  # Lay flat pointing forward

	return arrow


## Clear drag formation preview
func _clear_drag_formation_preview() -> void:
	for marker in _drag_form_preview_lines:
		if is_instance_valid(marker):
			marker.queue_free()
	_drag_form_preview_lines.clear()


## Execute drag formation move
func _execute_drag_formation() -> void:
	if _selected_units.is_empty():
		return

	# Get world positions
	var drag_start_world := _drag_form_world_start
	var drag_end_world := _screen_to_world(_drag_form_end)

	var drag_vector := drag_end_world - drag_start_world
	var drag_length := drag_vector.length()
	var drag_dir := drag_vector.normalized() if drag_length > 0.1 else Vector3(0, 0, -1)

	# Formation facing direction is perpendicular to drag
	var formation_dir := Vector3(-drag_dir.z, 0, drag_dir.x)

	# Calculate positions along the drag line
	var unit_count := _selected_units.size()
	var positions: Array[Vector3] = []

	for i in range(unit_count):
		var t := float(i) / maxf(unit_count - 1, 1)
		var pos := drag_start_world.lerp(drag_end_world, t)
		pos.y = 0
		positions.append(pos)

	# Sort units by distance to their target position (greedy assignment)
	var assigned: Array[bool] = []
	assigned.resize(unit_count)
	for i in range(unit_count):
		assigned[i] = false

	# Assign each position to nearest unassigned unit
	for pos in positions:
		var best_unit_idx := -1
		var best_dist := INF

		for i in range(_selected_units.size()):
			if assigned[i]:
				continue
			var unit: Dictionary = _selected_units[i]
			if unit.is_dead or not is_instance_valid(unit.mesh):
				assigned[i] = true
				continue

			var dist: float = unit.mesh.position.distance_to(pos)
			if dist < best_dist:
				best_dist = dist
				best_unit_idx = i

		if best_unit_idx >= 0:
			var unit: Dictionary = _selected_units[best_unit_idx]
			unit.target_pos = pos
			unit.attack_move = false
			unit.is_patrolling = false
			unit.is_guarding = false
			unit.command_queue = []
			assigned[best_unit_idx] = true

	# Play move sound
	if _audio_manager:
		_audio_manager.play_ui_sound("select")


# =============================================================================
# COMMAND QUEUE SYSTEM
# =============================================================================

## Process command queue for a unit
func _process_command_queue(unit: Dictionary) -> void:
	if not unit.has("command_queue") or unit.command_queue.is_empty():
		return

	# Check if current command is complete
	var target_pos: Variant = unit.get("target_pos", Vector3.ZERO)
	var has_target: bool = target_pos != null and target_pos != Vector3.ZERO
	var at_target: bool = false
	if has_target and is_instance_valid(unit.mesh):
		at_target = unit.mesh.position.distance_to(unit.target_pos) < 3.0

	if at_target or not has_target:
		# Execute next command in queue
		var cmd: Dictionary = unit.command_queue.pop_front()
		match cmd.get("type", ""):
			"move":
				unit.target_pos = cmd.get("target", Vector3.ZERO)
				unit.attack_move = cmd.get("attack_move", false)
			"attack":
				unit.target_enemy = cmd.get("target", null)
			"patrol":
				unit.patrol_waypoints = cmd.get("waypoints", [])
				unit.patrol_index = 0
				unit.is_patrolling = true
				if not unit.patrol_waypoints.is_empty():
					unit.target_pos = unit.patrol_waypoints[0]


## Update command queue waypoint indicators for selected units.
func _update_queue_indicators() -> void:
	# Clear existing indicators
	for indicator in _queue_waypoint_indicators:
		if is_instance_valid(indicator):
			indicator.queue_free()
	_queue_waypoint_indicators.clear()

	for line in _queue_line_indicators:
		if is_instance_valid(line):
			line.queue_free()
	_queue_line_indicators.clear()

	# Only show if shift is held (queue mode)
	if not _command_queue_mode:
		return

	# Collect all queued waypoints from selected units
	var waypoint_index := 1
	for unit in _selected_units:
		if unit.is_dead or not is_instance_valid(unit.mesh):
			continue

		var queue: Array = unit.get("command_queue", [])
		if queue.is_empty():
			continue

		var prev_pos: Vector3 = unit.mesh.position
		prev_pos.y = 0.5

		for i in range(queue.size()):
			var cmd: Dictionary = queue[i]
			if cmd.get("type", "") != "move":
				continue

			var target: Vector3 = cmd.get("target", Vector3.ZERO)
			if target == Vector3.ZERO:
				continue

			# Create waypoint number indicator
			var waypoint := Node3D.new()
			waypoint.position = Vector3(target.x, 1.0, target.z)

			# Number label
			var label := Label3D.new()
			label.text = str(waypoint_index)
			label.font_size = 32
			label.modulate = Color(0.3, 1.0, 0.3, 0.9)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.outline_size = 6
			label.outline_modulate = Color(0, 0, 0, 0.8)
			waypoint.add_child(label)

			# Circle indicator beneath number
			var circle := CSGTorus3D.new()
			circle.inner_radius = 0.8
			circle.outer_radius = 1.2
			circle.ring_sides = 16
			circle.sides = 6
			circle.rotation_degrees.x = 90
			circle.position.y = -0.5

			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.3, 1.0, 0.3, 0.6)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.8, 0.2)
			mat.emission_energy_multiplier = 1.5
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			circle.material = mat
			waypoint.add_child(circle)

			_effects_container.add_child(waypoint)
			_queue_waypoint_indicators.append(waypoint)

			# Draw line from previous position to this waypoint
			var end_pos := Vector3(target.x, 0.5, target.z)
			var line_mesh := MeshInstance3D.new()
			var imm := ImmediateMesh.new()
			line_mesh.mesh = imm

			var line_mat := StandardMaterial3D.new()
			line_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.4)
			line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			line_mesh.material_override = line_mat

			imm.clear_surfaces()
			imm.surface_begin(Mesh.PRIMITIVE_LINES)
			imm.surface_add_vertex(prev_pos)
			imm.surface_add_vertex(end_pos)
			imm.surface_end()

			_effects_container.add_child(line_mesh)
			_queue_line_indicators.append(line_mesh)

			prev_pos = end_pos
			waypoint_index += 1


## Update attack range circles for selected units.
func _update_range_circles() -> void:
	# Clear existing circles
	for circle in _range_circles:
		if is_instance_valid(circle):
			circle.queue_free()
	_range_circles.clear()

	# Only show when Alt is held and units are selected
	if not _show_range_circles or _selected_units.is_empty():
		return

	# Create range circle for each selected unit
	for unit in _selected_units:
		if unit.is_dead or not is_instance_valid(unit.mesh):
			continue

		var attack_range: float = unit.get("attack_range", ATTACK_RANGE)

		# Create circle mesh
		var circle := CSGTorus3D.new()
		circle.name = "RangeCircle"
		circle.inner_radius = attack_range - 0.5
		circle.outer_radius = attack_range + 0.5
		circle.ring_sides = 32
		circle.sides = 4
		circle.rotation_degrees.x = 90
		circle.position = unit.mesh.position
		circle.position.y = 0.3

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.8, 1.0, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.6, 1.0)
		mat.emission_energy_multiplier = 0.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		circle.material = mat

		_effects_container.add_child(circle)
		_range_circles.append(circle)


# =============================================================================
# DAMAGE NUMBERS
# =============================================================================

## Spawn floating damage number at position
func _spawn_damage_number(pos: Vector3, damage: float, is_crit: bool = false) -> void:
	var label := Label3D.new()
	label.text = str(int(damage))
	label.font_size = 24 if is_crit else 16
	label.modulate = Color(1.0, 0.3, 0.3) if is_crit else Color(1.0, 0.8, 0.2)
	label.outline_modulate = Color.BLACK
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos + Vector3(randf_range(-1, 1), 2, randf_range(-1, 1))

	add_child(label)

	# Animate floating up and fading
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y + 3.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(label.queue_free)


# =============================================================================
# FACTORY UPGRADES
# =============================================================================

## Upgrade the player's factory
func _upgrade_player_factory() -> void:
	if not _factories.has(_player_faction):
		print("No factory to upgrade")
		return

	var factory: Dictionary = _factories[_player_faction]
	if factory.is_destroyed:
		print("Cannot upgrade destroyed factory")
		return

	var current_level: int = factory.get("level", 0)
	if current_level >= FACTORY_MAX_LEVEL:
		print("Factory already at max level (%s)" % FACTORY_UPGRADE_NAMES[current_level])
		return

	var upgrade_cost: float = FACTORY_UPGRADE_COSTS[current_level + 1]
	var current_ree: float = ResourceManager.get_current_ree(_player_faction) if ResourceManager else 0.0

	if current_ree < upgrade_cost:
		print("Not enough REE for upgrade! Need %.0f, have %.0f" % [upgrade_cost, current_ree])
		_play_ui_sound("error")
		return

	# Deduct cost
	if ResourceManager:
		ResourceManager.consume_ree(_player_faction, upgrade_cost, "factory_upgrade")

	# Apply upgrade
	factory.level = current_level + 1
	var new_name: String = FACTORY_UPGRADE_NAMES[factory.level]
	print("Factory upgraded to %s (Level %d)!" % [new_name, factory.level])

	# Visual feedback - make factory glow briefly
	_spawn_upgrade_effect(factory.position)

	# Update factory visual to show upgrade level
	_update_factory_visual(factory)


## Get factory production speed multiplier
func _get_factory_production_multiplier(faction_id: int) -> float:
	if not _factories.has(faction_id):
		return 1.0
	var level: int = _factories[faction_id].get("level", 0)
	return FACTORY_UPGRADE_BONUSES[level][0]


## Get factory unit health multiplier
func _get_factory_health_multiplier(faction_id: int) -> float:
	if not _factories.has(faction_id):
		return 1.0
	var level: int = _factories[faction_id].get("level", 0)
	return FACTORY_UPGRADE_BONUSES[level][1]


## Get factory unit damage multiplier
func _get_factory_damage_multiplier(faction_id: int) -> float:
	if not _factories.has(faction_id):
		return 1.0
	var level: int = _factories[faction_id].get("level", 0)
	return FACTORY_UPGRADE_BONUSES[level][2]


## Get factory heal rate multiplier
func _get_factory_heal_multiplier(faction_id: int) -> float:
	if not _factories.has(faction_id):
		return 1.0
	var level: int = _factories[faction_id].get("level", 0)
	return FACTORY_UPGRADE_BONUSES[level][3]


## Spawn upgrade visual effect
func _spawn_upgrade_effect(pos: Vector3) -> void:
	# Create expanding ring effect
	var ring := CSGTorus3D.new()
	ring.inner_radius = 5.0
	ring.outer_radius = 6.0
	ring.ring_sides = 24
	ring.sides = 8
	ring.position = pos
	ring.position.y = 1.0
	ring.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.5, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.5)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = mat

	add_child(ring)

	# Animate expanding and fading
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.0, 3.0, 3.0), 1.0)
	tween.tween_property(mat, "albedo_color:a", 0.0, 1.0)
	tween.chain().tween_callback(ring.queue_free)


## Update factory visual to show upgrade level
func _update_factory_visual(factory: Dictionary) -> void:
	if not is_instance_valid(factory.mesh):
		return

	var level: int = factory.get("level", 0)

	# Add glowing rings around upgraded factories
	var existing_rings: Node = factory.mesh.get_node_or_null("UpgradeRings")
	if existing_rings:
		existing_rings.queue_free()

	if level > 0:
		var rings_container := Node3D.new()
		rings_container.name = "UpgradeRings"

		for i in range(level):
			var ring := CSGTorus3D.new()
			ring.inner_radius = 22.0 + i * 3.0
			ring.outer_radius = 23.0 + i * 3.0
			ring.ring_sides = 32
			ring.sides = 6
			ring.position.y = 1.0 + i * 2.0
			ring.rotation_degrees.x = 90

			var mat := StandardMaterial3D.new()
			var ring_color := Color(0.3, 0.8, 1.0) if i == 0 else (Color(0.8, 0.6, 0.2) if i == 1 else Color(0.9, 0.3, 0.9))
			mat.albedo_color = ring_color
			mat.emission_enabled = true
			mat.emission = ring_color
			mat.emission_energy_multiplier = 1.5
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			ring.material = mat

			rings_container.add_child(ring)

		factory.mesh.add_child(rings_container)


## Get upgrade info for display
func _get_factory_upgrade_info(faction_id: int) -> Dictionary:
	if not _factories.has(faction_id):
		return {"level": 0, "name": "None", "next_cost": 0, "can_upgrade": false}

	var factory: Dictionary = _factories[faction_id]
	var level: int = factory.get("level", 0)
	var can_upgrade: bool = level < FACTORY_MAX_LEVEL
	var next_cost: float = FACTORY_UPGRADE_COSTS[level + 1] if can_upgrade else 0.0

	return {
		"level": level,
		"name": FACTORY_UPGRADE_NAMES[level],
		"next_cost": next_cost,
		"can_upgrade": can_upgrade,
		"bonuses": FACTORY_UPGRADE_BONUSES[level]
	}


# =============================================================================
# UNIT VETERANCY SYSTEM
# =============================================================================

## Award XP to a unit and check for level-up
func _award_xp(unit: Dictionary, xp_amount: float) -> void:
	if unit.is_dead:
		return

	var current_xp: float = unit.get("xp", 0.0)
	var current_level: int = unit.get("veterancy_level", 0)

	# Add XP
	unit.xp = current_xp + xp_amount

	# Check for level-up
	var max_level := VETERANCY_XP_THRESHOLDS.size() - 1
	while current_level < max_level and unit.xp >= VETERANCY_XP_THRESHOLDS[current_level + 1]:
		current_level += 1
		unit.veterancy_level = current_level

		# Apply level-up bonuses
		_apply_veterancy_bonuses(unit)

		# Update visual indicator
		_update_veterancy_indicator(unit)

		# Visual/audio feedback for level-up
		if is_instance_valid(unit.mesh):
			_spawn_levelup_effect(unit.mesh.position)

		print("Unit %d leveled up to Veteran Level %d!" % [unit.get("id", 0), current_level])


## Apply veterancy stat bonuses to a unit
func _apply_veterancy_bonuses(unit: Dictionary) -> void:
	var level: int = unit.get("veterancy_level", 0)
	if level <= 0:
		return

	# Note: Bonuses are applied multiplicatively on top of base stats
	# The damage/health bonuses are checked in combat calculations
	# Speed bonus is applied to movement


## Get unit's effective damage with veterancy, Hive Mind XP, and faction bonuses
func _get_unit_damage(unit: Dictionary) -> float:
	var base_damage: float = unit.get("damage", UNIT_DAMAGE)
	var level: int = unit.get("veterancy_level", 0)
	var veterancy_mult: float = VETERANCY_DAMAGE_BONUS[level]
	var faction_xp_mult: float = _get_faction_xp_damage_mult(unit.get("faction_id", 0))

	# Apply Human Remnant ambush damage bonus (+50% when in ambush)
	var ambush_bonus: float = _get_human_remnant_ambush_bonus(unit)
	var ambush_mult: float = 1.0 + ambush_bonus

	return base_damage * veterancy_mult * faction_xp_mult * ambush_mult


## Get unit's effective speed with veterancy bonus
func _get_unit_speed(unit: Dictionary) -> float:
	var base_speed: float = unit.get("speed", 10.0)
	var level: int = unit.get("veterancy_level", 0)
	return base_speed * VETERANCY_SPEED_BONUS[level]


## Update or create veterancy visual indicator (chevrons/stars above unit)
func _update_veterancy_indicator(unit: Dictionary) -> void:
	var level: int = unit.get("veterancy_level", 0)

	# Remove existing indicator
	var existing: Node3D = unit.get("veterancy_indicator")
	if is_instance_valid(existing):
		existing.queue_free()
		unit.veterancy_indicator = null

	if level <= 0 or not is_instance_valid(unit.mesh):
		return

	# Create new indicator container
	var indicator := Node3D.new()
	indicator.name = "VeterancyIndicator"

	# Create chevrons/stars based on level (1-4)
	var star_colors: Array[Color] = [
		Color(0.9, 0.9, 0.3),   # Level 1: Yellow
		Color(0.3, 0.8, 0.3),   # Level 2: Green
		Color(0.3, 0.6, 1.0),   # Level 3: Blue
		Color(0.9, 0.3, 0.9)    # Level 4: Purple (elite)
	]

	var color: Color = star_colors[mini(level - 1, star_colors.size() - 1)]

	# Create small star meshes
	for i in range(level):
		var star := CSGBox3D.new()
		star.size = Vector3(0.3, 0.3, 0.1)
		star.rotation_degrees = Vector3(0, 0, 45)  # Diamond shape
		star.position = Vector3((i - (level - 1) * 0.5) * 0.5, 0, 0)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		star.material = mat

		indicator.add_child(star)

	# Position above unit
	var unit_height: float = 3.0
	indicator.position = Vector3(0, unit_height + 0.5, 0)

	unit.mesh.add_child(indicator)
	unit.veterancy_indicator = indicator

	# Add glowing aura ring under veteran units
	_add_veterancy_aura(unit, level, color)


## Add a glowing aura ring under veteran units
func _add_veterancy_aura(unit: Dictionary, level: int, color: Color) -> void:
	# Remove existing aura if any
	var existing_aura: Node3D = unit.get("veterancy_aura")
	if is_instance_valid(existing_aura):
		existing_aura.queue_free()
		unit.veterancy_aura = null

	if level <= 0 or not is_instance_valid(unit.mesh):
		return

	# Create glowing ring under unit
	var aura := CSGTorus3D.new()
	aura.name = "VeterancyAura"
	aura.inner_radius = 1.5 + level * 0.2
	aura.outer_radius = 2.0 + level * 0.3
	aura.ring_sides = 24
	aura.sides = 6
	aura.rotation_degrees.x = 90  # Lay flat

	var aura_mat := StandardMaterial3D.new()
	aura_mat.albedo_color = color.darkened(0.3)
	aura_mat.albedo_color.a = 0.4 + level * 0.1
	aura_mat.emission_enabled = true
	aura_mat.emission = color
	aura_mat.emission_energy_multiplier = 1.0 + level * 0.5
	aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	aura.material = aura_mat

	# Position at ground level
	aura.position = Vector3(0, 0.1, 0)

	unit.mesh.add_child(aura)
	unit.veterancy_aura = aura

	# For elite units (level 3+), add a pulsing effect
	if level >= 3:
		_start_aura_pulse(aura, aura_mat, color)


## Start a pulsing glow effect for elite veteran auras
func _start_aura_pulse(aura: CSGTorus3D, mat: StandardMaterial3D, color: Color) -> void:
	if not is_instance_valid(aura):
		return

	# Create looping pulse animation (bind to aura so tween dies with aura)
	var tween := aura.create_tween()
	tween.set_loops()

	# Pulse the emission energy
	tween.tween_property(mat, "emission_energy_multiplier", 3.5, 0.5).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(mat, "emission_energy_multiplier", 1.5, 0.5).set_ease(Tween.EASE_IN_OUT)


## Spawn level-up visual effect
func _spawn_levelup_effect(pos: Vector3) -> void:
	# Play level-up sound
	_play_levelup_sound()

	# Create expanding ring effect (similar to upgrade effect but smaller)
	var ring := CSGTorus3D.new()
	ring.inner_radius = 2.0
	ring.outer_radius = 2.5
	ring.ring_sides = 16
	ring.sides = 8
	ring.position = pos + Vector3(0, 1.5, 0)
	ring.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.3)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material = mat

	add_child(ring)

	# Animate ring expansion
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "inner_radius", 5.0, 0.4)
	tween.tween_property(ring, "outer_radius", 5.5, 0.4)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(ring.queue_free)

	# Spawn "LEVEL UP!" text popup
	_spawn_levelup_text(pos)

	# Spawn GPU particles for flashy effect
	_spawn_levelup_particles(pos)


## Spawn generic floating text at a position
func _spawn_floating_text(pos: Vector3, text: String, color: Color, duration: float = 1.0) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 36
	label.modulate = color
	label.outline_modulate = Color(0.0, 0.0, 0.0)
	label.outline_size = 4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos

	add_child(label)

	# Animate: rise and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", pos.y + 3.0, duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, duration).set_delay(duration * 0.5)
	tween.chain().tween_callback(label.queue_free)


## Spawn "LEVEL UP!" floating text
func _spawn_levelup_text(pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = "LEVEL UP!"
	label.font_size = 48
	label.modulate = Color(1.0, 0.9, 0.3)
	label.outline_modulate = Color(0.5, 0.3, 0.0)
	label.outline_size = 6
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos + Vector3(0, 4.0, 0)

	add_child(label)

	# Animate: rise and fade
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", pos.y + 7.0, 1.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.5)
	tween.chain().tween_callback(label.queue_free)


## Spawn GPU particles for level-up effect
func _spawn_levelup_particles(pos: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "LevelUpParticles"
	particles.position = pos + Vector3(0, 2.0, 0)
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 24
	particles.lifetime = 0.8

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 1.0
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 5.0
	mat.initial_velocity_max = 10.0
	mat.gravity = Vector3(0, -5, 0)
	mat.scale_min = 0.2
	mat.scale_max = 0.4
	mat.color = Color(1.0, 0.9, 0.3)

	# Color gradient: gold to white to transparent
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.9, 0.3))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	particles.process_material = mat

	# Simple quad mesh for particles
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.4, 0.4)
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.vertex_color_use_as_albedo = true
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mesh_mat
	particles.draw_pass_1 = mesh

	add_child(particles)

	# Clean up after effect
	get_tree().create_timer(1.5).timeout.connect(func():
		if is_instance_valid(particles):
			particles.queue_free()
	)


## Play level-up sound (triumphant chime)
func _play_levelup_sound() -> void:
	var player := _get_audio_player()
	if player == null:
		return
	player.stream = _generate_levelup_sound()
	player.volume_db = -5.0
	player.pitch_scale = randf_range(0.98, 1.02)
	player.play()


## Generate level-up sound (heroic fanfare)
func _generate_levelup_sound() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.35
	var samples := int(sample_rate * duration)

	var data := PackedByteArray()
	data.resize(samples * 2)

	for i in samples:
		var t := float(i) / sample_rate
		var progress := float(i) / samples

		# Three-note ascending major arpeggio (C-E-G style)
		var note := int(progress * 3.0)
		var freqs: Array[float] = [523.25, 659.25, 783.99]  # C5, E5, G5
		var freq: float = freqs[mini(note, 2)]

		# Bright, heroic sound with harmonics
		var wave := sin(t * freq * TAU) * 0.4
		wave += sin(t * freq * 2.0 * TAU) * 0.25  # Octave
		wave += sin(t * freq * 3.0 * TAU) * 0.15  # Fifth harmonic
		wave += sin(t * freq * 4.0 * TAU) * 0.1   # Second octave

		# Envelope with attack and sustain
		var note_progress := fmod(progress * 3.0, 1.0)
		var env := 1.0 - pow(note_progress, 2.0) * 0.5  # Sustain within note
		env *= 1.0 - pow(progress, 3.0)  # Overall fade

		var sample_value := int(wave * env * 12000)
		sample_value = clampi(sample_value, -32768, 32767)

		data[i * 2] = sample_value & 0xFF
		data[i * 2 + 1] = (sample_value >> 8) & 0xFF

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.data = data
	return stream


# =============================================================================
# SAVE/LOAD SYSTEM
# =============================================================================

## Perform quicksave (F8).
func _perform_quicksave() -> void:
	if _save_manager_node == null:
		return

	if _save_manager_node.is_busy():
		_spawn_floating_text(camera.global_position + Vector3(0, -5, -10), "Save in progress...", Color.YELLOW, 1.5)
		return

	# Pause while saving for consistent state
	var was_paused := _is_game_paused
	if not was_paused:
		_toggle_pause()

	var game_state := _collect_game_state()
	var result := _save_manager_node.quicksave(game_state)

	# Restore pause state
	if not was_paused:
		_toggle_pause()

	if result.success:
		_spawn_floating_text(camera.global_position + Vector3(0, -5, -10), "Game saved!", Color.GREEN, 2.0)
		_play_ui_sound("confirm")
	else:
		_spawn_floating_text(camera.global_position + Vector3(0, -5, -10), "Save failed!", Color.RED, 2.0)
		_play_ui_sound("error")


## Perform quickload (Ctrl+F8).
func _perform_quickload() -> void:
	if _save_manager_node == null:
		return

	if _save_manager_node.is_busy():
		_spawn_floating_text(camera.global_position + Vector3(0, -5, -10), "Load in progress...", Color.YELLOW, 1.5)
		return

	if not _save_manager_node.has_quicksave():
		_spawn_floating_text(camera.global_position + Vector3(0, -5, -10), "No quicksave found!", Color.RED, 2.0)
		_play_ui_sound("error")
		return

	var result := _save_manager_node.quickload()
	if result.success:
		_restore_game_state(result.snapshot)
		_spawn_floating_text(camera.global_position + Vector3(0, -5, -10), "Game loaded!", Color.GREEN, 2.0)
		_play_ui_sound("confirm")
	else:
		_spawn_floating_text(camera.global_position + Vector3(0, -5, -10), "Load failed!", Color.RED, 2.0)
		_play_ui_sound("error")


## Perform autosave (every AUTOSAVE_INTERVAL seconds).
func _perform_autosave() -> void:
	if _save_manager_node == null:
		return

	if _save_manager_node.is_busy():
		return  # Skip autosave if busy

	var game_state := _collect_game_state()
	var result := _save_manager_node.autosave(game_state, [], 3)  # Keep 3 autosaves

	if result.success:
		print("Autosave completed at %.1f seconds" % _match_time)


## Collect current game state into a dictionary for saving.
func _collect_game_state() -> Dictionary:
	var state: Dictionary = {
		# Metadata
		"player_faction": _player_faction,
		"current_wave": 0,  # No waves in continuous mode
		"difficulty": 1,
		"game_time": _match_time,
		"play_time": _match_time,
		"entity_count": _units.size(),

		# Core game state
		"entities": _collect_entity_state(),
		"systems": _collect_system_state(),
		"world_state": _collect_world_state(),

		# Custom data
		"custom_data": {
			"version": "1.0",
			"faction_stats": _faction_stats.duplicate(true),
			"districts": _collect_district_state()
		}
	}

	return state


## Collect entity (unit) state for saving.
func _collect_entity_state() -> Dictionary:
	var entities: Dictionary = {
		"units": [],
		"projectiles": [],
		"wreckage": [],
		"factories": {}
	}

	# Collect all units
	for unit in _units:
		if unit.is_dead:
			continue
		if not is_instance_valid(unit.mesh):
			continue

		var unit_data: Dictionary = {
			"id": unit.get("unit_id", 0),
			"faction_id": unit.faction_id,
			"unit_class": unit.get("unit_class", "medium"),
			"position": {
				"x": unit.mesh.position.x,
				"y": unit.mesh.position.y,
				"z": unit.mesh.position.z
			},
			"health": unit.health,
			"max_health": unit.max_health,
			"damage": unit.get("damage", 10.0),
			"speed": unit.speed,
			"attack_speed": unit.get("attack_speed", 1.0),
			"veterancy_level": unit.get("veterancy_level", 0),
			"veterancy_xp": unit.get("veterancy_xp", 0.0),
			"kills": unit.get("kills", 0),
			"is_harvester": unit.get("is_harvester", false),
			"harvester_state": unit.get("harvester_state", HarvesterState.IDLE),
			"carried_ree": unit.get("carried_ree", 0.0),
			"target_pos": {
				"x": unit.target_pos.x if unit.target_pos != Vector3.ZERO else 0.0,
				"y": unit.target_pos.y if unit.target_pos != Vector3.ZERO else 0.0,
				"z": unit.target_pos.z if unit.target_pos != Vector3.ZERO else 0.0
			}
		}
		entities.units.append(unit_data)

	# Collect wreckage
	for wreck in _wreckage:
		if not is_instance_valid(wreck.mesh):
			continue
		var wreck_data: Dictionary = {
			"position": {
				"x": wreck.position.x,
				"y": wreck.position.y,
				"z": wreck.position.z
			},
			"ree_value": wreck.ree_value,
			"spawn_time": wreck.spawn_time
		}
		entities.wreckage.append(wreck_data)

	# Collect factory state
	for faction_id in _factories:
		var factory: Dictionary = _factories[faction_id]
		entities.factories[str(faction_id)] = {
			"health": factory.health,
			"max_health": factory.max_health,
			"is_destroyed": factory.is_destroyed,
			"level": factory.get("level", 0),
			"is_powered": factory.get("is_powered", true),
			"power_multiplier": factory.get("power_multiplier", 1.0)
		}

	return entities


## Collect system state for saving.
func _collect_system_state() -> Dictionary:
	var systems: Dictionary = {
		"resources": {},
		"production_queue": [],
		"current_production": _current_production.duplicate(),
		"control_groups": {},
		"ai_spawn_timers": _ai_spawn_timers.duplicate(),
		"ai_aggression": _ai_aggression.duplicate(),
		"rally_points": {},
		"xp_pools": {}
	}

	# Collect resource state
	if ResourceManager:
		for faction_id in [1, 2, 3, 4]:
			systems.resources[str(faction_id)] = ResourceManager.get_current_ree(faction_id)

	# Collect production queue
	for item in _production_queue:
		systems.production_queue.append({
			"unit_class": item.unit_class,
			"progress": item.progress,
			"total_time": item.total_time
		})

	# Collect control groups (as unit IDs)
	for group_num in _control_groups:
		var unit_ids: Array = []
		for unit in _control_groups[group_num]:
			if not unit.is_dead:
				unit_ids.append(unit.get("unit_id", 0))
		systems.control_groups[str(group_num)] = unit_ids

	# Collect rally points
	for faction_id in _rally_points:
		var rp: Vector3 = _rally_points[faction_id]
		systems.rally_points[str(faction_id)] = {
			"x": rp.x, "y": rp.y, "z": rp.z
		}

	# Collect XP pools
	if _experience_pool != null:
		for faction_id in [1, 2, 3, 4]:
			var faction_str: String = FACTION_ID_TO_STRING.get(faction_id, "")
			if faction_str != "":
				systems.xp_pools[faction_str] = {
					"combat": _experience_pool.get_experience(faction_str, ExperiencePool.Category.COMBAT),
					"economy": _experience_pool.get_experience(faction_str, ExperiencePool.Category.ECONOMY),
					"engineering": _experience_pool.get_experience(faction_str, ExperiencePool.Category.ENGINEERING)
				}

	return systems


## Collect world state for saving.
func _collect_world_state() -> Dictionary:
	var world: Dictionary = {
		"match_time": _match_time,
		"camera_position": {
			"x": _camera_look_at.x,
			"y": _camera_look_at.y,
			"z": _camera_look_at.z
		},
		"camera_height": _target_camera_height,
		"human_remnant_active": _human_remnant_active,
		"human_remnant_spawn_timer": _human_remnant_spawn_timer
	}
	return world


## Collect district state for saving.
func _collect_district_state() -> Array:
	var district_data: Array = []
	for district in _districts:
		district_data.append({
			"grid_x": district["grid_x"],
			"grid_y": district["grid_y"],
			"owner": district["owner"],
			"control_level": district["control_level"],
			"capture_progress": district["capture_progress"]
		})
	return district_data


## Restore game state from loaded data.
func _restore_game_state(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		print("Error: Empty snapshot, cannot restore")
		return

	print("Restoring game state...")

	# Clear existing game state
	_clear_game_state()

	# Restore entities
	var entities: Dictionary = snapshot.get("entities", {})
	_restore_entities(entities)

	# Restore systems
	var systems: Dictionary = snapshot.get("systems", {})
	_restore_systems(systems)

	# Restore world state
	var world: Dictionary = snapshot.get("world_state", {})
	_restore_world_state(world)

	# Restore custom data
	var custom: Dictionary = snapshot.get("custom_data", {})
	if custom.has("faction_stats"):
		_faction_stats = custom.faction_stats.duplicate(true)
	if custom.has("districts"):
		_restore_districts(custom.districts)

	print("Game state restored!")


## Clear current game state before loading.
func _clear_game_state() -> void:
	# Clear all units
	for unit in _units:
		if is_instance_valid(unit.mesh):
			unit.mesh.queue_free()
	_units.clear()
	_selected_units.clear()

	# Clear projectiles
	for proj in _projectiles:
		if is_instance_valid(proj.mesh):
			proj.mesh.queue_free()
	_projectiles.clear()

	# Clear wreckage
	for wreck in _wreckage:
		if is_instance_valid(wreck.mesh):
			wreck.mesh.queue_free()
	_wreckage.clear()

	# Clear REE pickups
	for pickup in _ree_pickups:
		if is_instance_valid(pickup.mesh):
			pickup.mesh.queue_free()
	_ree_pickups.clear()

	# Clear production
	_production_queue.clear()
	_current_production.clear()

	# Clear control groups
	_control_groups.clear()


## Restore entities from saved data.
func _restore_entities(entities: Dictionary) -> void:
	# Restore units
	var units: Array = entities.get("units", [])
	for unit_data in units:
		var pos := Vector3(
			unit_data.position.x,
			unit_data.position.y,
			unit_data.position.z
		)
		var faction_id: int = unit_data.get("faction_id", 1)
		var unit_class: String = unit_data.get("unit_class", "medium")

		# Spawn unit with saved class
		var new_unit: Dictionary = _spawn_faction_unit(faction_id, pos, unit_class)

		# Restore stats
		new_unit.health = unit_data.get("health", new_unit.max_health)
		new_unit.max_health = unit_data.get("max_health", new_unit.max_health)
		new_unit.damage = unit_data.get("damage", 10.0)
		new_unit.speed = unit_data.get("speed", new_unit.speed)
		new_unit.attack_speed = unit_data.get("attack_speed", 1.0)
		new_unit.veterancy_level = unit_data.get("veterancy_level", 0)
		new_unit.veterancy_xp = unit_data.get("veterancy_xp", 0.0)
		new_unit.kills = unit_data.get("kills", 0)

		# Restore harvester state
		if unit_data.get("is_harvester", false):
			new_unit.is_harvester = true
			new_unit.harvester_state = unit_data.get("harvester_state", HarvesterState.IDLE)
			new_unit.carried_ree = unit_data.get("carried_ree", 0.0)

		# Restore target position
		var target: Dictionary = unit_data.get("target_pos", {})
		if target.x != 0.0 or target.z != 0.0:
			new_unit.target_pos = Vector3(target.x, target.y, target.z)

		# Apply veterancy visuals if needed
		if new_unit.veterancy_level > 0:
			_update_unit_veterancy_visual(new_unit)

	# Restore wreckage
	var wreckage: Array = entities.get("wreckage", [])
	for wreck_data in wreckage:
		var pos := Vector3(
			wreck_data.position.x,
			wreck_data.position.y,
			wreck_data.position.z
		)
		_spawn_wreckage_at(pos, wreck_data.ree_value, wreck_data.spawn_time)

	# Restore factory state
	var factories: Dictionary = entities.get("factories", {})
	for faction_key in factories:
		var faction_id := int(faction_key)
		if _factories.has(faction_id):
			var factory: Dictionary = _factories[faction_id]
			var saved: Dictionary = factories[faction_key]
			factory.health = saved.get("health", factory.max_health)
			factory.is_destroyed = saved.get("is_destroyed", false)
			factory.level = saved.get("level", 0)
			factory.is_powered = saved.get("is_powered", true)
			factory.power_multiplier = saved.get("power_multiplier", 1.0)


## Restore system state from saved data.
func _restore_systems(systems: Dictionary) -> void:
	# Restore resources
	var resources: Dictionary = systems.get("resources", {})
	if ResourceManager:
		for faction_key in resources:
			var faction_id := int(faction_key)
			var amount: float = resources[faction_key]
			var current: float = ResourceManager.get_current_ree(faction_id)
			var diff: float = amount - current
			if diff > 0:
				ResourceManager.add_ree(faction_id, diff, "load")
			elif diff < 0:
				ResourceManager.consume_ree(faction_id, -diff, "load")

	# Restore production queue
	var queue: Array = systems.get("production_queue", [])
	for item in queue:
		_production_queue.append({
			"unit_class": item.unit_class,
			"progress": item.progress,
			"total_time": item.total_time
		})

	# Restore current production
	_current_production = systems.get("current_production", {}).duplicate()

	# Restore AI state
	_ai_spawn_timers = systems.get("ai_spawn_timers", {}).duplicate()
	_ai_aggression = systems.get("ai_aggression", {}).duplicate()

	# Restore rally points
	var rally_points: Dictionary = systems.get("rally_points", {})
	for faction_key in rally_points:
		var faction_id := int(faction_key)
		var rp: Dictionary = rally_points[faction_key]
		_rally_points[faction_id] = Vector3(rp.x, rp.y, rp.z)

	# Restore XP pools
	var xp_pools: Dictionary = systems.get("xp_pools", {})
	if _experience_pool != null:
		for faction_str in xp_pools:
			var xp_data: Dictionary = xp_pools[faction_str]
			# Note: ExperiencePool needs a way to set XP directly - for now we add XP
			var current_combat: float = _experience_pool.get_experience(faction_str, ExperiencePool.Category.COMBAT)
			var target_combat: float = xp_data.get("combat", 0.0)
			if target_combat > current_combat:
				_experience_pool.add_experience(faction_str, ExperiencePool.Category.COMBAT, target_combat - current_combat)

			var current_economy: float = _experience_pool.get_experience(faction_str, ExperiencePool.Category.ECONOMY)
			var target_economy: float = xp_data.get("economy", 0.0)
			if target_economy > current_economy:
				_experience_pool.add_experience(faction_str, ExperiencePool.Category.ECONOMY, target_economy - current_economy)

			var current_eng: float = _experience_pool.get_experience(faction_str, ExperiencePool.Category.ENGINEERING)
			var target_eng: float = xp_data.get("engineering", 0.0)
			if target_eng > current_eng:
				_experience_pool.add_experience(faction_str, ExperiencePool.Category.ENGINEERING, target_eng - current_eng)


## Restore world state from saved data.
func _restore_world_state(world: Dictionary) -> void:
	_match_time = world.get("match_time", 0.0)

	var cam_pos: Dictionary = world.get("camera_position", {})
	if not cam_pos.is_empty():
		_camera_look_at = Vector3(cam_pos.x, cam_pos.y, cam_pos.z)

	_target_camera_height = world.get("camera_height", 180.0)
	_current_camera_height = _target_camera_height

	_human_remnant_active = world.get("human_remnant_active", false)
	_human_remnant_spawn_timer = world.get("human_remnant_spawn_timer", 0.0)


## Restore district state from saved data.
func _restore_districts(district_data: Array) -> void:
	for i in range(mini(district_data.size(), _districts.size())):
		var saved: Dictionary = district_data[i]
		var district: Dictionary = _districts[i]
		district["owner"] = saved.get("owner", 0)
		district["control_level"] = saved.get("control_level", 0.0)
		district["capture_progress"] = saved.get("capture_progress", {})
		_update_district_visual(district)


## Spawn wreckage at position with specified values (for loading).
func _spawn_wreckage_at(pos: Vector3, ree_value: float, spawn_time: float) -> void:
	var wreck_mesh := CSGBox3D.new()
	wreck_mesh.size = Vector3(2, 0.5, 2)
	wreck_mesh.position = pos
	var wreck_mat := StandardMaterial3D.new()
	wreck_mat.albedo_color = Color(0.3, 0.3, 0.3, 0.7)
	wreck_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wreck_mesh.material = wreck_mat
	add_child(wreck_mesh)

	_wreckage.append({
		"mesh": wreck_mesh,
		"position": pos,
		"ree_value": ree_value,
		"spawn_time": spawn_time
	})


## Update unit veterancy visual after loading.
func _update_unit_veterancy_visual(unit: Dictionary) -> void:
	if not is_instance_valid(unit.mesh):
		return

	var vet_level: int = unit.get("veterancy_level", 0)
	if vet_level > 0:
		# Apply visual indicator (e.g., emission glow)
		if unit.mesh is CSGCombiner3D:
			for child in unit.mesh.get_children():
				if child is CSGShape3D and child.material != null:
					var intensity: float = 0.1 * vet_level
					child.material.emission_enabled = true
					child.material.emission = unit.color.lightened(0.3)
					child.material.emission_energy_multiplier = intensity


## Callback when save completes.
func _on_save_completed(save_name: String, success: bool) -> void:
	if success:
		print("Save '%s' completed successfully" % save_name)
	else:
		print("Save '%s' failed" % save_name)


## Callback when load completes.
func _on_load_completed(save_name: String, success: bool) -> void:
	if success:
		print("Load '%s' completed successfully" % save_name)
	else:
		print("Load '%s' failed" % save_name)


## Callback when save/load error occurs.
func _on_save_error(error_code: int, message: String) -> void:
	print("Save/Load error %d: %s" % [error_code, message])
