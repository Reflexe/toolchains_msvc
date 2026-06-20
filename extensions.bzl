"""Bazel module extension for `toolchains_msvc` (MSVC, Windows SDK, and LLVM).

Fetch MSVC / WinSDK / LLVM packages, and declare toolchains according to `toolchain.toolchain_set(...)` blocks.

Typical `MODULE.bazel` pattern:

```
toolchain = use_extension("@toolchains_msvc//:extensions.bzl", "toolchain")
toolchain.toolchain_set(
    name = "main",
    msvc_versions = ["..."],
    winsdk_versions = ["..."],
)
use_repo(toolchain, "msvc_toolchains")
register_toolchains("@msvc_toolchains//:all")
```

Environment:

* ``BAZEL_TOOLCHAINS_MSVC_HOSTS`` — comma-separated list of hosts, used if ``hosts`` is omitted on a set.
* ``BAZEL_TOOLCHAINS_MSVC_TARGETS`` — comma-separated list of targets, used if ``targets`` is omitted.
"""

load(
    "//private:flags.bzl",
    "CLANG_CXX_COMPILE_FLAGS_DEFAULT",
    "CLANG_C_COMPILE_FLAGS_DEFAULT",
    "CLANG_DBG_CXX_COMPILE_FLAGS_DEFAULT",
    "CLANG_DBG_C_COMPILE_FLAGS_DEFAULT",
    "CLANG_DBG_LINK_FLAGS_DEFAULT",
    "CLANG_FASTBUILD_CXX_COMPILE_FLAGS_DEFAULT",
    "CLANG_FASTBUILD_C_COMPILE_FLAGS_DEFAULT",
    "CLANG_FASTBUILD_LINK_FLAGS_DEFAULT",
    "CLANG_LINK_FLAGS_DEFAULT",
    "CLANG_OPT_CXX_COMPILE_FLAGS_DEFAULT",
    "CLANG_OPT_C_COMPILE_FLAGS_DEFAULT",
    "CLANG_OPT_LINK_FLAGS_DEFAULT",
    "CL_CXX_COMPILE_FLAGS_DEFAULT",
    "CL_C_COMPILE_FLAGS_DEFAULT",
    "CL_DBG_CXX_COMPILE_FLAGS_DEFAULT",
    "CL_DBG_C_COMPILE_FLAGS_DEFAULT",
    "CL_DBG_LINK_FLAGS_DEFAULT",
    "CL_FASTBUILD_CXX_COMPILE_FLAGS_DEFAULT",
    "CL_FASTBUILD_C_COMPILE_FLAGS_DEFAULT",
    "CL_FASTBUILD_LINK_FLAGS_DEFAULT",
    "CL_LINK_FLAGS_DEFAULT",
    "CL_OPT_CXX_COMPILE_FLAGS_DEFAULT",
    "CL_OPT_C_COMPILE_FLAGS_DEFAULT",
    "CL_OPT_LINK_FLAGS_DEFAULT",
    "merge_flags",
)
load("//private:llvm_repo.bzl", "llvm_repo")
load("//private:msvc_repo.bzl", "msvc_repo")
load("//private:msvc_toolchains_repo.bzl", "msvc_toolchains_repo")
load(
    "//private:vs_channel_manifest.bzl",
    "KNOWN_EXTRA_PACKAGES",
    "VALID_MSVC_HOSTS",
    "VALID_MSVC_TARGETS",
    "download_and_map",
    "get_msvc_package_ids",
    "get_msvc_redist_package_ids",
    "get_winsdk_msi_list",
    "get_winsdk_package_id",
    "list_clang_version",
    "list_msvc_redist_version",
    "list_msvc_version",
    "list_winsdk_version",
)
load("//private:common.bzl", "normalize_repository_os")
load("//private:msiutil_repo.bzl", "msiutil_repo")
load("//private:winsdk_repo.bzl", "winsdk_repo")

# Keys select which VS channel manifest is used ("17" vs "18"); values are aka.ms URLs.
CHANNEL_URL = {
    "18": "https://aka.ms/vs/stable/channel",
    "17": "https://aka.ms/vs/17/release/channel",
}

def _find_closest_redist_version(msvc_version, redist_versions_dict):
    """Pick a MSVC redistributable version compatible with the given MSVC toolset version.

    Args:
        msvc_version: MSVC version string (e.g. ``"14.44"``).
        redist_versions_dict: Map from redist version string to VS channel map key.

    Returns:
        A ``(redist_version, package_map_key)`` pair for manifest lookups.
    """
    redist_versions = redist_versions_dict.keys()
    target_v_parts = msvc_version.split(".")[:2]
    target_v = (int(target_v_parts[0]), int(target_v_parts[1]))

    closest_redist = None
    closest_diff = None
    for rv in redist_versions:
        rv_parts = rv.split(".")
        v = (int(rv_parts[0]), int(rv_parts[1]))

        # Starlark doesn't support >= for tuples, check elements manually
        is_greater_or_equal = v[0] > target_v[0] or (v[0] == target_v[0] and v[1] >= target_v[1])
        if is_greater_or_equal:
            diff_0 = v[0] - target_v[0]
            diff_1 = v[1] - target_v[1]
            if closest_diff == None:
                closest_diff = (diff_0, diff_1)
                closest_redist = rv
            elif diff_0 < closest_diff[0] or (diff_0 == closest_diff[0] and diff_1 < closest_diff[1]):
                closest_redist = rv

    if not closest_redist and redist_versions:
        # Fallback to the latest available redist version if no upper is found
        closest_redist = sorted(redist_versions)[-1]

    if not closest_redist:
        fail("No MSVC redist version could be determined for MSVC version {}".format(msvc_version))

    return (closest_redist, redist_versions_dict[closest_redist])

