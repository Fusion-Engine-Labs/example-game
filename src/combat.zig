//! Shooting: the blaster, energy bolts, targets, spark effects, and scoring.
//! Score and stats are logged to the editor Console as you play.

const std = @import("std");

const collision = @import("collision.zig");
const first_person = @import("first_person.zig");
const fusion = @import("fusion_sdk");
const game_components = @import("game_components.zig");

const AssetId = game_components.AssetId;
const Blaster = game_components.Blaster;
const BlasterState = game_components.BlasterState;
const MeshRenderComponent = fusion.components.MeshRenderComponent;
const Particle = game_components.Particle;
const ProjectileComponent = game_components.ProjectileComponent;
const Target = game_components.Target;
const TargetState = game_components.TargetState;
const TransformComponent = fusion.components.TransformComponent;
const Quat = fusion.Quat;
const Vec3 = fusion.Vec3;

/// Most targets tracked per step. Extra ones still animate but cannot be hit.
pub const max_targets = 128;

/// Kills closer together than this multiply their points.
const combo_window: f32 = 2.5;
const max_combo: u32 = 5;
/// Destroying every target before any respawns.
const clear_bonus: u64 = 1000;
/// After a clear, every target respawns within this many seconds.
const clear_respawn: f32 = 1.2;
const hit_marker_seconds: f32 = 0.14;
const dying_seconds: f32 = 0.18;
const appear_seconds: f32 = 0.35;
const aim_distance: f32 = 250;

const Session = struct {
    score: u64 = 0,
    shots: u32 = 0,
    hits: u32 = 0,
    kills: u32 = 0,
    combo: u32 = 0,
    combo_timer: f32 = 0,
    best_combo: u32 = 0,
    clears: u32 = 0,
    elapsed: f32 = 0,
    last_clear: f32 = 0,
    /// True from a clear until a target is alive again.
    cleared: bool = false,
    respawn_all: bool = false,
    hit_marker: f32 = 0,
    /// Spark mesh of the first blaster found at start.
    impact_mesh: AssetId = AssetId.zero,
    target_count: usize = 0,

    fn accuracy(self: Session) u32 {
        if (self.shots == 0) return 0;
        return @intFromFloat(@round(@as(f32, @floatFromInt(self.hits)) * 100 / @as(f32, @floatFromInt(self.shots))));
    }
};

// The library stays loaded between play sessions; `start` resets these.
var session: Session = .{};
var prng = std.Random.DefaultPrng.init(0x5eed);

/// 1 right after a projectile hits a target, fading to 0.
pub fn hitMarkerFraction() f32 {
    return session.hit_marker / hit_marker_seconds;
}

/// A target that projectiles can hit this step.
pub const TargetInfo = struct {
    entity: fusion.Entity,
    center: Vec3,
    radius: f32,
    alive: bool,
    /// Damage dealt by this step's projectiles, applied by `targetSystem`.
    damage: f32 = 0,
};

pub const Targets = struct {
    items: [max_targets]TargetInfo = undefined,
    len: usize = 0,

    pub fn slice(self: *Targets) []TargetInfo {
        return self.items[0..self.len];
    }

    fn find(self: *Targets, entity: fusion.Entity) ?*TargetInfo {
        for (self.slice()) |*info| {
            if (info.entity == entity) return info;
        }
        return null;
    }
};

