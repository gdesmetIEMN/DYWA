#region assembly import
Add-Type -Path $PSScriptRoot\Library\SysadminsLV.Asn1Parser.dll -ErrorAction Stop
Add-Type -Path $PSScriptRoot\Library\SysadminsLV.PKI.dll -ErrorAction Stop
Add-Type -AssemblyName System.Security -ErrorAction Stop
#endregion

#region global variable section
[Version]$OSVersion = [Environment]::OSVersion.Version
# compatibility
[bool]$NoDomain = $true # computer is a member of workgroup
try {
    $Domain = ([ADSI]"LDAP://RootDSE").ConfigurationNamingContext
    $PkiConfigContext = "CN=Public Key Services,CN=Services,$Domain"
    $NoDomain = $false
} catch {$NoDomain = $true}

[bool]$NoCAPI = $true   # CertAdm.dll server managemend library is missing
if (Test-Path $PSScriptRoot\Server) {
    try {
        $CertAdmin = New-Object -ComObject CertificateAuthority.Admin
        $NoCAPI = $false
    } catch {$NoCAPI = $true}
}
[bool]$NoCAPIv2 = $true # referring to enrollment web services support
$NoCAPIv2 = if (
        $OSVersion.Major -lt 6 -or
        ($OSVersion.Major -eq 6 -and
        $OSVersion.Minor -lt 1)
    ) {$true} else {$false}


$RegPath = "System\CurrentControlSet\Services\CertSvc\Configuration"
# os version map
$Win2003    = if ($OSVersion.Major -lt 6) {$true} else {$false}
$Win2008    = if ($OSVersion.Major -eq 6 -and $OSVersion.Minor -eq 0) {$true} else {$false}
$Win2008R2  = if ($OSVersion.Major -eq 6 -and $OSVersion.Minor -eq 1) {$true} else {$false}
$Win2012    = if ($OSVersion.Major -eq 6 -and $OSVersion.Minor -eq 2) {$true} else {$false}
$Win2012R2  = if ($OSVersion.Major -eq 6 -and $OSVersion.Minor -eq 3) {$true} else {$false}
$Win2016    = if ($OSVersion.Major -eq 10 -and $OSVersion.Minor -eq 0) {$true} else {$false}
# warning messages
$RestartRequired = @"
New {0} are set, but will not be applied until Certification Authority service is restarted.
In future consider to use '-RestartCA' switch for this cmdlet to restart Certification Authority service immediatelly when new settings are set.

See more: Start-CertificationAuthority, Stop-CertificationAuthority and Restart-CertificationAuthority cmdlets.
"@
$NothingIsSet = @"
Input object was not modified since it was created. Nothing is written to the CA configuration.
"@
#endregion

#region helper functions
function Ping-ICertAdmin ($ConfigString) {
    $success = $true
    try {
        $CertAdmin = New-Object -ComObject CertificateAuthority.Admin
        $var = $CertAdmin.GetCAProperty($ConfigString,0x6,0,4,0)
    } catch {$success = $false}
    $success
}

