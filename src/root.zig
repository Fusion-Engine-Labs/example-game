const sdk = @import("fusion_sdk");
const game = @import("game.zig");

comptime {
    sdk.exportGame(&game.module);
}

test {
    _ = @import("game_systems.zig");
}
