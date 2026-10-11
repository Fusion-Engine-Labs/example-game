const sdk = @import("fusion_sdk");
const components = @import("game_components.zig");
const systems = @import("game_systems.zig");

pub const module = sdk.game(
    &.{components.KeyboardMovementComponent},
    systems.keyboardMovementSystem,
);
