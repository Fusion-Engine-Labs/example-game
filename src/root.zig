const sdk = @import("fusion_sdk");
const game = @import("game.zig");

comptime {
    sdk.exportGame(&game.module);
}

test {
    _ = @import("game_systems.zig");
    _ = @import("collision.zig");
    _ = @import("first_person.zig");
    _ = @import("combat.zig");
    _ = @import("view_model.zig");
}
