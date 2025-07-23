"""Run nix flake checks with nix-fast-build and generate summary output."""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from typing import List, Set, Tuple


class Colors:
    """ANSI color codes for terminal output."""

    def __init__(self, enabled: bool = True):
        if enabled and not os.environ.get("CI"):
            self.RED = "\033[0;31m"
            self.GREEN = "\033[0;32m"
            self.YELLOW = "\033[1;33m"
            self.NC = "\033[0m"
        else:
            self.RED = ""
            self.GREEN = ""
            self.YELLOW = ""
            self.NC = ""


def parse_build_output(build_log: str) -> Tuple[Set[str], Set[str]]:
    """Parse nix-fast-build output to identify successful and failed checks."""
    failed_checks = set()
    potential_success = set()

    # Parse error messages - both individual BuildFailure and Failed attributes list
    error_pattern = r"ERROR:nix_fast_build:BuildFailure for ([^:]+):"
    for match in re.finditer(error_pattern, build_log):
        check_name = match.group(1)
        # Convert format like x86_64-linux."3.5.1" to checks.x86_64-linux.3.5.1
        if not check_name.startswith("checks."):
            check_name = re.sub(r"\.", ".checks.", check_name, count=1)
        check_name = check_name.replace('"', "")
        failed_checks.add(check_name)

    # Parse "Failed attributes:" line which lists all failures
    failed_attrs_pattern = r"ERROR:nix_fast_build:Failed attributes: (.+)"
    for match in re.finditer(failed_attrs_pattern, build_log):
        failed_attrs_line = match.group(1)
        # Split by spaces and extract each .#checks.x86_64-linux."version" pattern
        attr_pattern = r'\.#checks\.([^"]*"[^"]*"|\S+)'
        for attr_match in re.finditer(attr_pattern, failed_attrs_line):
            attr_name = attr_match.group(1)
            # Convert x86_64-linux."3.5.1" to checks.x86_64-linux.3.5.1
            check_name = f"checks.{attr_name}".replace('"', "")
            failed_checks.add(check_name)

    # Parse building lines to identify potential successes
    building_pattern = r"^\s*building\s+([^\s]+)"
    for line in build_log.split("\n"):
        match = re.match(building_pattern, line)
        if match:
            check_name = match.group(1)
            # Skip derivation paths
            if check_name.startswith(("/nix/store/", '"/nix/store/', "'/nix/store/")):
                continue
            # Convert format
            if not check_name.startswith("checks."):
                check_name = re.sub(r"\.", ".checks.", check_name, count=1)
            check_name = check_name.replace('"', "")
            potential_success.add(check_name)

    # Only consider successes that aren't in the failed list
    successful_checks = potential_success - failed_checks

    return successful_checks, failed_checks


def get_all_checks() -> List[str]:
    """Get all available checks for the current system."""
    try:
        # Get current system
        result = subprocess.run(
            ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"],
            capture_output=True,
            text=True,
            check=True,
        )
        current_system = result.stdout.strip()

        # Get all checks for this system
        expr = f'builtins.concatStringsSep " " (builtins.attrNames (builtins.getFlake (toString ./.)).checks.{current_system})'
        result = subprocess.run(
            ["nix", "eval", "--impure", "--raw", "--expr", expr],
            capture_output=True,
            text=True,
            check=True,
        )

        checks = []
        for check in result.stdout.strip().split():
            if check:
                checks.append(f"checks.{current_system}.{check}")

        return checks
    except subprocess.CalledProcessError:
        return []


def filter_valid_checks(checks: Set[str]) -> List[str]:
    """Filter out invalid check names and remove duplicates."""
    valid_pattern = r"^(checks\.)?[a-zA-Z0-9_-]+\."
    normalized = set()

    for check in checks:
        if "/nix/store/" not in check and re.match(valid_pattern, check):
            # Normalize all check names to start with "checks."
            if not check.startswith("checks."):
                # Convert x86_64-linux.checks.foo to checks.x86_64-linux.foo
                parts = check.split(".", 2)
                if len(parts) >= 3 and parts[1] == "checks":
                    check = f"checks.{parts[0]}.{parts[2]}"
                else:
                    # Convert x86_64-linux.foo to checks.x86_64-linux.foo
                    check = re.sub(r"\.", ".checks.", check, count=1)
            normalized.add(check)

    return sorted(normalized, key=lambda x: x.lower())


