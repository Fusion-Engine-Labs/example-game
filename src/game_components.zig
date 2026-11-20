const sdk = @import("fusion_sdk");

const scene = sdk.scene_schema;
const Vec3 = sdk.Vec3;
const Quat = sdk.Quat;

/// Asset reference type used by built-in components such as `MeshRenderComponent`.
pub const AssetId = @FieldType(sdk.components.MeshRenderComponent, "mesh");

pub const KeyboardMovementComponent = struct {
    speed: f32 = 2.5,
    sprint_multiplier: f32 = 2.0,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e01",
        .name = "fusion.game.KeyboardMovement",
        .display_name = "Keyboard Movement",
        .version = 1,
        .fields = &.{
            .{ .name = "speed", .number = 1, .display_name = "Speed", .editor = .{ .min = 0 } },
            .{ .name = "sprint_multiplier", .number = 2, .display_name = "Sprint Multiplier", .editor = .{ .min = 1 } },
        },
    };
};

/// Fires a copy of its entity's mesh forward each time Space is pressed.
pub const ProjectileLauncherComponent = struct {
    speed: f32 = 6.0,
    lifetime: f32 = 2.0,
    scale: f32 = 0.25,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e03",
        .name = "fusion.game.ProjectileLauncher",
        .display_name = "Projectile Launcher",
        .version = 1,
        .fields = &.{
            .{ .name = "speed", .number = 1, .display_name = "Speed", .editor = .{ .min = 0 } },
            .{ .name = "lifetime", .number = 2, .display_name = "Lifetime", .editor = .{ .min = 0 } },
            .{ .name = "scale", .number = 3, .display_name = "Scale", .editor = .{ .min = 0.01 } },
        },
    };
};

/// Runtime-only state of a fired projectile. Never authored in a scene.
/// Projectiles stop at the first `BoxCollider` or live target they touch.
pub const ProjectileComponent = struct {
    velocity: Vec3 = Vec3.zero,
    remaining: f32 = 0,
    gravity: f32 = 0,
    /// Collision radius, in world units.
    radius: f32 = 0,
    damage: f32 = 1,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e04",
        .name = "fusion.game.Projectile",
        .display_name = "Projectile",
        .version = 1,
        .fields = &.{
            .{ .name = "velocity", .number = 1, .display_name = "Velocity" },
            .{ .name = "remaining", .number = 2, .display_name = "Remaining", .editor = .{ .min = 0 } },
            .{ .name = "gravity", .number = 3, .display_name = "Gravity" },
            .{ .name = "radius", .number = 4, .display_name = "Radius", .editor = .{ .min = 0 } },
            .{ .name = "damage", .number = 5, .display_name = "Damage", .editor = .{ .min = 0 } },
        },
    };
};

/// First-person player: WASD to move, Shift to sprint, Space to jump. Click
/// to lock the cursor for mouse look (Escape releases it); the arrow keys
/// also look. Put it on the entity with the active camera; the transform is
/// the eye position.
pub const FirstPersonController = struct {
    move_speed: f32 = 5.5,
    sprint_multiplier: f32 = 1.6,
    /// How quickly velocity reaches the target speed on the ground, in m/s².
    acceleration: f32 = 55,
    /// Fraction of `acceleration` available while airborne.
    air_control: f32 = 0.3,
    jump_speed: f32 = 7.0,
    gravity: f32 = 20,
    height: f32 = 1.8,
    radius: f32 = 0.35,
    /// Tallest ledge the player walks up without jumping.
    step_height: f32 = 0.45,
    eye_height: f32 = 1.6,
    /// Radians of turn per pixel of mouse movement.
    look_sensitivity: f32 = 0.0015,
    /// Radians per second when turning with the arrow keys.
    turn_speed: f32 = 2.5,
    /// Camera dip per footstep, in meters.
    head_bob: f32 = 0.035,
    /// Extra field of view while sprinting, as a fraction of the camera's.
    sprint_fov_boost: f32 = 0.08,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e05",
        .name = "fusion.game.FirstPersonController",
        .display_name = "First Person Controller",
        .version = 1,
        .fields = &.{
            .{ .name = "move_speed", .number = 1, .display_name = "Move Speed", .editor = .{ .min = 0 } },
            .{ .name = "sprint_multiplier", .number = 2, .display_name = "Sprint Multiplier", .editor = .{ .min = 1 } },
            .{ .name = "acceleration", .number = 3, .display_name = "Acceleration", .editor = .{ .min = 0 } },
            .{ .name = "air_control", .number = 4, .display_name = "Air Control", .editor = .{ .min = 0, .max = 1, .slider = true } },
            .{ .name = "jump_speed", .number = 5, .display_name = "Jump Speed", .editor = .{ .min = 0 } },
            .{ .name = "gravity", .number = 6, .display_name = "Gravity", .editor = .{ .min = 0 } },
            .{ .name = "height", .number = 7, .display_name = "Height", .editor = .{ .min = 0.1 } },
            .{ .name = "radius", .number = 8, .display_name = "Radius", .editor = .{ .min = 0.05 } },
            .{ .name = "step_height", .number = 9, .display_name = "Step Height", .editor = .{ .min = 0 } },
            .{ .name = "eye_height", .number = 10, .display_name = "Eye Height", .editor = .{ .min = 0 } },
            .{ .name = "look_sensitivity", .number = 11, .display_name = "Look Sensitivity", .editor = .{ .min = 0 } },
            .{ .name = "turn_speed", .number = 12, .display_name = "Turn Speed", .editor = .{ .min = 0 } },
            .{ .name = "head_bob", .number = 13, .display_name = "Head Bob", .editor = .{ .min = 0 } },
            .{ .name = "sprint_fov_boost", .number = 14, .display_name = "Sprint FOV Boost", .editor = .{ .min = 0, .max = 0.5, .slider = true } },
        },
    };
};

