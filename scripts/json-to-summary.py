#!/usr/bin/env python3
"""Convert JSON output from check-with-summary.py to human-readable format."""

import argparse
import json
import os
import sys
from typing import Dict, Any


class Colors:
    """ANSI color codes for terminal output."""

    def __init__(self, enabled: bool = True):
        if enabled:
            self.RED = "\033[0;31m"
            self.GREEN = "\033[0;32m"
            self.YELLOW = "\033[1;33m"
            self.NC = "\033[0m"
        else:
            self.RED = ""
            self.GREEN = ""
            self.YELLOW = ""
            self.NC = ""


def parse_json_input() -> Dict[str, Any]:
    """Read and parse JSON from stdin."""
    try:
        json_input = sys.stdin.read()
        return json.loads(json_input)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON input: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error reading input: {e}", file=sys.stderr)
        sys.exit(1)


def generate_markdown_output(data: Dict[str, Any]) -> None:
    """Generate markdown output."""
    timestamp = data.get("timestamp", "")
    total = data.get("total", 0)
    successful_count = data.get("successful", 0)
    failed_count = data.get("failed", 0)
    successful_checks = data.get("successful_checks", [])
    failed_checks = data.get("failed_checks", [])

    print("## Nix Flake Check Summary")
    print("")
    print(f"_Generated at: {timestamp}_")
    print("")
    print("| Status | Count |")
    print("|--------|-------|")
    print(f"| Total | {total} |")
    print(f"| ✅ Successful | {successful_count} |")
    print(f"| ❌ Failed | {failed_count} |")
    print("")

    if successful_count > 0:
        print("### ✅ Successful builds")
        if successful_count <= 50:
            print("<details>")
            print("<summary>Click to expand</summary>")
            print("")
            for check in sorted(successful_checks, key=str.lower):
                print(f"- ✓ `{check}`")
            print("")
            print("</details>")
        else:
            print(f"All {successful_count} checks passed successfully.")
        print("")

    if failed_count > 0:
        print("### ❌ Failed builds")
        print("<details open>")
        print("<summary>Click to expand</summary>")
        print("")
        for check in sorted(failed_checks, key=str.lower):
            print(f"- ✗ `{check}`")
        print("")
        print("</details>")


def generate_terminal_output(data: Dict[str, Any], colors: Colors) -> None:
    """Generate terminal output with colors."""
    timestamp = data.get("timestamp", "")
    total = data.get("total", 0)
    successful_count = data.get("successful", 0)
    failed_count = data.get("failed", 0)
    successful_checks = data.get("successful_checks", [])
    failed_checks = data.get("failed_checks", [])
    is_success = data.get("success", False)

    print("")
    print("================================")
    print("Build Summary")
    print("================================")
    print("")
    print(f"Generated at: {timestamp}")
    print("")
    print(f"Total checks: {total}")
    print(f"{colors.GREEN}✓ Successful: {successful_count}{colors.NC}")
    print(f"{colors.RED}✗ Failed: {failed_count}{colors.NC}")
    print("")

    if successful_count > 0:
        print(f"{colors.GREEN}Successful builds:{colors.NC}")
        for check in sorted(successful_checks, key=str.lower):
            print(f"  ✓ {check}")
        print("")

    if failed_count > 0:
        print(f"{colors.RED}Failed builds:{colors.NC}")
        for check in sorted(failed_checks, key=str.lower):
            print(f"  ✗ {check}")
        print("")

    if is_success:
        print(f"{colors.GREEN}All checks passed successfully!{colors.NC}")
    else:
        print(f"{colors.YELLOW}Some checks failed. See details above.{colors.NC}")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Convert JSON output to human-readable summary",
        epilog="Reads JSON from stdin and outputs human-readable summary",
    )
    parser.add_argument(
        "--markdown",
        action="store_true",
        help="Generate markdown output instead of terminal output",
    )
    args = parser.parse_args()

    # Parse JSON input
    data = parse_json_input()

    # Generate appropriate output
    if args.markdown:
        generate_markdown_output(data)
    else:
        # Disable colors in CI or markdown mode
        colors = Colors(enabled=not os.environ.get("CI"))
        generate_terminal_output(data, colors)

    # Exit with appropriate code based on success status
    is_success = data.get("success", False)
    sys.exit(0 if is_success else 1)


if __name__ == "__main__":
    main()
