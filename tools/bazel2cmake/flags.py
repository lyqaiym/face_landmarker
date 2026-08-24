"""Split a CppCompile argv into the pieces CMake wants.

Bazel emits a single flat command line per source file. Measured over the 2378 actions in
this build, the only flags taking a separate argument are -isystem, -iquote, -MF, -c, -o;
everything else is joined (-Ipath, -DFOO=1).
"""

from __future__ import annotations

from dataclasses import dataclass, field

# Take a separate following argument.
_TWO_ARG = ("-isystem", "-iquote", "-MF", "-c", "-o", "-include", "-x", "--sysroot")

# The CMake toolchain file already supplies these, or they are Bazel bookkeeping.
_DROP_EXACT = {
    "-no-canonical-prefixes",
    "-fPIC",
    "-MD",
    "-MMD",
    "-fdiagnostics-color",
}
_DROP_PREFIX = (
    "--target=",
    "--sysroot",
    "-fdiagnostics-color",
    "-gcc-toolchain",
    "-frandom-seed=",
    "-fmodule",
    "-Xclang",
    "--gcc-toolchain",
)

_CXX_EXT = (".cc", ".cpp", ".cxx", ".C", ".c++")
_C_EXT = (".c",)
_ASM_EXT = (".S", ".s", ".asm")


@dataclass
class Compile:
    source: str = ""
    output: str = ""
    defines: list[str] = field(default_factory=list)
    includes: list[str] = field(default_factory=list)
    quote_includes: list[str] = field(default_factory=list)
    system_includes: list[str] = field(default_factory=list)
    options: list[str] = field(default_factory=list)

    @property
    def language(self) -> str:
        if self.source.endswith(_CXX_EXT):
            return "CXX"
        if self.source.endswith(_C_EXT):
            return "C"
        if self.source.endswith(_ASM_EXT):
            return "ASM"
        return "CXX"

    def key(self) -> tuple:
        """Identity of everything except the source, for grouping sources per target."""
        return (
            self.language,
            tuple(self.defines),
            tuple(self.includes),
            tuple(self.quote_includes),
            tuple(self.system_includes),
            tuple(self.options),
        )


def parse(argv: list[str]) -> Compile:
    out = Compile()
    i = 1  # argv[0] is the NDK clang wrapper
    n = len(argv)
    while i < n:
        arg = argv[i]

        two_arg = arg in _TWO_ARG
        value = argv[i + 1] if two_arg and i + 1 < n else ""
        i += 2 if two_arg else 1

        if arg == "-isystem":
            out.system_includes.append(value)
        elif arg == "-iquote":
            out.quote_includes.append(value)
        elif arg == "-c":
            out.source = value
        elif arg == "-o":
            out.output = value
        elif arg in ("-MF", "-include", "-x", "--sysroot"):
            pass
        elif arg.startswith("-D"):
            out.defines.append(arg[2:])
        elif arg.startswith("-I"):
            out.includes.append(arg[2:])
        elif arg in _DROP_EXACT or arg.startswith(_DROP_PREFIX):
            pass
        elif arg.endswith(".cppmap"):
            pass
        elif arg.startswith("-"):
            out.options.append(arg)
        # A bare argument not consumed by a two-arg flag is the source; Bazel always
        # passes it via -c, so reaching here means the command line changed shape.
        elif not out.source:
            out.source = arg

    return out