/// Runtime-only state of a `FirstPersonController`. Added when play starts.
pub const FirstPersonState = struct {
    /// Bottom-center of the player's body.
    feet: Vec3 = Vec3.zero,
    velocity: Vec3 = Vec3.zero,
    yaw: f32 = 0,
    pitch: f32 = 0,
    grounded: bool = false,
    bob_phase: f32 = 0,
    bob_weight: f32 = 0,
    landing_dip: f32 = 0,
    /// Seconds a jump press is remembered before landing.
    jump_buffer: f32 = 0,
    /// Seconds a jump is still allowed after walking off a ledge.
    coyote_time: f32 = 0,
    sprint_blend: f32 = 0,
    /// Where the player started, for respawning after a fall.
    spawn: Vec3 = Vec3.zero,
    spawn_yaw: f32 = 0,
    /// The camera's authored field of view, before the sprint boost.
    base_fov: f32 = 0,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e06",
        .name = "fusion.game.FirstPersonState",
        .display_name = "First Person State",
        .version = 1,
        .fields = &.{
            .{ .name = "feet", .number = 1, .display_name = "Feet" },
            .{ .name = "velocity", .number = 2, .display_name = "Velocity" },
            .{ .name = "yaw", .number = 3, .display_name = "Yaw" },
            .{ .name = "pitch", .number = 4, .display_name = "Pitch" },
            .{ .name = "grounded", .number = 5, .display_name = "Grounded" },
            .{ .name = "bob_phase", .number = 6, .display_name = "Bob Phase" },
            .{ .name = "bob_weight", .number = 7, .display_name = "Bob Weight" },
            .{ .name = "landing_dip", .number = 8, .display_name = "Landing Dip" },
            .{ .name = "jump_buffer", .number = 9, .display_name = "Jump Buffer" },
            .{ .name = "coyote_time", .number = 10, .display_name = "Coyote Time" },
            .{ .name = "sprint_blend", .number = 11, .display_name = "Sprint Blend" },
            .{ .name = "spawn", .number = 12, .display_name = "Spawn" },
            .{ .name = "spawn_yaw", .number = 13, .display_name = "Spawn Yaw" },
            .{ .name = "base_fov", .number = 14, .display_name = "Base FOV" },
        },
    };
};

/// Static, axis-aligned solid that blocks players and projectiles. The box is
/// centered on the entity's position plus `offset`, and both are multiplied
/// by the entity's scale; rotation is ignored.
pub const BoxCollider = struct {
    half_extents: Vec3 = Vec3.new(0.5, 0.5, 0.5),
    offset: Vec3 = Vec3.zero,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e07",
        .name = "fusion.game.BoxCollider",
        .display_name = "Box Collider",
        .version = 1,
        .fields = &.{
            .{ .name = "half_extents", .number = 1, .display_name = "Half Extents" },
            .{ .name = "offset", .number = 2, .display_name = "Offset" },
        },
    };
};

