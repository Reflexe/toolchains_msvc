"""Repository rule to define MSVC toolchains.

The generated `@msvc_toolchains` repo folds the MSVC / WinSDK / LLVM *version*
axes behind `select()`-based facade packages keyed on the `//msvc`, `//winsdk`,
and `//llvm` flags:

* `//llvm/bin`, `//llvm/include`
* `//msvc/bin`, `//msvc/include`, `//msvc/lib`
* `//winsdk/include`, `//winsdk/bin` (rc.exe), `//winsdk/lib`

Architecture (host/target) is NOT selected: one `cc_toolchain` is generated per
`(toolchain_set, compiler, host, target)` and registered with
`exec_compatible_with` / `target_compatible_with` so cross-compilation picks the
right baked tools. Only the version axes use `select()`.
"""

load("//private:libs.bzl", "msvc_lib", "ucrt_lib", "um_lib")
load("//private:utils.bzl", "convert_msvc_arch_to_bazel_arch", "convert_msvc_arch_to_clang_target", "msvc_version_to_cl_internal_version")

def _normalize_lib_name(lib_name):
    """Returns lowercase name without .lib extension."""
    name = lib_name.lower()
    if name.endswith(".lib"):
        return name[:-4]
    return name

def _add_lib_variant(lib_map, lib_name, config_name, label):
    variants = lib_map.get(lib_name)
    if variants == None:
        variants = {}
        lib_map[lib_name] = variants

    existing = variants.get(config_name)
    if existing != None and existing != label:
        fail("Library '{}' has conflicting variants for '{}': '{}' and '{}'".format(lib_name, config_name, existing, label))

    variants[config_name] = label

def _append_list_line(content, var_name, values, item_prefix = ""):
    """Appends 'var_name = [item_prefix"v1", item_prefix"v2", ...]' for generated .bzl files."""
    if not values:
        s = "[]"
    else:
        # Escape so generated Starlark is valid if a value contains backslash or quote
        escaped = ["\"" + item_prefix + str(x).replace("\\", "\\\\").replace("\"", "\\\"") + "\"" for x in values]
        s = "[" + ", ".join(escaped) + "]"
    return content + var_name + " = " + s + "\n"

def _toolchain_set_prefix(group_name):
    return "toolchain_set/{}".format(group_name)

def _select_label(flag_pkg, versions, label_for_version, indent = "        "):
    """Returns a `select({...})` expression string keyed on `//<flag_pkg>:<v>`.

    Args:
        flag_pkg: package of the version flag (e.g. "msvc", "winsdk", "llvm").
        versions: list of version strings (the select arms).
        label_for_version: function version -> label string (without quotes).
        indent: leading whitespace for each arm.
    """
    close_indent = indent[:-4] if len(indent) >= 4 else ""
    lines = ["select({"]
    for v in versions:
        lines.append("{}\"//{}:{}\": \"{}\",".format(indent, flag_pkg, v, label_for_version(v)))
    lines.append(close_indent + "})")
    return "\n".join(lines)

def _select_list(flag_pkg, versions, label_for_version, indent = "        "):
    """Like `_select_label` but each arm is a single-element list (for `srcs`)."""
    close_indent = indent[:-4] if len(indent) >= 4 else ""
    lines = ["select({"]
    for v in versions:
        lines.append("{}\"//{}:{}\": [\"{}\"],".format(indent, flag_pkg, v, label_for_version(v)))
    lines.append(close_indent + "})")
    return "\n".join(lines)

def _llvm_hosts(hosts):
    # LLVM provides no x86 Windows host binaries.
    return [h for h in hosts if h != "x86"]