/// Resets the score, adds runtime state to blasters and targets, and warms
/// up the effect meshes so the first shot does not wait on a load.
pub fn start(world: fusion.World) !void {
    session = .{};
    prng = std.Random.DefaultPrng.init(0x5eed);

    var blasters = try world.query(.{ .read = &.{Blaster} });
    var has_blaster = false;
    while (try blasters.each()) |row| {
        const blaster = try row.read(Blaster);
        try world.add(row.entity, BlasterState{});
        if (!has_blaster) session.impact_mesh = blaster.impact_mesh;
        has_blaster = true;
        // Zero-size particles make the renderer load these before the first shot.
        for ([_]AssetId{ blaster.projectile_mesh, blaster.impact_mesh, blaster.muzzle_flash_mesh }) |mesh| {
            try spawnParticle(world, mesh, Vec3.zero, Quat.identity, .{ .remaining = 0.25, .lifetime = 0.25, .size = 0 });
        }
    }

    var phase: f32 = 0;
    var targets = try world.query(.{ .read = &.{ TransformComponent, Target } });
    while (try targets.each()) |row| {
        const transform = try row.read(TransformComponent);
        const target = try row.read(Target);
        try world.add(row.entity, TargetState{
            .origin = transform.position,
            .base_scale = transform.scale,
            .base_rotation = transform.rotation,
            .phase = phase,
            .health = target.health,
        });
        phase += 1.7;
        session.target_count += 1;
    }

    if (has_blaster) {
        world.log(.info, "ARENA: click to capture the mouse (Esc releases it). WASD move, Shift sprint, Space jump, mouse or arrow keys look, left mouse fires.", .{});
        world.log(.info, "{d} targets. Chain kills within {d:.1}s for a combo; destroy them all before any respawn for +{d}.", .{ session.target_count, combo_window, clear_bonus });
    }
}

/// Logs a summary of the session.
pub fn stop(world: fusion.World) !void {
    if (session.shots == 0) return;
    world.log(.info, "Session over: {d} points, {d} kills, {d}/{d} hits ({d}% accuracy), best combo x{d}, {d} clears", .{
        session.score,
        session.kills,
        session.hits,
        session.shots,
        session.accuracy(),
        session.best_combo,
        session.clears,
    });
}

/// Snapshot of the targets projectiles can hit this step.
pub fn gatherTargets(world: fusion.World) !Targets {
    var targets: Targets = .{};
    var query = try world.query(.{ .read = &.{ TransformComponent, Target, TargetState } });
    while (try query.each()) |row| {
        if (targets.len == max_targets) break;
        const transform = try row.read(TransformComponent);
        const target = try row.read(Target);
        const state = try row.read(TargetState);
        targets.items[targets.len] = .{
            .entity = row.entity,
            .center = transform.position,
            .radius = target.radius * maxComponent(state.base_scale),
            .alive = state.alive,
        };
        targets.len += 1;
    }
    return targets;
}

/// Fires while the left mouse button is held and the cursor is locked.
/// Returns the view-model kick for this step (0 to the blaster's recoil).
pub fn blasterSystem(
    world: fusion.World,
    frame: *const fusion.Frame,
    pose: ?first_person.Pose,
    colliders: []const collision.Aabb,
    targets: *Targets,
) !f32 {
    const view = pose orelse return 0;
    var recoil: f32 = 0;

    var query = try world.query(.{ .read = &.{Blaster}, .write = &.{BlasterState} });
    while (try query.each()) |row| {
        const blaster = try row.read(Blaster);
        var state = try row.read(BlasterState);

        state.cooldown -= frame.seconds;
        state.recoil = @max(state.recoil - frame.seconds * 7, 0);
        // The click that locks the cursor is not a shot: wait for the
        // trigger to come up once the cursor is locked.
        if (!frame.cursor_locked) {
            state.armed = false;
        } else if (!frame.isMouseDown(.Left)) {
            state.armed = true;
        }
        if (state.armed and frame.isMouseDown(.Left) and state.cooldown <= 0) {
            try fire(world, blaster, view, colliders, targets);
            state.cooldown += 1.0 / @max(blaster.fire_rate, 0.1);
            state.recoil = 1;
        }
        state.cooldown = @max(state.cooldown, 0);

        recoil = state.recoil * blaster.recoil;
        try row.write(BlasterState, state);
    }
    return recoil;
}

