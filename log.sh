#!/bin/sh

# Output CSV file
CSV_FILE="cheri_combined_logs.csv"

# Initialize the CSV file with headers
if [ ! -f "$CSV_FILE" ]; then
    echo "Timestamp,CPU_Usage(%),Per_CPU_Usage(%),CPU_Cores,Load_Avg_1min,Load_Avg_5min,Load_Avg_15min,Memory_Usage(%),Total_Memory(MB),Used_Memory(MB),Free_Memory(MB),Swap_Usage(MB),Memory_Anomalies,Error_Logs,Memory_Access_Patterns,Targeted_PID,Targeted_Memory_Regions,Attack_Outcome" > "$CSV_FILE"
fi

# Variables to track state
LAST_ERROR_LOG=""
LAST_PID=""
LAST_ACCESS_PATTERN=""

# Function to get overall CPU usage
get_cpu_usage() {
    CPU_USAGE=$(top -d1 | grep "CPU:" | awk '{print $2}' | head -n1 || echo "0.0")
    echo "$CPU_USAGE"
}

# Function to get per-CPU usage
get_per_cpu_usage() {
    PER_CPU_USAGE=$(top -P -d1 | grep "CPU" | awk '{print $2}' | tr '\n' ';' || echo "N/A")
    echo "$PER_CPU_USAGE"
}

# Function to get number of CPU cores
get_cpu_cores() {
    CPU_CORES=$(sysctl -n hw.ncpu || echo "N/A")
    echo "$CPU_CORES"
}

# Function to get load averages
get_load_avg() {
    LOAD_AVG=$(sysctl -n vm.loadavg | awk '{print $2, $3, $4}' || echo "N/A N/A N/A")
    echo "$LOAD_AVG"
}

# Function to get memory usage details
get_memory_usage() {
    MEMORY_TOTAL=$(sysctl -n hw.physmem || echo "0")
    MEMORY_USED=$(sysctl -n vm.stats.vm.v_active_count || echo "0")
    MEMORY_FREE=$((MEMORY_TOTAL - (MEMORY_USED * $(sysctl -n hw.pagesize || echo "4096"))))
    MEMORY_TOTAL_MB=$((MEMORY_TOTAL / 1024 / 1024))
    MEMORY_USED_MB=$((MEMORY_USED * $(sysctl -n hw.pagesize || echo "4096") / 1024 / 1024))
    MEMORY_FREE_MB=$((MEMORY_FREE / 1024 / 1024))
    MEMORY_USAGE_PERCENT=$((MEMORY_USED_MB * 100 / MEMORY_TOTAL_MB))
    echo "$MEMORY_USAGE_PERCENT,$MEMORY_TOTAL_MB,$MEMORY_USED_MB,$MEMORY_FREE_MB"
}

# Function to get swap usage
get_swap_usage() {
    SWAP_USAGE=$(sysctl -n vm.swap_total || echo "0")
    SWAP_USAGE_MB=$((SWAP_USAGE / 1024 / 1024))
    echo "$SWAP_USAGE_MB"
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
        ktrace -p "$PID" 2>/dev/null
        sleep 0.5
        ACCESS_PATTERN=$(kdump | grep -E 'read|write' | tail -n 1 || echo "No access patterns detected")
        echo "$ACCESS_PATTERN"
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

    procstat -v "$PID" 2>/dev/null | awk '{print $1, $2, $3, $4}' | grep -i "rw" | head -n 3 || echo "No memory regions found"
}

# Main monitoring loop
echo "Starting CHERI memory monitoring and attack logging..."
while true; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    CPU_USAGE=$(get_cpu_usage)
    PER_CPU_USAGE=$(get_per_cpu_usage)
    CPU_CORES=$(get_cpu_cores)
    LOAD_AVG=$(get_load_avg)
    MEMORY_DETAILS=$(get_memory_usage)
    SWAP_USAGE=$(get_swap_usage)
    MEMORY_ANOMALIES=$(detect_memory_anomalies)
    ERROR_LOGS=$(get_error_logs)

    # Monitor access patterns
    ACCESS_PATTERNS=$(monitor_memory_access_patterns)
    if [ "$ACCESS_PATTERNS" = "$LAST_ACCESS_PATTERN" ]; then
        ACCESS_PATTERNS="No new patterns detected"
    else
        LAST_ACCESS_PATTERN="$ACCESS_PATTERNS"
    fi

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
    echo "$TIMESTAMP,$CPU_USAGE,\"$PER_CPU_USAGE\",$CPU_CORES,$LOAD_AVG,$MEMORY_DETAILS,$SWAP_USAGE,\"$MEMORY_ANOMALIES\",\"$ERROR_LOGS\",\"$ACCESS_PATTERNS\",\"$CURRENT_PID\",\"$TARGETED_MEMORY_REGIONS\",\"$ATTACK_OUTCOME\"" >> "$CSV_FILE"

    echo "Logged at $TIMESTAMP: CPU=${CPU_USAGE}, Per-CPU=${PER_CPU_USAGE}, Memory=${MEMORY_DETAILS}, Swap=${SWAP_USAGE}, Anomalies=${MEMORY_ANOMALIES}, Errors=${ERROR_LOGS}, Access Patterns=${ACCESS_PATTERNS}, PID=${CURRENT_PID}, Outcome=${ATTACK_OUTCOME}"

    sleep 0.5  # Adjust polling frequency for faster logging
done
