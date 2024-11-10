﻿####################################################################
#Reset settings
####################################################################
#Resets everything else if you're using this in ISE or something

$ErrorActionPreference = 'Stop'
[string[]] $script:Pinned = @()
$Options = new-object PSobject
$ResticPath = $null
$MenuAddress = 0

####################################################################
#Functions
####################################################################

function Clear-Variables {
    #Clear menu navigation relevant variables when needed while ascending menu trees
    try {remove-variable -name MenuChoice -Scope script -ErrorAction Stop} catch {} #Menu choice entered by user
    $script:MenuPage = 1 #For keeping the same page if the menu options don't change
    $script:KeepPage = $false #as above
    $script:RepoPath = $null #Path to root folder of selected repository
    $script:RepoPassword = $null #Password to selected repository
    $script:RepoPasswordCommand = $null #No password flag added to repo command is set
    $script:env:RESTIC_PASSWORD = $null #Environment variable Restic  reads the password from
    $script:RepoStats = $null #Object repository information from different  commands is merged into
    $script:RepoUnlocked = $false #Set to true after basic info is successfully read from repository
    $script:RepoInfo = $null #Identifying info read from repo as part of testing path/password
    [array]$script:SnapIDs = @() #Restic's short snapshot IDs.  Used to get info about or browse a specific snapshot
    $script:SnapID = $null #Selected snapshot short ID for querying info or browsing
    $Script:NoPinned = $false #Set to true if Load-ini finds pinned repos
    [string[]] $script:Snapshots = @() #Snapshot list formatted for Show-Menu
    $Script:SnapshotStatsRaw = $null #Object Restic's nested json snapshot info is put into
    [string[]]$script:SnapshotStatsFormatted = @() #Array of the useful data in formatted strings
    $script:FolderPath = $null #Current path being browsed in snapshot
    [array]$script:FolderData = $null #Object with converted data from Restic's json
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
    $script:NewRepoPath = ""
}

function Load-ini {
    #create basic settings file if none is found
    if (!(test-path "PowerRestic.ini")) {
        Make-Ini
    }
    $RawIni = get-content "PowerRestic.ini"

    foreach ($line in $RawIni) {
        #Check for exe path
        if ($line -like "ResticPath=*" -and (test-path ($line.split("="))[1])) {
            $Script:ResticPath = ($line.split("="))[1]
        #Make an array of pinned repos
        } elseif ($line -like "pin*=*") {
            $script:Pinned += (($line.split("="))[1]).trim()
        #Skip comments, section headers,blank lines, lines starting with a space
        } elseif ($line[0] -in @(";","[",""," ") -or "=" -notin $line.ToCharArray()) {
            #noop
        #Throw everything else in a generic option object
        } else {
            $script:Options | Add-Member -NotePropertyName (($line.split("="))[0]).trim() (($line.split("="))[1]).trim()
        }
    }
    if ($script:options.debug -eq 1) {
        write-host ""
        foreach ($line in $RawIni) { write-host $line}
        write-host ""
    }

    #Make sure settings won't cause an exception
    Check-Settings
}

function Make-Ini {
    #Find path for restic exe and set defaults for required settings

    $mResticPath = ""
    cls
    Write-Host "No settings found!"
    Write-Host ""
    if (Test-Path "restic.exe") {
        Write-Host "Will use restic.exe found found in working directory."
        $mResticPath = "restic.exe"
    } else {
        $i = 0
        while ($mResticPath -eq "" -and $i -lt 3) {
            Write-Host "Please enter the path to the restic executable:"
            $s = Read-Host
            if ((Test-Path "$s") -and $s.substring(($s.length - 4))) {
                $mResticPath = $s
                Write-Host "Restic executable exists"
            } else {
                Write-Host "Restic executable not found"
                $i++
            }
        }
    }
    Write-Host ""
    Write-Host "Writing default settings"
    "[PowerRestic]" | Out-File .\PowerRestic.ini
    "" | Out-File .\PowerRestic.ini -Append
    "ResticPath=$($mResticPath)" | Out-File .\PowerRestic.ini -Append
    "" | Out-File .\PowerRestic.ini -Append
    "DisplayLines=50" | Out-File .\PowerRestic.ini -Append
    "Retries=3" | Out-File .\PowerRestic.ini -Append

    Start-Sleep -s 3
}

function Check-Settings {
    #Check and set defaults for required settings

    #Check working directory for restic.exe
    if (Test-Path "restic.exe") {$script:ResticPath = "restic.exe"}
    #exit if no exe was found
    if ($script:ResticPath -eq $null -or -not(test-path $script:ResticPath)) {
        Write-Host "Restic Executable not found."
        exit 1
    }

    try {[int]::Parse($script:Options.retries)} catch {$script:Options.retries = 1}
    if ($script:Options.retries -lt 1) {$script:Options.retries = 1}

    try {[int]::Parse($script:Options.DisplayLines)} catch {$script:Options.DisplayLines = 1}
    if ($script:Options.DisplayLines -lt 10) {$script:Options.DisplayLines = 10}
}

