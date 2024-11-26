#!/bin/sh

# Output CSV file
CSV_FILE="cheri_combined_logs.csv"

# Initialize the CSV file with headers
if [ ! -f "$CSV_FILE" ]; then
    echo "Timestamp,CPU_Usage(%),Memory_Usage(MB),Memory_Anomalies,Error_Logs,Memory_Access_Patterns,Targeted_PID,Targeted_Memory_Regions,Attack_Outcome" > "$CSV_FILE"
fi

# Variables to track state
LAST_ERROR_LOG=""
LAST_PID=""

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

# Function to monitor memory access patterns
monitor_memory_access_patterns() {
    PID=$(pgrep abs)  # Replace "abs" with your target process name
    if [ -n "$PID" ]; then
        ktrace -p "$PID"
        sleep 0.5
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

# Main monitoring loop
echo "Starting CHERI memory monitoring and attack logging..."
while true; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    CPU_USAGE=$(get_cpu_usage)
    MEMORY_USAGE=$(get_memory_usage)
    MEMORY_ANOMALIES=$(detect_memory_anomalies)
    MEMORY_ACCESS_PATTERNS=$(monitor_memory_access_patterns)
    ERROR_LOGS=$(get_error_logs)

    # Check for PID changes and log attack details
    CURRENT_PID=$(pgrep abs)  # Replace "abs" with your target process name
    if [ "$CURRENT_PID" != "$LAST_PID" ]; then
        # PID change indicates a restart or new process instance
        if [ -n "$CURRENT_PID" ]; then
            ATTACK_OUTCOME="Process Restarted"
            TARGETED_MEMORY_REGIONS=$(fetch_memory_regions "$CURRENT_PID")
            LAST_PID="$CURRENT_PID"
        else
            ATTACK_OUTCOME="Process Stopped"
            TARGETED_MEMORY_REGIONS="N/A"
        fi
    else
        ATTACK_OUTCOME="No Impact"
        TARGETED_MEMORY_REGIONS="N/A"
    fi

    # Log to CSV
    echo "$TIMESTAMP,$CPU_USAGE,$MEMORY_USAGE,\"$MEMORY_ANOMALIES\",\"$ERROR_LOGS\",\"$MEMORY_ACCESS_PATTERNS\",\"$CURRENT_PID\",\"$TARGETED_MEMORY_REGIONS\",\"$ATTACK_OUTCOME\"" >> "$CSV_FILE"

    echo "Logged at $TIMESTAMP: CPU=${CPU_USAGE}, Memory=${MEMORY_USAGE}, Anomalies=${MEMORY_ANOMALIES}, Errors=${ERROR_LOGS}, Access Patterns=${MEMORY_ACCESS_PATTERNS}, PID=${CURRENT_PID}, Outcome=${ATTACK_OUTCOME}"

    sleep 0.5  # Reduced polling frequency for faster logging
done