def _unique_values(values):
    """Returns ``values`` without duplicates, preserving first-seen order."""
    seen = {}
    result = []
    for value in values:
        if value not in seen:
            seen[value] = True
            result.append(value)
    return result

def _env_list(module_ctx, env_var):
    """Parses a comma-separated environment variable into a list of non-empty strings.

    Args:
        module_ctx: The module extension context.
        env_var: Name of the environment variable.

    Returns:
        A list of stripped segments, or an empty list if unset/blank.
    """
    value = module_ctx.os.environ.get(env_var, "").strip()
    if not value:
        return []
    return _unique_values([item.strip() for item in value.split(",") if item.strip()])

def _resolve_group_axis(module_ctx, explicit_values, env_var, fallback):
    """Resolves a host/target axis: tag list wins, then ``env_var``, then ``fallback``.

    Args:
        module_ctx: The module extension context (used to read environment variables).
        explicit_values: List of values provided directly on the tag; used as-is if non-empty.
        env_var: Name of the environment variable to parse when ``explicit_values`` is empty.
        fallback: Default list returned when both ``explicit_values`` and ``env_var`` are absent.

    Returns:
        De-duplicated list of resolved values in their original priority order.
    """
    if explicit_values:
        return _unique_values(explicit_values)
    env_values = _env_list(module_ctx, env_var)
    if env_values:
        return env_values
    return fallback

def _validate_toolchain_set_name(name):
    """Fails if ``name`` is empty or contains characters unsafe in labels or paths."""
    if not name:
        fail("toolchain_set name must not be empty.")
    for invalid_char in ["/", "\\", ":", "@", " "]:
        if invalid_char in name:
            fail("Invalid toolchain_set name '{}': must not contain '{}'.".format(name, invalid_char))

def _sort_packages(packages):
    """Sorts package dicts by ``filename`` then ``sha256`` for deterministic ordering."""
    return sorted(packages, key = lambda pkg: "{}\n{}".format(pkg["filename"], pkg["sha256"]))

def _register_package_url(all_packages_url, sha256, url):
    """Records the first URL seen for a package digest (deduplicated by ``sha256``)."""
    existing = all_packages_url.get(sha256)
    if existing == None:
        all_packages_url[sha256] = url
        return

def _package_urls_for_repo(all_packages_url, packages):
    """Builds a ``sha256 -> url`` map for the given package list."""
    package_urls = {}
    for pkg in packages:
        sha256 = pkg["sha256"]
        url = all_packages_url.get(sha256)
        if url == None:
            fail("Missing URL for package digest '{}' (file '{}')".format(sha256, pkg["filename"]))
        package_urls[sha256] = url
    return package_urls

def _llvm_package_filename(version, host):
    """Official LLVM release tarball basename for ``version`` and Windows ``host`` (``x64`` or ``arm64``)."""
    if host == "x64":
        llvm_arch = "x86_64"
    elif host == "arm64":
        llvm_arch = "aarch64"
    else:
        fail("Unsupported LLVM host architecture for package filename: {}".format(host))
    return "clang+llvm-{}-{}-pc-windows-msvc.tar.xz".format(version, llvm_arch)

def _register_repo_definition(repos, repo):
    """Inserts ``repo`` into ``repos`` by name, or fails on conflicting definitions."""
    name = repo["name"]
    existing = repos.get(name)
    if existing == None:
        repos[name] = repo
        return
    if existing != repo:
        fail("Conflicting definitions for repo '{}': {} != {}".format(name, existing, repo))

