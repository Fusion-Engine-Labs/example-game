const sdk = @import("fusion_sdk");
const components = @import("game_components.zig");
const systems = @import("game_systems.zig");

const game_components = [_]type{
    components.KeyboardMovementComponent,
    components.ProjectileLauncherComponent,
    components.ProjectileComponent,
    components.FirstPersonController,
    components.FirstPersonState,
    components.BoxCollider,
    components.Blaster,
    components.BlasterState,
    components.ViewModel,
    components.Target,
    components.TargetState,
    components.Particle,
};

pub const module = sdk.game(.{
    .components = &game_components,
    .start = systems.start,
    .update = systems.update,
    .stop = systems.stop,
});
