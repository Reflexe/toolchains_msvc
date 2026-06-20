load("@bazel_skylib//rules/directory:directory.bzl", "directory")
load("@bazel_skylib//rules/directory:subdirectory.bzl", "subdirectory")

package(default_visibility = ["//visibility:public"])

# CL
exports_files(
    [
        "Tools/bin/Hostx64/x64/cl.exe",
        "Tools/bin/Hostx64/x86/cl.exe",
        "Tools/bin/Hostx64/arm64/cl.exe",
        "Tools/bin/Hostx86/x64/cl.exe",
        "Tools/bin/Hostx86/x86/cl.exe",
        "Tools/bin/Hostx86/arm64/cl.exe",
        "Tools/bin/Hostarm64/x64/cl.exe",
        "Tools/bin/Hostarm64/x86/cl.exe",
        "Tools/bin/Hostarm64/arm64/cl.exe",
    ],
    visibility = ["//visibility:public"],
)

# CL wrapper (forwards EXECROOT to cl.exe via /pathmap for reproducible paths)
exports_files(
    [
        "Tools/bin/Hostx64/x64/cl_wrapper.bat",
        "Tools/bin/Hostx64/x86/cl_wrapper.bat",
        "Tools/bin/Hostx64/arm64/cl_wrapper.bat",
        "Tools/bin/Hostx86/x64/cl_wrapper.bat",
        "Tools/bin/Hostx86/x86/cl_wrapper.bat",
        "Tools/bin/Hostx86/arm64/cl_wrapper.bat",
        "Tools/bin/Hostarm64/x64/cl_wrapper.bat",
        "Tools/bin/Hostarm64/x86/cl_wrapper.bat",
        "Tools/bin/Hostarm64/arm64/cl_wrapper.bat",
    ],
    visibility = ["//visibility:public"],
)

alias(
    name = "cl_hostx64_targetx64",
    actual = ":Tools/bin/Hostx64/x64/cl.exe",
)

alias(
    name = "cl_hostx64_targetx86",
    actual = ":Tools/bin/Hostx64/x86/cl.exe",
)

alias(
    name = "cl_hostx64_targetarm64",
    actual = ":Tools/bin/Hostx64/arm64/cl.exe",
)

alias(
    name = "cl_hostx86_targetx64",
    actual = ":Tools/bin/Hostx86/x64/cl.exe",
)

alias(
    name = "cl_hostx86_targetx86",
    actual = ":Tools/bin/Hostx86/x86/cl.exe",
)

alias(
    name = "cl_hostx86_targetarm64",
    actual = ":Tools/bin/Hostx86/arm64/cl.exe",
)

alias(
    name = "cl_hostarm64_targetx64",
    actual = ":Tools/bin/Hostarm64/x64/cl.exe",
)

alias(
    name = "cl_hostarm64_targetx86",
    actual = ":Tools/bin/Hostarm64/x86/cl.exe",
)

alias(
    name = "cl_hostarm64_targetarm64",
    actual = ":Tools/bin/Hostarm64/arm64/cl.exe",
)

alias(
    name = "cl_wrapper_hostx64_targetx64",
    actual = ":Tools/bin/Hostx64/x64/cl_wrapper.bat",
)
alias(
    name = "cl_wrapper_hostx64_targetx86",
    actual = ":Tools/bin/Hostx64/x86/cl_wrapper.bat",
)
alias(
    name = "cl_wrapper_hostx64_targetarm64",
    actual = ":Tools/bin/Hostx64/arm64/cl_wrapper.bat",
)
alias(
    name = "cl_wrapper_hostx86_targetx64",
    actual = ":Tools/bin/Hostx86/x64/cl_wrapper.bat",
)
alias(
    name = "cl_wrapper_hostx86_targetx86",
    actual = ":Tools/bin/Hostx86/x86/cl_wrapper.bat",
)
alias(
    name = "cl_wrapper_hostx86_targetarm64",
    actual = ":Tools/bin/Hostx86/arm64/cl_wrapper.bat",
)
alias(
    name = "cl_wrapper_hostarm64_targetx64",
    actual = ":Tools/bin/Hostarm64/x64/cl_wrapper.bat",
)
alias(
    name = "cl_wrapper_hostarm64_targetx86",
    actual = ":Tools/bin/Hostarm64/x86/cl_wrapper.bat",
)
alias(
    name = "cl_wrapper_hostarm64_targetarm64",
    actual = ":Tools/bin/Hostarm64/arm64/cl_wrapper.bat",
)

# Linker
exports_files(
    [
        "Tools/bin/Hostx64/x64/link.exe",
        "Tools/bin/Hostx64/x86/link.exe",
        "Tools/bin/Hostx64/arm64/link.exe",
        "Tools/bin/Hostx86/x64/link.exe",
        "Tools/bin/Hostx86/x86/link.exe",
        "Tools/bin/Hostx86/arm64/link.exe",
        "Tools/bin/Hostarm64/x64/link.exe",
        "Tools/bin/Hostarm64/x86/link.exe",
        "Tools/bin/Hostarm64/arm64/link.exe",
    ],
    visibility = ["//visibility:public"],
)

