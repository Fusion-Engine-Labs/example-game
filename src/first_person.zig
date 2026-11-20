//! First-person movement and look for the entity with a
//! `FirstPersonController`: cursor-locked mouse look, acceleration-based
//! walking, sprint, buffered jumps with coyote time, gravity, stair stepping,
//! head bob, and a sprint field-of-view kick.

const std = @import("std");

const collision = @import("collision.zig");
const fusion = @import("fusion_sdk");
const game_components = @import("game_components.zig");

const CameraComponent = fusion.components.CameraComponent;
const FirstPersonController = game_components.FirstPersonController;
const FirstPersonState = game_components.FirstPersonState;
const TransformComponent = fusion.components.TransformComponent;
const Quat = fusion.Quat;
const Vec3 = fusion.Vec3;

pub const max_pitch: f32 = std.math.pi / 2.0 - 0.01;
/// Falling below this height respawns the player.
const kill_height: f32 = -25;
const jump_buffer_seconds: f32 = 0.12;
const coyote_seconds: f32 = 0.1;
/// Meters walked per footstep, for head bob.
const stride: f32 = 1.15;

/// The camera after this step's movement, for systems that follow it.
pub const Pose = struct {
    position: Vec3,
    rotation: Quat,
    forward: Vec3,
    velocity: Vec3,
    grounded: bool,
    bob_phase: f32,
    bob_weight: f32,
    landing_dip: f32,
};

/// Adds runtime state to every controller, starting from where its camera
/// is placed and facing in the scene.
pub fn start(world: fusion.World) !void {
    var query = try world.query(.{ .read = &.{ TransformComponent, FirstPersonController } });
    while (try query.each()) |row| {
        const transform = try row.read(TransformComponent);
        const controller = try row.read(FirstPersonController);
        const camera = try world.get(row.entity, CameraComponent) orelse CameraComponent{};
        const facing = yawPitchFromForward(transform.forward());
        const feet = transform.position.sub(Vec3.new(0, controller.eye_height, 0));

        try world.add(row.entity, FirstPersonState{
            .feet = feet,
            .yaw = facing.yaw,
            .pitch = facing.pitch,
            .spawn = feet,
            .spawn_yaw = facing.yaw,
            .base_fov = camera.fov,
        });
    }
}

/// Moves the first controller found and returns its camera pose, or null if
/// the scene has none. Clicking locks the cursor for mouse look and Escape
/// releases it (the editor also releases it on Escape, Pause, and Stop).
pub fn update(world: fusion.World, frame: *const fusion.Frame, colliders: []const collision.Aabb) !?Pose {
    var query = try world.query(.{
        .read = &.{FirstPersonController},
        .write = &.{ TransformComponent, FirstPersonState, CameraComponent },
    });

    while (try query.each()) |row| {
        if (!frame.cursor_locked and frame.wasMousePressed(.Left)) try world.setCursorLocked(true);
        if (frame.cursor_locked and frame.wasKeyPressed(.Escape)) try world.setCursorLocked(false);

        const controller = try row.read(FirstPersonController);
        var state = try row.read(FirstPersonState);
        var transform = try row.read(TransformComponent);
        var camera = try row.read(CameraComponent);

        const pose = step(&state, controller, frame, colliders);
        transform.position = pose.position;
        transform.rotation = pose.rotation;
        camera.fov = state.base_fov * (1 + controller.sprint_fov_boost * state.sprint_blend);

        try row.write(FirstPersonState, state);
        try row.write(TransformComponent, transform);
        try row.write(CameraComponent, camera);
        return pose;
    }
    return null;
}

