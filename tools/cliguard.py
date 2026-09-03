#!/usr/bin/env python3
"""Reject command-line options a tool does not define, instead of ignoring them.

WHY THIS EXISTS. Several generators here take an optional output PATH as
`argv[1]` and test their own flags with `"--flag" in sys.argv`. Those two habits
combine badly: a mistyped or invented option is not an error, it is a FILENAME,
and the run exits 0 looking exactly like success.

Three live examples, all real before this module:

  * `mkarchpage.py --check` — a mode that tool has never had — wrote a file
    literally named `--check` and printed "wrote --check 82765 bytes". Read as
    a passing verification. It was found by someone doing precisely that.
  * `mkenginepage.py --chekc` skips the `--check` branch, falls through to
    "argv[1] is the output path", and writes `--chekc`. The tool HAS a
    verification mode, so the typo silently converts a check into a no-op.
  * `mkindex.py --chekc` is the worst of the three: `--check` is tested with
    `in sys.argv`, so a typo falls through to the WRITE branch and REGENERATES
    `tools/README.md`, printing "wrote tools/README.md (...)". In CI that reads
    like the staleness check passing while it is actually erasing the evidence
    of drift — trap 17 with the safety catch removed.

This is the shape the project already refuses elsewhere: `mksigs.py` ends its
mode dispatch with `raise SystemExit(f"unknown mode {mode}")`, and that is the
behaviour generalised here. A check that cannot fail is not a check (HANDOFF
trap 20); a check that quietly does something ELSE is worse, because it prints a
success line while doing it.

Positional arguments are deliberately NOT policed — these tools legitimately
take a path, and a path is whatever the caller says it is. Only tokens that look
like options (a leading `-`) are rejected, because those are the ones a reader
believes will be interpreted.

    from cliguard import reject_unknown_flags
    reject_unknown_flags(sys.argv, {"--standalone"}, "mkarchpage.py")

`selftest()` is the negative control: every branch of this module must be shown
to fail on purpose before anything is allowed to depend on it.
"""
import sys


def reject_unknown_flags(argv, allowed, tool):
    """Exit non-zero if argv carries an option `allowed` does not list.

    argv     the caller's sys.argv (argv[0] is skipped)
    allowed  iterable of accepted option strings, e.g. {"--check"}
    tool     name to print, e.g. "mkarchpage.py"

    A bare "-" and the conventional "--" end-of-options marker are left alone;
    neither is an option, and refusing them would be a new surprise in place of
    the old one.
    """
    allowed = set(allowed)
    unknown = [a for a in argv[1:]
               if a.startswith("-") and a not in ("-", "--") and a not in allowed]
    if not unknown:
        return
    offer = ", ".join(sorted(allowed)) if allowed else "no options"
    raise SystemExit(
        "%s: unknown option %s\n"
        "  this tool accepts: %s\n"
        "  (an unrecognised option would otherwise be taken as the output "
        "FILENAME and the run would exit 0)"
        % (tool, " ".join(unknown), offer))


def selftest():
    """Prove each branch fails, and passes, on purpose. -> list of failures."""
    bad = []

    def fires(argv, allowed, why):
        try:
            reject_unknown_flags(argv, allowed, "t")
        except SystemExit:
            return
        bad.append("did NOT reject %r (%s)" % (argv[1:], why))

    def silent(argv, allowed, why):
        try:
            reject_unknown_flags(argv, allowed, "t")
        except SystemExit as e:
            bad.append("wrongly rejected %r (%s): %s" % (argv[1:], why, e))

    # must fire
    fires(["t", "--check"], set(), "tool with no options at all")
    fires(["t", "--check"], {"--standalone"}, "the real mkarchpage case")
    fires(["t", "--chekc"], {"--check"}, "a typo of a real flag")
    fires(["t", "out.html", "--nope"], {"--standalone"}, "option after a path")
    fires(["t", "-x"], {"--x"}, "short form is not the long form")
    # must stay silent
    silent(["t"], {"--check"}, "no arguments")
    silent(["t", "--check"], {"--check"}, "the flag it declares")
    silent(["t", "out.html"], {"--check"}, "a positional path")
    silent(["t", "--standalone", "site/index.html"], {"--standalone"}, "flag + path")
    silent(["t", "--"], {"--check"}, "the end-of-options marker")
    silent(["t", "-"], {"--check"}, "a bare dash")
    # a path that merely CONTAINS a dash is not an option
    silent(["t", "out-file.html"], set(), "hyphen inside a filename")
    return bad


if __name__ == "__main__":
    problems = selftest()
    for p in problems:
        print("FAIL " + p, file=sys.stderr)
    print("cliguard selftest: %s (12 cases)" % ("FAILURES" if problems else "ALL PASS"))
    sys.exit(1 if problems else 0)