function Show-Menu{
    param (
        [Parameter(Mandatory = $true)]
        [int]$HeaderLines,
        [Parameter(Mandatory = $true)]
        [bool]$IndentHeader,
        [Parameter(Mandatory = $true)]
        [int]$FooterLines,
        [Parameter(Mandatory = $true)]
        [bool]$IndentFooter,
        [bool]$ScrollMenu = $false,
        [Parameter()]
        [bool]$FolderMenu = $false,
        [Parameter()]
        [bool]$RestoreMenu = $false,
        [Parameter()]
        [bool]$QueueMenu = $false,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$MenuLines
    )
    #Turns an array of strings into a numbered menu
    #Headers and footers which are not turned into numbered options can be specified
    #They can be indented to match the numbers prefixing the choices or not
    #Common separator characters are multiped to match when indented
    #$ScrollMenu and $FolderMenu enable options for scrolling pages and browsing folders respectively
    #$ScrollMenu is only added a a parameter when called from within Split-Menu
    #Any number of $MenuLines may be fed on
    #If the number of $MenuLines minus $HeaderLines and $FooterLines exceeds $Options.DisplayLines all of Show-Menu's
    #inputs will be fed to Split-Menu, chopped up, and fed back to Show-Menu

    #Reset choice
    try {remove-variable -name MenuChoice -Scope script -ErrorAction Stop} catch {}

    cls

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
        Split-Menu -HeaderLines $HeaderLines -IndentHeader $IndentHeader -FooterLines $FooterLines -IndentFooter $IndentFooter -FolderMenu $FolderMenu -RestoreMenu $RestoreMenu -QueueMenu $QueueMenu -MenuLines $MenuLines
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
                if ($IndentHeader -eq $True) {
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
                if ($IndentFooter -eq $True) {
                    $output += " "*($offset + 3) + $line + "`n"
                } else {
                    $output += $line + "`n"
                }
            }
        }
    }
    #write out menu
    write-host $output

    #Input is taken and validated in a separate function
    Read-MenuChoice -NumberOfOptions $NumberOfOptions -ScrollMenu $ScrollMenu -FolderMenu $FolderMenu -RestoreMenu $RestoreMenu -QueueMenu $QueueMenu
}

function Split-Menu {
    param (
        [Parameter(Mandatory = $true)]
        [int]$HeaderLines,
        [Parameter(Mandatory = $true)]
        [bool]$IndentHeader,
        [Parameter(Mandatory = $true)]
        [int]$FooterLines,
        [Parameter(Mandatory = $true)]
        [bool]$IndentFooter,
        [bool]$ScrollMenu = $true,
        [Parameter()]
        [bool]$FolderMenu = $false,
        [Parameter()]
        [bool]$RestoreMenu = $false,
        [Parameter()]
        [bool]$QueueMenu = $false,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$MenuLines
    )

    #This takes the same parameters as show-menu
    #it chops them up into smaller sections and feeds them back to show-menu

    #Subtract header and footer lines to get number of menu options
    $NumberOfOptions = $MenuLines.Count - ($HeaderLines + $FooterLines)
    #Split header, foot, and options into different arrays
    $MenuHeader = [string[]]$MenuLines[0..($HeaderLines - 1)]
    $MenuFooter = [string[]]$MenuLines[($MenuLines.Count - $FooterLines)..($MenuLines.Count)]
    $MenuOptions = [string[]]$MenuLines[($HeaderLines)..($MenuLines.Count - $FooterLines - 1)]

    #Get number of pages needed
    $NumberOfPages = [math]::Ceiling($NumberOfOptions/$options.DisplayLines)

    #increment $FooterLines to insert page numbers at bottom
    $FooterLines = $FooterLines + 1

    #Call Show-Menu once for each page
    while ($true) {
        $PageLines = ($MenuHeader + $MenuOptions[(($script:MenuPage - 1) * $Options.DisplayLines)..((($script:MenuPage - 1) * $Options.DisplayLines) + ($Options.DisplayLines - 1))] + $MenuFooter + "Page $script:MenuPage/$NumberOfPages")
        Show-Menu -HeaderLines $HeaderLines -IndentHeader $IndentHeader -FooterLines $FooterLines -IndentFooter $IndentFooter -ScrollMenu $ScrollMenu -FolderMenu $FolderMenu -RestoreMenu $RestoreMenu -QueueMenu $QueueMenu -MenuLines ([string[]]$PageLines)
        #Adjust page number
        if ($script:MenuChoice -eq "") {$script:MenuPage++}
        if ($script:MenuChoice -in "+") {$script:MenuPage = $script:MenuPage -1}
        #Wrap around
        if ($script:MenuPage -gt $NumberOfPages) {$script:MenuPage = 1}
        if ($script:MenuPage -lt 1) {$script:MenuPage = $NumberOfPages}
        #Break and return to original menu for up or exit
        if ($script:MenuChoice -in "-",".","/","*") {break}
        #Add multiplier for number of pages in to $MenuChoice to match the full array of items
        if ($script:MenuChoice -is [int]) {
            $script:MenuChoice = [int]($script:MenuChoice + (($script:MenuPage - 1) * $Options.DisplayLines))
            break
        }
    }
    return
}

