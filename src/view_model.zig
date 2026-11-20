//! Keeps `ViewModel` entities (the held blaster, crosshair, and hit marker)
//! locked to the first-person camera, with walk sway, recoil kick, landing
//! dip, and pull-back when the barrel would poke through a wall.

const std = @import("std");

const collision = @import("collision.zig");
const first_person = @import("first_person.zig");
const fusion = @import("fusion_sdk");
const game_components = @import("game_components.zig");

const TransformComponent = fusion.components.TransformComponent;
const ViewModel = game_components.ViewModel;
const Quat = fusion.Quat;
const Vec3 = fusion.Vec3;

/// Wall distance below which the held weapon starts pulling back.
const reach: f32 = 0.95;
const max_retract: f32 = 0.55;

pub fn update(
    world: fusion.World,
    pose: first_person.Pose,
    recoil: f32,
    hit_marker: f32,
    colliders: []const collision.Aabb,
) !void {
    const wall_distance = collision.rayDistance(pose.position, pose.forward, reach, colliders);
    const retract = std.math.clamp(reach - wall_distance, 0, max_retract);

    var query = try world.query(.{ .read = &.{ViewModel}, .write = &.{TransformComponent} });
    while (try query.each()) |row| {
        const view_model = try row.read(ViewModel);
        var transform = try row.read(TransformComponent);

        const placement = place(view_model, pose, recoil, if (view_model.retract_when_blocked) retract else 0);
        transform.position = pose.position.add(pose.rotation.rotateVec3(placement.offset));
        transform.rotation = pose.rotation.mul(placement.kick);
        if (view_model.show_on_hit) {
            transform.scale = if (hit_marker > 0) Vec3.one.scale(1 + 0.5 * hit_marker) else Vec3.zero;
        }
        try row.write(TransformComponent, transform);
    }
}

const Placement = struct { offset: Vec3, kick: Quat };

/// Camera-space offset and extra rotation for one view model this step.
fn place(view_model: ViewModel, pose: first_person.Pose, recoil: f32, retract: f32) Placement {
    var offset = view_model.offset;
    var kick = Quat.identity;

    if (view_model.sway > 0) {
        const bob = pose.bob_weight * view_model.sway;
        // Side to side once per two steps; rises a little as the head dips.
        offset.x += @sin(pose.bob_phase) * 0.011 * bob;
        offset.y += @abs(@sin(pose.bob_phase)) * 0.006 * bob;
        offset.y -= pose.landing_dip * 0.35 * view_model.sway;

        offset.z += recoil * 0.055 * view_model.sway;
        offset.y += recoil * 0.008 * view_model.sway;
        kick = Quat.fromAxisAngle(Vec3.unitX, recoil * 0.14 * view_model.sway);
    }

    offset.z += retract;
    offset.y -= retract * 0.25;
    return .{ .offset = offset, .kick = kick };
}

const testing = std.testing;
const tolerance: f32 = 1e-4;

const still_pose: first_person.Pose = .{
    .position = Vec3.zero,
    .rotation = Quat.identity,
    .forward = Vec3.new(0, 0, -1),
    .velocity = Vec3.zero,
    .grounded = true,
    .bob_phase = 0,
    .bob_weight = 0,
    .landing_dip = 0,
};

test "a still camera places the view model exactly at its offset" {
    const placement = place(.{ .offset = Vec3.new(0.2, -0.2, -0.4) }, still_pose, 0, 0);
    try testing.expectApproxEqAbs(@as(f32, 0.2), placement.offset.x, tolerance);
    try testing.expectApproxEqAbs(@as(f32, -0.4), placement.offset.z, tolerance);
    try testing.expectEqual(Quat.identity, placement.kick);
}

test "recoil pushes the weapon back and tilts it up" {
    const placement = place(.{ .offset = Vec3.new(0, 0, -0.4) }, still_pose, 1, 0);
    try testing.expect(placement.offset.z > -0.4);
    const barrel = placement.kick.rotateVec3(Vec3.new(0, 0, -1));
    try testing.expect(barrel.y > 0);
}

test "zero sway ignores bob and recoil but still retracts" {
    var pose = still_pose;
    pose.bob_phase = 1;
    pose.bob_weight = 1;
    const placement = place(.{ .offset = Vec3.new(0, 0, -0.2), .sway = 0 }, pose, 1, 0.1);
    try testing.expectApproxEqAbs(@as(f32, 0), placement.offset.x, tolerance);
    try testing.expectApproxEqAbs(@as(f32, -0.1), placement.offset.z, tolerance);
    try testing.expectEqual(Quat.identity, placement.kick);
}