/// One fixed step of look and movement.
pub fn step(
    state: *FirstPersonState,
    controller: FirstPersonController,
    frame: *const fusion.Frame,
    colliders: []const collision.Aabb,
) Pose {
    const dt = frame.seconds;
    applyLook(state, controller, frame);

    // Horizontal: accelerate toward the speed the keys ask for.
    const wish = wishDirection(frame, state.yaw);
    const moving = wish.x != 0 or wish.z != 0;
    const sprinting = moving and frame.isKeyDown(.LeftShift);
    const speed = controller.move_speed * if (sprinting) controller.sprint_multiplier else 1.0;
    const accel = controller.acceleration * if (state.grounded) 1.0 else controller.air_control;
    const horizontal = moveTowards(
        Vec3.new(state.velocity.x, 0, state.velocity.z),
        wish.scale(speed),
        accel * dt,
    );
    state.velocity.x = horizontal.x;
    state.velocity.z = horizontal.z;

    // Jumping: remember presses briefly and allow them just after a ledge.
    state.jump_buffer = if (frame.wasKeyPressed(.Space)) jump_buffer_seconds else @max(state.jump_buffer - dt, 0);
    state.coyote_time = if (state.grounded) coyote_seconds else @max(state.coyote_time - dt, 0);
    if (state.jump_buffer > 0 and state.coyote_time > 0) {
        state.velocity.y = controller.jump_speed;
        state.jump_buffer = 0;
        state.coyote_time = 0;
        state.grounded = false;
    }
    state.velocity.y -= controller.gravity * dt;

    const body: collision.Body = .{ .radius = controller.radius, .height = controller.height };
    const step_height = if (state.grounded) controller.step_height else 0;
    const fall_speed = -state.velocity.y;
    const move = collision.moveBody(state.feet, state.velocity.scale(dt), body, step_height, colliders);
    state.feet = move.feet;
    if (move.blocked_x) state.velocity.x = 0;
    if (move.blocked_z) state.velocity.z = 0;
    if (move.hit_ceiling and state.velocity.y > 0) state.velocity.y = 0;

    const was_grounded = state.grounded;
    state.grounded = move.landed;
    if (move.landed) {
        if (!was_grounded and fall_speed > 4) {
            state.landing_dip = @min((fall_speed - 4) * 0.012, 0.14);
        }
        state.velocity.y = 0;
    }
    state.landing_dip = approach(state.landing_dip, 0, dt * 0.6);

    if (state.feet.y < kill_height) respawn(state);

    // Head bob follows distance walked, fading in and out with speed.
    const ground_speed = horizontal.length();
    const bobbing = state.grounded and ground_speed > 0.5;
    state.bob_weight = approach(state.bob_weight, if (bobbing) @min(ground_speed / controller.move_speed, 1.3) else 0, dt * 6);
    state.bob_phase = @mod(state.bob_phase + ground_speed * dt * std.math.pi / stride, std.math.tau);
    state.sprint_blend = approach(state.sprint_blend, if (sprinting and state.grounded) 1 else 0, dt * 5);

    const bob = -@abs(@sin(state.bob_phase)) * controller.head_bob * state.bob_weight;
    const rotation = orientation(state.yaw, state.pitch);
    return .{
        .position = state.feet.add(Vec3.new(0, controller.eye_height + bob - state.landing_dip, 0)),
        .rotation = rotation,
        .forward = rotation.rotateVec3(Vec3.new(0, 0, -1)),
        .velocity = state.velocity,
        .grounded = state.grounded,
        .bob_phase = state.bob_phase,
        .bob_weight = state.bob_weight,
        .landing_dip = state.landing_dip,
    };
}

/// Mouse look while the cursor is locked, plus arrow-key turning that works
/// without the mouse.
fn applyLook(state: *FirstPersonState, controller: FirstPersonController, frame: *const fusion.Frame) void {
    if (frame.cursor_locked) {
        state.yaw -= frame.mouse_delta[0] * controller.look_sensitivity;
        state.pitch -= frame.mouse_delta[1] * controller.look_sensitivity;
    }

    const turn = controller.turn_speed * frame.seconds;
    if (frame.isKeyDown(.Left)) state.yaw += turn;
    if (frame.isKeyDown(.Right)) state.yaw -= turn;
    if (frame.isKeyDown(.Up)) state.pitch += turn * 0.7;
    if (frame.isKeyDown(.Down)) state.pitch -= turn * 0.7;

    state.yaw = @mod(state.yaw, std.math.tau);
    state.pitch = std.math.clamp(state.pitch, -max_pitch, max_pitch);
}

fn respawn(state: *FirstPersonState) void {
    state.feet = state.spawn;
    state.velocity = Vec3.zero;
    state.yaw = state.spawn_yaw;
    state.pitch = 0;
    state.grounded = false;
}

/// Camera rotation for a yaw around +Y followed by a pitch around the
/// camera's own X axis.
pub fn orientation(yaw: f32, pitch: f32) Quat {
    return Quat.fromAxisAngle(Vec3.unitY, yaw).mul(Quat.fromAxisAngle(Vec3.unitX, pitch));
}

