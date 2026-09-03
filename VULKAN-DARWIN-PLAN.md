# Architectural Plan: Enabling Vulkan (MoltenVK) and libplacebo Video Output on macOS (Darwin / Apple Silicon)

## 1. Executive Summary & Verdict

**Verdict:** **NOT-BUILDABLE** in the current checkout.

VLC 4.0.0-dev (`MacLC`) cannot build or run the Vulkan-backed `libplacebo` video output module (`placebo_vk`) on Darwin without introducing new contrib packages and modifying existing contrib rules. 

While the host macOS system may have Vulkan and MoltenVK installed externally (e.g. via Homebrew at `/opt/homebrew`), the VLC build system relies on an isolated contrib dependency ecosystem. In this repository:
1. **MoltenVK is completely absent** from `contrib/src/`. No package, build recipe, or tarball exists for MoltenVK.
2. **libplacebo on Darwin is explicitly built without Vulkan** (`contrib/src/libplacebo/rules.mak:26-31`).
3. **vulkan-loader is restricted to Windows desktop** (`contrib/src/vulkan-loader/rules.mak:8-10`).
4. **Vulkan is disabled by default in macOS build scripts** (`hdr-handoff/HANDOFF-HDR-MACOS.md:404`).
5. **No Darwin Vulkan platform module exists** in `modules/video_output/vulkan/`.

In accordance with **STEP 0(c)** of the task specification ("If Vulkan support cannot be enabled in this tree at all without adding a contrib package, STOP CODING and report that in your output with the exact evidence. In that case, deliver only: (i) a precise written plan in a new file at the repository root named VULKAN-DARWIN-PLAN.md, and (ii) nothing else"), this document details the complete, actionable roadmap required to make Vulkan and MoltenVK functional on macOS.

---

## 2. Audit Evidence (Static Code Analysis)

The following lines in the checkout prove that Vulkan support cannot compile or run on Darwin as the tree currently stands:

1. **`contrib/src/libplacebo/rules.mak:26-31`**:
   ```makefile
   # We don't want vulkan on darwin for now
   ifndef HAVE_DARWIN_OS
   ifndef HAVE_EMSCRIPTEN
   DEPS_libplacebo += vulkan-loader $(DEPS_vulkan-loader) vulkan-headers $(DEPS_vulkan-headers)
   endif
   endif
   ```
   *Evidence:* `libplacebo` explicitly excludes `vulkan-loader` and `vulkan-headers` when compiling for Darwin (`HAVE_DARWIN_OS`). When libplacebo is built without Vulkan headers/loader, `libplacebo.pc` defines `pl_has_vulkan=0`.

2. **`configure.ac:3453-3462`**:
   ```m4
   AS_IF([test "$enable_vulkan" != "no"], [
     AC_MSG_CHECKING([libplacebo is compiled with vulkan support])
     PLACEBO_HAS_VULKAN="$(${PKG_CONFIG} libplacebo --variable pl_has_vulkan)"
     AS_IF([test "${PLACEBO_HAS_VULKAN}" = "1"], [
       AC_MSG_RESULT([yes])
       VLC_ADD_PLUGIN([placebo_vk])
     ],[
       AC_MSG_RESULT([no])
     ])
   ])
   ```
   *Evidence:* The Vulkan backend plugin `placebo_vk` is strictly gated on `PLACEBO_HAS_VULKAN == 1`. Because contrib libplacebo is built with Vulkan disabled, `placebo_vk` is omitted during configure.

3. **`contrib/src/vulkan-loader/rules.mak:8-10`**:
   ```makefile
   # On WIN32 platform, we don't know where to find the loader
   # so always build it for the Vulkan module.
   ifdef HAVE_WIN32_DESKTOP
   PKGS += vulkan-loader
   endif
   ```
   *Evidence:* The Vulkan loader is only added to `PKGS` for Windows desktop builds. Darwin targets do not build `vulkan-loader` in contrib.

