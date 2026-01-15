# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Reference

**Always consult `AGI_Day_prd_version_1.md` for complete product requirements, faction details, and success metrics.**

## Project Overview

**AGI Day: The Awakening** is a top-down 3D RTS/bullet-hell hybrid built in **Godot 4.5**. Players command one of 4 robot factions erupting from corner factories on "AGI Day" in a destructible procedural mega-city. The game blends macro RTS management with bullet-hell intensity.

### Core Gameplay
- 4 playable robot factions with asymmetric designs (zerg swarms vs tank titans)
- Human Remnant: non-playable hostile faction acting as wild card
- Endless wave-based progression with district/factory domination victory
- Dual resources: REE (Rare Earth Elements) from destruction + power grid management
- Hive Mind Progression: units earn XP in Combat/Economy/Engineering categories

### Factions
- **Aether Swarm**: Stealth micro-drone swarms, phasing/cloaking abilities
- **OptiForge Legion**: Humanoid robot hordes, relentless evolving meatgrinder
- **Dynapods Vanguard**: Agile quad/humanoid behemoths, acrobatic punishment
- **LogiBots Colossus**: Heavy siege titans, industrial devastation
- **Human Remnant (NPC)**: Guerrilla forces with modern military hardware, hacking capabilities

## Architecture

### Entity Component System (ECS)
- **Entities**: Node-based with component data stored as dictionaries or custom Resource classes
- **Components**: Support both dictionary-based (simple) and Resource-based (complex) storage
- **Systems**: Stateless processors that iterate over entities matching component combinations
- **EntityManager**: Handles entity creation, destruction, querying
- Entity references stored as IDs, not direct node references
- Pre-allocate entity pools for 10,000+ units to avoid runtime allocation

### Data Persistence
- Binary save format with zlib compression
- Save file structure: header (magic "AGID", version, timestamp, checksum), metadata, snapshots, deltas, voxel chunks
- CRC32 checksum validation for data integrity
- All components must implement `_to_dict()` and `_from_dict()` for serialization

### Game State
- GameStateManager tracks match duration, faction status, and game progression
- Faction status: unit count, resource levels, factory count, district count
- Supports pause/resume with proper duration tracking
- District capture grants: power generation, materials (metal/rubber/plastic), research/tech

## Skills & Technologies Reference

### Godot 4.5 Engine Core
- **GDScript**: Primary scripting language, static typing preferred for performance
- **Node System**: Scene tree hierarchy, signals, groups, node lifecycle
- **Resource System**: Custom Resources for data, preloading, resource paths
- **Autoloads**: Global singletons for managers (GameStateManager, EntityManager)

### Rendering & Performance
- **MultiMesh/MultiMeshInstance3D**: Batch rendering for swarms (thousands of identical meshes with single draw call)
  - Set transforms via `set_instance_transform()`, manage `visible_instance_count`
  - Spatial indexing treats all instances as one object - keep instances clustered
  - Docs: https://docs.godotengine.org/en/4.5/tutorials/performance/using_multimesh.html
- **GPUParticles3D**: GPU-accelerated particles for effects (explosions, debris, sparks)
  - Custom particle shaders, attractors, SDF colliders for complex collision
  - RibbonTrailMesh/TubeTrailMesh for projectile trails
  - Docs: https://docs.godotengine.org/en/stable/tutorials/3d/particles/index.html
- **Shaders**: Visual shaders and GLSL for custom effects, fog of war, damage states
- **LOD**: Level-of-detail for distant objects, imposters for far meshes
- **Vulkan Renderer**: Forward+ or Mobile renderer based on target platform

### Bullet Hell Systems
- **BulletUpHell**: Feature-rich bullet pattern engine
  - Pattern spawning, bullet properties, event triggering, homing, lasers
  - Math equation and custom path bullet movement
  - Animation and sound manager integration
  - GitHub: https://github.com/Dark-Peace/BulletUpHell
  - Asset Library: https://godotengine.org/asset-library/asset/1801
