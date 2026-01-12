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

## Conventions

### Naming
- **PascalCase**: Entity types, Component names, class names
- **snake_case**: Component properties, method names, variables

### Directory Structure
- `core/`: ECS framework and base classes

### Serialization Requirements
- All entity and component data must be binary-serializable
- No circular references in component data
- Components validate serializability on creation

## Performance Targets
- 5,000+ units and 10,000+ projectiles at 60fps
- Save operations: <1s
- Load operations: <2s
- Save file size: <50MB on disk, <500MB in memory

## Work Orders

This project uses the Software Factory MCP server for work order management:
- `mcp__software-factory__get_next_work_order` - Fetch next available task
- `mcp__software-factory__start_work_order` - Mark work order as in progress
- `mcp__software-factory__complete_work_order` - Mark work order for review