def _extension_impl(module_ctx):
    """Module extension implementation: manifests, repos, and toolchains registration.

    Phases:

    1. Download VS channel manifests; enforce EULA if needed.
    2. Parse tags (toolchain sets and defaults).
    3. Resolve per-set MSVC / WinSDK / LLVM versions, hosts, targets, and merged flags.
    4. Build the package-URL map; emit and instantiate LLVM, MSVC, and WinSDK repository rules.
    5. Create the aggregate ``msvc_toolchains`` repository.

    Args:
        module_ctx: Bazel module extension context.

    Returns:
        ``extension_metadata`` marking the toolchains repo as a direct root dependency.
    """
    # 1. Download manifest and map for each channel
    packages_maps = {}
    accept_eula = module_ctx.os.environ.get("BAZEL_TOOLCHAINS_MSVC_ACCEPT_MICROSOFT_VISUAL_STUDIO_BUILDTOOLS_EULA", "").lower()
    accept_eula_error = ""
    for package_map_key, channel_url in CHANNEL_URL.items():
        package_map, license_url = download_and_map(module_ctx, channel_url)
        packages_maps[package_map_key] = package_map

        if not accept_eula_error and accept_eula not in ["1", "true"]:
            accept_eula_error = (
                "You must accept the Microsoft Visual Studio Build Tools License to use this toolchain.\n" +
                "License URL: {}\n\n".format(license_url) +
                "To accept the license, set the environment variable BAZEL_TOOLCHAINS_MSVC_ACCEPT_MICROSOFT_VISUAL_STUDIO_BUILDTOOLS_EULA=1"
            )

    repo_name_value = "msvc_toolchains"
    toolchain_sets = []
    default_toolchain_set_name = None
    global_default_msvc_version = None
    global_default_llvm_version = None
    global_default_winsdk_version = None
    global_default_compiler = None

    for mod in module_ctx.modules:
        for tag in mod.tags.repo_name:
            repo_name_value = tag.name
        for tag in mod.tags.toolchain_set:
            toolchain_sets.append(tag)
        for tag in mod.tags.default_toolchain_set:
            default_toolchain_set_name = tag.name
        for tag in mod.tags.default_msvc_version:
            global_default_msvc_version = tag.version
        for tag in mod.tags.default_llvm_version:
            global_default_llvm_version = tag.version
        for tag in mod.tags.default_winsdk_version:
            global_default_winsdk_version = tag.version
        for tag in mod.tags.default_compiler:
            global_default_compiler = tag.compiler

    if not toolchain_sets:
        fail("At least one toolchain.toolchain_set(...) is required.")

    msvc_versions_dict = list_msvc_version(packages_maps)
    winsdk_versions_dict = list_winsdk_version(packages_maps)
    redist_versions_dict = list_msvc_redist_version(packages_maps)
    clang_versions_dict = None

    group_configs = []
    group_names = []
    group_names_set = {}
    all_targets = []
    all_hosts = []
    all_msvc_versions = []
    all_llvm_versions = []
    all_winsdk_versions = []
    all_extra_msvc_packages = []

    for group in toolchain_sets:
        group_name = group.name
        _validate_toolchain_set_name(group_name)
        if group_name in group_names_set:
            fail("Duplicate toolchain_set name '{}'.".format(group_name))
        group_names_set[group_name] = True
        group_names.append(group_name)

        targets = _resolve_group_axis(module_ctx, group.targets, "BAZEL_TOOLCHAINS_MSVC_TARGETS", ["x64"])
        hosts = _resolve_group_axis(module_ctx, group.hosts, "BAZEL_TOOLCHAINS_MSVC_HOSTS", ["x64"])
        msvc_versions = _unique_values(group.msvc_versions)
        llvm_versions = _unique_values(group.llvm_versions)
        cl_with_lld_version = group.cl_with_lld_version if group.cl_with_lld_version else ""
        winsdk_versions = _unique_values(group.winsdk_versions)
        llvm_repo_versions = _unique_values(llvm_versions + ([cl_with_lld_version] if cl_with_lld_version else []))

        if not msvc_versions or not winsdk_versions:
            fail("toolchain_set '{}' must specify msvc_versions and winsdk_versions.".format(group_name))

        for msvc_version in msvc_versions:
            if msvc_version not in msvc_versions_dict:
                fail("Invalid MSVC version '{}' in toolchain_set '{}'. Valid versions are: {}".format(msvc_version, group_name, msvc_versions_dict.keys()))
        for winsdk_version in winsdk_versions:
            if winsdk_version not in winsdk_versions_dict:
                fail("Invalid Windows SDK version '{}' in toolchain_set '{}'. Valid versions are: {}".format(winsdk_version, group_name, winsdk_versions_dict.keys()))

        if llvm_repo_versions:
            if clang_versions_dict == None:
                clang_versions_dict = list_clang_version(module_ctx)
            for llvm_version in llvm_repo_versions:
                if llvm_version not in clang_versions_dict:
                    fail("Invalid Clang/LLVM version '{}' in toolchain_set '{}'. Valid versions are: {}".format(llvm_version, group_name, clang_versions_dict.keys()))

        for h in hosts:
            if h not in VALID_MSVC_HOSTS:
                fail("Invalid host '{}' in toolchain_set '{}', must be one of: {}".format(h, group_name, VALID_MSVC_HOSTS))
        for t in targets:
            if t not in VALID_MSVC_TARGETS:
                fail("Invalid target '{}' in toolchain_set '{}', must be one of: {}".format(t, group_name, VALID_MSVC_TARGETS))
        for extra in group.extra_msvc_packages:
            if extra not in KNOWN_EXTRA_PACKAGES:
                fail("Invalid extra_msvc_package '{}' in toolchain_set '{}', must be one of: {}".format(extra, group_name, sorted(KNOWN_EXTRA_PACKAGES.keys())))

        all_targets = _unique_values(all_targets + targets)
        all_hosts = _unique_values(all_hosts + hosts)
        all_msvc_versions = _unique_values(all_msvc_versions + msvc_versions)
        all_llvm_versions = _unique_values(all_llvm_versions + llvm_repo_versions)
        all_winsdk_versions = _unique_values(all_winsdk_versions + winsdk_versions)
        all_extra_msvc_packages = _unique_values(all_extra_msvc_packages + group.extra_msvc_packages)

        # Resolve flags (merge defaults with replace/add from each toolchain_set) in the extension.
        msvc_default_c_compile_flags = merge_flags(CL_C_COMPILE_FLAGS_DEFAULT, group.cl_copt, group.add_cl_copt)
        msvc_default_cxx_compile_flags = merge_flags(CL_CXX_COMPILE_FLAGS_DEFAULT, group.cl_cxxopt, group.add_cl_cxxopt)
        msvc_default_link_flags = merge_flags(CL_LINK_FLAGS_DEFAULT, group.cl_linkopt, group.add_cl_linkopt)
        msvc_dbg_c_compile_flags = merge_flags(CL_DBG_C_COMPILE_FLAGS_DEFAULT, group.cl_dbg_copt, group.add_cl_dbg_copt)
        msvc_dbg_cxx_compile_flags = merge_flags(CL_DBG_CXX_COMPILE_FLAGS_DEFAULT, group.cl_dbg_cxxopt, group.add_cl_dbg_cxxopt)
        msvc_dbg_link_flags = merge_flags(CL_DBG_LINK_FLAGS_DEFAULT, group.cl_dbg_linkopt, group.add_cl_dbg_linkopt)
        msvc_fastbuild_c_compile_flags = merge_flags(CL_FASTBUILD_C_COMPILE_FLAGS_DEFAULT, group.cl_fastbuild_copt, group.add_cl_fastbuild_copt)
        msvc_fastbuild_cxx_compile_flags = merge_flags(CL_FASTBUILD_CXX_COMPILE_FLAGS_DEFAULT, group.cl_fastbuild_cxxopt, group.add_cl_fastbuild_cxxopt)
        msvc_fastbuild_link_flags = merge_flags(CL_FASTBUILD_LINK_FLAGS_DEFAULT, group.cl_fastbuild_linkopt, group.add_cl_fastbuild_linkopt)
        msvc_opt_c_compile_flags = merge_flags(CL_OPT_C_COMPILE_FLAGS_DEFAULT, group.cl_opt_copt, group.add_cl_opt_copt)
        msvc_opt_cxx_compile_flags = merge_flags(CL_OPT_CXX_COMPILE_FLAGS_DEFAULT, group.cl_opt_cxxopt, group.add_cl_opt_cxxopt)
        msvc_opt_link_flags = merge_flags(CL_OPT_LINK_FLAGS_DEFAULT, group.cl_opt_linkopt, group.add_cl_opt_linkopt)

        clang_default_c_compile_flags = merge_flags(CLANG_C_COMPILE_FLAGS_DEFAULT, group.clang_copt, group.add_clang_copt)
        clang_default_cxx_compile_flags = merge_flags(CLANG_CXX_COMPILE_FLAGS_DEFAULT, group.clang_cxxopt, group.add_clang_cxxopt)
        clang_default_link_flags = merge_flags(CLANG_LINK_FLAGS_DEFAULT, group.clang_linkopt, group.add_clang_linkopt)
        clang_dbg_c_compile_flags = merge_flags(CLANG_DBG_C_COMPILE_FLAGS_DEFAULT, group.clang_dbg_copt, group.add_clang_dbg_copt)
        clang_dbg_cxx_compile_flags = merge_flags(CLANG_DBG_CXX_COMPILE_FLAGS_DEFAULT, group.clang_dbg_cxxopt, group.add_clang_dbg_cxxopt)
        clang_dbg_link_flags = merge_flags(CLANG_DBG_LINK_FLAGS_DEFAULT, group.clang_dbg_linkopt, group.add_clang_dbg_linkopt)
        clang_fastbuild_c_compile_flags = merge_flags(CLANG_FASTBUILD_C_COMPILE_FLAGS_DEFAULT, group.clang_fastbuild_copt, group.add_clang_fastbuild_copt)
        clang_fastbuild_cxx_compile_flags = merge_flags(CLANG_FASTBUILD_CXX_COMPILE_FLAGS_DEFAULT, group.clang_fastbuild_cxxopt, group.add_clang_fastbuild_cxxopt)
        clang_fastbuild_link_flags = merge_flags(CLANG_FASTBUILD_LINK_FLAGS_DEFAULT, group.clang_fastbuild_linkopt, group.add_clang_fastbuild_linkopt)
        clang_opt_c_compile_flags = merge_flags(CLANG_OPT_C_COMPILE_FLAGS_DEFAULT, group.clang_opt_copt, group.add_clang_opt_copt)
        clang_opt_cxx_compile_flags = merge_flags(CLANG_OPT_CXX_COMPILE_FLAGS_DEFAULT, group.clang_opt_cxxopt, group.add_clang_opt_cxxopt)
        clang_opt_link_flags = merge_flags(CLANG_OPT_LINK_FLAGS_DEFAULT, group.clang_opt_linkopt, group.add_clang_opt_linkopt)

        group_configs.append({
            "name": group_name,
            "targets": targets,
            "hosts": hosts,
            "msvc_versions": msvc_versions,
            "llvm_versions": llvm_versions,
            "winsdk_versions": winsdk_versions,
            "cl_with_lld_version": cl_with_lld_version,
            "msvc_default_c_compile_flags": msvc_default_c_compile_flags,
            "msvc_default_cxx_compile_flags": msvc_default_cxx_compile_flags,
            "msvc_default_link_flags": msvc_default_link_flags,
            "msvc_dbg_c_compile_flags": msvc_dbg_c_compile_flags,
            "msvc_dbg_cxx_compile_flags": msvc_dbg_cxx_compile_flags,
            "msvc_dbg_link_flags": msvc_dbg_link_flags,
            "msvc_fastbuild_c_compile_flags": msvc_fastbuild_c_compile_flags,
            "msvc_fastbuild_cxx_compile_flags": msvc_fastbuild_cxx_compile_flags,
            "msvc_fastbuild_link_flags": msvc_fastbuild_link_flags,
            "msvc_opt_c_compile_flags": msvc_opt_c_compile_flags,
            "msvc_opt_cxx_compile_flags": msvc_opt_cxx_compile_flags,
            "msvc_opt_link_flags": msvc_opt_link_flags,
            "clang_default_c_compile_flags": clang_default_c_compile_flags,
            "clang_default_cxx_compile_flags": clang_default_cxx_compile_flags,
            "clang_default_link_flags": clang_default_link_flags,
            "clang_dbg_c_compile_flags": clang_dbg_c_compile_flags,
            "clang_dbg_cxx_compile_flags": clang_dbg_cxx_compile_flags,
            "clang_dbg_link_flags": clang_dbg_link_flags,
            "clang_fastbuild_c_compile_flags": clang_fastbuild_c_compile_flags,
            "clang_fastbuild_cxx_compile_flags": clang_fastbuild_cxx_compile_flags,
            "clang_fastbuild_link_flags": clang_fastbuild_link_flags,
            "clang_opt_c_compile_flags": clang_opt_c_compile_flags,
            "clang_opt_cxx_compile_flags": clang_opt_cxx_compile_flags,
            "clang_opt_link_flags": clang_opt_link_flags,
            "default_features": group.features,
            "dbg_implies_features": group.dbg_features,
            "fastbuild_implies_features": group.fastbuild_features,
            "opt_implies_features": group.opt_features,
        })

    if default_toolchain_set_name == None:
        default_toolchain_set_name = group_names[0]
    elif default_toolchain_set_name not in group_names_set:
        fail("default_toolchain_set '{}' does not match any declared toolchain_set. Available values: {}".format(default_toolchain_set_name, group_names))

    default_msvc_for_repo = global_default_msvc_version
    if not default_msvc_for_repo:
        default_msvc_for_repo = all_msvc_versions[0]
    elif default_msvc_for_repo not in all_msvc_versions:
        fail("default_msvc_version '{}' is not among the MSVC versions declared across toolchain_sets: {}".format(default_msvc_for_repo, all_msvc_versions))

    default_winsdk_for_repo = global_default_winsdk_version
    if not default_winsdk_for_repo:
        default_winsdk_for_repo = all_winsdk_versions[0]
    elif default_winsdk_for_repo not in all_winsdk_versions:
        fail("default_winsdk_version '{}' is not among the Windows SDK versions declared across toolchain_sets: {}".format(default_winsdk_for_repo, all_winsdk_versions))

    default_llvm_for_repo = global_default_llvm_version
    if not default_llvm_for_repo:
        if all_llvm_versions:
            default_llvm_for_repo = all_llvm_versions[0]
        else:
            default_llvm_for_repo = ""
    elif default_llvm_for_repo not in all_llvm_versions:
        fail("default_llvm_version '{}' is not among the LLVM versions declared across toolchain_sets: {}".format(default_llvm_for_repo, all_llvm_versions))

    default_compiler_for_repo = global_default_compiler if global_default_compiler else "msvc-cl"
    if default_compiler_for_repo in ["clang", "clang-cl"] and not all_llvm_versions:
        fail("default_compiler '{}' requires at least one LLVM version across toolchain_sets (llvm_versions or cl_with_lld_version).".format(default_compiler_for_repo))

    all_packages_url = {}
    for package_map_key in sorted(packages_maps.keys()):
        packages_map = packages_maps[package_map_key]
        for package_id in sorted(packages_map.keys()):
            payloads = packages_map[package_id].get("payloads", [])
            for payload in payloads:
                url = payload.get("url")
                sha256 = payload.get("sha256")
                if url and sha256:
                    _register_package_url(all_packages_url, sha256, url)
    if clang_versions_dict != None:
        for llvm_version in sorted(clang_versions_dict.keys()):
            entry = clang_versions_dict[llvm_version]
            for arch in ["x64", "arm64"]:
                url = entry.get(arch)
                sha256 = entry.get("{}_digest".format(arch))
                if url and sha256:
                    _register_package_url(all_packages_url, sha256, url)

    repos = {}

    # 2. Construct llvm repo definitions (only if llvm versions are defined)
    if all_llvm_versions:
        for llvm_version in all_llvm_versions:
            entry = clang_versions_dict[llvm_version]
            for host in all_hosts:
                if host == "x86":
                    continue  # LLVM does not provide x86 Windows binaries
                digest = entry["x64_digest"] if host == "x64" else entry["arm64_digest"]
                if not digest:
                    fail("Missing digest for LLVM version '{}' host '{}' in {}".format(llvm_version, host, entry))
                _register_repo_definition(repos, {
                    "kind": "llvm",
                    "name": "llvm_{}_{}".format(llvm_version, host),
                    "version": llvm_version,
                    "host": host,
                    "packages": _sort_packages([{
                        "filename": _llvm_package_filename(llvm_version, host),
                        "sha256": digest,
                    }]),
                })

    # 3. Construct all msvc repo definitions
    for msvc_version in all_msvc_versions:
        msvc_package_map_key = msvc_versions_dict[msvc_version]
        msvc_packages_map = packages_maps[msvc_package_map_key]
        deps = get_msvc_package_ids(msvc_packages_map, msvc_version, hosts = all_hosts, targets = all_targets, extra_msvc_packages = all_extra_msvc_packages)

        closest_redist, redist_package_map_key = _find_closest_redist_version(msvc_version, redist_versions_dict)
        redist_packages_map = packages_maps[redist_package_map_key]
        redist_deps = get_msvc_redist_package_ids(redist_packages_map, closest_redist, targets = all_targets)
        deps.extend(redist_deps)

        deps = sorted(deps)

        packages_list = []
        for dep_id in deps:
            pkg = msvc_packages_map.get(dep_id)
            if not pkg:
                pkg = redist_packages_map.get(dep_id)
            if pkg:
                payloads = pkg.get("payloads", [])
                for payload in payloads:
                    if "url" in payload:
                        sha256 = payload.get("sha256")
                        filename = payload.get("fileName")
                        if not sha256 or not filename:
                            fail("MSVC payload in '{}' is missing sha256 or fileName".format(dep_id))
                        packages_list.append({
                            "filename": filename,
                            "sha256": sha256,
                        })

        _register_repo_definition(repos, {
            "kind": "msvc",
            "name": "msvc_{}".format(msvc_version),
            "hosts": all_hosts,
            "targets": all_targets,
            "packages": _sort_packages(packages_list),
        })

    # 4. Construct all winsdk repo definitions
    for winsdk_version in all_winsdk_versions:
        winsdk_package_map_key = winsdk_versions_dict[winsdk_version]
        winsdk_packages_map = packages_maps[winsdk_package_map_key]
        id = get_winsdk_package_id(winsdk_version)
        required_msi_files = get_winsdk_msi_list(all_targets)

        packages_list = []
        pkg = winsdk_packages_map.get(id)
        payloads = pkg.get("payloads", [])
        for payload in payloads:
            if "url" in payload and "fileName" in payload:
                sha256 = payload.get("sha256")
                if not sha256:
                    fail("WinSDK payload for '{}' is missing sha256".format(id))
                raw_filename = payload["fileName"]
                filename = raw_filename
                if raw_filename.startswith("Installers\\"):
                    filename = raw_filename[len("Installers\\"):]
                if filename.endswith(".msi"):
                    for required_msi_file in required_msi_files:
                        if filename.endswith(required_msi_file):
                            packages_list.append({
                                "filename": filename,
                                "sha256": sha256,
                            })
                            break
                elif filename.endswith(".cab"):
                    packages_list.append({
                        "filename": filename,
                        "sha256": sha256,
                    })

        _register_repo_definition(repos, {
            "kind": "winsdk",
            "name": "winsdk_{}".format(winsdk_version),
            "targets": all_targets,
            "packages": _sort_packages(packages_list),
            "winsdk_version": winsdk_version,
        })

    msiutil_repo(name = "msiutil")
    msiutil_label = "@msiutil//:{}".format("msiutil.exe" if normalize_repository_os(module_ctx.os.name) == "windows" else "msiutil")

    for repo_name in sorted(repos.keys()):
        repo = repos[repo_name]
        kind = repo["kind"]
        packages = repo["packages"]
        package_urls = _package_urls_for_repo(all_packages_url, repo["packages"])

        if kind == "llvm":
            llvm_repo(
                name = repo["name"],
                version = repo["version"],
                host = repo["host"],
                packages = json.encode(packages),
                package_urls = json.encode(package_urls),
            )
            continue

        if kind == "msvc":
            msvc_repo(
                name = repo["name"],
                hosts = repo["hosts"],
                targets = repo["targets"],
                packages = json.encode(packages),
                package_urls = json.encode(package_urls),
                error = accept_eula_error,
            )
            continue

        if kind == "winsdk":
            winsdk_repo(
                name = repo["name"],
                # Label string plus intra-extension deferred mapping (not Label(...) at eval time).
                msiutil = msiutil_label,
                targets = repo["targets"],
                packages = json.encode(packages),
                package_urls = json.encode(package_urls),
                winsdk_version = repo["winsdk_version"],
                error = accept_eula_error,
            )
            continue

        fail("Unsupported repo kind '{}' for repo '{}'".format(kind, repo["name"]))

    # 5. Instantiate toolchains repo with resolved toolchain_set configs.
    msvc_toolchains_repo(
        name = repo_name_value,
        group_configs = json.encode(group_configs),
        toolchain_sets = group_names,
        default_toolchain_set = default_toolchain_set_name,
        llvm_versions = all_llvm_versions,
        msvc_versions = all_msvc_versions,
        winsdk_versions = all_winsdk_versions,
        targets = all_targets,
        hosts = all_hosts,
        extra_msvc_packages = all_extra_msvc_packages,
        default_msvc_version = default_msvc_for_repo,
        default_clang_version = default_llvm_for_repo,
        default_windows_sdk_version = default_winsdk_for_repo,
        default_compiler = default_compiler_for_repo,
    )

    direct_deps = [repo_name_value]

    return module_ctx.extension_metadata(
        reproducible = False,
        root_module_direct_deps = direct_deps,
        root_module_direct_dev_deps = [],
    )

