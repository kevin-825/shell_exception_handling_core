# test_recovery.sh
source ./exception_handling_core.sh

# 1. Define a specific repair function
my_fix_handler() {
    echo "[my_fix_handler] Handling error for key: $4"
    echo exit_code:$2
    return 0 # Tell the core to resume the worker
}

# 2. Register it
register_handler "JSON_FIX" "my_fix_handler"

# 3. The Worker Logic
echo "Step 1: Starting task..."

# Trigger the exception
throw_exception "JSON_FIX" "some_key.join(' ')"
throw_exception "JSON_FIX" 4 "some_key.join(' ')"

echo "Step 3: I survived! The repair tool worked."

exit_code=5
throw_exception "unknown_context" $exit_code "unknown_args0" "unknown_args1"

echo "enf of main 0"
echo "enf of main 1"

