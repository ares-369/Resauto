import subprocess
import psutil
import csv
import time
from datetime import datetime
import os

# Output CSV file
csv_file = "cheri_memory_anomalies.csv"
write_headers = not os.path.exists(csv_file)

# Function to log metrics into a CSV file
def log_to_csv(timestamp, cpu_usage, memory_usage, memory_anomalies, error_logs):
    with open(csv_file, 'a', newline='') as file:
        writer = csv.writer(file)
        if write_headers:
            writer.writerow([
                "Timestamp", 
                "CPU_Usage(%)", 
                "Memory_Usage(MB)", 
                "Memory_Anomalies", 
                "Error_Logs"
            ])
        writer.writerow([
            timestamp, 
            cpu_usage, 
            memory_usage, 
            memory_anomalies, 
            error_logs
        ])

# Function to record system metrics
def get_system_metrics():
    cpu_usage = psutil.cpu_percent(interval=1)
    memory_usage = psutil.virtual_memory().used / (1024 * 1024)  # Convert to MB
    return cpu_usage, memory_usage

# Function to detect memory access anomalies
def detect_memory_access_anomalies():
    try:
        # Check kernel logs for CHERI capability faults
        logs = subprocess.check_output(['dmesg'], text=True)
        anomalies = [line for line in logs.splitlines() if "capability fault" in line]
        return anomalies[-1] if anomalies else "No anomalies detected"
    except Exception as e:
        return f"Error detecting anomalies: {str(e)}"

# Function to fetch system error logs
def get_error_logs():
    try:
        # Fetch the last error from dmesg
        logs = subprocess.check_output(['dmesg'], text=True)
        return logs.splitlines()[-1] if logs else "No errors detected"
    except Exception as e:
        return f"Error fetching logs: {str(e)}"

# Monitoring loop
def monitor():
    print("Starting CHERI monitoring...")
    try:
        while True:
            timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            cpu_usage, memory_usage = get_system_metrics()
            memory_anomalies = detect_memory_access_anomalies()
            error_logs = get_error_logs()

            # Log data to CSV
            log_to_csv(timestamp, cpu_usage, memory_usage, memory_anomalies, error_logs)
            print(f"Logged at {timestamp}: CPU={cpu_usage}%, Memory={memory_usage}MB, Anomalies={memory_anomalies}")
            
            # Adjust sleep interval for logging frequency
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nMonitoring interrupted by user.")

# Main function
if __name__ == "__main__":
    try:
        monitor()
    except KeyboardInterrupt:
        print("\nExiting.")
