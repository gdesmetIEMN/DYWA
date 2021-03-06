<#
    .SYNOPSIS
        Install a Program using PowerShellGet/PackageManagement Modules OR the Chocolatey CmdLine.

    .DESCRIPTION
        This function was written to make program installation on Windows as easy and generic
        as possible by leveraging existing solutions such as PackageManagement/PowerShellGet
        and the Chocolatey CmdLine.

        Default behavior for this function (using only the -ProgramName parameter) is to try
        installation via PackageManagement/PowerShellGet. If that fails for whatever reason, then
        the Chocolatey CmdLine is used (it will be installed if it isn't already). You can use
        more specific parameters to change this default behavior (i.e. ONLY try installation via
        PowerShellGet/PackageManagement or ONLY try installation via Chocolatey CmdLine).

        If you use the -ResolveCommandPath parameter, this function will attempt to find the Main
        Executable associated with the Program you are installing. If the .exe does NOT have the
        same name as the Program, the function may need additional information provided via the
        -CommandName and/or -ExpectedInstallLocation parameters in order to find the Main Executable.

    .NOTES

    .PARAMETER ProgramName
        This parameter is MANDATORY.

        This paramter takes a string that represents the name of the program that you'd like to install.

    .PARAMETER CommandName
        This parameter is OPTIONAL.

        This parameter takes a string that represents the name of the main executable for the installed
        program. For example, if you are installing 'openssh', the value of this parameter should be 'ssh'.

    .PARAMETER PreRelease
        This parameter is OPTIONAL.

        This parameter is a switch. If used, the latest version of the program in the pre-release branch
        (if one exists) will be installed.

    .PARAMETER GetPreviousVersion
        This parameter is OPTIONAL.

        This parameter is a switch. If used, the version preceding the latest version of the program will
        be installed.

    .PARAMETER UsePowerShellGet
        This parameter is OPTIONAL.

        This parameter is a switch. If used the function will attempt program installation using ONLY
        PackageManagement/PowerShellGet Modules. If installation using those modules fails, the function
        halts and returns the relevant error message(s).

        Installation via the Chocolatey CmdLine will NOT be attempted.

    .PARAMETER ForceChocoInstallScript
        This parameter is OPTIONAL.

        This parameter is a switch. If the program being installed is from the Chocolatey Package Repository,
        using this parameter will force running the program's associated 'chocolateyinstall.ps1' script.
        This switch exists because some Chocolatey packages do NOT run 'chocolateyinstall.ps1' by default,
        meaning that 'Get-Package' could report that a program is 'Installed' when it actually is not.

    .PARAMETER UseChocolateyCmdLine
        This parameter is OPTIONAL.

        This parameter is a switch. If used the function will attempt installation using ONLY
        the Chocolatey CmdLine. (The Chocolatey CmdLine will be installed if it is not already).
        If installation via the Chocolatey CmdLine fails for whatever reason,
        the function halts and returns the relevant error message(s).

    .PARAMETER UpdatePackageManagement
        This parameter is OPTIONAL.

        This parameter is a switch. If used, PowerShellGet/PackageManagement Modules will be updated before
        any install actions take place.

        WARNING: If the Modules are updated, you may need to open a new PowerShell Session before they can be used.

    .PARAMETER ExpectedInstallLocation
        This parameter is OPTIONAL.

        This parameter takes a string that represents the full path to a directory that will contain
        main executable associated with the program to be installed. This directory does NOT have to
        be the immediate parent directory of the .exe.

        If you are absolutely certain you know where the Main Executable for the program to be installed
        will be, then use this parameter to speed things up.

    .PARAMETER ScanCDriveForMainExeIfNecessary
        This parameter is OPTIONAL.

        This parameter is a switch. If used in conjunction with the -CommandName parameter, this function will
        scan the entire C Drive until it finds a .exe that matches the values provided to the -CommandName parameter.

    .PARAMETER ResolveCommandPath
        This parameter is OPTIONAL.

        This parameter is a switch. This switch is meant to be used in situations where you are not certain what the
        name of the Main Executable of the program to be installed will be. This switch will provide an array of
        exe files associated with the program installation in the 'PossibleMainExecutables' property of the function's
        output.

    .PARAMETER Force
        This parameter is OPTIONAL.

        This parameter is a switch. If used, install will be attempted for the specified -ProgramName even if it is
        already installed.

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName kubernetes-cli -CommandName kubectl.exe

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName awscli -CommandName aws.exe -UsePowerShellGet

    .EXAMPLE
        # Open an elevated PowerShell Session, import the module, and -

        PS C:\Users\zeroadmin> Install-Program -ProgramName VisualStudioCode -CommandName Code.exe -UseChocolateyCmdLine

    .EXAMPLE
        # If the Program Name and Main Executable are the same, then this is all you need for the function to find the Main Executable
        
        PS C:\Users\zeroadmin> Install-Program -ProgramName vagrant

#>
function Install-Program {
    [CmdletBinding(DefaultParameterSetName='ChocoCmdLine')]
    Param (
        [Parameter(
            Mandatory=$True,
            Position=0
        )]
        [string]$ProgramName,

        [Parameter(Mandatory=$False)]
        [string]$CommandName,

        [Parameter(Mandatory=$False)]
        [switch]$PreRelease,

        [Parameter(Mandatory=$False)]
        [switch]$GetPreviousVersion,

        [Parameter(
            Mandatory=$False,
            ParameterSetName='PackageManagement'
        )]
        [switch]$UsePowerShellGet,

        [Parameter(
            Mandatory=$False,
            ParameterSetName='PackageManagement'
        )]
        [switch]$ForceChocoInstallScript,

        [Parameter(Mandatory=$False)]
        [switch]$UseChocolateyCmdLine,

        [Parameter(Mandatory=$False)]
        [switch]$UpdatePackageManagement,

        [Parameter(Mandatory=$False)]
        [string]$ExpectedInstallLocation,

        [Parameter(Mandatory=$False)]
        [switch]$ScanCDriveForMainExeIfNecessary,

        [Parameter(Mandatory=$False)]
        [switch]$ResolveCommandPath,

        [Parameter(Mandatory=$False)]
        [switch]$Force
    )

    ##### BEGIN Native Helper Functions #####

    # The below function adds Paths from System PATH that aren't present in $env:Path (this probably shouldn't
    # be an issue, because $env:Path pulls from System PATH...but sometimes profile.ps1 scripts do weird things
    # and also $env:Path wouldn't necessarily be updated within the same PS session where a program is installed...)
    function Synchronize-SystemPathEnvPath {
        $SystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
        
        $SystemPathArray = $SystemPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        $EnvPathArray = $env:Path -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        
        # => means that $EnvPathArray HAS the paths but $SystemPathArray DOES NOT
        # <= means that $SystemPathArray HAS the paths but $EnvPathArray DOES NOT
        $PathComparison = Compare-Object $SystemPathArray $EnvPathArray
        [System.Collections.ArrayList][Array]$SystemPathsThatWeWantToAddToEnvPath = $($PathComparison | Where-Object {$_.SideIndicator -eq "<="}).InputObject

        if ($SystemPathsThatWeWantToAddToEnvPath.Count -gt 0) {
            foreach ($NewPath in $SystemPathsThatWeWantToAddToEnvPath) {
                if ($env:Path[-1] -eq ";") {
                    $env:Path = "$env:Path$NewPath"
                }
                else {
                    $env:Path = "$env:Path;$NewPath"
                }
            }
        }
    }

    # Outputs [System.Collections.ArrayList]$ExePath
    function Adjudicate-ExePath {
        [CmdletBinding()]
        Param (
            [Parameter(Mandatory=$True)]
            [string]$ProgramName,

            [Parameter(Mandatory=$True)]
            [string]$OriginalSystemPath,

            [Parameter(Mandatory=$True)]
            [string]$OriginalEnvPath,

            [Parameter(Mandatory=$True)]
            [string]$FinalCommandName,

            [Parameter(Mandatory=$False)]
            [string]$ExpectedInstallLocation
        )

        # ...search for it in the $ExpectedInstallLocation if that parameter is provided by the user...
        if ($ExpectedInstallLocation) {
            if (Test-Path $ExpectedInstallLocation) {
                [System.Collections.ArrayList][Array]$ExePath = $(Get-ChildItem -Path $ExpectedInstallLocation -File -Recurse -Filter "*$FinalCommandName.exe").FullName
            }
        }
        # If we don't have $ExpectedInstallLocation provided...
        if (!$ExpectedInstallLocation) {
            # ...then we can compare $OriginalSystemPath to the current System PATH to potentially
            # figure out which directories *might* contain the main executable.
            $OriginalSystemPathArray = $OriginalSystemPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
            $OriginalEnvPathArray = $OriginalEnvPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}

            $CurrentSystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
            $CurrentSystemPathArray = $CurrentSystemPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
            $CurrentEnvPath = $env:Path
            $CurrentEnvPathArray = $CurrentEnvPath -split ";" | foreach {if (-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
            

            $OriginalVsCurrentSystemPathComparison = Compare-Object $OriginalSystemPathArray $CurrentSystemPathArray
            $OriginalVsCurrentEnvPathComparison = Compare-Object $OriginalEnvPathArray $CurrentEnvPathArray

            [System.Collections.ArrayList]$DirectoriesToSearch = @()
            if ($OriginalVsCurrentSystemPathComparison -ne $null) {
                # => means that $CurrentSystemPathArray has some new directories
                [System.Collections.ArrayList][Array]$NewSystemPathDirs = $($OriginalVsCurrentSystemPathComparison | Where-Object {$_.SideIndicator -eq "=>"}).InputObject
            
                if ($NewSystemPathDirs.Count -gt 0) {
                    foreach ($dir in $NewSystemPathDirs) {
                        $null = $DirectoriesToSearch.Add($dir)
                    }
                }
            }
            if ($OriginalVsCurrentEnvPathComparison -ne $null) {
                # => means that $CurrentEnvPathArray has some new directories
                [System.Collections.ArrayList][Array]$NewEnvPathDirs = $($OriginalVsCurrentEnvPathComparison | Where-Object {$_.SideIndicator -eq "=>"}).InputObject
            
                if ($NewEnvPathDirs.Count -gt 0) {
                    foreach ($dir in $NewEnvPathDirs) {
                        $null = $DirectoriesToSearch.Add($dir)
                    }
                }
            }

            if ($DirectoriesToSearch.Count -gt 0) {
                $DirectoriesToSearchFinal = $($DirectoriesToSearch | Sort-Object | Get-Unique) | foreach {if (Test-Path $_ -ErrorAction SilentlyContinue) {$_}}
                $DirectoriesToSearchFinal = $DirectoriesToSearchFinal | Where-Object {$_ -match "$ProgramName"}

                [System.Collections.ArrayList]$ExePath = @()
                foreach ($dir in $DirectoriesToSearchFinal) {
                    [Array]$ExeFiles = $(Get-ChildItem -Path $dir -File -Filter "*$FinalCommandName.exe").FullName
                    if ($ExeFiles.Count -gt 0) {
                        $null = $ExePath.Add($ExeFiles)
                    }
                }

                # If there IS a difference in original vs current System PATH / $Env:Path, but we 
                # still DO NOT find the main executable in those diff directories (i.e. $ExePath is still not set),
                # it's possible that the name of the main executable that we're looking for is actually
                # incorrect...in which case just tell the user that we can't find the expected main
                # executable name and provide a list of other .exe files that we found in the diff dirs.
                if (!$ExePath -or $ExePath.Count -eq 0) {
                    [System.Collections.ArrayList]$ExePath = @()
                    foreach ($dir in $DirectoriesToSearchFinal) {
                        [Array]$ExeFiles = $(Get-ChildItem -Path $dir -File -Filter "*.exe").FullName
                        foreach ($File in $ExeFiles) {
                            $null = $ExePath.Add($File)
                        }
                    }
                }
            }
        }

        $ExePath | Sort-Object | Get-Unique
    }

    ##### END Native Helper Functions #####

    ##### BEGIN Variable/Parameter Transforms and PreRun Prep #####

    # Invoke-WebRequest fix...
    [Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls"

    Push-Location

    if (!$(GetElevation)) {
        Write-Error "The $($MyInvocation.MyCommand.Name) function must be ran from an elevated PowerShell Session (i.e. 'Run as Administrator')! Halting!"
        $global:FunctionResult = "1"
        return
    }

    Write-Host "Please wait..."
    $global:FunctionResult = "0"
    $MyFunctionsUrl = "https://raw.githubusercontent.com/pldmgg/misc-powershell/master/MyFunctions"

    if ($UpdatePackageManagement) {
        if (![bool]$(Get-Command Update-PackageManagement -ErrorAction SilentlyContinue)) {
            $UpdatePMFunctionUrl = "$MyFunctionsUrl/PowerShellCore_Compatible/Update-PackageManagement.ps1"
            try {
                Invoke-Expression $([System.Net.WebClient]::new().DownloadString($UpdatePMFunctionUrl))
            }
            catch {
                Write-Error $_
                Write-Error "Unable to load the Update-PackageManagement function! Halting!"
                $global:FunctionResult = "1"
                return
            }
        }

        try {
            $global:FunctionResult = "0"
            $null = Update-PackageManagement -AddChocolateyPackageProvider -ErrorAction SilentlyContinue -ErrorVariable UPMErr
            if ($UPMErr -and $global:FunctionResult -eq "1") {throw "The Update-PackageManagement function failed! Halting!"}
        }
        catch {
            Write-Error $_
            Write-Host "Errors from the Update-PackageManagement function are as follows:"
            Write-Error $($UPMErr | Out-String)
            $global:FunctionResult = "1"
            return
        }
    }

    try {
        if ($PSVersionTable.PSEdition -ne "Core") {
            $null = Install-PackageProvider -Name Nuget -Force -Confirm:$False
            $null = Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            $null = Install-PackageProvider -Name Chocolatey -Force -Confirm:$False
            $null = Set-PackageSource -Name chocolatey -Trusted -Force
        }
        else {
            $null = Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    # Install chocolatey resources for PowerShellGet
    if ($PSVersionTable.PSEdition -ne "Core") {
        try {
            $ChocoResourcePackageNames = @("chocolatey-core.extension","chocolatey-windowsupdate.extension")
            foreach ($ChocoResourcePackageName in $ChocoResourcePackageNames) {
                $null = Install-Package $ChocoResourcePackageName -ProviderName Chocolatey -Force -ErrorAction Stop
            }
        }
        catch {
            Write-Warning "Unable to install PowerShellGet package $ChocoResourcePackageName ..."
        }
    }

    if ($UseChocolateyCmdLine -or $(!$UsePowerShellGet -and !$UseChocolateyCmdLine)) {
        #$null = Uninstall-Package chocolatey -ErrorAction SilentlyContinue

        if (![bool]$(Get-Command Install-ChocolateyCmdLine -ErrorAction SilentlyContinue)) {
            $InstallCCFunctionUrl = "$MyFunctionsUrl/Install-ChocolateyCmdLine.ps1"
            try {
                Invoke-Expression $([System.Net.WebClient]::new().DownloadString($InstallCCFunctionUrl))
            }
            catch {
                Write-Error $_
                Write-Error "Unable to load the Install-ChocolateyCmdLine function! Halting!"
                $global:FunctionResult = "1"
                return
            }
        }
    }

    if (![bool]$(Get-Command Update-ChocolateyEnv -ErrorAction SilentlyContinue)) {
        $RefreshCEFunctionUrl = "$MyFunctionsUrl/PowerShellCore_Compatible/Update-ChocolateyEnv.ps1"
        try {
            Invoke-Expression $([System.Net.WebClient]::new().DownloadString($RefreshCEFunctionUrl))
        }
        catch {
            Write-Error $_
            Write-Error "Unable to load the Update-ChocolateyEnv function! Halting!"
            $global:FunctionResult = "1"
            return
        }
    }

    # Get-AllPackageInfo
    try {
        #$null = clist --local-only
        $PackageManagerInstallObjects = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue
        [array]$ChocolateyInstalledProgramObjects = $PackageManagerInstallObjects.ChocolateyInstalledProgramObjects
        [array]$PSGetInstalledPackageObjects = $PackageManagerInstallObjects.PSGetInstalledPackageObjects
        [array]$RegistryProperties = $PackageManagerInstallObjects.RegistryProperties
    }
    catch {
        Write-Error $_
        $global:FunctionResult = "1"
        return
    }

    $AllPackageManagementVersions = Find-Package -Name $ProgramName -Source chocolatey -AllVersions -EA SilentlyContinue
    if ([bool]$AllPackageManagementVersions) {
        $PackageManagementLatestVersion = $($AllPackageManagementVersions | Sort-Object -Property Version -EA SilentlyContinue)[-1]
        $PackageManagementPreviousVersion = $($AllPackageManagementVersions | Sort-Object -Property Version -EA SilentlyContinue)[-2]
    }
    if ([bool]$(Get-Command choco -EA SilentlyContinue)) {
        $AllChocoVersions = choco list $ProgramName -e --all
        if ([bool]$AllChocoVersions) {
            $ChocoLatestVersion = $($AllChocoVersions[1] -split "[\s]")[1].Trim()
            $ChocoPreviousVersion = $($AllChocoVersions[2] -split "[\s]")[1].Trim()
        }
    }

    if ($PSGetInstalledPackageObjects.Count -gt 0) {
        if ($PSGetInstalledPackageObjects.Count -eq 1) {
            $PackageManagementCurrentInstalledPackage = $PSGetInstalledPackageObjects
            $PackageManagementLatestVersion = $(Find-Package -Name $PSGetInstalledPackageObjects.Name -Source chocolatey -AllVersions | Sort-Object -Property Version)[-1]
            $PackageManagementPreviousVersion = $(Find-Package -Name $PSGetInstalledPackageObjects.Name -Source chocolatey -AllVersions | Sort-Object -Property Version)[-2]
        }
        if ($PSGetInstalledPackageObjects.Count -gt 1) {
            $ExactMatchCheck = $PSGetInstalledPackageObjects | Where-Object {$_.Name -eq $ProgramName}
            if (!$ExactMatchCheck) {
                Write-Warning "The following Programs are currently installed and match the string '$ProgramName':"
                for ($i=0; $i -lt $PSGetInstalledPackageObjects.Count; $i++) {
                    Write-Host "$i) $($PSGetInstalledPackageObjects[$i].Name)"
                }
                $ValidChoiceNumbers = 0..$($PSGetInstalledPackageObjects.Count-1)
                $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
                while ($ValidChoiceNumbers -notcontains $ProgramChoiceNumber) {
                    Write-Warning "'$ProgramChoiceNumber' is not a valid option. Please choose: $($ValidChoicenumbers -join ", ")"
                    $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
                }

                $ProgramName = $PSGetInstalledPackageObjects[$ProgramChoiceNumber].Name
                $PackageManagementLatestVersion = $(Find-Package -Name $UpdatedProgramName -Source chocolatey -AllVersions | Sort-Object -Property Version)[-1]
            }
            else {
                $PackageManagementLatestVersion = $(Find-Package -Name $ProgramName -Source chocolatey -AllVersions | Sort-Object -Property Version)[-1]
            }
        }
    }
    if ($ChocolateyInstalledProgramObjects.Count -gt 0) {
        if ($ChocolateyInstalledProgramObjects.Count -gt 1) {
            $ExactMatchCheck = $ChocolateyInstalledProgramObjects | Where-Object {$_.ProgramName -eq $ProgramName}
            if (!$ExactMatchCheck) {
                Write-Warning "The following Programs are currently installed and match the string '$ProgramName':"
                for ($i=0; $i -lt $ChocolateyInstalledProgramObjects.Count; $i++) {
                    Write-Host "$i) $($ChocolateyInstalledProgramObjects[$i].ProgramName)"
                }
                $ValidChoiceNumbers = 0..$($ChocolateyInstalledProgramObjects.Count-1)
                $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
                while ($ValidChoiceNumbers -notcontains $ProgramChoiceNumber) {
                    Write-Warning "'$ProgramChoiceNumber' is not a valid option. Please choose: $($ValidChoicenumbers -join ", ")"
                    $ProgramChoiceNumber = Read-Host -Prompt " Please choose the number that corresponds to the Program you would like to update:"
                }

                $ProgramName = $ChocolateyInstalledProgramObjects[$ProgramChoiceNumber].ProgramName
            }
        }

        # Also get a list of outdated packages in case this Install-Program function is used to update a package
        $ChocolateyOutdatedProgramsPrep = choco outdated
        $UpperLineMatch = $ChocolateyOutdatedProgramsPrep -match "Output is package name"
        $LowerLineMatch = $ChocolateyOutdatedProgramsPrep -match "Chocolatey has determined"
        $UpperIndex = $ChocolateyOutdatedProgramsPrep.IndexOf($UpperLineMatch) + 2
        $LowerIndex = $ChocolateyOutdatedProgramsPrep.IndexOf($LowerLineMatch) - 2
        $ChocolateyOutdatedPrograms = $ChocolateyOutdatedProgramsPrep[$UpperIndex..$LowerIndex]

        [System.Collections.ArrayList]$ChocolateyOutdatedProgramsPSObjects = @()
        foreach ($line in $ChocolateyOutdatedPrograms) {
            $ParsedLine = $line -split "\|"
            $Program = $ParsedLine[0]
            $CurrentInstalledVersion = $ParsedLine[1]
            $LatestAvailableVersion = $ParsedLine[2]

            $PSObject = [pscustomobject]@{
                ProgramName                 = $Program
                CurrentInstalledVersion     = $CurrentInstalledVersion
                LatestAvailableVersion      = $LatestAvailableVersion
            }

            $null = $ChocolateyOutdatedProgramsPSObjects.Add($PSObject)
        }

        # Get all available Chocolatey Versions
        $AllChocoVersions = choco list $ProgramName -e --all

        # Get the latest version of $ProgramName from chocolatey
        $ChocoLatestVersion = $($AllChocoVersions[1] -split "[\s]")[1].Trim()

        # Also get the previous version of $ProgramName in case we want the previous version
        $ChocoPreviousVersion = $($AllChocoVersions[2] -split "[\s]")[1].Trim()
    }

    if ($CommandName -match "\.exe") {
        $CommandName = $CommandName -replace "\.exe",""
    }
    $FinalCommandName = if ($CommandName) {$CommandName} else {$ProgramName}

    # Save the original System PATH and $env:Path before we do anything, just in case
    $OriginalSystemPath = $(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path
    $OriginalEnvPath = $env:Path
    Synchronize-SystemPathEnvPath
    $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue

    ##### END Variable/Parameter Transforms and PreRun Prep #####


    ##### BEGIN Main Body #####

    $CheckLatestVersion = $(
        $PackageManagementCurrentInstalledPackage.Version -ne $PackageManagementLatestVersion.Version -or
        $ChocolateyOutdatedProgramsPSObjects.ProgramName -contains $ProgramName
    )
    $CheckPreviousVersion = $(
        $PackageManagementCurrentInstalledPackage.Version -ne $PackageManagementPreviousVersion.Version -or
        $ChocoPreviousVersion -ne $ChocolateyInstalledProgramObjects.Version
    )
    if ($GetPreviousVersion) {
        $VersionCheck = $CheckPreviousVersion
        $PackageManagementRequiredVersion = $PackageManagementPreviousVersion.Version
        $ChocoRequiredVersion = $ChocoLatestVersion
    }
    else {
        $VersionCheck = $CheckLatestVersion
        $PackageManagementRequiredVersion = $PackageManagementLatestVersion.Version
        $ChocoRequiredVersion = $ChocoPreviousVersion
    }

    # Install $ProgramName if it's not already or if it's outdated...
    if ($($PSGetInstalledPackageObjects.Name -notcontains $ProgramName -and
    $ChocolateyInstalledProgramsPSObjects.ProgramName -notcontains $ProgramName) -or
    $VersionCheck -or $Force
    ) {
        if ($UsePowerShellGet -or $(!$UsePowerShellGet -and !$UseChocolateyCmdLine) -or 
        $PSGetInstalledPackageObjects.Name -contains $ProgramName -and $ChocolateyInstalledProgramsPSObjects.ProgramName -notcontains $ProgramName
        ) {
            $PreInstallPackagesList = $(Get-Package).Name

            $InstallPackageSplatParams = @{
                Name            = $ProgramName
                Force           = $True
                ErrorAction     = "SilentlyContinue"
                ErrorVariable   = "InstallError"
                WarningAction   = "SilentlyContinue"
            }
            if ([bool]$PackageManagementRequiredVersion) {
                $InstallPackageSplatParams.Add("RequiredVersion",$PackageManagementRequiredVersion)
            }
            if ($PreRelease) {
                try {
                    $LatestVersion = $(Find-Package $ProgramName -AllVersions -ErrorAction Stop)[-1].Version
                    $InstallPackageSplatParams.Add("MinimumVersion",$LatestVersion)
                }
                catch {
                    Write-Verbose "Unable to find latest PreRelease version...Proceeding with 'Install-Package' without the '-MinimumVersion' parameter..."
                }
            }
            # NOTE: The PackageManagement install of $ProgramName is unreliable, so just in case, fallback to the Chocolatey cmdline for install
            $null = Install-Package @InstallPackageSplatParams
            if ($InstallError.Count -gt 0 -or $($(Get-Package).Name -match $ProgramName).Count -eq 0) {
                if ($($(Get-Package).Name -match $ProgramName).Count -gt 0) {
                    $null = Uninstall-Package $ProgramName -Force -ErrorAction SilentlyContinue
                }
                Write-Warning "There was a problem installing $ProgramName via PackageManagement/PowerShellGet!"
                
                if ($UsePowerShellGet) {
                    Write-Error "One or more errors occurred during the installation of $ProgramName via the the PackageManagement/PowerShellGet Modules failed! Installation has been rolled back! Halting!"
                    Write-Host "Errors for the Install-Package cmdlet are as follows:"
                    Write-Error $($InstallError | Out-String)
                    $global:FunctionResult = "1"
                    return
                }
                else {
                    Write-Host "Trying install via Chocolatey CmdLine..."
                    $PMInstall = $False
                }
            }
            else {
                $PMInstall = $True

                # Since Installation via PackageManagement/PowerShellGet was succesful, let's update $env:Path with the
                # latest from System PATH before we go nuts trying to find the main executable manually
                Synchronize-SystemPathEnvPath
                $env:Path = $($(Update-ChocolateyEnv -ErrorAction SilentlyContinue) -split ";" | foreach {
                    if (-not [System.String]::IsNullOrWhiteSpace($_) -and $(Test-Path $_ -ErrorAction SilentlyContinue)) {$_}
                }) -join ";"
            }
        }

        if (!$PMInstall -or $UseChocolateyCmdLine -or
        $ChocolateyInstalledProgramsPSObjects.ProgramName -contains $ProgramName
        ) {
            try {
                Write-Host "Refreshing `$env:Path..."
                $global:FunctionResult = "0"
                $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue -ErrorVariable RCEErr

                # The first time we attempt to Update-ChocolateyEnv, Chocolatey CmdLine and/or the
                # Chocolatey Package Provider legitimately might not be installed,
                # so if the Update-ChocolateyEnv function throws that error, we can ignore it
                if ($RCEErr.Count -gt 0 -and
                $global:FunctionResult -eq "1" -and
                ![bool]$($RCEErr -match "Neither the Chocolatey PackageProvider nor the Chocolatey CmdLine appears to be installed!")) {
                    throw "The Update-ChocolateyEnv function failed! Halting!"
                }
            }
            catch {
                Write-Error $_
                Write-Host "Errors from the Update-ChocolateyEnv function are as follows:"
                Write-Error $($RCEErr | Out-String)
                $global:FunctionResult = "1"
                return
            }

            # Make sure Chocolatey CmdLine is installed...if not, install it
            if (![bool]$(Get-Command choco -ErrorAction SilentlyContinue)) {
                #$null = Uninstall-Package chocolatey -ErrorAction SilentlyContinue

                try {
                    $global:FunctionResult = "0"
                    $null = Install-ChocolateyCmdLine -ErrorAction SilentlyContinue -ErrorVariable ICCErr -WarningAction SilentlyContinue
                    if ($ICCErr -and $global:FunctionResult -eq "1") {throw "The Install-ChocolateyCmdLine function failed! Halting!"}
                }
                catch {
                    Write-Error $_
                    Write-Host "Errors from the Install-ChocolateyCmdline function are as follows:"
                    Write-Error $($ICCErr | Out-String)
                    $global:FunctionResult = "1"
                    return
                }
            }

            # Make sure you can reach the Chocolatey Repo
            if ($(Invoke-WebRequest -Uri 'http://chocolatey.org/api/v2/').StatusCode -ne 200) {
                Write-Error "Unable to reach the Chocolatey Package Repo at 'http://chocolatey.org/api/v2/'! Halting!"
                $global:FunctionResult = "1"
                return
            }

            # Import all of the Chocolatey helper Modules
            $ChocolateyResourceDirectories = Get-ChildItem -Path "$env:ProgramData\chocolatey\lib" -Directory | Where-Object {$_.BaseName -match "chocolatey"}
            $ModulesToImport = foreach ($ChocoResourceDir in $ChocolateyResourceDirectories) {
                $(Get-ChildItem -Path $ChocoResourceDir.FullName -Recurse -Filter "*.psm1").FullName
            }
            foreach ($ChocoModulePath in $($ModulesToImport | Where-Object {$_})) {
                Import-Module $ChocoModulePath -Global
            }

            # Since choco installs can hang indefinitely, we're starting another powershell process and giving it a time limit
            try {
                if ($PreRelease) {
                    $CupArgs = "--pre -y"
                }
                elseif ([bool]$ChocoRequiredVersion) {
                    $CupArgs = "--version=$ChocoRequiredVersion -y"
                }
                else {
                    $CupArgs = "-y"
                }
                $ChocoPrepScript = @(
                    "`$ChocolateyResourceDirectories = Get-ChildItem -Path '$env:ProgramData\chocolatey\lib' -Directory | Where-Object {`$_.BaseName -match 'chocolatey'}"
                    '$ModulesToImport = foreach ($ChocoResourceDir in $ChocolateyResourceDirectories) {'
                    "    `$(Get-ChildItem -Path `$ChocoResourceDir.FullName -Recurse -Filter '*.psm1').FullName"
                    '}'
                    'foreach ($ChocoModulePath in $($ModulesToImport | Where-Object {$_})) {'
                    '    Import-Module $ChocoModulePath -Global'
                    '}'
                    "cup $ProgramName $CupArgs"
                )
                $ChocoPrepScript = $ChocoPrepScript -join "`n"
                $FinalArguments = "-NoProfile -NoLogo -Command `"$ChocoPrepScript`""
                
                $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                #$ProcessInfo.WorkingDirectory = $BinaryPath | Split-Path -Parent
                $ProcessInfo.FileName = $(Get-Command powershell).Source
                $ProcessInfo.RedirectStandardError = $true
                $ProcessInfo.RedirectStandardOutput = $true
                $ProcessInfo.UseShellExecute = $false
                $ProcessInfo.Arguments = $FinalArguments
                $Process = New-Object System.Diagnostics.Process
                $Process.StartInfo = $ProcessInfo
                $Process.Start() | Out-Null
                # Below $FinishedInAlottedTime returns boolean true/false
                # Give it 60 seconds to finish installing, otherwise, kill choco.exe
                $FinishedInAlottedTime = $Process.WaitForExit(60000)
                if (!$FinishedInAlottedTime) {
                    $Process.Kill()
                }
                $stdout = $Process.StandardOutput.ReadToEnd()
                $stderr = $Process.StandardError.ReadToEnd()
                $AllOutputA = $stdout + $stderr

                #$AllOutput | Export-CliXml "$HOME\CupInstallOutput.ps1"
                
                if (![bool]$($(clist --local-only $ProgramName) -match $ProgramName)) {
                    if ($AllOutput -match "prerelease" -and $Arguments -notmatch '--pre') {
                        $CupArgs = "--pre -y"
                        $ChocoPrepScript = @(
                            "`$ChocolateyResourceDirectories = Get-ChildItem -Path '$env:ProgramData\chocolatey\lib' -Directory | Where-Object {`$_.BaseName -match 'chocolatey'}"
                            '$ModulesToImport = foreach ($ChocoResourceDir in $ChocolateyResourceDirectories) {'
                            "    `$(Get-ChildItem -Path `$ChocoResourceDir.FullName -Recurse -Filter '*.psm1').FullName"
                            '}'
                            'foreach ($ChocoModulePath in $($ModulesToImport | Where-Object {$_})) {'
                            '    Import-Module $ChocoModulePath -Global'
                            '}'
                            "cup $ProgramName $CupArgs"
                        )
                        $ChocoPrepScript = $ChocoPrepScript -join "`n"
                        $FinalArguments = "-NoProfile -NoLogo -Command `"$ChocoPrepScript`""

                        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
                        #$ProcessInfo.WorkingDirectory = $BinaryPath | Split-Path -Parent
                        $ProcessInfo.FileName = $(Get-Command powershell).Source
                        $ProcessInfo.RedirectStandardError = $true
                        $ProcessInfo.RedirectStandardOutput = $true
                        $ProcessInfo.UseShellExecute = $false
                        $ProcessInfo.Arguments = $FinalArguments
                        $Process = New-Object System.Diagnostics.Process
                        $Process.StartInfo = $ProcessInfo
                        $Process.Start() | Out-Null
                        # Below $FinishedInAlottedTime returns boolean true/false
                        # Give it 60 seconds to finish installing, otherwise, kill choco.exe
                        $FinishedInAlottedTime = $Process.WaitForExit(60000)
                        if (!$FinishedInAlottedTime) {
                            $Process.Kill()
                        }
                        $stdout = $Process.StandardOutput.ReadToEnd()
                        $stderr = $Process.StandardError.ReadToEnd()
                        $AllOutputB = $stdout + $stderr
                    }
                }
                
                if (![bool]$($(clist --local-only $ProgramName) -match $ProgramName)) {
                    throw "'cup $ProgramName $CupArgs' failed with the following Output:`n$AllOutputA`n$AllOutputB"
                }

                $ChocoInstall = $true

                # Since Installation via the Chocolatey CmdLine was succesful, let's update $env:Path with the
                # latest from System PATH before we go nuts trying to find the main executable manually
                Synchronize-SystemPathEnvPath
                $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning $_.Exception.Message

                Write-Host "Trying 'cup $ProgramName $CupArgs' within this powershell process ($PID)..." -ForegroundColor Yellow

                cup $ProgramName -y

                if (![bool]$($(clist --local-only $ProgramName) -match $ProgramName)) {
                    Write-Error "'cup $ProgramName -y' failed! Halting!"
                    Write-Warning "Please update Chocolatey via:`n    cup chocolatey -y"
                    $global:FunctionResult = "1"
                    return
                }
            }
        }

        if ($ResolveCommandPath -or $PSBoundParameters['CommandName']) {
            ## BEGIN Try to Find Main Executable Post Install ##

            # Now the parent directory of $ProgramName's main executable should be part of the SYSTEM Path
            # (and therefore part of $env:Path). If not, try to find it in Chocolatey directories...
            if ($(Get-Command $FinalCommandName -ErrorAction SilentlyContinue).CommandType -eq "Alias") {
                while (Test-Path Alias:\$FinalCommandName -ErrorAction SilentlyContinue) {
                    Remove-Item Alias:\$FinalCommandName
                }
            }

            if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)) {
                try {
                    Write-Host "Refreshing `$env:Path..."
                    $global:FunctionResult = "0"
                    $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue -ErrorVariable RCEErr
                    if ($RCEErr.Count -gt 0 -and $global:FunctionResult -eq "1") {throw "The Update-ChocolateyEnv function failed! Halting!"}
                }
                catch {
                    Write-Error $_
                    Write-Host "Errors from the Update-ChocolateyEnv function are as follows:"
                    Write-Error $($RCEErr | Out-String)
                    $global:FunctionResult = "1"
                    return
                }
            }
            
            # If we still can't find the main executable...
            if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue) -and $(!$ExePath -or $ExePath.Count -eq 0)) {
                $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue
                
                if ($ExpectedInstallLocation) {
                    if (Test-Path $ExpectedInstallLocation -ErrorAction SilentlyContinue) {
                        [System.Collections.ArrayList][Array]$ExePath = Adjudicate-ExePath -ProgramName $ProgramName -OriginalSystemPath $OriginalSystemPath -OriginalEnvPath $OriginalEnvPath -FinalCommandName $FinalCommandName -ExpectedInstallLocation $ExpectedInstallLocation
                    }
                }
                else {
                    [System.Collections.ArrayList][Array]$ExePath = Adjudicate-ExePath -ProgramName $ProgramName -OriginalSystemPath $OriginalSystemPath -OriginalEnvPath $OriginalEnvPath -FinalCommandName $FinalCommandName
                }
            }

            # Determine if there's an exact match for the $FinalCommandName
            if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)) {
                if ($ExePath.Count -ge 1) {
                    if ([bool]$($ExePath -match "\\$FinalCommandName.exe$")) {
                        $FoundExactCommandMatch = $True
                    }
                }
            }

            # If we STILL can't find the main executable...
            if ($(![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue) -and $(!$ExePath -or $ExePath.Count -eq 0)) -or 
            $(![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue) -and !$FoundExactCommandMatch -and $PSBoundParameters['CommandName']) -or
            $($ResolveCommandPath -and !$FoundExactCommandMatch) -or $ForceChocoInstallScript) {
                # If, at this point we don't have $ExePath, if we did a $ChocoInstall, then we have to give up...
                # ...but if we did a $PMInstall, then it's possible that PackageManagement/PowerShellGet just
                # didn't run the chocolateyInstall.ps1 script that sometimes comes bundled with Packages from the
                # Chocolatey Package Provider/Repo. So try running that...
                if ($ChocoInstall) {
                    if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)) {
                        #Write-Warning "Unable to find main executable for $ProgramName!"
                        $MainExeSearchFail = $True
                    }
                }
                if ($PMInstall -or $ForceChocoInstallScript) {
                    [System.Collections.ArrayList]$PossibleChocolateyInstallScripts = @()
                    
                    if (Test-Path "C:\Chocolatey" -ErrorAction SilentlyContinue) {
                        $ChocoScriptsA = Get-ChildItem -Path "C:\Chocolatey" -Recurse -File -Filter "*chocolateyinstall.ps1" | Where-Object {$($(Get-Date) - $_.CreationTime).TotalMinutes -lt 5}
                        foreach ($Script in $ChocoScriptsA) {
                            $null = $PossibleChocolateyInstallScripts.Add($Script)
                        }
                    }
                    if (Test-Path "C:\ProgramData\chocolatey" -ErrorAction SilentlyContinue) {
                        $ChocoScriptsB = Get-ChildItem -Path "C:\ProgramData\chocolatey" -Recurse -File -Filter "*chocolateyinstall.ps1" | Where-Object {$($(Get-Date) - $_.CreationTime).TotalMinutes -lt 5}
                        foreach ($Script in $ChocoScriptsB) {
                            $null = $PossibleChocolateyInstallScripts.Add($Script)
                        }
                    }

                    [System.Collections.ArrayList][Array]$ChocolateyInstallScriptSearch = $PossibleChocolateyInstallScripts.FullName | Where-Object {$_ -match ".*?$ProgramName.*?chocolateyinstall.ps1$"}
                    if ($ChocolateyInstallScriptSearch.Count -eq 0) {
                        Write-Warning "Unable to find main the Chocolatey Install Script for $ProgramName PowerShellGet install!"
                        $MainExeSearchFail = $True
                    }
                    if ($ChocolateyInstallScriptSearch.Count -eq 1) {
                        $ChocolateyInstallScript = $ChocolateyInstallScriptSearch[0]
                    }
                    if ($ChocolateyInstallScriptSearch.Count -gt 1) {
                        $ChocolateyInstallScript = $($ChocolateyInstallScriptSearch | Sort-Object LastWriteTime)[-1]
                    }
                    
                    if ($ChocolateyInstallScript) {
                        try {
                            Write-Host "Trying the Chocolatey Install script from $ChocolateyInstallScript..." -ForegroundColor Yellow

                            # Make sure Chocolatey Modules / helper scripts are loaded
                            if (Test-Path "C:\ProgramData\chocolatey" -ErrorAction SilentlyContinue) {
                                $ChocoPath = "C:\ProgramData\chocolatey"
                            }
                            elseif (Test-Path "C:\Chocolatey" -ErrorAction SilentlyContinue) {
                                $ChocoPath = "C:\Chocolatey"
                            }
                            else {
                                if ($ExpectedInstallLocation) {
                                    if (Test-Path $ExpectedInstallLocation -ErrorAction SilentlyContinue) {
                                        [System.Collections.ArrayList][Array]$ExePath = Adjudicate-ExePath -ProgramName $ProgramName -OriginalSystemPath $OriginalSystemPath -OriginalEnvPath $OriginalEnvPath -FinalCommandName $FinalCommandName -ExpectedInstallLocation $ExpectedInstallLocation
                                    }
                                }
                                else {
                                    [System.Collections.ArrayList][Array]$ExePath = Adjudicate-ExePath -ProgramName $ProgramName -OriginalSystemPath $OriginalSystemPath -OriginalEnvPath $OriginalEnvPath -FinalCommandName $FinalCommandName
                                }
    
                                # If we STILL don't have $ExePath, try this...
                                if (!$ExePath -or $ExePath.Count -eq 0) {
                                    $ProgramSourceParentDir = $(Get-Package $ProgramName).Source | Split-Path -Parent
                                    if (![System.String]::IsNullOrWhiteSpace($ProgramSourceParentDir)) {
                                        $ExePath = $(Get-ChildItem -Path $ProgramSourceParentDir -Recurse -File | Where-Object {$_.Name -like "*$ProgramName*exe"}).FullName
                                    }
                                }
    
                                # If we STILL don't have $ExePath, we need to give up...
                                if (!$ExePath -or $ExePath.Count -eq 0) {
                                    #Write-Warning "Unable to find main executable for $ProgramName!"
                                    $MainExeSearchFail = $True
                                }

                                throw "Unable to find `$ChocoPath!"
                            }
                            
                            $ChocoInstallerModuleFileItem = Get-ChildItem -Path $ChocoPath -Recurse -File | Where-Object {$_.FullName -match "chocolateyinstaller\.psm1"}
                            $ChocoProfileModuleFileItem = Get-ChildItem -Path $ChocoPath -Recurse -File | Where-Object {$_.FullName -match "chocolateyProfile\.psm1"}
                            $ChocoScriptRunnerFileItem = Get-ChildItem -Path $ChocoPath -Recurse -File | Where-Object {$_.FullName -match "chocolateyScriptRunner\.ps1"}
                            $ChocoTabExpansionFileItem = Get-ChildItem -Path $ChocoPath -Recurse -File | Where-Object {$_.FullName -match "chocolateyTabExpansion\.ps1"}
                            
                            if (!$ChocoInstallerModuleFileItem -or !$ChocoProfileModuleFileItem) {
                                $ChocoResourcesPath = "$ChocoPath\lib\chocolatey.resources"
                                $null = New-Item -ItemType Directory -Path $ChocoResourcesPath -Force
                                $ChocoMasterSrcZipUri = "https://github.com/chocolatey/choco/archive/master.zip"
                                $ChocoMasterOutFile = "$HOME\Downloads\ChocoMaster.zip"
                                Invoke-WebRequest -Uri $ChocoMasterSrcZipUri -OutFile $ChocoMasterOutFile
                                UnzipFile -PathToZip $ChocoMasterOutFile -TargetDir $ChocoResourcesPath -SpecificItem 'chocolatey\.resources\\helpers$'

                                $ChocoInstallerModuleFileItem = Get-ChildItem -Path $ChocoResourcesPath -Recurse -File | Where-Object {$_.FullName -match "chocolateyinstaller\.psm1"}
                                $ChocoProfileModuleFileItem = Get-ChildItem -Path $ChocoResourcesPath -Recurse -File | Where-Object {$_.FullName -match "chocolateyProfile\.psm1"}
                                $ChocoScriptRunnerFileItem = Get-ChildItem -Path $ChocoResourcesPath -Recurse -File | Where-Object {$_.FullName -match "chocolateyScriptRunner\.ps1"}
                                $ChocoTabExpansionFileItem = Get-ChildItem -Path $ChocoResourcesPath -Recurse -File | Where-Object {$_.FullName -match "chocolateyTabExpansion\.ps1"}

                                if (!$ChocoInstallerModuleFileItem -or !$ChocoProfileModuleFileItem) {
                                    throw "Unable to find chocolateyInstaller.psm1 or chocolateyProfile.psm1"
                                }
                            }

                            if ($ChocoInstallerModuleFileItem) {
                                Import-Module $ChocoInstallerModuleFileItem.FullName -Global -ErrorAction SilentlyContinue
                                $ChocoHelpersDir = $ChocoInstallerModuleFileItem.Directory
                            }
                            elseif ($ChocoProfileModuleFileItem) {
                                Import-Module $ChocoProfileModuleFileItem.FullName -Global -ErrorAction SilentlyContinue
                                $ChocoHelpersDir = $ChocoProfileModuleFileItem.Directory
                            }
                            elseif ($ChocoScriptRunnerFileItem) {
                                $ChocoHelpersDir = $ChocoScriptRunnerFileItem.Directory
                            }
                            elseif ($ChocoTabExpansionFileItem) {
                                $ChocoHelpersDir = $ChocoTabExpansionFileItem.Directory
                            }
                            
                            # Run the install script
                            $tempfile = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName())
                            <#
                            $ChocoScriptContent = Get-Content $ChocolateyInstallScript
                            $LineToReplace = $ChocoScriptContent -match "-nonewwindow -wait"
                            $UpdatedLine = $LineToReplace + "-RedirectStandardOutput `"$tempfile`""
                            $UpdatedChocoScriptContent = $ChocoScriptContent -replace [regex]::Escape($LineToReplace),$UpdatedLine
                            Set-Content -Path $ChocolateyInstallScript -Value $UpdatedChocoScriptContent
                            #>
                            $null = & $ChocolateyInstallScript *> $tempfile
                            #$null = Start-Process powershell -ArgumentList "& `"$ChocolateyInstallScript`"" -NoNewWindow -Wait -RedirectStandardOutput $tempfile
                            if (Test-Path $tempfile -ErrorAction SilentlyContinue) {Remove-Item $tempfile -Force}

                            # Now that the $ChocolateyInstallScript ran, search for the main executable again
                            Synchronize-SystemPathEnvPath
                            $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue

                            if ($ExpectedInstallLocation) {
                                if (Test-Path $ExpectedInstallLocation -ErrorAction SilentlyContinue) {
                                    [System.Collections.ArrayList][Array]$ExePath = Adjudicate-ExePath -ProgramName $ProgramName -OriginalSystemPath $OriginalSystemPath -OriginalEnvPath $OriginalEnvPath -FinalCommandName $FinalCommandName -ExpectedInstallLocation $ExpectedInstallLocation
                                }
                            }
                            else {
                                [System.Collections.ArrayList][Array]$ExePath = Adjudicate-ExePath -ProgramName $ProgramName -OriginalSystemPath $OriginalSystemPath -OriginalEnvPath $OriginalEnvPath -FinalCommandName $FinalCommandName
                            }

                            # If we STILL don't have $ExePath, try this...
                            if (!$ExePath -or $ExePath.Count -eq 0) {
                                $ProgramSourceParentDir = $(Get-Package $ProgramName).Source | Split-Path -Parent
                                if (![System.String]::IsNullOrWhiteSpace($ProgramSourceParentDir)) {
                                    $ExePath = $(Get-ChildItem -Path $ProgramSourceParentDir -Recurse -File | Where-Object {$_.Name -like "*$ProgramName*exe"}).FullName
                                }
                            }

                            # If we STILL don't have $ExePath, we need to give up...
                            if (!$ExePath -or $ExePath.Count -eq 0) {
                                #Write-Warning "Unable to find main executable for $ProgramName!"
                                $MainExeSearchFail = $True
                            }
                        }
                        catch {
                            #Write-Error $_
                            Write-Warning "The Chocolatey Install Script that came with the PowerShellGet Package (i.e. $ChocolateyInstallScript) threw an Error:`n    $($_.Exception.Message)"
                            Write-Warning "Uninstalling $ProgramName and any dependencies that were installed with it prior to trying Chocolatey Cmdline..."

                            $PackagesToUninstall = $(Get-Package).Name | foreach {if ($PreInstallPackagesList -notcontains $_ -and $_ -notmatch "choco") {$_}} | Sort-Object | Get-Unique
                            #$PackagesToUninstall | Export-CliXml "$HOME\PackagesToUninstall.xml"

                            $ChocolateyUninstallScript = $ChocolateyInstallScript -replace "chocolateyinstall","chocolateyuninstall"
                            if (Test-Path $ChocolateyUninstallScript) {
                                try {
                                    $tempfile = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName())
                                    $null = & $ChocolateyUninstallScript *> $tempfile
                                    if (Test-Path $tempfile -ErrorAction SilentlyContinue) {Remove-Item $tempfile -Force}
                                    
                                    foreach ($PackageName in $PackagesToUninstall) {
                                        $Counter = 0
                                        while ($(Get-Package).Name -contains $PackageName -and $Counter -le 3) {
                                            $null = Uninstall-Program -ProgramName $PackageName -ErrorAction SilentlyContinue
                                            $Counter++
                                        }
                                    }
                                }
                                catch {
                                    $CheckInstallStatus = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue

                                    if (!$CheckInstallStatus -or
                                    $($CheckInstallStatus.ChocolateyInstalledProgramObjects.Count -ne 0 -or
                                    $CheckInstallStatus.PSGetInstalledPackageObjects.Count -ne 0 -or
                                    $CheckInstallStatus.RegistryProperties.Count -ne 0)
                                    ) {
                                        $RunUninstallProgramFunction = $True
                                    }
                                }

                            }
                            if (!$(Test-Path $ChocolateyUninstallScript) -or $RunUninstallProgramFunction) {
                                foreach ($PackageName in $PackagesToUninstall) {
                                    $Counter = 0
                                    while ($(Get-Package).Name -contains $PackageName -and $Counter -le 3) {
                                        $null = Uninstall-Program -ProgramName $PackageName -ErrorAction SilentlyContinue
                                        $Counter++
                                    }
                                }
                            }

                            Write-Host "Checking install status..."

                            $CheckInstallStatus = Get-AllPackageInfo -ProgramName $ProgramName -ErrorAction SilentlyContinue
                            #$CheckInstallStatus | Export-CliXml "$HOME\CheckInstallStatus.xml"

                            if (!$CheckInstallStatus -or
                            $($CheckInstallStatus.ChocolateyInstalledProgramObjects.Count -ne 0 -or
                            $CheckInstallStatus.PSGetInstalledPackageObjects.Count -ne 0 -or
                            $CheckInstallStatus.RegistryProperties.Count -ne 0)
                            ) {
                                Write-Error "The PackageManagement/PowerShellGet installation did NOT uninstall cleanly!"
                                Write-Warning "Please check...`n    Get-Package`n    clist --local-only`n    appwiz.cpl`n...for the following Programs...`n$($PackagesToUninstall -join "`n")"
                                return
                            }

                            Write-Host "Installing via Chocolatey CmdLine..."

                            if (!$UsePowerShellGet -and !$ForceChocoInstallScript) {
                                Remove-Module chocolateyinstaller -ErrorAction SilentlyContinue
                                Remove-Module chocolateyProfile -ErrorAction SilentlyContinue

                                # Now we need to try the Chocolatey CmdLine. Easiest way to do this at this point is to just
                                # invoke the function again with the same parameters, but specify -UseChocolateyCmdLine
                                $BoundParametersDictionary = $PSCmdlet.MyInvocation.BoundParameters
                                $InstallProgramSplatParams = @{}
                                foreach ($kvpair in $BoundParametersDictionary.GetEnumerator()) {
                                    $key = $kvpair.Key
                                    $value = $BoundParametersDictionary[$key]
                                    if ($key -notmatch "UsePowerShellGet|ForceChocoInstallScript" -and $InstallProgramSplatParams.Keys -notcontains $key) {
                                        $InstallProgramSplatParams.Add($key,$value)
                                    }
                                }
                                if ($InstallProgramSplatParams.Keys -notcontains "UseChocolateyCmdLine") {
                                    $InstallProgramSplatParams.Add("UseChocolateyCmdLine",$True)
                                }
                                if ($InstallProgramSplatParams.Keys -notcontains "ErrorAction") {
                                    $InstallProgramSplatParams.Add("ErrorAction","Stop")
                                }
                                $PMInstall = $False

                                #$InstallProgramSplatParams | Export-CliXml "$HOME\InstallProgramSplatParams.xml"
                                
                                try {
                                    Install-Program @InstallProgramSplatParams
                                }
                                catch {
                                    $ParamstoString = $($InstallProgramSplatParams.GetEnumerator() | foreach {$_.key + ' ' + $_.value}) -join " "
                                    Write-Error $_
                                    Write-Error "'Install-Program $ParamstoString' failed. Please update Chocolatey via:`n    cup chocolatey -y"
                                    $global:FunctionResult = "1"
                                }
                                return
                                
                                <#
                                New-Runspace -RunspaceName "InstProgChocoCmd" -ScriptBlock {Install-Program @InstallProgramSplatParams}

                                while ($global:RSSyncHash.InstProgChocoCmdResult.Done -ne $True) {
                                    Write-Verbose "Waiting for install via Chocolatey CmdLine to finish..."
                                    Start-Sleep -Seconds 1
                                }

                                if ($global:RSSyncHash.Errors.Count -gt 0) {
                                    foreach ($ErrMsg in $global:RSSyncHash.Errors) {Write-Error $_}
                                }

                                if ($global:RSSyncHash.Output) {
                                    $global:RSSyncHash.Output
                                }

                                if (!$global:RSSyncHash.Output -or $global:RSSyncHash.Errors.Count -gt 0) {
                                    Write-Warning "Install via Chocolatey CmdlLine failed. Please update Chocolatey via:`n    cup chocolatey -y"
                                }
                                
                                return
                                #>
                            }
                            else {
                                $global:FunctionResult = "1"
                                return
                            }
                        }
                    }
                }
            }

            ## END Try to Find Main Executable Post Install ##
        }
    }
    else {
        if ($ChocolateyInstalledProgramsPSObjects.ProgramName -contains $ProgramName) {
            Write-Warning "$ProgramName is already installed via the Chocolatey CmdLine!"
            $AlreadyInstalled = $True
        }
        elseif ([bool]$(Get-Package $ProgramName -ErrorAction SilentlyContinue)) {
            Write-Warning "$ProgramName is already installed via PackageManagement/PowerShellGet!"
            $AlreadyInstalled = $True
        }

        if ($CommandName -or $ExpectedInstallLocation -or $ResolveCommandPath) {
            if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue) -and $(!$ExePath -or $ExePath.Count -eq 0)) {
                $env:Path = Update-ChocolateyEnv -ErrorAction SilentlyContinue
                
                if ($ExpectedInstallLocation) {
                    if (Test-Path $ExpectedInstallLocation -ErrorAction SilentlyContinue) {
                        [System.Collections.ArrayList][Array]$ExePath = Adjudicate-ExePath -ProgramName $ProgramName -OriginalSystemPath $OriginalSystemPath -OriginalEnvPath $OriginalEnvPath -FinalCommandName $FinalCommandName -ExpectedInstallLocation $ExpectedInstallLocation
                    }
                }
                else {
                    [System.Collections.ArrayList][Array]$ExePath = Adjudicate-ExePath -ProgramName $ProgramName -OriginalSystemPath $OriginalSystemPath -OriginalEnvPath $OriginalEnvPath -FinalCommandName $FinalCommandName
                }
            }
        }
    }

    # If we weren't able to find the main executable (or any potential main executables) for
    # $ProgramName, offer the option to scan the whole C:\ drive (with some obvious exceptions)
    if ($MainExeSearchFail -and
    $($ResolveCommandPath -or $PSBoundParameters['CommandName'] -or $PSBoundParameters['ScanCDriveForMainExeIfNecessary']) -and
    ![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)
    ) {
        if (!$ScanCDriveForMainExeIfNecessary -and !$ResolveCommandPath -and !$PSBoundParameters['CommandName']) {
            $ScanCDriveChoice = Read-Host -Prompt "Would you like to scan C:\ for $FinalCommandName.exe? NOTE: This search excludes system directories but still could take some time. [Yes\No]"
            while ($ScanCDriveChoice -notmatch "Yes|yes|Y|y|No|no|N|n") {
                Write-Host "$ScanDriveChoice is not a valid input. Please enter 'Yes' or 'No'"
                $ScanCDriveChoice = Read-Host -Prompt "Would you like to scan C:\ for $FinalCommandName.exe? NOTE: This search excludes system directories but still could take some time. [Yes\No]"
            }
        }

        if ($ScanCDriveChoice -match "Yes|yes|Y|y" -or $ScanCDriveForMainExeIfNecessary -or $ResolveCommandPath -or $PSBoundParameters['CommandName']) {
            $DirectoriesToSearchRecursively = $(Get-ChildItem -Path "C:\" -Directory | Where-Object {$_.Name -notmatch "Windows|PerfLogs|Microsoft"}).FullName
            [System.Collections.ArrayList]$ExePath = @()
            # Try to find a directory that matches the $ProgramName
            [System.Collections.ArrayList]$FoundMatchingDirs = @()
            foreach ($dir in $DirectoriesToSearchRecursively) {
                $DirectoriesIndex = Get-ChildItem -Path $dir -Recurse -Directory
                foreach ($subdirItem in $DirectoriesIndex) {
                    if ($subdirItem.FullName -match $ProgramName) {
                        $null = $FoundMatchingDirs.Add($subdiritem)
                    }
                }
            }
            foreach ($MatchingDirItem in $FoundMatchingDirs) {
                $FilesIndex = Get-ChildItem -Path $MatchingDirItem.FullName -Recurse -File
                foreach ($FilePath in $FilesIndex.Fullname) {
                    if ($FilePath -match "(.*?)$FinalCommandName([^\\]+)") {
                        $null = $ExePath.Add($FilePath)
                    }
                }
            }
        }
    }

    # Finalize $env:Path
    if ($ResolveCommandPath -or $PSBoundParameters['CommandName']) {
        if ([bool]$($ExePath -match "\\$FinalCommandName.exe$")) {
            $PathToAdd = $($ExePath -match "\\$FinalCommandName.exe$") | Split-Path -Parent
            $env:Path = $PathToAdd + ";" + $env:Path
        }
        $FinalEnvPathArray = $env:Path -split ";" | foreach {if(-not [System.String]::IsNullOrWhiteSpace($_)) {$_}}
        $FinalEnvPathString = $($FinalEnvPathArray | foreach {if (Test-Path $_ -ErrorAction SilentlyContinue) {$_}}) -join ";"
        $env:Path = $FinalEnvPathString

        if (![bool]$(Get-Command $FinalCommandName -ErrorAction SilentlyContinue)) {
            # Try to determine Main Executable
            if (!$ExePath -or $ExePath.Count -eq 0) {
                Write-Warning "Unable to find main executable for $ProgramName!"
                $FinalExeLocation = "NotFound"
            }
            elseif ($ExePath.Count -eq 1) {
                $UpdatedFinalCommandName = $ExePath | Split-Path -Leaf

                try {
                    $FinalExeLocation = $(Get-Command $UpdatedFinalCommandName -ErrorAction SilentlyContinue).Source
                }
                catch {
                    $FinalExeLocation = $ExePath | Where-Object {$($_ | Split-Path -Leaf) -match "\.exe$"}
                }
            }
            elseif ($ExePath.Count -gt 1) {
                if (![bool]$($ExePath -match "\\$FinalCommandName.exe$")) {
                    Write-Warning "No exact match for main executable $FinalCommandName.exe was found. However, other executables associated with $ProgramName were found."
                }
                $FinalExeLocation = $ExePath | Where-Object {$($_ | Split-Path -Leaf) -match "\.exe$"}
            }
        }
        else {
            $FinalExeLocation = $(Get-Command $FinalCommandName).Source
        }
    }

    if ($ChocoInstall) {
        $InstallManager = "choco.exe"
        $InstallCheck = $(clist --local-only $ProgramName)[1]
    }
    if ($PMInstall -or [bool]$(Get-Package $ProgramName -ProviderName Chocolatey -ErrorAction SilentlyContinue)) {
        $InstallManager = "PowerShellGet"
        $InstallCheck = Get-Package $ProgramName -ErrorAction SilentlyContinue
    }

    if ($AlreadyInstalled) {
        $InstallAction = "AlreadyInstalled"
    }
    elseif ($($PackageManagementCurrentInstalledPackage.Version -ne $null -and
    $PackageManagementCurrentInstalledPackage.Version -ne $PackageManagementLatestVersion.Version -and $PMInstall) -or
    $($ChocolateyOutdatedProgramsPSObjects.ProgramName -contains $ProgramName)
    ) {
        $InstallAction = "Updated"
    }
    else {
        $InstallAction = "FreshInstall"
    }

    $env:Path = Update-ChocolateyEnv

    1..3 | foreach {Pop-Location}

    if ($InstallAction -match "Updated|FreshInstall") {
        Write-Host "The program '$ProgramName' was installed successfully!" -ForegroundColor Green
    }
    elseif ($InstallAction -eq "AlreadyInstalled") {
        Write-Host "The program '$ProgramName' is already installed!" -ForegroundColor Green
    }

    $OutputHT = [ordered]@{
        InstallManager      = $InstallManager
        InstallAction       = $InstallAction
        InstallCheck        = $InstallCheck
    }
    if ([array]$($FinalExeLocation).Count -gt 1) {
        $OutputHT.Add("PossibleMainExecutables",$FinalExeLocation)
    }
    else {
        $OutputHT.Add("MainExecutable",$FinalExeLocation)
    }
    $OutputHT.Add("OriginalSystemPath",$OriginalSystemPath)
    $OutputHT.Add("CurrentSystemPath",$(Get-ItemProperty -Path 'Registry::HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Session Manager\Environment' -Name PATH).Path)
    $OutputHT.Add("OriginalEnvPath",$OriginalEnvPath)
    $OutputHT.Add("CurrentEnvPath",$env:Path)
    
    [pscustomobject]$OutputHT

    ##### END Main Body #####
}
