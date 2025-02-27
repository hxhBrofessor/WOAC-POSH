# ================================
# Angeles_Enum.psm1 - PowerShell Module for System Diagnostics
# ================================

# Enforce strict mode to catch potential issues
Set-StrictMode -Version Latest

# ------------------------------------
# Function: Get-OSDetails
# Purpose: Retrieves the operating system details (e.g., name and version) for a given computer.
# Usage: Defaults to the localhost if no computer name is provided.
# ------------------------------------
function Get-OSDetails {
    param ([string]$ComputerName = "localhost")
    try {
        # Retrieve OS and System Type information
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName
        $systemInfo = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $ComputerName

        # Structure the JSON properly without redundant nesting
        [PSCustomObject]@{
            OS_Details = @{
                Name        = $osInfo.Caption
                Version     = $osInfo.Version
                System_Type = $systemInfo.SystemType
            }
        }
    } catch {
        Write-Error "Failed to retrieve OS details for $ComputerName. Error: $_"
    }
}


# ------------------------------------
# Function: Get-StorageDetails
# Purpose: Retrieves storage details for the fixed disks (e.g., drive letter, total size, free space).
# Notes: Only fixed disks (DriveType=3) are included in the results.
# ------------------------------------
function Get-StorageDetails {
    param ([string]$ComputerName = "localhost")
    try {
        # Query fixed disks and format the output with device ID, total size, and free space in GB
        Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ComputerName $ComputerName |
                Select-Object @{
                    Name = "Storage_Details"
                    Expression = { [PSCustomObject]@{
                        Drive     = $_.DeviceID
                        Total_GB  = [math]::Round($_.Size / 1GB, 2)
                        Free_GB   = [math]::Round($_.FreeSpace / 1GB, 2)
                    } }
                }
    } catch {
        Write-Error "Failed to retrieve storage details for $ComputerName. Error: $_"
    }
}

# ------------------------------------
# Function: Get-InstalledApps
# Purpose: Lists installed applications for the system. Filters for applications related to "Microsoft" or "Windows".
# Notes: Uses the "Win32_Product" WMI class.
# ------------------------------------
function Get-InstalledApps {
    param ([string]$ComputerName = "localhost")
    try {
        # Filter installed applications for "Microsoft" or "Windows" and combine name with version
        Get-CimInstance -ClassName Win32_Product -ComputerName $ComputerName |
                Where-Object { $_.Name -match "Microsoft|Windows" } |
                Select-Object @{
                    Name = "Application"
                    Expression = { [PSCustomObject]@{
                        Name    = $_.Name
                        Version = $_.Version
                    } }
                }
    } catch {
        Write-Error "Failed to retrieve installed apps for $ComputerName. Error: $_"
    }
}

# ------------------------------------
# Function: Get-ProcessDetails
# Purpose: Retrieves process details, combining the process name with OS information (name and version).
# Notes: First gets OS information, then processes running on the system.
# ------------------------------------
function Get-ProcessDetails {
    param ([string]$ComputerName = "localhost")
    try {
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName
        Get-CimInstance -ClassName Win32_Process -ComputerName $ComputerName |
                Select-Object @{
                    Name = "Process_Details"
                    Expression = { [PSCustomObject]@{
                        Process       = $_.Name
                        OSName        = $osInfo.Caption
                        WindowsVersion = $osInfo.Version
                    } }
                }
    } catch {
        Write-Error "Failed to retrieve process details for $ComputerName. Error: $_"
    }
}


# ------------------------------------
# Function: Get-UserDetails
# Purpose: Retrieves local user account details, including admin group membership and security identifiers (SIDs).
# Notes:
#   - Uses different methods for local and remote systems to find admin group members.
#   - Tags accounts as "Admin" or "User" based on group membership.
# ------------------------------------
function Get-UserDetails {
    param ([string]$ComputerName = "localhost")
    try {
        $admins = Get-LocalGroupMember -Group "Administrators" | Select-Object -ExpandProperty Name
        $users = Get-CimInstance -ClassName Win32_UserAccount -ComputerName $ComputerName -Filter "LocalAccount=True"

        $users | Select-Object @{
            Name = "User_Details"
            Expression = { [PSCustomObject]@{
                Username = $_.Name
                SID      = $_.SID
                Type     = if ($admins -contains $_.Name) { "Admin" } else { "User" }
            } }
        }
    } catch {
        Write-Error "Failed to retrieve user details for $ComputerName. Error: $_"
    }
}


# ------------------------------------
# Function: Get-EnvironmentVariables
# Purpose: Retrieves specific environment variables (e.g., Path, PSModulePath) for a given computer.
# ------------------------------------
function Get-EnvironmentVariables {
    param ([string]$ComputerName = "localhost")
    try {
        # Specify the environment variables to retrieve
        $envVars = @("PSModulePath", "Path")
        # Fetch environment variables and combine their names with values
        Get-CimInstance -ClassName Win32_Environment -ComputerName $ComputerName |
                Where-Object { $_.Name -in $envVars } |
                Select-Object @{
                    Name = "Environment_Variable"
                    Expression = { [PSCustomObject]@{
                        Variable = $_.Name
                        Value    = $_.VariableValue
                    } }
                }
    } catch {
        Write-Error "Failed to retrieve environment variables for $ComputerName. Error: $_"
    }
}

# ------------------------------------
# Function: Get-NetworkInfo
# Purpose: Retrieves information about enabled network adapters, including IP and MAC addresses.
# Details: Combines adapter description, IP address, and MAC address into a single output.
# ------------------------------------
function Get-NetworkInfo {
    param ([string]$ComputerName = "localhost")
    try {
        # Retrieve details for network adapters with IP enabled
        Get-CimInstance -Class Win32_NetworkAdapterConfiguration -ComputerName $ComputerName -Filter "IPEnabled=True" |
                Select-Object @{
                    Name = "Network_Info"
                    Expression = { [PSCustomObject]@{
                        NIC  = $_.Description
                        IP   = $_.IPAddress
                        MAC  = $_.MACAddress
                    } }
                }
    } catch {
        Write-Error "Failed to retrieve network info for $ComputerName. Error: $_"
    }
}
