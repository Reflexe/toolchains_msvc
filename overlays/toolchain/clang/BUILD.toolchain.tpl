load("@rules_cc//cc/toolchains:args.bzl", "cc_args")
load("@rules_cc//cc/toolchains:feature.bzl", "cc_feature")
load("@rules_cc//cc/toolchains:tool.bzl", "cc_tool")
load("@rules_cc//cc/toolchains:tool_map.bzl", "cc_tool_map")
load("@rules_cc//cc/toolchains:toolchain.bzl", "cc_toolchain")

package(default_visibility = ["//visibility:public"])

# tools
cc_tool_map(
    name = "all_tools",
    tools = {
        "@rules_cc//cc/toolchains/actions:assembly_actions": ":ml64",
        "@rules_cc//cc/toolchains/actions:c_compile": ":clang",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions": ":clang",
        "@rules_cc//cc/toolchains/actions:link_actions": ":link",
        "@rules_cc//cc/toolchains/actions:ar_actions": ":lib",
        "@rules_cc//cc/toolchains/actions:strip": ":link",
    },
    visibility = ["//visibility:public"],
)

cc_tool(
    name = "clang",
    src = "//llvm/bin:clang_{suffix}",
    data = [
        "//llvm/bin:clang_exe_only_{suffix}",
        "//msvc/include:all_includes",
    ],
)

cc_tool(
    name = "link",
    src = "//llvm/bin:lld-link_{suffix}",
    data = [
        "//llvm/bin:lld_link_exe_only_{suffix}",
    ],
)

cc_tool(
    name = "lib",
    src = "//llvm/bin:llvm-lib_{suffix}",
    data = [
        "//llvm/bin:llvm_lib_exe_only_{suffix}",
    ],
)

cc_tool(
    name = "ml64",
    src = "//llvm/bin:llvm-ml_{suffix}",
    data = [
        "//llvm/bin:llvm_ml_exe_only_{suffix}",
    ],
)

# args
cc_args(
    name = "base_compile_flags",
    actions = [
        "@rules_cc//cc/toolchains/actions:c_compile",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions",
    ],
    args = [
        "--target={clang_target}",
        "-fms-compatibility",
        "-fms-extensions",
        "-nostdinc",
        "-mno-incremental-linker-compatible",
        "-fdebug-compilation-dir=.",
        "-fcoverage-compilation-dir=.",
        "-resource-dir=.",
        "-no-canonical-prefixes",
        "-fno-ident",
    ] + {ms_compat_version_select},
)

cc_args(
    name = "base_link_flags",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "/lldignoreenv",
{nodefaultlib_line}        "/INCREMENTAL:NO",
        "/PDBALTPATH:%_PDB%",
        "/Brepro",
        "/pdbsourcepath:.",
    ],
)
{local_config_cc_compat_args}
cc_args(
    name = "include_paths",
    actions = [
        "@rules_cc//cc/toolchains/actions:c_compile",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions",
    ],
    allowlist_include_directories = [
        "//llvm/include:clang_builtin_include_host{host}",
        "//msvc/include:include_dir",
        "//msvc/include:atlmfc_include",
        "//winsdk/include:ucrt_include",
        "//winsdk/include:um_include",
        "//winsdk/include:shared_include",
        "//winsdk/include:cppwinrt_include",
        "//winsdk/include:winrt_include",
    ],
    args = [
        "-isystem",
        "{clang_builtin_include}",
        "-isystem",
        "{msvc_include}",
        "-isystem",
        "{msvc_atlmfc_include}",
        "-isystem",
        "{winsdk_ucrt_include}",
        "-isystem",
        "{winsdk_um_include}",
        "-isystem",
        "{winsdk_shared_include}",
        "-isystem",
        "{winsdk_cppwinrt_include}",
        "-isystem",
        "{winsdk_winrt_include}",
    ],
    data = [
        "//llvm/include:clang_builtin_include_files_host{host}",
        "//msvc/include:all_includes",
        "//msvc/include:atlmfc_include_files",
        "//winsdk/include:um_include_files",
        "//winsdk/include:ucrt_include_files",
        "//winsdk/include:shared_include_files",
        "//winsdk/include:cppwinrt_include_files",
        "//winsdk/include:winrt_include_files",
    ],
    format = {
        "clang_builtin_include": "//llvm/include:clang_builtin_include_host{host}",
        "msvc_include": "//msvc/include:include_dir",
        "msvc_atlmfc_include": "//msvc/include:atlmfc_include",
        "winsdk_ucrt_include": "//winsdk/include:ucrt_include",
        "winsdk_um_include": "//winsdk/include:um_include",
        "winsdk_shared_include": "//winsdk/include:shared_include",
        "winsdk_cppwinrt_include": "//winsdk/include:cppwinrt_include",
        "winsdk_winrt_include": "//winsdk/include:winrt_include",
    },
)