repo_name_tag = tag_class(
    doc = "Sets the name of the generated toolchains repository (default is `msvc_toolchains`).",
    attrs = {
        "name": attr.string(
            mandatory = True,
            doc = "Repository name used in `use_repo(toolchain, \"<name>\")` and `@<name>//...` labels.",
        ),
    },
)

toolchain_set_tag = tag_class(
    doc = "Declares a set of toolchains made of the cross-product of MSVC, WinSDK, and optional LLVM versions, hosts, targets, features, and compiler flags.",
    attrs = {
        "name": attr.string(
            mandatory = True,
            doc = "Unique name for this toolchain set; must be a valid label segment (no `/`, `\\`, `:`, `@`, or spaces).",
        ),
        "targets": attr.string_list(
            default = [],
            doc = "List of target architecture, among `x64`, `x86` or `arm64`. If empty, uses `BAZEL_TOOLCHAINS_MSVC_TARGETS` or `x64`.",
        ),
        "hosts": attr.string_list(
            default = [],
            doc = "List of host architecture, value should be among `x64`, `x86` or `arm64`. If empty, uses `BAZEL_TOOLCHAINS_MSVC_HOSTS` or `x64`.",
        ),
        "msvc_versions": attr.string_list(
            default = [],
            doc = "List of enabled MSVC versions. Must have at least one element.",
        ),
        "cl_with_lld_version": attr.string(
            default = "",
            doc = "Optional LLVM version string to pull in `lld-link` for use with `cl` (adds an LLVM repo for that version).",
        ),
        "llvm_versions": attr.string_list(
            default = [],
            doc = "LLVM/Clang versions for `clang` / `clang-cl` based toolchains. Can be empty.",
        ),
        "winsdk_versions": attr.string_list(
            default = [],
            doc = "Windows SDK versions for this toolchain set. Must have at least one element.",
        ),
        "extra_msvc_packages": attr.string_list(
            default = [],
            doc = "Optional MSVC packages to opt into. Currently supported: `atl` (Visual C++ ATL headers and atls.lib, ~30-60 MB compressed per host/target). The opt-in is a union across all `toolchain_set` invocations in the same module graph. When opted in, ATL libs are exposed as `cc_import` targets on the aggregate facade (e.g. `@msvc_toolchains//msvc/lib:atls`).",
        ),
        "features": attr.string_list(
            default = [],
            doc = "Default `features` to be enabled for this toolchain set (Bazel `cc` feature names).",
        ),
        "dbg_features": attr.string_list(
            default = [],
            doc = "Extra `features` enabled when compiling with `-c dbg`.",
        ),
        "fastbuild_features": attr.string_list(
            default = [],
            doc = "Extra `features` enabled when compiling with `-c fastbuild`.",
        ),
        "opt_features": attr.string_list(
            default = [],
            doc = "Extra `features` enabled when compiling with `-c opt`.",
        ),
        "cl_copt": attr.string_list(
            default = [],
            doc = "MSVC `cl` or `clang-cl` C compile options for the default compilation mode; replaces the built-in default list.",
        ),
        "cl_cxxopt": attr.string_list(
            default = [],
            doc = "MSVC `cl` or `clang-cl` C++ compile options for the default mode; replaces the built-in default list.",
        ),
        "cl_linkopt": attr.string_list(
            default = [],
            doc = "MSVC link flags for the default mode; replaces the built-in default list.",
        ),
        "cl_dbg_copt": attr.string_list(
            default = [],
            doc = "MSVC `cl` or `clang-cl` C compile options for `-c dbg`; replaces the dbg defaults.",
        ),
        "cl_dbg_cxxopt": attr.string_list(
            default = [],
            doc = "MSVC `cl` or `clang-cl` C++ compile options for `-c dbg`; replaces the dbg defaults.",
        ),
        "cl_dbg_linkopt": attr.string_list(
            default = [],
            doc = "MSVC link flags for `-c dbg`; replaces the dbg defaults.",
        ),
        "cl_fastbuild_copt": attr.string_list(
            default = [],
            doc = "MSVC `cl` or `clang-cl` C compile options for `-c fastbuild`; replaces fastbuild defaults.",
        ),
        "cl_fastbuild_cxxopt": attr.string_list(
            default = [],
            doc = "MSVC `cl` or `clang-cl` C++ compile options for `-c fastbuild`; replaces fastbuild defaults.",
        ),
        "cl_fastbuild_linkopt": attr.string_list(
            default = [],
            doc = "MSVC link flags for `-c fastbuild`; replaces fastbuild defaults.",
        ),
        "cl_opt_copt": attr.string_list(
            default = [],
            doc = "MSVC `cl` or `clang-cl` C compile options for `-c opt`; replaces opt defaults.",
        ),
        "cl_opt_cxxopt": attr.string_list(
            default = [],
            doc = "MSVC `cl` or `clang-cl` C++ compile options for `-c opt`; replaces opt defaults.",
        ),
        "cl_opt_linkopt": attr.string_list(
            default = [],
            doc = "MSVC link flags for `-c opt`; replaces opt defaults.",
        ),
        "add_cl_copt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC `cl` or `clang-cl` C flags for the default mode (after defaults or `cl_copt` replacement).",
        ),
        "add_cl_cxxopt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC `cl` or `clang-cl` C++ flags for the default mode.",
        ),
        "add_cl_linkopt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC link flags for the default mode.",
        ),
        "add_cl_dbg_copt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC `cl` or `clang-cl` C flags for `-c dbg`.",
        ),
        "add_cl_dbg_cxxopt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC `cl` or `clang-cl` C++ flags for `-c dbg`.",
        ),
        "add_cl_dbg_linkopt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC link flags for `-c dbg`.",
        ),
        "add_cl_fastbuild_copt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC `cl` or `clang-cl` C flags for `-c fastbuild`.",
        ),
        "add_cl_fastbuild_cxxopt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC `cl` or `clang-cl` C++ flags for `-c fastbuild`.",
        ),
        "add_cl_fastbuild_linkopt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC link flags for `-c fastbuild`.",
        ),
        "add_cl_opt_copt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC `cl` or `clang-cl` C flags for `-c opt`.",
        ),
        "add_cl_opt_cxxopt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC `cl` or `clang-cl` C++ flags for `-c opt`.",
        ),
        "add_cl_opt_linkopt": attr.string_list(
            default = [],
            doc = "Appended to the effective MSVC link flags for `-c opt`.",
        ),
        "clang_copt": attr.string_list(
            default = [],
            doc = "Clang C compile options for the default mode; non-empty replaces the built-in default list.",
        ),
        "clang_cxxopt": attr.string_list(
            default = [],
            doc = "Clang C++ compile options for the default mode; non-empty replaces the built-in default list.",
        ),
        "clang_linkopt": attr.string_list(
            default = [],
            doc = "Clang/lld link flags for the default mode; non-empty replaces the built-in default list.",
        ),
        "clang_dbg_copt": attr.string_list(
            default = [],
            doc = "Clang C compile options for `-c dbg`; non-empty replaces dbg defaults.",
        ),
        "clang_dbg_cxxopt": attr.string_list(
            default = [],
            doc = "Clang C++ compile options for `-c dbg`; non-empty replaces dbg defaults.",
        ),
        "clang_dbg_linkopt": attr.string_list(
            default = [],
            doc = "Clang link flags for `-c dbg`; non-empty replaces dbg defaults.",
        ),
        "clang_fastbuild_copt": attr.string_list(
            default = [],
            doc = "Clang C compile options for `-c fastbuild`; non-empty replaces fastbuild defaults.",
        ),
        "clang_fastbuild_cxxopt": attr.string_list(
            default = [],
            doc = "Clang C++ compile options for `-c fastbuild`; non-empty replaces fastbuild defaults.",
        ),
        "clang_fastbuild_linkopt": attr.string_list(
            default = [],
            doc = "Clang link flags for `-c fastbuild`; non-empty replaces fastbuild defaults.",
        ),
        "clang_opt_copt": attr.string_list(
            default = [],
            doc = "Clang C compile options for `-c opt`; non-empty replaces opt defaults.",
        ),
        "clang_opt_cxxopt": attr.string_list(
            default = [],
            doc = "Clang C++ compile options for `-c opt`; non-empty replaces opt defaults.",
        ),
        "clang_opt_linkopt": attr.string_list(
            default = [],
            doc = "Clang link flags for `-c opt`; non-empty replaces opt defaults.",
        ),
        "add_clang_copt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang C flags for the default mode.",
        ),
        "add_clang_cxxopt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang C++ flags for the default mode.",
        ),
        "add_clang_linkopt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang link flags for the default mode.",
        ),
        "add_clang_dbg_copt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang C flags for `-c dbg`.",
        ),
        "add_clang_dbg_cxxopt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang C++ flags for `-c dbg`.",
        ),
        "add_clang_dbg_linkopt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang link flags for `-c dbg`.",
        ),
        "add_clang_fastbuild_copt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang C flags for `-c fastbuild`.",
        ),
        "add_clang_fastbuild_cxxopt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang C++ flags for `-c fastbuild`.",
        ),
        "add_clang_fastbuild_linkopt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang link flags for `-c fastbuild`.",
        ),
        "add_clang_opt_copt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang C flags for `-c opt`.",
        ),
        "add_clang_opt_cxxopt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang C++ flags for `-c opt`.",
        ),
        "add_clang_opt_linkopt": attr.string_list(
            default = [],
            doc = "Appended to the effective Clang link flags for `-c opt`.",
        ),
    },
)