fn fire(
    world: fusion.World,
    blaster: Blaster,
    view: first_person.Pose,
    colliders: []const collision.Aabb,
    targets: *Targets,
) !void {
    session.shots += 1;
    const eye = view.position;
    const muzzle = eye.add(view.rotation.rotateVec3(blaster.muzzle_offset));

    // Point-blank, the barrel can be inside a wall or past a target: hit
    // whatever is between the eye and the muzzle instead of spawning a bolt.
    if (nearestHit(eye, muzzle, blaster.projectile_radius, colliders, targets)) |blocked| {
        try impact(world, lerp(eye, muzzle, blocked.t), blocked, blaster.damage);
        return;
    }

    // Bolts leave the barrel but converge on whatever the crosshair is over.
    const far = eye.add(view.forward.scale(aim_distance));
    const aim_point = if (nearestHit(eye, far, 0, colliders, targets)) |hit| lerp(eye, far, hit.t) else far;
    var direction = collision.safeNormalize(aim_point.sub(muzzle), view.forward);
    if (direction.dot(view.forward) < 0.5) direction = view.forward;

    const radius = blaster.projectile_radius;
    _ = try world.spawn(.{
        TransformComponent{
            .position = muzzle,
            .rotation = lookRotation(direction),
            .scale = Vec3.one.scale(radius * 2),
        },
        MeshRenderComponent{ .mesh = blaster.projectile_mesh },
        ProjectileComponent{
            .velocity = direction.scale(blaster.projectile_speed),
            .remaining = blaster.projectile_lifetime,
            .gravity = blaster.projectile_gravity,
            .radius = radius,
            .damage = blaster.damage,
        },
    });

    const roll = Quat.fromAxisAngle(Vec3.new(0, 0, 1), random().float(f32) * std.math.tau);
    try spawnParticle(world, blaster.muzzle_flash_mesh, muzzle, view.rotation.mul(roll), .{
        .velocity = view.velocity,
        .remaining = 0.05,
        .lifetime = 0.05,
        .size = 0.15 + random().float(f32) * 0.05,
    });
}

/// Moves projectiles, stopping each at the first collider or live target in
/// its path this step (swept, so fast bolts cannot tunnel through).
pub fn projectileSystem(
    world: fusion.World,
    frame: *const fusion.Frame,
    colliders: []const collision.Aabb,
    targets: *Targets,
) !void {
    var query = try world.query(.{ .write = &.{ TransformComponent, ProjectileComponent } });
    while (try query.each()) |row| {
        var projectile = try row.read(ProjectileComponent);
        var transform = try row.read(TransformComponent);

        projectile.velocity.y -= projectile.gravity * frame.seconds;
        const from = transform.position;
        const to = from.add(projectile.velocity.scale(frame.seconds));

        if (nearestHit(from, to, projectile.radius, colliders, targets)) |hit| {
            try impact(world, lerp(from, to, hit.t), hit, projectile.damage);
            try row.despawn();
            continue;
        }

        projectile.remaining -= frame.seconds;
        if (projectile.remaining <= 0) {
            try row.despawn();
            continue;
        }

        transform.position = to;
        if (projectile.gravity != 0) {
            transform.rotation = lookRotation(collision.safeNormalize(projectile.velocity, transform.forward()));
        }
        try row.write(ProjectileComponent, projectile);
        try row.write(TransformComponent, transform);
    }
}

/// Sparks at `point`, plus damage and a hit marker if a target was hit.
/// The damage is applied by `targetSystem` later in the step.
fn impact(world: fusion.World, point: Vec3, hit: SegmentHit, damage: f32) !void {
    if (hit.target) |target| {
        target.damage += damage;
        session.hits += 1;
        session.hit_marker = hit_marker_seconds;
    }
    try spawnSparks(world, session.impact_mesh, point, hit.normal, .impact);
}

