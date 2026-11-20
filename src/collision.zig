//! Axis-aligned collision for the arena: static `BoxCollider` solids, a
//! feet-anchored player body that slides and steps, and swept tests for
//! projectiles and aim rays.

const std = @import("std");

const fusion = @import("fusion_sdk");
const game_components = @import("game_components.zig");

const BoxCollider = game_components.BoxCollider;
const TransformComponent = fusion.components.TransformComponent;
const Vec3 = fusion.Vec3;

/// Gap kept between a resolved body and the surface it touches, so resting
/// contact does not count as overlap on the next step.
const skin: f32 = 0.001;

/// Most colliders `gather` collects. Extra ones are ignored with a warning.
pub const max_colliders = 512;

pub const Aabb = struct {
    min: Vec3,
    max: Vec3,

    pub fn fromCenter(center: Vec3, half: Vec3) Aabb {
        return .{ .min = center.sub(half), .max = center.add(half) };
    }

    /// True when the interiors intersect; touching faces do not overlap.
    pub fn overlaps(a: Aabb, b: Aabb) bool {
        return a.min.x < b.max.x and a.max.x > b.min.x and
            a.min.y < b.max.y and a.max.y > b.min.y and
            a.min.z < b.max.z and a.max.z > b.min.z;
    }

    pub fn containsPoint(a: Aabb, p: Vec3) bool {
        return p.x > a.min.x and p.x < a.max.x and
            p.y > a.min.y and p.y < a.max.y and
            p.z > a.min.z and p.z < a.max.z;
    }

    pub fn expand(a: Aabb, amount: f32) Aabb {
        const grow = Vec3.new(amount, amount, amount);
        return .{ .min = a.min.sub(grow), .max = a.max.add(grow) };
    }
};

/// Where along a segment something was hit (0 = start, 1 = end) and the
/// surface normal there.
pub const Hit = struct {
    t: f32,
    normal: Vec3,
};

/// Collects every `BoxCollider` in the world into `buffer`.
pub fn gather(world: fusion.World, buffer: []Aabb) ![]Aabb {
    var count: usize = 0;
    var skipped: usize = 0;
    var query = try world.query(.{ .read = &.{ TransformComponent, BoxCollider } });
    while (try query.each()) |row| {
        if (count == buffer.len) {
            skipped += 1;
            continue;
        }
        const transform = try row.read(TransformComponent);
        const collider = try row.read(BoxCollider);
        buffer[count] = colliderBox(transform, collider);
        count += 1;
    }
    if (skipped > 0) {
        world.log(.warn, "{d} box colliders over the limit of {d} were ignored", .{ skipped, buffer.len });
    }
    return buffer[0..count];
}

/// The world-space box of a collider on an entity at `transform`.
pub fn colliderBox(transform: TransformComponent, collider: BoxCollider) Aabb {
    const scale = Vec3.new(@abs(transform.scale.x), @abs(transform.scale.y), @abs(transform.scale.z));
    const center = transform.position.add(collider.offset.mul(transform.scale));
    return Aabb.fromCenter(center, collider.half_extents.mul(scale));
}

/// First hit of the segment `from`→`to` against `box`. A segment starting
/// inside the box hits at t = 0.
pub fn segmentAabb(from: Vec3, to: Vec3, box: Aabb) ?Hit {
    const delta = to.sub(from);
    if (box.containsPoint(from)) {
        return .{ .t = 0, .normal = safeNormalize(delta.neg(), Vec3.unitY) };
    }

    var t_enter: f32 = 0;
    var t_exit: f32 = 1;
    var normal = Vec3.zero;

    inline for (.{ Axis.x, Axis.y, Axis.z }) |axis| {
        const start = get(from, axis);
        const d = get(delta, axis);
        const lo = get(box.min, axis);
        const hi = get(box.max, axis);

        if (@abs(d) < 1e-9) {
            if (start < lo or start > hi) return null;
        } else {
            const inv = 1.0 / d;
            var t0 = (lo - start) * inv;
            var t1 = (hi - start) * inv;
            if (t0 > t1) std.mem.swap(f32, &t0, &t1);
            if (t0 > t_enter) {
                t_enter = t0;
                // Entering through the face that opposes the motion.
                normal = with(Vec3.zero, axis, if (d > 0) -1 else 1);
            }
            t_exit = @min(t_exit, t1);
            if (t_enter > t_exit) return null;
        }
    }
    return .{ .t = t_enter, .normal = normal };
}

