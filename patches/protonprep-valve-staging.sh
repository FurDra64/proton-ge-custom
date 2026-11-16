#!/bin/bash

# patch functions
apply_patch() {
    local patch_path="$1"
    # Guard against empty-PASS regressions (git apply exiting 0 in a pushd
    # subdirectory without touching anything): every patch must name at
    # least one target file, and the tree must show it applied afterwards.
    # An unexpected 0-file skip is FAILED (see apply_all_in_dir for dirs).
    local nfiles
    nfiles=$(git apply --numstat "$patch_path" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$nfiles" ] || [ "$nfiles" -eq 0 ]; then
        echo "FAILED patch=$patch_path (targets no files)" >&2
        if [ "${CHECK_MODE:-0}" = "1" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 0
        fi
        return 1
    fi
    if git apply -p1 --whitespace=fix "$patch_path"; then
        if git apply --check -R -p1 "$patch_path" 2>/dev/null; then
            if [ "${CHECK_MODE:-0}" = "1" ]; then
                PASS_COUNT=$((PASS_COUNT + 1))
            fi
            return 0
        fi
        echo "FAILED patch=$patch_path (not applied)" >&2
        if [ "${CHECK_MODE:-0}" = "1" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 0
        fi
        return 1
    fi
    # Non-interactive fallback (</dev/null); GNU fuzz preserved for GE layers.
    if patch -Np1 -s --no-backup-if-mismatch -i "$patch_path" </dev/null; then
        if patch -R -Np1 -s --dry-run -i "$patch_path" </dev/null 2>/dev/null; then
            if [ "${CHECK_MODE:-0}" = "1" ]; then
                PASS_COUNT=$((PASS_COUNT + 1))
            fi
            return 0
        fi
        echo "FAILED patch=$patch_path (not applied)" >&2
        if [ "${CHECK_MODE:-0}" = "1" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 0
        fi
        return 1
    fi
    echo "FAILED patch=$patch_path" >&2
    if [ "${CHECK_MODE:-0}" = "1" ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 0
    fi
    return 1
}

# Directories known to legitimately contain no *.patch files. An empty,
# undeclared directory is an unexpected skip and counts as FAILED.
EMPTY_OK_DIRS=()

apply_all_in_dir() {
    local dir="$1"
    shopt -s nullglob
    local patches=("$dir"/*.patch)
    if [ "${#patches[@]}" -eq 0 ]; then
        local d
        for d in "${EMPTY_OK_DIRS[@]}"; do
            if [ "$dir" = "$d" ]; then
                return 0
            fi
        done
        echo "FAILED dir=$dir (no patches)" >&2
        if [ "${CHECK_MODE:-0}" = "1" ]; then
            FAIL_COUNT=$((FAIL_COUNT + 1))
            return 0
        fi
        return 1
    fi
    local patch
    for patch in "${patches[@]}"; do
        apply_patch "$patch"
    done
}

CHECK_MODE=0
SHADOW=""
PASS_COUNT=0
FAIL_COUNT=0

# --check: export pristine wine HEAD to a shadow sibling directory (so that
# ../patches and ../wine-staging resolve) and run only the WINE sections
# (2-0 through 2-7) against it. Network/build steps are skipped. The real
# tree is never touched; the shadow is always removed via the EXIT trap.
# Known residuals are reported as FAILED, never repaired here.
if [ "${1:-}" = "--check" ]; then
    CHECK_MODE=1
    SHADOW="$(mktemp -d "${PWD}/.wine-check-XXXXXX")"
    trap 'rm -rf "$SHADOW"' EXIT
    git -C wine archive HEAD | tar -x -C "$SHADOW"
    # Make the shadow a git repo with committed base: bare `git apply`
    # silently skips `diff --git` patches in an untracked dir (verified:
    # 766 silent skips), which corrupts --check into cascade failures.
    git -C "$SHADOW" init -q
    git -C "$SHADOW" -c user.email=check@local -c user.name=check add -A
    git -C "$SHADOW" -c user.email=check@local -c user.name=check commit -qm base
    echo "check: running WINE sections (2-0 through 2-7) against $SHADOW"
fi

### (1) PREP SECTION ###

    if [ "$CHECK_MODE" != "1" ]; then

    # Wine-Mono is reset from its pinned release archive rather than a Git submodule.
    bash ./patches/wine-mono/prepare.sh || exit 1

    pushd dxvk
    git reset --hard HEAD
    git clean -xdf
    patch -Np1 < ../patches/dxvk/layered-overlay-dxvk.patch
    # Keep child-rendering backpressure from repeatedly recreating launcher swapchains.
    apply_patch "../patches/dxvk/dxvk-preserve-swapchain-on-acquire-backpressure.patch"
    apply_patch "../patches/dxvk/dxgi-defer-initial-fullscreen-for-probe-swapchains.patch"
    apply_patch "../patches/dxvk/dxgi-follow-d3d12-fullscreen-client-resizes.patch"
    # FFXIV: keep emulated fullscreen when focus moves to another window (#639).
    apply_patch "../patches/dxvk/dxgi-keep-fullscreen-on-focus-loss.patch"
    # Black Desert also needs the matching Wine activation compatibility patch below.
    apply_patch "../patches/dxvk/black-desert-keep-fullscreen-on-focus-loss.patch"
    # Assassin's Creed DX10: preserve fullscreen presentation across Alt+Tab.
    apply_patch "../patches/dxvk/assassins-creed-keep-fullscreen-on-focus-loss.patch"
    # Swapchain colorspace instance-extension support is upstream in DXVK 3c40ca1b.
    # Do not advertise HDR when Wine reports an SDR output, even with DXVK_HDR=1.
    apply_patch "../patches/dxvk/dxgi-respect-output-hdr-state.patch"
    # Query the active output by default instead of requiring an HDR opt-in.
    apply_patch "../patches/dxvk/dxgi-auto-detect-hdr.patch"
    # StarCraft II: avoid GPU hangs with D3D9 constant buffer streaming (#790).
    apply_patch "../patches/dxvk/starcraft2-disable-constant-buffer-streaming.patch"
    popd

    pushd d7vk
    git reset --hard HEAD
    git clean -xdf
    apply_patch "../patches/d7vk/d7vk-allow-avx-with-clang.patch"
    popd

    pushd openvr
    git reset --hard HEAD
    git clean -xdf
    apply_patch "../patches/openvr/openvr-no-msvc-assumption.patch"
    popd

    pushd vkd3d-proton
    git reset --hard HEAD
    git clean -xdf
    echo "VKD3D-PROTON: prevent stalled present waits from deadlocking swapchain teardown"
    echo "VKD3D-PROTON: don't map the parent process image for engine detection (EAC untrusted file, Star Citizen/Hunt)"
    apply_all_in_dir "../patches/vkd3d-proton/"
    popd

    pushd dxvk-nvapi
    git reset --hard HEAD
    git clean -xdf
    popd

    pushd protonfixes
    git reset --hard HEAD
    git clean -xdf
    popd

    pushd wineopenxr
    git checkout .
    git clean -xdf
    echo "WINEOPENXR: patch wineopenxr so it can be built as part of wine"
    apply_all_in_dir "../patches/wineopenxr/"
    popd

    pushd vklayers/low_latency_layer
    git reset --hard HEAD
    git clean -xdf
    echo "LOW_LATENCY_LAYER: use relative library path"
    apply_all_in_dir "../../patches/low_latency_layer"
    popd

### END PREP SECTION ###

    git checkout steam_helper
    git checkout umu_helper

    echo "DISCORD: -DISCORD RPC BRIDGE- patch steam/umu helpers"
    apply_all_in_dir "patches/discordrpc/helpers"

    git checkout -- \
        lsteamclient/Makefile.in \
        lsteamclient/gen_wrapper.py \
        lsteamclient/steam_input_manual.c \
        lsteamclient/steamclient_main.c \
        lsteamclient/steamclient_private.h \
        lsteamclient/unix_private.h \
        lsteamclient/unixlib.cpp \
        lsteamclient/winISteamController.c \
        lsteamclient/winISteamInput.c

    # Regenerated by patch 0010; leave the custom overlay_bridge/ sources intact.
    rm -f -- lsteamclient/steam_overlay_focus.h

    echo "LSTEAMCLIENT: apply Steam Input and initialization fixes"
    apply_all_in_dir "patches/lsteamclient"

    git checkout -- \
        vrclient_x64/json_converter.cpp \
        vrclient_x64/unix_private.h

    echo "VRCLIENT: apply build fixes"
    apply_all_in_dir "patches/vrclient"
    fi

### (2) WINE PATCHING ###

    if [ "$CHECK_MODE" = "1" ]; then
        pushd "$SHADOW" > /dev/null
    else
        pushd wine
        git reset --hard HEAD
        git clean -xdf
    fi

### (2-0) FURDRA64/WINE-OWNED PATCHSET SECTION ###

    # FurDra64/wine keeps a clean tree + patches/ overlay (series.conf order).
    # Apply the wine-owned patchsets first; GE protonprep sections below layer on top.
    echo "WINE: -FURDRA64- applying wine-owned patchsets (scripts/apply-patches.sh)"
    if [ "$CHECK_MODE" = "1" ]; then
        bash scripts/apply-patches.sh || { echo "FAILED scripts/apply-patches.sh" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
    else
        bash scripts/apply-patches.sh || exit 1
    fi

### END FURDRA64/WINE-OWNED PATCHSET SECTION ###

### (2-1) PROBLEMATIC COMMIT REVERT SECTION ###

# Bring back configure files. Staging uses them to regenerate fresh ones
# https://github.com/ValveSoftware/wine/commit/e813ca5771658b00875924ab88d525322e50d39f

    if [ "$CHECK_MODE" != "1" ]; then
        git revert --no-commit e813ca5771658b00875924ab88d525322e50d39f
    fi

### END PROBLEMATIC COMMIT REVERT SECTION ###

### (2-2) EM-11/WINE-WAYLAND PATCH SECTION ###

    # EM-11 5a1ae24b090b on Wine bleeding-edge 981e2f0b9007.
    # Import and exclusion details: wine-hotfixes/wine-wayland/README.md

    echo "WINE: -WINEOPENXR- copy files into wine"
    mkdir -p dlls/wineopenxr
    cp -R ../wineopenxr/* dlls/wineopenxr/

    echo "WINE: -CUSTOM- ETAASH WINE-WAYLAND+ PATCHES"
    apply_all_in_dir "../patches/wine-hotfixes/wine-wayland/"


    # Original work by Erhan Bilgili:
    # https://github.com/nanomatters/wine-wineland/tree/wineland_20260713-reorg
    echo "WINE: -CUSTOM- WINELAND CROSS-PROCESS CHILD RENDERING"
    apply_all_in_dir "../patches/wine-hotfixes/wineland-child-rendering/"

    echo "WINE: -CUSTOM- ETAASH WINE-WAYLAND+ FIXUPS"
    for patch in ../patches/wine-hotfixes/em-fixups/*.patch; do
        case "$patch" in
            */0001-winewayland-add-SNI-tray-icons-and-native-context-me.patch|\
            */0002-winewayland-route-tray-balloons-through-desktop-notifications.patch|\
            */0003-winewayland-position-edge-notification-windows.patch|\
            */0004-win32u-initialize-vulkan-for-wayland-overlay-layer.patch|\
            */0005-explorer-honor-WINE_GRAPHICS_DRIVER.patch|\
            */0006-win32u-bridge-Steam-overlay-through-native-EGL.patch|\
            */0007-win32u-suppress-game-input-while-Steam-overlay-is-active.patch|\
            */0037-server-terminate-system-threads-with-last-user-thread.patch|\
            */0053-win32u-preserve-overlay-cursor-ownership.patch|\
            */0054-winewayland-commit-pointer-constraint-updates.patch|\
            */0056-win32u-preserve-xembed-tray-on-mutter.patch|\
            */0058-win32u-omit-unimplemented-sni-menu-property.patch|\
            */0059-winewayland-release-tray-menu-keyboard-focus.patch|\
            */0061-winewayland-place-tray-menus-above-shell-panels.patch|\
            */0062-winex11-restore-tray-icons-after-host-recreation.patch|\
            */0063-explorer-forward-tray-click-foreground-permission.patch|\
            */0065-win32u-keep-game-windows-out-of-tray-menu-layers.patch|\
            */0074-win32u-advertise-sni-menu-sentinel-on-gnome.patch|\
            */winewayland-render-ddb-cursors-to-32bit-dib.patch) ;;
            *) apply_patch "$patch" ;;
        esac
    done

### END EM-11/WINE-WAYLAND PATCH SECTION ###

### (2-3) WINE STAGING APPLY SECTION ###

    echo "WINE: -STAGING- applying staging patches"

    ../wine-staging/staging/patchinstall.py DESTDIR="." --all --no-autoconf\
    -W server-Signal_Thread \
    -W server-Stored_ACLs \
    -W server-File_Permissions \
    -W kernel32-CopyFileEx \
    -W dbghelp-Debug_Symbols \
    -W version-VerQueryValue \
    -W mf_http_support \
    -W ntdll-Serial_Port_Detection \
    -W server-PeekMessage \
    -W msxml3-FreeThreadedXMLHTTP60 \
    -W ntdll-ForceBottomUpAlloc \
    -W ntdll-NtDevicePath \
    -W user32-rawinput-mouse \
    -W user32-recursive-activation \
    -W d3dx9_36-D3DXStubs \
    -W wined3d-zero-inf-shaders \
    -W ntdll-RtlQueryPackageIdentity \
    -W vkd3d-latest \
    -W loader-KeyboardLayouts \
    -W ntdll-Syscall_Emulation \
    -W ntdll_reg_flush \
    -W ntdll-Hide_Wine_Exports \
    -W kernel32-Debugger \
    -W ntdll-ext4-case-folder \
    -W winex11-Window_Style \
    -W wininet-Cleanup \
    -W wintrust-WTHelperGetProvCertFromChain \
    -W winex11-ime-check-thread-data \
    -W winex11-Fixed-scancodes \
    -W winedevice-Default_Drivers \
    -W Staging

    # Manual sets use GE-rebased copies where their context overlaps our earlier patches.
    # A detailed list of why the above patches are disabled is listed below:

    # server-Signal_Thread - breaks steamclient for some games -- notably DBFZ
    # server-Stored_ACLs - requires ntdll-Junction_Points
    # server-File_Permissions - requires ntdll-Junction_Pointsv
    # kernel32-CopyFileEx - breaks various installers
    # dbghelp-Debug_Symbols - Ubisoft Connect games (3/3 I had installed and could test) will crash inside pe_load_debug_info function with this enabled
    # version-VerQueryValue - just a test and doesn't apply cleanly. not relevant for gaming
    # mf_http_support - disabled in favor of custom ffmpeg backend video playback solution
    # ntdll-Serial_Port_Detection - its mountmgr probe opens every /dev/ttyS*, ttyUSB*, ttyACM* without O_NOCTTY
    #   from winedevice.exe (a session leader without a terminal): the first one becomes its controlling tty and
    #   is hung up when the prefix shuts down, breaking the program that had it open (e.g. a Sinden lightgun's
    #   serial link to its driver: the gun stops working after each game)

    # server-PeekMessage - already applied
    # msxml3-FreeThreadedXMLHTTP60 - already applied
    # ntdll-ForceBottomUpAlloc - already applied
    # ntdll-NtDevicePath - already applied
    # user32-rawinput-mouse - already applied
    # user32-recursive-activation - already applied
    # d3dx9_36-D3DXStubs - already applied
    # wined3d-zero-inf-shaders - already applied
    # ntdll-RtlQueryPackageIdentity - already applied
    # vkd3d-latest - already applied
    # loader-KeyboardLayouts - already applied
    # ntdll-Syscall_Emulation - already applied
    # ntdll_reg_flush - already applied
    # wintrust-WTHelperGetProvCertFromChain - already applied by Wine upstream

    # ntdll-Hide_Wine_Exports - applied manually
    # kernel32-Debugger - applied manually
    # ntdll-ext4-case-folder - applied manually
    # winex11-Window_Style - applied manually
    # wininet-Cleanup - applied manually
    # Staging - applied manually
    # winex11-ime-check-thread-data - applied manually, needed rebase
    # winex11-Fixed-scancodes - applied manually, needed rebase
    # winedevice-Default_Drivers - applied manually, tests rebased onto upstream ntoskrnl changes

    # winex11-WM_WINDOWPOSCHANGING - Causes origin to freeze -- currently also disabled in upstream staging
    # ntdll-Junction_Points - breaks CEG drm -- currently also disabled in upstream staging
    # shell32-Progress_Dialog - relies on kernel32-CopyFileEx -- currently also disabled in upstream staging
    # shell32-ACE_Viewer - adds a UI tab, not needed, relies on kernel32-CopyFileEx -- currently also disabled in upstream staging
    # dinput-joy-mappings - disabled in favor of proton's gamepad patches -- currently also disabled in upstream staging
    # mfplat-streaming-support -- interferes with proton's mfplat -- currently also disabled in upstream staging
    # wined3d-SWVP-shaders -- interferes with proton's wined3d -- currently also disabled in upstream staging
    # wined3d-Indexed_Vertex_Blending -- interferes with proton's wined3d -- currently also disabled in upstream staging






    echo "WINE: -STAGING- wininet-Cleanup manually applied"
    # Skip 0005: it makes HTTP_ADDREQ_FLAG_REPLACE fail for headers not yet
    # present, while Windows 10 adds them. TLOU Part II adds Content-Type and
    # Authorization that way, so its leaderboard requests were sent without
    # them and rejected (403).
    # https://github.com/GloriousEggroll/proton-ge-custom/issues/463
    apply_patch "../wine-staging/patches/wininet-Cleanup/0001-wininet-tests-Add-more-tests-for-cookies.patch"
    apply_patch "../wine-staging/patches/wininet-Cleanup/0002-wininet-tests-Test-auth-credential-reusage-with-host.patch"
    apply_patch "../wine-staging/patches/wininet-Cleanup/0003-wininet-tests-Check-cookie-behaviour-when-overriding.patch"
    apply_patch "../wine-staging/patches/wininet-Cleanup/0004-wininet-Strip-filename-if-no-path-is-set-in-cookie.patch"

    echo "WINE: -STAGING- Staging manually applied"
    apply_all_in_dir "../wine-staging/patches/Staging/"

    echo "WINE: -STAGING- winex11-ime-check-thread-data manually applied"
    apply_all_in_dir "../patches/wine-hotfixes/wine-staging/winex11-ime-check-thread-data/"


    echo "WINE: -STAGING- comctl32_animate_avi cleanup -Werror"
    apply_all_in_dir "../patches/wine-hotfixes/wine-staging/comctl32_animate_avi/"

    echo "WINE: -STAGING- d3drm-starwars cleanup -Werror"
    apply_all_in_dir "../patches/wine-hotfixes/wine-staging/d3drm-starwars/"

    echo "WINE: -STAGING- windowscodecs-TIFF_Support cleanup -Werror"
    apply_all_in_dir "../patches/wine-hotfixes/wine-staging/windowscodecs-TIFF_Support/"

    echo "WINE: -STAGING- mmsystem.dll16-MIDIHDR_Refcount cleanup -Werror"
    apply_all_in_dir "../patches/wine-hotfixes/wine-staging/mmsystem.dll16-MIDIHDR_Refcount/"


### END WINE STAGING APPLY SECTION ###

### (2-4) GAME PATCH SECTION ###






    # multi-process-launcher-x11-fallback.patch is intentionally disabled.
    # Wine-Wayland now renders cross-process launcher windows directly.


    # https://github.com/GloriousEggroll/proton-ge-custom/issues/721

    echo "WINE: -GAME FIXES- make MapleStory launch: avoid NULL deref in CharPrevA/CharPrevExA"
    apply_patch "../patches/game-patches/maplestory-kernelbase-charprev-null.patch"


    # https://github.com/GloriousEggroll/proton-ge-custom/issues/736

    # Original CPU detection diagnosis and fix by LuigoAlma:
    # https://www.reddit.com/r/Amd/comments/dr5f0b/comment/f6q2krp/

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/587
    # https://bugs.winehq.org/show_bug.cgi?id=60296


    # https://github.com/GloriousEggroll/proton-ge-custom/issues/847
    # Original fix by mkrsym1 in dawn-winery/wine-dwproton (ecedc3e2d6d2)

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/847
    # ACE-CORE driver fixes by NelloKudo in dawn-winery/wine-dwproton
    # (4ef68081d5, 6a06ad015f, e7942574f6, 532d18e79a)

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/847
    # ACE-CORE fails DriverEntry unless lsass.exe is running. Backported in
    # CachyOS/wine-cachyos (3b0c6a64ba, b1fbd12dd0); drop with the Wine 12 rebase.
    echo "WINE: -GAME FIXES- add and start an lsass.exe SamSs service stub for ACE anti-cheat"
    apply_patch "../patches/game-patches/ace-lsass-samss-service-stub.patch"

### END GAME PATCH SECTION ###

### (2-5) WINE HOTFIX/BACKPORT SECTION ###


    echo "WINE: -HOTFIX- Initialize the SQM client machine identifier"
    apply_patch "../patches/wine-hotfixes/pending/wineboot-create-sqm-machine-id.patch"




    # Warcraft III 3.0: modern CERT_CHAIN_ENGINE_CONFIG used by ClientSdk login.
    # Upstream Wine fixes for #59531 and the legacy-layout regression #59600.
    apply_patch "../patches/wine-hotfixes/pending/crypt32-wc3-modern-chain-engine-config.patch"
    apply_patch "../patches/wine-hotfixes/pending/crypt32-wc3-trace-chain-engine-config.patch"
    apply_patch "../patches/wine-hotfixes/pending/crypt32-wc3-check-exclusive-flags-size.patch"
    apply_patch "../patches/wine-hotfixes/pending/crypt32-wc3-accept-legacy-chain-engine-config.patch"









    echo "WINE: -HOTFIX- Backport schannel SECBUFFER_MISSING size fix for incomplete TLS records (upstream 9aee0e71, 35b1e7eb)"
    apply_patch "../patches/wine-hotfixes/pending/secur32-schannel-fix-incomplete-message-missing-size.patch"



    echo "WINE: -HOTFIX- Keep Forza background windows unmapped on wlroots"
    apply_patch "../patches/wine-hotfixes/pending/winex11-keep-forza-background-windows-unmapped-on-wlroots.patch"

    echo "WINE: -HOTFIX- Reconcile unsupported minimization on xwayland-satellite"
    apply_patch "../patches/wine-hotfixes/pending/winex11-handle-unsupported-minimization-on-satellite.patch"



    echo "WINE: -HOTFIX- Limit the extra Vulkan swapchain image workaround to DOOM"
    apply_patch "../patches/wine-hotfixes/pending/win32u-limit-extra-swapchain-image-to-doom.patch"




    # https://gitlab.winehq.org/wine/wine/-/commit/f4c5b04148db5fc4e5265beec461d3b7d9f4a789
    echo "WINE: -HOTFIX- Reserve top-down space for large-address-aware WoW64 applications"
    apply_patch "../patches/wine-hotfixes/pending/ntdll-reserve-top-down-space-for-large-address-aware-wow64.patch"

    # The NVIDIA driver maps 4G + 2M at the first free address from 0x200000000 for the Vulkan extensions DLSS needs;
    # bottom-up allocation (ntdll-ForceBottomUpAlloc) can fill that range (DLSS in Star Citizen, #460).


    # Publish process-exit state before pending I/O APCs can take orphaned locks.

    # Richard Burns Rally (RSF) closes a kill-on-close job it's in when quitting,
    # which frees its handle table while wineserver is still using it.

    # https://gitlab.winehq.org/wine/wine/-/commit/a31ec8da9572672e04ae46792a398da942649875
    echo "WINE: -HOTFIX- Prefer native non-Microsoft DLLs using version resources"
    apply_patch "../patches/wine-hotfixes/pending/ntdll-prefer-native-version-resource-heuristics.patch"


### END WINE HOTFIX/BACKPORT SECTION ###

### (2-6) WINE PENDING UPSTREAM SECTION ###

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/531
    # https://gitlab.winehq.org/wine/wine/-/merge_requests/10889 (Aaron Yourk)
    echo "WINE: -BACKPORT- Recreate stale OLE clipboard windows after STA thread exit"
    apply_patch "../patches/wine-hotfixes/pending/ole32-clipboard-stale-handle-1-tests.patch"
    apply_patch "../patches/wine-hotfixes/pending/ole32-clipboard-stale-handle-2-fix.patch"

    # https://github.com/Frogging-Family/wine-tkg-git/commit/ca0daac62037be72ae5dd7bf87c705c989eba2cb

    # llvm-libc: kernel thread ID and no _r_debug warning, neither changes glibc builds

    # https://bugs.winehq.org/show_bug.cgi?id=58476

    echo "WINE: -PENDING- ncrypt: NCryptDecrypt implementation (PSN Login for Ghost of Tsushima)"
    apply_patch "../patches/wine-hotfixes/pending/NCryptDecrypt_implementation.patch"

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/433

    # Import upstream icuu forwarders patches to fix broken GoW2Hollow_Setup.exe for Gears of War 2 Hollow
    echo "WINE: -PENDING-  Import upstream icuu forwarders patches to fix broken GoW2Hollow_Setup.exe for Gears of War 2 Hollow"
    apply_patch "../patches/wine-hotfixes/pending/icuuc-icuin-forwarder-dlls.patch"


    # Separate OpenXR steam reliance
    # https://github.com/GloriousEggroll/proton-ge-custom/issues/214


### END WINE PENDING UPSTREAM SECTION ###


### (2-7) PROTON-GE ADDITIONAL CUSTOM PATCHES ###




    echo "WINE: -Nvidia Reflex- Support VK_NV_low_latency2"
    apply_patch "../patches/proton/83-nv_low_latency_wine.patch"



    # https://steamcommunity.com/app/2074920/discussions/0/604168604057160448/


    # https://github.com/GloriousEggroll/proton-ge-custom/pull/759

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/873


    echo "WINE: -HOTFIX- Implement GE-Proton ffmpeg + winedmo only video playback rework patches"
    apply_all_in_dir "../patches/ge-video-rework/"

    # https://github.com/xzn/proton-ds5-haptic
    # Includes default VitaPad-to-DS4 translation (issue #691).
    echo "WINE: -HOTFIX- Add proton DS5 patches"
    for patch in ../patches/proton-ds5-haptic/*.patch; do
        case "$patch" in
            */0001-mmdevapi-setupapi-HACK-Set-MMDevices-properties-in-s.patch|\
            */0002-setupapi-Set-DeviceContainers-registry-values-when-c.patch|\
            */0004-xaudio2-faudio-Implement-taking-device-ids-to-create.patch|\
            */0005-setupapi-SetupDiGetDeviceRegistryProperty-now-return.patch|\
            */0006-mmdevapi-Add-PROTON_MMDEV_FAKE_EXCLUSIVE-envvar-for-.patch|\
            */0007-hid-mmdevapi-full-name-for-DualSense-Wireless-Contro.patch|\
            */0008-faudio-xaudio2-Partially-rewrite-asserts-to-error-ha.patch|\
            */0009-mmdevapi-faudio-xaudio2-Reorganize-create-thread-for.patch|\
            */0010-winepulse-mmdevapi-Add-support-for-hotplugged-audio-.patch|\
            */0011-mmdevapi-Call-registered-IMMNotificationClients-when.patch|\
            */0012-winepulse-mmdevapi-avoid-blocking-delta-hotplug-path.patch|\
            */0013-winepulse-route-dualsense-usb-haptics-to-raw-node.patch|\
            */0014-winebus-prefer-hidraw-for-dualsense-hotplug.patch|\
            */0015-winepulse-refresh-audio-endpoint-deltas-for-ds5-hotplug.patch|\
            */0016-winepulse-refresh-ds5-hotplug-only-on-audio-events.patch|\
            */0017-mmdevapi-notify-device-added-when-hotplugged-endpoint.patch|\
            */0018-winebus-remove-hidraw-device-on-fatal-read-error.patch|\
            */0019-mmdevapi-do-not-preload-persisted-dualsense-audio-endpoints.patch|\
            */0021-mmdevapi-keep-audio-hotplug-worker-on-current-flow.patch|\
            */0022-winepulse-bound-format-probes-during-ds5-hotplug.patch|\
            */0023-winepulse-keep-ds5-mono-hotplug-deltas-pending.patch|\
            */0024-winepulse-keep-audio-hotplug-worker-alive-before-mainloop.patch|\
            */0026-mmdevapi-avoid-dualsense-mono-endpoint-readd-churn.patch|\
            */0033-mmdevapi-cap-overlong-endpoint-property-names.patch|\
            */0036-winebus-ignore-duplicate-udev-devnodes.patch|\
            */0040-winepulse-require-real-dualsense-speaker-streams.patch|\
            */0054-winepulse-process-dualsense-render-before-capture.patch|\
            */0055-winepulse-defer-dualsense-capture-until-render.patch|\
            */0056-winepulse-dont-starve-current-hotplug-flow.patch|\
            */0057-mmdevapi-wait-for-pending-dualsense-render-hotplug.patch|\
            */0106-winmm-compact-successfully-enumerated-mmdevices.patch|\
            */0107-winebus-optionally-map-sony-hidraw-devices-to-xinput.patch|\
            */0108-xinput-map-native-sony-hid-reports-correctly.patch|\
            */0127-xinput-identify-sony-fallback-as-xbox-controller.patch|\
            */0130-mmdevapi-preserve-fake-exclusive-event-timing.patch|\
            */0131-winepulse-route-s16-dualsense-haptic-streams.patch|\
            */0132-winebus-initialize-dualsense-speaker-for-raw-haptics.patch|\
            */0133-winebus-preserve-dualsense-speaker-route.patch|\
            */0136-xaudio2-trace-controller-audio-routing.patch|\
            */0140-mmdevapi-enable-death-stranding-controller-effects.patch|\
            */0141-mmdevapi-gate-death-stranding-controller-effects.patch|\
            */0143-xaudio2-trace-controller-source-buffer-peaks.patch|\
            */0149-winebus-send-separate-dualsense-speaker-route.patch|\
            */0163-winepulse-route-direct-profile-through-pipewire.patch|\
            */0177-winebus-prefer-hidraw-for-dualshock4.patch|\
            */0193-winepulse-prefer-public-quad-sinks-for-sony-split-audio.patch|\
            */0196-user32-refresh-diablo-iv-startup-dualsense.patch|\
            */0198-dinput-identify-forced-sony-xinput-companion-as-xbox.patch|\
            */0207-mmdevapi-preserve-shared-sony-endpoint-properties-on-startup.patch) ;;
            *) apply_patch "$patch" ;;
        esac
    done

    echo "WINE: expose mapped Switch Pro controllers as Xbox when Steam Input is disabled"
    apply_patch "../patches/wine-hotfixes/pending/winebus-switch-pro-xinput-identity.patch"

    echo "WINE: expose native DualSense Edge as DualSense for Diablo IV"
    apply_patch "../patches/wine-hotfixes/pending/winebus-diablo-iv-dualsense-edge-identity.patch"

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/837
    echo "WINE: -GAME FIXES- win32u: release swapchain images presented to hidden windows instead of blocking the host present (RuneScape Vulkan on winewayland)"
    apply_patch "../patches/wine-hotfixes/pending/win32u-release-images-presented-to-hidden-windows.patch"

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/837

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/852
    echo "WINE: -GAME FIXES- winewayland: advertise the OpenVR/OpenXR Vulkan device pseudo-extensions like winex11 (DXVK/vkd3d device creation fails on Wayland with an OpenXR runtime installed)"
    apply_patch "../patches/wine-hotfixes/pending/winewayland-advertise-openvr-openxr-device-extensions.patch"

    # https://github.com/GloriousEggroll/proton-ge-custom/issues/881

    # Bluetooth LE GATT and WinRT BLE (Zwift, Rouvy trainers). winebth.sys stays disabled
    # unless PROTON_ENABLE_WINEBTH=1. https://github.com/GloriousEggroll/proton-ge-custom/issues/814
    # https://github.com/evanjt/wine
    echo "WINE: -HOTFIX- Add Bluetooth LE GATT and WinRT BLE support"
    apply_all_in_dir "../patches/wine-hotfixes/bluetooth-le/"

    if [ "$CHECK_MODE" != "1" ]; then
        echo "WINE: RUN AUTOCONF TOOLS/MAKE_REQUESTS"
        autoreconf -f
        ./tools/make_requests
    fi

    popd



### END PROTON-GE ADDITIONAL CUSTOM PATCHES ###
### END WINE PATCHING ###

    if [ "$CHECK_MODE" = "1" ]; then
        if [ "$FAIL_COUNT" -gt 0 ]; then
            echo "check FAILED: $FAIL_COUNT failed, $PASS_COUNT passed" >&2
            exit 1
        fi
        echo "check passed"
    fi
