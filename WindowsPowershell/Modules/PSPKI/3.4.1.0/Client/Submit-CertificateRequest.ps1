function Submit-CertificateRequest {
<#
.ExternalHelp PSPKI.Help.xml
#>
[OutputType('PKI.Enrollment.CertRequestStatus')]
[CmdletBinding(DefaultParameterSetName = '__dcom')]
	param(
		[Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
		[IO.FileInfo[]]$Path,
		[Parameter(Mandatory = $true, ParameterSetName = '__dcom')]
		[Alias('CA')]
		[PKI.CertificateServices.CertificateAuthority]$CertificationAuthority,
		[Parameter(Mandatory = $true, ParameterSetName = '__xcep')]
		[Alias('CEP')]
		[PKI.Enrollment.Policy.PolicyServerClient]$EnrollmentPolicyServer,
		[System.Management.Automation.PSCredential]$Credential,
		[String[]]$Attribute
	)
	begin {
		$ErrorActionPreference = "Stop"
		$CertRequest = New-Object -ComObject CertificateAuthority.Request
		switch ($PsCmdlet.ParameterSetName) {
			"__xcep" {
				if ($NoCAPIv2) {throw New-Object NotSupportedException}
				if (![string]::IsNullOrEmpty($Credential.UserName)) {
					switch ($EnrollmentPolicyServer.Authentication) {
						"UserNameAndPassword" {
							$CertRequest.SetCredential(
								0,
								[int]$EnrollmentPolicyServer.Authentication,
								$Credential.UserName,
								[Runtime.InteropServices.Marshal]::PtrToStringAuto(
									[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
								)
							)
						}
						"ClientCertificate" {							
							$CertRequest.SetCredential(
								0,
								[int]$EnrollmentPolicyServer.Authentication,
								$Credential.UserName,
								$null
							)
						}
					}
				}
			}
			"__dcom" {
				if (!$CertificationAuthority.IsAccessible) {
					$e = New-Object PKI.Exceptions.ServerUnavailableException
					$e.Server = $CertificationAuthority.DisplayName
					throw $e
				}
			}
		}
		if ($Attribute -eq $null) {
			$strAttribute = [string]::Empty
		} else {
			$SB = New-Object Text.StringBuilder
			foreach ($attrib in $Attribute) {
				[Void]$SB.Append($attrib + "`n")
			}
			$strAttribute = $SB.ToString()
			$strAttribute = $strAttribute.Substring(0,$strAttribute.Length - 1)
		}
	}
	process {
		$Path | ForEach-Object {
			try {
				$Request = [IO.File]::ReadAllText($_)
				$Status = $CertRequest.Submit(0xff,$Request,$strAttribute,$CertificationAuthority.ConfigString)
				$Output = New-Object PKI.Enrollment.CertRequestStatus -Property @{
					CertificationAuthority = $CertificationAuthority;
					Status = $Status;
					RequestID = $CertRequest.GetRequestId()
				}
				if ($Status -eq 3) {
					$base64 = $CertRequest.GetCertificate(1)
					$Output.Certificate = New-Object Security.Cryptography.X509Certificates.X509Certificate2 (,[Convert]::FromBase64String($base64))
				} else {
					$Output.ErrorInformation = $CertRequest.GetDispositionMessage()
				}
				$Output
			} catch {throw $_}
		}
	}
}
# SIG # Begin signature block
# MIIcgAYJKoZIhvcNAQcCoIIccTCCHG0CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAwIxZ4wW5gWuCd
# NPVx0G4gnADTBxZM/LuMQvsgpx1qPaCCF4owggUTMIID+6ADAgECAhAJwnVp5a70
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
# DAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgLdqQ7cAtw3CRf38l0Nw2/Hb3
# xQf99Nl3jN8R9mRZ/bwwDQYJKoZIhvcNAQEBBQAEggEAlERB47UkbENYSRShML3T
# GitaS9/5JhFhB4lOWWVEF0t8zUrACoX8u0GUgfqoQfg/QpNP5P06mo7ijIladAnA
# BLwwYO7H/O3vXRl5t7CXO3HYK+TGR/VxYZnxwMxCHSwqzPvu93cnhrZW5LUaM74k
# MceOE8Mk5HeDknW9Ik1Kx/pkog3m3wZliA/MzoGE6WiWg3R1vdqP9oaImKzQj+33
# GBb9jDXrGHeyBwY36sTGk3+jIlRMYvBC1uLqwygo8A8mHu14JBuSschh9IqBmmFb
# YrwW2Q5l6Hgr5KIK+X/KWvySNCkF8N/lzqx6DwH/59SfwHcI+P+XxCtJt15oG/qZ
# baGCAg8wggILBgkqhkiG9w0BCQYxggH8MIIB+AIBATB2MGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3VyZWQgSUQgQ0EtMQIQAwGaAjr/WLFr
# 1tXq5hfwZjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAc
# BgkqhkiG9w0BCQUxDxcNMTgxMDIyMTYyNzIyWjAjBgkqhkiG9w0BCQQxFgQUlhcU
# 8D85Jem2chGO9S9GMJzMYU8wDQYJKoZIhvcNAQEBBQAEggEAHqiv07ehdw8+NTdM
# lNWHT0pKRg2pKVIMSVY3Cx40a8PmzVTG3wp5fcCGhzmQ85OZwFQmaQdcIh4Hg4Uk
# IHNYgIkHU0iRxsPN04rGJgGHg2pgwDdLCeVuLXjPL2H08vHgbb1boF1Rhoajdx+7
# RCmfaNAFcmH8GvP1DqwU5spCge7ijhIiIPbOUldKiyy1duOeJ53Je86JkXK/bFza
# d7Bb4GTJRmIL4vKo5gZK73bt0k4IAbM7J3mpToJTYyzhGrFp2tTuoPODnfU0OAsm
# OLl9JjtcktFkBEESlDEpdkdwsa80Jwy4CsBRyS5mJ07LX50dYZ6jVBOooT2/qKrK
# FyFETw==
# SIG # End signature block