/// Applies damage, animates movement, destroy and respawn, and scores kills.
pub fn targetSystem(
    world: fusion.World,
    frame: *const fusion.Frame,
    pose: ?first_person.Pose,
    targets: *Targets,
) !void {
    const dt = frame.seconds;
    session.elapsed += dt;
    session.hit_marker = @max(session.hit_marker - dt, 0);
    session.combo_timer = @max(session.combo_timer - dt, 0);
    const respawn_all = session.respawn_all;
    session.respawn_all = false;

    var total: usize = 0;
    var alive: usize = 0;
    var query = try world.query(.{ .read = &.{Target}, .write = &.{ TransformComponent, TargetState } });
    while (try query.each()) |row| {
        const target = try row.read(Target);
        var state = try row.read(TargetState);
        var transform = try row.read(TransformComponent);
        total += 1;
        state.time += dt;

        if (targets.find(row.entity)) |info| {
            if (state.alive and info.damage > 0) {
                state.health -= info.damage;
                state.hit_pulse = 1;
                if (state.health <= 0) {
                    state.alive = false;
                    state.dying = dying_seconds;
                    state.respawn_timer = target.respawn_delay;
                    try scoreKill(world, target, transform.position);
                }
            }
        }

        if (!state.alive) {
            if (respawn_all) state.respawn_timer = @min(state.respawn_timer, clear_respawn);
            state.respawn_timer -= dt;
            if (state.respawn_timer <= 0) {
                state.alive = true;
                state.health = target.health;
                state.appearing = appear_seconds;
                state.hit_pulse = 0;
            }
        }
        if (state.alive) alive += 1;

        state.hit_pulse = @max(state.hit_pulse - dt * 6, 0);
        state.dying = @max(state.dying - dt, 0);
        state.appearing = @max(state.appearing - dt, 0);

        transform.position = state.origin.add(target.motion.scale(@sin(state.time * target.motion_speed + state.phase)));
        transform.rotation = targetRotation(target, state, transform.position, pose);
        transform.scale = state.base_scale.scale(targetScale(state));

        try row.write(TargetState, state);
        try row.write(TransformComponent, transform);
    }

    if (alive > 0) {
        session.cleared = false;
    } else if (total > 0 and !session.cleared) {
        session.cleared = true;
        session.respawn_all = true;
        session.clears += 1;
        session.score += clear_bonus;
        world.log(.info, "RANGE CLEARED in {d:.1}s! +{d} bonus | score {d}", .{ session.elapsed - session.last_clear, clear_bonus, session.score });
        session.last_clear = session.elapsed;
    }
}

fn scoreKill(world: fusion.World, target: Target, position: Vec3) !void {
    session.kills += 1;
    session.combo = if (session.combo_timer > 0) @min(session.combo + 1, max_combo) else 1;
    session.combo_timer = combo_window;
    session.best_combo = @max(session.best_combo, session.combo);

    const points = @as(u64, target.points) * session.combo;
    session.score += points;
    try spawnSparks(world, session.impact_mesh, position, Vec3.unitY, .burst);

    if (session.combo > 1) {
        world.log(.info, "+{d} (x{d} combo) | score {d} | accuracy {d}%", .{ points, session.combo, session.score, session.accuracy() });
    } else {
        world.log(.info, "+{d} | score {d} | accuracy {d}%", .{ points, session.score, session.accuracy() });
    }
}

fn targetRotation(target: Target, state: TargetState, position: Vec3, pose: ?first_person.Pose) Quat {
    if (target.face_player) {
        if (pose) |view| {
            const to_player = view.position.sub(position);
            if (to_player.x * to_player.x + to_player.z * to_player.z > 1e-6) {
                return Quat.fromAxisAngle(Vec3.unitY, std.math.atan2(to_player.x, to_player.z));
            }
        }
    }
    if (target.spin_speed != 0) {
        return Quat.fromAxisAngle(Vec3.unitY, state.time * target.spin_speed).mul(state.base_rotation);
    }
    return state.base_rotation;
}

/// Size multiplier: pop on hit, swell-and-vanish when destroyed, overshoot
/// on respawn, hidden while waiting to respawn.
pub fn targetScale(state: TargetState) f32 {
    if (!state.alive) {
        if (state.dying <= 0) return 0;
        const k = state.dying / dying_seconds;
        return (1 + 0.5 * (1 - k)) * k;
    }
    var scale = 1 + 0.3 * state.hit_pulse;
    if (state.appearing > 0) scale *= easeOutBack(1 - state.appearing / appear_seconds);
    return scale;
}

