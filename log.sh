#!/bin/bash

# Unified CSV log file
output_csv="cheribsd_logs.csv"

# Write CSV header
echo "Timestamp,CPU_Usage,Memory_Usage(MB),Memory_Active_Pages,Attack_Timestamp,Attack_Type,Targeted_Region,Impacted_Variable,Attack_Outcome,Accessed_Memory_Region,Exceptions" > $output_csv

# Function to monitor CPU usage
get_cpu_usage() {
    sysctl -n vm.loadavg | awk '{print $1}'  # Return only the 1-minute load average
}

# Function to monitor memory usage
get_memory_usage() {
    physmem=$(sysctl -n hw.physmem)
    active_pages=$(sysctl -n vm.stats.vm.v_active_count)
    # Convert bytes to MB
    memory_mb=$((physmem / 1024 / 1024))
    echo "$memory_mb,$active_pages"
}

# Function to monitor memory access (via dtrace)
get_memory_access() {
    dtrace_output=$(dtrace -n 'pid$target:memory::entry { printf("%p\n", arg0); }' -p $1 -c sleep 1 2>/dev/null)
    if [ -z "$dtrace_output" ]; then
        echo "No memory access recorded"
    else
        echo "$dtrace_output"
    fi
}

# Function to simulate attack logging
log_attack() {
    # Example attack data (replace with your real attack simulation script)
    attack_type="BufferOverflow"
    targeted_region="0x7fffabcde000"
    impacted_variable="VariableX"
    outcome="Success"
    attack_timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$attack_timestamp,$attack_type,$targeted_region,$impacted_variable,$outcome"
}

# Function to get exception logs
get_exceptions() {
    tail -n 1 /var/log/messages 2>/dev/null || echo "No new exceptions"
}

# Start the logging process
while true; do
    # Get current timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Collect CPU and memory usage
    cpu_usage=$(get_cpu_usage)
    memory_data=$(get_memory_usage)
    memory_usage=$(echo "$memory_data" | cut -d',' -f1)
    active_pages=$(echo "$memory_data" | cut -d',' -f2)

    # Simulate an attack and log its data
    attack_data=$(log_attack)
    attack_timestamp=$(echo "$attack_data" | cut -d',' -f1)
    attack_type=$(echo "$attack_data" | cut -d',' -f2)
    targeted_region=$(echo "$attack_data" | cut -d',' -f3)
    impacted_variable=$(echo "$attack_data" | cut -d',' -f4)
    attack_outcome=$(echo "$attack_data" | cut -d',' -f5)

    # Log memory access during the attack
    attack_pid=$$  # Assuming the attack is run in the current script
    accessed_memory=$(get_memory_access $attack_pid)

    # Collect the latest exception logs
    exceptions=$(get_exceptions)

    # Append all data into a single row in the CSV file
    echo "$timestamp,$cpu_usage,$memory_usage,$active_pages,$attack_timestamp,$attack_type,$targeted_region,$impacted_variable,$attack_outcome,\"$accessed_memory\",\"$exceptions\"" >> $output_csv

    # Add a delay (e.g., 1 second) to prevent overloading
    sleep 1
done
