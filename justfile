set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# --- config (override on the CLI, e.g. `just port=/dev/cu.usbmodemflipX install snake_game`) ---
fw      := justfile_directory() + "/../flipperzero-firmware"
catalog := justfile_directory() + "/../flipper-application-catalog"
port    := "/dev/cu.usbmodemflip_Wlipurk1"
target  := "6"
origin  := "az0v"
builddir := fw + "/build/f6-firmware-D"

# show recipes
default:
    @just --list

# clone the app catalog if missing
catalog:
    @if [ ! -d "{{catalog}}/applications" ]; then \
        git clone --depth 1 https://github.com/flipperdevices/flipper-application-catalog.git "{{catalog}}"; \
    else echo "catalog present: {{catalog}}"; fi

# list catalog apps (optionally filter by category: `just list Games`)
list category='':
    @python3 {{justfile_directory()}}/scripts/catalog.py list "{{catalog}}" "{{category}}"

# fetch one app's pinned source into the firmware tree's applications_user/
fetch appid:
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(python3 {{justfile_directory()}}/scripts/catalog.py resolve "{{catalog}}" "{{appid}}")"
    cache="/tmp/f6-appkit-cache/$(echo "$ORIGIN@$COMMIT" | tr -c 'A-Za-z0-9' _)"
    if [ ! -f "$cache/.ok" ]; then
        rm -rf "$cache"; mkdir -p "$cache"
        git -C "$cache" init -q
        git -C "$cache" remote add origin "$ORIGIN"
        git -C "$cache" fetch --depth 1 -q origin "$COMMIT" || git -C "$cache" fetch -q origin
        git -C "$cache" -c advice.detachedHead=false checkout -q "$COMMIT"
        touch "$cache/.ok"
    fi
    src="$cache/${SUBDIR}"
    [ -f "$src/application.fam" ] || { echo "no application.fam at $src"; exit 1; }
    dst="{{fw}}/applications_user/{{appid}}"
    rm -rf "$dst"; mkdir -p "$dst"
    rsync -a --exclude .git "$src/" "$dst/"
    echo "fetched {{appid}} ($CATEGORY) -> $dst"

# build one app's fap against the f6 SDK (uses the firmware tree's pinned fbt toolchain)
build appid:
    cd "{{fw}}" && FBT_NO_SYNC=1 ./fbt TARGET_HW={{target}} FIRMWARE_ORIGIN={{origin}} fap_{{appid}}
    @echo "built: {{builddir}}/.extapps/{{appid}}.fap"

# deploy a built fap to the device over USB, into its catalog category folder
deploy appid:
    #!/usr/bin/env bash
    set -euo pipefail
    eval "$(python3 {{justfile_directory()}}/scripts/catalog.py resolve "{{catalog}}" "{{appid}}")"
    fap="{{builddir}}/.extapps/{{appid}}.fap"
    [ -f "$fap" ] || { echo "not built: $fap (run 'just build {{appid}}')"; exit 1; }
    python3 "{{fw}}/scripts/storage.py" -p "{{port}}" mkdir "/ext/apps/$CATEGORY" || true
    python3 "{{fw}}/scripts/storage.py" -p "{{port}}" send "$fap" "/ext/apps/$CATEGORY/{{appid}}.fap"
    echo "deployed {{appid}} -> /ext/apps/$CATEGORY/{{appid}}.fap"

# fetch + build + deploy in one go
install appid: (fetch appid) (build appid) (deploy appid)
    @echo "installed {{appid}}"

# remove a fetched app's source from the firmware tree
clean appid:
    rm -rf "{{fw}}/applications_user/{{appid}}"
    @echo "cleaned {{appid}}"