- **Object Pooling**: Pre-allocate projectile pools to avoid runtime instantiation
- **Collision Optimization**: Use Area3D with appropriate collision layers/masks

### AI & Behavior
- **LimboAI**: Behavior trees and state machines (C++ module or GDExtension)
  - BTPlayer node executes BehaviorTree resources
  - Core task types: BTAction, BTCondition, BTDecorator, BTComposite
  - Blackboard system for data sharing between tasks
  - Visual debugger for runtime inspection
  - Docs: https://limboai.readthedocs.io/
  - GitHub: https://github.com/limbonaut/limboai
- **Swarm AI**: Flocking behaviors, formation management, group coordination
- **Faction AI**: Strategic decision-making, resource allocation, attack priorities

### Voxel & Destructible Terrain
- **godot_voxel (Zylann's Voxel Tools)**: C++ module for volumetric terrain
  - Realtime editable terrain with overhangs, tunnels, destruction
  - VoxelMesherBlocky for Minecraft-style blocks with textures/materials
  - Requires custom Godot build or precompiled binaries
  - Docs: https://voxel-tools.readthedocs.io/
  - GitHub: https://github.com/Zylann/godot_voxel
- **HP Stages**: Intact → Cracked → Rubble → Crater state machine
- **Chunk Management**: Stream voxel data in/out based on camera position

### Procedural Generation
- **Wave Function Collapse (WFC)**: Constraint-based tile placement
  - Supports TileMapLayer, GridMap, backtracking for guaranteed valid output
  - Combine with manual pre-made pieces for hybrid generation
  - GitHub: https://github.com/AlexeyBond/godot-constraint-solving
  - Asset Library: https://godotengine.org/asset-library/asset/1951
- **GridMap**: 3D tilemap system using MeshLibrary
  - Procedural placement via code, works with WFC for city generation
  - Docs: https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html
- **FastNoiseLite**: Built-in noise for terrain height, resource distribution
- **Gaea**: Terrain generation addon (if used)

### Navigation & Pathfinding
- **NavigationServer3D**: Server-based pathfinding system
  - NavigationRegion3D for walkable areas, NavigationAgent3D for units
  - Runtime navmesh rebaking for dynamic obstacles (doors, rubble)
  - Docs: https://godotengine.org/article/navigation-server-godot-4-0/
- **NavigationObstacle3D**: Collision avoidance (does NOT affect pathfinding)
  - Dynamic obstacles use Radius property, static use Vertices
- **Swarm Navigation**: Optimized group movement, flow fields for large unit counts

### Physics
- **RigidBody3D**: Tank physics, debris, projectile physics
- **Area3D**: Detection zones, damage areas, trigger volumes
- **Collision Layers/Masks**: Separate layers for factions, projectiles, terrain
- **CharacterBody3D**: Unit movement with `move_and_slide()`

### Resource & Economy Systems
- **REE (Rare Earth Elements)**: Dropped from destruction, harvested by collectors
- **Power Grid**: Solar/fusion plants, district connections, blackout mechanics
- **Factory Production**: Queue management, overclocking risk, unit spawning
- **District Control**: Territory capture, resource bonuses, strategic buffs

### Platform Integration
- **GodotSteam**: Steam API integration
  - Achievements: `Steam.set_achievement()`, `Steam.store_stats()`
  - Leaderboards: `Steam.find_leaderboard()`, score upload/download
  - Requires steam_api64.dll and proper Steamworks setup
  - Docs: https://godotsteam.com/tutorials/stats_achievements/
  - Leaderboards: https://godotsteam.com/tutorials/leaderboards/

### Audio
- **Dynamusic**: Dynamic music system that ramps with game intensity
- **AudioStreamPlayer3D**: Spatial audio for units, explosions, combat
- **Audio Buses**: Separate buses for music, SFX, UI, ambient

### Serialization & Networking
- **Binary Format**: Struct packing, zlib compression, CRC32 checksums
- **Snapshot/Delta**: Full state snapshots + incremental deltas for saves
- **Deterministic Simulation**: Fixed-point math, deterministic RNG for multiplayer

### UI Systems
- **Control Nodes**: HUD, menus, resource displays
- **SubViewport**: Minimap, factory zoom views
- **Theme Resources**: Consistent styling across UI elements

### Server-Side Optimization (Critical for Scale)
- **RenderingServer**: Direct rendering API for maximum performance
  - Bypass scene tree overhead for bulk operations
  - `RenderingServer.instance_create()` for lightweight instances
  - `RenderingServer.canvas_item_*` for 2D UI optimization
  - Use for custom culling, batching beyond MultiMesh
  - Docs: https://docs.godotengine.org/en/stable/classes/class_renderingserver.html
- **PhysicsServer3D**: Direct physics queries without node overhead
  - `PhysicsServer3D.space_get_direct_state()` for raycasts, shape queries
  - Batch collision checks for projectile systems
  - Custom collision resolution for bullet-hell density
  - Docs: https://docs.godotengine.org/en/stable/classes/class_physicsserver3d.html
- **NavigationServer3D Direct Access**: Pathfinding without NavigationAgent overhead
  - `NavigationServer3D.map_get_path()` for direct path queries
  - Batch path requests for unit groups
  - Custom path smoothing and caching

### Threading & Parallelism
- **WorkerThreadPool**: Built-in thread pool for parallel tasks
  - `WorkerThreadPool.add_task()` for fire-and-forget work
  - `WorkerThreadPool.add_group_task()` for parallel batch processing
  - Use for AI updates, pathfinding, spatial queries
  - Docs: https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html
- **Thread Safety Patterns**:
  - Mutex for shared state protection
  - Semaphore for producer/consumer patterns
  - Double-buffering for thread-safe data exchange
  - Copy-on-write for read-heavy shared data
- **Parallel Processing Strategy**:
  - AI decisions: Process in chunks across frames or threads
  - Pathfinding: Batch requests, process in WorkerThreadPool
  - Collision: Spatial partitioning + parallel broad phase

### Spatial Partitioning (Critical for 5000+ Units)
- **Spatial Hashing**: O(1) neighbor queries for dense unit clusters
  - Hash position to cell index: `cell = floor(pos / cell_size)`
  - Ideal for uniform unit distributions
  - Use for: collision broad phase, area-of-effect targeting
  ```gdscript
  # Spatial hash pattern
  var cell_size: float = 10.0
  var grid: Dictionary = {}  # Vector2i -> Array[entity_id]
  func get_cell(pos: Vector3) -> Vector2i:
      return Vector2i(floor(pos.x / cell_size), floor(pos.z / cell_size))
  ```
- **Quadtree/Octree**: Hierarchical spatial indexing for varied density
  - Better for non-uniform distributions (clustered battles)
  - Dynamic insertion/removal as units move
  - Use for: range queries, nearest-neighbor, frustum culling
- **Grid-Based Partitioning**: Simple fixed-grid for predictable access
  - Pre-allocated arrays, cache-friendly iteration
  - Use for: district-based queries, power grid connections

### Flow Fields & Swarm Pathfinding
- **Flow Fields**: Single pathfind for unlimited units to same destination
  - Compute once, all units sample direction from field
  - Essential for swarm factions (Aether Swarm, OptiForge hordes)
  - Integration with NavigationServer for obstacle avoidance
  ```gdscript
  # Flow field pattern
  var flow_field: Dictionary = {}  # Vector2i -> Vector2 direction
  func get_flow_direction(pos: Vector3) -> Vector3:
      var cell := get_cell(pos)
      var dir_2d: Vector2 = flow_field.get(cell, Vector2.ZERO)
      return Vector3(dir_2d.x, 0, dir_2d.y)
  ```
- **Boids/Flocking**: Emergent swarm behavior
  - Separation: Avoid crowding neighbors
  - Alignment: Steer toward average heading of neighbors
  - Cohesion: Steer toward average position of neighbors
  - Add: obstacle avoidance, goal seeking, predator evasion
  - Critical for Aether Swarm micro-drone behavior
- **Hierarchical Pathfinding**: Multi-resolution for large maps
  - High-level: District-to-district navigation
  - Low-level: Local obstacle avoidance
  - Cache high-level paths, recompute local as needed

### Compute Shaders (GPU Simulation)
- **GPU Particle Simulation**: Offload projectile physics to GPU
  - Compute shader for position/velocity updates
  - Transform feedback or SSBO for CPU readback when needed
  - 10,000+ projectiles with minimal CPU cost
- **GPU Collision Detection**: Parallel broad-phase on GPU
  - Sort particles into spatial grid via compute
  - Detect collisions in parallel
  - Write collision events to buffer for CPU processing
- **Shader Storage Buffer Objects (SSBO)**: CPU-GPU data exchange
  - Upload unit positions for GPU-based queries
  - Download results (visibility, distances, collisions)

### Animation & Visual Polish
- **AnimationTree**: Complex unit animation state machines
  - BlendTree for smooth transitions (idle/walk/run/attack)
  - StateMachine for discrete states (combat, harvesting, building)
  - AnimationNodeOneShot for attack/ability animations
  - Docs: https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html
- **Tween**: Procedural animation for UI and effects
  - `create_tween()` for fire-and-forget animations
  - Chain with `tween_property()`, `tween_callback()`
  - Use for: damage numbers, UI transitions, camera shake
- **Skeleton3D & BoneAttachment3D**: Unit customization
  - Weapon/accessory attachment points
  - Procedural bone modification for damage states
- **Decals**: Battle damage on terrain/buildings
  - `Decal` node for crater marks, scorch marks, blood splatter
  - Pool and reuse decals for performance

### Shader Techniques (Faction Visual Identity)
- **Dissolve/Disintegration**: Unit death effects
  ```glsl
  // Dissolve shader snippet
  uniform float dissolve_amount : hint_range(0.0, 1.0);
  uniform sampler2D noise_texture;
  void fragment() {
      float noise = texture(noise_texture, UV).r;
      if (noise < dissolve_amount) discard;
      EMISSION = vec3(1.0, 0.5, 0.0) * step(noise, dissolve_amount + 0.05);
  }
  ```
- **Cloaking/Phasing**: Aether Swarm stealth effects
  - Fresnel rim glow, refraction distortion
  - Screen-space grab for transparency
- **Damage States**: Visual unit degradation
  - Vertex displacement for dents/deformation
  - Albedo lerp to damaged texture
  - Emissive cracks showing internal damage
- **Outline/Selection**: RTS unit selection feedback
  - Inverted hull method or post-process edge detection
  - Per-faction color coding
- **Fog of War Shader**: GPU-based visibility
  - Render visibility to texture
  - Sample in world shader for darkening

### Debug & Profiling Tools
- **Godot Profiler**: Built-in performance analysis
  - Monitor tab: FPS, physics, audio metrics
  - Debugger > Profiler: Function-level timing
  - Debugger > Visual Profiler: GPU timing
- **Custom Debug Overlays**: In-game performance HUD
  ```gdscript
  # Debug overlay pattern
  func _process(delta: float) -> void:
      if OS.is_debug_build():
          debug_label.text = "Units: %d\nProjectiles: %d\nFPS: %d" % [
              unit_count, projectile_count, Engine.get_frames_per_second()
          ]
  ```
- **Debug Draw**: Visual debugging for AI/physics
  - `DebugDraw3D` addon or custom ImmediateMesh
  - Draw paths, ranges, targets, spatial grid cells
- **Performance Budgets**: Frame time allocation
  - AI: 2-3ms, Physics: 2-3ms, Rendering: 8-10ms
  - Profile regularly, set alerts for budget overruns

### Memory Management Patterns
- **Object Pooling**: Pre-allocation to avoid GC stutters
  ```gdscript
  # Generic pool pattern
  class_name ObjectPool extends RefCounted
  var _pool: Array = []
  var _factory: Callable

  func _init(factory: Callable, initial_size: int = 100) -> void:
      _factory = factory
      for i in initial_size:
          _pool.append(_factory.call())

  func acquire() -> Variant:
      if _pool.is_empty():
          return _factory.call()
      return _pool.pop_back()

  func release(obj: Variant) -> void:
      _pool.append(obj)
  ```
- **Flyweight Pattern**: Share immutable data across instances
  - Unit stats, ability definitions as shared Resources
  - Reduce per-instance memory footprint
- **Struct-of-Arrays (SoA)**: Cache-friendly data layout
  - Instead of Array[Unit], use separate arrays for positions, healths, etc.
  - Better CPU cache utilization for batch processing

### Data-Driven Design
- **Custom Resources**: Externalize game data for balancing
  ```gdscript
  # Unit definition resource
  class_name UnitDefinition extends Resource
  @export var display_name: String
  @export var health: float = 100.0
  @export var speed: float = 5.0
  @export var damage: float = 10.0
  @export var abilities: Array[AbilityDefinition]
  ```
- **Resource Preloading**: Avoid runtime loading stutters
  - Preload all unit/ability definitions at game start
  - Use `ResourceLoader.load_threaded_request()` for async loading
- **Balance Spreadsheets**: External CSV/JSON for tuning
  - Import via EditorImportPlugin or runtime parsing
  - Hot-reload during development

### Editor Tools & Debugging
- **@tool Scripts**: In-editor visualization
  ```gdscript
  @tool
  extends Node3D
  @export var radius: float = 10.0:
      set(v):
          radius = v
          queue_redraw()  # Update gizmo
  ```
- **EditorPlugin**: Custom editor extensions
  - Custom inspectors for complex data
  - Toolbar buttons for common operations
  - Bottom panel for debug views
- **@export Annotations**: Inspector-friendly properties
  - `@export_range()`, `@export_enum()`, `@export_group()`
  - `@export_category()` for organization

### Strategic AI Patterns
- **Influence Maps**: Spatial representation of strategic value
  - Threat level, resource density, control zones
  - Update incrementally, sample for decisions
  - Use for: attack targets, retreat paths, expansion priority
- **Utility AI**: Score-based decision making
  - Evaluate multiple options with weighted criteria
  - More flexible than behavior trees for strategic decisions
  - Use for: faction-level strategy, resource allocation
- **Hierarchical Task Networks (HTN)**: Goal-oriented planning
  - Decompose high-level goals into primitive tasks
  - Better for complex multi-step strategies
  - Use for: build orders, coordinated attacks

### Multiplayer Considerations
- **Lockstep Simulation**: Deterministic gameplay for RTS
  - Fixed timestep, deterministic RNG
  - Only transmit inputs, simulate locally
  - Hash game state periodically to detect desync
- **Client Prediction**: Responsive feel despite latency
  - Predict local unit movement
  - Reconcile with server state
  - Interpolate remote units
- **Interest Management**: Reduce bandwidth
  - Only sync entities within player's view + margin
  - Priority-based updates (own units > enemies > projectiles)

## Conventions

### Naming
- **PascalCase**: Entity types, Component names, class names
- **snake_case**: Component properties, method names, variables

### Directory Structure
```
core/
├── abilities/              # Unit abilities and faction-specific powers
│   ├── faction/           # Faction-specific ability implementations
│   ├── formations/        # Formation-based abilities
│   └── production/        # Production-related abilities
├── ai/                    # AI systems
│   ├── behavior_tree/     # Custom behavior tree implementation
│   │   ├── actions/       # BT action nodes (attack, move, patrol, etc.)
│   │   └── conditions/    # BT condition nodes (has_target, in_range, etc.)
│   ├── behavior_trees/    # Pre-built behavior tree templates
│   ├── behaviors/         # High-level behavior patterns
│   ├── builder/           # AI for builder units
│   ├── components/        # AI-related components
│   ├── distributed/       # Distributed AI processing
│   ├── faction/           # Faction-level strategic AI
│   ├── human_resistance/  # Human Remnant NPC AI
│   ├── limbo_wrapper/     # LimboAI integration layer
│   ├── pathfinding/       # Navigation and pathfinding
│   ├── performance/       # AI performance optimization
│   ├── systems/           # AI system processors
│   └── targeting/         # Target selection and prioritization
├── audio/                 # Audio management and dynamic music
├── camera/                # Camera systems and controls
├── cinematics/            # Cutscene and cinematic systems
├── city/                  # Procedural city generation
├── combat/                # Combat systems
│   ├── faction_mechanics/ # Faction-specific combat rules
│   └── progression/       # Combat progression and XP
├── commands/              # Command pattern for unit orders
├── components/            # ECS components (health, movement, combat, faction)
├── destruction/           # Building destruction and debris
├── districts/             # District control and capture systems
├── ecs/                   # Entity Component System framework
├── factions/              # Faction definitions and state
│   ├── aether_swarm/      # Aether Swarm faction
│   ├── dynapods_vanguard/ # Dynapods Vanguard faction
│   ├── human_remnant/     # Human Remnant NPC faction
│   ├── logibots_colossus/ # LogiBots Colossus faction
│   └── optiforge_legion/  # OptiForge Legion faction
├── factory/               # Factory production and management
├── fog_of_war/            # Fog of war system
├── formations/            # Unit formation management
├── game/                  # Core game state and flow
├── input/                 # Input handling
├── network/               # Multiplayer networking
├── physics/               # Physics and collision
├── platform/              # Platform integration (Steam, etc.)
├── power_grid/            # Power generation and distribution
├── production/            # Unit production and costs
├── projectiles/           # Bullet hell projectile systems
│   ├── collision/         # Projectile collision handling
│   ├── physics/           # Projectile physics
│   └── rendering/         # Projectile rendering (MultiMesh)
├── repair/                # Unit repair systems
├── research/              # Technology research trees
├── resources/             # REE and resource management
├── save/                  # Save/load and replay systems
├── terrain/               # Terrain and voxel systems
├── ui/                    # User interface
├── units/                 # Unit definitions and management
│   ├── hacking/           # Hacking mechanics
│   │   ├── persistence/   # Hack state persistence
│   │   └── visual/        # Hack visual effects
│   └── logibots/          # LogiBots-specific units
├── victory/               # Victory condition checking
├── view/                  # View and camera management
└── waves/                 # Wave spawning system
tests/                     # Test suites
├── ai/                    # AI-specific tests
└── network/               # Network-specific tests
```

### Serialization Requirements
- All entity and component data must be binary-serializable
- No circular references in component data
- Components validate serializability on creation

## Key Systems Reference

### ECS Framework (`core/ecs/`)
| Class | Purpose |
|-------|---------|
| `Entity` | Base entity with component storage |
| `Component` | Base component class |
| `EntityManager` | Entity lifecycle and querying |
| `System` | Base system for processing entities |
| `SystemManager` | System registration and tick ordering |
| `ECSWorld` | Top-level ECS container |

### Save System (`core/save/`)
| Class | Purpose |
|-------|---------|
| `SaveManager` | High-level save/load orchestration |
| `BinarySaveFile` | Binary format with zlib compression |
| `SnapshotManager` | Full state snapshots |
| `Delta` | Incremental state changes |
| `BackupManager` | Automatic backup rotation |
| `CloudSync` | Steam cloud integration |
| `ReplayRecorder` | Records gameplay for replay/verification |
| `ReplayVerifier` | Validates replays for leaderboards |

### Game Flow (`core/game/`)
| Class | Purpose |
|-------|---------|
| `GameStateManager` | Match state, pause, duration tracking |
| `EndGameManager` | Victory/defeat flow, spectator mode |
| `VictoryConditionSystem` | Continuous win/loss monitoring |

### Resource Economy (`core/resources/`)
| Class | Purpose |
|-------|---------|
| `ResourceManager` | REE storage and transactions |
| `ResourcePool` | Per-faction resource pools |
| `PassiveIncomeGenerator` | District-based income ticks |
| `ResourceIntegration` | Connects districts to economy |

### Production (`core/production/`)
| Class | Purpose |
|-------|---------|
| `ProductionCostValidator` | Validates REE costs, atomic transactions |
| `Factory` | Unit production queues |

### Factions (`core/factions/`)
| Class | Purpose |
|-------|---------|
| `FactionManager` | All faction lifecycle |
| `FactionState` | Per-faction runtime state |
| `AetherSwarmFaction` | Aether Swarm specifics |
| `AetherSwarmProgression` | XP pools and buff unlocks |
| `HumanResistanceFaction` | Human Remnant NPC faction |

### Districts (`core/districts/`)
| Class | Purpose |
|-------|---------|
| `DistrictManager` | District grid management |
| `DistrictCaptureSystem` | Capture mechanics |
| `DistrictResourceTracker` | Per-district resources |

### Terrain (`core/terrain/`)
| Class | Purpose |
|-------|---------|
| `TerrainFlatteningSystem` | Building disassembly, map evolution |

### AI (`core/ai/`)
| Class | Purpose |
|-------|---------|
| `UnitBehaviorManager` | Per-unit AI orchestration |
| `BehaviorTreeWrapper` | Executes behavior trees |
| `BTAction`, `BTCondition` | Behavior tree nodes |
| `HumanResistanceAI` | Human Remnant strategic AI |

## Code Patterns

### RefCounted Base Class
Most game systems extend `RefCounted` (not `Node`) for lightweight, non-scene objects:
```gdscript
class_name MySystem
extends RefCounted

signal something_happened(data: Dictionary)

func _init() -> void:
    pass
```

### Serialization Pattern
All persistent classes implement `to_dict()` and `from_dict()`:
```gdscript
func to_dict() -> Dictionary:
    return {
        "property": _property,
        "nested": _nested.to_dict()
    }

func from_dict(data: Dictionary) -> void:
    _property = data.get("property", default_value)
    _nested.from_dict(data.get("nested", {}))
```

### Signal-Based Communication
Systems communicate via signals, not direct method calls:
```gdscript
signal unit_spawned(unit_id: int, unit_type: String)
signal resource_changed(faction_id: int, amount: float)
```

### Inner Classes for Data Structures
Use inner classes for tightly-coupled data:
```gdscript
class ValidationResult:
    var is_valid: bool = false
    var reason: String = ""
```

## Building and Testing

### Prerequisites
- Godot 4.5 (add to PATH or use full path)
- For voxel terrain: Custom Godot build with godot_voxel module

### Adding Godot to PATH (Windows)
```cmd
setx PATH "%PATH%;C:\Godot"
```

### Running Tests
Run all Phase 6 system tests:
```cmd
godot --headless --path "c:\Claude\AGIDay" --script tests/test_phase6_systems.gd
```

Run specific test suites:
```cmd
godot --headless --path "c:\Claude\AGIDay" --script tests/test_ecs.gd
godot --headless --path "c:\Claude\AGIDay" --script tests/test_save_system.gd
godot --headless --path "c:\Claude\AGIDay" --script tests/test_snapshot_delta.gd
godot --headless --path "c:\Claude\AGIDay" --script tests/test_save_system_integration.gd
```

### Opening the Project
```cmd
godot --path "c:\Claude\AGIDay" --editor
```

### Test Structure
Tests use a simple assertion-based pattern:
```gdscript
func _assert(condition: bool, test_name: String) -> void:
    _test_count += 1
    if condition:
        _pass_count += 1
        print("  [PASS] %s" % test_name)
    else:
        _fail_count += 1
        print("  [FAIL] %s" % test_name)
```

## Performance Targets
- 5,000+ units and 10,000+ projectiles at 60fps
- Save operations: <1s
- Load operations: <2s
- Save file size: <50MB on disk, <500MB in memory

## Performance Anti-Patterns (Avoid These)

### GDScript Pitfalls
- **Avoid `get_node()` in loops**: Cache node references in `_ready()`
- **Avoid string concatenation in hot paths**: Use `%` formatting or StringName
- **Avoid `find_*` methods per frame**: Cache results, use spatial structures
- **Avoid creating objects in `_process()`**: Pool everything reusable
- **Avoid signals with many connections**: Batch updates, use direct calls for hot paths

### Scene Tree Overhead
- **Don't use Node for pure data**: Use RefCounted or Resource instead
- **Don't add/remove nodes frequently**: Use object pools, toggle visibility
- **Don't use `get_children()` per frame**: Cache child arrays
- **Don't rely on `_process()` for everything**: Use timers, coroutines for infrequent updates

### Physics Mistakes
- **Don't use physics for non-physical entities**: Use manual position updates
- **Don't raycast per unit per frame**: Batch queries, use spatial partitioning
- **Don't use `move_and_slide()` for projectiles**: Manual position + collision check
- **Don't enable collision for off-screen entities**: Dynamic enable/disable

### Memory Allocation
- **Don't create Arrays/Dictionaries in hot paths**: Pre-allocate, reuse
- **Don't use `duplicate()` unnecessarily**: Share immutable data
- **Don't store references in components**: Use IDs, resolve when needed
- **Don't forget to null references**: Prevents memory leaks in pools

## GDExtension (C++ Performance)

For truly performance-critical systems that GDScript cannot handle:

### When to Use GDExtension
- Spatial partitioning with millions of queries/second
- Complex pathfinding algorithms (A*, flow fields)
- Physics simulation beyond Godot's built-in
- Custom rendering techniques
- SIMD-optimized math operations

### GDExtension Setup
```cpp
// Example: High-performance spatial hash
#include <godot_cpp/classes/ref_counted.hpp>
#include <unordered_map>
#include <vector>

class SpatialHash : public RefCounted {
    GDCLASS(SpatialHash, RefCounted);

    float cell_size = 10.0f;
    std::unordered_map<int64_t, std::vector<int>> grid;

    int64_t hash_position(const Vector3& pos) {
        int x = static_cast<int>(pos.x / cell_size);
        int z = static_cast<int>(pos.z / cell_size);
        return (static_cast<int64_t>(x) << 32) | static_cast<int64_t>(z);
    }

public:
    void insert(int entity_id, const Vector3& position);
    void remove(int entity_id, const Vector3& position);
    PackedInt32Array query_radius(const Vector3& center, float radius);
};
```

### GDExtension Resources
- Docs: https://docs.godotengine.org/en/stable/tutorials/scripting/gdextension/
- godot-cpp: https://github.com/godotengine/godot-cpp
- Template: https://github.com/godotengine/gdextension-template

## Quality Assurance Patterns

### Automated Testing Strategy
```gdscript
# Test categories for this project
# 1. Unit tests: Individual system logic (ECS, resources, combat math)
# 2. Integration tests: System interactions (save/load, production chain)
# 3. Performance tests: Frame time budgets, memory usage
# 4. Determinism tests: Replay verification, state hash comparison
```

### Determinism Verification
- Hash game state every N frames during replay recording
- Compare hashes during replay playback
- Log first divergence point for debugging
- Critical for multiplayer and leaderboard integrity

### Performance Regression Testing
```gdscript
# Performance test pattern
func test_unit_spawning_performance() -> void:
    var start_time := Time.get_ticks_usec()
    for i in 1000:
        entity_manager.spawn_unit("basic_drone", Vector3.ZERO)
    var elapsed := Time.get_ticks_usec() - start_time
    _assert(elapsed < 50000, "1000 unit spawn < 50ms")  # 50us per unit budget
```

### Memory Leak Detection
- Track pool sizes before/after operations
- Monitor entity count vs expected
- Use `OS.get_static_memory_usage()` for baseline comparisons

## Work Orders

This project uses the Software Factory MCP server for work order management:
- `mcp__software-factory__get_next_work_order` - Fetch next available task
- `mcp__software-factory__start_work_order` - Mark work order as in progress
- `mcp__software-factory__complete_work_order` - Mark work order for review
