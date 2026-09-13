const fusion = @import("fusion_runtime");
const std = @import("std");

const components = @import("game_components.zig");
const systems = @import("game_systems.zig");

fn registerComponents(world: *fusion.World) bool {
    fusion.World.registerGameComponenets(
        &world.world,
        world.schemas,
        &.{components.KeyboardMovementComponent},
    ) catch |err| {
        std.debug.print("sandbox component registration failed: {s}\n", .{
            @errorName(err),
        });
        return false;
    };
    return true;
}

fn fixedUpdate(world: *fusion.EcsWorld, commands: *fusion.CommandBuffer) bool {
    systems.keyboardMovementSystem(world, commands) catch |err| {
        std.debug.print("sandbox fixed update failed: {s}\n", .{@errorName(err)});
        return false;
    };
    return true;
}

pub const module: fusion.game_module.GameModule = .{
    .register_components = registerComponents,
    .fixed_update = fixedUpdate,
};