function Write-ErrorMessage {
    param (
        [PKI.Utils.PSErrorSourceEnum]$Source,
        $ComputerName,
        $ExtendedInformation
    )
$DCUnavailable = @"
"Active Directory domain could not be contacted.
"@
$CAPIUnavailable = @"
Unable to locate required assemblies. This can be caused if attempted to run this module on a client machine where AdminPack/RSAT (Remote Server Administration Tools) are not installed.
"@
$WmiUnavailable = @"
Unable to connect to CA server '$ComputerName'. Make sure if Remote Registry service is running and you have appropriate permissions to access it.
Also this error may indicate that Windows Remote Management protocol exception is not enabled in firewall.
"@
$XchgUnavailable = @"
Unable to retrieve any 'CA Exchange' certificates from '$ComputerName'. This error may indicate that target CA server do not support key archival. All requests which require key archival will immediately fail.
"@
    switch ($source) {
        DCUnavailable {
            Write-Error -Category ObjectNotFound -ErrorId "ObjectNotFoundException" `
            -Message $DCUnavailable
        }
        CAPIUnavailable {
            Write-Error -Category NotImplemented -ErrorId "NotImplementedException" `
            -Message $NoCAPI; exit
        }
        CAUnavailable {
            Write-Error -Category ResourceUnavailable -ErrorId ResourceUnavailableException `
            -Message "Certificate Services are either stopped or unavailable on '$ComputerName'."
        }
        WmiUnavailable {
            Write-Error -Category ResourceUnavailable -ErrorId ResourceUnavailableException `
            -Message $WmiUnavailable
        }
        WmiWriteError {
            try {$text = Get-ErrorMessage $ExtendedInformation}
            catch {$text = "Unknown error '$code'"}
            Write-Error -Category NotSpecified -ErrorId NotSpecifiedException `
            -Message "An error occured during CA configuration update: $text"
        }
        ADKRAUnavailable {
            Write-Error -Category ObjectNotFound -ErrorId "ObjectNotFoundException" `
            -Message "No KRA certificates found in Active Directory."
        }
        ICertAdminUnavailable {
            Write-Error -Category ResourceUnavailable -ErrorId ResourceUnavailableException `
            -Message "Unable to connect to management interfaces on '$ComputerName'"
        }
        NoXchg {
            Write-Error -Category ObjectNotFound -ErrorId ObjectNotFoundException `
            -Message $XchgUnavailable
        }
        NonEnterprise {
            Write-Error -Category NotImplemented -ErrorAction NotImplementedException `
            -Message "Specified Certification Authority type is not supported. The CA type must be either 'Enterprise Root CA' or 'Enterprise Standalone CA'."
        }
    }
}
#endregion

#region module installation stuff
# dot-source all function files
Get-ChildItem -Path $PSScriptRoot -Include *.ps1 -Recurse | Foreach-Object { . $_.FullName }
$aliases = @()
if ($Win2008R2 -and (Test-Path $PSScriptRoot\Server)) {
    New-Alias -Name Add-CEP                 -Value Add-CertificateEnrollmentPolicyService -Force
    New-Alias -Name Add-CES                 -Value Add-CertificateEnrollmentService -Force
    New-Alias -Name Remove-CEP              -Value Remove-CertificateEnrollmentPolicyService -Force
    New-Alias -Name Remove-CES              -Value Remove-CertificateEnrollmentService -Force
    New-Alias -Name Get-DatabaseRow         -Value Get-AdcsDatabaseRow -Force
    $aliases += "Add-CEP", "Add-CES", "Remove-CEP", "Remove-CES", "Get-DatabaseRow"
}
if (($Win2008 -or $Win2008R2) -and (Test-Path $PSScriptRoot\Server)) {
    New-Alias -Name Install-CA                  -Value Install-CertificationAuthority -Force
    New-Alias -Name Uninstall-CA                -Value Uninstall-CertificationAuthority -Force
    $aliases += "Install-CA", "Uninstall-CA"
}
if (!$NoDomain) {
    New-Alias -Name Add-AdCrl                   -Value Add-AdCertificateRevocationList -Force
    New-Alias -Name Remove-AdCrl                -Value Add-AdCertificateRevocationList -Force
    $aliases += "Add-AdCrl ", "Remove-AdCrl"
}
if (!$NoDomain -and (Test-Path $PSScriptRoot\Server)) {
    New-Alias -Name Get-CA                      -Value Get-CertificationAuthority -Force
    New-Alias -Name Get-KRAFlag                 -Value Get-KeyRecoveryAgentFlag -Force
    New-Alias -Name Enable-KRAFlag              -Value Enable-KeyRecoveryAgentFlag -Force
    New-Alias -Name Disable-KRAFlag             -Value Disable-KeyRecoveryAgentFlag -Force
    New-Alias -Name Restore-KRAFlagDefault      -Value Restore-KeyRecoveryAgentFlagDefault -Force
    $aliases += "Get-CA", "Get-KRAFlag", "Enable-KRAFlag", "Disable-KRAFlag", "Restore-KRAFlagDefault"
}
if (Test-Path $PSScriptRoot\Server) {
    New-Alias -Name Connect-CA                  -Value Connect-CertificationAuthority -Force
    
    New-Alias -Name Add-AIA                     -Value Add-AuthorityInformationAccess -Force
    New-Alias -Name Get-AIA                     -Value Get-AuthorityInformationAccess -Force
    New-Alias -Name Remove-AIA                  -Value Remove-AuthorityInformationAccess -Force
    New-Alias -Name Set-AIA                     -Value Set-AuthorityInformationAccess -Force

    New-Alias -Name Add-CDP                     -Value Add-CRLDistributionPoint -Force
    New-Alias -Name Get-CDP                     -Value Get-CRLDistributionPoint -Force
    New-Alias -Name Remove-CDP                  -Value Remove-CRLDistributionPoint -Force
    New-Alias -Name Set-CDP                     -Value Set-CRLDistributionPoint -Force
    
    New-Alias -Name Get-CRLFlag                 -Value Get-CertificateRevocationListFlag -Force
    New-Alias -Name Enable-CRLFlag              -Value Enable-CertificateRevocationListFlag -Force
    New-Alias -Name Disable-CRLFlag             -Value Disable-CertificateRevocationListFlag -Force
    New-Alias -Name Restore-CRLFlagDefault      -Value Restore-CertificateRevocationListFlagDefault -Force
    
    New-Alias -Name Remove-Request              -Value Remove-DatabaseRow -Force
    
    New-Alias -Name Get-CAACL                   -Value Get-CASecurityDescriptor -Force
    New-Alias -Name Add-CAACL                   -Value Add-CAAccessControlEntry -Force
    New-Alias -Name Remove-CAACL                -Value Remove-CAAccessControlEntry -Force
    New-Alias -Name Set-CAACL                   -Value Set-CASecurityDescriptor -Force
    $aliases += "Connect-CA", "Add-AIA", "Get-AIA", "Remove-AIA", "Add-CDP", "Get-CDP", "Remove-CDP",
        "Set-CDP", "Get-CRLFlag", "Enable-CRLFlag", "Disable-CRLFlag", "Restore-CRLFlagDefault",
        "Remove-Request", "Get-CAACL", "Add-CAACL", "Remove-CAACL", "Set-CAACL"
}

if (Test-Path $PSScriptRoot\Client) {
    New-Alias -Name "oid"                       -Value Get-ObjectIdentifier -Force
    New-Alias -Name oid2                        -Value Get-ObjectIdentifierEx -Force

    New-Alias -Name Get-Csp                     -Value Get-CryptographicServiceProvider -Force

    New-Alias -Name Get-CRL                     -Value Get-CertificateRevocationList -Force
    New-Alias -Name Show-CRL                    -Value Show-CertificateRevocationList -Force
    New-Alias -Name Get-CTL                     -Value Get-CertificateTrustList -Force
    New-Alias -Name Show-CTL                    -Value Show-CertificateTrustList -Force
    $aliases += "oid", "oid2", "Get-CRL", "Show-CRL", "Get-CTL", "Show-CTL"
}

# define restricted functions
$RestrictedFunctions =      "Get-RequestRow",
                            "Ping-ICertAdmin",
                            "Write-ErrorMessage"
$NoDomainExcludeFunctions = "Get-AdPkicontainer",
                            "Add-AdCertificate",
                            "Remove-AdCertificate",
                            "Add-AdCertificateRevocationList",
                            "Remove-AdCertificateRevocationList",
                            "Add-CAKRACertificate",
                            "Add-CATemplate",
                            "Add-CertificateEnrollmentPolicyService",
                            "Add-CertificateEnrollmentService",
                            "Add-CertificateTemplateAcl",
                            "Disable-KeyRecoveryAgentFlag",
                            "Enable-KeyRecoveryAgentFlag",
                            "Get-ADKRACertificate",
                            "Get-CAExchangeCertificate",
                            "Get-CAKRACertificate",
                            "Get-CATemplate",
                            "Get-CertificateTemplate",
                            "Get-CertificateTemplateAcl",
                            "Get-EnrollmentServiceUri",
                            "Get-KeyRecoveryAgentFlag",
                            "Remove-CAKRACertificate",
                            "Remove-CATemplate",
                            "Remove-CertificateTemplate",
                            "Remove-CertificateTemplateAcl",
                            "Restore-KeyRecoveryAgentFlagDefault",
                            "Set-CAKRACertificate",
                            "Set-CATemplate",
                            "Set-CertificateTemplateAcl",
                            "Get-CertificationAuthority"
$Win2003ExcludeFunctions =  "Add-CertificateEnrollmentPolicyService",
                            "Add-CertificateEnrollmentService",
                            "Install-CertificationAuthority",
                            "Remove-CertificateEnrollmentPolicyService",
                            "Remove-CertificateEnrollmentService",
                            "Uninstall-CertificationAuthority"  
$Win2008ExcludeFunctions =  "Add-CertificateEnrollmentPolicyService",
                            "Add-CertificateEnrollmentService",
                            "Remove-CertificateEnrollmentPolicyService",
                            "Remove-CertificateEnrollmentService"
$Win2012ExcludeFunctions =  "Install-CertificationAuthority",
                            "Uninstall-CertificationAuthority",
                            "Add-CertificateEnrollmentPolicyService",
                            "Add-CertificateEnrollmentService",
                            "Remove-CertificateEnrollmentPolicyService",
                            "Remove-CertificateEnrollmentService"

if ($Win2003) {$RestrictedFunctions += $Win2003ExcludeFunctions}
if ($Win2008) {$RestrictedFunctions += $Win2008ExcludeFunctions}
if ($Win2012) {$RestrictedFunctions += $Win2012ExcludeFunctions}
if ($Win2012R2) {$RestrictedFunctions += $Win2012ExcludeFunctions}
if ($Win2016) {$RestrictedFunctions += $Win2012ExcludeFunctions}
if ($NoDomain) {$RestrictedFunctions += $NoDomainExcludeFunctions}
# do not export any function from Server folder when RSAT is not installed.
# only client components are exported
if ($NoCAPI) {
    $RestrictedFunctions += Get-ChildItem $PSScriptRoot\Server -Filter "*.ps1" | ForEach-Object {$_.BaseName}
    Write-Warning @"
Active Directory Certificate Services remote administration tools (RSAT) are not installed and only
client-side functionality will be available.
"@
}
# export module members
Export-ModuleMember –Function @(
    Get-ChildItem $PSScriptRoot -Include *.ps1 -Recurse | `
        ForEach-Object {$_.Name -replace ".ps1"} | `
        Where-Object {$RestrictedFunctions -notcontains $_}
)
Export-ModuleMember -Alias $aliases
#endregion
# SIG # Begin signature block
# MIIcgAYJKoZIhvcNAQcCoIIccTCCHG0CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBtXOunUBdaFL7k
# uJLeYd+NFoV3/VttbSzFqr3k6P8zdKCCF4owggUTMIID+6ADAgECAhAJwnVp5a70
# RHscglFEfEqLMA0GCSqGSIb3DQEBCwUAMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNV
# BAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0EwHhcN
# MTcwNDE3MDAwMDAwWhcNMjAwNDIxMTIwMDAwWjBQMQswCQYDVQQGEwJMVjENMAsG
# A1UEBxMEUmlnYTEYMBYGA1UEChMPU3lzYWRtaW5zIExWIElLMRgwFgYDVQQDEw9T
# eXNhZG1pbnMgTFYgSUswggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCo
# NCCuzEogktL+1+lvPHu7ctNtCD7wA5Nalebh0FaKz3v1944APtg7A5oQfh6c20f7
# xYyTw4wVuo6L6S3dlMUa+bfXvTXIco0ilTIz0uqUKW8WGYwJtbFpu6PvCs0LHDRD
# rD8sEFgGHQhbz+J4gtV8BI7OID+yNfgbUk4JeSBGNzgeqZMdf/xceMoLx+fHi9tU
# OdTtgs/dXQYg3M3J+rGxFdpxOO7JmUZ8nqVALlnU9cHBGKUY4hDvDxfp7EukhnHv
# RpkhacZB1RBw0q8q+ekvLVCZwpG4N1Pnq2ksHiBzqRWQQE89iV+UwgRnLx2igywk
# 2kX+JPSZYsQCbDGo4DqBAgMBAAGjggHFMIIBwTAfBgNVHSMEGDAWgBRaxLl7Kgqj
# pepxA8Bg+S32ZXUOWDAdBgNVHQ4EFgQU9Mh+66y4uf1WQl9FmsWMHdk2HrswDgYD
# VR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGA1UdHwRwMG4wNaAz
# oDGGL2h0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9zaGEyLWFzc3VyZWQtY3MtZzEu
# Y3JsMDWgM6Axhi9odHRwOi8vY3JsNC5kaWdpY2VydC5jb20vc2hhMi1hc3N1cmVk
# LWNzLWcxLmNybDBMBgNVHSAERTBDMDcGCWCGSAGG/WwDATAqMCgGCCsGAQUFBwIB
# FhxodHRwczovL3d3dy5kaWdpY2VydC5jb20vQ1BTMAgGBmeBDAEEATCBhAYIKwYB
# BQUHAQEEeDB2MCQGCCsGAQUFBzABhhhodHRwOi8vb2NzcC5kaWdpY2VydC5jb20w
# TgYIKwYBBQUHMAKGQmh0dHA6Ly9jYWNlcnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dFNIQTJBc3N1cmVkSURDb2RlU2lnbmluZ0NBLmNydDAMBgNVHRMBAf8EAjAAMA0G
# CSqGSIb3DQEBCwUAA4IBAQCfpLMUerP0WXkcb9+dunMLt3jowZEd8X6ISxxzdsdB
# 8jOZ92L88qKqjWD1I9HBceba4tdJZCLV33S9a3eoxUunIlJH4GmYH/HSrc2qgNxg
# PyobmWf556c7Wd3q6ZUKgos0bw++TtLqb/jvoKN19epTEkwQDIwVFzOAxZ4T+sYr
# jmFhd9KeaRhTLZRBVdKNTKtXaoWFrfNSQTp8NcNYdkEM05cUnEUMDOoeLSmxPnIv
# pl8KbripxtVQ591rCLJN2uMtrtSE1nvjiYfSFQI00EiB33ZoI2T1eCNuP1M6c+ex
# KzQQC8UDp7J+duzl1j605TwSfLS/MJsaiwftNzc3FfgSMIIFMDCCBBigAwIBAgIQ
# BAkYG1/Vu2Z1U0O1b5VQCDANBgkqhkiG9w0BAQsFADBlMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMTMxMDIy
# MTIwMDAwWhcNMjgxMDIyMTIwMDAwWjByMQswCQYDVQQGEwJVUzEVMBMGA1UEChMM
# RGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMTEwLwYDVQQD
# EyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5nIENBMIIBIjAN
# BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA+NOzHH8OEa9ndwfTCzFJGc/Q+0WZ
# sTrbRPV/5aid2zLXcep2nQUut4/6kkPApfmJ1DcZ17aq8JyGpdglrA55KDp+6dFn
# 08b7KSfH03sjlOSRI5aQd4L5oYQjZhJUM1B0sSgmuyRpwsJS8hRniolF1C2ho+mI
# LCCVrhxKhwjfDPXiTWAYvqrEsq5wMWYzcT6scKKrzn/pfMuSoeU7MRzP6vIK5Fe7
# SrXpdOYr/mzLfnQ5Ng2Q7+S1TqSp6moKq4TzrGdOtcT3jNEgJSPrCGQ+UpbB8g8S
# 9MWOD8Gi6CxR93O8vYWxYoNzQYIH5DiLanMg0A9kczyen6Yzqf0Z3yWT0QIDAQAB
# o4IBzTCCAckwEgYDVR0TAQH/BAgwBgEB/wIBADAOBgNVHQ8BAf8EBAMCAYYwEwYD
# VR0lBAwwCgYIKwYBBQUHAwMweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhho
# dHRwOi8vb2NzcC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNl
# cnRzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwgYEG
# A1UdHwR6MHgwOqA4oDaGNGh0dHA6Ly9jcmw0LmRpZ2ljZXJ0LmNvbS9EaWdpQ2Vy
# dEFzc3VyZWRJRFJvb3RDQS5jcmwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0
# LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwTwYDVR0gBEgwRjA4Bgpg
# hkgBhv1sAAIEMCowKAYIKwYBBQUHAgEWHGh0dHBzOi8vd3d3LmRpZ2ljZXJ0LmNv
# bS9DUFMwCgYIYIZIAYb9bAMwHQYDVR0OBBYEFFrEuXsqCqOl6nEDwGD5LfZldQ5Y
# MB8GA1UdIwQYMBaAFEXroq/0ksuCMS1Ri6enIZ3zbcgPMA0GCSqGSIb3DQEBCwUA
# A4IBAQA+7A1aJLPzItEVyCx8JSl2qB1dHC06GsTvMGHXfgtg/cM9D8Svi/3vKt8g
# VTew4fbRknUPUbRupY5a4l4kgU4QpO4/cY5jDhNLrddfRHnzNhQGivecRk5c/5Cx
# GwcOkRX7uq+1UcKNJK4kxscnKqEpKBo6cSgCPC6Ro8AlEeKcFEehemhor5unXCBc
# 2XGxDI+7qPjFEmifz0DLQESlE/DmZAwlCEIysjaKJAL+L3J+HNdJRZboWR3p+nRk
# a7LrZkPas7CM1ekN3fYBIM6ZMWM9CBoYs4GbT8aTEAb8B4H6i9r5gkn3Ym6hU/oS
# lBiFLpKR6mhsRDKyZqHnGKSaZFHvMIIGajCCBVKgAwIBAgIQAwGaAjr/WLFr1tXq
# 5hfwZjANBgkqhkiG9w0BAQUFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBBc3N1cmVkIElEIENBLTEwHhcNMTQxMDIyMDAwMDAwWhcNMjQxMDIy
# MDAwMDAwWjBHMQswCQYDVQQGEwJVUzERMA8GA1UEChMIRGlnaUNlcnQxJTAjBgNV
# BAMTHERpZ2lDZXJ0IFRpbWVzdGFtcCBSZXNwb25kZXIwggEiMA0GCSqGSIb3DQEB
# AQUAA4IBDwAwggEKAoIBAQCjZF38fLPggjXg4PbGKuZJdTvMbuBTqZ8fZFnmfGt/
# a4ydVfiS457VWmNbAklQ2YPOb2bu3cuF6V+l+dSHdIhEOxnJ5fWRn8YUOawk6qhL
# LJGJzF4o9GS2ULf1ErNzlgpno75hn67z/RJ4dQ6mWxT9RSOOhkRVfRiGBYxVh3lI
# RvfKDo2n3k5f4qi2LVkCYYhhchhoubh87ubnNC8xd4EwH7s2AY3vJ+P3mvBMMWSN
# 4+v6GYeofs/sjAw2W3rBerh4x8kGLkYQyI3oBGDbvHN0+k7Y/qpA8bLOcEaD6dpA
# oVk62RUJV5lWMJPzyWHM0AjMa+xiQpGsAsDvpPCJEY93AgMBAAGjggM1MIIDMTAO
# BgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEF
# BQcDCDCCAb8GA1UdIASCAbYwggGyMIIBoQYJYIZIAYb9bAcBMIIBkjAoBggrBgEF
# BQcCARYcaHR0cHM6Ly93d3cuZGlnaWNlcnQuY29tL0NQUzCCAWQGCCsGAQUFBwIC
# MIIBVh6CAVIAQQBuAHkAIAB1AHMAZQAgAG8AZgAgAHQAaABpAHMAIABDAGUAcgB0
# AGkAZgBpAGMAYQB0AGUAIABjAG8AbgBzAHQAaQB0AHUAdABlAHMAIABhAGMAYwBl
# AHAAdABhAG4AYwBlACAAbwBmACAAdABoAGUAIABEAGkAZwBpAEMAZQByAHQAIABD
# AFAALwBDAFAAUwAgAGEAbgBkACAAdABoAGUAIABSAGUAbAB5AGkAbgBnACAAUABh
# AHIAdAB5ACAAQQBnAHIAZQBlAG0AZQBuAHQAIAB3AGgAaQBjAGgAIABsAGkAbQBp
# AHQAIABsAGkAYQBiAGkAbABpAHQAeQAgAGEAbgBkACAAYQByAGUAIABpAG4AYwBv
# AHIAcABvAHIAYQB0AGUAZAAgAGgAZQByAGUAaQBuACAAYgB5ACAAcgBlAGYAZQBy
# AGUAbgBjAGUALjALBglghkgBhv1sAxUwHwYDVR0jBBgwFoAUFQASKxOYspkH7R7f
# or5XDStnAs0wHQYDVR0OBBYEFGFaTSS2STKdSip5GoNL9B6Jwcp9MH0GA1UdHwR2
# MHQwOKA2oDSGMmh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3Vy
# ZWRJRENBLTEuY3JsMDigNqA0hjJodHRwOi8vY3JsNC5kaWdpY2VydC5jb20vRGln
# aUNlcnRBc3N1cmVkSURDQS0xLmNybDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUH
# MAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDov
# L2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElEQ0EtMS5jcnQw
# DQYJKoZIhvcNAQEFBQADggEBAJ0lfhszTbImgVybhs4jIA+Ah+WI//+x1GosMe06
# FxlxF82pG7xaFjkAneNshORaQPveBgGMN/qbsZ0kfv4gpFetW7easGAm6mlXIV00
# Lx9xsIOUGQVrNZAQoHuXx/Y/5+IRQaa9YtnwJz04HShvOlIJ8OxwYtNiS7Dgc6aS
# wNOOMdgv420XEwbu5AO2FKvzj0OncZ0h3RTKFV2SQdr5D4HRmXQNJsQOfxu19aDx
# xncGKBXp2JPlVRbwuwqrHNtcSCdmyKOLChzlldquxC5ZoGHd2vNtomHpigtt7BIY
# vfdVVEADkitrwlHCCkivsNRu4PQUCjob4489yq9qjXvc2EQwggbNMIIFtaADAgEC
# AhAG/fkDlgOt6gAK6z8nu7obMA0GCSqGSIb3DQEBBQUAMGUxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xJDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0wNjEx
# MTAwMDAwMDBaFw0yMTExMTAwMDAwMDBaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IEFzc3VyZWQgSUQgQ0EtMTCCASIwDQYJKoZIhvcNAQEBBQAD
# ggEPADCCAQoCggEBAOiCLZn5ysJClaWAc0Bw0p5WVFypxNJBBo/JM/xNRZFcgZ/t
# LJz4FlnfnrUkFcKYubR3SdyJxArar8tea+2tsHEx6886QAxGTZPsi3o2CAOrDDT+
# GEmC/sfHMUiAfB6iD5IOUMnGh+s2P9gww/+m9/uizW9zI/6sVgWQ8DIhFonGcIj5
# BZd9o8dD3QLoOz3tsUGj7T++25VIxO4es/K8DCuZ0MZdEkKB4YNugnM/JksUkK5Z
# ZgrEjb7SzgaurYRvSISbT0C58Uzyr5j79s5AXVz2qPEvr+yJIvJrGGWxwXOt1/HY
# zx4KdFxCuGh+t9V3CidWfA9ipD8yFGCV/QcEogkCAwEAAaOCA3owggN2MA4GA1Ud
# DwEB/wQEAwIBhjA7BgNVHSUENDAyBggrBgEFBQcDAQYIKwYBBQUHAwIGCCsGAQUF
# BwMDBggrBgEFBQcDBAYIKwYBBQUHAwgwggHSBgNVHSAEggHJMIIBxTCCAbQGCmCG
# SAGG/WwAAQQwggGkMDoGCCsGAQUFBwIBFi5odHRwOi8vd3d3LmRpZ2ljZXJ0LmNv
# bS9zc2wtY3BzLXJlcG9zaXRvcnkuaHRtMIIBZAYIKwYBBQUHAgIwggFWHoIBUgBB
# AG4AeQAgAHUAcwBlACAAbwBmACAAdABoAGkAcwAgAEMAZQByAHQAaQBmAGkAYwBh
# AHQAZQAgAGMAbwBuAHMAdABpAHQAdQB0AGUAcwAgAGEAYwBjAGUAcAB0AGEAbgBj
# AGUAIABvAGYAIAB0AGgAZQAgAEQAaQBnAGkAQwBlAHIAdAAgAEMAUAAvAEMAUABT
# ACAAYQBuAGQAIAB0AGgAZQAgAFIAZQBsAHkAaQBuAGcAIABQAGEAcgB0AHkAIABB
# AGcAcgBlAGUAbQBlAG4AdAAgAHcAaABpAGMAaAAgAGwAaQBtAGkAdAAgAGwAaQBh
# AGIAaQBsAGkAdAB5ACAAYQBuAGQAIABhAHIAZQAgAGkAbgBjAG8AcgBwAG8AcgBh
# AHQAZQBkACAAaABlAHIAZQBpAG4AIABiAHkAIAByAGUAZgBlAHIAZQBuAGMAZQAu
# MAsGCWCGSAGG/WwDFTASBgNVHRMBAf8ECDAGAQH/AgEAMHkGCCsGAQUFBwEBBG0w
# azAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUF
# BzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVk
# SURSb290Q0EuY3J0MIGBBgNVHR8EejB4MDqgOKA2hjRodHRwOi8vY3JsMy5kaWdp
# Y2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3JsMDqgOKA2hjRodHRw
# Oi8vY3JsNC5kaWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3Js
# MB0GA1UdDgQWBBQVABIrE5iymQftHt+ivlcNK2cCzTAfBgNVHSMEGDAWgBRF66Kv
# 9JLLgjEtUYunpyGd823IDzANBgkqhkiG9w0BAQUFAAOCAQEARlA+ybcoJKc4HbZb
# Ka9Sz1LpMUerVlx71Q0LQbPv7HUfdDjyslxhopyVw1Dkgrkj0bo6hnKtOHisdV0X
# FzRyR4WUVtHruzaEd8wkpfMEGVWp5+Pnq2LN+4stkMLA0rWUvV5PsQXSDj0aqRRb
# poYxYqioM+SbOafE9c4deHaUJXPkKqvPnHZL7V/CSxbkS3BMAIke/MV5vEwSV/5f
# 4R68Al2o/vsHOE8Nxl2RuQ9nRc3Wg+3nkg2NsWmMT/tZ4CMP0qquAHzunEIOz5HX
# J7cW7g/DvXwKoO4sCFWFIrjrGBpN/CohrUkxg0eVd3HcsRtLSxwQnHcUwZ1PL1qV
# CCkQJjGCBEwwggRIAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdp
# Q2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xMTAvBgNVBAMTKERp
# Z2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcgQ0ECEAnCdWnlrvRE
# exyCUUR8SoswDQYJYIZIAWUDBAIBBQCggYQwGAYKKwYBBAGCNwIBDDEKMAigAoAA
# oQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEEAYI3AgELMQ4w
# DAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQg84dkK8PZF3x3CoMSZwy+TAGg
# YpcWi6VserkFAl+rV8UwDQYJKoZIhvcNAQEBBQAEggEAaBDXiIeaUWiufAvh4Y5Z
# 4GxJHbTVlrUrCvR3O9gd16NXWrnApAzzy5h3wG+YmVOLAitm3c/n16uBmnloJObp
# PgMu+R13rnFr+aQ1OjLVEbKblVhc9IQKXwFc6je0E+HpSQKfwqPqopae8t1hUjqg
# rVVqbGT6fpv8eIpbhlbFdTRi/Tx78moESnMZdX/+7lNZX+SFux+xYe10/TR0ctaj
# Jo/jhXZLDe/ICENBzRomPplagozEGAM1X+BE5/AkGb7YCyrEzIIW70rgutkPxxOT
# MeLNa0Xycl+YEIaCeLc4tsH2TNKdp+0K/pD3aEkB5dHn3EnjQ0YgtaxspsAZepv1
# KqGCAg8wggILBgkqhkiG9w0BCQYxggH8MIIB+AIBATB2MGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3VyZWQgSUQgQ0EtMQIQAwGaAjr/WLFr
# 1tXq5hfwZjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAc
# BgkqhkiG9w0BCQUxDxcNMTgxMDIyMTYyMzQwWjAjBgkqhkiG9w0BCQQxFgQUkJgh
# BYviEVpKgsj+cswlOtTMXUAwDQYJKoZIhvcNAQEBBQAEggEAK9rQfCdzuRz7YvVe
# 3nGPDlov0loOQoP8q0S7oBsPbO3NzzgDFWRdSzycRkfg9e8CjQbiR3izFD1R7Wgq
# k/XPGZIyXOlwHZBVVc1XtUJL7zolzrpOUuh+D+QrsoEVJukGZZc7EKivLnQjjjFj
# Elfo5cBKcjyjGRKr+lTkU1Un4WNe7j28Xz/Gmyjtfrj9gN1ST1C3gzzzlIWpScza
# I1hbCRkTLJTXudX8tCb+1KzXYIuRTES37Tn1LxloV3tE0YiJ/jxMP/Xfe9bZDvr/
# eKIzpJZckgjqALM7Ig9E9FT+nygTgR7rL2Orh86ivuDZRFoSURO2pycTCoGyFljp
# Vegj8A==
# SIG # End signature block