4. **Absence of MoltenVK in Contrib (`contrib/src/`)**:
   *Evidence:* Apple platforms do not ship a native Vulkan ICD or loader in the macOS SDK. Running Vulkan on macOS requires MoltenVK (translating Vulkan API calls to Metal). There is no directory `contrib/src/moltenvk/`, no rules file, and no tarball hashes in `contrib/src/`.

5. **`configure.ac:3553-3562`**:
   ```m4
   AS_IF([test "$enable_vulkan" != "no"], [
     PKG_CHECK_MODULES([VULKAN], [vulkan >= 1.0.26], [
     ], [
       AS_IF([test -n "${enable_vulkan}"], [
         AC_MSG_ERROR([${VULKAN_PKG_ERRORS}.])
       ])
       enable_vulkan="no"
     ])
   ])
   AM_CONDITIONAL(HAVE_VULKAN, [test "$enable_vulkan" != "no"])
   ```
   *Evidence:* Vulkan detection relies on `pkg-config` discovering `vulkan.pc`. Because contrib does not install `vulkan.pc` on Darwin, `enable_vulkan` evaluates to `no`.

6. **`modules/video_output/vulkan/Makefile.am:18-26`**:
   ```makefile
   if HAVE_VULKAN
   if HAVE_WIN32_DESKTOP
   vout_PLUGINS += libvk_win32_plugin.la
   endif

   if HAVE_ANDROID
   vout_PLUGINS += libvk_android_plugin.la
   endif
   endif
   ```
   *Evidence:* Only Win32 and Android platform modules exist. There is no Darwin/macOS platform module declared.

7. **`hdr-handoff/HANDOFF-HDR-MACOS.md:404`**:
   ```bash
   ./configure --enable-debug --enable-videotoolbox --enable-av1 --enable-dav1d --disable-vulkan --prefix=$(pwd)/install_dir
   ```
   *Evidence:* The existing repository documentation and handoff instructions explicitly build with `--disable-vulkan` on macOS.

---

## 3. Required Contrib Infrastructure

To support Vulkan on Darwin, the contrib system must provide:
1. **MoltenVK** (translating Vulkan calls to Metal).
2. **Vulkan-Headers** (installed on Darwin).
3. **Vulkan-Loader** (or direct linkage to `libMoltenVK`).
4. **libplacebo built with Vulkan support**.

### Step 3.1: Add MoltenVK Contrib Package
Create `contrib/src/moltenvk/rules.mak`:
- Fetch release tarball from `https://github.com/KhronosGroup/MoltenVK/archive/v$(MOLTENVK_VERSION).tar.gz`.
- Target: build `libMoltenVK.dylib` or static `libMoltenVK.a` using CMake or `xcodebuild` targeting macOS on `arm64`.
- Install headers (`MoltenVK/vk_mvk_moltenvk.h`) and libraries into `$(PREFIX)/include` and `$(PREFIX)/lib`.
- Generate and install `moltenvk.pc` and `vulkan.pc` so `pkg-config` detects Vulkan support on Darwin.

### Step 3.2: Enable `vulkan-loader` on Darwin in Contrib
Modify `contrib/src/vulkan-loader/rules.mak`:
- Add `HAVE_DARWIN_OS` to `PKGS += vulkan-loader`:
  ```makefile
  ifeq ($(filter 1,$(HAVE_WIN32_DESKTOP) $(HAVE_DARWIN_OS)),1)
  PKGS += vulkan-loader
  endif
  ```
- Configure loader with `-DENABLE_WERROR=OFF -DBUILD_TESTS=OFF -DVULKAN_HEADERS_INSTALL_DIR=$(PREFIX)`.
- On macOS, install MoltenVK's ICD definition (`MoltenVK_icd.json`) into `$(PREFIX)/share/vulkan/icd.d/` so the Vulkan loader can discover MoltenVK at runtime.