/// Hold the left mouse button to fire energy bolts from the first-person
/// camera while the cursor is locked. Put it on the same entity as the
/// `FirstPersonController`. Unset meshes are simply not drawn.
pub const Blaster = struct {
    /// Shots per second while the trigger is held.
    fire_rate: f32 = 7,
    projectile_speed: f32 = 45,
    projectile_lifetime: f32 = 2.5,
    projectile_gravity: f32 = 0,
    projectile_radius: f32 = 0.07,
    damage: f32 = 1,
    /// Where bolts leave the barrel, in camera space (-Z is forward).
    muzzle_offset: Vec3 = Vec3.new(0.16, -0.165, -0.88),
    /// Strength of the view model kick per shot.
    recoil: f32 = 1,
    projectile_mesh: AssetId = AssetId.zero,
    impact_mesh: AssetId = AssetId.zero,
    muzzle_flash_mesh: AssetId = AssetId.zero,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e08",
        .name = "fusion.game.Blaster",
        .display_name = "Blaster",
        .version = 1,
        .fields = &.{
            .{ .name = "fire_rate", .number = 1, .display_name = "Fire Rate", .editor = .{ .min = 0.1 } },
            .{ .name = "projectile_speed", .number = 2, .display_name = "Projectile Speed", .editor = .{ .min = 0 } },
            .{ .name = "projectile_lifetime", .number = 3, .display_name = "Projectile Lifetime", .editor = .{ .min = 0 } },
            .{ .name = "projectile_gravity", .number = 4, .display_name = "Projectile Gravity" },
            .{ .name = "projectile_radius", .number = 5, .display_name = "Projectile Radius", .editor = .{ .min = 0 } },
            .{ .name = "damage", .number = 6, .display_name = "Damage", .editor = .{ .min = 0 } },
            .{ .name = "muzzle_offset", .number = 7, .display_name = "Muzzle Offset" },
            .{ .name = "recoil", .number = 8, .display_name = "Recoil", .editor = .{ .min = 0 } },
            .{ .name = "projectile_mesh", .number = 9, .display_name = "Projectile Mesh", .kind_override = .{ .asset_ref = .mesh }, .default_override = .{ .asset_ref = AssetId.zero } },
            .{ .name = "impact_mesh", .number = 10, .display_name = "Impact Mesh", .kind_override = .{ .asset_ref = .mesh }, .default_override = .{ .asset_ref = AssetId.zero } },
            .{ .name = "muzzle_flash_mesh", .number = 11, .display_name = "Muzzle Flash Mesh", .kind_override = .{ .asset_ref = .mesh }, .default_override = .{ .asset_ref = AssetId.zero } },
        },
    };
};

/// Runtime-only state of a `Blaster`. Added when play starts.
pub const BlasterState = struct {
    cooldown: f32 = 0,
    /// 1 right after a shot, decaying to 0; drives the view model kick.
    recoil: f32 = 0,
    /// The trigger has been up since the cursor was locked, so the click
    /// that locked it does not also fire.
    armed: bool = false,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e09",
        .name = "fusion.game.BlasterState",
        .display_name = "Blaster State",
        .version = 1,
        .fields = &.{
            .{ .name = "cooldown", .number = 1, .display_name = "Cooldown" },
            .{ .name = "recoil", .number = 2, .display_name = "Recoil" },
            .{ .name = "armed", .number = 3, .display_name = "Armed" },
        },
    };
};

/// Locks an entity to the first-person camera every step: the held weapon,
/// the crosshair, and the hit marker.
pub const ViewModel = struct {
    /// Position in camera space (-Z is forward).
    offset: Vec3 = Vec3.new(0.16, -0.18, -0.46),
    /// Multiplier for walk bob and recoil. 0 keeps the entity perfectly still.
    sway: f32 = 1,
    /// Pull back toward the camera when a wall is closer than the barrel.
    retract_when_blocked: bool = true,
    /// Only visible for a moment after a projectile hits a target.
    show_on_hit: bool = false,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e0a",
        .name = "fusion.game.ViewModel",
        .display_name = "View Model",
        .version = 1,
        .fields = &.{
            .{ .name = "offset", .number = 1, .display_name = "Offset" },
            .{ .name = "sway", .number = 2, .display_name = "Sway", .editor = .{ .min = 0 } },
            .{ .name = "retract_when_blocked", .number = 3, .display_name = "Retract When Blocked" },
            .{ .name = "show_on_hit", .number = 4, .display_name = "Show On Hit" },
        },
    };
};

