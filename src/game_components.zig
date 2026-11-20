const sdk = @import("fusion_sdk");

const scene = sdk.scene_schema;

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
pub const ProjectileComponent = struct {
    velocity: sdk.Vec3 = sdk.Vec3.zero,
    remaining: f32 = 0,

    pub const schema_meta = scene.SchemaMeta{
        .id = "8c1f2a70-3d5e-4b91-8f42-1a6b9c0d3e04",
        .name = "fusion.game.Projectile",
        .display_name = "Projectile",
        .version = 1,
        .fields = &.{
            .{ .name = "velocity", .number = 1, .display_name = "Velocity" },
            .{ .name = "remaining", .number = 2, .display_name = "Remaining", .editor = .{ .min = 0 } },
        },
    };
};