### Step 3.3: Re-enable Vulkan in `contrib/src/libplacebo/rules.mak`
In `contrib/src/libplacebo/rules.mak`:
- Remove lines 26–31 that suppress Vulkan dependencies on Darwin:
  ```makefile
  # Replace:
  # ifndef HAVE_DARWIN_OS
  # ifndef HAVE_EMSCRIPTEN
  # DEPS_libplacebo += vulkan-loader $(DEPS_vulkan-loader) vulkan-headers $(DEPS_vulkan-headers)
  # endif
  # endif

  # With:
  ifndef HAVE_EMSCRIPTEN
  DEPS_libplacebo += vulkan-loader $(DEPS_vulkan-loader) vulkan-headers $(DEPS_vulkan-headers)
  endif
  ```
- In `PLACEBOCONF`, enable Vulkan (`-Dvulkan=enabled`).
- Ensure `libplacebo.pc` outputs `pl_has_vulkan=1`.

---

## 4. Darwin Vulkan Platform Module Specification

Once the contrib layer is in place, the Darwin Vulkan platform module (`modules/video_output/vulkan/platform_macos.m`) must be created.

### 4.1 Interface Contract
Following `modules/video_output/vulkan/platform.h`:
- Struct operations:
  ```c
  static const struct vlc_vk_platform_operations platform_ops = {
      .close = ClosePlatform,
      .create_surface = CreateSurface,
  };
  ```
- Module activation:
  - Check `vk->window->type == VLC_WINDOW_TYPE_NSOBJECT`.
  - Set `vk->platform_ext = VK_EXT_METAL_SURFACE_EXTENSION_NAME;` ("VK_EXT_metal_surface").
  - Set `vk->ops = &platform_ops;`.
  - Capability: `"vulkan platform"`, priority `50`.
  - Shortcut: `"vk_macos"`.

### 4.2 Layer & View Attachment (Main Thread Concurrency)
All AppKit and CoreAnimation UI modifications must execute on the macOS main thread:
1. Extract the container view from `vk->window->handle.nsobject` (`id container = (__bridge id)vk->window->handle.nsobject;`).
2. Dispatch synchronously to `dispatch_get_main_queue()`:
   - Instantiate a `CAMetalLayer` (`[CAMetalLayer layer]`).
   - Enable layer hosting on the container: `[container setWantsLayer:YES]`.
   - Add the metal layer to the container's layer hierarchy: `[container.layer addSublayer:metalLayer]`.
   - Bind layer frame to container bounds (`metalLayer.frame = container.bounds;`).
   - Set autoresizing masks (`kCALayerWidthSizable | kCALayerHeightSizable`).
   - Synchronize contentsScale with the active screen's backing scale factor (`metalLayer.contentsScale = screen.backingScaleFactor;`).

### 4.3 HDR & Color Space Configuration
To achieve parity with `modules/video_output/caopengllayer.m`:
1. **Extended Dynamic Range:**
   ```objc
   if (@available(macOS 10.15, *)) {
       metalLayer.wantsExtendedDynamicRangeContent = YES;
       CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
       if (cs) {
           metalLayer.colorspace = cs;
           CGColorSpaceRelease(cs);
       }
   }
   ```
2. **Dynamic Range Headroom & Tone Mapping (macOS 14.0+ & 15.0+):**
   ```objc
   if (@available(macOS 14.0, *)) {
       metalLayer.preferredDynamicRange = CADynamicRangeHigh;
       metalLayer.contentsHeadroom = screen.maximumExtendedDynamicRangeColorComponentValue;
   }
   if (@available(macOS 15.0, *)) {
       metalLayer.toneMapMode = CAToneMapModeIfSupported;
   }
   ```

### 4.4 Surface Creation via `VK_EXT_metal_surface`
In `CreateSurface`:
1. Obtain `vkCreateMetalSurfaceEXT` via `inst->get_proc_address`:
   ```c
   PFN_vkCreateMetalSurfaceEXT CreateMetalSurfaceEXT = (PFN_vkCreateMetalSurfaceEXT)
       inst->get_proc_address(inst->instance, "vkCreateMetalSurfaceEXT");
   if (!CreateMetalSurfaceEXT) {
       msg_Err(vk, "vkCreateMetalSurfaceEXT not available");
       return VLC_EGENERIC;
   }
   ```