# See msvc-cl/BUILD.toolchain.tpl :system_include_paths for rationale.
cc_feature(
    name = "system_include_paths",
    args = [":include_paths"],
    feature_name = "system_include_paths",
)

cc_args(
    name = "release_dynamic_runtime_link",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "{ucrt}",
        "{msvcrt}",
        "{vcruntime}",
        "{msvcprt}",
    ],
    data = [
        "//winsdk/lib:rt_ucrt_{target}",
        "//msvc/lib:rt_msvcrt_{target}",
        "//msvc/lib:rt_vcruntime_{target}",
        "//msvc/lib:rt_msvcprt_{target}",
    ],
    format = {
        "ucrt": "//winsdk/lib:rt_ucrt_{target}",
        "msvcrt": "//msvc/lib:rt_msvcrt_{target}",
        "vcruntime": "//msvc/lib:rt_vcruntime_{target}",
        "msvcprt": "//msvc/lib:rt_msvcprt_{target}",
    },
    requires_any_of = ["{features_package}/clang:no_static_no_debug_constraint"],
)

cc_args(
    name = "release_static_runtime_link",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "{libucrt}",
        "{libvcruntime}",
        "{libcmt}",
        "{libcpmt}",
    ],
    data = [
        "//winsdk/lib:rt_libucrt_{target}",
        "//msvc/lib:rt_libvcruntime_{target}",
        "//msvc/lib:rt_libcmt_{target}",
        "//msvc/lib:rt_libcpmt_{target}",
    ],
    format = {
        "libucrt": "//winsdk/lib:rt_libucrt_{target}",
        "libvcruntime": "//msvc/lib:rt_libvcruntime_{target}",
        "libcmt": "//msvc/lib:rt_libcmt_{target}",
        "libcpmt": "//msvc/lib:rt_libcpmt_{target}",
    },
    requires_any_of = ["{features_package}/clang:static_no_debug_constraint"],
)

cc_args(
    name = "debug_dynamic_runtime_link",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "{ucrtd}",
        "{msvcrtd}",
        "{vcruntimed}",
        "{msvcprtd}",
    ],
    data = [
        "//winsdk/lib:rt_ucrtd_{target}",
        "//msvc/lib:rt_msvcrtd_{target}",
        "//msvc/lib:rt_vcruntimed_{target}",
        "//msvc/lib:rt_msvcprtd_{target}",
    ],
    format = {
        "ucrtd": "//winsdk/lib:rt_ucrtd_{target}",
        "msvcrtd": "//msvc/lib:rt_msvcrtd_{target}",
        "vcruntimed": "//msvc/lib:rt_vcruntimed_{target}",
        "msvcprtd": "//msvc/lib:rt_msvcprtd_{target}",
    },
    requires_any_of = ["{features_package}/clang:no_static_debug_constraint"],
)

cc_args(
    name = "debug_static_runtime_link",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = [
        "{libucrtd}",
        "{libvcruntimed}",
        "{libcmtd}",
        "{libcpmtd}",
    ],
    data = [
        "//winsdk/lib:rt_libucrtd_{target}",
        "//msvc/lib:rt_libvcruntimed_{target}",
        "//msvc/lib:rt_libcmtd_{target}",
        "//msvc/lib:rt_libcpmtd_{target}",
    ],
    format = {
        "libucrtd": "//winsdk/lib:rt_libucrtd_{target}",
        "libvcruntimed": "//msvc/lib:rt_libvcruntimed_{target}",
        "libcmtd": "//msvc/lib:rt_libcmtd_{target}",
        "libcpmtd": "//msvc/lib:rt_libcpmtd_{target}",
    },
    requires_any_of = ["{features_package}/clang:static_debug_constraint"],
)

# cc_toolchain
cc_toolchain(
    name = "cc_toolchain",
    compiler = "{compiler}",
    supports_param_files = True,
    args = [
        ":base_compile_flags",
        ":base_link_flags",
        ":release_dynamic_runtime_link",
        ":release_static_runtime_link",
        ":debug_dynamic_runtime_link",
        ":debug_static_runtime_link",
        {local_config_cc_compat_toolchain_arg}
    ],
    artifact_name_patterns = [
        "{artifacts_package}:executable",
        "{artifacts_package}:object_file",
        "{artifacts_package}:static_library",
        "{artifacts_package}:alwayslink_static_library",
        "{artifacts_package}:dynamic_library",
        "{artifacts_package}:interface_library",
    ],
    enabled_features = [
        "{features_package}/clang:default_features",
        ":system_include_paths",
        "{features_package}/clang:dependency_file",
    ],
    known_features = [
        ":system_include_paths",
        "{features_package}/clang:all_known_features",
    ],
    tool_map = ":all_tools",
)
