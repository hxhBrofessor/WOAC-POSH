# ================================
# Angeles_StartUp.ps1 - PowerShell StartUp Script to import Angeles_Enum Module
# ================================

# Import the required module containing custom functions
$modulePath = Join-Path $PSScriptRoot "Angeles_Enum.psm1"
$moduleFullPath = (Resolve-Path $modulePath).Path
Import-Module $moduleFullPath -Force

# Display ASCII art from the file 'daArt.txt' (optional aesthetic enhancement)
# A friendly greeting to users; color-coded message for better visibility
$asciiArtPath = Join-Path $PSScriptRoot "daArt.txt"
if (Test-Path $asciiArtPath) {
    $asciiArt = Get-Content $asciiArtPath -Raw
    Write-Host "`n$asciiArt`n" -ForegroundColor Cyan
} else {
    # Indicate that the optional art file is missing
    Write-Host "ASCII art file not found: $asciiArtPath" -ForegroundColor Red
}

# Extract all function names starting with "Get-" from the module.
# This assumes all pertinent diagnostic functions in the module use this naming convention.
$Functions = Get-Content $moduleFullPath | Select-String -Pattern "^function Get-" | ForEach-Object { ($_ -split "\s+")[1] }

# Exit if no functions are detected in the module.
if ($Functions.Count -eq 0) {
    Write-Host "No diagnostic functions found in the module. Exiting." -ForegroundColor Yellow
    exit
}

# Prompt the user for computer names to target. Default to the local machine if no input is given.
# Ensure input is handled correctly and spaces are trimmed from the names.
$ComputerInput = Read-Host "Enter computer names (comma-separated, blank for local machine)"
if (-not $ComputerInput) {
    # Default to executing on the local computer
    $ComputerNames = @($env:COMPUTERNAME)
} else {
    $ComputerNames = $ComputerInput -split ',' | ForEach-Object { $_.Trim() }
}

# Validate the provided computer names.
# Allow only valid characters: letters, digits, dots, and hyphens.
$ComputerNames = $ComputerNames | Where-Object { $_ -match '^[a-zA-Z0-9.-]+$' }

# Exit if no valid computer names are provided.
if ($ComputerNames.Count -eq 0) {
    Write-Host "Invalid computer names provided. Exiting..." -ForegroundColor Red
    exit
}

# Main processing loop: Enumerate each computer in the list provided by the user.
foreach ($ComputerName in $ComputerNames) {
    Write-Host "`nProcessing system: $ComputerName" -ForegroundColor Yellow

    # Define the path for saving the diagnostic results in JSON format.
    $jsonPath = "\\$ComputerName\C$\Tmp\data_retrieved.json"

    # Ensure the destination directory exists on the target computer.
    if (!(Test-Path "\\$ComputerName\C$\Tmp")) {
        # Create the directory if it doesn't exist, using -Force to avoid errors if there are existing folders.
        New-Item -Path "\\$ComputerName\C$\Tmp" -ItemType Directory -Force | Out-Null
    }

    # Track progress as each diagnostic function is run
    $totalFunctions = $Functions.Count
    $completedFunctions = 0

    # Launch each function as a background job for parallel processing
    $jobs = @()
    foreach ($func in $Functions) {
        Write-Progress -Activity "Starting enumeration jobs for $ComputerName" -Status "Running: $func" -PercentComplete (($completedFunctions / $totalFunctions) * 100)

        # Use Start-Job to execute each function asynchronously
        $job = Start-Job -ScriptBlock {
            param ($mod, $funcName, $comp)
            Import-Module $mod -Force | Out-Null        # Import the required module inside the job's runspace
            $result = & $funcName -ComputerName $comp  # Execute the current function for the specified computer
            Write-Output $result                       # Output the result of the function call
        } -ArgumentList $moduleFullPath, $func, $ComputerName

        $jobs += $job  # Store the job for further monitoring
    }

    # Periodically check the status of jobs and update the progress bar
    do {
        $runningJobs = Get-Job -State Running
        $completedFunctions = $totalFunctions - $runningJobs.Count
        Write-Progress -Activity "Processing jobs for $ComputerName" -Status "Completed: $completedFunctions of $totalFunctions" -PercentComplete (($completedFunctions / $totalFunctions) * 100)

        Start-Sleep -Seconds 1  # Pause for a second before the next update
    } while ($runningJobs.Count -gt 0)

    # Retrieve results from all jobs and clean up completed jobs
    $results = Receive-Job -Job $jobs   # Collect results from finished jobs
    Remove-Job -Job $jobs | Out-Null    # Remove jobs to free resources

    # Combine all results into a single hashtable for easier JSON conversion
    $allResults = @{}

    # Process each result object received from the jobs and extract properties
    foreach ($result in $results) {
        foreach ($prop in $result.PSObject.Properties) {
            # Exclude redundant or unnecessary properties
            if ($prop.Name -notin @("RunspaceId", "PSComputerName", "PSShowComputerName")) {
                if (-not $allResults.ContainsKey($prop.Name)) {
                    $allResults[$prop.Name] = @()  # Initialize the key if it doesn't exist
                }
                $allResults[$prop.Name] += $prop.Value
            }
        }
    }

    # Reorder results so "OS_Details" appears first (if available) for better readability
    if ($allResults.ContainsKey("OS_Details")) {
        $orderedResults = [ordered]@{"OS_Details" = $allResults["OS_Details"]}
        foreach ($key in $allResults.Keys | Where-Object { $_ -ne "OS_Details" }) {
            $orderedResults[$key] = $allResults[$key]
        }
    } else {
        # If "OS_Details" is absent, maintain the existing order
        $orderedResults = [ordered]@{}
        foreach ($key in $allResults.Keys) {
            $orderedResults[$key] = $allResults[$key]
        }
    }

    # Save the final results to a JSON file on the target system
    $finalResults = [ordered]@{$ComputerName = $orderedResults}
    $finalResults | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

    # Define event log details
    $logName = "System"
    $eventSource = "WinResTool"

    # Ensure the event source exists in the System log (requires Admin privileges)
    if (-not [System.Diagnostics.EventLog]::SourceExists($eventSource)) {
        try {
            New-EventLog -LogName $logName -Source $eventSource
            Write-Host "Event source '$eventSource' registered successfully under '$logName' log." -ForegroundColor Green
        } catch {
            Write-Host "Failed to create event source. Try running PowerShell as Administrator." -ForegroundColor Red
            exit
        }
    }

    # Write a completion message to the System event log
    try {
        Write-EventLog -LogName $logName -Source $eventSource -EntryType Information -EventId 10001 -Message "Diagnostics complete for $ComputerName."
    } catch {
        Write-Host "Failed to write event log." -ForegroundColor Red
    }

    # Retrieve and display the last 30 minutes of logs from the "System" event log related to this tool
    try {
        $logs = Get-EventLog -LogName "System" -After (Get-Date).AddMinutes(-30) | Where-Object { $_.Source -eq "WinResTool" }

        if ($logs) {
            Write-Host "`nRecent Logs for WinResTool in the 'System' Log:" -ForegroundColor Cyan
            $logs | Format-Table TimeGenerated, EntryType, Message -AutoSize
        } else {
            Write-Host "No relevant logs found in the last 30 minutes in the 'System' log." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Unable to retrieve event logs from the 'System' log." -ForegroundColor Red
    }

    # Confirm that the results were saved successfully
    Write-Host "Results saved to $jsonPath for $ComputerName"
}

# Inform the user that all processing is complete
Write-Host "All systems completed successfully!" -ForegroundColor Green