fn easeOutBack(t: f32) f32 {
    const c1: f32 = 1.70158;
    const c3 = c1 + 1;
    const u = t - 1;
    return 1 + c3 * u * u * u + c1 * u * u;
}

/// Moves particles and shrinks them over their lifetime.
pub fn particleSystem(world: fusion.World, frame: *const fusion.Frame) !void {
    const dt = frame.seconds;
    var query = try world.query(.{ .write = &.{ TransformComponent, Particle } });
    while (try query.each()) |row| {
        var particle = try row.read(Particle);
        particle.remaining -= dt;
        if (particle.remaining <= 0) {
            try row.despawn();
            continue;
        }

        var transform = try row.read(TransformComponent);
        particle.velocity.y -= particle.gravity * dt;
        particle.velocity = particle.velocity.scale(@max(1 - particle.drag * dt, 0));
        transform.position = transform.position.add(particle.velocity.scale(dt));
        transform.scale = Vec3.one.scale(particle.size * particle.remaining / particle.lifetime);

        try row.write(Particle, particle);
        try row.write(TransformComponent, transform);
    }
}

const Spray = struct {
    count: usize,
    /// How far directions stray from the surface normal.
    spread: f32,
    min_speed: f32,
    max_speed: f32,
    /// Lifetime is 0.25 s plus up to this much.
    extra_life: f32,
    size_scale: f32,

    const impact: Spray = .{ .count = 7, .spread = 0.9, .min_speed = 2, .max_speed = 5, .extra_life = 0.2, .size_scale = 1 };
    const burst: Spray = .{ .count = 18, .spread = 2.5, .min_speed = 2.5, .max_speed = 7, .extra_life = 0.5, .size_scale = 1.6 };
};

fn spawnSparks(world: fusion.World, mesh: AssetId, point: Vec3, normal: Vec3, spray: Spray) !void {
    if (mesh.isZero()) return;
    for (0..spray.count) |_| {
        const direction = collision.safeNormalize(normal.add(randomUnit().scale(spray.spread)), normal);
        const life = 0.25 + random().float(f32) * spray.extra_life;
        const size = (0.04 + random().float(f32) * 0.05) * spray.size_scale;
        try spawnParticle(world, mesh, point.add(normal.scale(0.03)), randomRotation(), .{
            .velocity = direction.scale(spray.min_speed + random().float(f32) * (spray.max_speed - spray.min_speed)),
            .remaining = life,
            .lifetime = life,
            .size = size,
            .gravity = 9,
            .drag = 1.5,
        });
    }
}

fn spawnParticle(world: fusion.World, mesh: AssetId, position: Vec3, rotation: Quat, particle: Particle) !void {
    if (mesh.isZero()) return;
    _ = try world.spawn(.{
        TransformComponent{ .position = position, .rotation = rotation, .scale = Vec3.one.scale(particle.size) },
        MeshRenderComponent{ .mesh = mesh },
        particle,
    });
}

const SegmentHit = struct {
    t: f32,
    normal: Vec3,
    target: ?*TargetInfo = null,
};

/// Nearest collider or live target touched by a sphere of `radius` moving
/// from `from` to `to`. Pass null `targets` to test only colliders.
fn nearestHit(from: Vec3, to: Vec3, radius: f32, colliders: []const collision.Aabb, targets: ?*Targets) ?SegmentHit {
    var best: ?SegmentHit = null;
    for (colliders) |box| {
        if (collision.segmentAabb(from, to, box.expand(radius))) |hit| {
            if (best == null or hit.t < best.?.t) best = .{ .t = hit.t, .normal = hit.normal };
        }
    }
    if (targets) |list| {
        for (list.slice()) |*info| {
            if (!info.alive) continue;
            if (collision.segmentSphere(from, to, info.center, info.radius + radius)) |hit| {
                if (best == null or hit.t < best.?.t) best = .{ .t = hit.t, .normal = hit.normal, .target = info };
            }
        }
    }
    return best;
}

