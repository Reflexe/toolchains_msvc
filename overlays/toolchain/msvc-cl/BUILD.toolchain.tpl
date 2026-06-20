load("@rules_cc//cc/toolchains:args.bzl", "cc_args")
load("@rules_cc//cc/toolchains:tool.bzl", "cc_tool")
load("@rules_cc//cc/toolchains:tool_map.bzl", "cc_tool_map")
load("@rules_cc//cc/toolchains:toolchain.bzl", "cc_toolchain")

package(default_visibility = ["//visibility:public"])

# tools

cc_tool_map(
    name = "all_tools",
    tools = {
        "@rules_cc//cc/toolchains/actions:assembly_actions": ":ml64",
        "@rules_cc//cc/toolchains/actions:c_compile": ":cl",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions": ":cl",
        "@rules_cc//cc/toolchains/actions:link_actions": ":link",
        "@rules_cc//cc/toolchains/actions:ar_actions": ":lib",
        "@rules_cc//cc/toolchains/actions:strip": ":link",
    },
    visibility = ["//visibility:public"],
)

cc_tool(
    name = "cl",
    src = "//msvc/bin:cl_wrapper_{suffix}",
    data = [
        "//msvc/bin:all_binaries_{suffix}",
        "//msvc/include:all_includes",
    ],
)

{link_cc_tool}

cc_tool(
    name = "lib",
    src = "//msvc/bin:lib_{suffix}",
    data = [
        "//msvc/bin:all_binaries_{suffix}",
    ],
)

cc_tool(
    name = "ml64",
    src = "//msvc/bin:ml64_{suffix}",
    data = [
        "//msvc/bin:all_binaries_{suffix}",
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
        "/nologo",
        "/experimental:deterministic",
        "/Brepro",
    ],
)

cc_args(
    name = "base_ar_flags",
    actions = [
        "@rules_cc//cc/toolchains/actions:ar_actions",
    ],
    args = [
        "/nologo",
        "/experimental:deterministic",
        "/Brepro",
    ],
)

{base_link_flags}

cc_args(
    name = "base_link_flags",
    actions = [
        "@rules_cc//cc/toolchains/actions:link_actions",
    ],
    args = base_link_flags
)

cc_args(
    name = "include_paths",
    actions = [
        "@rules_cc//cc/toolchains/actions:c_compile",
        "@rules_cc//cc/toolchains/actions:cpp_compile_actions",
    ],
    allowlist_include_directories = [
        "//msvc/include:include_dir",
        "//msvc/include:atlmfc_include",
        "//winsdk/include:ucrt_include",
        "//winsdk/include:um_include",
        "//winsdk/include:shared_include",
    ],
    args = [
        "/external:W0",
        "/external:I{msvc_include}",
        "/external:I{msvc_atlmfc_include}",
        "/external:I{winsdk_ucrt_include}",
        "/external:I{winsdk_um_include}",
        "/external:I{winsdk_shared_include}",
    ],
    data = [
        "//msvc/include:all_includes",
        "//msvc/include:atlmfc_include_files",
        "//winsdk/include:shared_include_files",
        "//winsdk/include:ucrt_include_files",
        "//winsdk/include:um_include_files",
    ],
    format = {
        "msvc_include": "//msvc/include:include_dir",
        "msvc_atlmfc_include": "//msvc/include:atlmfc_include",
        "winsdk_ucrt_include": "//winsdk/include:ucrt_include",
        "winsdk_um_include": "//winsdk/include:um_include",
        "winsdk_shared_include": "//winsdk/include:shared_include",
    },
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
    requires_any_of = ["{features_package}/msvc:no_static_no_debug_constraint"],
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
    requires_any_of = ["{features_package}/msvc:static_no_debug_constraint"],
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
    requires_any_of = ["{features_package}/msvc:no_static_debug_constraint"],
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
    requires_any_of = ["{features_package}/msvc:static_debug_constraint"],
)

cc_toolchain(
    name = "cc_toolchain",
    compiler = "{compiler}",
    supports_param_files = True,
    args = [
        "base_compile_flags",
        "base_link_flags",
        "base_ar_flags",
        "include_paths",
        "release_dynamic_runtime_link",
        "release_static_runtime_link",
        "debug_dynamic_runtime_link",
        "debug_static_runtime_link",
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
        "{features_package}/msvc:default_features",
        "{features_package}/msvc:no_dotd_file",
        "{features_package}/msvc:parse_showincludes",
    ],
    known_features = [
        "{features_package}/msvc:all_known_features",
    ],
    tool_map = ":all_tools",
)
