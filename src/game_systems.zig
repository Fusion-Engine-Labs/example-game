const std = @import("std");

const game_components = @import("game_components.zig");
const fusion = @import("fusion_sdk");

const KeyboardMovementComponent = game_components.KeyboardMovementComponent;
const ProjectileLauncherComponent = game_components.ProjectileLauncherComponent;
const ProjectileComponent = game_components.ProjectileComponent;
const MeshRenderComponent = fusion.components.MeshRenderComponent;
const TransformComponent = fusion.components.TransformComponent;
const Vec3 = fusion.Vec3;

pub fn keyboardMovementSystem(world: fusion.World, input: *const fusion.Frame) !void {
    const direction = keyboardDirection(input);
    if (direction.x == 0 and direction.z == 0) {
        return;
    }

    const delta_time = input.seconds;
    var iter = try world.query(.{
        .write = &.{TransformComponent},
        .read = &.{KeyboardMovementComponent},
    });

    while (try iter.each()) |entity| {
        var transform = try entity.read(TransformComponent);
        const controller = try entity.read(KeyboardMovementComponent);

        const speed = controller.speed * if (input.isKeyDown(.LeftShift))
            controller.sprint_multiplier
        else
            1.0;
        const movement = direction.normalize().scale(speed * delta_time);
        transform.position = transform.position.add(movement);
        transform.rotation = fusion.Quat.fromAxisAngle(
            Vec3.new(0, 1, 0),
            std.math.atan2(-movement.x, -movement.z),
        );
        try entity.write(TransformComponent, transform);
    }
}

fn keyboardDirection(input: *const fusion.Frame) Vec3 {
    var direction = Vec3.zero;

    if (input.isKeyDown(.W) or input.isKeyDown(.Up)) direction.z -= 1;
    if (input.isKeyDown(.S) or input.isKeyDown(.Down)) direction.z += 1;
    if (input.isKeyDown(.A) or input.isKeyDown(.Left)) direction.x -= 1;
    if (input.isKeyDown(.D) or input.isKeyDown(.Right)) direction.x += 1;

    return direction;
}

pub fn update(world: fusion.World, frame: *const fusion.Frame) !void {
    try keyboardMovementSystem(world, frame);
    try launchProjectilesSystem(world, frame);
    try projectileSystem(world, frame);
}

/// Spawns one projectile per launcher on the step Space goes down.
pub fn launchProjectilesSystem(world: fusion.World, frame: *const fusion.Frame) !void {
    if (!frame.wasKeyPressed(.Space)) {
        return;
    }

    var launchers = try world.query(.{
        .read = &.{ TransformComponent, MeshRenderComponent, ProjectileLauncherComponent },
    });

    while (try launchers.each()) |row| {
        const transform = try row.read(TransformComponent);
        const mesh = try row.read(MeshRenderComponent);
        const launcher = try row.read(ProjectileLauncherComponent);

        _ = try world.spawn(.{
            TransformComponent{
                .position = transform.position,
                .rotation = transform.rotation,
                .scale = transform.scale.scale(launcher.scale),
            },
            MeshRenderComponent{ .mesh = mesh.mesh },
            ProjectileComponent{
                .velocity = transform.forward().scale(launcher.speed),
                .remaining = launcher.lifetime,
            },
        });
    }
}

/// Moves projectiles and removes each one when its lifetime runs out.
pub fn projectileSystem(world: fusion.World, frame: *const fusion.Frame) !void {
    var projectiles = try world.query(.{
        .write = &.{ TransformComponent, ProjectileComponent },
    });

    while (try projectiles.each()) |row| {
        var projectile = try row.read(ProjectileComponent);
        projectile.remaining -= frame.seconds;
        if (projectile.remaining <= 0) {
            try row.despawn();
            continue;
        }
        try row.write(ProjectileComponent, projectile);

        var transform = try row.read(TransformComponent);
        transform.position = transform.position.add(projectile.velocity.scale(frame.seconds));
        try row.write(TransformComponent, transform);
    }
}

const testing = std.testing;

fn inputWithKeysDown(keys: []const fusion.Key) fusion.Frame {
    var input: fusion.Frame = .{};
    for (keys) |key| {
        input.keys[@backingInt(key)] = 1;
    }
    return input;
}

test "keyboardDirection is zero with no keys held" {
    const input: fusion.Frame = .{};
    const direction = keyboardDirection(&input);

    try testing.expectEqual(@as(f32, 0), direction.x);
    try testing.expectEqual(@as(f32, 0), direction.z);
}

test "keyboardDirection maps WASD to forward/back/left/right" {
    try testing.expectEqual(@as(f32, -1), keyboardDirection(&inputWithKeysDown(&.{.W})).z);
    try testing.expectEqual(@as(f32, 1), keyboardDirection(&inputWithKeysDown(&.{.S})).z);
    try testing.expectEqual(@as(f32, -1), keyboardDirection(&inputWithKeysDown(&.{.A})).x);
    try testing.expectEqual(@as(f32, 1), keyboardDirection(&inputWithKeysDown(&.{.D})).x);
}

test "keyboardDirection treats arrow keys as aliases for WASD" {
    try testing.expectEqual(@as(f32, -1), keyboardDirection(&inputWithKeysDown(&.{.Up})).z);
    try testing.expectEqual(@as(f32, 1), keyboardDirection(&inputWithKeysDown(&.{.Down})).z);
    try testing.expectEqual(@as(f32, -1), keyboardDirection(&inputWithKeysDown(&.{.Left})).x);
    try testing.expectEqual(@as(f32, 1), keyboardDirection(&inputWithKeysDown(&.{.Right})).x);
}

test "keyboardDirection combines simultaneous keys" {
    const direction = keyboardDirection(&inputWithKeysDown(&.{ .W, .D }));

    try testing.expectEqual(@as(f32, -1), direction.z);
    try testing.expectEqual(@as(f32, 1), direction.x);
}

test "keyboardDirection cancels opposing keys" {
    const direction = keyboardDirection(&inputWithKeysDown(&.{ .W, .S, .A, .D }));

    try testing.expectEqual(@as(f32, 0), direction.z);
    try testing.expectEqual(@as(f32, 0), direction.x);
}
