#!/bin/sh

# Output CSV file
CSV_FILE="cheri_memory_anomalies.csv"

# Initialize the CSV file with headers
if [ ! -f "$CSV_FILE" ]; then
    echo "Timestamp,CPU_Usage(%),Memory_Usage(MB),Memory_Anomalies,Error_Logs" > "$CSV_FILE"
fi

# Function to get CPU usage
get_cpu_usage() {
    CPU_USAGE=$(top -d1 | grep "CPU:" | awk '{print $2}' | head -n1)
    echo "$CPU_USAGE"
}

# Function to get memory usage
get_memory_usage() {
    MEMORY_USAGE=$(vmstat -h | awk '/Pages active/ {print $3}' | head -n1)
    echo "$MEMORY_USAGE"
}

# Function to detect memory anomalies
detect_memory_access_anomalies() {
    ANOMALIES=$(dmesg | grep -i "capability fault" | tail -n 1)
    if [ -z "$ANOMALIES" ]; then
        echo "No anomalies detected"
    else
        echo "$ANOMALIES"
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
echo "Starting CHERI memory anomaly monitoring..."
while true; do
    # Timestamp
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Collect metrics
    CPU_USAGE=$(get_cpu_usage)
    MEMORY_USAGE=$(get_memory_usage)
    MEMORY_ANOMALIES=$(detect_memory_access_anomalies)
    ERROR_LOGS=$(get_error_logs)
    
    # Log to CSV
    echo "$TIMESTAMP,$CPU_USAGE,$MEMORY_USAGE,\"$MEMORY_ANOMALIES\",\"$ERROR_LOGS\"" >> "$CSV_FILE"
    
    # Print to terminal for live monitoring
    echo "Logged at $TIMESTAMP: CPU=${CPU_USAGE}%, Memory=${MEMORY_USAGE}MB, Anomalies=${MEMORY_ANOMALIES}, Errors=${ERROR_LOGS}"
    
    # Adjust logging frequency
    sleep 1
done