default_toolchain_set_tag = tag_class(
    doc = "Selects which declared `toolchain_set` is the default for the generated repo. Otherwise, the first declared toolchain set is used.",
    attrs = {
        "name": attr.string(
            mandatory = True,
            doc = "Must match the `name` of a `toolchain.toolchain_set` in this extension invocation.",
        ),
    },
)

default_msvc_version_tag = tag_class(
    doc = "Default MSVC toolset version for the aggregate toolchains repository (must appear in some `toolchain_set`).",
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "Must be one of the MSVC versions declared in `toolchain_set`. If the whole `default_msvc_version` tag is omitted, the first MSVC version across sets is used.",
        ),
    },
)

default_llvm_version_tag = tag_class(
    doc = "Default LLVM version when LLVM is used (must appear in at least one `toolchain_set`).",
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "Must be one of the LLVM versions declared in `toolchain_set`. If the whole `default_llvm_version` tag is omitted, the first LLVM version across sets is used when LLVM is enabled.",
        ),
    },
)

default_winsdk_version_tag = tag_class(
    doc = "Default Windows SDK version (must appear in at least one `toolchain_set`).",
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "Must be one of the WinSDK versions declared in `toolchain_set`. If the whole `default_winsdk_version` tag is omitted, the first WinSDK version across sets is used.",
        ),
    },
)