/// Something to shoot. Moves along `motion` (a sine sweep of that length in
/// each direction), and respawns `respawn_delay` seconds after it is destroyed.
pub const Target = struct {
    health: f32 = 1,
    /// Hit sphere radius at scale 1.
    radius: f32 = 0.5,
    points: u32 = 100,
    respawn_delay: f32 = 6,
    motion: Vec3 = Vec3.zero,
    /// Radians per second of the motion sweep.
    motion_speed: f32 = 1,
    /// Radians per second around the vertical axis. Ignored when facing the player.
    spin_speed: f32 = 0,
    face_player: bool = true,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e0b",
        .name = "fusion.game.Target",
        .display_name = "Target",
        .version = 1,
        .fields = &.{
            .{ .name = "health", .number = 1, .display_name = "Health", .editor = .{ .min = 0.1 } },
            .{ .name = "radius", .number = 2, .display_name = "Radius", .editor = .{ .min = 0.01 } },
            .{ .name = "points", .number = 3, .display_name = "Points" },
            .{ .name = "respawn_delay", .number = 4, .display_name = "Respawn Delay", .editor = .{ .min = 0 } },
            .{ .name = "motion", .number = 5, .display_name = "Motion" },
            .{ .name = "motion_speed", .number = 6, .display_name = "Motion Speed" },
            .{ .name = "spin_speed", .number = 7, .display_name = "Spin Speed" },
            .{ .name = "face_player", .number = 8, .display_name = "Face Player" },
        },
    };
};

/// Runtime-only state of a `Target`. Added when play starts.
pub const TargetState = struct {
    origin: Vec3 = Vec3.zero,
    base_scale: Vec3 = Vec3.one,
    base_rotation: Quat = Quat.identity,
    time: f32 = 0,
    phase: f32 = 0,
    health: f32 = 1,
    alive: bool = true,
    /// Counts down to the next respawn while destroyed.
    respawn_timer: f32 = 0,
    /// 1 on a hit, decaying to 0; drives the squash-and-pop feedback.
    hit_pulse: f32 = 0,
    /// Counts down the destroy animation.
    dying: f32 = 0,
    /// Counts down the respawn grow-in animation.
    appearing: f32 = 0,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e0c",
        .name = "fusion.game.TargetState",
        .display_name = "Target State",
        .version = 1,
        .fields = &.{
            .{ .name = "origin", .number = 1, .display_name = "Origin" },
            .{ .name = "base_scale", .number = 2, .display_name = "Base Scale" },
            .{ .name = "base_rotation", .number = 3, .display_name = "Base Rotation" },
            .{ .name = "time", .number = 4, .display_name = "Time" },
            .{ .name = "phase", .number = 5, .display_name = "Phase" },
            .{ .name = "health", .number = 6, .display_name = "Health" },
            .{ .name = "alive", .number = 7, .display_name = "Alive" },
            .{ .name = "respawn_timer", .number = 8, .display_name = "Respawn Timer" },
            .{ .name = "hit_pulse", .number = 9, .display_name = "Hit Pulse" },
            .{ .name = "dying", .number = 10, .display_name = "Dying" },
            .{ .name = "appearing", .number = 11, .display_name = "Appearing" },
        },
    };
};

/// Runtime-only short-lived effect: sparks, debris, and muzzle flashes.
/// Shrinks to nothing over its lifetime, then despawns.
pub const Particle = struct {
    velocity: Vec3 = Vec3.zero,
    remaining: f32 = 0,
    lifetime: f32 = 1,
    size: f32 = 0.1,
    gravity: f32 = 0,
    drag: f32 = 0,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e0d",
        .name = "fusion.game.Particle",
        .display_name = "Particle",
        .version = 1,
        .fields = &.{
            .{ .name = "velocity", .number = 1, .display_name = "Velocity" },
            .{ .name = "remaining", .number = 2, .display_name = "Remaining" },
            .{ .name = "lifetime", .number = 3, .display_name = "Lifetime" },
            .{ .name = "size", .number = 4, .display_name = "Size" },
            .{ .name = "gravity", .number = 5, .display_name = "Gravity" },
            .{ .name = "drag", .number = 6, .display_name = "Drag" },
        },
    };
};
