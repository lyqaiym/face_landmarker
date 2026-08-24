"""CLI: bazel aquery dumps -> mediapipe_tasks/src/main/cpp/generated/*.cmake"""

from __future__ import annotations

import argparse
import os
import sys

import aquery
import emit

DEFAULT_DUMPS = "mediapipesource"
DEFAULT_OUT = "mediapipe_tasks/src/main/cpp/generated"


def _write(path: str, text: str) -> None:
    with open(path, "w") as fh:
        fh.write(text)
    print(f"  wrote {os.path.relpath(path)} ({len(text.splitlines())} lines)")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dumps", default=DEFAULT_DUMPS, help="dir holding *_actions.json")
    ap.add_argument("--out", default=DEFAULT_OUT, help="output dir for generated cmake")
    args = ap.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)

    compile_dump = os.path.join(args.dumps, "compile_actions.json")
    print(f"loading {compile_dump}")
    compile_aq = aquery.load(compile_dump)

    model = emit.build(compile_aq.actions)
    print(emit.report_counts(model))

    genproto_dump = os.path.join(args.dumps, "genproto_actions.json")
    print(f"loading {genproto_dump}")
    genproto_aq = aquery.load(genproto_dump)

    codegen_dump = os.path.join(args.dumps, "codegen_actions.json")
    print(f"loading {codegen_dump}")
    codegen_aq = aquery.load(codegen_dump)

    _write(os.path.join(args.out, "10_common.cmake"), emit.emit_flavors(model))
    _write(os.path.join(args.out, "20_protos.cmake"), emit.emit_protos(model, genproto_aq.actions))
    _write(
        os.path.join(args.out, "30_flatbuffers.cmake"),
        emit.emit_flatbuffers(model, codegen_aq.actions, genproto_aq.actions),
    )
    _write(
        os.path.join(args.out, "40_configure.cmake"),
        emit.emit_configure(model, codegen_aq.actions, genproto_aq.actions),
    )
    _write(os.path.join(args.out, "45_codegen.cmake"), emit.emit_codegen_barrier(model))
    _write(os.path.join(args.out, "50_mediapipe.cmake"), emit.emit_main(model))
    _write(os.path.join(args.out, "60_external.cmake"), emit.emit_external(model))
    _write(os.path.join(args.out, "90_link.cmake"), emit.emit_link(model, codegen_aq.actions))

    uncovered = model.generated_sources - set(model.codegen_outputs)
    if uncovered:
        print(f"\nFAIL: {len(uncovered)} generated sources have no codegen rule:", file=sys.stderr)
        for path in sorted(uncovered):
            print(f"  {path}", file=sys.stderr)
        return 1

    unmapped = model.mapper.report()
    _write(os.path.join(args.out, "unmapped.txt"), unmapped)

    if unmapped:
        print("\nFAIL: unmapped Bazel paths (see unmapped.txt):", file=sys.stderr)
        print(unmapped, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