/// Inverse of `orientation` for a forward vector.
pub fn yawPitchFromForward(forward: Vec3) struct { yaw: f32, pitch: f32 } {
    const f = collision.safeNormalize(forward, Vec3.new(0, 0, -1));
    return .{
        .yaw = std.math.atan2(-f.x, -f.z),
        .pitch = std.math.clamp(std.math.asin(std.math.clamp(f.y, -1, 1)), -max_pitch, max_pitch),
    };
}

/// Unit horizontal direction from WASD relative to `yaw`, or zero.
pub fn wishDirection(frame: *const fusion.Frame, yaw: f32) Vec3 {
    var forward_amount: f32 = 0;
    var right_amount: f32 = 0;
    if (frame.isKeyDown(.W)) forward_amount += 1;
    if (frame.isKeyDown(.S)) forward_amount -= 1;
    if (frame.isKeyDown(.D)) right_amount += 1;
    if (frame.isKeyDown(.A)) right_amount -= 1;
    if (forward_amount == 0 and right_amount == 0) return Vec3.zero;

    const forward = Vec3.new(-@sin(yaw), 0, -@cos(yaw));
    const right = Vec3.new(@cos(yaw), 0, -@sin(yaw));
    return forward.scale(forward_amount).add(right.scale(right_amount)).normalize();
}

/// Moves `current` toward `target` by at most `max_delta`.
pub fn moveTowards(current: Vec3, target: Vec3, max_delta: f32) Vec3 {
    const difference = target.sub(current);
    const distance = difference.length();
    if (distance <= max_delta or distance < 1e-6) return target;
    return current.add(difference.scale(max_delta / distance));
}

fn approach(current: f32, target: f32, max_delta: f32) f32 {
    if (current < target) return @min(current + max_delta, target);
    return @max(current - max_delta, target);
}

const testing = std.testing;
const tolerance: f32 = 1e-4;

fn frameWithKeys(keys: []const fusion.Key) fusion.Frame {
    var frame: fusion.Frame = .{ .seconds = 1.0 / 60.0 };
    for (keys) |key| frame.keys[@backingInt(key)] = 1;
    return frame;
}

const arena_floor = [_]collision.Aabb{.{ .min = Vec3.new(-50, -1, -50), .max = Vec3.new(50, 0, 50) }};

fn standingState() FirstPersonState {
    return .{ .feet = Vec3.zero, .grounded = true };
}

fn stepDefault(state: *FirstPersonState, controller: FirstPersonController, frame: *const fusion.Frame, colliders: []const collision.Aabb) void {
    _ = step(state, controller, frame, colliders);
}

test "orientation and yawPitchFromForward round-trip" {
    const rotation = orientation(0.7, -0.3);
    const look = yawPitchFromForward(rotation.rotateVec3(Vec3.new(0, 0, -1)));
    try testing.expectApproxEqAbs(@as(f32, 0.7), look.yaw, tolerance);
    try testing.expectApproxEqAbs(@as(f32, -0.3), look.pitch, tolerance);
}

test "zero yaw looks down -Z" {
    const forward = orientation(0, 0).rotateVec3(Vec3.new(0, 0, -1));
    try testing.expectApproxEqAbs(@as(f32, -1), forward.z, tolerance);
}

test "wishDirection is relative to yaw and normalized" {
    const forward = wishDirection(&frameWithKeys(&.{.W}), 0);
    try testing.expectApproxEqAbs(@as(f32, -1), forward.z, tolerance);

    // Facing -X (yaw 90°), W moves -X and D moves -Z.
    const turned = wishDirection(&frameWithKeys(&.{.W}), std.math.pi / 2.0);
    try testing.expectApproxEqAbs(@as(f32, -1), turned.x, tolerance);
    const strafe = wishDirection(&frameWithKeys(&.{.D}), std.math.pi / 2.0);
    try testing.expectApproxEqAbs(@as(f32, -1), strafe.z, tolerance);

    const diagonal = wishDirection(&frameWithKeys(&.{ .W, .D }), 0);
    try testing.expectApproxEqAbs(@as(f32, 1), diagonal.length(), tolerance);

    const none = wishDirection(&frameWithKeys(&.{ .W, .S, .A, .D }), 0);
    try testing.expectEqual(@as(f32, 0), none.length());
}