def _emit_llvm_facades(ctx, llvm_versions, hosts, targets):
    """Generates //llvm/bin and //llvm/include facades (select over //llvm)."""
    if not llvm_versions:
        return

    llvm_hosts = _llvm_hosts(hosts)

    bin_content = ["package(default_visibility = [\"//visibility:public\"])", ""]

    # alias name -> repo target name (same name pattern in the llvm repo)
    alias_tools = ["clang", "clang-cl", "lld-link", "llvm-lib", "llvm-ml"]

    # filegroup data targets (exe_only) -> repo target name
    data_tools = {
        "clang_exe_only": "clang_exe_only",
        "clang_cl_exe_only": "clang_cl_exe_only",
        "lld_link_exe_only": "lld_link_exe_only",
        "llvm_lib_exe_only": "llvm_lib_exe_only",
        "llvm_ml_exe_only": "llvm_ml_exe_only",
    }

    for host in llvm_hosts:
        for target in targets:
            suffix = "host{}_target{}".format(host, target)
            for tool in alias_tools:
                actual = _select_label(
                    "llvm",
                    llvm_versions,
                    lambda v, host = host, suffix = suffix, tool = tool: "@llvm_{}_{}//:{}_{}".format(v, host, tool, suffix),
                )
                bin_content.append("alias(\n    name = \"{}_{}\",\n    actual = {},\n)\n".format(tool, suffix, actual))
            for fg_name, repo_name in data_tools.items():
                srcs = _select_list(
                    "llvm",
                    llvm_versions,
                    lambda v, host = host, suffix = suffix, repo_name = repo_name: "@llvm_{}_{}//:{}_{}".format(v, host, repo_name, suffix),
                )
                bin_content.append("filegroup(\n    name = \"{}_{}\",\n    srcs = {},\n)\n".format(fg_name, suffix, srcs))

    ctx.file("llvm/bin/BUILD.bazel", "\n".join(bin_content))

    inc_content = ["package(default_visibility = [\"//visibility:public\"])", ""]
    for host in llvm_hosts:
        actual = _select_label(
            "llvm",
            llvm_versions,
            lambda v, host = host: "@llvm_{}_{}//:clang_builtin_include".format(v, host),
        )
        inc_content.append("alias(\n    name = \"clang_builtin_include_host{}\",\n    actual = {},\n)\n".format(host, actual))
        srcs = _select_list(
            "llvm",
            llvm_versions,
            lambda v, host = host: "@llvm_{}_{}//:clang_builtin_include_files".format(v, host),
        )
        inc_content.append("filegroup(\n    name = \"clang_builtin_include_files_host{}\",\n    srcs = {},\n)\n".format(host, srcs))

    ctx.file("llvm/include/BUILD.bazel", "\n".join(inc_content))

def _emit_msvc_facades(ctx, msvc_versions, hosts, targets):
    """Generates //msvc/bin and //msvc/include facades (select over //msvc)."""
    bin_content = ["package(default_visibility = [\"//visibility:public\"])", ""]

    alias_tools = ["cl", "cl_wrapper", "link", "lib", "ml64"]
    for host in hosts:
        for target in targets:
            suffix = "host{}_target{}".format(host, target)
            for tool in alias_tools:
                actual = _select_label(
                    "msvc",
                    msvc_versions,
                    lambda v, suffix = suffix, tool = tool: "@msvc_{}//:{}_{}".format(v, tool, suffix),
                )
                bin_content.append("alias(\n    name = \"{}_{}\",\n    actual = {},\n)\n".format(tool, suffix, actual))
            srcs = _select_list(
                "msvc",
                msvc_versions,
                lambda v, suffix = suffix: "@msvc_{}//:msvc_all_binaries_{}".format(v, suffix),
            )
            bin_content.append("filegroup(\n    name = \"all_binaries_{}\",\n    srcs = {},\n)\n".format(suffix, srcs))

    ctx.file("msvc/bin/BUILD.bazel", "\n".join(bin_content))

    inc_content = ["package(default_visibility = [\"//visibility:public\"])", ""]
    inc_content.append("alias(\n    name = \"include_dir\",\n    actual = {},\n)\n".format(
        _select_label("msvc", msvc_versions, lambda v: "@msvc_{}//:include_dir".format(v)),
    ))
    # ATL include facade: mirrors the per-version :atlmfc_include label.
    # Lib-side aggregate (//msvc/lib:atlmfc_lib_*) lands in the upstream
    # system_libpaths follow-up patch when its consumer (the cc_feature
    # that emits /LIBPATH: for atlmfc/lib) is added.
    inc_content.append("alias(\n    name = \"atlmfc_include\",\n    actual = {},\n)\n".format(
        _select_label("msvc", msvc_versions, lambda v: "@msvc_{}//:atlmfc_include".format(v)),
    ))
    inc_content.append("filegroup(\n    name = \"all_includes\",\n    srcs = {},\n)\n".format(
        _select_list("msvc", msvc_versions, lambda v: "@msvc_{}//:msvc_all_includes".format(v)),
    ))
    inc_content.append("filegroup(\n    name = \"atlmfc_include_files\",\n    srcs = {},\n)\n".format(
        _select_list("msvc", msvc_versions, lambda v: "@msvc_{}//:atlmfc_include_files".format(v)),
    ))
    ctx.file("msvc/include/BUILD.bazel", "\n".join(inc_content))