alias(
    name = "link_hostx64_targetx64",
    actual = ":Tools/bin/Hostx64/x64/link.exe",
)

alias(
    name = "link_hostx64_targetx86",
    actual = ":Tools/bin/Hostx64/x86/link.exe",
)

alias(
    name = "link_hostx64_targetarm64",
    actual = ":Tools/bin/Hostx64/arm64/link.exe",
)

alias(
    name = "link_hostx86_targetx64",
    actual = ":Tools/bin/Hostx86/x64/link.exe",
)

alias(
    name = "link_hostx86_targetx86",
    actual = ":Tools/bin/Hostx86/x86/link.exe",
)

alias(
    name = "link_hostx86_targetarm64",
    actual = ":Tools/bin/Hostx86/arm64/link.exe",
)

alias(
    name = "link_hostarm64_targetx64",
    actual = ":Tools/bin/Hostarm64/x64/link.exe",
)

alias(
    name = "link_hostarm64_targetx86",
    actual = ":Tools/bin/Hostarm64/x86/link.exe",
)

alias(
    name = "link_hostarm64_targetarm64",
    actual = ":Tools/bin/Hostarm64/arm64/link.exe",
)

# Librarian
exports_files(
    [
        "Tools/bin/Hostx64/x64/lib.exe",
        "Tools/bin/Hostx64/x86/lib.exe",
        "Tools/bin/Hostx64/arm64/lib.exe",
        "Tools/bin/Hostx86/x64/lib.exe",
        "Tools/bin/Hostx86/x86/lib.exe",
        "Tools/bin/Hostx86/arm64/lib.exe",
        "Tools/bin/Hostarm64/x64/lib.exe",
        "Tools/bin/Hostarm64/x86/lib.exe",
        "Tools/bin/Hostarm64/arm64/lib.exe",
    ],
    visibility = ["//visibility:public"],
)

alias(
    name = "lib_hostx64_targetx64",
    actual = ":Tools/bin/Hostx64/x64/lib.exe",
)

alias(
    name = "lib_hostx64_targetx86",
    actual = ":Tools/bin/Hostx64/x86/lib.exe",
)

alias(
    name = "lib_hostx64_targetarm64",
    actual = ":Tools/bin/Hostx64/arm64/lib.exe",
)

alias(
    name = "lib_hostx86_targetx64",
    actual = ":Tools/bin/Hostx86/x64/lib.exe",
)

alias(
    name = "lib_hostx86_targetx86",
    actual = ":Tools/bin/Hostx86/x86/lib.exe",
)

alias(
    name = "lib_hostx86_targetarm64",
    actual = ":Tools/bin/Hostx86/arm64/lib.exe",
)

alias(
    name = "lib_hostarm64_targetx64",
    actual = ":Tools/bin/Hostarm64/x64/lib.exe",
)

alias(
    name = "lib_hostarm64_targetx86",
    actual = ":Tools/bin/Hostarm64/x86/lib.exe",
)

alias(
    name = "lib_hostarm64_targetarm64",
    actual = ":Tools/bin/Hostarm64/arm64/lib.exe",
)

# Assembler
exports_files(
    [
        "Tools/bin/Hostx64/x64/ml64.exe",
        "Tools/bin/Hostx64/x86/ml64.exe",
        "Tools/bin/Hostx64/arm64/ml64.exe",
        "Tools/bin/Hostx86/x64/ml64.exe",
        "Tools/bin/Hostx86/x86/ml64.exe",
        "Tools/bin/Hostx86/arm64/ml64.exe",
        "Tools/bin/Hostarm64/x64/ml64.exe",
        "Tools/bin/Hostarm64/x86/ml64.exe",
        "Tools/bin/Hostarm64/arm64/ml64.exe",
    ],
    visibility = ["//visibility:public"],
)

alias(
    name = "ml64_hostx64_targetx64",
    actual = ":Tools/bin/Hostx64/x64/ml64.exe",
)

alias(
    name = "ml64_hostx64_targetx86",
    actual = ":Tools/bin/Hostx64/x86/ml64.exe",
)

alias(
    name = "ml64_hostx64_targetarm64",
    actual = ":Tools/bin/Hostx64/arm64/ml64.exe",
)

alias(
    name = "ml64_hostx86_targetx64",
    actual = ":Tools/bin/Hostx86/x64/ml64.exe",
)

alias(
    name = "ml64_hostx86_targetx86",
    actual = ":Tools/bin/Hostx86/x86/ml64.exe",
)

alias(
    name = "ml64_hostx86_targetarm64",
    actual = ":Tools/bin/Hostx86/arm64/ml64.exe",
)

alias(
    name = "ml64_hostarm64_targetx64",
    actual = ":Tools/bin/Hostarm64/x64/ml64.exe",
)

alias(
    name = "ml64_hostarm64_targetx86",
    actual = ":Tools/bin/Hostarm64/x86/ml64.exe",
)

