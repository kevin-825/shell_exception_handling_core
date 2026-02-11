#!/bin/bash
# ==============================================================================
# MODULE: exception_handling_core.sh
# DESCRIPTION: Multi-process exception engine with auto-recovery and data passing.
# ==============================================================================

# --- 1. ENGINE SETTINGS (Adaptive) ---
set -E
set -o errtrace

# Probe for inherit_errexit support without triggering errors
HAS_INHERIT_ERREXIT=false
if set -o inherit_errexit 2>/dev/null; then
    HAS_INHERIT_ERREXIT=true
fi

# --- 2. STATE STORAGE ---
declare -A HANDLERS
export HANDLER_ARGS=()

# --- 3. HELP SYSTEM ---
exception_handler_help() {
    # Using 'EOF' in quotes makes the text 100% literal (no accidental execution)
    cat << 'EOF'
Exception handler Usage:
  register_handler [-f] <CONTEXT> <FUNCTION_NAME>
    - Register a repair function for a specific error context.
    - Use -f to force overwrite an existing registration.

  throw_exception <CONTEXT> [EXIT_CODE] [ARGS...]
    - Triggers the ERR trap and jumps to the registered handler.
    - Exit code defaults to 1. Extra args passed to handler as $4, $5, etc.

  dispatch_exception (Internal)
    - The trap runner. Returns 0 to resume worker at the next line.
EOF

    if [ "$HAS_INHERIT_ERREXIT" = false ]; then
        cat << 'EOF'

Warning: inherit_errexit is NOT supported by this Bash binary.
Manual throw is required for command substitutions.

Fails silently on this machine:  data=$(some_broken_command)
Works on this machine:          data=$(some_broken_command) || throw_exception "ERR" "msg"
EOF
    fi
}

# --- 4. DEFAULT HANDLER ---
default_handler() {
    local context="$1"
    local exit_code="$2"
    local failed_cmd="$3"

    echo -e "\n--------------------------------------------------------" >&2
    [[ "$context" != "DEFAULT" ]] && echo -e "handler not found for $context, Default handler Entered" >&2
    echo "--------------------------------------------------------" >&2
    echo "🚨 EXCEPTION TRIGGERED" >&2
    echo "Context:    $context" >&2
    echo "Exit Code:  $exit_code" >&2
    echo "Command:    $failed_cmd" >&2
    echo "Arguments: ${HANDLER_ARGS[*]}" >&2
    echo "--------------------------------------------------------" >&2
    
    echo "TRACEBACK (Most recent call last):" >&2
    
    # We start at 1 to skip the 'dispatch_exception' and 'default_handler' themselves
    for ((i=1; i<${#FUNCNAME[@]}; i++)); do
        local func="${FUNCNAME[$i]}"
        local file="${BASH_SOURCE[$i]}"
        local line="${BASH_LINENO[$((i-1))]}" # Line where the call happened
        
        # Skip internal Bash top-level call "main" if you prefer
        #[[ "$func" == "main" && "$file" == "$0" ]] && func="[Script Top Level]"
        
        printf "  File \"%s\", line %d, in %s\n" "$file" "$line" "$func" >&2
    done
    
    echo "--------------------------------------------------------" >&2
    
    # Cleanup and exit as before
    HANDLER_ARGS=()
    export CURRENT_CONTEXT="DEFAULT"
    echo "exiting with code: $exit_code" >&2
    exit "$exit_code"
}

# --- 5. UNIFIED THROWER ---
throw_exception() {
    local custom_code=1
    local context="$1"
    [[ -z "$context" ]] && { echo "[throw_exception error] Context name required"; return 1; }

    if [[ "$2" =~ ^[0-9]+$ ]]; then
        custom_code="$2"
        shift 2
    else
        shift 1
    fi

    export CURRENT_CONTEXT="$context"
    HANDLER_ARGS=("$@")

    # 1. Trigger the trap
    (exit "$custom_code")

    # 2. Prevent the function itself from returning 1 and re-triggering the trap
    return 0
}

# --- 6. REGISTRATION ---
register_handler() {
    local force=false
    [[ "$1" == "-f" ]] && { force=true; shift; }

    local context="$1"
    local handler_cmd="$2"

    [[ -z "$context" || -z "$handler_cmd" ]] && return 1
    [[ -n "${HANDLERS[$context]}" && "$force" == false ]] && return 1
    ! type "$handler_cmd" > /dev/null 2>&1 && return 1

    HANDLERS["$context"]="$handler_cmd"
}

# --- 7. SMART DISPATCH ENGINE ---
dispatch_exception() {
    local exit_code=$?
    local failed_cmd="$BASH_COMMAND"
    local context="${CURRENT_CONTEXT:-DEFAULT}"
    local repair_func="${HANDLERS[$context]:-default_handler}"

    "$repair_func" "$context" "$exit_code" "$failed_cmd" "${HANDLER_ARGS[@]}"
    local handler_status=$?

    HANDLER_ARGS=()
    export CURRENT_CONTEXT="DEFAULT"

    [[ $handler_status -ne 0 ]] && exit $handler_status
    return 0
}

# --- 8. INITIALIZATION ---
trap 'dispatch_exception' ERR
register_handler "DEFAULT" "default_handler"

# Show help only if the script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "[Exception Handler Ready] Bash $BASH_VERSION detected."
    exception_handler_help
fi
