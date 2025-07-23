#!/usr/bin/env bash
set -euo pipefail

# Script to convert JSON output from check-with-summary.sh to human-readable format
# Usage: json-to-summary.sh [--markdown] < input.json

# Parse command line arguments
MARKDOWN_MODE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --markdown)
            MARKDOWN_MODE=true
            shift
            ;;
        *)
            echo "Usage: $0 [--markdown]" >&2
            echo "  Reads JSON from stdin and outputs human-readable summary" >&2
            exit 1
            ;;
    esac
done

# Read JSON from stdin
JSON_INPUT=$(cat)

# Extract values using jq (ensure jq is available)
if ! command -v jq &> /dev/null; then
    # Fallback to basic parsing if jq is not available
    echo "Warning: jq not found, using basic parsing" >&2
    
    # Extract values using grep and sed
    TOTAL=$(echo "$JSON_INPUT" | grep -o '"total":[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
    SUCCESS_COUNT=$(echo "$JSON_INPUT" | grep -o '"successful":[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
    FAILED_COUNT=$(echo "$JSON_INPUT" | grep -o '"failed":[[:space:]]*[0-9]*' | grep -o '[0-9]*$')
    SUCCESS=$(echo "$JSON_INPUT" | grep -o '"success":[[:space:]]*[a-z]*' | grep -o '[a-z]*$')
    TIMESTAMP=$(echo "$JSON_INPUT" | grep -o '"timestamp":[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
else
    # Use jq for proper JSON parsing (suppress stderr to avoid devenv noise)
    TOTAL=$(echo "$JSON_INPUT" | jq -r '.total // 0' 2>/dev/null || echo "0")
    SUCCESS_COUNT=$(echo "$JSON_INPUT" | jq -r '.successful // 0' 2>/dev/null || echo "0")
    FAILED_COUNT=$(echo "$JSON_INPUT" | jq -r '.failed // 0' 2>/dev/null || echo "0")
    SUCCESS=$(echo "$JSON_INPUT" | jq -r '.success // false' 2>/dev/null || echo "false")
    TIMESTAMP=$(echo "$JSON_INPUT" | jq -r '.timestamp // ""' 2>/dev/null || echo "")
fi

# Colors for terminal output (only in non-markdown mode)
if [ "$MARKDOWN_MODE" = false ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

if [ "$MARKDOWN_MODE" = true ]; then
    # Markdown output
    echo "## Nix Flake Check Summary"
    echo ""
    echo "_Generated at: ${TIMESTAMP}_"
    echo ""
    echo "| Status | Count |"
    echo "|--------|-------|"
    echo "| Total | $TOTAL |"
    echo "| ✅ Successful | $SUCCESS_COUNT |"
    echo "| ❌ Failed | $FAILED_COUNT |"
    echo ""
    
    if [ "$SUCCESS_COUNT" -gt 0 ]; then
        echo "### ✅ Successful builds"
        if [ "$SUCCESS_COUNT" -le 50 ]; then
            echo "<details>"
            echo "<summary>Click to expand</summary>"
            echo ""
            if command -v jq &> /dev/null; then
                echo "$JSON_INPUT" | jq -r '.successful_checks[] | "- ✓ `\(.)`"' | sort -V
            else
                # Basic parsing fallback
                echo "$JSON_INPUT" | grep -o '"successful_checks":\[[^]]*\]' | \
                    sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | sed 's/"//g' | \
                    while read -r check; do
                        [ -n "$check" ] && echo "- ✓ \`$check\`"
                    done | sort -V
            fi
            echo ""
            echo "</details>"
        else
            echo "All $SUCCESS_COUNT checks passed successfully."
        fi
        echo ""
    fi
    
    if [ "$FAILED_COUNT" -gt 0 ]; then
        echo "### ❌ Failed builds"
        echo "<details open>"
        echo "<summary>Click to expand</summary>"
        echo ""
        if command -v jq &> /dev/null; then
            echo "$JSON_INPUT" | jq -r '.failed_checks[] | "- ✗ `\(.)`"' | sort -V
        else
            # Basic parsing fallback
            echo "$JSON_INPUT" | grep -o '"failed_checks":\[[^]]*\]' | \
                sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | sed 's/"//g' | \
                while read -r check; do
                    [ -n "$check" ] && echo "- ✗ \`$check\`"
                done | sort -V
        fi
        echo ""
        echo "</details>"
    fi
else
    # Terminal output
    echo ""
    echo "================================"
    echo "Build Summary"
    echo "================================"
    echo ""
    echo "Generated at: $TIMESTAMP"
    echo ""
    echo "Total checks: $TOTAL"
    printf "${GREEN}✓ Successful: $SUCCESS_COUNT${NC}\n"
    printf "${RED}✗ Failed: $FAILED_COUNT${NC}\n"
    echo ""
    
    if [ "$SUCCESS_COUNT" -gt 0 ]; then
        printf "${GREEN}Successful builds:${NC}\n"
        if command -v jq &> /dev/null; then
            echo "$JSON_INPUT" | jq -r '.successful_checks[]' | sort -V | while read -r check; do
                echo "  ✓ $check"
            done
        else
            # Basic parsing fallback
            echo "$JSON_INPUT" | grep -o '"successful_checks":\[[^]]*\]' | \
                sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | sed 's/"//g' | sort -V | \
                while read -r check; do
                    [ -n "$check" ] && echo "  ✓ $check"
                done
        fi
        echo ""
    fi
    
    if [ "$FAILED_COUNT" -gt 0 ]; then
        printf "${RED}Failed builds:${NC}\n"
        if command -v jq &> /dev/null; then
            echo "$JSON_INPUT" | jq -r '.failed_checks[]' | sort -V | while read -r check; do
                echo "  ✗ $check"
            done
        else
            # Basic parsing fallback
            echo "$JSON_INPUT" | grep -o '"failed_checks":\[[^]]*\]' | \
                sed 's/.*\[\(.*\)\]/\1/' | tr ',' '\n' | sed 's/"//g' | sort -V | \
                while read -r check; do
                    [ -n "$check" ] && echo "  ✗ $check"
                done
        fi
        echo ""
    fi
    
    if [ "$SUCCESS" = "true" ]; then
        printf "${GREEN}All checks passed successfully!${NC}\n"
    else
        printf "${YELLOW}Some checks failed. See details above.${NC}\n"
    fi
fi

# Exit with appropriate code
[ "$SUCCESS" = "true" ] && exit 0 || exit 1