default_compiler_tag = tag_class(
    doc = "Default compiler to be used (`msvc-cl`, `clang-cl`, or `clang`) when resolving toolchains.",
    attrs = {
        "compiler": attr.string(
            mandatory = True,
            values = ["msvc-cl", "clang-cl", "clang"],
            doc = "`msvc-cl` uses MSVC `cl`; `clang-cl` / `clang` require LLVM versions to be declared.",
        ),
    },
)

toolchain = module_extension(
    implementation = _extension_impl,
    doc = "Fetches MSVC, Windows SDK, and optional LLVM artifacts and registers matching C++ toolchains.",
    tag_classes = {
        "repo_name": repo_name_tag,
        "toolchain_set": toolchain_set_tag,
        "default_toolchain_set": default_toolchain_set_tag,
        "default_msvc_version": default_msvc_version_tag,
        "default_llvm_version": default_llvm_version_tag,
        "default_winsdk_version": default_winsdk_version_tag,
        "default_compiler": default_compiler_tag,
    },
    environ = [
        "BAZEL_TOOLCHAINS_MSVC_HOSTS",
        "BAZEL_TOOLCHAINS_MSVC_TARGETS",
        "BAZEL_TOOLCHAINS_MSVC_ACCEPT_MICROSOFT_VISUAL_STUDIO_BUILDTOOLS_EULA",
    ],
)
