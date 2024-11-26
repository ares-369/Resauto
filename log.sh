#!/bin/sh

# Output CSV file
CSV_FILE="cheri_memory_anomalies.csv"

# Initialize the CSV file with headers
if [ ! -f "$CSV_FILE" ]; then
    echo "Timestamp,CPU_Usage(%),Memory_Usage(MB),Memory_Anomalies,Error_Logs,Memory_Access_Patterns" > "$CSV_FILE"
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
    # Start tracing the process if PID is known
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

# Monitoring loop
echo "Starting CHERI memory monitoring..."
while true; do
    # Timestamp
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Collect metrics
    CPU_USAGE=$(get_cpu_usage)
    MEMORY_USAGE=$(get_memory_usage)
    MEMORY_ANOMALIES=$(detect_memory_anomalies)
    MEMORY_ACCESS_PATTERNS=$(monitor_memory_access_patterns)
    ERROR_LOGS=$(get_error_logs)
    
    # Log to CSV
    echo "$TIMESTAMP,$CPU_USAGE,$MEMORY_USAGE,\"$MEMORY_ANOMALIES\",\"$ERROR_LOGS\",\"$MEMORY_ACCESS_PATTERNS\"" >> "$CSV_FILE"
    
    # Print to terminal for live monitoring
    echo "Logged at $TIMESTAMP: CPU=${CPU_USAGE}, Memory=${MEMORY_USAGE}, Anomalies=${MEMORY_ANOMALIES}, Errors=${ERROR_LOGS}, Access Patterns=${MEMORY_ACCESS_PATTERNS}"
    
    # Adjust logging frequency
    sleep 1
done