def run_nix_fast_build(json_output: bool) -> str:
    """Run nix-fast-build and return the output while streaming to stderr."""
    cmd = [
        "devenv",
        "shell",
        "--quiet",
        "--",
        "nix-fast-build",
        "--flake=.#checks",
        "--no-link",
    ]

    # Add --no-nom flag for CI or JSON mode
    if os.environ.get("CI") or json_output:
        cmd.append("--no-nom")

    print("Running nix flake checks with nix-fast-build...", file=sys.stderr)
    print("================================", file=sys.stderr)

    try:
        # Stream output in real-time while capturing it
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True,
        )

        output_lines = []
        for line in process.stdout:
            # Stream to stderr for real-time visibility
            print(line, file=sys.stderr, end="")
            output_lines.append(line)

        process.wait()
        return "".join(output_lines)

    except Exception as e:
        print(f"Error running nix-fast-build: {e}", file=sys.stderr)
        return ""


def generate_json_output(successful: List[str], failed: List[str]) -> str:
    """Generate JSON output format."""
    timestamp = datetime.now(timezone.utc).isoformat()
    total = len(successful) + len(failed)

    json_data = {
        "timestamp": timestamp,
        "total": total,
        "successful": len(successful),
        "failed": len(failed),
        "success": len(failed) == 0,
        "successful_checks": successful,
        "failed_checks": failed,
    }

    try:
        json_output = json.dumps(json_data, indent=2)
        if not json_output.strip():
            raise ValueError("Generated JSON is empty")
        return json_output
    except (TypeError, ValueError) as e:
        print(f"Error generating JSON: {e}", file=sys.stderr)
        sys.exit(1)


def generate_human_output(
    successful: List[str], failed: List[str], colors: Colors
) -> None:
    """Generate human-readable output to stderr."""
    total = len(successful) + len(failed)

    output = [
        "",
        "================================",
        "Build Summary",
        "================================",
        "",
        f"Total checks: {total}",
        f"{colors.GREEN}✓ Successful: {len(successful)}{colors.NC}",
        f"{colors.RED}✗ Failed: {len(failed)}{colors.NC}",
        "",
    ]

    if successful:
        output.append(f"{colors.GREEN}Successful builds:{colors.NC}")
        for check in successful:
            output.append(f"  ✓ {check}")
        output.append("")

    if failed:
        output.append(f"{colors.RED}Failed builds:{colors.NC}")
        for check in failed:
            output.append(f"  ✗ {check}")
        output.append("")

    if not failed:
        output.append(f"{colors.GREEN}All checks passed successfully!{colors.NC}")
    else:
        output.append(
            f"{colors.YELLOW}Some checks failed. See details above.{colors.NC}"
        )

    print("\n".join(output), file=sys.stderr)


def generate_github_summary(successful: List[str], failed: List[str]) -> None:
    """Generate GitHub Actions step summary."""
    github_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if not github_summary:
        return

    total = len(successful) + len(failed)

    with open(github_summary, "a") as f:
        f.write("## Nix Flake Check Summary\n\n")
        f.write("| Status | Count |\n")
        f.write("|--------+-------|\n")
        f.write(f"| Total | {total} |\n")
        f.write(f"| ✅ Successful | {len(successful)} |\n")
        f.write(f"| ❌ Failed | {len(failed)} |\n")
        f.write("\n")

        if successful and len(successful) <= 50:
            f.write("### ✅ Successful builds\n")
            f.write("<details>\n")
            f.write("<summary>Click to expand</summary>\n\n")
            for check in successful:
                f.write(f"- ✓ `{check}`\n")
            f.write("\n</details>\n\n")
        elif successful:
            f.write("### ✅ Successful builds\n")
            f.write(f"All {len(successful)} checks passed successfully.\n\n")

        if failed:
            f.write("### ❌ Failed builds\n")
            f.write("<details open>\n")
            f.write("<summary>Click to expand</summary>\n\n")
            for check in failed:
                f.write(f"- ✗ `{check}`\n")
            f.write("\n</details>\n")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Run nix flake checks with summary output"
    )
    parser.add_argument("--json", action="store_true", help="Output in JSON format")
    args = parser.parse_args()

    colors = Colors(enabled=not args.json)

    # Run nix-fast-build
    build_output = run_nix_fast_build(args.json)

    # Parse the output
    successful_checks, failed_checks = parse_build_output(build_output)

    # Always enumerate all checks to get the complete picture (including cached builds)
    if not args.json:
        print("Enumerating all checks to account for cached builds...", file=sys.stderr)

    all_checks = get_all_checks()
    all_checks_set = set(all_checks)

    # Any check that wasn't explicitly failed must be successful (built or cached)
    complete_successful = (all_checks_set - failed_checks) | successful_checks

    # Filter and sort results
    successful = filter_valid_checks(complete_successful)
    failed = filter_valid_checks(failed_checks)

    # Generate output
    if args.json:
        print(generate_json_output(successful, failed))
    else:
        generate_human_output(successful, failed, colors)
        generate_github_summary(successful, failed)

    # Exit with appropriate code
    sys.exit(0 if not failed else 1)


if __name__ == "__main__":
    main()