/// First hit of the segment `from`→`to` against a sphere.
pub fn segmentSphere(from: Vec3, to: Vec3, center: Vec3, radius: f32) ?Hit {
    const d = to.sub(from);
    const f = from.sub(center);
    const c = f.dot(f) - radius * radius;
    if (c <= 0) {
        return .{ .t = 0, .normal = safeNormalize(f, d.neg()) };
    }

    const a = d.dot(d);
    if (a < 1e-12) return null;
    const b = 2 * f.dot(d);
    const discriminant = b * b - 4 * a * c;
    if (discriminant < 0) return null;

    const t = (-b - @sqrt(discriminant)) / (2 * a);
    if (t < 0 or t > 1) return null;
    const point = from.add(d.scale(t));
    return .{ .t = t, .normal = safeNormalize(point.sub(center), d.neg()) };
}

/// Distance along `direction` from `origin` to the first collider, or
/// `max_distance` if nothing is closer.
pub fn rayDistance(origin: Vec3, direction: Vec3, max_distance: f32, colliders: []const Aabb) f32 {
    const end = origin.add(direction.scale(max_distance));
    var nearest: f32 = 1;
    for (colliders) |box| {
        if (segmentAabb(origin, end, box)) |hit| nearest = @min(nearest, hit.t);
    }
    return nearest * max_distance;
}

/// A vertical box standing on `feet`.
pub const Body = struct {
    radius: f32,
    height: f32,

    pub fn box(self: Body, feet: Vec3) Aabb {
        return .{
            .min = Vec3.new(feet.x - self.radius, feet.y, feet.z - self.radius),
            .max = Vec3.new(feet.x + self.radius, feet.y + self.height, feet.z + self.radius),
        };
    }

    fn lowOffset(self: Body, axis: Axis) f32 {
        return if (axis == .y) 0 else -self.radius;
    }

    fn highOffset(self: Body, axis: Axis) f32 {
        return if (axis == .y) self.height else self.radius;
    }
};

pub const Move = struct {
    feet: Vec3,
    blocked_x: bool = false,
    blocked_z: bool = false,
    /// Moving down ended on a surface.
    landed: bool = false,
    /// Moving up ended against a surface.
    hit_ceiling: bool = false,
    /// Climbed a ledge no taller than the step height.
    stepped: bool = false,
};

/// Moves `body` from `feet` by `delta`, sliding along anything in the way.
/// When horizontal movement is blocked and `step_height` > 0, it also tries
/// the move from `step_height` higher and keeps that if it lands on a ledge
/// and gets further, which lets the body walk up stairs.
pub fn moveBody(feet: Vec3, delta: Vec3, body: Body, step_height: f32, colliders: []const Aabb) Move {
    const along_x = sweep(feet, .x, delta.x, body, colliders);
    const along_z = sweep(along_x.feet, .z, delta.z, body, colliders);
    var result: Move = .{ .feet = along_z.feet, .blocked_x = along_x.blocked, .blocked_z = along_z.blocked };

    if ((along_x.blocked or along_z.blocked) and step_height > 0) {
        const up = sweep(feet, .y, step_height, body, colliders);
        const step_x = sweep(up.feet, .x, delta.x, body, colliders);
        const step_z = sweep(step_x.feet, .z, delta.z, body, colliders);
        const down = sweep(step_z.feet, .y, feet.y - up.feet.y, body, colliders);
        const plain = horizontalDistance2(feet, result.feet);
        const stepped = horizontalDistance2(feet, down.feet);
        if (down.blocked and stepped > plain + 1e-8) {
            result = .{
                .feet = down.feet,
                .blocked_x = step_x.blocked,
                .blocked_z = step_z.blocked,
                .stepped = true,
            };
        }
    }

    const vertical = sweep(result.feet, .y, delta.y, body, colliders);
    result.feet = vertical.feet;
    if (vertical.blocked) {
        if (delta.y < 0) result.landed = true else result.hit_ceiling = true;
    }
    return result;
}

const Sweep = struct { feet: Vec3, blocked: bool };