def _emit_winsdk_facades(ctx, winsdk_versions, hosts):
    """Generates //winsdk/include and //winsdk/bin facades (select over //winsdk)."""
    inc_content = ["package(default_visibility = [\"//visibility:public\"])", ""]
    for inc in ["ucrt_include", "um_include", "shared_include"]:
        inc_content.append("alias(\n    name = \"{}\",\n    actual = {},\n)\n".format(
            inc,
            _select_label("winsdk", winsdk_versions, lambda v, inc = inc: "@winsdk_{}//:{}".format(v, inc)),
        ))
    for inc in ["ucrt_include_files", "um_include_files", "shared_include_files"]:
        inc_content.append("filegroup(\n    name = \"{}\",\n    srcs = {},\n)\n".format(
            inc,
            _select_list("winsdk", winsdk_versions, lambda v, inc = inc: "@winsdk_{}//:{}".format(v, inc)),
        ))
    ctx.file("winsdk/include/BUILD.bazel", "\n".join(inc_content))

    bin_content = ["package(default_visibility = [\"//visibility:public\"])", ""]
    for host in hosts:
        # Bare rc.exe (single file) - usable as a cc_tool `src`.
        bin_content.append("alias(\n    name = \"rc_{}\",\n    actual = {},\n)\n".format(
            host,
            _select_label("winsdk", winsdk_versions, lambda v, host = host: "@winsdk_{}//:bin/10.0.{}.0/{}/rc.exe".format(v, v, host)),
        ))
        # rc.exe + rcdll.dll bundle - usable as cc_tool/cc_args `data`.
        bin_content.append("filegroup(\n    name = \"rc_files_{}\",\n    srcs = {},\n)\n".format(
            host,
            _select_list("winsdk", winsdk_versions, lambda v, host = host: "@winsdk_{}//:rc_files_{}".format(v, host)),
        ))
    ctx.file("winsdk/bin/BUILD.bazel", "\n".join(bin_content))

