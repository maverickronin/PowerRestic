# PowerRestic - Text Menu interface for restic
# Copyright (C) 2025    maverickronin

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published
# by the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.

# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

####################################################################
#Reset settings and other declarations
####################################################################
#Resets everything else if you're using this in ISE/VS Code or something

$ErrorActionPreference = 'Stop'
$FormatEnumerationLimit = -1
$ResticPath = $null
$MenuAddress = 0
$RClonePath = $null
$RCloneInPath = $false

enum RestoreOverwriteOption {
    Different
    Newer
    Never
}

####################################################################
#Self called functions and helpers
####################################################################

#Basic checks for PowerShell Group Policy logging registry keys.  Exits if  they are active.
if (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription") {
    if ($(get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription").EnableTranscripting -eq 1) {
        Write-Host "PowerShell transcription is enabled"
        exit 1
    }
}
if (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging") {
    if ($(get-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging").EnableModuleLogging -eq 1) {
        Write-Host "PowerShell module logging is enabled"
        exit 1
    }
}

#Script calls self as Restic/Rclone password command to decrypt cached credentials
if ($args[0] -ne $null) {
    if (Test-Path $args[0]) {
        $Credential = Import-Clixml -Path "$($args[0])"
        $PlainTextPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR(($Credential).Password))
        $PlainTextPassword
        exit
    } else {
        exit
    }
}

####################################################################
#Functions
####################################################################

function Clear-Variables {
    #Clear menu navigation relevant variables when needed while ascending menu trees

    try {Remove-Variable -name MenuChoice -Scope script -ErrorAction Stop} catch {} #Menu choice entered by user
    ##Use Remove-Variable here and other places in order to reset the type for next use
    $script:MenuPage = 1 #For keeping the same page if the menu options don't change
    $script:KeepPage = $false #as above
    $script:RepoPath = $null #Path to root folder of selected repository
    $script:RepoPassword = $null #Password to selected repository
    $script:RepoPasswordCommand = $null #No password flag added to repo command is set
    $env:RESTIC_PASSWORD = $null #Environment variable Restic reads the password from
    $env:RESTIC_PASSWORD_COMMAND = $null #Command printing the password for the repository to stdout
    $script:RepoStats = $null #Object repository information from different  commands is merged into
    $script:RepoOpened = $false #Set to true after basic info is successfully read from repository
    $script:RepoInfo = $null #Identifying info read from repo as part of testing path/password
    $env:RCLONE_CONFIG = "" #Path to RClone conf file for currently selected repo
    $env:RCLONE_PASSWORD_COMMAND = $null
    [array]$script:SnapIDs = @() #Restic's short snapshot IDs.  Used to get info about or browse a specific snapshot
    $script:SnapID = $null #Selected snapshot short ID for querying info or browsing
    $Script:NoPinned = $false #Set to true if Load-ini finds pinned repos
    [string[]] $script:Snapshots = @() #Snapshot list formatted for Show-Menu
    $Script:SnapshotStatsRaw = $null #Object Restic's nested json snapshot info is put into
    [string[]]$script:SnapshotStatsFormatted = @() #Array of the useful data in formatted strings
    $script:FolderPath = $null #Current path being browsed in snapshot
    [array]$script:FolderData = $null #Object with converted data from Restic's json fo a single folder in a snapshot
    [array]$script:FolderDirs = @() #Directories extracted from $FolderData and sorted
    [array]$script:FolderFiles = @() #Files extracted from $FolderData and sorted
    [array]$script:FolderDirsAndFiles = @() #Combination of the above
    [string[]]$script:FolderLines = @() #Sorted and formatted data from $Folder$Dirs and $FolderFiles tha can be fed to Show-Menu
    [array]$script:FolderDataRecursiveRaw = @() #Restic's raw json data folder's recursive contents
    [array]$script:FolderDataRecursiveFormatted = @() #Raw json data tallied up
    [string[]]$script:FileDetailsFormatted = @() #basic file info
    $script:RestoreFromSingle = $null #Individual item chosen in browse/restore menu
    [System.Collections.ArrayList]$script:RestoreFromQueue = @() #List of items Queued to restore together
    $script:RestoreTo = "" #Folder to restore the item to
    $script:NewRepoPath = "" #Path to create new repo at
    $script:RepoCheckCommand = "" #Command specifying options for checking repository integrity
    $script:RestoreOverwriteOption = [RestoreOverwriteOption]::Different #if/when to overwrite existing files - Different, Newer, Never
    $script:RestoreDeleteOption = $false #If to delete existing files  not in snapshot
    $script:RestoreDryRunOption = $false #Dry run to double check dangerous operations
    $script:CurrentLogPath = "" #Current location to write lof files to, based on selected repository
    $script:LastRestoreLog = "" #File name of last saved restore log file
    $script:DryRunQueueMode = "" #Approve dry run results one at a time for each item in the queue or approve/deny all together - Individual, Group
    [string[]]$script:QueueRestoreLogPaths = @() #Paths to all restore logs generated by queue restore in group dry run mode
    [string[]]$script:WinHostDrives = @() #Drive letters of local, fixed storage devices
    [string]$script:WinHostFolderPath = $null #Current folder being browsed in local storage
    [array]$script:WinHostFolders = @() #Array of subfolders of $WinHostFolderPath as objects
    [string[]]$script:WinHostFolderLines = @() #Subfolders of $WinHostFolderPath formatted as strings for menu display
}

function Load-ini {
    #Try to load ini file and figure out/create required settings if the ini file is missing

    #Reset changable settings
    [string[]] $script:Pinned = @()
    [string[]] $script:RCLoneConfs = @()
    $script:Options = new-object PSobject

    #Load ini if it exists
    if (test-path "PowerRestic.ini") {
        $RawIni = get-content "PowerRestic.ini"
        #Ignore string parsing failures because everything is going to be better validated later
        $ErrorActionPreference = 'SilentlyContinue'
        foreach ($line in $RawIni) {
            #Check for restic.exe path
            if ($line -like "ResticPath=*" -and (test-path $(Unquote-Path(($line.substring((($line.split("="))[0]).length + 1).trim()))))) {
                $script:ResticPath = $(Unquote-Path($line.substring((($line.split("="))[0]).length + 1).trim()))
            #Check for RClone.exe path
            } elseif ($line -like "RClonePath=*" -and (test-path $(Unquote-Path(($line.substring((($line.split("="))[0]).length + 1).trim()))))) {
                $script:RClonePath = $(Unquote-Path($line.substring((($line.split("="))[0]).length + 1).trim()))
            #Make an array of pinned repos
            } elseif ($line -like "pin*=*") {
                $script:Pinned += $line.substring((($line.split("="))[0]).length + 1).trim()
            } elseif ($line -like "RCloneConf*=*") {
                $script:RCLoneConfs += $line.substring((($line.split("="))[0]).length + 1).trim()
            #Skip comments, section headers,blank lines, lines starting with a space
            } elseif ($line[0] -in @(";","[",""," ") -or "=" -notin $line.ToCharArray()) {
                #noop
            #Throw everything else in a generic option object
            } else {
                #Skip second item if there are duplicate names
                if ((($line.split("="))[0]).trim() -notin $script:Options.PSObject.Properties.Name) {
                    $script:Options | Add-Member -NotePropertyName (($line.split("="))[0]).trim() $line.substring((($line.split("="))[0]).length + 1).trim() | out-null
                }
            }
        }
        $ErrorActionPreference = 'Stop'
        #Validate settings
        Check-Settings
    } else {
        #Setting validation sets defaults will be written to ini if it's missing
        Check-Settings
        Make-Ini
    }
    #Always double check path exists and prompt for new path if needed
    Find-ResticPath
}

function Check-Settings {
    #Set defaults for missing or invalid setting data in $script:Options

    if ("Retries" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "Retries" 3  | out-null
    } else {
        try {[int]::Parse($script:Options.Retries) | out-null} catch {$script:Options.Retries = 3}
        if ($script:Options.Retries -lt 1) {$script:Options.Retries = 3}
    }

    if ("DisplayLines" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "DisplayLines" 40  | out-null
    } else {
        try {[int]::Parse($script:Options.DisplayLines) | out-null} catch {$script:Options.DisplayLines = 40}
        if ($script:Options.DisplayLines -lt 10) {$script:Options.DisplayLines = 10}
    }

    if ("AutoOpenDryRunLog" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "AutoOpenDryRunLog" 1  | out-null
    } else {
        if ($script:Options.AutoOpenDryRunLog -notin 0,1) {$script:Options.AutoOpenDryRunLog = 1}
    }

    #Logs default to inside the repository being accessed
    #Variable name stored as string literal so it can be expanded later with Invoke-Expression
$LogSubDirs =
@'
+ "\" + ((($script:RepoPath).Replace(":","")).Replace("/","\")).Trim("\")
'@
    if ("LogPath" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "LogPath" "`"`$script:RepoPath\pr_data`""  | out-null
    } else {
        #Test if value is valid as either and absolute or relative path
        $a = Validate-WinPath ($script:Options.LogPath).trim("\")
        $r = Validate-WinPath ($script:Options.LogPath).trim("\") -Relative
        if ($a[0] -eq $true) {
            $script:Options.LogPath = '"' + $($a[1]).trim("\") + '"' + $LogSubDirs
        } elseif ($r[0] -eq $true) {
            $script:Options.LogPath = '"' + $($r[1]).trim("\") + '"' + $LogSubDirs
        } else {
            $script:Options.LogPath = "`"`$script:RepoPath\pr_data`""
        }
    }

    #Path for logs of remote repository types which PowerShell can't directly write to
    #Variable name stored as string literal so it can be expanded later with Invoke-Expression
$RemoteRepoLogBase =
@'
"$env:APPDATA" + "\PowerRestic"
'@
$RemoteRepoLogSub =
@'
+ "\" + ((($script:RepoPath).Replace(":","\")).Replace("/","\")).Trim("\")
'@
    if ("RemoteRepoLogPath" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "RemoteRepoLogPath" $("$RemoteRepoLogBase" + "$RemoteRepoLogSub") | out-null
    } else {
        #Test if value is valid as either and absolute or relative path
        $a = Validate-WinPath ($script:Options.RemoteRepoLogPath).trim("\")
        $r = Validate-WinPath ($script:Options.RemoteRepoLogPath).trim("\") -Relative
        if ($a[0] -eq $true) {
            $script:Options.RemoteRepoLogPath = '"' + $($a[1]).trim("\") + '"' + $RemoteRepoLogSub
        } elseif ($r[0] -eq $true) {
            $script:Options.RemoteRepoLogPath = '"' + $($r[1]).trim("\") + '"' + $RemoteRepoLogSub
        } else {
            $script:Options.RemoteRepoLogPath = $RemoteRepoLogBase + $RemoteRepoLogSub
        }
    }

    if ("QuickRestoreConfirm" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "QuickRestoreConfirm" 1  | out-null
    } else {
        if ($script:Options.QuickRestoreConfirm -ne 0) {$script:Options.QuickRestoreConfirm = 1}
    }

    if ("PruneMaxRepackSize" -in $script:Options.PSObject.Properties.Name) {
        if (-not(Validate-DataSize $script:Options.PruneMaxRepackSize -bytes $false)) {
            $script:Options.PSObject.Properties.Remove("PruneMaxRepackSize")
        }
    }

    if ("PruneMaxUnused" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "PruneMaxUnused" "5%"  | out-null
    } else {
        if ((Validate-Percentage -Number ($script:Options.PruneMaxUnused).Trim("%") -Hundred -AllowZero)) {
            $script:Options.PruneMaxUnused = $(($script:Options.PruneMaxUnused).Trim("%")) + "%"
        } else {
            $script:Options.PruneMaxUnused = "5%"
        }
    }

    if ("PruneRepackCacheableOnly" -in $script:Options.PSObject.Properties.Name) {
        if ($script:Options.PruneRepackCacheableOnly -ne 1) {
            $script:Options.PSObject.Properties.Remove("PruneRepackCacheableOnly")
        }
    }

    if ("PruneRepackSmall" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "PruneRepackSmall" 1  | out-null
    } else {
        if ($script:Options.PruneRepackSmall -ne 0) {$script:Options.PruneRepackSmall = 1}
    }

    if ("PruneRepackUncompressed" -notin $script:Options.PSObject.Properties.Name) {
        $script:Options | Add-Member -NotePropertyName "PruneRepackUncompressed" 1  | out-null
    } else {
        if ($script:Options.PruneRepackUncompressed -ne 0) {$script:Options.PruneRepackUncompressed = 1}
    }
}

function Make-Ini {
    #Writes new ini file if needed after Check-Settings sets defaults

    "[PowerRestic]" | Out-File .\PowerRestic.ini
    "" | Out-File .\PowerRestic.ini -Append
    foreach ($option in $script:options.PSObject.Properties) {
        "$($option.name)=$($option.value)" | Out-File .\PowerRestic.ini -Append
    }
}

function Find-ResticPath {
    #Confirms there is an item at $script:ResticPath
    #Replaces/adds path to ini file if wrong/missing

    #Work around to keep null/empty string from breaking test-path and
    #causing the whole if else block to be skipped
    if ($script:ResticPath -in "",$null) {$script:ResticPath = "???"}

    $resticFound = $false
    if (test-path $(Unquote-Path($script:ResticPath))) {
        $resticFound = $true
    } else {
        $i = 0
        :findRestic while ($i -lt $script:Options.Retries -or $resticFound -eq $false) {
            #Check $env:PATH/$PWD for restic.exe
            $ErrorActionPreference = 'Continue'
            $o = cmd /c where restic.exe *>&1
            $ErrorActionPreference = 'Stop'
            if ($o -ne "INFO: Could not find files for the given pattern(s).") {
                $script:ResticPath = "restic.exe"
                $resticFound = $true
                break findRestic
            }
            #Ask user for path
            if (Read-ResticPath) {
                $resticFound = $true
                break findRestic
            } else {
                write-host "Path not found!"
                pause
            }
            $i++
        }
        #Update ini if initial path was bad
        if ($resticFound -eq $true) {Update-ResticPath}
    }
}

function Read-ResticPath {
    #Prompts for restic path, tests path and returns true or false
    #If true, set

    cls
    Write-Host "Please enter the path to the restic executable:"
    $s = Read-Host
    if (Test-Path $(Unquote-Path($s))) {
        $script:ResticPath = $s
        $true
        return
    } else {
        $false
        return
    }
}

function Update-ResticPath {
    #.Add/replaces ResticPath= line in ini file

    $iniIn = get-content "PowerRestic.ini"
    [string[]]$iniMiddle = @()
    [string[]]$iniOut = @()

    #Strip blank line and/or old restic paths
    foreach ($line in $iniIn) {
        if ($line -like "ResticPath*=*" -or $line -eq "") {
        continue
        } else {
            $iniMiddle += $line
        }
    }

    #.Add header and new path
    if (($iniMiddle[0]).Trim() -eq "[PowerRestic]") {
        $iniOut += $iniMiddle[0]
        $iniOut += ""
        $iniOut += "ResticPath=$($script:ResticPath)"
        $iniOut += ""
        $iniOut += $iniMiddle[1..($iniMiddle.Count - 1)]
    } else {
        $iniOut += "[PowerRestic]"
        $iniOut += ""
        $iniOut += "ResticPath=$($script:ResticPath)"
        $iniOut += ""
        $iniOut+= $iniMiddle
    }

    Update-Ini -OverwriteLines $iniOut
}

function Find-RClonePath {
    #Confirms there is an item at $script:RClonePath
    #Replaces/adds path to ini file if wrong/missing

    #Work around to keep null/empty string from breaking test-path and
    #causing the whole if else block to be skipped
    if ($script:RClonePath -in "",$null) {$script:RClonePath = "???"}

    $RCloneFound = $false
    if (test-path $(Unquote-Path($script:RClonePath))) {
        $RCloneFound = $true
    } else {
        $i = 0
        :findRClone while ($i -lt $script:Options.Retries -or $RCloneFound -eq $false) {
            #Check $env:PATH for rclone.exe
            $ErrorActionPreference = 'Continue'
            $o = cmd /c where rclone.exe *>&1
            $ErrorActionPreference = 'Stop'
            if ($o.ToString() -ne "INFO: Could not find files for the given pattern(s)." -and $o -ne $("$PWD" + "\rclone.exe")) {
                $script:RCloneInPath = $true
                $RCloneFound = $true
                break findRClone
            }
            #Check working directory for RClone.exe
            if (Test-Path "RClone.exe") {
                $script:RClonePath = ".\RClone.exe"
                $RCloneFound = $true
                break findRClone
            }
            #Ask user for path
            if (Read-RClonePath) {
                $RCloneFound = $true
                break findRClone
            } else {
                write-host "Path not found!"
                pause
            }
            $i++
        }
        #Update ini if initial path was bad
        if ($RCloneFound -eq $true -and $script:RCloneInPath -eq $false) {Update-RClonePath}
    }
}

function Read-RClonePath {
    #Prompts for RClone path, tests path and returns true or false
    #If true, set

    cls
    Write-Host "Please enter the path to the RClone executable:"
    $s = Read-Host
    if (Test-Path $(Unquote-Path($s))) {
        $script:RClonePath = $s
        $true
        return
    } else {
        $false
        return
    }
}

function Update-RClonePath {
    # Add/replaces RClonePath= line in ini file

    $iniIn = get-content "PowerRestic.ini"
    [string[]]$iniMiddle = @()
    [string[]]$iniOut = @()

    #Strip blank line and/or old RClone paths
    foreach ($line in $iniIn) {
        if ($line -like "RClonePath*=*" -or $line -eq "") {
        continue
        } else {
            $iniMiddle += $line
        }
    }

    # Add header and new path
    if (($iniMiddle[0]).Trim() -eq "[PowerRestic]") {
        $iniOut += $iniMiddle[0]
        $iniOut += ""
        $iniOut += "RClonePath=$($script:RClonePath)"
        $iniOut += $iniMiddle[1..($iniMiddle.Count - 1)]
    } else {
        $iniOut += "[PowerRestic]"
        $iniOut += ""
        $iniOut += "RClonePath=$($script:RClonePath)"
        $iniOut+= $iniMiddle
    }

    Update-Ini -OverwriteLines $iniOut
}

function Find-RCloneConfPath{
    #Find and/or prompt for an RClone conf file path

    #Check if default conf files exists
    if (Test-Path $("$env:AppData" + "\rclone\rclone.conf")) {
        $DefaultRCloneConfExists = $true
    } else {
        $DefaultRCloneConfExists = $false
    }

    $i = 0
    while ($i -le $script:Options.Retries) {
        #Use default conf file without prompting if it exists and is explicitly set
        if ($script:Options.RCloneDefaultConf -eq 1 -and $DefaultRCloneConfExists) {
            $env:RCLONE_CONFIG = ""
        #Prompt for path if no config files are available
        } elseif ($script:Options.RCloneDefaultConf -ne 1 -and -not($DefaultRCloneConfExists) -and $script:RCLoneConfs.Count -eq 0) {
            Add-RCloneConfPath
        #List conf files in menu otherwise
        } else {
            #.Add default to list of manually specified conf files
            if ($DefaultRCloneConfExists -and $script:RCLoneConfs[0] -ne "Use default conf file") {
                $script:RCLoneConfs = ,"Use default conf file" + $script:RCLoneConfs
            }
            #Build and display menu
            [string[]]$RCLoneConfsMenu = @()
            $RCLoneConfsMenu += ,"Select RClone conf file"
            $RCLoneConfsMenu += ""
            $RCLoneConfsMenu += $script:RCLoneConfs
            $RCLoneConfsMenu += "Add conf file"
            Show-Menu -HeaderLines 2 -MenuLines $RCLoneConfsMenu
            if ($script:MenuChoice -eq 1) {
                $env:RCLONE_CONFIG = "" #$("$env:AppData" + "\rclone\rclone.conf")
            } elseif ($script:MenuChoice -gt 1 -and $script:MenuChoice -le $script:RCLoneConfs.Count) {
                $env:RCLONE_CONFIG = $script:RCLoneConfs[$MenuChoice - 1]
            } else {
                Add-RCloneConfPath
            }
        }
        #Test conf file
        if (Test-RCloneConfExists) {
            return
        }
    }
}

function Find-RCloneConfPW {
    #Finds if a password is needed for the RClone conf file and prompts for it necessary
    #Returns $true or $false

    #Try with no password
    if (Test-RCloneConfPW) {
        $true
        return
    #Prompt for password if needed
    } else {
        if ($env:RCLONE_CONFIG -in "",$null) {
            $name = "RClone default conf file"
        } else {
            $name = $env:RCLONE_CONFIG
        }
        $i = 0
        while ($i -lt $script:Options.Retries) {
            Save-Credential $name
            $env:RCLONE_PASSWORD_COMMAND = "PowerShell -NoProfile -ExecutionPolicy bypass -file PowerRestic.ps1 $(Quote-Path($(Get-CredentialName $name)))"
            if (Test-RCloneConfPW) {
                $true
                return
            }
            $i++
        }
        $false
        return
    }
}

function Test-RCloneConfPW {
    #Test if Rclone can read and decrypt the selected conf file and returns $true or $false

    $c = "$(Quote-Path($script:RClonePath))" + " config touch --ask-password=false"
    $ErrorActionPreference = 'Continue'
    cmd /c $c *>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        $false
        return
    } else {
        $true
        return
    }
}

function Test-RCloneConfExists {
    #Test that RClone conf file exists, returns true of false

    if ($env:RCLONE_CONFIG -in "",$null) {
        if (-not(Test-Path $("$env:AppData" + "\rclone\rclone.conf"))) {
            $false
            return
        }
    } else {
        if (-not(Test-Path "$env:RCLONE_CONFIG")) {
            $false
            return
        }
    }
    $true
}

function Add-RCloneConfPath {
    #Adds RCloneConfPath entry to ini file

    #Work around to keep null/empty string from breaking test-path and
    #causing the whole if else block to be skipped

    $RCloneConfPathFound = $false
    $i = 0
    :findRCloneConfPath while ($i -lt $script:Options.Retries -or $RCloneConfPathFound -eq $false) {
        #Ask user for path
        if (Read-RCloneConfPath) {
            $RCloneConfPathFound = $true
            break findRCloneConfPath
        } else {
            write-host "Path not found!"
            pause
        }
        $i++
    }
    #Update ini if successful
    if ($RCloneConfPathFound -eq $true) {
        Update-Ini -AppendLine ("RCloneConf=" + "$script:RCloneConfPath")
    }
}

function Read-RCloneConfPath {
    #Prompts for RClone conf file path, tests path and returns true or false
    #If true, set

    cls
    Write-Host "Please enter the path to the RClone conf file:"
    $s = Read-Host
    if (Test-Path $(Unquote-Path($s))) {
        $script:RCloneConfPath = $s
        $true
        return
    } else {
        $false
        return
    }
}

function Check-LogPath {
    #Redirects log path to a locally accessible location if repository path is not a locally
    #accessible filesystem

    if ($script:RepoPath -match '^[a-z,A-Z]:\\') {
        $script:CurrentLogPath= $script:Options.LogPath
    } else {
        $script:CurrentLogPath = $script:Options.RemoteRepoLogPath
    }
}

function Create-LogPath {
    #Creates missing subfolders in $script:CurrentLogPath

    if (Test-Path "$(Unquote-Path($(invoke-expression $script:CurrentLogPath)))\restore") {return}

    $folders = $("$(Unquote-Path(($(invoke-expression $script:CurrentLogPath))))\restore\").split("\")
    $builtPath = ""
    foreach ($folder in $folders) {
        if ($folder -eq "") {continue}
        if (test-path ($builtPath + $folder)) {
            $builtPath += $folder + "\"
        } else {
            New-Item -ItemType Directory ($builtPath + $folder) | out-null
            $builtPath += $folder + "\"
        }
    }
}

function Clear-ResticCache {
    #Clears old cache based on restic's default threshold of "old" if not instances are running
    #Ignore errors since it's not vital

    if ((Get-Process | Where{$_.Name -like "restic"}).count -eq 0) {
        Write-Host "Clearing old cache..."
        $c = "$(Quote-Path($ResticPath))" + " cache --cleanup"
        try {cmd /c $c | out-null} catch {}
    }
}

function Show-Menu{
    #Turns an array of strings into a numbered menu
    #Headers and footers which are not turned into numbered options can be specified
    #They can be indented to match the numbers prefixing the choices or not
    #Common separator characters are multiped to match when indented
    #If the number of $MenuLines minus $HeaderLines and $FooterLines exceeds $Options.DisplayLines all of Show-Menu's
    #inputs will be fed to Split-Menu, chopped up, and fed back to Show-Menu
    #Several parameters specify types of menu for navigation purposes
    #These are passed through to Read-MenuChoice where they actually do something

    param (
        [int]$HeaderLines = 0,
        [switch]$IndentHeader,
        [int]$FooterLines = 0,
        [switch]$IndentFooter,
        [switch]$ScrollMenu, #This should only be set automatically from within Split-Menu
        [switch]$RestoreFolderMenu,
        [switch]$LocalFolderMenu,
        [switch]$QueueMenu,
        [switch]$AllowEnter,
        [switch]$SlashForBack,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$MenuLines,
        [switch]$noCls
    )

    #Parameter set would get too messy so just "manually" check exclusive options aren't specified
    $f = 0
    if ($($RestoreFolderMenu).IsPresent) {$f++}
    if ($($LocalFolderMenu).IsPresent) {$f++}
    if ($($QueueMenu).IsPresent) {$f++}
    if ($f -gt 1) {throw "Only one group input options may be specified per menu."}

    #Reset choice
    try {remove-variable -name MenuChoice -Scope script -ErrorAction Stop} catch {}

    if (-not($noCls)) {cls}

    #Subtract header and footer lines to get number of menu options
    $NumberOfOptions = $MenuLines.Count - ($HeaderLines + $FooterLines)
    #if number of menu options is past the limit feed into Split-Menu
    if ($NumberOfOptions -gt $script:Options.DisplayLines) {
        #Keep page of multiline menu if true, otherwise reset to 1.  Reset immediately after use
        if ($script:KeepPage -eq $true) {
            $script:KeepPage = $false
        } else {
            $script:MenuPage = 1
        }
        $splitMenuParams = @{
            HeaderLines = $HeaderLines
            IndentHeader = $($IndentHeader).IsPresent
            FooterLines = $FooterLines
            IndentFooter = $($IndentFooter).IsPresent
            RestoreFolderMenu = $($RestoreFolderMenu).IsPresent
            LocalFolderMenu = $($LocalFolderMenu).IsPresent
            QueueMenu = $($QueueMenu).IsPresent
            AllowEnter = $($AllowEnter).IsPresent
            SlashForBack = $($SlashForBack).IsPresent
            MenuLines = $MenuLines
        }
        Split-Menu @splitMenuParams
        return
    }
    #Count number of digits in total number of options to
    #pad the front of smaller numbers with whitespace
    $offset = (($NumberOfOptions.ToString()).ToCharArray()).Count

    #Build a multiline string to output
    $CurrentLine = 1
    $output = ""
    #Add header
    if ($HeaderLines -gt 0) {
        foreach ($Line in $MenuLines[0..($HeaderLines - 1)]) {
            #If line looks like a separator  by matching -, !, @, #, $, %, ^, &, *, _, =, or +
            #Prepend more of it to match the offset, including space for the " - " separator
            if ($line -match '^-{20,}|^!{20,}|^@{20,}|^#{20,}|^\${20,}|^%{20,}|^\^{20,}|^&{20,}|^\*{20,}|^_{20,}|^={20,}|^\+{20,}') {
                $output += "$($Line[0])"*($offset + 3) + $line + "`n"
            } else {
                if ($IndentHeader) {
                    $output += " "*($offset + 3) + $line + "`n"
                } else {
                    $output += $line + "`n"
                }
            }
        }
    }
    #Add options
    #Allow for yes/no type menus
    if ($MenuLines.count -gt $HeaderLines + $FooterLines) {
        foreach ($Line in $MenuLines[($HeaderLines)..($MenuLines.count - ($FooterLines + 1 ))]) {
            #Spaces the highest number will use, minus spaces the current number uses + current number + " - " + the menu line + line break
            $output += " "*($offset - (($CurrentLine.ToString()).ToCharArray()).Count) + $CurrentLine.ToString() + " - " + $line + "`n"
            $CurrentLine++
        }
    }
    #Add footer
    if ($FooterLines -gt 0) {
        foreach ($Line in $MenuLines[($MenuLines.count - $FooterLines)..($MenuLines.count - 1)]) {
            #If line looks like a separator  by matching -, !, @, #, $, %, ^, &, *, _, =, or +
            #Prepend more of it to match the offset
            if ($line -match '^-{20,}|^!{20,}|^@{20,}|^#{20,}|^\${20,}|^%{20,}|^\^{20,}|^&{20,}|^\*{20,}|^_{20,}|^={20,}|^\+{20,}') {
                $output += "$($Line[0])"*($offset + 3) + $line + "`n"
            } else {
                if ($IndentFooter) {
                    $output += " "*($offset + 3) + $line + "`n"
                } else {
                    $output += $line + "`n"
                }
            }
        }
    }
    #write out menu
    write-host $output

    #User input is taken and validated in a separate function
    $menuChoiceParams = @{
        NumberOfOptions = $NumberOfOptions
        ScrollMenu = $($ScrollMenu).IsPresent
        RestoreFolderMenu = $($RestoreFolderMenu).IsPresent
        LocalFolderMenu = $($LocalFolderMenu).IsPresent
        QueueMenu = $($QueueMenu).IsPresent
        AllowEnter = $($AllowEnter).IsPresent
        SlashForBack = $($SlashForBack).IsPresent
    }
    Read-MenuChoice @menuChoiceParams
}

function Split-Menu {
    #This mostly takes the same parameters as show-menu
    #it paginates the choices, preserving the header and footer on each page, feeding each page back to Show-Menu

    param (
        [int]$HeaderLines,
        [switch]$IndentHeader,
        [int]$FooterLines,
        [switch]$IndentFooter,
        [switch]$RestoreFolderMenu,
        [switch]$LocalFolderMenu,
        [switch]$QueueMenu,
        [switch]$AllowEnter,
        [switch]$SlashForBack,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$MenuLines
    )

    #Subtract header and footer lines to get number of menu options
    $NumberOfOptions = $MenuLines.Count - ($HeaderLines + $FooterLines)
    #Split header, footer, and options into different arrays
    $MenuHeader = [string[]]$MenuLines[0..($HeaderLines - 1)]
    $MenuFooter = [string[]]$MenuLines[($MenuLines.Count - $FooterLines)..($MenuLines.Count)]
    $MenuOptions = [string[]]$MenuLines[($HeaderLines)..($MenuLines.Count - $FooterLines - 1)]

    #Get number of pages needed
    $NumberOfPages = [math]::Ceiling($NumberOfOptions/$options.DisplayLines)

    #increment $FooterLines to insert page numbers at bottom
    $FooterLines = $FooterLines + 1

    #Loop of menu pages
    while ($true) {
        $PageLines = ($MenuHeader + $MenuOptions[(($script:MenuPage - 1) * $Options.DisplayLines)..((($script:MenuPage - 1) * $Options.DisplayLines) + ($Options.DisplayLines - 1))] + $MenuFooter + "Page $script:MenuPage/$NumberOfPages")
        $showMenuParams = @{
            HeaderLines = $HeaderLines
            IndentHeader = $($IndentHeader).IsPresent
            FooterLines = $FooterLines
            IndentFooter = $($IndentFooter).IsPresent
            ScrollMenu = $true #This should always be true if we're already in this function
            RestoreFolderMenu = $($RestoreFolderMenu).IsPresent
            LocalFolderMenu = $($LocalFolderMenu).IsPresent
            QueueMenu = $($QueueMenu).IsPresent
            AllowEnter = $($AllowEnter).IsPresent
            SlashForBack = $($SlashForBack).IsPresent
            MenuLines = ([string[]]$PageLines)
        }
        Show-Menu @showMenuParams
        #Intercept inputs used for scrolling or selecting options for adjustment
        ###Adjust page number
        if ($script:MenuChoice -eq "") {$script:MenuPage++}
        if ($script:MenuChoice -in "+") {$script:MenuPage = $script:MenuPage -1}
        ###Wrap around
        if ($script:MenuPage -gt $NumberOfPages) {$script:MenuPage = 1}
        if ($script:MenuPage -lt 1) {$script:MenuPage = $NumberOfPages}
        ####Add multiplier for number of pages in to $MenuChoice to match the full array of items
        ####the calling code is going to index from
        if ($script:MenuChoice -is [int]) {
            $script:MenuChoice = [int]($script:MenuChoice + (($script:MenuPage - 1) * $Options.DisplayLines))
            break
        }
        #Break and return to original menu for other options
        if ($script:MenuChoice -in "-",".","/","*") {break}
    }
    return
}

function Read-MenuChoice {
    #Validates that input is within the number of listed choices
    #Parameters for type of menu change add/remove other acceptable options
    #Displays additional input options

    param (
        [Parameter(Mandatory = $true)]
        [int]$NumberOfOptions,
        [switch]$ScrollMenu,
        [switch]$RestoreFolderMenu,
        [switch]$LocalFolderMenu,
        [switch]$QueueMenu,
        [switch]$AllowEnter,
        [switch]$SlashForBack
    )

    #Reset choice if left over
    try {remove-variable -name MenuChoice -Scope script -ErrorAction Stop} catch {}

    #Start with all the numbers
    $AcceptableChoices = 0..$NumberOfOptions

    #Add options for different combinations

    #Single page flat menu with back/exit
    if ($($ScrollMenu).IsPresent -eq $false -and $($RestoreFolderMenu).IsPresent -eq $false  -and $($LocalFolderMenu).IsPresent -eq $false  -and $($QueueMenu).IsPresent -eq $false -and $($SlashForBack).IsPresent -eq $true) {
        write-host "`"/`" to go back"
        $AcceptableChoices += "/"
    }
    #Multiple pages and flat menu, alway have slash for back with this
    if ($($ScrollMenu).IsPresent -eq $true  -and $($RestoreFolderMenu).IsPresent -eq $false  -and $($LocalFolderMenu).IsPresent -eq $false  -and $($QueueMenu).IsPresent -eq $false ) {
        write-host "Enter for next screen, `"+`" for last screen, `"/`" to exit this menu"
        $AcceptableChoices += "+","/"
    }
    #Browse/restore menus - non-scrolling and scrolling
    if ($($ScrollMenu).IsPresent -eq $false -and $($RestoreFolderMenu).IsPresent) {
        write-host "`"-`" to go up a directory, `".`" for information about current directory,`"*`" to view or restore queued items, `"/`" to exit this menu"
        $AcceptableChoices += "-",".","/","*"
    }
    if ($($ScrollMenu).IsPresent -eq $true -and $($RestoreFolderMenu).IsPresent -eq $true) {
        write-host "Enter for next screen, `"+`" for last screen, `"-`" to go up a directory, `".`" for information about current directory, `"*`" to view restore or queued items, `"/`" to exit this menu"
        $AcceptableChoices += "+","-",".","/","*"
    }
    #Restore queue menu - non-scrolling and scrolling
    if ($($ScrollMenu).IsPresent -eq $false -and $($QueueMenu).IsPresent -eq $true) {
        write-host "Select an item to remove it from the queue"
        write-host "Enter `"-`" to clear the queue or `"/`" to go back"
        $AcceptableChoices += "-","/"
    }
    if ($($ScrollMenu).IsPresent -eq $true -and $($QueueMenu).IsPresent -eq $true) {
        write-host "Select an item to remove it from the queue"
        write-host "Enter for next screen, `"+`" for last screen, `"-`" to clear the queue, or `"/`" to go back"
        $AcceptableChoices += "+","-","/"
    }
    #Local drive menu - non-scrolling and scrolling
    if ($($ScrollMenu).IsPresent -eq $false -and $($LocalFolderMenu).IsPresent -eq $true) {
        write-host "`"-`" to go up a directory, `".`" to make a new directory, `"*`" to select this directory, `"/`" to exit this menu"
        $AcceptableChoices += "-",".","*","/"
    }
    if ($($ScrollMenu).IsPresent -eq $true -and $($LocalFolderMenu).IsPresent -eq $true) {
        write-host "Enter for next screen, `"+`" for last screen, `"-`" to go up a directory, `".`"  to make a new directory, `"*`" to select this directory, or `"/`" to exit this menu"
        $AcceptableChoices += "+","-",".","*","/"
    }

    #Get input and check it
    $Script:MenuChoice = read-host
    #Make sure that numbers count as ints to prevent problems in other places
    try {$Script:MenuChoice = [int]::Parse($Script:MenuChoice)} catch {}
    #Triple conditions because -in/-notin counts "" as in any array
    while ($Script:MenuChoice -notin $AcceptableChoices -or (($($AllowEnter).IsPresent -eq $false -and $($ScrollMenu).IsPresent -eq $false) -and $Script:MenuChoice -eq "")) {
        write-host ""
        write-host "Please enter a valid choice."
        write-host ""
        try {remove-variable -name MenuChoice -Scope script -ErrorAction Stop} catch {}
        $Script:MenuChoice = read-host
    }
    return
}

function Format-Bytes  {
    #Make bytes easily readable without having to draw commas on your screen
    param (
        [Parameter(Mandatory = $true)]
        [int64]$bytes
    )
    switch ($bytes) {
	{$bytes -gt 1TB} {($bytes / 1TB).ToString("n2") + " TB";break}
	{$bytes -gt 1GB} {($bytes / 1GB).ToString("n2") + " GB";break}
	{$bytes -gt 1MB} {($bytes / 1MB).ToString("n2") + " MB";break}
	{$bytes -gt 1KB} {($bytes / 1KB).ToString("n2") + " KB";break}
	default {"$bytes B"}
	}
}

function Append-RepoTypeOptions {
    #Appends options specific to a repository type to Restic commands

    param(
        [string]$cmd,
        [string]$path
    )

    if ($path -in $null,"") {
        $path = $script:RepoPath
    }
    if ($path -like "RClone:*") {
        if ($script:RCloneInPath -eq $false) {
            $cmd += " -o rclone.program=`"`'$script:RClonePath`'`""
        }
    }
    $cmd
    return
}

function Get-CredentialName {
    #Creates a legal filename for saving a cached credential from a repository name and type

    param ([string]$name)
    $name = $(Replace-IllegalWinChars $name)
    $name += "-credential.xml"
    $name
}

function Save-Credential {
    #Reads password and saves it to encrypted XML file

    param (
        [Parameter(Mandatory = $true)]
        [string]$name
    )
    cls
    Write-Host "Enter Password for $($name):"
    $Password = read-host -AsSecureString
    $Credential = New-Object -TypeName PSCredential -ArgumentList $ENV:COMPUTERNAME, $Password
    $file = $(Get-CredentialName $name)
    if (Test-Path "$file") {Remove-Item -Force "$file"}
    $Credential | Export-Clixml -Path $file
}

function Open-Repo {
    #"Opens" a repo by checking its path and password and storing them for use in other commands

    param (
        [Parameter(Mandatory = $true)]
        [string]$path
    )
    cls
    #Check type of repository
    if ($path -like "RClone:*") {
        Find-RClonePath
        Find-RCloneConfPath
        if (-not(Find-RCloneConfPW)) {
            Write-Host "Could not open RClone conf file.  Please try again"
            pause
            return
        }
        cls
    } else {
        #Confirm that a folder exists if not RClone
        $p = Validate-WinPath $path
        if ($p[0] -eq $true) {
            $path = $p[1]
        } else {
            Write-Host "$path is not a valid path.  Please try again"
            pause
            return
        }
        if ($path -eq "" -or -not(Test-Path $(Unquote-Path($path)))) {
            Write-Host "$path not found.  Please try again"
            pause
            return
        } else {
            Write-Host "$path exists."
            write-host ""
        }
    }
    #Automatically try to open with no password
    $i = -1 #Offset for automatic first try with no password
    $triedLocked = $false #Only attempt remove exclusive locks on the repo once
    $script:RepoPasswordCommand = " --insecure-no-password"
    $env:RESTIC_PASSWORD_COMMAND = ""
    :TryRepoPasswords while ($i -lt $script:Options.Retries -and $script:RepoOpened -eq $false) {
        #Skip asking for password on first count
        if ($i -gt -1) {
            $script:RepoPasswordCommand = ""
            cls
            Save-Credential $path
            $env:RESTIC_PASSWORD_COMMAND = "PowerShell -NoProfile -ExecutionPolicy bypass -file PowerRestic.ps1 $(Quote-Path($(Get-CredentialName $path)))"
        }

        $c = "$(Quote-Path($script:ResticPath))" + " -r $(Quote-Path($Path))" + "$script:RepoPasswordCommand" + " cat config"
        $c = Append-RepoTypeOptions "$c" "$path"
        cls
        Write-Host "Opening repository..."
        #shenanigans to hide restic's output from console while still storing it in a variable
        $ErrorActionPreference = 'Continue'
        $o = cmd /c $c *>&1
        $ErrorActionPreference = 'Stop'
        #Check other error
        foreach ($line in $o) {
            #Check if repository is locked by other restic instance
            if ($line -like "*unable to create lock*") {
                #Abort if this has already happened once
                if ($triedLocked -eq $true) {
                    cls
                    Write-Host "Repository could not be unlocked!  Repository cannot be opened!"
                    pause
                    break TryRepoPasswords
                #Try to unlock and decrement retry counter it this is the first time
                #passes lock message which can include username and PID
                } else {
                    Unlock-Repo -LockMessage $p.ToString() -LockedRepo $path
                    $i = $i - 1
                    $triedLocked = $true
                }
                break
            }
            #Display RClone errors
            if ($line -like "*rclone*" -and ($line -like "*critical*" -or $line -like "*fatal*")) {
                Write-Host $line
                pause
                break TryRepoPasswords
            }
        }

        #If it was not locked and the PW was correct there will be parsable json, if not it failed
        try {$o = $o | ConvertFrom-Json} catch {$o=$null}

        if ($o.version -is [int] -and $o.id -match'[0-9a-f]+' -and $o.chunker_polynomial -match '[0-9a-f]+') {
            $script:RepoOpened = $true
            $script:RepoPath = $path
            $o | Add-Member -NotePropertyName "repo_path" $script:RepoPath
            $script:RepoInfo = $o
            Check-LogPath
            return
        } else {
            #Hide failure notice for first try and get rid of the no password flag
            if ($i -gt -1) {
                write-host "Failed to open repository"
                write-host ""
            }
        }
        $i++
    }

    #Reset these if this function has failed out after passing the retry limit
    $env:RESTIC_PASSWORD_COMMAND = ""
    $script:RepoPasswordCommand = ""
}

function Unlock-Repo {
    #Displays lock message passed to it and asks if user wants to remove the lock
    #If it find a PID in the lock message it will try and check if the process is still active on this machine
    param (
        [Parameter(Mandatory = $true)]
        [string]$LockMessage,
        [Parameter(Mandatory = $true)]
        [string]$LockedRepo
    )

    #Build menu
    [string[]]$m = @()
    if ($LockMessage -match 'locked.*') {
        $m +="The repository at $LockedRepo is $($matches[0]))"
    } else {
        $m += "Raw error message from repository at $LockedRepo is: $LockMessage"
    }

    #Try and find a PID and see if it's still active
    if ($LockMessage -match '(?<=PID\ )\d*') {
        try {
            [int]::Parse($Matches[0]) | out-null
            if ($Matches[0] -in (Get-Process).id) {
                if ((get-process -ID $Matches[0]).ProcessName -like "restic*") {
                $m += "THIS PROCESS IS STILL RUNNING AND MAY BE ACTIVE"
                }
            } else {
                $m += "This process no longer appears to be active"
            }
        } catch {
            $m += "No information about the locking process was determined"
        }
    }

    $m += "Would you like to forcibly remove the lock?"
    $m += ""
    $m += "Yes"
    $m += "No"
    $m += ""
    $m += "WARNING: Removing the lock while another instance of restic is still active may result in DATA LOSS"

    #Double check with user
    Show-Menu -HeaderLines 4 -FooterLines 2 -MenuLines $m
    if ($MenuChoice -eq 1) {
        Show-Menu -HeaderLines 2 -MenuLines @(
            "Are you sure you wish to FORCIBLY remove this lock?"
            ""
            "Yes"
            "No"
        )
        if ($MenuChoice -eq 1) {
            $c = "$(Quote-Path($script:ResticPath))" + " -r $(Quote-Path($Path))" + "$script:RepoPasswordCommand" + " unlock"
            $c = Append-RepoTypeOptions "$c" "$path"
            cmd /c $c
            Pause
            return
        }
    }
}

function Quote-Path {
    #Adds quotes around a file path if it has spaces, for use in building command line arguments
    #-Force switch to always add quotes, even if there are no spaces

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Force
    )
    #Just return input if it's already quoted
    if ($path[0] -eq "`"" -and $path[-1] -eq "`"") {
        $Path
        return
    }
    #.Add quotes if there is a space in it
    if (" " -in $Path.ToCharArray() -or $Force.IsPresent) {
        $Path = "`"" + $Path + "`""
    }
    $Path
    return
}

function Unquote-Path {
        #Unquotes quoted paths because Test-Path is super picky and just fails if a path passed
        #via a variable is quoted

        param (
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        if ($path[0] -eq "`"" -and $path[-1] -eq "`"") {
            $path = $path.Substring(1,($path.length - 2))
        }
        if ($path[0] -eq "`'" -and $path[-1] -eq "`'") {
            $path = $path.Substring(1,($path.length - 2))
        }
        $Path
        return
}

function Gen-RepoStats {
    #Runs 3 commands that return different info about the repository and combine them into one object

    cls
    write-host "Getting repository stats..."
    #Build commands for each type of stat report
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    $RestoreSizeCommand = $c + " stats --json --mode restore-size"
    $FileContentsCommand = $c + " stats --json --mode files-by-contents"
    $RawDataCommand = $c + " stats --json --mode raw-data"
    #In case I want this one later
    #$BlobsFileCommand = $c + " stats --json --mode blobs-per-file"

    #Run commands and convert json data into objects
    $RawRestoreSize = cmd /c $RestoreSizeCommand | ConvertFrom-Json
    $RawFilesByContents = cmd /c $FileContentsCommand | ConvertFrom-Json
    $RawRawData = cmd /c $RawDataCommand | ConvertFrom-Json
    #In case I want this one later
    #$RawBlobsPerFile = cmd /c $BlobsFileCommand | ConvertFrom-Json

    #Pull out useful info
    $RepoStats = New-Object PSObject
    $RepoStats | Add-Member -NotePropertyName "Snapshots_Count" $RawRestoreSize.snapshots_count
    $RepoStats | Add-Member -NotePropertyName "Restorable_Files" $RawRestoreSize.total_file_count
    $RepoStats | Add-Member -NotePropertyName "Restorable_Size" (Format-Bytes ($RawRestoreSize.total_size))
    $RepoStats | Add-Member -NotePropertyName "Unique_Files" $RawFilesByContents.total_file_count
    $RepoStats | Add-Member -NotePropertyName "Unique_Files_Size" (Format-Bytes ($RawFilesByContents.total_size))
    $RepoStats | Add-Member -NotePropertyName "Size_on_Disk" (Format-Bytes ($RawRawData.total_size))
    $RepoStats | Add-Member -NotePropertyName "Uncompressed_Size" (Format-Bytes ($RawRawData.total_uncompressed_size))
    $RepoStats | Add-Member -NotePropertyName "Compression_Ratio" ([math]::Round($RawRawData.compression_ratio,2).ToString() + "X")
    $RepoStats | Add-Member -NotePropertyName "Compression_Space_Saving" ([math]::Round($RawRawData.Compression_Space_Saving,2).ToString() + "%")
    $script:RepoStats = $RepoStats
}

function Gen-Snapshots {
    #Makes matching arrays with the description of each snapshot and just its short ID
    #The descriptions are for making into menu choices
    #The IDs are for specifying them in command line arguments

    cls
    write-host "Getting snapshots..."

    $script:SnapIDs = @()
    [string[]] $Output = @()
    [string[]] $script:Snapshots = @()

    #Build command
    $c = "$(Quote-Path($script:ResticPath))" + " -r $(Quote-Path($script:RepoPath))" + "$script:RepoPasswordCommand" + " snapshots"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    $Output = cmd /c $c

    #Count snapshots in basic output and enumerate their short IDs
    foreach ($line in $Output) {
        if ($line -match '^[0-9a-f]{8}') {
            $script:SnapIDs += $Matches[0]
        }
    }

    #Return empty array if no SnapIDs are found
    if ($script:SnapIDs.count -gt 0) {$script:Snapshots = $Output}
}

function Get-SnapshotStats {
    #Populates $SnapshotStatsRaw with restic's data about a single snapshot

    cls
    write-host "Getting snapshot stats..."
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " cat snapshot" + " $SnapID"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    $Script:SnapshotStatsRaw = cmd /c $c | ConvertFrom-Json
}

function Format-SnapshotStats {
    #Formats $script:SnapshotStatsRaw into an array of strings holding a nice readable table of info

    [string[]]$script:SnapshotStatsFormatted = @()
    $SnapshotTable = new-object PSobject

    #Build object with all the properties we want to display
    $SnapshotTable | Add-Member -NotePropertyName "Hostname"  $($script:SnapshotStatsRaw.hostname)
    $SnapshotTable | Add-Member -NotePropertyName "Paths"  $($script:SnapshotStatsRaw.paths)
    $SnapshotTable | Add-Member -NotePropertyName "Tags"  $($script:SnapshotStatsRaw.tags)
    $SnapshotTable | Add-Member -NotePropertyName "Restic Version"  $($script:SnapshotStatsRaw.program_version)
    $SnapshotTable | Add-Member -NotePropertyName "Backup Started" (Parse-ResticDate "$($script:SnapshotStatsRaw.summary.backup_start)")
    $SnapshotTable | Add-Member -NotePropertyName "Backup Ended" (Parse-ResticDate "$($script:SnapshotStatsRaw.summary.backup_end)")
    $SnapshotTable | Add-Member -NotePropertyName "New Files" "$($script:SnapshotStatsRaw.summary.files_new)"
    $SnapshotTable | Add-Member -NotePropertyName "Changed Files" "$($script:SnapshotStatsRaw.summary.files_changed)"
    $SnapshotTable | Add-Member -NotePropertyName "Unchanged Files" "$($script:SnapshotStatsRaw.summary.files_unmodified)"
    $SnapshotTable | Add-Member -NotePropertyName "Files Processed" "$($script:SnapshotStatsRaw.summary.total_files_processed)"
    $SnapshotTable | Add-Member -NotePropertyName "New Directories" "$($script:SnapshotStatsRaw.summary.dirs_new)"
    $SnapshotTable | Add-Member -NotePropertyName "Changed Directories" "$($script:SnapshotStatsRaw.summary.dirs_changed)"
    $SnapshotTable | Add-Member -NotePropertyName "Unhanged Directories" "$($script:SnapshotStatsRaw.summary.dirs_unmodified)"
    $SnapshotTable | Add-Member -NotePropertyName "Data Processed" (Format-Bytes "$($script:SnapshotStatsRaw.summary.total_bytes_processed)")
    $SnapshotTable | Add-Member -NotePropertyName "Data Added to Repository" (Format-Bytes "$($script:SnapshotStatsRaw.summary.data_added_packed)")

    #Convoluted way to get the list formatting
    #Split multiline string and filter out the empty lines it includes
    $script:SnapshotStatsFormatted = ($SnapshotTable|fl|Out-String).Split("`r`n") | where {$_ -ne ""}
}

function Forget-Snapshot {
    #Gets user conformation and forgets the currently selected snapshot

    #Build menu array
    [string[]]$m = @()
    $m += "Are you sure you want to FORGET this snapshot in the repository at $($script:RepoPath)?"
    $m += ""
    $m += $SnapshotStatsFormatted
    $m += ""
    $m += "This operation CANNOT BE UNDONE"
    $m += ""
    $m += "Yes"
    $m += "No"
    $m += ""
    $m += "This operation CANNOT BE UNDONE"
    Show-Menu -HeaderLines 20 -FooterLines 2 -MenuLines $m

    if ($script:MenuChoice -eq 1) {
        $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " forget" + " $SnapID -vv"
        $c = Append-RepoTypeOptions "$c" "$RepoPath"
        cmd /c $c
        pause
        #Regen snapshots so the old one disappears from the UI
        Gen-Snapshots
    }
}

function Find-ChangedSnapshot {
    #Find new snapshot ID after changing tags because that also changes its ID
    #Matches by looking for the same time as the original
    #Updates $script:SnapID

    cls
    write-host "Finding updated snapshot..."
    $c = "$(Quote-Path($script:ResticPath))" + " -r $(Quote-Path($script:RepoPath))" + "$script:RepoPasswordCommand" + " snapshots --json"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    $newSnapshots = cmd /c $c | ConvertFrom-Json

    foreach ($snapshot in $newSnapshots) {
        if ($snapshot.time -eq $script:SnapshotStatsRaw.time) {
            $script:SnapID = $snapshot.short_id
            return
        }
    }
}

function Add-SnapshotTag {
    #Read user input and adds it as tag to the currently selected snapshot
    #Performs some basic validation to get rid of things that are probably bad ideas

$pattern = @"
[\\/'`""`\{\}\[\],;:^\*%|]
"@

    $validated = $false
    while ($validated -eq $false) {
        cls
        Write-Host "Enter the tag you would like to add:"
        $tag = Read-Host
        $tag = $tag.Trim()
        if ($tag -match $pattern) {
            Write-Host ""
            Write-Host "Please enter a tag without any of the following characters:"
            Write-Host "\  /  ``  `'  `"  {  }  [  ]  ,  ;  :  ^  *  %  |"
            Pause
            continue
        } else {
            $validated = $true
        }
        Show-Menu -HeaderLines 2 -MenuLines @(
            "Add tag `"$tag`" to this snapshot?"
            ""
            "Yes"
            "No"
        )
        if ($script:MenuChoice -eq 2) {return}
    }

    cls
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " tag" + " --add $(Quote-Path($tag))" + " $($script:SnapID)"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    cmd /c $c
}

function Remove-SnapshotTag {
    #Displays a menu with all tags and removes the selected tag after conformation

    cls

    if ($script:SnapshotStatsRaw.tags.Count -eq 0 ) {
        Write-Host "Selected snapshots has no tags to remove!"
        Pause
        return
    }

    #Build menu
    [string[]]$m = @()
    $m += "Select a tag to remove"
    $m += ""
    $script:SnapshotStatsRaw.tags | ForEach-Object {$m += $_}

    Show-Menu -HeaderLines 2 -MenuLines $m

    $i = $script:MenuChoice - 1

    Show-Menu -HeaderLines 2 -MenuLines @(
        "Do you want to remove the tag `"$($script:SnapshotStatsRaw.tags[$i])`" from this snapshot?"
        ""
        "Yes"
        "No"
    )

    if ($script:MenuChoice -eq 1) {
        cls
        $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " tag" + " --remove $(Quote-Path($script:SnapshotStatsRaw.tags[$i]))" + " $($script:SnapID)"
        $c = Append-RepoTypeOptions "$c" "$RepoPath"
        cmd /c $c
    }
}

function Clear-SnapshotTags {
    #I couldn't find a way to clear all tags in a single command so this seemed like the most efficient workaround
    #Use --set to make a single temporary tag with a hard coded name and then remove

    Show-Menu -HeaderLines 2 -MenuLines @(
        "Are you sure you want to remove ALL tags from this snapshot?"
        ""
        "Yes"
        "No"
    )
    if ($script:MenuChoice -eq 2) {return}

    cls
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " tag" + " --set PowerResticTemp" + " $($script:SnapID)"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    cmd /c $c
    cls
    Find-ChangedSnapshot
    cls
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " tag" + " --remove PowerResticTemp" + " $($script:SnapID)"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    cmd /c $c
}

function Get-PruneCommand {
    #Creates command line options string based on set options
    #Hard coded defaults can be changed in ini file

    $s = ""
    if ($script:Options.PruneMaxRepackSize -ne $null) {$s += " --max-repack-size $($script:Options.PruneMaxRepackSize)"}
    if ($script:Options.PruneMaxUnused -ne $null) {$s += " --max-unused $($script:Options.PruneMaxUnused)"}
    if ($script:Options.PruneRepackCacheableOnly -eq 1) {$s += " --repack-cacheable-only"}
    if ($script:Options.PruneRepackSmall -eq 1) {$s += " --repack-small"}
    if ($script:Options.PruneRepackUncompressed -eq 1) {$s += " --repack-uncompressed"}

    $s
    return
}

Function Prune-Repo {
    #Runs a prune command with or without a dry run option
    #Hard coded defaults can be changed in ini file

    param([switch]$DryRun)

    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " prune" + " $SnapID -vv" + "$(Get-PruneCommand)"
    if ($($DryRun).IsPresent) {$c += " --dry-run"}
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    cmd /c $c
    pause
}

function Gen-FolderData {
    #Populates $script:FolderData with subfolders and files in $script:FolderPath from a snapshot

    cls
    write-host "Getting folder contents..."
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " ls" + " $SnapID" + " $(Quote-Path($script:FolderPath))" + " --json"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    $script:FolderData = cmd /c $c | ConvertFrom-Json
}

function Jump-ToSnapshotPath {
    #Lets user manually enter a path to start browsing from by setting $script:FolderPath
    #Returns true after entering a path found in the snapshot and false after running out of tries

    $i = 0
    while ($i -lt $script:Options.Retries) {
        cls
        Write-Host "Please enter a path in this snapshot to jump to"
        Write-Host "WARNING: The path is case sensitive"
        $p = Read-Host
        $q = (Validate-WinPath $p)
        if ($q[0] -eq $false) {
            Write-Host "Please enter a valid path"
            pause
            $i++
            continue
        } else {
            $script:FolderPath = Convert-WinPathToNix($q[1])
            #Restic always returns an object for the snapshot itself and even for
            #an empty folder it returns an object for the empty parent folder.
            #The count will always be at least one, even if the path is gibberish
            #2 is an empty folder and 3 or more means there's something in the folder
            Gen-FolderData
            if ($script:FolderData.Count -gt 1) {
                $true
                return
            } else {
                Write-Host "Folder $(Quote-Path($q[1])) does not exist in this snapshot!"
                Pause
                $i++
                continue
            }
        }
        $i++
    }
    $false
    return
}

function Check-RootFolderPath {
    #Workaround to skip past the *nix-type "/" path root and right to a drive's contents when backup root is a single DOS style drive letter

    $script:FolderPath = '/'
    Gen-FolderData
    #If the ls of "/" returns only "/" and "/X" (any capital letter) just skip to "/X"
    if ($script:FolderData.count -eq 2 -and ($script:FolderData[1]).path -match '^/[A-Z]$') {
        $script:FolderPath = ($script:FolderData[1]).path
        Gen-FolderData
    }
}

function Sort-FolderData {
    #Fixes case sensitive sort
    #Makes separate lists of files and folders so Format-FolderDirsFiles can format them easier for the menu
    #Makes one big list for pulling data out when chosen from menu

    [array]$script:FolderDirs = @()
    [array]$script:FolderFiles = @()
    [array]$script:FolderDirsAndFiles = @()
    foreach ($item in $script:FolderData) {
        #The parent folder is always included before its child items so skip it
        if ($item.type -eq "dir" -and $item.path.Trim("/") -eq $script:FolderPath.Trim("/")) {continue}
        switch ($item.type) {
            "dir" {$script:FolderDirs += $item}
            "file" {$script:FolderFiles += $item}
        }
    }
    $script:FolderDirs = $script:FolderDirs | Sort-Object -Property name
    $script:FolderFiles = $script:FolderFiles | Sort-Object -Property name
    $script:FolderDirsAndFiles = $script:FolderDirs  + $script:FolderFiles
}

function Gen-WinHostDrives {
    #Starts off browsing for a restore to path by listing hard drives

    $script:WinHostDrives = (Get-WmiObject Win32_LogicalDisk | where {$_.DriveType -eq 3} | Select-Object -ExpandProperty DeviceID) | ForEach-Object {$_ + "\"}
}

function Browse-RestoreToPath {
    #Browse local drives to pick a path to restore to
    #Returns user selected path or a $null on exit

    #First display fixed root drives
    Gen-WinHostDrives
    while ($true) {
        [string[]]$m = @()
        $m += "Restore to..."
        $m += "Now Browsing:"
        $m += "Root drives"
        $m += ""
        $m += $script:WinHostDrives

        Show-Menu -HeaderLines 4 -SlashForBack -MenuLines $m
        if ($script:MenuChoice -is [int]) {
            $script:WinHostFolderPath = $script:WinHostDrives[$script:MenuChoice - 1]
        } elseif ($script:MenuChoice -eq "/") {
            $null
            return
        }

        #Display subfolders and break when Pop-WinDirectory goes above the drive root and returns aan empty string
        :WinHostDriveSubfolders while ($script:WinHostFolderPath -ne "") {
            Gen-WinHostFolders

            [string[]]$m = @()
            $m += "Restore to..."
            $m += "Now Browsing"
            $m += $script:WinHostFolderPath
            if  ($script:WinHostFolders.Count -eq 0) {
                $m += "This directory has no subfolders"
            } else {
                $m += ""
                $m += $script:WinHostFolderLines
            }

            Show-Menu -HeaderLines 4 -LocalFolderMenu -AllowEnter -MenuLines $m

            #Drill into new folder
            if ($script:MenuChoice -is [int]) {
                $script:WinHostFolderPath = ($script:WinHostFolders[$script:MenuChoice -1]).FullName
            #Pop directory or break and go back to the list of drives when Pop-WinDirectory returns a question mark
            } elseif ($MenuChoice -eq "-") {
                $script:WinHostFolderPath = Pop-WinDirectory $script:WinHostFolderPath
                if ($script:WinHostFolderPath -eq "") {break WinHostDriveSubfolders}
            #New folder
            } elseif ($script:MenuChoice -eq ".") {
                New-WinHostFolder
            #Return selected path
            } elseif ($script:MenuChoice -eq "*") {
                $script:WinHostFolderPath
                return
                break WinHostDriveSubfolders
            #Return $null on exit
            } elseif ($script:MenuChoice -eq "/") {
                $null
                return
            }
        }
    }
}

function Gen-WinHostFolders {
    #Gets and formats subfolders for $WinHostFolderPath for display in Show-Menu

    #Make sure there is always a trailing slash to ensure gci works with drive letters
    if ($script:WinHostFolderPath[-1] -ne "\") {$script:WinHostFolderPath += "\"}

    #Make sure there are actually subfolders
    $script:WinHostFolders = gci -Force $script:WinHostFolderPath | where {$_.PsIsContainer} | Sort-Object -Property name
    #Even if the count is 0 this will make the string "\\" and clutter up the menu
    if ($script:WinHostFolders.count -gt 0) {
        $script:WinHostFolderLines = ($script:WinHostFolders).Name | ForEach-Object {"\" + $_ + "\"}
    }
}

function New-WinHostFolder {
    #Prompts for the name of a new folder and creates it
    #checks if the name is valid and that a file/folder with that name does not already exist

    $names = (gci $script:WinHostFolderPath -force).name
    $success = $false
    $i = 0

    while ($success -eq $false -and $i -lt $script:Options.Retries) {
        cls
        Write-Host "Please enter a name for the new folder:"
        $p = Read-Host
        $q = $null
        $q = Validate-WinPath $p -relative
        if ($q[0] -eq $false) {
            Write-Host "Please enter a valid path name"
            Pause
            $i++
            continue
        }
        if ($q[1].Trim("\") -in $names) {
            Write-Host "A file or folder with this name already exists"
            Pause
            $i++
            continue
        }
        try {
            New-Item -Path $script:WinHostFolderPath -Name $q[1].Trim("\") -ItemType "directory" -ErrorVariable folderError
        } catch {
            $i++
            :NewFolderErrorLoop while ($true) {
                Show-Menu -HeaderLines 3 -MenuLines @(
                    "Creation of directory $($q[1]) in $script:WinHostFolderPath has failed!"
                    "Would you like to attempt to continue or exit?"
                    ""
                    "Continue"
                    "Exit"
                    "View error"
                )
                switch ($script:MenuChoice) {
                    1 {break NewFolderErrorLoop}
                    2 {exit}
                    3 {Write-Host $folderError
                        Pause
                    }
                }
            }
        }
        if (test-path ($script:WinHostFolderPath + $q[1])) {
            $success = $true
            Write-Host "Folder created successfully"
            pause
        }
    }
}

function Convert-WinPathToNix {
    #By default, converts absolute, drive letter anchored windows path to *nix style /<Drive>/<Folder>/
    #Relative switch to just flip slashes
    param (
        [Parameter(Mandatory = $true)]
        [string]$PathIn,
        [switch]$Relative
    )

    if ($PathIn -match '^[A-Z]:\\' -and $($Relative).IsPresent -eq $false) {
        $PathOut = "\" + $PathIn[0] + $PathIn.Substring(2)
        $PathOut = $PathOut.Replace("\","/")
        if ($PathOut[-1] -ne "/") {$PathOut += "/"}
        $PathOut
        return
    } elseif ($PathIn -notmatch '^[A-Z]:\\' -and $($Relative).IsPresent -eq $true) {
        $PathOut = $PathIn.Replace("\","/")
        $PathOut
        return
    } else {
        throw "Could not parse Windows directory!"
    }
}

function Convert-NixPathToWin {
    #Convert the *nix type paths that restic uses internally to windows paths

    param (
        [Parameter(Mandatory = $true)]
        [string]$PathIn
        )

    #Flip the slash if that's all there is
    if ($PathIn -eq "/") {
        $PathOut = "\"
        $PathOut
        return
    }

    $PathOut = ""
    #Convert a /X drive root to X:
    if ($PathIn -match '^/[A-Z]$') {
        $PathOut = $PathIn.Substring(1) + ":"
    }
    #As above but if it prefixes a longer path
    if ($($PathIn.Length) -gt 2 -and $PathIn.substring(0,2) -match '^/[A-Z]') {
        $PathOut += ($PathIn.Substring(1,1) + ":" + $PathIn.Substring(2))
    }
    #Reverse all the slashes to finish up
    $PathOut = $PathOut.Replace("/","\")
    $PathOut
    return
}

function Format-FolderDirsFiles {
    #Build array of strings array for $Show-Menu to list a snapshot's files and folders with header, footer,
    #and leading and/or trailing slashes added for clarity between files and directories
    #as seen in the menu

    [string[]]$script:FolderLines = @()

    #Prefix header
    $script:FolderLines += "Now browsing:"
    #Flip the root slash if we go above the Windows drive level for looks even if that's not really a thing
    if ($script:FolderPath -eq "/") {
        $script:FolderLines += "\"
    #Or convert a real path and add a trailing slash
    } else {
        $l = Convert-NixPathToWin $script:FolderPath
        if ($l[-1] -ne "\") {$l += "\"}
        #Add notice if directory is empty
        if ($script:FolderDirs.Count -eq 0 -and $script:FolderFiles.Count -eq 0) {$l += " (This directory is empty)"}
        $script:FolderLines += $l
    }

    $script:FolderLines += ""

    #Add directories with leading/trailing slashes
    foreach ($Dir in $script:FolderDirs) {
        if ($($Dir.path) -match '^/[A-Z]$') {
            #Add a colon if we go above the *nix root "/"
            $script:FolderLines += ($($Dir.name) + ":\")
        } else {
            $script:FolderLines += ("\" + $($Dir.name) + "\")
        }
    }
    #Add files with only leading slashes
    foreach ($File in $script:FolderFiles) {
        $script:FolderLines += ("\" + $($File.name))
    }

    #suffix footer
    $script:FolderLines += ""
    $script:FolderLines += "Select a file or folder"
}

function Pop-NixDirectory {
    #Returns *nix directory path one level up from input

    param (
        [Parameter(Mandatory = $true)]
        [string]$pathIn
    )
    #Already at root, return empty string and caller should interpret it as an error
    if ($pathIn -match '^/$') {
        ""
        return
    }
    #Trim trailing backslash to make the regex easier
    if ($pathIn[-1] -eq "/") {$pathIn = $pathIn.Substring(0,$pathIn.Length - 1)}
    #Check if there is only one folder below the root slash and then go up to root
    if ($pathIn -match '^[^/]*/{1}[^/]*$') {
        "/"
        return
        #Matches everything ahead of the last forwards slash in the string to go up one level
    } elseif ($pathIn -match ('.*(?=/{1}[^/]*$)')) {
        $Matches[0]
        return
    } else {
        throw "Can't parse *nix directory"
    }

}

function Pop-WinDirectory {
    #Returns Windows directory path one level up from input

    param (
        [Parameter(Mandatory = $true)]
        [string]$pathIn
    )

    #Check if we're already at a drive root - X:\ or X:
    #Return empty string as error the caller to handle
    if ($pathIn -match '^[A-Z]:\\$' -or $pathIn -match '^[A-Z]:$') {
        ""
        return
    } else {
        #Trim trailing backslash to make the regex easier
        if ($pathIn[-1] -eq "\") {$pathIn = $pathIn.Trim("\")}
        #Match everything ahead of the last backslash
        if ($pathIn -match '.*(?=\\{1}[^\\]*$)') {
            $Matches[0]
            return
        } else {
            throw "Could not parse Windows directory!"
        }
    }
}

function Cleave-FileName {
    #Returns file name after the last slash in either a *nix or Windows style path

    param (
        [Parameter(Mandatory = $true)]
        [string]$pathIn
    )
    if ($pathIn -match '[^\\/]*$') {
        $Matches[0]
        return
    } else {
        throw "Can't parse file path"
    }
}

function Replace-IllegalWinChars {
    #Replaces characters illegal in Windows file names with an underscore or another specified
    #character

    param (
        [Parameter(Mandatory = $true)]
        [string]$in,
        [string]$sub = "_"
    )
    $illegal = @("\","/",":","*",'"',"<",">","|")
    if ($sub.Length -gt 1 -or $sub -in $illegal) {$sub = "_"}
    $out = $in
    foreach ($char in $illegal) {$out = $out.Replace("$char","_")}
    $out
}

function Drill-Directory {
    #Go down a directory level in a snapshot and regens data

    $Selection = $script:FolderDirsAndFiles[$script:MenuChoice]
    $script:FolderPath = $Selection.path
    Gen-FolderData
}

function Gen-FileDetails {
    #Make an array of strings with a formatted table of data on the chosen file

    $Selection = $script:FolderDirsAndFiles[$script:MenuChoice]

    [string[]]$script:FileDetailsFormatted = @()
    $FileDetailsTable = new-object PSobject

    $FileDetailsTable | Add-Member -NotePropertyName "Size"  $(Format-Bytes $Selection.size)
    $FileDetailsTable | Add-Member -NotePropertyName "Created" $(Parse-ResticDate $Selection.ctime)
    $FileDetailsTable | Add-Member -NotePropertyName "Modified" $(Parse-ResticDate $Selection.mtime)

    #Convoluted way to get the list formatting
    #Split multiline string and filter out the empty lines it includes
    $script:FileDetailsFormatted = [string[]]($(Convert-NixPathToWin $Selection.path),"") + (($FileDetailsTable|fl|Out-String).Split("`r`n") | where {$_ -ne ""})
}

function Show-FileDetails {
    #Displays the data in $script:FileInfo above a menu with restore options

    Show-Menu -HeaderLines 6 -SlashForBack -MenuLines @(
        $script:FileDetailsFormatted + "" + "Queue for restore" + "Restore now" + "Quick Restore"
    )
}

function Parse-ResticDate {
    #Parse and reformat restic's timestamps
    param([string]$DateStringIn)

    $datetime = [datetime]::Parse($DateStringIn).ToString("yyyy-MM-dd dddd HH:mm-ss")
    $datetime
    return
}

function Gen-FolderDataRecursive {
    #Get json dump of folder's contents, recursively

    cls
    write-host "Getting folder details..."
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " ls" + " $SnapID" + " $(Quote-Path($script:FolderPath))" + " --recursive --json"
    $c = Append-RepoTypeOptions "$c" "$RepoPath"
    $script:FolderDataRecursiveRaw = cmd /c $c | ConvertFrom-Json
}

function Format-FolderDetails {
    #Make array of strings summarizing full contents of a folder

    [string[]]$script:FolderDetailsFormatted = @()
    $FolderDetailsTable = new-object PSobject

    $dirs = -1 #negative offset of one because parent folder is included in this data set
    $files = 0
    [int64]$bytes = 0
    $modTime = [datetime]::MinValue

    #Add up number of files, folders, and most recent modified date
    foreach ($item in $script:FolderDataRecursiveRaw) {
        if ($item.type -eq "dir") { $dirs++ }
        if ($item.type -eq "file") {
            $files++
            $bytes += $item.size
        }
        if ($item.mtime -ne $null) {
            if ([datetime]::parse("$($item.mtime)") -gt $modTime) {
                $modTime = [datetime]::parse("$($item.mtime)")
            }
        }
    }

    $FolderDetailsTable | Add-Member -NotePropertyName "Folders"  $dirs
    $FolderDetailsTable | Add-Member -NotePropertyName "Files"  $files
    $FolderDetailsTable | Add-Member -NotePropertyName "Data"  "$(Format-Bytes $bytes)"
    $FolderDetailsTable | Add-Member -NotePropertyName "Last Modified" $($modTime.ToString("yyyy-MM-dd dddd HH:mm-ss"))

    #Convoluted way to get the list formatting
    #Split multiline string and filter out the empty lines it includes
    $script:FolderDetailsFormatted = ($FolderDetailsTable|fl|Out-String).Split("`r`n") | where {$_ -ne ""}
}

function Show-FolderDetails {
    #Displays the data in $script:FolderDetailsFormatted above a menu with restore options

    Show-Menu -HeaderLines 7 -SlashForBack -MenuLines @(
        [string[]]("$(Convert-NixPathToWin $script:FolderPath)","") + $script:FolderDetailsFormatted + "" + "Queue for restore" + "Restore now" + "Quick Restore"
    )
}

function Confirm-ExitRestore {
    #Displays menu to double check if the user wants to exit a snapshot while items are queued for restore

    if ($script:RestoreFromQueue.Count -gt 0) {
        Show-Menu -HeaderLines 2 -MenuLines @(
            "There are still items queued to for restore!"
            ""
            "Exit anyway"
            "Restore now"
            "Don't exit"
        )
    }
}

function Restore-Item {
    #Takes 'restore from' and 'restore to' paths and figures out the proper command line based on the inputs
    #Leaving $script:RestoreTo as "" means restore to original location

    #Make sure restore to directory doesn't a trailing backslash
    if ($script:RestoreTo.ToCharArray().Count -gt 1 -and $script:RestoreTo[-1] -eq "\") {$script:RestoreTo = $script:RestoreTo.Trim("\")}

    #Set objects type data
    if ($script:RestoreFromSingle.type -eq "dir") {
        $file = $false
        $folder =$true
    } else {
        $file = $true
        $folder = $false
    }
    if ($script:RestoreTo -eq "") {
        $original = $true
        $new = $false
    } else {
        $original = $false
        $new = $true
    }

    #Construct command line argument

    #Base options
    #restic.exe -r B:\Repo --insecure-no-password restore
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " restore"

    #All four different from/to combinations
    if ($folder -eq $true -and $new -eq $true) {
        #"abcdef:/C/Dir1/Dir2/" --target "C:\Dir3\Dir4\"
        $c += " $(Quote-Path("$script:SnapID" + ":" + "$($script:RestoreFromSingle.path)" + "/"))" + " --target $(Quote-Path("$script:RestoreTo" + "\" + "$(Cleave-FileName($script:RestoreFromSingle.path))"))" + " -vv"
    }
    if ($folder -eq $true -and $original -eq $true) {
        #abcdefg:/C/Dir1/Dir2/" --target "C:\Dir1\Dir2"
        $c += " $(Quote-Path("$script:SnapID" + ":" + "$($script:RestoreFromSingle.path)" + "/"))" + " --target $(Quote-Path($(Convert-NixPathToWin($($script:RestoreFromSingle).path))))" + " -vv"
    }
    if ($file -eq $true -and $original -eq $true) {
        #"abcdef:/C/Dir1/Dir2/" --include "file.exe" --target "C:\Dir1\Dir2\"
        $c += " $(Quote-Path("$script:SnapID" + ":" + "$(Pop-NixDirectory($($script:RestoreFromSingle.path)))" + "/"))" + " --include /$(Quote-Path($(Cleave-FileName($($script:RestoreFromSingle.path)))))" + " --target $(Quote-Path($(Convert-NixPathToWin($(Pop-NixDirectory($script:RestoreFromSingle.path))))))\" + " -vv"
    }
    if ($file -eq $true -and $new -eq $true) {
        #"abcdef:/C/Dir1/Dir2/" --include "file.exe" --target "C:\Dir3\Dir4\"
        $c += " $(Quote-Path("$script:SnapID" + ":" + "$(Pop-NixDirectory($($script:RestoreFromSingle.path)))" + "/"))" + " --include /$(Quote-Path($(Cleave-FileName($($script:RestoreFromSingle.path)))))" + " --target $(Quote-Path("$script:RestoreTo"))\" + " -vv"
    }

    #Overwrite, delete, and dry run options
    switch ($script:RestoreOverwriteOption) {
        ([RestoreOverwriteOption]::Different) { } #Noop
        ([RestoreOverwriteOption]::Newer) {$c += " --overwrite if-newer"}
        ([RestoreOverwriteOption]::Never) {$c += " --overwrite never"}
    }
    if ($script:RestoreDeleteOption) {$c += " --delete"}
    if ($script:RestoreDryRunOption -eq $true) {$c += " --dry-run"}
    $c = Append-RepoTypeOptions "$c" "$RepoPath"

    #Soft fail to catch logs and ask user about error
    $ErrorActionPreference = 'Continue'
        cmd /c $c *>&1 | Tee-Object -Variable restoreOutput
    $ErrorActionPreference = 'Stop'

    if ($LASTEXITCODE -ne 0) {
        Restore-ErrorMenu $restoreOutput
    } else {
        Write-RestoreLog $restoreOutput
    }
}

function Restore-Queue {
    #Iterates though all items in restore queue to restore or test restoring

    [CmdletBinding(DefaultParameterSetName='empty')]
    param (
        [Parameter(ParameterSetName = "IndividualDryRuns")]
        [switch]$IndividualDryRuns,
        [Parameter(ParameterSetName = "GroupDryRun")]
        [switch]$GroupDryRun
    )

    #Confirm that state variable match with parameters
    if ($script:RestoreDryRunOption -eq $true -and $($IndividualDryRuns).IsPresent -eq $false -and $($GroupDryRun).IsPresent -eq $false) {
        Throw "Invalid state.  Dry run parameters cannot be specified with out matching `$RestoreDryRunOption."
    }

    cls
    #Clone $RestoreFromQueue array list
    #Iterate through the clone and remove successfully restored items from the original
    #NOT on a dry run
    $items = $script:RestoreFromQueue.Clone()
    foreach ($item in $items) {
        $script:RestoreFromSingle = $item
        #Dry run with individual menus if asked for
        if ($($IndividualDryRuns).IsPresent -eq $true) {
            Restore-SingleItemDryRunMenu
            #$script:RestoreDryRunOption will be flipped if user approves
            if ($script:RestoreDryRunOption -eq $false) {
                Restore-Item
                write-host ""
                pause
                write-host ""
            }
        }
        #Just run the restore command if in group approval or no dry run mode
        if ($($GroupDryRun).IsPresent -eq $true -or $script:RestoreDryRunOption -eq $false -and $($IndividualDryRuns).IsPresent -eq $false) {
            Restore-Item
        }
        #Remove item from original queue list if real restore was done and is successful
        if ($script:LASTEXITCODE -eq 0 -and ($($IndividualDryRuns).IsPresent -eq $true -or $script:RestoreDryRunOption -eq $false)) {
            $script:RestoreFromQueue.Remove($item)
        }
        #Append to array of log file names in group mode
        if ($($GroupDryRun).IsPresent -eq $true) {
            $script:QueueRestoreLogPaths += $script:LastRestoreLog
        }
        #Reset $RestoreDryRunOption for next item in individual mode
        if ($($IndividualDryRuns).IsPresent) {$script:RestoreDryRunOption = $true}
    }

    #Check and display success/failure if real restores were done
    if ($($GroupDryRun).IsPresent -eq $false) {
        if ($script:RestoreFromQueue.count -eq 0) {
            Write-Host ""
            Write-Host "All items restored successfully!"
        } else {
            Write-Host "$($script:RestoreFromQueue.count) items failed to restore!"
            Write-Host ""
            foreach ($item in $script:RestoreFromQueue) {
                Write-Host $(Convert-NixPathToWin($item.path))
            }
        }
        pause
    }
}

function Restore-ErrorMenu {
    #Displays meanings of restic's exit codes and asks to continue or quit

    $errorMessage = "Restore as failed with exit code $script:LASTEXITCODE, "
    switch ($script:LASTEXITCODE) {
        1 {$errorMessage += "a generic error."}
        10 {$errorMessage += "the repository does not exist."}
        11 {$errorMessage += "the repository is already locked."}
        12 {$errorMessage += "the repository password is incorrect."}
        default {$errorMessage += "an unknown error."}
    }
    while ($true) {
        Show-Menu -HeaderLines 4 -MenuLines @(
            "$errorMessage"
            ""
            "Would you like to attempt to continue or exit?"
            ""
            "Continue"
            "Exit"
            "View raw output"
        )

        switch ($script:MenuChoice) {
            1 {return}
            2 {exit}
            3 {Write-Host $args
                Pause
            }
        }
    }
}

function Write-RestoreLog {
    #Outputs log for restore operations and differentiates between real restores and dry runs
    #Default log path is to inside the repository restored from
    #by default $script:CurrentLogPath contains variable name $script:RepoPath as string literal
    #which is expanded here, after the repository is chosen

    param (
        [Parameter(Mandatory = $true)]
        $lines
    )

    if (-not(Test-Path "$(Unquote-Path($(invoke-expression $script:CurrentLogPath)))\restore")) {Create-LogPath}
    if ($script:RestoreDryRunOption -eq $false) {
        $script:LastRestoreLog = "$(get-date -Format "yyyy-MM-dd--HH-mm-ss")" + "_Restore_Log.txt"
    } else {
        $script:LastRestoreLog = "$(get-date -Format "yyyy-MM-dd--HH-mm-ss")" + "_Restore_Log_Dry_Run.txt"
    }
    $lines | out-file $(Invoke-Expression ("$(Quote-Path -Force ("$(Unquote-Path($(invoke-expression $script:CurrentLogPath)))\restore\$($script:LastRestoreLog)"))"))
}

function Open-RestoreLog {
    #Opens last restore log file in system default text editor or another fed as parameter
    #Default log path is to inside the repository restored from
    #$script:CurrentLogPath contains variable name $script:RepoPath as string literal which is expanded here, after the repository is chosen

    param (
        [string]$log = $script:LastRestoreLog
    )
    cmd /c "start `"`" $(Quote-Path -Force ("$(Unquote-Path($(invoke-expression $script:CurrentLogPath)))\restore\$($Log)"))"
}

function Restore-SingleItemDryRunMenu {
    #Runs Restore-Item with dry run option and flips $RestoreDryRunOption if user approves results of restore operation
    #Includes option to automatically open file in system default text editor

    Restore-Item
    if ($script:Options.AutoOpenDryRunLog -eq 1) {Open-RestoreLog}
    write-host ""
    Show-Menu -HeaderLines 2 -noCls -MenuLines @(
        "Are the results of the dry run acceptable?"
        ""
        "Yes"
        "No"
    )
    if ($script:MenuChoice -eq 1) {$script:RestoreDryRunOption = $false}
    return
}

function Confirm-DryRunQueueGroup {
    #Asks user to approve results of dry runs of all queued restores and flips $RestoreDryRunOption if user does so
    #Includes option to automatically open all files in system default text editor

    if ($script:Options.AutoOpenDryRunLog -eq 1) {
        foreach ($log in $script:QueueRestoreLogPaths) {
            Open-RestoreLog $log
        }
    }
    write-host ""
    Show-Menu -HeaderLines 2 -noCls -MenuLines @(
        "Are the results of the dry run acceptable?"
        ""
        "Yes"
        "No"
    )
    if ($script:MenuChoice -eq 1) {$script:RestoreDryRunOption = $false}
    return
}

function Validate-WinPath {
    #Some simple checks to try and make sure string input is a valid windows path
    #returns $false or an array of $true and a fixed path because this will fix typos like
    #extra whitespace, trailing dots, and remove quote for the user since they are not needed
    #Checks for being a valid absolute path by default.  Switches to check as a relative path
    #or as a valid substring of a path to use as a search term

    param (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$pathIn,
        [switch]$Relative,
        [switch]$Search
    )

    $illegalChars = @("<",">",":","`"","/","|","?","*")

    #False for empty, #null, and all whitespace
    if ($pathIn -in "",$null -or $pathIn -match '^\s*$') {
        $false
        return
    }

    #Trim typos and fixable errors - return fix string if nothing else is wrong
    #Trim whitespace, trailing dots are illegal
    #Trim quotes to not bug the user even though they are not needed
    if(-not($($Search).IsPresent)) {
        $pathIn = ($pathIn.Trim()).Trim(".","`"")
    #For a search term only trim quotes as they are not needed and always illegal
    #Leading/trailing whitespace and dots can be meant as substrings of a legal path
    } else {
        $pathIn = $pathIn.Trim("`"")
    }

    #Absolute paths
    if ($($Relative).IsPresent -eq $false -and $($Search).IsPresent -eq $false) {
        #Must start with <X>:\ and be at least 3 chars
        if ($pathIn -notmatch '^[a-z,A-Z]{1}:\\' -or $pathIn.Length -lt $script:Options.Retries) {
            $false
            return
        } else {
            $relativeSegment = $pathIn.Substring(2)
        }
    #Relative paths and search strings
    } else {
        $relativeSegment = $pathIn
    }

    #Check past or not including an <X>:\ drive anchor for
    #illegal chars and that there are not two backslashes in a row
    $lastArrayCharIsBackslash = $false
    foreach ($char in $relativeSegment.ToCharArray()) {
        if ($char -in $illegalChars) {
            $false
            return
        }
        if ($char -eq "\" -and $lastArrayCharIsBackslash -eq $true) {
            $false
            return
        }
        if ($char -eq "\") {
            $lastArrayCharIsBackslash = $true
        } else {
            $lastArrayCharIsBackslash = $false
        }
    }
    @($true,$pathIn)
    return
}

function Read-WinPath {
    #Input and attempt to validate Windows path
    #Returns empty string after retries are used up

    $i = 0
    while ($i -lt $script:options.Retries) {
        $p = ""
        $q = ""
        cls
        Write-Host "Enter a path to restore to"
        $p = Read-Host
        $q = Validate-WinPath $p
        if ($q[0] -eq $true) {
            $q[1]
            return
        } else {
            Write-Host "$p does not appear to be a valid path"
            Write-Host "Please try again"
            pause
        }
        $i++
    }
    ""
    return
}

function Queue-ForRestore {
    #Adds item to the restore queue or tells you it's already been added

    param (
        [Parameter(Mandatory = $true)]
        [PSObject]$item
    )

    cls
    if ($item -notin $script:RestoreFromQueue) {
        $script:RestoreFromQueue.add($item) | out-null
        Write-Host "$(Convert-NixPathToWin($item.path)) has been added to the restore queue."
    } else {
        Write-Host "$($item.path) is already in the restore queue."
    }
    pause
}

function Check-RestoreFromQueueConflict {
    #Check if we need to warn about overlapping restore paths
    #Just warn the use and assume they know what they are doing
    #returns $true or false

    [string[]]$uniqueParentPaths = @()
    $singleUniqueParentPath = $false
    $allDirs = $false
    $allFiles = $false
    $dirs = @()
    $files = @()
    [string[]]$uniqueFileParents = @()
    [string[]]$uniqueDirParents = @()
    [string[]]$dirRestorePaths = @()
    $conflict = $false

    #Check if all items share the same parent immediate parent folder
    $script:RestoreFromQueue | ForEach-Object {$uniqueParentPaths += $(Pop-NixDirectory($_.path))}
    $uniqueParentPaths = $uniqueParentPaths | Sort-Object | Get-Unique
    if ($uniqueParentPaths.count -eq 1) {$singleUniqueParentPath = $true}

    #Check if all items are individual files
    $files = $script:RestoreFromQueue | Where {$_.type -eq "file"}
    if ($script:RestoreFromQueue.count -eq $files.count) {$allFiles = $true}

    #If either of these are the case then no warning is needed because no items have the possibility to overwrite each other
    if ($singleUniqueParentPath -eq $true -or $allFiles -eq $true) {
        $false
        return
    }

    #Check if all items are dirs
    $dirs = $script:RestoreFromQueue | Where {$_.type -eq "dir"}
    if ($script:RestoreFromQueue.count -eq $dirs.count) {$allDirs =$true}

    #If all items are dirs then any overlap could be a problem
    if ($allDirs -eq $true) {
        foreach ($pathA in $uniqueParentPaths) {
            foreach ($pathB in $uniqueParentPaths) {
                if ($pathA -ne $pathB -and $pathA -like ("$pathB" + "/*")) {$conflict = $true}
                if ($conflict -eq $true) {break}
            }
            if ($conflict -eq $true) {break}
        }
    #If there are files too, then allow files individual files to be restored at levels above dirs also being restored
    #and warn about dirs restored at a level above a file
    } else {
        #Get parent paths for folders only
        $dirs | ForEach-Object {$uniqueDirParents += $(Pop-NixDirectory($_.path))}
        $uniqueDirParents = $uniqueDirParents | Sort-Object | Get-Unique

        #First run the same test as for directories
        foreach ($pathA in $uniqueDirParents) {
            foreach ($pathB in $uniqueDirParents) {
                if ($pathA -ne $pathB -and $pathA -like ("$pathB" + "/*")) {$conflict = $true}
                if ($conflict -eq $true) {break}
            }
            if ($conflict -eq $true) {break}
        }
        #Exit test loop because we have a conflict
        if ($conflict -eq $true) {break StopTesting}

        #Get parent paths for folders only
        $files | ForEach-Object {$uniqueFileParents += $(Pop-NixDirectory($_.path))}
        $uniqueFileParents = $uniqueFileParents | Sort-Object | Get-Unique
        #Compare to dirs being restored and not just their parent dir
        $dirRestorePaths = $dirs.path

        foreach ($dirRestorePath in $dirRestorePaths) {
            foreach ($uniqueFileParent in $uniqueFileParents){
                if ($dirRestorePath -eq $uniqueFileParent -or $dirRestorePath -like ("$uniqueFileParent" + "/*")) {$conflict = $true}
                if ($conflict -eq $true) {break}
            }
            if ($conflict -eq $true) {break}
        }
    }
    #this will return false if nothing above flipped it
    $conflict
    return
}

function Clear-RestoreFromQueue {
    #Clears entire restore from queue

    cls
    $script:RestoreFromQueue.Clear()
    Write-Host "Restore queue has been cleared!"
    pause
    return
}

function Check-RestoreFromQueueEmpty {
    #returns true if empty, false if not

    if ($script:RestoreFromQueue.count -lt 1) {
        $true
    } else {
        $false
    }
}

function Warn-RestoreFromQueueEmpty {
    #Just displays a message that the queue is empty

    cls
    Write-Host "Restore queue is empty!"
    Pause
    return
}

function Create-Repo {
    #Initializes a restic repository

    #Ask for path and confirm it's valid
    #Restic will create any missing directories itself
    $gotPath = $false
    $gotPW = $false
    $i = 0
    while ($i -lt $script:options.Retries) {
        $p = ""
        $q = ""
        cls
        Write-Host "Enter a path for the new repository:"
        $p = Read-Host
        if ($p -match '^[a-z,A-Z]{1}:\\') {
            $q = Validate-WinPath $p
            if ($q[0] -eq $true) {
                $p = $q[1]
                $gotPath = $true
                break
            } else {
                Write-Host "$p does not appear to be a valid path"
                Write-Host "Please try again"
                Pause
            }
        } elseif ($p -like "rclone:*") {
            Find-RClonePath
            Find-RCloneConfPath
            $gotPath = $true
            break
        }
        $i++
    }
    if ($gotPath -eq $false) {
        cls
        Write-Host "Failed to get a path for the new repo!"
        Pause
        return
    }

    #Ask for password
    $i = 0
    while ($i -lt $script:options.Retries) {
        $pw1 = ""
        $pw2 = ""
        $hiddenPW1 = ""
        $hiddenPW2 = ""
        $bstr1 = $null
        $bstr2 = $null

        cls
        Write-Host "Please enter a password for the repository."
        Write-Host "Leave blank for no password."
        $hiddenPW1 = Read-Host -AsSecureString
        #Silly workaround encrypting/decrypting because it's the only way to hide input in PS5
        $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($hiddenPW1)
        $pw1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
        #Free unmanaged memory
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1)
        Write-Host ""
        Write-Host "Please reenter the password."
        $hiddenPW2 = Read-Host -AsSecureString
        $bstr2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($hiddenPW2)
        $pw2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)

        if ($pw1 -eq $pw2) {
            $env:RESTIC_PASSWORD = $pw1
            $gotPW = $true
            break
        }   else {
            Write-Host "Passwords do not match!"
            Pause
        }
        $i++
    }
    if ($gotPW -eq $false) {
        cls
        Write-Host "Failed to get a password for the new repo!"
        Pause
        return
    }

    Write-Host ""
    $c = "$(Quote-Path($script:ResticPath))" + " init -r " + "$(Quote-Path($p))"
    #This will still count as $null and not "" even after $env:RESTIC_PASSWORD = ""
    if ($env:RESTIC_PASSWORD -eq $null) {$c += " --insecure-no-password"}
    $c = Append-RepoTypeOptions "$c" "$p"
    $ErrorActionPreference = 'Continue'
    $o = cmd /c $c *>&1
    $ErrorActionPreference = 'Stop'
    Write-Host $o
    pause

    if ($LASTEXITCODE -eq 0) {
        Show-Menu -HeaderLines 2 -MenuLines @(
            "Would you like to pin the new repository?"
            ""
            "Yes"
            "No"
        )
        if ($script:MenuChoice -eq 1) {Pin-Repository $p}
    }
}

function Validate-Decimal {
    #Checks that input can be parsed as a decimal - returns true or false

    param (
        [Parameter(Mandatory = $true)]
        $number
    )

    try {
        [decimal]::Parse($number)|Out-Null
    } catch {
        $false
        return
    }
    $true
    return
}

function Validate-Percentage {
    #Checks if a number can be interpreted as a percentage in either a 0-1 scale or a 0-100 scale
    #Returns true or false, excludes 0% and 100% by default

    param (
        [Parameter(Mandatory = $true)]
        $number,
        [Parameter(ParameterSetName='Hundred')]
        [switch]$Hundred,
        [Parameter(ParameterSetName='One')]
        [switch]$One,
        [switch]$AllowZero
    )

    try {
        $number = [decimal]::Parse($number)
    } catch {
        $false
        return
    }

    if ($AllowZero -and $number -eq 0) {
        $true
        return
    }
    if ($Hundred) {
        if ($number -gt 0 -and $number -lt 100) {
            $true
            return
        } else {
            $false
            return
        }
    }

    if ($One) {
        if ($number -gt 0 -and $number -lt 1) {
            $true
            return
        } else {
            $false
            return
        }
    }
}

function Validate-DataSize {
    #Validates if input matches a data size format such as 50M, 10g, or 20TB for K, M, G, and T and returns true or false
    #$bytes specifies if the suffix is supposed to include the trailing "B" or not

    param (
        [Parameter(Mandatory = $true)]
        [string]$string,
        [Parameter()]
        [bool]$bytes = $true
    )

    #False it doesn't start with a number
    if ($string -match '^[0-9]*') {
        $number = $Matches[0]
    } else {
        $false
        return
    }

    #check that the suffix is valid
    if ($string -match '[kKmMgGtT][bB]$' -and $bytes -eq $true) {
        # case insensitive match for kb, mb, gb, tb at the end
    } elseif ($string -match '[kKmMgGtT]$' -and $bytes -eq $false) {
        #case insensitive match for k, m, g, t at the end
    } else {
        $false
        return
    }

    #Double check the number by parsing as an int
    try {
        [int]::parse($number)|Out-Null
    } catch {
        $false
        return
    }
    #True if all tests passed
    $true
    return
}

function Update-Ini {
    #appends a sting to the end of the ini file or overwrites the entire file with an array of strings

    param (
        [parameter(ParameterSetName="Append")]
        [string]$AppendLine = "",
        [parameter(ParameterSetName="Overwrite")]
        [string[]]$OverwriteLines = @()
    )

    #Remake ini if missing
    if ($AppendLine -ne "" -and -not(Test-Path PowerRestic.ini)) {
        Load-ini
    }

    #Append single line
    if ($AppendLine -ne "" -and $OverwriteLines.Count -eq 0) {
        if ((Get-Content PowerRestic.ini -Raw)[-1] -match '\r' -or (Get-Content PowerRestic.ini -Raw)[-1] -match '\n') {
            Add-Content -Value $AppendLine -Path PowerRestic.ini -Force
        } else {
            Add-Content -Value "`n$AppendLine" -Path PowerRestic.ini -Force
        }
    }

    #Overwrite entire files
    if ($OverwriteLines.Count -gt 0 -and $AppendLine -eq "") {
        if (Test-Path PowerRestic.ini) {
            try {
                del PowerRestic.ini -ErrorAction Stop
            } catch {
                throw "Failed to delete PowerRestic.ini"
            }
        }
        $OverwriteLines | Out-File -FilePath PowerRestic.ini -Force
    }

    #Reload ini after changes
    Load-ini
}

function Pin-ConformationMenu {
    #Takes a path and ask for conformation before (Un)Pinning it

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [parameter(ParameterSetName="Pin")]
        [switch]$Pin,
        [parameter(ParameterSetName="Unpin")]
        [switch]$Unpin
    )

    [string[]]$m = @()
    if ($($Pin).IsPresent) {
        $m += "Are you sure you want to pin the repository at $path"
    } else {
        $m += "Are you sure you want to unpin the repository at $path"
    }
    $m += ""
    $m += "Yes"
    $m += "No"

    Show-Menu -HeaderLines 2 -MenuLines $m

    if ($script:MenuChoice -eq 1) {
        if ($($Unpin).IsPresent) {
            Unpin-Repository $Path
        } else {
            Pin-Repository $Path
        }
    }
}

function Pin-Repository {
    #Appends repository pinning line to ini
    #Reloads ini to update settings and confirm to the user it was written

    param (
        [Parameter(Mandatory = $true)]
        [string]$path
    )

    Update-Ini -AppendLine ("pin=" + "$path")
    if ($path -in $script:Pinned) {
        Write-host "Pinned repository: $path"
    } else {
        Write-Host "Failed to pin repository!"
    }
    pause
}

function Unpin-Repository {
    #Unpins a repository by rewriting the ini file without its line
    #Reloads ini to update settings and confirm to the user it was removed

    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $foundRepo = $false
    [string[]]$IniOut = @()

    $IniIn = get-content "PowerRestic.ini"

    foreach ($line in $IniIn) {
        if ($line -match '(?<=((?i)pin\s*=\s*)).*') {
            if ($Path -like ($matches[0].Trim())) {
                $foundRepo = $true
                continue
            }
        }
        $IniOut += $line
    }
    if ($foundRepo -eq $true) {
        Update-Ini -OverwriteLines $IniOut
    } else {
        Write-Host "$Path not found in existing ini file!"
    }
    if ($path -notin $script:Pinned) {
        Write-host "Unpinned repository: $path"
    } else {
        Write-Host "Failed to unpin repository!"
    }
    pause
}

function Ask-RestoreOptions {
    #Menu to choose and set overwrite and delete options for restore commands

    Show-Menu -HeaderLines 2 -MenuLines @(
        "Select restore options"
        ""
        "OVERWRITE existing files in destination if the snapshot's version is DIFFERENT, leave files in destination that are not in snapshot (Default)"
        "OVERWRITE existing files in destination if the snapshot's version is DIFFERENT, DELETE files in destination that are not in snapshot"
        "OVERWRITE existing files in destination if the snapshot's version is NEWER, leave files in destination that are not in snapshot"
        "OVERWRITE existing files in destination if the snapshot's version is NEWER, DELETE files in destination that are not in snapshot"
        "Do NOT OVERWRITE existing copies of files in destination with those in snapshot, leave files in destination that are not in snapshot"
        "Do NOT OVERWRITE existing copies of files in destination with those in snapshot, DELETE files in destination that are not in snapshot"
    )
    switch ($MenuChoice) {
        1 {
            $script:RestoreOverwriteOption = [RestoreOverwriteOption]::Different
            $script:RestoreDeleteOption = $false
        }
        2 {
            $script:RestoreOverwriteOption = [RestoreOverwriteOption]::Different
            $script:RestoreDeleteOption = $true
        }
        3 {
            $script:RestoreOverwriteOption = [RestoreOverwriteOption]::Newer
            $script:RestoreDeleteOption = $false
        }
        4 {
            $script:RestoreOverwriteOption = [RestoreOverwriteOption]::Newer
            $script:RestoreDeleteOption = $true
        }
        5 {
            $script:RestoreOverwriteOption = [RestoreOverwriteOption]::Never
            $script:RestoreDeleteOption = $false
        }
        6 {
            $script:RestoreOverwriteOption = [RestoreOverwriteOption]::Never
            $script:RestoreDeleteOption = $true
        }
    }
}

function Ask-DryRun {
    #Menu to ask and set if restore operations should be preceded by a dry run

    Show-Menu -HeaderLines 2 -MenuLines @(
            "Perform a dry run first?"
            ""
            "Yes"
            "No"
    )
    if ($MenuChoice -eq 1) {
        $script:RestoreDryRunOption = $true
    } else {
        $script:RestoreDryRunOption = $false
    }

    #Clear this because it will be set again if needed
    $script:DryRunQueueMode = ""
}

function Ask-DryRunQueueMode {
    #Menu to ask and set how dry runs should be performed when restoring from queue

    Show-Menu -HeaderLines 2 -MenuLines @(
        "How should dry runs and restore operations be performed?"
        ""
        "One item at a time:  Perform the dry run for one item and then approve or deny the restore operation before moving on to the next."
        "All at once:  Perform all dry runs and approve or deny all restoration jobs a a whole."
    )
    if ($MenuChoice -eq 1) {
        $script:DryRunQueueMode = "Individual"
    } else {
        $script:DryRunQueueMode = "Group"
    }
}

function Get-RestoreOptionsWarningString {
    #Returns a sting to warn about overwrites and deletes during restore operation base on currently set options

    if ($script:RestoreOverwriteOption -eq [RestoreOverwriteOption]::Different -and $script:RestoreDeleteOption -eq $false) {
        "OVERWRITE existing files in destination if the snapshot's version is DIFFERENT, leave files in destination that are not in snapshot (Default)"
    } elseif ($script:RestoreOverwriteOption -eq [RestoreOverwriteOption]::Different -and $script:RestoreDeleteOption -eq $true) {
        "OVERWRITE existing files in destination if the snapshot's version is DIFFERENT, DELETE files in destination that are not in snapshot"
    } elseif ($script:RestoreOverwriteOption -eq [RestoreOverwriteOption]::Newer -and $script:RestoreDeleteOption -eq $false) {
        "OVERWRITE existing files in destination if the snapshot's version is NEWER, leave files in destination that are not in snapshot"
    } elseif ($script:RestoreOverwriteOption -eq [RestoreOverwriteOption]::Newer -and $script:RestoreDeleteOption -eq $true) {
        "OVERWRITE existing files in destination if the snapshot's version is NEWER, DELETE files in destination that are not in snapshot"
    } elseif ($script:RestoreOverwriteOption -eq [RestoreOverwriteOption]::Never -and $script:RestoreDeleteOption -eq $false) {
        "Do NOT OVERWRITE existing copies of files in destination with those in snapshot, leave files in destination that are not in snapshot"
    } elseif ($script:RestoreOverwriteOption -eq [RestoreOverwriteOption]::Never -and $script:RestoreDeleteOption -eq $true) {
        "Do NOT OVERWRITE existing copies of files in destination with those in snapshot, DELETE files in destination that are not in snapshot"
    }
}

function Get-RestoreDryRunWarningString {
    #Returns sting to warn about including a dry run of a restore operation or not based on currently set options

    if ($script:RestoreDryRunOption -eq $false) {
        "WITHOUT a DRY RUN to preview results"
        return
    } elseif ($script:DryRunQueueMode -eq "") {
        "WITH a DRY RUN to preview results"
        return
    } elseif ($DryRunQueueMode -eq "Individual") {
        "WITH one DRY RUN PER ITEM to preview results"
        return
    } elseif ($DryRunQueueMode -eq "Group") {
        "WITH a SINGLE DRY RUN to preview results"
        return
    }
}

###################################################################################################
#Main loop
###################################################################################################
#Inside main loop each menu has a menu address and a matching while loop
#Jumping between menus is controlled by changing the menu address variable and breaking the
####current menu while loop
#Functions concerning the currently selected repository, snapshot, and restoring items generally
#### modify script scope variables and do not return a value
###################################################################################################
#Addresses
###################################################################################################
#   0 - MainMenu
###################################################################################################
# 1000 - TopRepositoryMenu                         # 2000 - TopBackupTaskMenu
# 1100 - ChoosePinnedRepositoryMenu
# 1200 - PinRepositoryMenu
# 1300 - UnpinRepositoryMenu
# 1400 - EnterRepositoryManuallyMenu
# 1500 - CreateRepositoryMenu
# 1700 - RepositoryOperationMenu
# 1710 - SnapshotSelectionMenu
# 1715 - SnapshotOperationsMenu
# 1720 - CheckRepositoryMenu
# 1730 - CheckRepositoryDataTypeMenu
# 1740 - ConfirmCheckRepositoryMetadataOnlyMenu
# 1750 - ConfirmCheckRepositoryFileDataMenu
# 1760 - EditSnapshotTagsMenu
# 1770 - PruneRepositoryData
# 1800 - BrowseAndRestoreMenu
# 1805 - ConfirmQuickRestore
# 1810 - RestoreSingleItemDestinationMenu
# 1820 - RestoreSingleItemOptionsMenu
# 1830 - ConfirmRestoreSingleItemMenu
# 1840 - RestoreQueueDestinationMenu
# 1850 - RestoreQueueOptionsMenu
# 1860 - ConfirmRestoreQueueMenu
# 1870 - ViewRestoreQueue

cls
Write-Host "Starting up..."
Load-ini
Clear-ResticCache

while ($true) {

    :MainMenu while ($MenuAddress -eq 0) {
        Clear-Variables
        Show-Menu -HeaderLines 2 -MenuLines @(
            "Welcome to PowerRestic!",
            "",
            "Work with repositories",
            "Work with backup tasks",
            "Exit"
        )
        switch ($MenuChoice) {
            1 {$MenuAddress = 1000} #TopRepositoryMenu
            2 {$MenuAddress = 2000} #TopBackupTaskMenu
            3 {exit}
        }
        break

    }

    ###################################################################################################
    #Repository Tasks
    ###################################################################################################

    :TopRepositoryMenu while ($MenuAddress -eq 1000) {
        Clear-Variables
        Show-Menu -HeaderLines 2 -SlashForBack -MenuLines @(
            "Manage Repositories"
            ""
            "Choose a pinned repository"
            "Pin a Repository"
            "Unpin a repository"
            "Enter a repository path manually"
            "Create a repository"
            "Exit"
        )
        switch ($MenuChoice) {
            1 {$MenuAddress = 1100} #ChoosePinnedRepositoryMenu
            2 {$MenuAddress = 1200} #PinRepositoryMenu
            3 {$MenuAddress = 1300} #UnpinRepositoryMenu
            4 {$MenuAddress = 1400} #EnterRepositoryManuallyMenu
            5 {$MenuAddress = 1500} #CreateRepositoryMenu
            6 {exit}
            "/" {$MenuAddress = 0}    #MainMenu
        }
        break

    }

    :ChoosePinnedRepositoryMenu while ($MenuAddress -eq 1100) {
        #Go back up a level if there's nothing to show
        if ($Pinned.count -lt 1) {
            Write-host "No pinned repos found"
            write-host ""
            pause
            write-host ""
            $MenuAddress = 1000 #TopRepositoryMenu
            break ChoosePinnedRepositoryMenu
        }
        #Build string array listing repository options
        [string[]] $PinnedRepoHeader = @(
            "$($Pinned.Count) pinned repositories found"
            ""
        )

        Show-Menu -HeaderLines 2 -SlashForBack -MenuLines ($PinnedRepoHeader + $Pinned)
        if ($MenuChoice -in "/") {
            #Go back
            $MenuAddress = 1000
            break ChoosePinnedRepositoryMenu
        }

        #Try and open the repo
        $p = $Pinned[($MenuChoice - 1)]
        Open-Repo $p
        if ($RepoOpened -eq $true) {
            $MenuAddress = 1700 #RepositoryOperationMenu
        #Ask to remove pins if they have failed to open
        } else {
            Show-Menu -HeaderLines 2 -MenuLines @(
            "Failed to open $p!  Would you like to unpin it?"
            ""
            "Yes"
            "No"
            )
            if ($MenuChoice -eq 1) {Unpin-Repository $p}
        }
    }

    :PinRepositoryMenu while ($MenuAddress -eq 1200) {
        $i = 0
        :PinRepositoryMenuRetry while ($i -lt $Options.Retries -and $RepoOpened -eq $false) {
            cls
            Write-host "Please enter the path to the repository you would like to pin:"
            $p = Read-Host

            #Confirm local drive paths are syntactically valid
            if ($p -match '^[a-z,A-Z]{1}:\\') {
                $q = Validate-WinPath $p
                if ($q[0] -eq $true) {
                    $p = $q[1]
                } else {
                    Write-host ""
                    Write-host "Please enter a valid path"
                    Write-host ""
                    pause
                    $i++
                    continue
                }
            }

            #Check it doesn't already exist
            foreach ($pin in $Pinned) {
                if ($pin -like $p) {
                    Write-host ""
                    Write-host "Repository $p is already pinned!"
                    Write-host ""
                    pause
                    $i++
                    continue PinRepositoryMenuRetry
                }
            }

            #In case you're just setting this up in advance or something
            Show-Menu -HeaderLines 2 -MenuLines @(
                "Would you like to test the repository at $p before pinning it?"
                ""
                "Yes"
                "No"
            )
            if ($MenuChoice -eq 1){
                Open-Repo $p
                $i++
            }
            if ($MenuChoice -eq 2 -or $RepoOpened -eq $true) {
                Pin-Repository $p
                break PinRepositoryMenuRetry
            }
        }
        $MenuAddress = 1000 #TopRepositoryMenu
    }

    :UnpinRepositoryMenu while ($MenuAddress -eq 1300) {
        #Go back up a level if there's nothing to show
        if ($Pinned.count -lt 1) {
            Write-host "No pinned repos found"
            write-host ""
            pause
            write-host ""
            $MenuAddress = 1000 #TopRepositoryMenu
            break UnpinRepositoryMenu
        }
        #Build string array listing repository options
        [string[]] $PinnedRepoHeader = @(
            "Select a repository to unpin"
            ""
        )
        #Select Repository
        Show-Menu -HeaderLines 2 -SlashForBack -MenuLines ($PinnedRepoHeader + $Pinned)
        if ($MenuChoice -in "/") {
            #Go back
            $MenuAddress = 1000
            break ChoosePinnedRepositoryMenu
        }
        #Confirm removal
        if ($MenuChoice -is [int]) {
            $r = $Pinned[($MenuChoice - 1)]
            Pin-ConformationMenu -Path $r -Unpin
        }
        #Go back up either way
        $MenuAddress = 1000 #TopRepositoryMenu
        break UnpinRepositoryMenu
    }

    :EnterRepositoryManuallyMenu while ($MenuAddress -eq 1400) {
        $i = 0
        while ($i -lt $Options.Retries -and $RepoOpened -eq $false) {
            cls
            Write-host "Please enter the path to the repository:"
            $p = Read-Host
            Open-Repo $p
            $i++
        }
        if ($RepoOpened -eq $true) {
            $MenuAddress = 1700 #RepositoryOperationMenu
        } else {
            $MenuAddress = 1000 #Back to top repo menu
        }
    }

    :CreateRepositoryMenu while ($MenuAddress -eq 1500) {
        Create-Repo
        $MenuAddress = 1000
    }

    :RepositoryOperationMenu while ($MenuAddress -eq 1700) {
        #Check if repo path is already pinned and add option to do the reverse
        $AlreadyPinned = $null
        $PinOrUnpin = ""
        foreach ($repo in $Pinned) {
            if ($RepoPath -like $repo) {
                $AlreadyPinned = $true
                break
            }
            $AlreadyPinned = $false
        }
        if ($AlreadyPinned -eq $true) {
            $PinOrUnpin = "Unpin this repository"
        } else {
            $PinOrUnpin = "Pin this repository"
        }

        #Now we get to the menu
        Show-Menu -HeaderLines 3 -SlashForBack -MenuLines @(
            "$($RepoInfo.repo_path)"
            "Repository ID $($RepoInfo.id)"
            ""
            "Get repository stats"
            "Check repository integrity"
            "Work with snapshots"
            "$PinOrUnpin"
            "Prune old data"
            "Return to main menu"
            "Exit"
        )
        switch ($MenuChoice) {
            1 {
                Gen-RepoStats
                cls
                Write-Host $RepoPath
                $RepoStats|fl
                pause
            }
            2 {$MenuAddress = 1720} #CheckRepositoryMenu
            3 {$MenuAddress = 1710} #SnapshotSelectionMenu
            4 {
                if ($AlreadyPinned -eq $true) {
                #Confirm unpinning and then go back up a level
                    Pin-ConformationMenu -Path $RepoPath -Unpin
                    if ($RepoPath -notin $Pinned) {
                        $MenuAddress = 1000 #TopRepositoryMenu
                        break RepositoryOperationMenu
                    }
                #Or just confirm and pin
                } else {
                    Pin-ConformationMenu -Path $RepoPath -Pin
                }
            }
            5 {$MenuAddress = 1770} #PruneRepositoryData
            6 {$MenuAddress = 0} #MainMenu
            7 {exit}
            "/" {$MenuAddress = 1000} #TopRepositoryMenu
        }
        break
    }

    :SnapshotSelectionMenu while ($MenuAddress -eq 1710) {
        #Clear changes that could be cause by deeper menus
        $RestoreFromQueue.Clear()
        Gen-Snapshots

        if ($Snapshots.count -eq 0) {
            cls
            Write-Host "No snapshots found in $RepoPath!"
            pause
            $MenuAddress = 1000 #TopRepositoryMenu
            break
        }

        Show-Menu -HeaderLines 2 -IndentHeader -FooterLines 4 -IndentFooter -SlashForBack -MenuLines @(
            $Snapshots + "" + "Enter a snapshot's number"
        )

        if ($MenuChoice -in "/") {
            $MenuAddress = 1700 #RepositoryOperationMenu
        } else {
            $SnapID = $SnapIDs[$MenuChoice - 1]
            $MenuAddress = 1715 #SnapshotOperationsMenu
        }
        break SnapshotSelectionMenu
    }

    :SnapshotOperationsMenu while ($MenuAddress -eq 1715) {
        #Clear changes that could be cause by deeper menus
        $RestoreFromQueue.Clear()
        #Generate data
        Get-SnapshotStats
        Format-SnapshotStats

        #Build menu
        [string[]]$m = @()
        $m += "Snapshot Stats"
        $m += ""
        $m += $SnapshotStatsFormatted
        $m += ""
        $m += "Browse/restore from this snapshot"
        $m += "Jump to path in this snapshot"
        $m += "Forget this snapshot"
        $m += "Edit this snapshot's tags"

        Show-Menu -HeaderLines 18 -SlashForBack -MenuLines $m

        switch ($MenuChoice) {
            1 {$MenuAddress = 1800} #BrowseAndRestoreMenu
            2 {
                if (Jump-ToSnapshotPath) {
                    $MenuAddress = 1800
                    $KeepPage = $true
                }
            }
            3 {
                Forget-Snapshot $SnapID
                $MenuAddress = 1710 #SnapshotSelectionMenu
            }
            4 {$MenuAddress = 1760} #EditSnapshotTagsMenu
            default {$MenuAddress = 1710} #SnapshotSelectionMenu
        }
        break SnapshotOperationsMenu
    }

    :CheckRepositoryMenu while ($MenuAddress -eq 1720) {
        Show-Menu -HeaderLines 2 -SlashForBack -MenuLines @(
            "Repo ID $($RepoInfo.id) at $($RepoInfo.repo_path) selected"
            ""
            "Check repository metadata integrity"
            "Check repository metadata and data integrity"
        )
        switch ($MenuChoice) {
            1 {$MenuAddress = 1740} #ConfirmCheckRepositoryMetadataOnlyMenu
            2 {$MenuAddress = 1730} #CheckRepositoryDataTypeMenu
            "/" {$MenuAddress = 1700} #RepositoryOperationMenu
        }
        break CheckRepositoryMenu
    }

    :CheckRepositoryDataTypeMenu while ($MenuAddress -eq 1730) {
        Show-Menu -HeaderLines 2 -MenuLines @(
            "Select data to check in repository ID $($RepoInfo.id) at path $RepoPath"
            ""
            "Check all data"
            "Specify a percentage of total repository data to check at random"
            "Specify a fixed amount of repository data to check at random"
        )
        #Build command line arguments in $RepoCheckCommand
        switch ($MenuChoice) {
            1 {
                $RepoCheckCommand = "--read-data"
                $MenuAddress = 1750 #ConfirmCheckRepositoryFileDataMenu
                break CheckRepositoryDataTypeMenu
            }
            2 {
                Write-Host "What percentage of data would you like to check?"
                $n = Read-Host
                $n = $n.Trim("%")
                if ((Validate-Decimal $n) -and (Validate-Percentage -number $n -Hundred)) {
                    $RepoCheckCommand = "--read-data-subset=$($n)%"
                    $MenuAddress = 1750 #ConfirmCheckRepositoryFileDataMenu
                    break CheckRepositoryDataTypeMenu
                } else {
                    Write-Host "Entry could not be parsed as a percentage!"
                    pause
                }
            }
            3 {
                Write-Host "How much data would you like to read?"
                Write-Host "Integer plus single letter size suffix, i.e. 10G"
                $n = Read-Host
                if ((Validate-DataSize -string $n -bytes $false) -ne $false) {
                    $RepoCheckCommand = "--read-data-subset=$($n)"
                    $MenuAddress = 1750 #ConfirmCheckRepositoryFileDataMenu
                    break CheckRepositoryDataTypeMenu
                } else {
                    Write-Host "Entry could not be parsed correctly!"
                    pause
                }
            }
        }
    }

    :ConfirmCheckRepositoryMetadataOnlyMenu while ($MenuAddress -eq 1740) {
        Show-Menu -HeaderLines 2 -MenuLines @(
            "Check metadata of repository ID $($RepoInfo.id) at path $RepoPath ?"
            ""
            "Yes"
            "No"
        )
        if ($MenuChoice -eq 1) {
            cls
            $c = "$(Quote-Path($script:ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$script:RepoPasswordCommand" + " check -vv"
            $c = Append-RepoTypeOptions "$c" "$RepoPath"
            cmd /c $c
            pause
        }
        $MenuAddress = 1700 #RepositoryOperationMenu
        break ConfirmCheckRepositoryMetadataOnlyMenu
    }

    :ConfirmCheckRepositoryFileDataMenu while ($MenuAddress -eq 1750) {
        #Get amount of data text for menu
        if ($($RepoCheckCommand.split("=")).count -eq 1) {
            $a = "ALL"
        } else {
            $a = "$($RepoCheckCommand.split("=")[1]) of"
        }
        Show-Menu -HeaderLines 2 -MenuLines @(
            "Do you want to check $a data in repository ID $($RepoInfo.id) at path $RepoPath"
            ""
            "Yes"
            "No"
        )
        if ($MenuChoice -eq 1) {
            cls
            $c = "$(Quote-Path($script:ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$script:RepoPasswordCommand" + " check $RepoCheckCommand -vv"
            $c = Append-RepoTypeOptions "$c" "$RepoPath"
            cmd /c $c
            pause
        }
        $MenuAddress = 1700 #RepositoryOperationMenu
        break ConfirmCheckRepositoryFileDataMenu
    }

    :EditSnapshotTagsMenu while ($MenuAddress -eq 1760) {
        [string[]]$m = @()
        $m += "Edit tags for the following snapshot"
        $m += ""
        $m += $SnapshotStatsFormatted
        $m += ""
        $m += "Add a tag"
        $m += "Remove a tag"
        $m += "Clear all tags"

        Show-Menu -HeaderLines 18 -SlashForBack -MenuLines $m
        switch ($MenuChoice) {
            1 {Add-SnapshotTag}
            2 {Remove-SnapshotTag}
            3 {Clear-SnapshotTags}
            "/" {
                $MenuAddress = 1715
                break EditSnapshotTagsMenu
            }
        }
        #Find the new ID and display the updated data after changes have been made
        Find-ChangedSnapshot
        Get-SnapshotStats
        Format-SnapshotStats
    }

    :PruneRepositoryData while ($MenuAddress -eq 1770) {
        Show-Menu -HeaderLines 2 -MenuLines @(
            "Prune unused data in repository at $($RepoPath)?"
            ""
            "Yes"
            "No"
        )
        if ($MenuChoice -eq 1) {
            Show-Menu -HeaderLines 2 -MenuLines @(
                "Perform prune as a dry run?"
                ""
                "Yes"
                "No"
            )
            if ($MenuChoice -eq 1) {
                Prune-Repo -DryRun
            } else {
                Prune-Repo
            }
        }
        $MenuAddress = 1700
        break PruneRepositoryData
    }

    :BrowseAndRestoreMenu while ($MenuAddress -eq 1800) {
        #Reads and displays contents  of a snapshot.  Starts at the snapshot's root and lets the user drill
        #down to lower level directories and files with options to view info and restore single files or
        #entire folders

        #Get root path when initially entering menu, skip if circling back with $KeepPage
        if ($KeepPage -eq $false) {Check-RootFolderPath}
        #Cycle though menu
        #Break :KeepFolderData after generating data about a new choice so :RefreshFolderData will resort it
        :RefreshFolderData while ($true) {
                Sort-FolderData
                Format-FolderDirsFiles
            :KeepFolderData while($true) {
                #Display the menu, remember long menus are nested within Split-Menu
                Show-Menu -HeaderLines 3 -FooterLines 2 -RestoreFolderMenu -AllowEnter -MenuLines $FolderLines
                #################################
                #Exit to snapshot selection menu
                #################################
                if ($MenuChoice -in @("/")) {
                    #Check if items are queued for restore and ask to confirm exit if there are any
                    Confirm-ExitRestore
                    #Exit choices from previous menus
                    if ($MenuChoice -in 1,"/") {
                        $MenuAddress = 1715 #SnapshotOperationsMenu
                    #Restore queued items
                    } elseif ($MenuChoice -eq 2) {
                        $MenuAddress = 1840 #RestoreQueueDestinationMenu
                        $KeepPage = $true
                    #Go back to last page if not exiting or restoring
                    } elseif ($MenuChoice -eq 3) {
                        $KeepPage = $true
                    }
                    break BrowseAndRestoreMenu
                ##############
                #Pop directory
                ##############
                } elseif ($MenuChoice -in @("-")) {
                    if ((Pop-NixDirectory($FolderPath)) -eq "") {
                        write-host ""
                        write-host "Already at root!"
                        write-host ""
                        Pause
                    } else {
                        $FolderPath = Pop-NixDirectory($FolderPath)
                        Gen-FolderData
                    }
                    break KeepFolderData
                ###################################
                #Get full data about current folder
                ###################################
                } elseif ($MenuChoice -in @(".")) {
                    $KeepPage = $true
                    Gen-FolderDataRecursive
                    Format-FolderDetails
                    Show-FolderDetails
                    #Restore options
                    switch ($MenuChoice) {
                        #Add to list of items to restore
                        1 {Queue-ForRestore $FolderData[1]}
                        #Restore this single item now
                        2 {
                            $RestoreFromSingle = $FolderData[1]
                            $KeepPage = $true
                            $MenuAddress = 1810 #RestoreSingleItemDestinationMenu
                            break BrowseAndRestoreMenu
                        }
                        #Quick restore to original location
                        3 {
                            $RestoreFromSingle = $FolderData[1]
                            $KeepPage = $true
                            $MenuAddress = 1805 #ConfirmQuickRestore
                            break BrowseAndRestoreMenu
                        }
                    }
                #####################
                #Restore queued items
                #####################
                } elseif ($MenuChoice -in @("*")) {
                    $KeepPage = $true
                    $MenuAddress = 1840 #RestoreQueueDestinationMenu
                    break BrowseAndRestoreMenu
                ####################
                #Choosing a new item
                ####################
                } elseif ($MenuChoice -is [int]) {
                    $MenuChoice = $MenuChoice - 1 #array offset
                    $BrowseChoice = $FolderDirsAndFiles[$MenuChoice]
                    #Drill into chosen directory
                    if ($BrowseChoice.type -eq "dir") {
                        Drill-Directory
                        break KeepFolderData
                    #Display file info
                    } elseif ($BrowseChoice.type -eq "file") {
                        $KeepPage = $true
                        Gen-FileDetails
                        Show-FileDetails
                        #Restore options
                        switch ($MenuChoice) {
                        #Add to list of items to restore
                            1 {Queue-ForRestore $BrowseChoice}
                        #Restore this single item now
                            2 {
                                $RestoreFromSingle = $BrowseChoice
                                $KeepPage = $true
                                $MenuAddress = 1810 #RestoreSingleItemDestinationMenu
                                break BrowseAndRestoreMenu
                            }
                            #Quick restore to original location
                            3 {
                                $RestoreFromSingle = $BrowseChoice
                                $KeepPage = $true
                                $MenuAddress = 1805 #ConfirmQuickRestore
                                break BrowseAndRestoreMenu
                            }
                        }
                    }
                }
            }
        }
        break BrowseAndRestoreMenu
    }

    :ConfirmQuickRestore while ($MenuAddress -eq 1805) {
        #Resets options for quick restore and gives one last chance change your mind if option is set

        $RestoreTo = ""
        $RestoreOverwriteOption = [RestoreOverwriteOption]::Different
        $RestoreDeleteOption = $false
        $RestoreDryRunOption = $false

        if ($Options.QuickRestoreConfirm -eq 1) {
            Show-Menu -HeaderLines 4 -MenuLines @(
                "Restore $($RestoreFromSingle.name) to original location?"
                "$(Get-RestoreOptionsWarningString)"
                "$(Get-RestoreDryRunWarningString)"
                ""
                "Yes"
                "No"
            )
        }
        if ($MenuChoice -eq 1 -or $Options.QuickRestoreConfirm -eq 0) {
            Restore-Item
            pause
        }
        $MenuAddress = 1800
        break ConfirmQuickRestore
    }

    :RestoreSingleItemDestinationMenu while ($MenuAddress -eq 1810) {
        #Pick destination for a single item chosen for restore

        Show-Menu -HeaderLines 2 -SlashForBack -MenuLines @(
            "$(Convert-NixPathToWin($RestoreFromSingle.path)) selected"
            ""
            "Restore to original location"
            "Browse other restore location"
            "Enter restore location manually"
        )
        #Set $RestoreTo and move on to next menu
        switch ($MenuChoice) {
            1 {
                $RestoreTo = "" #Empty string is interpreted as the original location
                $MenuAddress = 1820 #RestoreSingleItemOptionsMenu
                break RestoreSingleItemDestinationMenu
            }
            2 {
                $p = Browse-RestoreToPath
                if ($p -eq $null) { #$null if Browse-RestoreToPath is exited
                    break RestoreSingleItemDestinationMenu
                } else {
                    $RestoreTo = $p
                    $MenuAddress = 1820 #RestoreSingleItemOptionsMenu
                    break RestoreSingleItemDestinationMenu
                }
            }
            3 {
                $p = Read-WinPath
                if ($p -ne "") { #Read-WinPath returns an empty string after retries are used up.
                    $RestoreTo = $p
                    $MenuAddress = 1820 #RestoreSingleItemOptionsMenu
                    break RestoreSingleItemDestinationMenu
                } else {
                    break RestoreSingleItemDestinationMenu
                }
            }
        }
        $MenuAddress = 1800 #BrowseAndRestoreMenu
        break RestoreSingleItemDestinationMenu
    }

    :RestoreSingleItemOptionsMenu while ($MenuAddress -eq 1820) {
        #Sets options and moves on
        Ask-RestoreOptions
        Ask-DryRun
        $MenuAddress = 1830 #ConfirmRestoreSingleItemMenu
        break RestoreSingleItemOptionsMenu
    }

    :ConfirmRestoreSingleItemMenu while ($MenuAddress -eq 1830) {
        #Displays restore option and confirms operation with user before running restore

        #Build menu array
        [string[]]$m = @()
        #RestoreTo -eq "" means to original location
        if ($RestoreTo -eq "") {
            $m += "Restore $($RestoreFromSingle.name) to original location?"
        } else {
            $m += "Restore $($RestoreFromSingle.name) to $($RestoreTo)?"
        }
        $m += "$(Get-RestoreOptionsWarningString)" #Display these setting again for the user
        $m += "$(Get-RestoreDryRunWarningString)"
        $m += ""
        $m += "Yes"
        $m += "No"

        Show-Menu -HeaderLines 4 -MenuLines $m

        #Restore item and go back to BrowseAndRestoreMenu
        if ($MenuChoice -eq 1) {
            #This will change $RestoreDryRunOption to false if the user approves the results
            if ($RestoreDryRunOption -eq $true) {
                Restore-SingleItemDryRunMenu
            }
            #Skip real restore if $RestoreDryRunOption is not changed and go back to browse menu
            if ($RestoreDryRunOption -eq $false) {
                Restore-Item
                pause
            }
        }

        $MenuAddress = 1800 #BrowseAndRestoreMenu
        break ConfirmRestoreSingleItemMenu
    }

    :RestoreQueueDestinationMenu while ($MenuAddress -eq 1840) {
        #Destination options for queued items as well checking and editing queue

        #Go back if the queue is empty
        if (Check-RestoreFromQueueEmpty) {
            Warn-RestoreFromQueueEmpty
            $MenuAddress = 1800 #BrowseAndRestoreMenu
            break RestoreQueueDestinationMenu
        }

        #Build menu array
        [string[]]$m = @()
        $m += "$($script:RestoreFromQueue.count) items selected"
        $l = 2
        #Check if items have overlapping paths that may overwrite each other and add warning if needed
        if (Check-RestoreFromQueueConflict) {
            $m += "WARNING: Some items chosen for restore have overlapping paths.  Continuing may lead to unexpected results."
            $l++
        }
        $m += ""
        $m += "Restore to original location"
        $m += "Browse other restore location"
        $m += "Enter restore location manually"
        $m += "Review queued items"
        $m += "Clear restore queue"

        Show-Menu -HeaderLines $l -SlashForBack -MenuLines $m

        switch ($MenuChoice) {
            1 {
                $RestoreTo = "" #Empty string is interpreted as original location
                $MenuAddress = 1850 #RestoreQueueOptionsMenu
                break RestoreQueueDestinationMenu
            }
            2 {
                $p = Browse-RestoreToPath
                if ($p -eq $null) { #Browse-RestoreToPath returns $null if exited
                    break RestoreQueueDestinationMenu
                } else {
                    $RestoreTo = $p
                    $MenuAddress = 1850 #RestoreQueueOptionsMenu
                    break RestoreQueueDestinationMenu
                }
            }
            3 {
                $p = Read-WinPath
                if ($p -ne "") { #Read-WinPath returns $null after running out of retries
                    $RestoreTo = $p
                    $MenuAddress = 1850 #RestoreQueueOptionsMenu
                    break RestoreQueueDestinationMenu
                } else {
                    break RestoreQueueDestinationMenu
                }
            }
            4 {
                $MenuAddress = 1870 #ViewRestoreQueue
                break RestoreQueueDestinationMenu
            }
            5 {
                Clear-RestoreFromQueue
                break RestoreQueueDestinationMenu
            }
        }
        $MenuAddress = 1800 #BrowseAndRestoreMenu
        break RestoreQueueDestinationMenu
    }

    :RestoreQueueOptionsMenu while ($MenuAddress -eq 1850) {
        #Collect options and move on

        Ask-RestoreOptions
        Ask-DryRun
        if ($RestoreDryRunOption -eq $true) {
            Ask-DryRunQueueMode
        }
        $MenuAddress = 1860
        break RestoreQueueOptionsMenu
    }

    :ConfirmRestoreQueueMenu while ($MenuAddress -eq 1860) {
        #Displays restore options and confirms operation with user before running restore

        #Build menu array
        [string[]]$m = @()
        if ($RestoreTo -eq "") {
            $m += "Restore $($script:RestoreFromQueue.count) items to original locations?"
        } else {
            $m += "Restore $($script:RestoreFromQueue.count) items to $($RestoreTo)?"
        }
        $m += "$(Get-RestoreOptionsWarningString)" #Display these setting again for the user
        $m += "$(Get-RestoreDryRunWarningString)"
        $m += ""
        $m += "Yes"
        $m += "No"

        Show-Menu -HeaderLines 4 -MenuLines $m

        #Restore items and go back to BrowseAndRestoreMenu

        #Just restore everything at once
        if ($MenuChoice -eq 1 -and $RestoreDryRunOption -eq $false) {
            Restore-Queue
        #Dry run all at once, do it again for real if approved
        } elseif ($MenuChoice -eq 1 -and $RestoreDryRunOption -eq $true -and $DryRunQueueMode -eq "Group") {
            $script:QueueRestoreLogPaths = @()
            Restore-Queue -GroupDryRun
            Confirm-DryRunQueueGroup
            if ($RestoreDryRunOption -eq $false) {
                Restore-Queue
            }
        #Go through each item in queue individually with the single item functions.
        } elseif ($MenuChoice -eq 1 -and $RestoreDryRunOption -eq $true -and $DryRunQueueMode -eq "Individual") {
            Restore-Queue -IndividualDryRuns
        }
        $MenuAddress = 1800 #BrowseAndRestoreMenu
        break ConfirmRestoreQueueMenu
    }

    :ViewRestoreQueue while ($MenuAddress -eq 1870) {
        #View restore queue and remove individual items

        if (Check-RestoreFromQueueEmpty) {
            Warn-RestoreFromQueueEmpty
            $MenuAddress = 1800 #BrowseAndRestoreMenu
            break ViewRestoreQueue
        }
        $KeepPage = $false
        [string[]]$m = @()
        $m += "$($RestoreFromQueue.count) items in restore queue"
        $m += ""
        $script:RestoreFromQueue | ForEach-Object {$m += Convert-NixPathToWin($_.path)}
        $m += ""
        Show-Menu -HeaderLines 2 -FooterLines 1 -QueueMenu -MenuLines $m
        if ($MenuChoice -is [int]) {
            $RestoreFromQueue.Remove($RestoreFromQueue[$MenuChoice - 1])
        } elseif ($MenuChoice -in @("/","")) {
            $MenuAddress = 1840 #RestoreQueueDestinationMenu
            break ViewRestoreQueue
        } elseif ($MenuChoice -eq "-") {
            Clear-RestoreFromQueue
            $MenuAddress = 1800 #BrowseAndRestoreMenu
            break ViewRestoreQueue
        }
    }

    ###################################################################################################
    #Backup Tasks
    ###################################################################################################

    :TopBackupTaskMenu while ($MenuAddress -eq 2000) {
        cls
        write-host "Backup task creation and management coming soon!"
        pause
        $MenuAddress = 0
    }
}