/// Moves along one axis, stopping at the first collider in the way.
/// Colliders the body already overlaps are ignored so it can always move out.
fn sweep(feet: Vec3, comptime axis: Axis, amount: f32, body: Body, colliders: []const Aabb) Sweep {
    if (amount == 0) return .{ .feet = feet, .blocked = false };

    const before = body.box(feet);
    var moved = with(feet, axis, get(feet, axis) + amount);
    var blocked = false;
    for (colliders) |collider| {
        if (!body.box(moved).overlaps(collider) or before.overlaps(collider)) continue;
        blocked = true;
        const limit = if (amount > 0)
            get(collider.min, axis) - body.highOffset(axis) - skin
        else
            get(collider.max, axis) - body.lowOffset(axis) + skin;
        moved = with(moved, axis, limit);
    }
    return .{ .feet = moved, .blocked = blocked };
}

fn horizontalDistance2(a: Vec3, b: Vec3) f32 {
    const dx = b.x - a.x;
    const dz = b.z - a.z;
    return dx * dx + dz * dz;
}

/// `v` scaled to unit length, or `fallback` when `v` is (nearly) zero.
pub fn safeNormalize(v: Vec3, fallback: Vec3) Vec3 {
    const length = v.length();
    if (length < 1e-6) return fallback;
    return v.scale(1.0 / length);
}

const Axis = enum { x, y, z };

fn get(v: Vec3, comptime axis: Axis) f32 {
    return @field(v, @tagName(axis));
}

fn with(v: Vec3, comptime axis: Axis, value: f32) Vec3 {
    var result = v;
    @field(result, @tagName(axis)) = value;
    return result;
}

const testing = std.testing;
const tolerance: f32 = 1e-4;

const unit_body: Body = .{ .radius = 0.5, .height = 2 };
const floor = Aabb{ .min = Vec3.new(-50, -1, -50), .max = Vec3.new(50, 0, 50) };

test "aabb overlap excludes touching faces" {
    const a = Aabb.fromCenter(Vec3.zero, Vec3.one);
    try testing.expect(a.overlaps(Aabb.fromCenter(Vec3.new(1.5, 0, 0), Vec3.one)));
    try testing.expect(!a.overlaps(Aabb.fromCenter(Vec3.new(2, 0, 0), Vec3.one)));
}

test "collider box follows position, offset, and scale" {
    const box = colliderBox(
        .{ .position = Vec3.new(10, 0, 0), .scale = Vec3.new(2, 4, -1) },
        .{ .half_extents = Vec3.new(0.5, 0.5, 0.5), .offset = Vec3.new(0, 0.5, 0) },
    );
    try testing.expectApproxEqAbs(@as(f32, 9), box.min.x, tolerance);
    try testing.expectApproxEqAbs(@as(f32, 11), box.max.x, tolerance);
    try testing.expectApproxEqAbs(@as(f32, 0), box.min.y, tolerance);
    try testing.expectApproxEqAbs(@as(f32, 4), box.max.y, tolerance);
    try testing.expectApproxEqAbs(@as(f32, 1), box.max.z - box.min.z, tolerance);
}

test "segmentAabb reports entry time and the face normal" {
    const box = Aabb.fromCenter(Vec3.new(5, 0, 0), Vec3.one);
    const hit = segmentAabb(Vec3.zero, Vec3.new(10, 0, 0), box).?;
    try testing.expectApproxEqAbs(@as(f32, 0.4), hit.t, tolerance);
    try testing.expectApproxEqAbs(@as(f32, -1), hit.normal.x, tolerance);

    try testing.expect(segmentAabb(Vec3.zero, Vec3.new(3, 0, 0), box) == null);
    try testing.expect(segmentAabb(Vec3.new(0, 5, 0), Vec3.new(10, 5, 0), box) == null);
    try testing.expectEqual(@as(f32, 0), segmentAabb(Vec3.new(5, 0, 0), Vec3.new(6, 0, 0), box).?.t);
}

test "segmentAabb hits the top face when falling" {
    const hit = segmentAabb(Vec3.new(0, 3, 0), Vec3.new(0, -3, 0), floor).?;
    try testing.expectApproxEqAbs(@as(f32, 0.5), hit.t, tolerance);
    try testing.expectApproxEqAbs(@as(f32, 1), hit.normal.y, tolerance);
}

