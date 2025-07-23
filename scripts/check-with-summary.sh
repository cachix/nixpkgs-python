#!/usr/bin/env bash
set -euo

# Parse command line arguments
JSON_OUTPUT=false
while [[ $# -gt 0 ]]; do
	case $1 in
	--json)
		JSON_OUTPUT=true
		shift
		;;
	*)
		echo "Usage: $0 [--json]" >&2
		exit 1
		;;
	esac
done

# Colors for output (disabled in CI)
if [ -n "${CI:-}" ]; then
	RED=''
	GREEN=''
	YELLOW=''
	NC=''
else
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[1;33m'
	NC='\033[0m' # No Color
fi

# Create temporary files for tracking results
SUCCESS_FILE=$(mktemp)
FAILED_FILE=$(mktemp)
SUMMARY_FILE=$(mktemp)
BUILD_LOG=$(mktemp)

# Cleanup on exit
trap 'rm -f "$SUCCESS_FILE" "$FAILED_FILE" "$SUMMARY_FILE" "$BUILD_LOG"' EXIT

# Initialize exit code
EXIT_CODE=0

# Only show progress in non-JSON mode
printf "Running nix flake checks with nix-fast-build...\n"
printf "================================\n"

# Run nix-fast-build on all checks
# Use nom formatter for interactive use, --no-nom in CI or JSON mode for cleaner parsing
NOM_FLAG=""
if [ -n "${CI:-}" ] || [ "$JSON_OUTPUT" = true ]; then
	NOM_FLAG="--no-nom"
fi

# The --eval-workers flag controls parallel evaluation
# The --no-link flag prevents creating result symlinks
devenv shell --quiet -- \
	nix-fast-build \
	--flake .#checks \
	$NOM_FLAG \
	--eval-workers 4 \
	--no-link 2>&1 | tee "$BUILD_LOG"

printf ""

# Parse different output formats from nix-fast-build
# Look for error messages like:
# ERROR:nix_fast_build:BuildFailure for x86_64-linux."3.5.1": build exited with 1
grep -E "ERROR:nix_fast_build:BuildFailure for" "$BUILD_LOG" | while IFS= read -r line; do
	if [[ $line =~ BuildFailure[[:space:]]for[[:space:]]([^:]+): ]]; then
		check_name="${BASH_REMATCH[1]}"
		# Convert format like x86_64-linux."3.5.1" to checks.x86_64-linux.3.5.1
		check_name=$(echo "$check_name" | sed 's/\./\.checks\./; s/"//g')
		echo "$check_name" >>"$FAILED_FILE"
	fi
done

# Look for successful builds in the "building" lines
# Since nix-fast-build shows what it's building, we can infer success if no error follows
grep -E "^[[:space:]]*building[[:space:]]" "$BUILD_LOG" | while IFS= read -r line; do
	if [[ $line =~ building[[:space:]]([^[:space:]]+) ]]; then
		check_name="${BASH_REMATCH[1]}"
		# Skip if it looks like a derivation path
		if [[ $check_name =~ ^[\"\']/nix/store/ ]] || [[ $check_name =~ ^/nix/store/ ]]; then
			continue
		fi
		# Convert format like x86_64-linux."3.5.1" to checks.x86_64-linux.3.5.1
		check_name=$(echo "$check_name" | sed 's/\./\.checks\./; s/"//g')
		# Only add to success if it's not in the failed list
		if ! grep -qF "$check_name" "$FAILED_FILE" 2>/dev/null; then
			echo "$check_name" >>"$SUCCESS_FILE.tmp"
		fi
	fi
done

# Also check the summary line if present (e.g., ✔ 74)
if grep -qE "✔[[:space:]]*[0-9]+" "$BUILD_LOG"; then
	# Move temp successes to final success file
	if [ -f "$SUCCESS_FILE.tmp" ]; then
		mv "$SUCCESS_FILE.tmp" "$SUCCESS_FILE"
	fi
else
	rm -f "$SUCCESS_FILE.tmp"
fi

# Remove duplicates and filter out any store paths or malformed entries
sort -u "$SUCCESS_FILE" 2>/dev/null | grep -v "/nix/store/" | grep -E "^(checks\.)?[a-zA-Z0-9_-]+\." >"$SUCCESS_FILE.filtered" || true
mv "$SUCCESS_FILE.filtered" "$SUCCESS_FILE" 2>/dev/null || true

sort -u "$FAILED_FILE" 2>/dev/null | grep -v "/nix/store/" | grep -E "^(checks\.)?[a-zA-Z0-9_-]+\." >"$FAILED_FILE.filtered" || true
mv "$FAILED_FILE.filtered" "$FAILED_FILE" 2>/dev/null || true

# If we still have no results or only failures (cached builds don't show as "building"),
# enumerate all checks and mark non-failed ones as successful
if { [ ! -s "$SUCCESS_FILE" ] && [ ! -s "$FAILED_FILE" ]; } || { [ ! -s "$SUCCESS_FILE" ] && [ -s "$FAILED_FILE" ]; }; then
	if [ "$JSON_OUTPUT" = false ]; then
		echo "Enumerating all checks to account for cached builds..." >&2
	fi
	for system in $(nix eval --impure --raw --expr 'builtins.concatStringsSep " " (builtins.attrNames (builtins.getFlake (toString ./.)).checks)'); do
		for check in $(nix eval --impure --raw --expr "builtins.concatStringsSep \" \" (builtins.attrNames (builtins.getFlake (toString ./.)).checks.${system})" 2>/dev/null || echo ""); do
			check_name="checks.${system}.${check}"
			# If this check is not in the failed list, it must be successful (cached or built)
			if ! grep -qF "$check_name" "$FAILED_FILE" 2>/dev/null; then
				echo "$check_name" >>"$SUCCESS_FILE"
			fi
		done
	done
fi

# Count results
SUCCESS_COUNT=$(wc -l <"$SUCCESS_FILE" | tr -d ' ')
FAILED_COUNT=$(wc -l <"$FAILED_FILE" | tr -d ' ')
TOTAL_COUNT=$((SUCCESS_COUNT + FAILED_COUNT))

if [ "$JSON_OUTPUT" = true ]; then
	# Generate JSON output
	TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

	# Read checks into arrays
	SUCCESS_ARRAY=$(sort -V "$SUCCESS_FILE" 2>/dev/null | while IFS= read -r check; do
		[ -n "$check" ] && printf '"%s",' "$check"
	done | sed 's/,$//')

	FAILED_ARRAY=$(sort -V "$FAILED_FILE" 2>/dev/null | while IFS= read -r check; do
		[ -n "$check" ] && printf '"%s",' "$check"
	done | sed 's/,$//')

	# Output JSON
	cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "total": $TOTAL_COUNT,
  "successful": $SUCCESS_COUNT,
  "failed": $FAILED_COUNT,
  "success": $([ "$FAILED_COUNT" -eq 0 ] && echo "true" || echo "false"),
  "successful_checks": [${SUCCESS_ARRAY}],
  "failed_checks": [${FAILED_ARRAY}]
}
EOF

	EXIT_CODE=$([ "$FAILED_COUNT" -eq 0 ] && echo 0 || echo 1)
else
	# Generate human-readable summary to stderr
	{
		echo ""
		echo "================================"
		echo "Build Summary"
		echo "================================"
		echo ""
		echo "Total checks: $TOTAL_COUNT"
		echo -e "${GREEN}✓ Successful: $SUCCESS_COUNT${NC}"
		echo -e "${RED}✗ Failed: $FAILED_COUNT${NC}"
		echo ""

		if [ "$SUCCESS_COUNT" -gt 0 ]; then
			echo -e "${GREEN}Successful builds:${NC}"
			while IFS= read -r check; do
				echo "  ✓ $check"
			done <"$SUCCESS_FILE" | sort -V
			echo ""
		fi

		if [ "$FAILED_COUNT" -gt 0 ]; then
			echo -e "${RED}Failed builds:${NC}"
			while IFS= read -r check; do
				echo "  ✗ $check"
			done <"$FAILED_FILE" | sort -V
			echo ""
		fi

		if [ "$FAILED_COUNT" -eq 0 ]; then
			echo -e "${GREEN}All checks passed successfully!${NC}"
			EXIT_CODE=0
		else
			echo -e "${YELLOW}Some checks failed. See details above.${NC}"
			EXIT_CODE=1
		fi
	} >&2
fi

# Output summary to GitHub Actions if running in CI (only in non-JSON mode)
if [ -n "${GITHUB_STEP_SUMMARY:-}" ] && [ "$JSON_OUTPUT" = false ]; then
	{
		echo "## Nix Flake Check Summary"
		echo ""
		echo "| Status | Count |"
		echo "|--------|-------|"
		echo "| Total | $TOTAL_COUNT |"
		echo "| ✅ Successful | $SUCCESS_COUNT |"
		echo "| ❌ Failed | $FAILED_COUNT |"
		echo ""

		if [ "$SUCCESS_COUNT" -gt 0 ] && [ "$SUCCESS_COUNT" -le 50 ]; then
			echo "### ✅ Successful builds"
			echo "<details>"
			echo "<summary>Click to expand</summary>"
			echo ""
			while IFS= read -r check; do
				echo "- ✓ \`$check\`"
			done <"$SUCCESS_FILE" | sort -V
			echo ""
			echo "</details>"
			echo ""
		elif [ "$SUCCESS_COUNT" -gt 50 ]; then
			echo "### ✅ Successful builds"
			echo "All $SUCCESS_COUNT checks passed successfully."
			echo ""
		fi

		if [ "$FAILED_COUNT" -gt 0 ]; then
			echo "### ❌ Failed builds"
			echo "<details open>"
			echo "<summary>Click to expand</summary>"
			echo ""
			while IFS= read -r check; do
				echo "- ✗ \`$check\`"
			done <"$FAILED_FILE" | sort -V
			echo ""
			echo "</details>"
		fi
	} >>"$GITHUB_STEP_SUMMARY"
fi

exit "$EXIT_CODE"
