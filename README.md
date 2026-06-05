# f6-appkit

Fetch, build and deploy [Flipper app-catalog](https://github.com/flipperdevices/flipper-application-catalog)
apps for the f6 backport firmware. The official Apps hub won't serve faps for our custom
`az0v`/api-87.1 fork, so this builds them from source against our own SDK and side-loads
them over USB.

## Why

A fap only runs if it was built against the exact firmware SDK it'll load on. Our f6 build
is a custom fork, so any new catalog app has to be compiled against *this* SDK: the firmware
tree's `./fbt`, gcc 12.3, with the f6-to-f7 app-target patch baked in. Then pushed to the
device by hand.

The flake handles the toolchain part. It grabs fbt's exact gcc-arm-none-eabi 12.3 build
(the one that also bundles python, scons and openocd, version pinned as `toolchainVersion`
in `flake.nix`) from `update.flipperzero.one`, drops it in the nix store and points
`FBT_TOOLCHAIN_PATH` at it. So `./fbt` finds its toolchain locally and never reaches for the
network. When the firmware fork bumps `scripts/toolchain/fbtenv.sh`, bump `toolchainVersion`
and refresh the four hashes.

## Use

```sh
nix develop               # just, python(+pyserial), git, dfu-util, rsync, and the pinned toolchain
just                      # list recipes
just catalog              # clone the app catalog (once)
just list Games           # browse a category
just install snake_game   # fetch, build and deploy one app
```

Each step on its own: `just fetch <id>`, `just build <id>`, `just deploy <id>`, `just clean <id>`.

Override config inline, say a different device port or firmware path:

```sh
just port=/dev/cu.usbmodemflipX install acr122_emulator
just fw=/path/to/flipperzero-firmware build pomodoro
```

## How it works

`fetch` reads the app's `manifest.yml`, clones its pinned commit and copies the app (from
its `subdir`) into `<fw>/applications_user/<id>/`.

`build` runs `./fbt TARGET_HW=6 FIRMWARE_ORIGIN=az0v fap_<id>` in the firmware tree.

`deploy` sends the `.fap` to `/ext/apps/<Category>/` on the device with `storage.py`.

## Defaults (override on the CLI)

| var | default |
|---|---|
| `fw` | `../flipperzero-firmware` |
| `catalog` | `../flipper-application-catalog` |
| `port` | `/dev/cu.usbmodemflip_Wlipurk1` |
| `target` | `6` |
| `origin` | `az0v` |

Apps gated to `targets=["f7"]` build fine, since the f6 target satisfies f7 (see the
firmware fork's `appmanifest.py` patch). BLE and secure-enclave crypto work too now that
the fork has those sorted, so apps leaning on them run fine on this unit.
