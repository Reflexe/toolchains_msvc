"""Default compiler/linker flags and helpers to merge replace vs add semantics.

Attributes starting with add_* are merged with the default (default + add).
Other attributes replace the default when non-empty.
"""

def merge_flags(default, replace, add):
    """Returns replace + add if replace is non-empty, otherwise default + add."""
    base = replace if (replace != None and len(replace) > 0) else default
    return base + (add if add else [])

# --- MSVC (cl) default flags ---

CL_C_COMPILE_FLAGS_DEFAULT = [
    "/permissive-",
    "/GS",
    "/W3",
    "/Zc:wchar_t",
    "/Gm-",
    "/sdl",
    "/Zc:inline",
    "/fp:precise",
    "/Zc:forScope",
    "/Gd",
    "/EHsc",
    "/diagnostics:column",
]

CL_CXX_COMPILE_FLAGS_DEFAULT = []

CL_LINK_FLAGS_DEFAULT = [
    "/NXCOMPAT",
]

CL_DBG_C_COMPILE_FLAGS_DEFAULT = [
    "/JMC",
    "/Od",
    "/RTC1",
]

CL_DBG_CXX_COMPILE_FLAGS_DEFAULT = []
CL_DBG_LINK_FLAGS_DEFAULT = []

CL_FASTBUILD_C_COMPILE_FLAGS_DEFAULT = [
    "/Gy",
    "/O2",
    "/Oi",
]
CL_FASTBUILD_CXX_COMPILE_FLAGS_DEFAULT = []
CL_FASTBUILD_LINK_FLAGS_DEFAULT = []

CL_OPT_C_COMPILE_FLAGS_DEFAULT = [
    "/Gy",
    "/O2",
    "/Oi",
]
CL_OPT_CXX_COMPILE_FLAGS_DEFAULT = []
CL_OPT_LINK_FLAGS_DEFAULT = []

# --- Clang default flags ---

CLANG_C_COMPILE_FLAGS_DEFAULT = [
    "-fstack-protector",
    "-ffp-model=precise",
    "-fexceptions",
    "-fshow-column",
]

CLANG_CXX_COMPILE_FLAGS_DEFAULT = []

CLANG_LINK_FLAGS_DEFAULT = [
    "/NXCOMPAT",
]

CLANG_DBG_C_COMPILE_FLAGS_DEFAULT = [
    "-O0"
]
CLANG_DBG_CXX_COMPILE_FLAGS_DEFAULT = []
CLANG_DBG_LINK_FLAGS_DEFAULT = []

CLANG_FASTBUILD_C_COMPILE_FLAGS_DEFAULT = [
    "-O2",
    "-ffunction-sections",
    "-fdata-sections",
    "-fbuiltin",
]
CLANG_FASTBUILD_CXX_COMPILE_FLAGS_DEFAULT = []
CLANG_FASTBUILD_LINK_FLAGS_DEFAULT = []

CLANG_OPT_C_COMPILE_FLAGS_DEFAULT = [
    "-O2",
    "-ffunction-sections",
    "-fdata-sections",
    "-fbuiltin",
]
CLANG_OPT_CXX_COMPILE_FLAGS_DEFAULT = []
CLANG_OPT_LINK_FLAGS_DEFAULT = []