def _emit_lib_packages(ctx, msvc_versions, winsdk_versions, targets, extra_msvc_packages):
    """Generates //msvc/lib and //winsdk/lib (cc_import system libs + runtime-link file targets)."""

    # --- config_settings combining version flag + target cpu ---
    winsdk_cfg = ""
    for winsdk_version in winsdk_versions:
        for target in targets:
            target_arch = convert_msvc_arch_to_bazel_arch(target)
            winsdk_cfg += """config_setting(
    name = "winsdk{winsdk_version}_{target}",
    flag_values = {{"//winsdk:winsdk": "{winsdk_version}"}},
    constraint_values = ["@platforms//cpu:{target_arch}"],
)
""".format(winsdk_version = winsdk_version, target = target, target_arch = target_arch)

    msvc_cfg = ""
    for msvc_version in msvc_versions:
        for target in targets:
            target_arch = convert_msvc_arch_to_bazel_arch(target)
            msvc_cfg += """config_setting(
    name = "msvc{msvc_version}_{target}",
    flag_values = {{"//msvc:msvc": "{msvc_version}"}},
    constraint_values = ["@platforms//cpu:{target_arch}"],
)
""".format(msvc_version = msvc_version, target = target, target_arch = target_arch)

    # --- cc_import system libraries (kernel32, user32, msvcrt, ...) ---
    winsdk_libs = {}
    msvc_libs = {}

    for winsdk_version in winsdk_versions:
        for target in targets:
            config_name = ":winsdk{}_{}".format(winsdk_version, target)
            for lib_name in ucrt_lib:
                _add_lib_variant(
                    winsdk_libs,
                    lib_name,
                    config_name,
                    "@winsdk_{}//:Lib/10.0.{}.0/ucrt/{}/{}".format(winsdk_version, winsdk_version, target, lib_name),
                )
            for lib_name in um_lib:
                _add_lib_variant(
                    winsdk_libs,
                    lib_name,
                    config_name,
                    "@winsdk_{}//:Lib/10.0.{}.0/um/{}/{}".format(winsdk_version, winsdk_version, target, lib_name),
                )

    for msvc_version in msvc_versions:
        for target in targets:
            config_name = ":msvc{}_{}".format(msvc_version, target)
            for lib_name in msvc_lib:
                _add_lib_variant(
                    msvc_libs,
                    _normalize_lib_name(lib_name),
                    config_name,
                    "@msvc_{}//:Tools/lib/{}/{}".format(msvc_version, target, lib_name.lower()),
                )

    # --- optional ATL libs (cc_import targets), gated on `extra_msvc_packages = ["atl"]` ---
    # Mirrors the system-libs UX documented in the project README:
    # `cc_library(deps = ["@msvc_toolchains//msvc/lib:atls"])` rather than
    # bare-name linkopts + /LIBPATH:. atls is the only ATL static lib
    # currently shipped by the Microsoft.VC.<v>.ATL.<arch>.base.vsix payload
    # at Tools/atlmfc/lib/<arch>/atls.lib. Additional variants (atld.lib,
    # atlsn.lib, atlsnd.lib) can be added here if a future SDK ships them.
    if "atl" in extra_msvc_packages:
        for msvc_version in msvc_versions:
            for target in targets:
                config_name = ":msvc{}_{}".format(msvc_version, target)
                _add_lib_variant(
                    msvc_libs,
                    "atls",
                    config_name,
                    "@msvc_{}//:Tools/atlmfc/lib/{}/atls.lib".format(msvc_version, target),
                )

    def _cc_imports(lib_map):
        out = ""
        for lib_name in sorted(lib_map.keys()):
            variants = lib_map[lib_name]
            out += "\ncc_import(\n    name = \"{}\",\n    interface_library = select({{\n".format(_normalize_lib_name(lib_name))
            for config_name in sorted(variants.keys()):
                out += "        \"{}\": \"{}\",\n".format(config_name, variants[config_name])
            out += "    }),\n    system_provided = True,\n)\n"
        return out

    # --- runtime-link file targets (used by toolchain link args) ---
    def _rt_winsdk(out):
        rt = {
            "ucrt": "ucrt.lib",
            "ucrtd": "ucrtd.lib",
            "libucrt": "libucrt.lib",
            "libucrtd": "libucrtd.lib",
        }
        for name in sorted(rt.keys()):
            file_name = rt[name]
            for target in targets:
                srcs = _select_list(
                    "winsdk",
                    winsdk_versions,
                    lambda v, target = target, file_name = file_name: "@winsdk_{}//:Lib/10.0.{}.0/ucrt/{}/{}".format(v, v, target, file_name),
                )
                out += "\nfilegroup(\n    name = \"rt_{}_{}\",\n    srcs = {},\n)\n".format(name, target, srcs)
        return out

    def _rt_msvc(out):
        rt = [
            "msvcrt",
            "msvcrtd",
            "vcruntime",
            "vcruntimed",
            "msvcprt",
            "msvcprtd",
            "libvcruntime",
            "libvcruntimed",
            "libcmt",
            "libcmtd",
            "libcpmt",
            "libcpmtd",
        ]
        for name in rt:
            for target in targets:
                srcs = _select_list(
                    "msvc",
                    msvc_versions,
                    lambda v, target = target, name = name: "@msvc_{}//:Tools/lib/{}/{}.lib".format(v, target, name),
                )
                out += "\nfilegroup(\n    name = \"rt_{}_{}\",\n    srcs = {},\n)\n".format(name, target, srcs)
        return out

    winsdk_content = """load("@rules_cc//cc:defs.bzl", "cc_import")

package(default_visibility = ["//visibility:public"])

""" + winsdk_cfg + _cc_imports(winsdk_libs)
    winsdk_content = _rt_winsdk(winsdk_content)
    ctx.file("winsdk/lib/BUILD.bazel", winsdk_content)

    msvc_content = """load("@rules_cc//cc:defs.bzl", "cc_import")

package(default_visibility = ["//visibility:public"])

""" + msvc_cfg + _cc_imports(msvc_libs)
    msvc_content = _rt_msvc(msvc_content)
    ctx.file("msvc/lib/BUILD.bazel", msvc_content)