function Read-MenuChoice {
    param (
        [Parameter(Mandatory = $true)]
        [int]$NumberOfOptions,
        [Parameter()]
        [bool]$ScrollMenu = $false,
        [Parameter()]
        [bool]$FolderMenu = $false,
        [Parameter()]
        [bool]$RestoreMenu = $false,
        [Parameter()]
        [bool]$QueueMenu = $false
    )
    #Validates that input is within the number of listed choices
    #Adds other input options based on $ScrollMenu and $FolderMenu

    #Reset choice if left over
    try {remove-variable -name MenuChoice -Scope script -ErrorAction Stop} catch {}

    #Start with all the numbers options plus just hitting enter
    $AcceptableChoices = 0..$NumberOfOptions
    $AcceptableChoices += ""

    #Add options for each combination of $ScrollMenu and $FolderMenu

    #Single page and flat menu
    if ($ScrollMenu -eq $false -and $FolderMenu -eq $false) {
        #not sure if something will go
    }
    #Multiple pages and flat menu
    if ($ScrollMenu -eq $true -and $FolderMenu -eq $false) {
        write-host "Enter for next screen, `"+`" for last screen, `"/`" to exit this menu"
        $AcceptableChoices += "+","/"
    }
    #Single page menu with levels, restorable or not restorable
    if ($ScrollMenu -eq $false -and $FolderMenu -eq $true -and $RestoreMenu -eq $true) {
        write-host "`"-`" to go up a directory, `".`" for information about current directory,`"*`" to restore queued items, `"/`" to exit this menu"
        $AcceptableChoices += "-",".","/","*"
    }
    if ($ScrollMenu -eq $false -and $FolderMenu -eq $true -and $RestoreMenu -eq $false) {
        write-host "`"-`" to go up a directory, `".`" for information about current directory, `"/`" to exit this menu"
        $AcceptableChoices += "-",".","/"
    }
    #Multiple page menu with levels, restorable or not restorable
    if ($ScrollMenu -eq $true -and $FolderMenu -eq $true -and $RestoreMenu -eq $true) {
        write-host  "Enter for next screen, `"+`" for last screen, `"-`" to go up a directory, `".`" for information about current directory, `"*`" to restore queued items, `"/`" to exit this menu"
        $AcceptableChoices += "+","-",".","/","*"
    }
    if ($ScrollMenu -eq $true -and $FolderMenu -eq $true -and $RestoreMenu -eq $false) {
        write-host  "Enter for next screen, `"+`" for last screen, `"-`" to go up a directory, `".`" for information about current directory, or `"/`" to exit this menu"
        $AcceptableChoices += "+","-",".","/"
    }
    if ($ScrollMenu -eq $true  -and $QueueMenu -eq $true) {
        write-host  "Enter for next screen, `"+`" for last screen, `"-`" to clear the queue, or `"/`" to exit this menu"
        $AcceptableChoices += "+","-","/"
    }
    if ($ScrollMenu -eq $false  -and $QueueMenu -eq $true) {
        write-host  "Enter `"-`" to clear the queue or `"/`" to exit this menu"
        $AcceptableChoices += "-","/"
    }

    #Get input and check it
    $Script:MenuChoice = read-host
    #Make sure that numbers count as ints to prevent problems in other places
    try {$Script:MenuChoice = [int]::Parse($Script:MenuChoice)} catch {}
    while ($Script:MenuChoice -notin $AcceptableChoices) {
        write-host ""
        write-host "Please enter a valid choice."
        write-host ""
        try {remove-variable -name MenuChoice -Scope script -ErrorAction Stop} catch {}
        $Script:MenuChoice = read-host
    }
    return
}