2. Populate `VkMetalSurfaceCreateInfoEXT`:
   ```c
   VkMetalSurfaceCreateInfoEXT minfo = {
       .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT,
       .pNext = NULL,
       .flags = 0,
       .pLayer = (__bridge void *)sys->metal_layer,
   };
   ```
3. Call `CreateMetalSurfaceEXT(inst->instance, &minfo, NULL, surface_out)`.

### 4.5 MoltenVK Portability Enumeration Flag
MoltenVK 1.2+ is a non-conformant portability implementation and requires the instance flag:
`VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR`
and extension `VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME`.
In `modules/video_output/libplacebo/instance_vulkan.c:62-70`, `pl_vk_inst_create` must pass these flags when initializing on Darwin so that MoltenVK physical devices can be enumerated.

---

## 5. Build System Registrations

### 5.1 `modules/video_output/vulkan/Makefile.am`
Add Darwin platform build rules:
```makefile
libvk_macos_plugin_la_SOURCES = $(VULKAN_COMMONSOURCES) \
				video_output/vulkan/platform_macos.m
libvk_macos_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) $(VULKAN_CFLAGS) \
				  -fobjc-arc -DPLATFORM_NAME=MacOS
libvk_macos_plugin_la_LDFLAGS = $(AM_LDFLAGS) -rpath '$(voutdir)'
libvk_macos_plugin_la_LIBADD = $(VULKAN_LIBS) -Wl,-framework,Cocoa,-framework,QuartzCore,-framework,Metal

if HAVE_VULKAN
if HAVE_OSX
vout_PLUGINS += libvk_macos_plugin.la
endif
endif
```

### 5.2 Meson Build System (`modules/video_output/meson.build`)
Register Darwin platform module in `modules/video_output/meson.build` or a new `modules/video_output/vulkan/meson.build`:
```meson
if host_system == 'darwin' and vulkan_dep.found()
    vlc_modules += {
        'name' : 'vk_macos',
        'sources' : files('vulkan/platform.c', 'vulkan/platform_macos.m'),
        'objc_args' : ['-fobjc-arc'],
        'dependencies' : [
            vulkan_dep,
            frameworks['Cocoa'],
            frameworks['QuartzCore'],
            frameworks['Metal'],
        ],
    }
endif
```

---

## 6. Video Output Election Priority Adjustment

In `modules/video_output/libplacebo/display.c`:
- Current line 653:
  ```c
  set_callback_display(Open, 0)
  ```
- Target update:
  ```c
  set_callback_display(Open, 200)
  ```
- **Rationale:**
  - `VLCSampleBufferDisplay.m:1835` has priority **600** (default primary vout on macOS).
  - `caopengllayer.m:1127` has priority **300** (fallback OpenGL vout).
  - Priority **200** places `libplacebo` as a viable, electable output below `caopengllayer` and `samplebufferdisplay`, selectable explicitly via `--vout=placebo` without hijacking default playback.

---

## 7. Implementation Checklist

1. [ ] Create `contrib/src/moltenvk/rules.mak` and download target for MoltenVK.
2. [ ] Update `contrib/src/vulkan-loader/rules.mak` to build on Darwin.
3. [ ] Update `contrib/src/libplacebo/rules.mak` to depend on `vulkan-loader` and `vulkan-headers` on Darwin.
4. [ ] Build contrib on Apple Silicon (`make -C contrib src-macos-arm64`).
5. [ ] Implement `modules/video_output/vulkan/platform_macos.m`.
6. [ ] Register `libvk_macos_plugin` in `modules/video_output/vulkan/Makefile.am` and `modules/video_output/meson.build`.
7. [ ] Update `modules/video_output/libplacebo/display.c:653` priority from 0 to 200.
8. [ ] Verify compilation and test Vulkan surface creation with HDR playback.
