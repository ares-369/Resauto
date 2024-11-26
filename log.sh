#!/bin/sh

# Output CSV files
PERFORMANCE_CSV="cheri_memory_anomalies.csv"
ATTACK_CSV="memory_attack_logs.csv"

# Initialize the CSV files with headers
if [ ! -f "$PERFORMANCE_CSV" ]; then
    echo "Timestamp,CPU_Usage(%),Memory_Usage(MB),Memory_Anomalies,Error_Logs,Memory_Access_Patterns" > "$PERFORMANCE_CSV"
fi

if [ ! -f "$ATTACK_CSV" ]; then
    echo "Start_Timestamp,End_Timestamp,Duration(s),Targeted_Process_PID,Error_Log,Targeted_Memory_Regions,Attack_Outcome" > "$ATTACK_CSV"
fi

# Function to get CPU usage
get_cpu_usage() {
    CPU_USAGE=$(top -d1 | grep "CPU:" | awk '{print $2}' | head -n1)
    echo "$CPU_USAGE"
}

# Function to get memory usage
get_memory_usage() {
    MEMORY_USED=$(sysctl -n vm.stats.vm.v_active_count)
    MEMORY_TOTAL=$(sysctl -n vm.stats.vm.v_page_count)
    PAGE_SIZE=$(sysctl -n hw.pagesize)

    MEMORY_USED_MB=$((MEMORY_USED * PAGE_SIZE / 1024 / 1024))
    MEMORY_TOTAL_MB=$((MEMORY_TOTAL * PAGE_SIZE / 1024 / 1024))

    MEMORY_USAGE_PERCENT=$((MEMORY_USED_MB * 100 / MEMORY_TOTAL_MB))
    echo "$MEMORY_USAGE_PERCENT%"
}

# Function to detect memory anomalies
detect_memory_anomalies() {
    ANOMALIES=$(dmesg | grep -i "memory error" | tail -n 1)
    if [ -z "$ANOMALIES" ]; then
        echo "No memory anomalies detected"
    else
        echo "$ANOMALIES"
    fi
}

# Function to monitor memory access patterns using ktrace
monitor_memory_access_patterns() {
    PID=$(pgrep abs)  # Replace "abs" with your target process name
    if [ -n "$PID" ]; then
        ktrace -p "$PID"
        sleep 1
        kdump | grep -E 'read|write' | tail -n 1
    else
        echo "No target process found"
    fi
}

# Function to fetch error logs
get_error_logs() {
    ERROR_LOG=$(dmesg | tail -n 1)
    if [ -z "$ERROR_LOG" ]; then
        echo "No errors detected"
    else
        echo "$ERROR_LOG"
    fi
}

# Function to fetch memory regions of the target process
fetch_memory_regions() {
    local PID=$1
    if [ -z "$PID" ]; then
        echo "No PID found"
        return
    fi

    procstat -v "$PID" | awk '{print $1, $2, $3, $4}' | grep -i "rw" | head -n 3
}

# Function to monitor attacks on the target process
log_attack() {
    local TARGET_PROCESS="abs"  # Replace with your target process name
    local CURRENT_PID=$(pgrep "$TARGET_PROCESS")

    if [ -z "$CURRENT_PID" ]; then
        echo "Target process not running."
        return
    fi

    echo "Monitoring attack on process '$TARGET_PROCESS' (Initial PID: $CURRENT_PID)..."

    START_TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    INITIAL_PID=$CURRENT_PID
    ATTACK_ONGOING=1

    while [ "$ATTACK_ONGOING" -eq 1 ]; do
        sleep 1  # Poll every second to monitor for errors or PID changes

        # Check for kernel errors related to the target process
        ERROR_LOG=$(dmesg | grep -i "segfault\|signal 34\|capability fault" | tail -n 1)

        # Check if the PID has changed (indicating the process has restarted)
        NEW_PID=$(pgrep "$TARGET_PROCESS")
        if [ -z "$NEW_PID" ]; then
            ATTACK_ONGOING=0
            OUTCOME="Process Stopped"
        elif [ "$NEW_PID" != "$CURRENT_PID" ]; then
            CURRENT_PID=$NEW_PID
            OUTCOME="Process Restarted"
        else
            OUTCOME="No Impact"
        fi

        # Log attack details when an error is detected
        if [ ! -z "$ERROR_LOG" ]; then
            END_TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
            DURATION=$(( $(date -d "$END_TIMESTAMP" +%s) - $(date -d "$START_TIMESTAMP" +%s) ))
            MEMORY_REGIONS=$(fetch_memory_regions "$CURRENT_PID")

            # Log to attack CSV
            echo "$START_TIMESTAMP,$END_TIMESTAMP,$DURATION,$CURRENT_PID,\"$ERROR_LOG\",\"$MEMORY_REGIONS\",\"$OUTCOME\"" >> "$ATTACK_CSV"

            # Reset attack timer if PID changes
            if [ "$OUTCOME" = "Process Restarted" ]; then
                START_TIMESTAMP=$END_TIMESTAMP
            fi
        fi
    done

    echo "Attack monitoring completed."
}

# Main monitoring loop
echo "Starting CHERI memory monitoring and attack logging..."
while true; do
    # Timestamp
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # Collect performance metrics
    CPU_USAGE=$(get_cpu_usage)
    MEMORY_USAGE=$(get_memory_usage)
    MEMORY_ANOMALIES=$(detect_memory_anomalies)
    MEMORY_ACCESS_PATTERNS=$(monitor_memory_access_patterns)
    ERROR_LOGS=$(get_error_logs)

    # Log to performance CSV
    echo "$TIMESTAMP,$CPU_USAGE,$MEMORY_USAGE,\"$MEMORY_ANOMALIES\",\"$ERROR_LOGS\",\"$MEMORY_ACCESS_PATTERNS\"" >> "$PERFORMANCE_CSV"

    # Check for attacks on the target process
    log_attack &  # Run attack logging in the background

    # Print to terminal for live monitoring
    echo "Logged at $TIMESTAMP: CPU=${CPU_USAGE}, Memory=${MEMORY_USAGE}, Anomalies=${MEMORY_ANOMALIES}, Errors=${ERROR_LOGS}, Access Patterns=${MEMORY_ACCESS_PATTERNS}"

    # Adjust logging frequency
    sleep 1
done
