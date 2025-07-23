#!/usr/bin/env python3
"""Convert JSON output from check-with-summary.py to human-readable format."""

import argparse
import json
import sys
from typing import Dict, Any

from rich.console import Console
from rich.table import Table


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
    """Generate markdown output using the markdown library."""
    timestamp = data.get("timestamp", "")
    total = data.get("total", 0)
    successful_count = data.get("successful", 0)
    failed_count = data.get("failed", 0)
    successful_checks = data.get("successful_checks", [])
    failed_checks = data.get("failed_checks", [])

    # Build markdown content
    md_content = []
    md_content.append("## Nix Flake Check Summary")
    md_content.append("")
    md_content.append(f"_Generated at: {timestamp}_")
    md_content.append("")
    md_content.append("| Status | Count |")
    md_content.append("|--------|-------|")
    md_content.append(f"| Total | {total} |")
    md_content.append(f"| ✅ Successful | {successful_count} |")
    md_content.append(f"| ❌ Failed | {failed_count} |")
    md_content.append("")

    if successful_count > 0:
        md_content.append("### ✅ Successful builds")
        if successful_count <= 50:
            md_content.append("<details>")
            md_content.append("<summary>Click to expand</summary>")
            md_content.append("")
            for check in sorted(successful_checks, key=str.lower):
                md_content.append(f"- ✓ `{check}`")
            md_content.append("")
            md_content.append("</details>")
        else:
            md_content.append(f"All {successful_count} checks passed successfully.")
        md_content.append("")

    if failed_count > 0:
        md_content.append("### ❌ Failed builds")
        md_content.append("<details open>")
        md_content.append("<summary>Click to expand</summary>")
        md_content.append("")
        for check in sorted(failed_checks, key=str.lower):
            md_content.append(f"- ✗ `{check}`")
        md_content.append("")
        md_content.append("</details>")

    # Convert to markdown and print
    md_text = "\n".join(md_content)
    print(md_text)


def generate_terminal_output(data: Dict[str, Any]) -> None:
    """Generate terminal output using Rich."""
    console = Console()
    timestamp = data.get("timestamp", "")
    total = data.get("total", 0)
    successful_count = data.get("successful", 0)
    failed_count = data.get("failed", 0)
    successful_checks = data.get("successful_checks", [])
    failed_checks = data.get("failed_checks", [])
    is_success = data.get("success", False)

    console.print()
    console.rule("[bold]Build Summary[/bold]")
    console.print()
    console.print(f"Generated at: {timestamp}")
    console.print()

    # Create summary table
    table = Table(show_header=True, header_style="bold magenta")
    table.add_column("Status", style="bold")
    table.add_column("Count", justify="right")

    table.add_row("Total", str(total))
    table.add_row("✓ Successful", f"[green]{successful_count}[/green]")
    table.add_row("✗ Failed", f"[red]{failed_count}[/red]")

    console.print(table)
    console.print()

    if successful_count > 0:
        console.print("[bold green]Successful builds:[/bold green]")
        for check in sorted(successful_checks, key=str.lower):
            console.print(f"  [green]✓[/green] {check}")
        console.print()

    if failed_count > 0:
        console.print("[bold red]Failed builds:[/bold red]")
        for check in sorted(failed_checks, key=str.lower):
            console.print(f"  [red]✗[/red] {check}")
        console.print()

    if is_success:
        console.print("[bold green]All checks passed successfully![/bold green]")
    else:
        console.print(
            "[bold yellow]Some checks failed. See details above.[/bold yellow]"
        )


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
        generate_terminal_output(data)

    # Exit with appropriate code based on success status
    is_success = data.get("success", False)
    sys.exit(0 if is_success else 1)


if __name__ == "__main__":
    main()
