const fusion = @import("fusion_runtime");
const game = @import("game.zig");

export fn fusion_get_game() *const fusion.game_module.GameModule {
    return &game.module;
}

test {
    _ = @import("game_systems.zig");
}
