# Libplacebo-based video outputs

libplacebo_dep = dependency('libplacebo',
                            version: '>= 2.72',
                            required: get_option('libplacebo'))

if not libplacebo_dep.found()
    libplacebo_utils = disabler()
    subdir_done()
endif
libplacebo_utils = static_library('vlc_libplacebo_utils',
                                files('utils.c'),
                                dependencies: [libplacebo_dep],
                                include_directories: [vlc_include_dirs])

placebo_sources = files('instance.c', 'display.c')
placebo_deps = [libplacebo_dep]
placebo_objc_args = []

if host_system == 'darwin'
    placebo_sources += files('darwin_icc.m')
    placebo_deps += [
        frameworks['Cocoa'],
        frameworks['CoreGraphics'],
        frameworks['CoreFoundation'],
    ]
    placebo_objc_args += ['-fobjc-arc']
endif

vlc_modules += {
    'name' : 'placebo',
    'sources' : placebo_sources,
    'link_with' : [libplacebo_utils],
    'dependencies' : placebo_deps,
    'objc_args' : placebo_objc_args,
}

## Vulkan
if vulkan_dep.found()
    vlc_modules += {
        'name' : 'placebo_vk',
        'sources' : files('../vulkan/platform.c', 'instance_vulkan.c'),
        'link_with' : [libplacebo_utils],
        'dependencies' : [libplacebo_dep],
    }
endif

## OpenGL
if opengl_dep.found()
    vlc_modules += {
        'name' : 'placebo_gl',
        'sources' : files('instance_opengl.c'),
        'link_with' : [libplacebo_utils],
        'dependencies' : [libplacebo_dep],
    }
endif

if opengles2_dep.found()
    vlc_modules += {
        'name' : 'placebo_gles2',
        'sources' : files('instance_opengl.c'),
        'link_with' : [libplacebo_utils],
        'c_args' : '-DUSE_OPENGL_ES2',
        'dependencies' : [libplacebo_dep],
    }
endif
