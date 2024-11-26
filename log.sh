#!/bin/sh

# Output CSV file
CSV_FILE="cheri_combined_logs.csv"

# Initialize the CSV file with headers
if [ ! -f "$CSV_FILE" ]; then
    echo "Timestamp,CPU_Usage(%),Memory_Usage(MB),Memory_Anomalies,Error_Logs,Memory_Access_Patterns,Attack_Start,Attack_End,Duration(s),Targeted_PID,Targeted_Memory_Regions,Attack_Outcome" > "$CSV_FILE"
fi

# Function to get CPU usage
get_cpu_usage() {
    CPU_USAGE=$(top -d1 | grep "CPU:" | awk '{print $2}' | head -n1 || echo "0.0")
    echo "$CPU_USAGE"
}

# Function to get memory usage
get_memory_usage() {
    MEMORY_USED=$(sysctl -n vm.stats.vm.v_active_count || echo "0")
    MEMORY_TOTAL=$(sysctl -n vm.stats.vm.v_page_count || echo "1")
    PAGE_SIZE=$(sysctl -n hw.pagesize || echo "4096")

    MEMORY_USED_MB=$((MEMORY_USED * PAGE_SIZE / 1024 / 1024))
    MEMORY_TOTAL_MB=$((MEMORY_TOTAL * PAGE_SIZE / 1024 / 1024))

    if [ "$MEMORY_TOTAL_MB" -eq 0 ]; then
        echo "0%"
    else
        MEMORY_USAGE_PERCENT=$((MEMORY_USED_MB * 100 / MEMORY_TOTAL_MB))
        echo "$MEMORY_USAGE_PERCENT%"
    fi
}

# Function to detect memory anomalies
detect_memory_anomalies() {
    ANOMALIES=$(dmesg | grep -i "memory error" | grep -vi "icmp" | tail -n 1 || echo "No memory anomalies detected")
    echo "$ANOMALIES"
}

# Function to monitor memory access patterns using ktrace
monitor_memory_access_patterns() {
    PID=$(pgrep abs)  # Replace "abs" with your target process name
    if [ -n "$PID" ]; then
        ktrace -p "$PID"
        sleep 1
        kdump | grep -E 'read|write' | tail -n 1 || echo "No access patterns detected"
    else
        echo "No target process found"
    fi
}

# Function to fetch error logs (excluding ICMP-related messages)
get_error_logs() {
    ERROR_LOG=$(dmesg | grep -vi "icmp" | tail -n 1 || echo "No errors detected")
    echo "$ERROR_LOG"
}

# Function to fetch memory regions of the target process
fetch_memory_regions() {
    local PID=$1
    if [ -z "$PID" ]; then
        echo "No PID found"
        return
    fi

    procstat -v "$PID" | awk '{print $1, $2, $3, $4}' | grep -i "rw" | head -n 3 || echo "No memory regions found"
}

# Function to monitor attacks on the target process
log_attack() {
    local TARGET_PROCESS="abs"  # Replace with your target process name
    local CURRENT_PID=$(pgrep "$TARGET_PROCESS")

    if [ -z "$CURRENT_PID" ]; then
        echo "Target process not running."
        return
    fi

    START_TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    INITIAL_PID=$CURRENT_PID
    ATTACK_ONGOING=1

    while [ "$ATTACK_ONGOING" -eq 1 ]; do
        sleep 1  # Poll every second to monitor for errors or PID changes

        # Check for kernel errors related to the target process
        ERROR_LOG=$(dmesg | grep -i "segfault\|signal 34\|capability fault" | grep -vi "icmp" | tail -n 1 || echo "No errors detected")

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
            START_SEC=$(date -j -f "%Y-%m-%d %H:%M:%S" "$START_TIMESTAMP" "+%s")
            END_SEC=$(date -j -f "%Y-%m-%d %H:%M:%S" "$END_TIMESTAMP" "+%s")
            DURATION=$((END_SEC - START_SEC))
            MEMORY_REGIONS=$(fetch_memory_regions "$CURRENT_PID")

            # Log to combined CSV
            echo "$START_TIMESTAMP,$END_TIMESTAMP,$DURATION,$CURRENT_PID,\"$ERROR_LOG\",\"$MEMORY_REGIONS\",\"$OUTCOME\"" >> "$CSV_FILE"

            # Reset attack timer if PID changes
            if [ "$OUTCOME" = "Process Restarted" ]; then
                START_TIMESTAMP=$END_TIMESTAMP
            fi
        fi
    done
}

# Main monitoring loop
echo "Starting CHERI memory monitoring and attack logging..."
while true; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    CPU_USAGE=$(get_cpu_usage)
    MEMORY_USAGE=$(get_memory_usage)
    MEMORY_ANOMALIES=$(detect_memory_anomalies)
    MEMORY_ACCESS_PATTERNS=$(monitor_memory_access_patterns)
    ERROR_LOGS=$(get_error_logs)

    # Log everything into a single CSV file
    echo "$TIMESTAMP,$CPU_USAGE,$MEMORY_USAGE,\"$MEMORY_ANOMALIES\",\"$ERROR_LOGS\",\"$MEMORY_ACCESS_PATTERNS\",\"N/A\",\"N/A\",\"N/A\",\"N/A\",\"N/A\",\"N/A\"" >> "$CSV_FILE"

    # Check for attacks on the target process
    log_attack &  # Run attack logging in the background

    echo "Logged at $TIMESTAMP: CPU=${CPU_USAGE}, Memory=${MEMORY_USAGE}, Anomalies=${MEMORY_ANOMALIES}, Errors=${ERROR_LOGS}, Access Patterns=${MEMORY_ACCESS_PATTERNS}"

    sleep 1  # Adjust frequency of monitoring
done
