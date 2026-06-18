# Implementation Features

Internal features required to make the toolchain work. Not intended for end-users.

---

## Plumbing Features

Required by the `rules_cc` framework to wire compiler/linker/archiver invocations together. Each maps a Bazel toolchain variable to the correct command-line syntax for the compiler.

| Feature                    | Action    | Purpose |
|----------------------------|-----------|---------|
| `no_legacy_features`       | —         | Disables all built-in legacy feature injection from Bazel; the toolchain owns its full feature graph. |
| `compiler_input_flags`     | compile   | Passes the source file path (`-c {source}` / `/c {source}`). |
| `compiler_output_flags`    | compile   | Passes the output object path (`-o {out}` / `/Fo{out}`). |
| `linker_input`             | link      | Iterates `libraries_to_link` and passes each as the appropriate linker input (object files, static libs, DLLs, import libs). |
| `output_execpath_flags`    | link      | Passes the binary output path (`/OUT:{path}`). |
| `linker_param_file`        | link      | Passes a response file (`@{param_file}`) to the linker to work around Windows command-line length limits. |
| `archive_param_file`       | archive   | Same as `linker_param_file` but for the archiver. |
| `compiler_param_file`      | compile   | Same as `linker_param_file` but for the compiler. |
| `archiver_input`           | archive   | Iterates `libraries_to_link` and passes object files to `lib.exe`. |
| `archiver_output`          | archive   | Passes the output `.lib` path (`/OUT:{path}`). |
| `strip_input`              | strip     | Placeholder — no strip action on Windows, but required by the framework. |
| `strip_output`             | strip     | Placeholder — same reason. |

---

## DLL Support

Required for building and consuming shared libraries (`.dll` / `.lib` import libs) on Windows.

| Feature                           | Purpose |
|-----------------------------------|---------|
| `shared_flag`                     | Adds `/DLL` to the linker to produce a DLL instead of an EXE. |
| `interface_library_output_flags`  | Passes `/IMPLIB:{path}` so the linker writes an import library alongside the DLL. |
| `has_configured_linker_path`      | Sentinel feature that tells Bazel the linker path is resolved; required by the `cc_binary` rule for DLL targets. |
| `supports_interface_shared_libraries` | Declares to Bazel that this toolchain can produce interface (import) libraries. |
| `targets_windows`                 | Marks the toolchain as targeting Windows, enabling Windows-specific rule paths in `rules_cc`. |
| `copy_dynamic_libraries_to_binary` | Instructs Bazel to copy `.dll` runfiles next to the final binary so it can run without `PATH` manipulation. |

---

## Header Dependency Discovery

Tells Bazel which mechanism to use to discover `#include` dependencies for incremental rebuilds.

| Feature              | Compiler       | Purpose |
|----------------------|----------------|---------|
| `parse_showincludes` | cl, clang-cl   | Passes `/showIncludes` and sets `VSLANG=1033` (English output) so Bazel can parse the include list from compiler stdout. |
| `no_dotd_file`       | cl, clang-cl   | Disables `.d` file generation; `parse_showincludes` is used instead. |
| `dependency_file`    | clang          | Passes `-MD -MF {dep_file}` to produce a Make-style `.d` dependency file. |

---

## Toolchain Policy Defaults

Always-enabled features that inject the toolchain's baseline flags into every action. These flags come from the `toolchain_set` configuration and can be overridden per toolchain set.

| Feature                  | Action    | Purpose |
|--------------------------|-----------|---------|
| `default_flags`          | varies    | Umbrella feature that pulls in `default_cxx_compile_flags`, `default_c_compile_flags`, `default_assemble_flags`, `default_link_flags`, `default_archive_flags`, `default_strip_flags`. |
| `all_runtime_flags`      | compile   | Umbrella feature that injects the correct CRT flag (`/MD`, `/MT`, `/MDd`, `/MTd`) based on the active `static_runtime` / `debug_runtime` combination via feature constraints. |
| `all_subsystem_flags`    | link      | Umbrella feature that injects `/SUBSYSTEM:WINDOWS` or `/SUBSYSTEM:CONSOLE` based on the active subsystem feature. Defaults to console when neither `window_subsystem` nor `console_subsystem` is active. |

---

## Rule-Level Passthrough

Forward Bazel rule attributes to the compiler/linker. These map the well-known `rules_cc` variables to the correct syntax for each compiler.

| Feature                | Source attribute | Action  | Purpose |
|------------------------|-----------------|---------|---------|
| `user_compile_flags`   | `copts`          | compile | Forwards each `copts` string verbatim to the compiler. |
| `user_compile_defines` | `defines`        | compile | Prepends `/D` (or `-D`) to each `defines` entry. |
| `includes`             | `includes`       | compile | Maps quote, system, external, and framework include paths to the correct `/I` or `/external:I` flags. |
| `user_link_flags`      | `linkopts`       | link    | Forwards each `linkopts` string verbatim to the linker. |

---

## Configuration (Mode-Driven)

Bazel selects a compilation mode (`dbg`, `fastbuild`, or `opt`) at the command line (`-c dbg`). These features translate that selection into concrete compiler flags.

| Feature      | Purpose |
|--------------|---------|
| `default`    | Implied at startup; pulls in the features listed in the `toolchain_set` `features` attribute. Used to inject toolchain-set-specific defaults without touching `dbg`/`fastbuild`/`opt`. |
| `dbg`        | Debug mode. Overrides the `rules_cc` built-in. Adds debug compile/link flags and implies whichever features the toolchain set lists under `dbg_features`. |
| `fastbuild`  | Fast-build mode (minimal optimisation, no debug info unless requested). Implies `fastbuild_features`. |
| `opt`        | Optimised build. Implies `opt_features`. |

The three mode features are mutually exclusive (only one can be active at a time).