def _msvc_toolchains_repo_impl(ctx):
    # Install common.bzl (string_enum_flag) at repo root
    ctx.template("common.bzl", ctx.attr.src_common, {})

    group_configs = json.decode(ctx.attr.group_configs)
    msvc_versions = ctx.attr.msvc_versions
    llvm_versions = ctx.attr.llvm_versions
    winsdk_versions = ctx.attr.winsdk_versions
    targets = ctx.attr.targets
    hosts = ctx.attr.hosts

    default_msvc_value = ctx.attr.default_msvc_version
    default_winsdk_value = ctx.attr.default_windows_sdk_version
    default_llvm_value = ctx.attr.default_clang_version if ctx.attr.default_clang_version else "unknown"
    default_compiler_value = ctx.attr.default_compiler
    default_toolchain_set_value = ctx.attr.default_toolchain_set

    root_build_file_content = """
package(default_visibility = ["//visibility:public"])
"""

    for group in group_configs:
        group_name = group["name"]
        group_prefix = _toolchain_set_prefix(group_name)
        features_package = "//{}".format(group_prefix + "/features")
        args_package = "//{}".format(group_prefix + "/args")
        artifacts_package = "//{}".format(group_prefix + "/artifacts")

        ctx.template(
            "{}/features/msvc/BUILD.bazel".format(group_prefix),
            ctx.attr.src_features,
            substitutions = {
                "{COMPILER_KIND}": "msvc",
                "{features_package}": features_package,
                "{args_package}": args_package,
            },
        )
        ctx.template(
            "{}/features/clang/BUILD.bazel".format(group_prefix),
            ctx.attr.src_features,
            substitutions = {
                "{COMPILER_KIND}": "clang",
                "{features_package}": features_package,
                "{args_package}": args_package,
            },
        )

        msvc_flags_content = ""
        msvc_flags_content = _append_list_line(msvc_flags_content, "default_c_compile_flags", group["msvc_default_c_compile_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "default_cxx_compile_flags", group["msvc_default_cxx_compile_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "default_link_flags", group["msvc_default_link_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "dbg_c_compile_flags", group["msvc_dbg_c_compile_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "dbg_cxx_compile_flags", group["msvc_dbg_cxx_compile_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "dbg_link_flags", group["msvc_dbg_link_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "fastbuild_c_compile_flags", group["msvc_fastbuild_c_compile_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "fastbuild_cxx_compile_flags", group["msvc_fastbuild_cxx_compile_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "fastbuild_link_flags", group["msvc_fastbuild_link_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "opt_c_compile_flags", group["msvc_opt_c_compile_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "opt_cxx_compile_flags", group["msvc_opt_cxx_compile_flags"])
        msvc_flags_content = _append_list_line(msvc_flags_content, "opt_link_flags", group["msvc_opt_link_flags"])
        ctx.file("{}/args/msvc/flags.bzl".format(group_prefix), msvc_flags_content)

        clang_flags_content = ""
        clang_flags_content = _append_list_line(clang_flags_content, "default_c_compile_flags", group["clang_default_c_compile_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "default_cxx_compile_flags", group["clang_default_cxx_compile_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "default_link_flags", group["clang_default_link_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "dbg_c_compile_flags", group["clang_dbg_c_compile_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "dbg_cxx_compile_flags", group["clang_dbg_cxx_compile_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "dbg_link_flags", group["clang_dbg_link_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "fastbuild_c_compile_flags", group["clang_fastbuild_c_compile_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "fastbuild_cxx_compile_flags", group["clang_fastbuild_cxx_compile_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "fastbuild_link_flags", group["clang_fastbuild_link_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "opt_c_compile_flags", group["clang_opt_c_compile_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "opt_cxx_compile_flags", group["clang_opt_cxx_compile_flags"])
        clang_flags_content = _append_list_line(clang_flags_content, "opt_link_flags", group["clang_opt_link_flags"])
        ctx.file("{}/args/clang/flags.bzl".format(group_prefix), clang_flags_content)

        features_content = ""
        features_content = _append_list_line(features_content, "default_implied_features", group["default_features"], item_prefix = ":")
        features_content = _append_list_line(features_content, "dbg_implied_features", group["dbg_implies_features"], item_prefix = ":")
        features_content = _append_list_line(features_content, "fastbuild_implied_features", group["fastbuild_implies_features"], item_prefix = ":")
        features_content = _append_list_line(features_content, "opt_implied_features", group["opt_implies_features"], item_prefix = ":")
        ctx.file("{}/features/features.bzl".format(group_prefix), features_content)
        ctx.file("{}/features/BUILD.bazel".format(group_prefix), """package(default_visibility = ["//visibility:public"])
""")

        ctx.template(
            "{}/args/msvc/BUILD.bazel".format(group_prefix),
            ctx.attr.src_args_msvc,
            substitutions = {
                "{COMPILER_KIND}": "msvc",
                "{features_package}": features_package,
            },
        )
        ctx.template(
            "{}/args/clang/BUILD.bazel".format(group_prefix),
            ctx.attr.src_args_clang,
            substitutions = {
                "{COMPILER_KIND}": "clang",
                "{features_package}": features_package,
            },
        )
        ctx.template(
            "{}/artifacts/BUILD.bazel".format(group_prefix),
            ctx.attr.src_artifacts,
        )

        group_msvc_versions = group["msvc_versions"]
        group_llvm_versions = group["llvm_versions"]
        group_winsdk_versions = group["winsdk_versions"]
        group_targets = group["targets"]
        group_hosts = group["hosts"]
        cl_with_lld_version = group["cl_with_lld_version"]

        # The MSVC compatibility version varies by the selected MSVC version, so
        # it cannot be a label - emit a select() over //msvc for clang/clang-cl.
        ms_compat_select = "select({\n" + "".join([
            "        \"//msvc:{}\": [\"-fms-compatibility-version={}\"],\n".format(
                v,
                msvc_version_to_cl_internal_version(v),
            )
            for v in group_msvc_versions
        ]) + "    })"

        for host in group_hosts:
            host_arch = convert_msvc_arch_to_bazel_arch(host)
            for target in group_targets:
                target_arch = convert_msvc_arch_to_bazel_arch(target)
                suffix = "host{}_target{}".format(host, target)

                # --- msvc-cl ---
                if cl_with_lld_version:
                    lld_link_llvm_repo = "llvm_{}_{}".format(cl_with_lld_version, host)
                    link_cc_tool = """cc_tool(
    name = "link",
    src = "@{llvm_repo}//:lld-link_{suffix}",
    data = [
        "@{llvm_repo}//:lld_link_exe_only_{suffix}",
    ],
)""".format(llvm_repo = lld_link_llvm_repo, suffix = suffix)
                    base_link_flags = """base_link_flags = [
    "/lldignoreenv",
    "/NODEFAULTLIB",
    "/INCREMENTAL:NO",
    "/PDBALTPATH:%_PDB%",
    "/Brepro",
    "/pdbsourcepath:.",
]"""
                else:
                    link_cc_tool = """cc_tool(
    name = "link",
    src = "//msvc/bin:link_{suffix}",
    data = [
        "//msvc/bin:all_binaries_{suffix}",
    ],
)""".format(suffix = suffix)
                    base_link_flags = """base_link_flags = [
    "/nologo",
    "/NODEFAULTLIB",
    "/INCREMENTAL:NO",
    "/experimental:deterministic",
    "/Brepro",
    "/PDBALTPATH:%_PDB%",
]"""

                msvc_toolchain_name = "{}_msvc-cl_{}".format(group_name, suffix)
                ctx.template(
                    "{}/toolchain/{}/BUILD.bazel".format(group_prefix, msvc_toolchain_name),
                    ctx.attr.src_toolchain_msvc,
                    substitutions = {
                        "{toolchain_name}": msvc_toolchain_name,
                        "{compiler}": "msvc-cl",
                        "{link_cc_tool}": link_cc_tool,
                        "{base_link_flags}": base_link_flags,
                        "{target}": target,
                        "{host}": host,
                        "{suffix}": suffix,
                        "{artifacts_package}": artifacts_package,
                        "{features_package}": features_package,
                    },
                )
                root_build_file_content += _toolchain_registration(
                    msvc_toolchain_name,
                    group_name,
                    "msvc-cl",
                    group_prefix,
                    host_arch,
                    target_arch,
                    llvm_version = None,
                )

                # --- clang / clang-cl (require LLVM, no x86 host) ---
                if not group_llvm_versions or host == "x86":
                    continue

                clang_target = convert_msvc_arch_to_clang_target(target)

                for compiler, src_attr in [("clang", ctx.attr.src_toolchain_clang), ("clang-cl", ctx.attr.src_toolchain_clang_cl)]:
                    tc_name = "{}_{}_{}".format(group_name, compiler, suffix)
                    ctx.template(
                        "{}/toolchain/{}/BUILD.bazel".format(group_prefix, tc_name),
                        src_attr,
                        substitutions = {
                            "{toolchain_name}": tc_name,
                            "{compiler}": compiler,
                            "{clang_target}": clang_target,
                            "{ms_compat_version_select}": ms_compat_select,
                            "{target}": target,
                            "{host}": host,
                            "{suffix}": suffix,
                            "{artifacts_package}": artifacts_package,
                            "{features_package}": features_package,
                        },
                    )
                    root_build_file_content += _toolchain_registration(
                        tc_name,
                        group_name,
                        compiler,
                        group_prefix,
                        host_arch,
                        target_arch,
                        llvm_version = True,
                    )

    ctx.file("BUILD.bazel", root_build_file_content)

    # Version-selection flag packages.
    _emit_flag_package(ctx, "winsdk", winsdk_versions, default_winsdk_value)
    _emit_flag_package(ctx, "msvc", msvc_versions, default_msvc_value)
    _emit_flag_package(ctx, "llvm", llvm_versions, default_llvm_value)

    ctx.file("toolchain_set/BUILD.bazel", """load("//:common.bzl", "string_enum_flag")

package(default_visibility = ["//visibility:public"])

string_enum_flag(
    name = "toolchain_set",
    build_setting_default = "{default_toolchain_set}",
    allowed_values = {allowed_toolchain_sets},
)

{config_settings}
""".format(
        default_toolchain_set = default_toolchain_set_value,
        allowed_toolchain_sets = ctx.attr.toolchain_sets,
        config_settings = "\n".join([
            """config_setting(
    name = "{v}",
    flag_values = {{"//toolchain_set": "{v}"}},
)""".format(v = v)
            for v in ctx.attr.toolchain_sets
        ]),
    ))

    compiler_build_file = """load("//:common.bzl", "string_enum_flag")

package(default_visibility = ["//visibility:public"])

string_enum_flag(
    name = "compiler",
    build_setting_default = "{default_compiler}",
    allowed_values = [
        "msvc-cl",
        "clang-cl",
        "clang",
    ],
)

{config_settings}
""".format(
        default_compiler = default_compiler_value,
        config_settings = "\n".join([
            """config_setting(
    name = "{v}",
    flag_values = {{":compiler": "{v}"}},
)""".format(v = v)
            for v in ["msvc-cl", "clang-cl", "clang"]
        ]),
    )
    ctx.file("compiler/BUILD.bazel", compiler_build_file)

    # Facade packages.
    _emit_llvm_facades(ctx, llvm_versions, hosts, targets)
    _emit_msvc_facades(ctx, msvc_versions, hosts, targets)
    _emit_winsdk_facades(ctx, winsdk_versions, hosts)
    _emit_lib_packages(ctx, msvc_versions, winsdk_versions, targets, ctx.attr.extra_msvc_packages)

    return ctx.repo_metadata(reproducible = True)

def _emit_flag_package(ctx, name, versions, default_value):
    ctx.file("{}/BUILD.bazel".format(name), """load("//:common.bzl", "string_enum_flag")

package(default_visibility = ["//visibility:public"])

string_enum_flag(
    name = "{name}",
    build_setting_default = "{default}",
    allowed_values = {allowed},
)

{config_settings}
""".format(
        name = name,
        default = default_value,
        allowed = versions,
        config_settings = "\n".join([
            """config_setting(
    name = "{v}",
    flag_values = {{":{name}": "{v}"}},
)""".format(v = v, name = name)
            for v in versions
        ]),
    ))

def _toolchain_registration(toolchain_name, group_name, compiler, group_prefix, host_arch, target_arch, llvm_version):
    settings = [
        "\"//toolchain_set:{}\"".format(group_name),
        "\"//compiler:{}\"".format(compiler),
    ]
    return """
toolchain(
    name = "{toolchain_name}",
    exec_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:{host_arch}",
    ],
    target_compatible_with = [
        "@platforms//os:windows",
        "@platforms//cpu:{target_arch}",
    ],
    target_settings = [
        {settings},
    ],
    toolchain = "//{group_prefix}/toolchain/{toolchain_name}:cc_toolchain",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)

""".format(
        toolchain_name = toolchain_name,
        host_arch = host_arch,
        target_arch = target_arch,
        settings = ",\n        ".join(settings),
        group_prefix = group_prefix,
    )

msvc_toolchains_repo = repository_rule(
    implementation = _msvc_toolchains_repo_impl,
    attrs = {
        "group_configs": attr.string(mandatory = True),
        "toolchain_sets": attr.string_list(mandatory = True),
        "default_toolchain_set": attr.string(mandatory = True),
        "msvc_versions": attr.string_list(mandatory = True),
        "llvm_versions": attr.string_list(mandatory = True),
        "winsdk_versions": attr.string_list(mandatory = True),
        "targets": attr.string_list(mandatory = True),
        "hosts": attr.string_list(mandatory = True),
        "extra_msvc_packages": attr.string_list(default = []),
        "default_msvc_version": attr.string(mandatory = True),
        "default_clang_version": attr.string(mandatory = False),
        "default_windows_sdk_version": attr.string(mandatory = True),
        "default_compiler": attr.string(mandatory = True),
        "src_features": attr.label(default = Label("//overlays/toolchain:BUILD.features.tpl"), allow_single_file = True),
        "src_artifacts": attr.label(default = Label("//overlays/toolchain:BUILD.artifacts.bazel"), allow_single_file = True),
        "src_args_msvc": attr.label(default = Label("//overlays/toolchain:BUILD.args-msvc.tpl"), allow_single_file = True),
        "src_args_clang": attr.label(default = Label("//overlays/toolchain:BUILD.args-clang.tpl"), allow_single_file = True),
        "src_toolchain_msvc": attr.label(default = Label("//overlays/toolchain/msvc-cl:BUILD.toolchain.tpl"), allow_single_file = True),
        "src_toolchain_clang": attr.label(default = Label("//overlays/toolchain/clang:BUILD.toolchain.tpl"), allow_single_file = True),
        "src_toolchain_clang_cl": attr.label(default = Label("//overlays/toolchain/clang-cl:BUILD.toolchain.tpl"), allow_single_file = True),
        "src_common": attr.label(default = Label("//overlays:common.bzl"), allow_single_file = True),
    },
)