test "segmentSphere finds the near intersection" {
    const hit = segmentSphere(Vec3.zero, Vec3.new(0, 0, -10), Vec3.new(0, 0, -5), 1).?;
    try testing.expectApproxEqAbs(@as(f32, 0.4), hit.t, tolerance);
    try testing.expectApproxEqAbs(@as(f32, 1), hit.normal.z, tolerance);
    try testing.expect(segmentSphere(Vec3.zero, Vec3.new(0, 0, -3), Vec3.new(0, 0, -5), 1) == null);
    try testing.expect(segmentSphere(Vec3.new(2, 0, 0), Vec3.new(2, 0, -10), Vec3.new(0, 0, -5), 1) == null);
}

test "rayDistance stops at the nearest collider" {
    const near = Aabb.fromCenter(Vec3.new(0, 0, -3), Vec3.new(1, 1, 0.5));
    const far = Aabb.fromCenter(Vec3.new(0, 0, -8), Vec3.new(1, 1, 0.5));
    const colliders = [_]Aabb{ far, near };
    try testing.expectApproxEqAbs(@as(f32, 2.5), rayDistance(Vec3.zero, Vec3.new(0, 0, -1), 20, &colliders), tolerance);
    try testing.expectApproxEqAbs(@as(f32, 20), rayDistance(Vec3.zero, Vec3.new(0, 1, 0), 20, &colliders), tolerance);
}

test "moveBody lands on the floor and reports it" {
    const colliders = [_]Aabb{floor};
    const move = moveBody(Vec3.new(0, 0.5, 0), Vec3.new(0, -1, 0), unit_body, 0, &colliders);
    try testing.expect(move.landed);
    try testing.expectApproxEqAbs(@as(f32, 0), move.feet.y, 0.01);
}

test "moveBody slides along a wall instead of stopping" {
    const wall = Aabb{ .min = Vec3.new(1, 0, -10), .max = Vec3.new(2, 3, 10) };
    const colliders = [_]Aabb{ floor, wall };
    const move = moveBody(Vec3.new(0, 0, 0), Vec3.new(1, 0, 1), unit_body, 0, &colliders);
    try testing.expect(move.blocked_x);
    try testing.expect(!move.blocked_z);
    try testing.expectApproxEqAbs(@as(f32, 0.5), move.feet.x, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 1), move.feet.z, tolerance);
}

test "moveBody walks up a low step but not a tall one" {
    const low = Aabb{ .min = Vec3.new(0.6, 0, -5), .max = Vec3.new(5, 0.3, 5) };
    const low_move = moveBody(Vec3.new(0, 0, 0), Vec3.new(0.5, 0, 0), unit_body, 0.45, &.{ floor, low });
    try testing.expect(low_move.stepped);
    try testing.expectApproxEqAbs(@as(f32, 0.3), low_move.feet.y, 0.01);
    try testing.expectApproxEqAbs(@as(f32, 0.5), low_move.feet.x, tolerance);

    const tall = Aabb{ .min = Vec3.new(0.6, 0, -5), .max = Vec3.new(5, 1.0, 5) };
    const tall_move = moveBody(Vec3.new(0, 0, 0), Vec3.new(0.5, 0, 0), unit_body, 0.45, &.{ floor, tall });
    try testing.expect(!tall_move.stepped);
    try testing.expect(tall_move.blocked_x);
    try testing.expectApproxEqAbs(@as(f32, 0), tall_move.feet.y, tolerance);
}

test "moveBody stops at a ceiling" {
    const ceiling = Aabb{ .min = Vec3.new(-5, 2.5, -5), .max = Vec3.new(5, 3, 5) };
    const move = moveBody(Vec3.new(0, 0, 0), Vec3.new(0, 1, 0), unit_body, 0, &.{ceiling});
    try testing.expect(move.hit_ceiling);
    try testing.expectApproxEqAbs(@as(f32, 0.5), move.feet.y, 0.01);
}

test "moveBody can always move out of a collider it starts inside" {
    const box = Aabb.fromCenter(Vec3.zero, Vec3.one);
    const move = moveBody(Vec3.new(0, 0, 0), Vec3.new(2, 0, 0), unit_body, 0, &.{box});
    try testing.expectApproxEqAbs(@as(f32, 2), move.feet.x, tolerance);
}
