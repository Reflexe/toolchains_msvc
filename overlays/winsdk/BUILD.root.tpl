load("@bazel_skylib//rules/directory:directory.bzl", "directory")
load("@bazel_skylib//rules/directory:subdirectory.bzl", "subdirectory")

package(default_visibility = ["//visibility:public"])

# Include Dirs
directory(
    name = "winsdk_tree",
    srcs = glob(
        [
            "Include/10.0.{winsdk_version}.0/ucrt/**",
            "Include/10.0.{winsdk_version}.0/um/**",
            "Include/10.0.{winsdk_version}.0/shared/**",
            "Include/10.0.{winsdk_version}.0/cppwinrt/**",
            "Lib/10.0.{winsdk_version}.0/um/x64/**",
            "Lib/10.0.{winsdk_version}.0/ucrt/x64/**",
            "Lib/10.0.{winsdk_version}.0/um/x86/**",
            "Lib/10.0.{winsdk_version}.0/ucrt/x86/**",
            "Lib/10.0.{winsdk_version}.0/um/arm64/**",
            "Lib/10.0.{winsdk_version}.0/ucrt/arm64/**",
        ],
        allow_empty = True,
    ),
)

subdirectory(
    name = "ucrt_include",
    parent = ":winsdk_tree",
    path = "Include/10.0.{winsdk_version}.0/ucrt",
)

filegroup(
    name = "ucrt_include_files",
    srcs = glob(
        [
            "Include/10.0.{winsdk_version}.0/ucrt/**/*.h",
            "Include/10.0.{winsdk_version}.0/ucrt/**/*.hpp",
        ],
        allow_empty = True,
    ),
)

subdirectory(
    name = "um_include",
    parent = ":winsdk_tree",
    path = "Include/10.0.{winsdk_version}.0/um",
)

filegroup(
    name = "um_include_files",
    srcs = glob(
        [
            "Include/10.0.{winsdk_version}.0/um/**/*.h",
            "Include/10.0.{winsdk_version}.0/um/**/*.hpp",
        ],
        allow_empty = True,
    ),
)

subdirectory(
    name = "shared_include",
    parent = ":winsdk_tree",
    path = "Include/10.0.{winsdk_version}.0/shared",
)

filegroup(
    name = "shared_include_files",
    srcs = glob(
        [
            "Include/10.0.{winsdk_version}.0/shared/**/*.h",
            "Include/10.0.{winsdk_version}.0/shared/**/*.hpp",
        ],
        allow_empty = True,
    ),
)

# Resource compiler runfiles (rc.exe + rcdll.dll), one bundle per host arch.
# Shipped in the "Windows SDK for Windows Store Apps Tools" MSI under
# bin/10.0.<ver>.0/<host>/. The bare rc.exe (for use as a tool `src`) is
# available directly via the catch-all `exports_files` below.
filegroup(
    name = "rc_files_x64",
    srcs = glob(
        [
            "bin/10.0.{winsdk_version}.0/x64/rc.exe",
            "bin/10.0.{winsdk_version}.0/x64/rcdll.dll",
        ],
        allow_empty = True,
    ),
)

filegroup(
    name = "rc_files_x86",
    srcs = glob(
        [
            "bin/10.0.{winsdk_version}.0/x86/rc.exe",
            "bin/10.0.{winsdk_version}.0/x86/rcdll.dll",
        ],
        allow_empty = True,
    ),
)

filegroup(
    name = "rc_files_arm64",
    srcs = glob(
        [
            "bin/10.0.{winsdk_version}.0/arm64/rc.exe",
            "bin/10.0.{winsdk_version}.0/arm64/rcdll.dll",
        ],
        allow_empty = True,
    ),
)

subdirectory(
    name = "cppwinrt_include",
    parent = ":winsdk_tree",
    path = "Include/10.0.{winsdk_version}.0/cppwinrt",
)

filegroup(
    name = "cppwinrt_include_files",
    srcs = glob(
        [
            "Include/10.0.{winsdk_version}.0/cppwinrt/**/*.h",
            "Include/10.0.{winsdk_version}.0/cppwinrt/**/*.hpp",
        ],
        allow_empty = True,
    ),
)

exports_files(
    glob(["**/*"]),  # or narrower patterns
    visibility = ["//visibility:public"],
)

