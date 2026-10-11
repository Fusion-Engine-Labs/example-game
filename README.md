# Sandbox game

Gameplay builds as a native library using `fusion-sdk`. Built-in component
schemas/types come from the SDK; `game_components.zig` declares only game types.
The editor has no build dependency on this project.

From this directory, build the game in Debug:

```sh
zig build -Doptimize=Debug
zig build test -Doptimize=Debug
```