function Format-Bytes  {
    #Make bytes easily readable without drawing commas on your screen
    param (
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

function Open-Repo {
    param ([string]$path)

    cls
    #Confirm that folder even exists
    if ($path -eq "" -or -not(Test-Path $path)) {
        Write-Host "$path not found.  Please try again"
        pause
        return
    } else {
        Write-Host "$path exists."
        write-host ""
    }

    #Automatically try to open with no password
    $i = -1 #Offset for automatic first try with no password
    $script:RepoPasswordCommand = " --insecure-no-password"
    $env:RESTIC_PASSWORD = ""
    while ($i -lt $script:Options.Retries -or $script:RepoUnlocked -eq $false) {
        $c = "$(Quote-Path($script:ResticPath))" + " -r $(Quote-Path($Path))" + "$script:RepoPasswordCommand" + " cat config"
        #redirection shenanigans to ensure a hard fail and hide restic's output
        try {
            $o = cmd /c $c *>&1 | ConvertFrom-Json
        } catch {$o=$null}

        #Basic check of the hex identifiers that cat config returns as check for valid data
        if ($o.version -is [int] -and $o.id -match'[0-9a-f]+' -and $o.chunker_polynomial -match '[0-9a-f]+') {
            $script:RepoUnlocked = $true
            $script:RepoPath = $path
            $o | Add-Member -NotePropertyName "repo_path" $script:RepoPath
            $script:RepoInfo = $o
            return
        } else {
            #Hide failure notice for first try and get rid of the no password flag
            if ($i -gt -1) {
                write-host "Failed to open repo"
                write-host ""
            } else {
                $script:RepoPasswordCommand = ""
            }
        }

        Write-Host "Please enter the password for this repository:"
        #Silly workaround encrypting/decrypting because it's the only way to hide input
        $HiddenPassword = Read-Host -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($HiddenPassword)
        $RepoPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        while ($RepoPassword -eq "" -or $RepoPassword -eq $null){
            Write-Host "Repo password cannot be blank."
            $HiddenPassword = Read-Host -AsSecureString
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($HiddenPassword)
            $RepoPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
        }
        #Free unmanaged memory
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $env:RESTIC_PASSWORD = $RepoPassword
        $i++
    }
    $env:RESTIC_PASSWORD = ""
    $script:RepoPasswordCommand = ""
}

function Quote-Path {
    #Adds quotes around a file path if it has spaces, for use in building command line arguments
    param ([string[]]$Path)
    if (" " -in $Path.ToCharArray()) {
        $Path = "`"" + $Path + "`""
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
    cls
    write-host "Getting snapshot stats..."
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " cat snapshot" + " $SnapID"
    $Script:SnapshotStatsRaw = cmd /c $c | ConvertFrom-Json
}

function Format-SnapshotStats {
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

function Gen-FolderData {
    #Populates $script:FolderData with subfolders and files in$script:FolderPath
    cls
    write-host "Getting folder contents..."
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " ls" + " $SnapID" + " $(Quote-Path($script:FolderPath))" + " --json"
    $script:FolderData = cmd /c $c | ConvertFrom-Json
}

function Check-RootFolderPath {
    #Workaround to skip *nix-type "/" path root and show the drive's contents when backup consists of a single drive letter
    $script:FolderPath = '/'
    Gen-FolderData
    #If the ls of "/" returns only "/" and "/X" (any capital letter) just skip to "/X"
    if ($script:FolderData.count -eq 2 -and ($script:FolderData[1]).path -match '^/[A-Z]$') {
        $script:FolderPath = ($script:FolderData[1]).path
        Gen-FolderData
    }
}

function Sort-FolderData {
    #Make separate lists of files and folders while fixing case sensitive sort
    [array]$script:FolderDirs = @()
    [array]$script:FolderFiles = @()
    [array]$script:FolderDirsAndFiles = @()
    foreach ($item in $script:FolderData) {
        if ($item.type -eq "dir" -and $item.path -eq $script:FolderPath) {continue}
        switch ($item.type) {
            "dir" {$script:FolderDirs += $item}
            "file" {$script:FolderFiles += $item}
        }
    }
    $script:FolderDirs = $script:FolderDirs | Sort-Object -Property name
    $script:FolderFiles = $script:FolderFiles | Sort-Object -Property name
    $script:FolderDirsAndFiles = $script:FolderDirs  + $script:FolderFiles
}

function Convert-NixPathToWin {
    param ([string]$PathIn)
    #Convert the *nix type paths that restic uses internally to windows paths for display
    #Flip the slash if that's all there is
    if ($PathIn -eq "/") {
        $PathOut = "\"
        $PathOut
        return
    }
    $PathOut = ""
    #Convert root drive letter
    #For just the drive to show under "/"
    if ($PathIn -match '^/[A-Z]$') {
        $PathOut = $PathIn.Substring(1) + ":"
    }
    #For a longer path
    if ($($PathIn.ToCharArray().Count) -gt 2 -and $PathIn.substring(0,2) -match '^/[A-Z]') {
        $PathOut += ($PathIn.Substring(1,1) + ":" + $PathIn.Substring(2))
    }
    #Reverse slashes
    $PathOut = $PathOut.Replace("/","\")
    $PathOut
    return
}

function Format-FolderDirsFiles {
    #Make array for $Show-Menu to list files and folders with header, footer,
    #and leading and/or trailing slashes added for clarity
    [array]$script:FolderLines = @()

    #Prefix header
    $script:FolderLines += "Now browsing:"
    #Flip the root slash if we go above the Windows drive level
    if ($script:FolderPath -eq "/") {
        $script:FolderLines += "\"
    } else {
        $script:FolderLines += (Convert-NixPathToWin $script:FolderPath) + "\"
    }
    $script:FolderLines += ""

    #Add leading/trailing slashes to directories
    foreach ($Dir in $script:FolderDirs) {
        if ($($Dir.path) -match '^/[A-Z]$') {
            #Add a colon if we go above the *nix root "/"
            $script:FolderLines += ($($Dir.name) + ":\")
        } else {
            $script:FolderLines += ("\" + $($Dir.name) + "\")
        }
    }
    #Add only leading slashes for files
    foreach ($File in $script:FolderFiles) {
        $script:FolderLines += ("\" + $($File.name))
    }

    #suffix footer
    $script:FolderLines += ""
    $script:FolderLines += "Select a file or folder"
}

function Pop-NixDirectory {
    param (
        [string]$pathIn
    )
    #Already at root
    if ($pathIn -match '^/$') {
        ""
        return
    #Check if there is only one folder below the root slash and then go up to root
    } elseif ($pathIn -match '^[^/]*/{1}[^/]*$') {
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
    param (
        [string]$pathIn
    )
    #Go up one windows directory
    #Matches everything ahead of the last backslash in the string to go up one level
    if ($pathIn -match '.*(?=\\{1}[^\\]*$)') {
        $pathOut = $Matches[0]
        $pathOut
        return
    } else {
        throw "Can't parse windows directory"
    }
}

function Cleave-FileName {
    param (
        [string]$pathIn
    )
    if ($pathIn -match '[^\\/]*$') {
        $Matches[0]
        return
    } else {
        throw "Can't parse file path"
    }
}

function Drill-Directory {
    #Go down a directory level of display details about a file

    #Pick $script:MenuChoice out of the array and regen data
    $Selection = $script:FolderDirsAndFiles[$script:MenuChoice]
    $script:FolderPath = $Selection.path
    Gen-FolderData
}

function Gen-FileDetails {
    #Pick $script:MenuChoice out of the array
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
    #Displays the data in $script:FileInfo
    cls
    Show-Menu -HeaderLines 6 -IndentHeader $false -FooterLines 2 -IndentFooter $false -MenuLines @(
        $script:FileDetailsFormatted + "" + "Queue for restore" + "Restore now" + "Quick Restore" + "" + "Enter to return"
    )
}

function Parse-ResticDate {
    #Parse and reformat restic's timestamps
    $datetime = [datetime]::Parse($args).ToString("yyyy-MM-dd dddd HH:mm-ss")
    $datetime
    return
}

function Gen-FolderDataRecursive {
    #json dump of folder's contents, recursively
    cls
    write-host "Getting folder details..."
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " ls" + " $SnapID" + " $(Quote-Path($script:FolderPath))" + " --recursive --json"
    $script:FolderDataRecursiveRaw = cmd /c $c | ConvertFrom-Json
}

function Format-FolderDetails {
    #Summarize full contents of a folder
    [string[]]$script:FolderDetailsFormatted = @()
    $FolderDetailsTable = new-object PSobject

    $dirs = -1 #negative offset of one because parent folder is included in this data set
    $files = 0
    [int64]$bytes = 0
    $modTime = [datetime]::MinValue

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
    #$FolderDetailsTable | Add-Member -NotePropertyName "Last Modified" $($modTime.ToString("yyyy-MM-dd dddd HH:mm-ss"))

    #Convoluted way to get the list formatting
    #Split multiline string and filter out the empty lines it includes
    $script:FolderDetailsFormatted = ($FolderDetailsTable|fl|Out-String).Split("`r`n") | where {$_ -ne ""}
}

function Show-FolderDetails {
    #Displays the data in $script:FolderDetailsFormatted
    cls
    Show-Menu -HeaderLines 6 -IndentHeader $false -FooterLines 2 -IndentFooter $false -MenuLines @(
        [string[]]("$(Convert-NixPathToWin $script:FolderPath)","") + $script:FolderDetailsFormatted + "" + "Queue for restore" + "Restore now" + "Quick Restore" + "" + "Enter to return"
    )
}

function Confirm-ExitRestore {
    if ($script:RestoreFromQueue.Count -gt 0) {
        Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 0 -IndentFooter $false -MenuLines @(
            "There are still items queued to for restore!"
            ""
            "Exit anyway"
            "Restore now"
            "Don't exit"
        )
    }
}

function Restore-Item {
    #Takes from and to paths and figures out the proper command line based on the inputs
    #Leaving $script:RestoreTo as "" means restore to original location

    #Make sure restore to directory doesn't a trailing backslash
    if ($script:RestoreTo.ToCharArray().Count -gt 1 -and $script:RestoreTo[-1] -eq "\") {$script:RestoreTo = $script:RestoreTo.Trim("\")}

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
    $c = "$(Quote-Path($ResticPath))" + " -r $(Quote-Path($RepoPath))" + "$RepoPasswordCommand" + " restore"

    if ($folder -eq $true -and $new -eq $true) {
        #restic.exe -r B:\Repo --insecure-no-password restore "abcdef:/C/Dir1/Dir2/" --target "C:\Dir3\Dir4\"
        $c += " $(Quote-Path("$script:SnapID" + ":" + "$($script:RestoreFromSingle.path)" + "/"))" + " --target $(Quote-Path("$script:RestoreTo" + "\" + "$(Cleave-FileName($script:RestoreFromSingle.path))"))" + " -vv"
    }
    if ($folder -eq $true -and $original -eq $true) {
        #restic.exe -r B:\Repo --insecure-no-password restore "abcdef:/C/Dir1/Dir2/" --target "C:\Dir1\Dir2"
        $c += " $(Quote-Path("$script:SnapID" + ":" + "$($script:RestoreFromSingle.path)" + "/"))" + " --target $(Quote-Path($(Convert-NixPathToWin($($script:RestoreFromSingle).path))))" + " -vv"
    }
    if ($file -eq $true -and $original -eq $true) {
        #restic.exe -r B:\Repo --insecure-no-password restore "abcdef:/C/Dir1/Dir2/" --include "file.exe" --target "C:\Dir1\Dir2\"
        $c += " $(Quote-Path("$script:SnapID" + ":" + "$(Pop-NixDirectory($($script:RestoreFromSingle.path)))" + "/"))" + " --include $(Quote-Path($(Cleave-FileName($($script:RestoreFromSingle.path)))))" + " --target $(Quote-Path($(Convert-NixPathToWin($(Pop-NixDirectory($script:RestoreFromSingle.path))))))" + " -vv"
    }
    if ($file -eq $true -and $new -eq $true) {
        #restic.exe -r B:\Repo --insecure-no-password restore "abcdef:/C/Dir1/Dir2/" --include "file.exe" --target "C:\Dir3\Dir4\"
        $c += " $(Quote-Path("$script:SnapID" + ":" + "$(Pop-NixDirectory($($script:RestoreFromSingle.path)))" + "/"))" + " --include $(Quote-Path($(Cleave-FileName($($script:RestoreFromSingle.path)))))" + " --target $(Quote-Path("$script:RestoreTo"))" + " -vv"
    }

    $ErrorActionPreference = 'Continue'
        cmd /c $c *>&1 | Tee-Object -Variable output
    $ErrorActionPreference = 'Stop'


    if ($LASTEXITCODE -ne 0) {
        Restore-ErrorMenu $output
    } else {
        #
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
        Show-Menu -HeaderLines 4 -IndentHeader $false -FooterLines 0 -IndentFooter $false -MenuLines @(
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

function Validate-WinPath {
    param (
        [string]$pathIn
    )
    #Some simple checks to try and make sure string input is a valid windows path
    #returns $false or an array of $true and the path because this will fix extra whitespace and trailing dots
    $illegalChars = @("<",">",":","`"","/","|","?","*")
    #Trim whitespace
    #trailing dots are illegal
    $pathIn = ($pathIn.Trim()).Trim(".")

    #Check it starts with a proper drive letter prompt
    if ($pathIn -notmatch '^[a-z,A-Z]{1}:\\') {
        $false
        return
    }

    #Check for illegal chars and that there are not to backslashes in a row
    $lastCharIsBackslash = $false
    foreach ($char in ($pathIn.Substring(2).ToCharArray())) {
        if ($char -in $illegalChars) {
            $false
            return
        }
        if ($char -eq "\" -and $lastCharIsBackslash -eq $true) {
            $false
            return
        }
        if ($char -eq "\") {
            $lastCharIsBackslash = $true
        } else {
            $lastCharIsBackslash = $false
        }
    }
    @($true,$pathIn)
    return
}

function Read-WinPath {
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
    param (
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
            #Check if we need to warn about overlapping restores
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
        $conflict
        return
}

function Clear-RestoreFromQueue {
    cls
    $script:RestoreFromQueue.Clear()
    Write-Host "Restore queue has been cleared!"
    pause
    return
}

function Check-RestoreFromQueueEmpty {
    if ($script:RestoreFromQueue.count -lt 1) {
        $true
    } else {
        $false
    }
}

function Warn-RestoreFromQueueEmpty {
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
        $bstr1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($hiddenPW1)
        $pw1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
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
    if ($env:RESTIC_PASSWORD -eq $null) {$c += " --insecure-no-password"}
    cmd /c $C
    pause
}

###################################################################################################
#Main loop
###################################################################################################
#Inside main loop each menu has a menu address and a matching while loop
#Jumping between menus is controlled by changing the menu address variable and breaking the
##current menu while loop
#Functions are called in order according to menu logic and generally modify script scope variables
##Being more general, menus are an exception and only reference the script settings externally
###################################################################################################
#Addresses
###################################################################################################
#   0 - MainMenu
###################################################################################################
#1000 - TopRepositoryMenu                         #2000 - TopBackupTaskMenu
#1100 - ChoosePinnedRepositoryMenu
#1200 - PinRepositoryMenu
#1300 - UnpinRepositoryMenu
#1400 - EnterRepositoryManuallyMenu
#1500 - CreateRepositoryMenu
#1700 - RepositoryOperationMenu
#1710 - SnapshotSelectionMenu
#1720 - CheckRepositoryMenu
#1730 - CheckRepositoryDataTypeMenu
#1740 - ConfirmCheckRepositoryMenu
#1800 - BrowseAndRestoreMenu
#1810 - RestoreSingleItemDestinationMenu
#1820 - RestoreSingleItemOptionsMenu
#1830 - ConfirmRestoreSingleItemMenu
#1840 - RestoreQueueDestinationMenu
#1850 - RestoreQueueOptionsMenu
#1860 - ConfirmRestoreQueueMenu
#1870 - ViewRestoreQueue

Load-ini

while ($true) {

    :MainMenu while ($MenuAddress -eq 0) {
        Clear-Variables
        Show-Menu -HeaderLines 2 -IndentHeader $false  -FooterLines 0 -IndentFooter $false -MenuLines @(
            "Welcome to PowerRestic!",
            "",
            "Work with repositories",
            "Work with backup tasks",
            "Exit"
        )
        switch ($MenuChoice) {
            1 {$MenuAddress = 1000}
            2 {$MenuAddress = 2000}
            3 {exit}
        }
        break

    }

    ###################################################################################################
    #Repository Tasks
    ###################################################################################################

    :TopRepositoryMenu while ($MenuAddress -eq 1000) {
        Clear-Variables
        Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 0 -IndentFooter $false -MenuLines @(
            "Manage Repositories"
            ""
            "Choose a pinned repository"
            "Pin a Repository"
            "Unpin a repository"
            "Enter a repository path manually"
            "Create a repository"
            "Return to main menu"
            "Exit"
        )
        switch ($MenuChoice) {
            1 {$MenuAddress = 1100} #ChoosePinnedRepositoryMenu
            2 {$MenuAddress = 1200} #PinRepositoryMenu
            3 {$MenuAddress = 1300} #UnpinRepositoryMenu
            4 {$MenuAddress = 1400} #EnterRepositoryManuallyMenu
            5 {$MenuAddress = 1500} #CreateRepositoryMenu
            6 {$MenuAddress = 0}    #MainMenu
            7 {exit}
        }
        break

    }

    :ChoosePinnedRepositoryMenu while ($MenuAddress -eq 1100) {
        if ($Pinned.count -lt 1) {
            #Go back up a level if there's nothing to show
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
        [string[]] $PinnedRepoFooter = @(
            ""
            "Select a Repo or enter to go back"
        )
        Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 2 -IndentFooter $false -MenuLines ($PinnedRepoHeader + $Pinned + $PinnedRepoFooter)
        if ($MenuChoice -eq "") {
            #Go back if you just hit enter
            $MenuAddress = 1000
            break ChoosePinnedRepositoryMenu
        }
        #Try and open the repo
        Open-Repo $Pinned[($MenuChoice - 1)]
        if ($RepoUnlocked -eq $true) {$MenuAddress = 1700} #RepositoryOperationMenu
    }

    :PinRepositoryMenu while ($MenuAddress -eq 1200) {
        write-host ""
        write-host "Not implemented yet.  Press enter to continue"
        read-host
        $MenuAddress = 1000
    }

    :UnpinRepositoryMenu while ($MenuAddress -eq 1300) {
        write-host ""
        write-host "Not implemented yet.  Press enter to continue"
        read-host
        $MenuAddress = 1000
    }

    :EnterRepositoryManuallyMenu while ($MenuAddress -eq 1400) {
        $i = 0
        while ($i -lt $Options.Retries -and $RepoUnlocked -eq $false) {
            cls
            Write-host "Please enter the path to the repository:"
            $p = Read-Host
            Open-Repo $p
            $i++
        }
        if ($RepoUnlocked -eq $true) {
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
        Show-Menu -HeaderLines 3 -IndentHeader $false -FooterLines 0 -IndentFooter $false -MenuLines @(
            "$($RepoInfo.repo_path)"
            "Repository ID $($RepoInfo.id)"
            ""
            "Get repository stats"
            "Check repository integrity"
            "Work with snapshots"
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
            4 {$MenuAddress = 0}    #MainMenu
            5 {exit}
        }
        break
    }

    :SnapshotSelectionMenu while ($MenuAddress -eq 1710) {
        #Only regen snapshots if they've been reset ata higher menu level
        if ($Snapshots.count -eq 0) {Gen-Snapshots}
        #Check again and make sure the repo even has snapshots
        if ($Snapshots.count -eq 0) {
            cls
            Write-Host "No snapshots found in $RepoPath!"
            pause
            $MenuAddress = 1000
            break
        }
        Show-Menu -HeaderLines 2 -IndentHeader $true -FooterLines 4 -IndentFooter $true -MenuLines @(
                $Snapshots + "" + "Enter a snapshot's number or enter to return"
            )
            if ($MenuChoice -eq "") {
                $MenuAddress = 1700
                break
            }
            $SnapID = $SnapIDs[$MenuChoice - 1]
            Get-SnapshotStats
            Format-SnapshotStats
            Show-Menu -HeaderLines 18 -IndentHeader $false -FooterLines 2 -IndentFooter $false -MenuLines @(
                [string[]]("Snapshot Stats","") + $SnapshotStatsFormatted + "" + "Browse/restore from this snapshot" + "" + "Enter to return"
            )
                switch ($MenuChoice) {
                    1 {$MenuAddress = 1800} #BrowseAndRestoreMenu
                }
            break
    }

    :CheckRepositoryMenu while ($MenuAddress -eq 1720) {
        Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 0 -MenuLines $false @(
            "Repo ID $($RepoInfo.id) at $($RepoInfo.repo_path) selected"
            ""
            "Check repository metadata integrity"
            "Check repository metadata and data integrity"
            "Return to main menu"
            "Exit"
        )
        switch ($MenuChoice) {
            1 {$MenuAddress -eq 1740} #ConfirmCheckRepositoryMenu
            2 {$MenuAddress -eq 1730} #CheckRepositoryDataTypeMenu
            3 {$MenuAddress = 0}      #MainMenu
            4 {exit}
        }
        write-host ""
        write-host "Not implemented yet.  Press enter to continue"
        read-host
        $MenuAddress = 1700
        break
    }

    :CheckRepositoryDataTypeMenu while ($MenuAddress -eq 1730) {
        write-host ""
        write-host "Not implemented yet.  Press enter to continue"
        read-host
        $MenuAddress = 1700
    }

    :ConfirmCheckRepositoryMenu while ($MenuAddress -eq 1740) {
        write-host ""
        write-host "Not implemented yet.  Press enter to continue"
        read-host
        $MenuAddress = 1700
    }

    :BrowseAndRestoreMenu while ($MenuAddress -eq 1800) {
        #Just get root path when initially entering menu
        if ($KeepPage -eq $false) {Check-RootFolderPath}
        #Cycle though menu
        #Changes to what is displayed all occur within the loops
        #Break :KeepFolderData after generating data about a new choice so :RefreshFolderData will resort it
        :RefreshFolderData while ($true) {
                Sort-FolderData
                Format-FolderDirsFiles
            :KeepFolderData while($true) {
                #Display the menu, remember long menus are nested within Split-Menu
                Show-Menu -HeaderLines 3 -IndentHeader $false -FooterLines 2 -IndentFooter $false -FolderMenu $true -RestoreMenu $true -MenuLines $FolderLines
                #################################
                #Exit to snapshot selection menu
                #################################
                if ($MenuChoice -in @("/")) {
                    #Check if items are queued for restore and ask to confirm exit if there are any
                    Confirm-ExitRestore
                    #Exit choices from previous menus
                    if ($MenuChoice -in 1,"/") {
                        $MenuAddress = 1710
                    #Restore queued items
                    } elseif ($MenuChoice -eq 2) {
                        $MenuAddress = 1840
                        $KeepPage = $true
                    #go back to last page if not exiting or restoring
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
                            $MenuAddress = 1810
                            break BrowseAndRestoreMenu
                        }
                        #Quick restore to original location
                        3 {
                            $RestoreFromSingle = $FolderData[1]
                            $RestoreTo = ""
                            $KeepPage = $true
                            Restore-Item
                            pause
                            break BrowseAndRestoreMenu
                        }
                    }
                #####################
                #Restore queued items
                #####################
                } elseif ($MenuChoice -in @("*")) {
                    $KeepPage = $true
                    $MenuAddress = 1840
                    break BrowseAndRestoreMenu
                ####################
                #Choosing a new item
                ####################
                } elseif ($MenuChoice -is [int]) {
                    $MenuChoice = $MenuChoice  -1 #array offset
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
                                $MenuAddress = 1810
                                break BrowseAndRestoreMenu
                            }
                            #Quick restore to original location
                            3 {
                                $RestoreFromSingle = $BrowseChoice
                                $RestoreTo = ""
                                $KeepPage = $true
                                Restore-Item
                                pause
                                break BrowseAndRestoreMenu
                            }
                        }
                    }
                }
            }
        }
        break BrowseAndRestoreMenu
    }

    :RestoreSingleItemDestinationMenu while ($MenuAddress -eq 1810){
        Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 2 -IndentFooter $false -MenuLines @(
            "$(Convert-NixPathToWin($RestoreFromSingle.path)) selected"
            ""
            "Restore to original location"
            "Browse other restore location"
            "Enter restore location manually"
            ""
            "Enter to return to last screen"
        )
        #Set $RestoreTo and move on to next menu
        switch ($MenuChoice) {
            1 {
                $RestoreTo = ""
                $MenuAddress = 1820
                break RestoreSingleItemDestinationMenu
            }
            2 {write-host "Not implemented yet"; pause}
            3 {
                $p = Read-WinPath
                if ($p -ne "") {
                    $RestoreTo = $p
                    $MenuAddress = 1820
                    break RestoreSingleItemDestinationMenu
                } else {
                    break RestoreSingleItemDestinationMenu
                }
            }
        }
        $MenuAddress = 1800
        break RestoreSingleItemDestinationMenu
    }

    :RestoreSingleItemOptionsMenu while ($MenuAddress -eq 1820){
        #Not implemented, skip to next
        $MenuAddress = 1830
        break RestoreSingleItemOptionsMenu
    }

    :ConfirmRestoreSingleItemMenu while ($MenuAddress -eq 1830) {
        #If RestoreTo blank means to original location
        if ($RestoreTo -eq "") {
            Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 0 -IndentFooter $false -MenuLines @(
                "Restore $(Convert-NixPathToWin($RestoreFromSingle.path)) to original location?"
                ""
                "Yes"
                "No"
            )
        #else it's restore to different location
        } else {
            Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 0 -IndentFooter $false -MenuLines @(
                "Restore $(Convert-NixPathToWin($RestoreFromSingle.path)) to $($RestoreTo)?"
                ""
                "Yes"
                "No"
            )
        }
        #Restore item and go back to BrowseAndRestoreMenu
        if ($MenuChoice -eq 1) {
            Restore-Item
            pause
        }
        $MenuAddress = 1800
        break ConfirmRestoreSingleItemMenu
    }

    :RestoreQueueDestinationMenu while ($MenuAddress -eq 1840) {
        if (Check-RestoreFromQueueEmpty) {
            Warn-RestoreFromQueueEmpty
            $MenuAddress = 1800
            break ViewRestoreQueue
        }
        #Check if items have overlapping paths that may overwrite each other and add warning if needed
        [string[]]$m = @()
        $m += "$($script:RestoreFromQueue.count) items selected"
        $l = 2
        if (Check-RestoreFromQueueConflict -eq $true) {
            $m += "WARNING: Some items chosen for restore have overlapping paths.  Continuing may lead to unexpected results."
            $l++
        }
        $m += ""
        $m += "Restore to original location"
        $m += "Browse other restore location"
        $m += "Enter restore location manually"
        $m += "Review queued items"
        $m += "Clear restore queue"
        $m += ""
        $m += "Enter to return to last screen"
        Show-Menu -HeaderLines $l -IndentHeader $false -FooterLines 2 -IndentFooter $false -MenuLines $m

        switch ($MenuChoice) {
            1 {
                $RestoreTo = ""
                $MenuAddress = 1850
                break RestoreQueueDestinationMenu
            }
            2 {
                $MenuAddress = 1850
                break RestoreQueueDestinationMenu
            }
            3 {
                $p = Read-WinPath
                if ($p -ne "") {
                    $RestoreTo = $p
                    $MenuAddress = 1850
                    break RestoreQueueDestinationMenu
                } else {
                    break RestoreQueueDestinationMenu
                }
            }
            4 {
                $MenuAddress = 1870
                break RestoreQueueDestinationMenu
            }
            5 {
                Clear-RestoreFromQueue
                break RestoreQueueDestinationMenu
            }
        }
        $MenuAddress = 1800
        break RestoreQueueDestinationMenu
    }

    :RestoreQueueOptionsMenu while ($MenuAddress -eq 1850) {
        #Not implemented, skip to next
        $MenuAddress = 1860
        break RestoreQueueOptionsMenu
    }

    :ConfirmRestoreQueueMenu while ($MenuAddress -eq 1860) {
        #If RestoreTo blank means to original location
        if ($RestoreTo -eq "") {
            Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 0 -IndentFooter $false -MenuLines @(
                "Restore $($script:RestoreFromQueue.count) items to original location?"
                ""
                "Yes"
                "No"
            )
        #else it's restore to different location
        } else {
            Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 0 -IndentFooter $false -MenuLines @(
                "Restore $($script:RestoreFromQueue.count) items to $($RestoreTo)?"
                ""
                "Yes"
                "No"
            )
        }
        #Restore item and go back to BrowseAndRestoreMenu
        if ($MenuChoice -eq 1) {
            cls
            $items = $RestoreFromQueue.Clone()
            foreach ($item in $items) {
                $RestoreFromSingle = $item
                Restore-Item
                if ($LASTEXITCODE -eq 0) {
                    $RestoreFromQueue.Remove($item)
                }
            }
            if ($RestoreFromQueue.count -eq 0) {
                Write-Host ""
                Write-Host "All items restored successfully!"
            } else {
                Write-Host "$($RestoreFromQueue.count) items failed to restore!"
                Write-Host ""
                foreach ($item in $RestoreFromQueue) {
                    Write-Host $(Convert-NixPathToWin($item.path))
                }
            }
            pause
        }
        $MenuAddress = 1800
        break ConfirmRestoreQueueMenu
    }

    :ViewRestoreQueue while ($MenuAddress -eq 1870) {
        if (Check-RestoreFromQueueEmpty) {
            Warn-RestoreFromQueueEmpty
            $MenuAddress = 1800
            break ViewRestoreQueue
        }
        $KeepPage = $false
        [string[]]$m = @()
        $m += "$($RestoreFromQueue.count) items in restore queue"
        $m += ""
        $RestoreFromQueue | ForEach-Object {$m += $_.path}
        $m += ""
        Show-Menu -HeaderLines 2 -IndentHeader $false -FooterLines 1 -IndentFooter $false -QueueMenu $true -MenuLines $m
        if ($MenuChoice -is [int]) {
            $RestoreFromQueue.Remove($RestoreFromQueue[$MenuChoice - 1])
        } elseif ($MenuChoice -in @("/","")) {
            $MenuAddress = 1840
            break ViewRestoreQueue
        } elseif ($MenuChoice -eq "-") {
            Clear-RestoreFromQueue
            $MenuAddress = 1800
            break ViewRestoreQueue
        }
    }

    ###################################################################################################
    #Backup Tasks
    ###################################################################################################

    :TopBackupTaskMenu while ($MenuAddress -eq 2000) {
        write-host ""
        write-host "Not implemented yet.  Press enter to continue"
        read-host
        $MenuAddress = 0
    }
}