alias(
    name = "ml64_hostarm64_targetarm64",
    actual = ":Tools/bin/Hostarm64/arm64/ml64.exe",
)

# Directory tree metadata for precise subdirectory paths.
directory(
    name = "msvc_tree",
    srcs = glob(
        [
            "Tools/include/**",
            "Tools/atlmfc/include/**",
            "Tools/lib/x64/**",
            "Tools/lib/x86/**",
            "Tools/lib/arm64/**",
            "Tools/bin/Hostx64/x64/**",
            "Tools/bin/Hostx64/x86/**",
            "Tools/bin/Hostx64/arm64/**",
            "Tools/bin/Hostx86/x64/**",
            "Tools/bin/Hostx86/x86/**",
            "Tools/bin/Hostx86/arm64/**",
            "Tools/bin/Hostarm64/x64/**",
            "Tools/bin/Hostarm64/x86/**",
            "Tools/bin/Hostarm64/arm64/**",
        ],
        allow_empty = True,
    ),
)

# Include Dir
subdirectory(
    name = "include_dir",
    parent = ":msvc_tree",
    path = "Tools/include",
)

# The :atlmfc_* labels mirror the on-disk Tools/atlmfc/ directory name
# (Microsoft's canonical Visual C++ layout). Population is gated on
# `toolchain.toolchain_set(extra_msvc_packages = ["atl"])` — without it, the .atl
# packages are skipped by private/vs_channel_manifest.bzl::get_msvc_package_ids
# and these globs match nothing, so the labels exist but resolve to empty.
# The .mfc package id remains excluded unconditionally for now.
subdirectory(
    name = "atlmfc_include",
    parent = ":msvc_tree",
    path = "Tools/atlmfc/include",
)

filegroup(
    name = "atlmfc_include_files",
    srcs = glob(
        [
            "Tools/atlmfc/include/**/*.h",
            "Tools/atlmfc/include/**/*.inl",
        ],
        allow_empty = True,
    ),
)

filegroup(
    name = "msvc_all_includes",
    srcs = glob(["**/*.h", "**/*.hpp"]) + glob(["**/*"], exclude = ["**/*.*"], exclude_directories = 1)
)

# Per-arch MSVC Tools/lib subdirectories + filegroups. The directory
# label is forwarded to /LIBPATH: by the toolchain's system_vc_compat
# cc_args (when the extension's system_vc_compat option is enabled);
# the filegroup carries the .lib files into the link action's inputs.
subdirectory(
    name = "lib_x64",
    parent = ":msvc_tree",
    path = "Tools/lib/x64",
)

subdirectory(
    name = "lib_x86",
    parent = ":msvc_tree",
    path = "Tools/lib/x86",
)

subdirectory(
    name = "lib_arm64",
    parent = ":msvc_tree",
    path = "Tools/lib/arm64",
)

filegroup(
    name = "lib_files_x64",
    srcs = glob(["Tools/lib/x64/**/*.lib"], allow_empty = True),
)

filegroup(
    name = "lib_files_x86",
    srcs = glob(["Tools/lib/x86/**/*.lib"], allow_empty = True),
)

filegroup(
    name = "lib_files_arm64",
    srcs = glob(["Tools/lib/arm64/**/*.lib"], allow_empty = True),
)

# Binaries
filegroup(
    name = "msvc_all_binaries_hostx64_targetx64",
    srcs = glob(["Tools/bin/Hostx64/x64/**"], allow_empty = True),
)

filegroup(
    name = "msvc_all_binaries_hostx64_targetx86",
    srcs = glob(["Tools/bin/Hostx64/x86/**"], allow_empty = True),
)

filegroup(
    name = "msvc_all_binaries_hostx64_targetarm64",
    srcs = glob(["Tools/bin/Hostx64/arm64/**"], allow_empty = True),
)

filegroup(
    name = "msvc_all_binaries_hostx86_targetx64",
    srcs = glob(["Tools/bin/Hostx86/x64/**"], allow_empty = True),
)

filegroup(
    name = "msvc_all_binaries_hostx86_targetx86",
    srcs = glob(["Tools/bin/Hostx86/x86/**"], allow_empty = True),
)

filegroup(
    name = "msvc_all_binaries_hostx86_targetarm64",
    srcs = glob(["Tools/bin/Hostx86/arm64/**"], allow_empty = True),
)

filegroup(
    name = "msvc_all_binaries_hostarm64_targetx64",
    srcs = glob(["Tools/bin/Hostarm64/x64/**"], allow_empty = True),
)

filegroup(
    name = "msvc_all_binaries_hostarm64_targetx86",
    srcs = glob(["Tools/bin/Hostarm64/x86/**"], allow_empty = True),
)

filegroup(
    name = "msvc_all_binaries_hostarm64_targetarm64",
    srcs = glob(["Tools/bin/Hostarm64/arm64/**"], allow_empty = True),
)

exports_files(
    glob(["**/*"]),  # or narrower patterns
    visibility = ["//visibility:public"],
)