/// Rotation that points -Z (the engine's forward) along `direction`.
pub fn lookRotation(direction: Vec3) Quat {
    const look = first_person.yawPitchFromForward(direction);
    return first_person.orientation(look.yaw, look.pitch);
}

fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
    return a.add(b.sub(a).scale(t));
}

fn maxComponent(v: Vec3) f32 {
    return @max(@abs(v.x), @max(@abs(v.y), @abs(v.z)));
}

fn random() std.Random {
    return prng.random();
}

fn randomUnit() Vec3 {
    while (true) {
        const v = Vec3.new(random().float(f32) * 2 - 1, random().float(f32) * 2 - 1, random().float(f32) * 2 - 1);
        const length2 = v.dot(v);
        if (length2 > 1e-4 and length2 <= 1) return v.scale(1 / @sqrt(length2));
    }
}

fn randomRotation() Quat {
    return Quat.fromAxisAngle(randomUnit(), random().float(f32) * std.math.tau);
}

const testing = std.testing;
const tolerance: f32 = 1e-4;

test "lookRotation points forward along the direction" {
    const direction = Vec3.new(1, 0.5, -2).normalize();
    const forward = lookRotation(direction).rotateVec3(Vec3.new(0, 0, -1));
    try testing.expectApproxEqAbs(direction.x, forward.x, tolerance);
    try testing.expectApproxEqAbs(direction.y, forward.y, tolerance);
    try testing.expectApproxEqAbs(direction.z, forward.z, tolerance);
}

test "nearestHit prefers the closer of a wall and a target" {
    const wall = collision.Aabb.fromCenter(Vec3.new(0, 0, -10), Vec3.new(5, 5, 0.5));
    var targets: Targets = .{};
    targets.items[0] = .{ .entity = @fromBackingInt(@intCast(7)), .center = Vec3.new(0, 0, -5), .radius = 0.5, .alive = true };
    targets.len = 1;

    const hit = nearestHit(Vec3.zero, Vec3.new(0, 0, -20), 0, &.{wall}, &targets).?;
    try testing.expect(hit.target != null);
    try testing.expectApproxEqAbs(@as(f32, 0.225), hit.t, tolerance);

    // Destroyed targets are ignored, so the wall is hit instead.
    targets.items[0].alive = false;
    const wall_hit = nearestHit(Vec3.zero, Vec3.new(0, 0, -20), 0, &.{wall}, &targets).?;
    try testing.expect(wall_hit.target == null);
    try testing.expectApproxEqAbs(@as(f32, 0.475), wall_hit.t, tolerance);
}

test "nearestHit accounts for the projectile radius" {
    const wall = collision.Aabb.fromCenter(Vec3.new(0, 0, -10), Vec3.new(5, 5, 0.5));
    const hit = nearestHit(Vec3.zero, Vec3.new(0, 0, -20), 1, &.{wall}, null).?;
    try testing.expectApproxEqAbs(@as(f32, 0.425), hit.t, tolerance);
}

test "target scale pops on hit, vanishes when destroyed, and overshoots on respawn" {
    try testing.expectApproxEqAbs(@as(f32, 1), targetScale(.{}), tolerance);
    try testing.expect(targetScale(.{ .hit_pulse = 1 }) > 1.2);
    try testing.expectEqual(@as(f32, 0), targetScale(.{ .alive = false }));
    try testing.expect(targetScale(.{ .alive = false, .dying = dying_seconds * 0.5 }) > 0);
    try testing.expect(targetScale(.{ .appearing = appear_seconds * 0.3 }) > 1);
    try testing.expectApproxEqAbs(@as(f32, 0), targetScale(.{ .appearing = appear_seconds }), tolerance);
}

test "session accuracy rounds to a whole percent" {
    try testing.expectEqual(@as(u32, 0), (Session{}).accuracy());
    try testing.expectEqual(@as(u32, 67), (Session{ .shots = 3, .hits = 2 }).accuracy());
}
