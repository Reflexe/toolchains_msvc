"""Repository rule for downloading MSVC compiler artifacts."""

def _package_url(package_urls, pkg):
    sha256 = pkg.get("sha256")
    url = package_urls.get(sha256)
    if not url:
        fail("Missing URL for MSVC package '{}' ({})".format(pkg.get("filename"), sha256))
    return url

def _msvc_repo_impl(ctx):
    """Implementation of the msvc_repo rule."""
    if ctx.attr.error:
        fail(ctx.attr.error)

    packages = json.decode(ctx.attr.packages)
    package_urls = json.decode(ctx.attr.package_urls)
    extracted_package_filenames = []

    for pkg in packages:
        sha256 = pkg.get("sha256")
        filename = pkg.get("filename")

        ctx.report_progress("Downloading and Extracting {}".format(filename))

        ctx.download_and_extract(
            url = _package_url(package_urls, pkg),
            sha256 = sha256,
            output = "tmp",
            type = "zip",
        )

        extracted_package_filenames.append(filename)

    ctx.file(
        "package.txt",
        "\n".join(extracted_package_filenames) + ("\n" if extracted_package_filenames else ""),
    )

    tools_dir = ctx.path("tmp/Contents/VC/Tools/MSVC").readdir()[0]
    redist_dir = ctx.path("tmp/Contents/VC/Redist/MSVC").readdir()[0]

    ctx.execute(["cmd", "/c", "move", str(tools_dir).replace("/", "\\"), "Tools"])
    ctx.execute(["cmd", "/c", "move", str(redist_dir).replace("/", "\\"), "Redist"])
    ctx.delete("tmp")

    # Add cl_wrapper.bat next to cl.exe in every host/target config so EXECROOT can be
    # forwarded to cl.exe via /pathmap:%EXECROOT%=. for reproducible paths.
    cl_wrapper_content = """@echo off
:: %CD% provides the absolute path of the current directory (the execroot)
set EXECROOT=%CD%
"%~dp0cl.exe" /pathmap:%EXECROOT%=. %*
"""
    for host in ctx.attr.hosts:
        for target in ctx.attr.targets:
            ctx.file(
                "Tools/bin/Host{host}/{target}/cl_wrapper.bat".format(host = host, target = target),
                cl_wrapper_content,
            )

    # The Tools/atlmfc/include/ subtree only exists when the caller opts in
    # via `toolchain.toolchain_set(extra_msvc_packages = ["atl"])`. The
    # :atlmfc_include subdirectory() label in BUILD.root.tpl is emitted
    # unconditionally so the cc_args templated formats in
    # overlays/toolchain/{msvc-cl,clang-cl,clang}/BUILD.toolchain.tpl
    # resolve regardless of opt-in (bazel_skylib's subdirectory() rule
    # validates the path against the globbed file tree). When not opted
    # in, the directory is empty; an empty placeholder file keeps the
    # subdirectory() label resolvable and cl.exe silently ignores
    # /external:I paths that contain no headers, so non-opted-in builds
    # see no behavior change. The Tools/atlmfc/lib/ side is gated
    # entirely by the cc_import emission in
    # private/msvc_toolchains_repo.bzl (no facade label exists when not
    # opted in), so no placeholder is needed there.
    atlmfc_include = "Tools/atlmfc/include"
    if not ctx.path(atlmfc_include).exists:
        ctx.file("{}/.placeholder".format(atlmfc_include), "")

    # Generate a BUILD file
    ctx.template(
        "BUILD.bazel",
        ctx.attr.src_build,
    )

    return ctx.repo_metadata(reproducible = True)

msvc_repo = repository_rule(
    implementation = _msvc_repo_impl,
    attrs = {
        "packages": attr.string(mandatory = True, doc = "JSON string list of package dicts"),
        "package_urls": attr.string(mandatory = True, doc = "JSON string map from sha256 to URL"),
        "error": attr.string(mandatory = True),
        "hosts": attr.string_list(doc = "Host architectures"),
        "targets": attr.string_list(doc = "Target architectures"),
        "src_build": attr.label(default = Label("//overlays/msvc:BUILD.root.tpl"), allow_single_file = True, doc = "Label to BUILD.root.tpl"),
    },
)
