# wsdr-studio tasks. Every tool comes from nix (works on macOS and Linux); `just` lists the recipes.

pkgs := "cmake pkg-config libusb1 fftwFloat nlohmann_json boost nodejs pkgsCross.mipsel-linux-gnu.buildPackages.binutils-unwrapped"
nix := "nix-shell -p " + pkgs + " --run"
mips := "mipsel-unknown-linux-gnu"
port := "8073"

default:
    @just --list

# Fetch the pinned wifi-sdr and devourer submodules
submodules:
    git submodule update --init external/wifi-sdr
    git -C external/wifi-sdr submodule update --init external/devourer

# Configure and build the backend (wsdr-studiod) and test_core
backend:
    {{nix}} 'cmake -S . -B build -DMIPS_AS=$(command -v {{mips}}-as) -DMIPS_LD=$(command -v {{mips}}-ld) -DMIPS_OBJCOPY=$(command -v {{mips}}-objcopy) && cmake --build build -j'

# Build the web UI into web/dist
web:
    {{nix}} 'cd web && ([ -d node_modules ] || npm ci) && npm run build'

# Build everything
build: backend web

# Build only what is missing (`just build` rebuilds after changes)
[private]
ensure:
    @[ -x build/wsdr-studiod ] || just backend
    @[ -f web/dist/index.html ] || just web

# Open the app: the Electron window, which starts the backend itself
app: ensure
    {{nix}} 'cd desktop && ([ -d node_modules ] || npm ci) && npm start'

# Backend only, for scripts and `just dev` (a plain browser tab cannot connect: the page needs the app's token)
serve: ensure
    build/wsdr-studiod --port {{port}} --web web/dist

# Run the web UI dev server (hot reload) against a running `just serve`
dev:
    {{nix}} 'cd web && npm run dev'

# Run the backend and web unit tests
test: build
    build/test_core
    {{nix}} 'cd web && npm test'

# Package build-macapp/wsdr-studio.app (macOS)
package: build
    {{nix}} 'cd desktop && ([ -d node_modules/electron/dist ] || npm ci)'
    bash scripts/build-macapp.sh

# Remove build output
clean:
    rm -rf build build-macapp web/dist