test "moveTowards caps the change per step" {
    const result = moveTowards(Vec3.zero, Vec3.new(10, 0, 0), 2);
    try testing.expectApproxEqAbs(@as(f32, 2), result.x, tolerance);
    try testing.expectApproxEqAbs(@as(f32, 10), moveTowards(Vec3.new(9, 0, 0), Vec3.new(10, 0, 0), 2).x, tolerance);
}

test "walking forward reaches move speed and stays on the floor" {
    var state = standingState();
    const controller: FirstPersonController = .{};
    const frame = frameWithKeys(&.{.W});
    for (0..60) |_| stepDefault(&state, controller, &frame, &arena_floor);

    try testing.expect(state.grounded);
    try testing.expectApproxEqAbs(-controller.move_speed, state.velocity.z, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 0), state.feet.y, 0.01);
    try testing.expect(state.feet.z < -4);
}

test "sprinting is faster than walking" {
    var walk = standingState();
    var sprint = standingState();
    const controller: FirstPersonController = .{};
    for (0..60) |_| {
        stepDefault(&walk, controller, &frameWithKeys(&.{.W}), &arena_floor);
        stepDefault(&sprint, controller, &frameWithKeys(&.{ .W, .LeftShift }), &arena_floor);
    }
    try testing.expect(sprint.feet.z < walk.feet.z - 2);
    try testing.expect(sprint.sprint_blend > 0.9);
}

test "a jump rises about v²/2g and lands again" {
    var state = standingState();
    const controller: FirstPersonController = .{};
    var frame = frameWithKeys(&.{});
    frame.keys_pressed[@backingInt(fusion.Key.Space)] = 1;
    stepDefault(&state, controller, &frame, &arena_floor);
    try testing.expect(!state.grounded);

    const idle = frameWithKeys(&.{});
    var peak: f32 = 0;
    for (0..120) |_| {
        stepDefault(&state, controller, &idle, &arena_floor);
        peak = @max(peak, state.feet.y);
    }
    const expected = controller.jump_speed * controller.jump_speed / (2 * controller.gravity);
    try testing.expectApproxEqAbs(expected, peak, 0.08);
    try testing.expect(state.grounded);
}

test "a jump pressed just before landing still fires" {
    // Airborne and 2 cm up: this step's fall lands, but the press came first.
    var state: FirstPersonState = .{ .feet = Vec3.new(0, 0.02, 0), .velocity = Vec3.new(0, -2, 0) };
    const controller: FirstPersonController = .{};
    var frame = frameWithKeys(&.{});
    frame.keys_pressed[@backingInt(fusion.Key.Space)] = 1;
    stepDefault(&state, controller, &frame, &arena_floor);
    try testing.expect(state.grounded);

    stepDefault(&state, controller, &frameWithKeys(&.{}), &arena_floor);
    try testing.expect(state.velocity.y > 0);
}

test "mouse movement turns the camera only while the cursor is locked" {
    var state = standingState();
    var frame = frameWithKeys(&.{});
    frame.cursor_locked = true;
    frame.mouse_delta = .{ -100, 50 };
    _ = step(&state, .{ .look_sensitivity = 0.01 }, &frame, &arena_floor);
    try testing.expectApproxEqAbs(@as(f32, 1), state.yaw, tolerance);
    try testing.expectApproxEqAbs(@as(f32, -0.5), state.pitch, tolerance);

    // With a free cursor the mouse is for the editor, not the view.
    frame.cursor_locked = false;
    _ = step(&state, .{ .look_sensitivity = 0.01 }, &frame, &arena_floor);
    try testing.expectApproxEqAbs(@as(f32, 1), state.yaw, tolerance);
}

test "pitch is clamped short of straight up" {
    var state = standingState();
    _ = step(&state, .{ .turn_speed = 1000 }, &frameWithKeys(&.{.Up}), &arena_floor);
    try testing.expectApproxEqAbs(max_pitch, state.pitch, tolerance);
}

test "falling out of the world respawns at the start" {
    var state: FirstPersonState = .{ .feet = Vec3.new(3, -30, 3), .spawn = Vec3.new(1, 0, 2), .spawn_yaw = 0.5 };
    _ = step(&state, .{}, &frameWithKeys(&.{}), &.{});
    try testing.expectApproxEqAbs(@as(f32, 1), state.feet.x, tolerance);
    try testing.expectApproxEqAbs(@as(f32, 0.5), state.yaw, tolerance);
}
