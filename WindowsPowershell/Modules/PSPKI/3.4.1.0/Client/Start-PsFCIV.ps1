function Start-PsFCIV {
<#
.ExternalHelp PSPKI.Help.xml
#>
[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true, Position = 0)]
		[IO.DirectoryInfo]$Path,
		[Parameter(Mandatory = $true, Position = 1, ParameterSetName = '__xml')]
		[string]$XML,
		[Parameter(Position = 2)]
		[string]$Include = "*",
		[Parameter(Position = 3)]
		[string[]]$Exclude,
		[ValidateSet("Rename", "Delete")]
		[string]$Action,
		[ValidateSet("Bad", "Locked", "Missed", "New", "Ok", "Unknown", "All")]
		[String[]]$Show,
		[ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
		[AllowEmptyCollection()]
		[String[]]$HashAlgorithm = "SHA1",
		[switch]$Recurse,
		[switch]$Rebuild,
		[switch]$Quiet,
		[switch]$NoStatistic,
		[Parameter(ParameterSetName = '__online')]
		[switch]$Online
	)

#region C# wrappers
Add-Type @"
using System;
using System.Collections.Generic;
using System.Xml.Serialization;
namespace PsFCIV {
	public class StatTable {
		public List<String> Total = new List<String>();
		public List<String> New = new List<String>();
		public List<String> Ok = new List<String>();
		public List<String> Bad = new List<String>();
		public List<String> Missed = new List<String>();
		public List<String> Locked = new List<String>();
		public List<String> Unknown = new List<String>();
		public int Del;
	}
	public class IntStatTable {
		public Int32 Total;
		public Int32 New;
		public Int32 Ok;
		public Int32 Bad;
		public Int32 Missed;
		public Int32 Locked;
		public Int32 Unknown;
		public Int32 Del;
	}
	[XmlType(AnonymousType = true)]
	[XmlRoot(Namespace = "", IsNullable = false)]
	public class FCIV {
		public FCIV() { FILE_ENTRY = new List<FCIVFILE_ENTRY>(); }
		
		[XmlElement("FILE_ENTRY")]
		public List<FCIVFILE_ENTRY> FILE_ENTRY { get; set; }
	}
	[XmlType(AnonymousType = true)]
	public class FCIVFILE_ENTRY {
		public FCIVFILE_ENTRY() { }
		public FCIVFILE_ENTRY(string path) { name = path; }

		public String name { get; set; }
		public UInt64 Size { get; set; }
		public String TimeStamp { get; set; }
		public String MD5 { get; set; }
		public String SHA1 { get; set; }
		public String SHA256 { get; set; }
		public String SHA384 { get; set; }
		public String SHA512 { get; set; }

		public override Int32 GetHashCode() { return name.GetHashCode(); }
		public override Boolean Equals(Object other) {
			if (ReferenceEquals(null, other) || other.GetType() != GetType()) { return false; }
			return other.GetType() == GetType() && String.Equals(name, ((FCIVFILE_ENTRY)other).name);
		}
	}
}
"@ -Debug:$false -Verbose:$false -ReferencedAssemblies "System.Xml"
Add-Type -AssemblyName System.Xml
#endregion
	
	if ($PSBoundParameters.Verbose) {$VerbosePreference = "continue"}
	if ($PSBoundParameters.Debug) {$DebugPreference = "continue"}
	$oldverb = $host.PrivateData.VerboseForegroundColor
	$olddeb = $host.PrivateData.DebugForegroundColor
	# preserving current path
	$oldpath = $pwd.Path
	$Exclude += $XML

	if (Test-Path -LiteralPath $path) {
		Set-Location -LiteralPath $path
		if ($pwd.Provider.Name -ne "FileSystem") {
			Set-Location $oldpath
			throw "Specified path is not filesystem path. Try again!"
		}
	} else {throw "Specified path not found."}
	
	# statistic variables
	$sum = $new = New-Object PsFCIV.FCIV
	# creating statistics variable with properties. Each property will contain file names (and paths) with corresponding status.
	$global:stats = New-Object PsFCIV.StatTable
	$script:statcount = New-Object PsFCIV.IntStatTable
	
	# lightweight proxy function for Get-ChildItem cmdlet
	function dirx ([string]$Path, [string]$Filter, [string[]]$Exclude, $Recurse, [switch]$Force) {
		Get-ChildItem @PSBoundParameters -ErrorAction SilentlyContinue | Where-Object {!$_.psiscontainer}
	}	
	# internal function that will check whether the file is locked. All locked files are added to a group with 'Unknown' status.
	function __filelock ($file) {
		$locked = $false
		trap {Set-Variable -name locked -value $true -scope 1; continue}
		$inputStream = New-Object IO.StreamReader $file.FullName
		if ($inputStream) {$inputStream.Close()}
		if ($locked) {
			$host.PrivateData.VerboseForegroundColor = "Yellow"
			$host.PrivateData.DebugForegroundColor = "Yellow"
			Write-Verbose "File $($file.Name) is locked. Skipping this file.."
			Write-Debug "File $($file.Name) is locked. Skipping this file.."
			__statcounter $filename Locked
		}
		$locked
	}	
	# internal function to generate UI window with results by using Out-GridView cmdlet.
	function __formatter ($props, $max) {
		$total = @($input)
		foreach ($property in $props) {
			$(for ($n = 0; $n -lt $max; $n++) {
				$total[0] | Select-Object @{n = $property; e = {$_.$property[$n]}}
			}) | Out-GridView -Title "File list by category: $property"
		}
	}
	# internal hasher
	function __hashbytes ($type, $file) {
		$hasher = [Security.Cryptography.HashAlgorithm]::Create($type)
		$inputStream = New-Object IO.StreamReader $file.FullName
		$hashBytes = $hasher.ComputeHash($inputStream.BaseStream)
		$hasher.Clear()
		$inputStream.Close()
		$hashBytes
	}
	# internal function which reads the XML file (if exist).
	function __fromxml ($xml) {
	# reading existing XML file and selecting required properties
		if (!(Test-Path -LiteralPath $XML)) {return New-Object PsFCIV.FCIV}
		try {
			$fs = New-Object IO.FileStream $XML, "Open"
			$xmlser = New-Object System.Xml.Serialization.XmlSerializer ([Type][PsFCIV.FCIV])
			$sum = $xmlser.Deserialize($fs)
			$fs.Close()
			$sum
		} catch {
			Write-Error -Category InvalidData -Message "Input XML file is not valid FCIV XML file."
		} finally {
			if ($fs -ne $null) {$fs.Close()}
		}
		
	}
	# internal xml writer
	function __writexml ($sum) {
		if ($sum.FILE_ENTRY.Count -eq 0) {
			$host.PrivateData.VerboseForegroundColor = "Yellow"
			$host.PrivateData.DebugForegroundColor = "Yellow"
			Write-Verbose "There is no data to write to XML database."
			Write-Debug "There is no data to write to XML database."
		} else {
			$host.PrivateData.DebugForegroundColor = "Cyan"
			Write-Debug "Preparing to DataBase file creation..."
			try {
				$fs = New-Object IO.FileStream $XML, "Create"
				$xmlser = New-Object System.Xml.Serialization.XmlSerializer ([Type][PsFCIV.FCIV])
				$xmlser.Serialize($fs,$sum)
			} finally {
				if ($fs -ne $null) {$fs.Close()}
			}
			Write-Debug "DataBase file created..."
		}
	}
	# internal function to create XML entry object for a file.
	function __makeobject ($file, [switch]$NoHash, [switch]$hex) {
		$host.PrivateData.DebugForegroundColor = "Yellow"
		Write-Debug "Starting object creation for '$($file.FullName)'..."
		$object = New-Object PsFCIV.FCIVFILE_ENTRY
		$object.name = $file.FullName -replace [regex]::Escape($($pwd.ProviderPath + "\"))
		$object.Size = $file.Length
		# use culture-invariant date/time format.
		$object.TimeStamp = "$($file.LastWriteTime.ToUniversalTime())"
		if (!$NoHash) {
		# calculating appropriate hash and convert resulting byte array to a Base64 string
			foreach ($hash in "MD5", "SHA1", "SHA256", "SHA384", "SHA512") {
				if ($HashAlgorithm -contains $hash) {
					Write-Debug "Calculating '$hash' hash..."
					$hashBytes = __hashbytes $hash $file
					if ($hex) {
						$object.$hash = -join ($hashBytes | Foreach-Object {"{0:X2}" -f $_})
					} else {
						Write-Debug ("Calculated hash value: " + (-join ($hashBytes | Foreach-Object {"{0:X2}" -f $_})))
						$object.$hash = [System.Convert]::ToBase64String($hashBytes)
					}
				}
			}
		}
		Write-Debug "Object created!"
		$object
	}	
	# internal function that calculates current file hash and formats it to an octet string (for example, B926D7416E8235E6F94F756E9F3AE2F33A92B2C4).
	function __precheck ($entry, $file, $HashAlgorithm) {
		$host.PrivateData.DebugForegroundColor = "Yellow"
		if ($HashAlgorithm.Length -gt 0) {
			$SelectedHash = $HashAlgorithm
		} else {
			:outer foreach ($hash in "SHA512", "SHA384", "SHA256", "SHA1", "MD5") {
				if ($entry.$hash) {$SelectedHash = $hash; break outer}
			}
		}
		$host.PrivateData.DebugForegroundColor = "Green"
		Write-Debug "Selected hash: $hash"
		-join ($(__hashbytes $SelectedHash $file) | ForEach-Object {"{0:X2}" -f $_})
		$SelectedHash
	}
	# process -Action parameter to perform an action against bad file (if actual file properties do not match the record in XML).
	function __takeaction ($file, $Action) {
		switch ($Action) {
			"Rename" {Rename-Item $file $($file.FullName + ".bad")}
			"Delete" {Remove-Item $file -Force}
		}
	}	
	# core file verification function.
	function __checkfiles ($entry, $file, $Action) {
		if (($file.Length -eq $entry.Size) -and ("$($file.LastWriteTime.ToUniversalTime())" -eq $entry.TimeStamp)) {
			$hexhash = __precheck $entry $file $HashAlgorithm
			$ActualHash = -join ([Convert]::FromBase64String($entry.($hexhash[1])) | ForEach-Object {"{0:X2}" -f $_})
			if (!$ActualHash) {
				$host.PrivateData.VerboseForegroundColor = "Red"
				Write-Verbose "XML database entry does not contains '$($hexhash[1])' hash value for the entry '$($entry.name)'."
				__statcounter $entry.name Unknown
				return
			} elseif ($ActualHash -eq $hexhash[0]) {
				$host.PrivateData.VerboseForegroundColor = $Host.PrivateData.DebugForegroundColor = "Green"
				Write-Debug "File hash: $ActualHash"
				Write-Verbose "File '$($file.name)' is ok."
				__statcounter $entry.name Ok
				return
			} else {
				$host.PrivateData.DebugForegroundColor = "Red"
				Write-Debug "File '$($file.name)' failed hash verification.
					Expected hash: $hexhash
					Actual hash: $ActualHash"
				__statcounter $entry.name Bad
				if ($Action) {__takeaction $file $Action}
			}
		} else {
			$host.PrivateData.VerboseForegroundColor = $Host.PrivateData.DebugForegroundColor = "Red"
			Write-Verbose "File '$($file.FullName)' size or Modified Date/Time mismatch."
			Write-Debug "Expected file size is: $($entry.Size) byte(s), actual size is: $($file.Length) byte(s)."
			Write-Debug "Expected file modification time is: $($entry.TimeStamp), actual file modification time is: $($file.LastWriteTime.ToUniversalTime())"
			__statcounter $entry.name Bad
			if ($Action) {__takeaction $file $Action}
		}
	}
	# internal function to calculate resulting statistics and show if if necessary.	
	function __stats {
	# if -Show parameter is presented we display selected groups (Total, New, Ok, Bad, Missed, Unknown)
		if ($show -and !$NoStatistic) {
			if ($Show -eq "All" -or $Show.Contains("All")) {
				$global:stats | __formatter "Bad", "Locked", "Missed", "New", "Ok", "Unknown" $script:statcount.Total
			} else {
				$global:stats | Select-Object $show | __formatter $show $script:statcount.Total
			}			
		}
		# script work in numbers
		if (!$Quiet) {
			Write-Host ----------------------------------- -ForegroundColor Green
			if ($Rebuild) {
				Write-Host Total entries processed: $script:statcount.Total -ForegroundColor Cyan
				Write-Host Total removed unused entries: $script:statcount.Del -ForegroundColor Yellow
			} else {Write-Host Total files processed: $script:statcount.Total -ForegroundColor Cyan}
			Write-Host Total new added files: $script:statcount.New -ForegroundColor Green
			Write-Host Total good files: $script:statcount.Ok -ForegroundColor Green
			Write-Host Total bad files: $script:statcount.Bad -ForegroundColor Red
			Write-Host Total unknown status files: $script:statcount.Unknown -ForegroundColor Yellow
			Write-Host Total missing files: $script:statcount.Missed -ForegroundColor Yellow
			Write-Host Total locked files: $script:statcount.Locked -ForegroundColor Yellow
			Write-Host ----------------------------------- -ForegroundColor Green
		}
		# restore original variables
		Set-Location -LiteralPath $oldpath
		$host.PrivateData.VerboseForegroundColor = $oldverb
		$host.PrivateData.DebugForegroundColor = $olddeb
		$exit = 0
		# create exit code depending on check status
		if ($Rebuild) {$exit = [int]::MaxValue} else {
			if ($script:statcount.Bad -ne 0) {$exit += 1}
			if ($script:statcount.Missed -ne 0) {$exit += 2}
			if ($script:statcount.Unknown -ne 0) {$exit += 4}
			if ($script:statcount.Locked -ne 0) {$exit += 8}
		}
		if ($Quiet) {exit $exit}
	}
	# internal function to update statistic counters.
	function __statcounter ($filename, $status) {
		$script:statcount.$status++
		$script:statcount.Total++
		if (!$NoStatistic) {
			$global:stats.$status.Add($filename)
		}
	}
	if ($Online) {
		$host.PrivateData.DebugForegroundColor = "White"
		Write-Debug "Online mode ON"
		dirx -Path .\* -Filter $Include -Exclude $Exclude $Recurse -Force | ForEach-Object {
			$host.PrivateData.VerboseForegroundColor = $Host.UI.RawUI.ForegroundColor
			Write-Verbose "Perform file '$($_.fullName)' checking."
			$file = Get-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
			if (__filelock $file) {return}
			__makeobject $file -hex
		}
		return
	}

	<#
	in this part we perform XML file update by removing entries for non-exist files and
	adding new entries for files that are not in the database.
	#>
	if ($Rebuild) {
		$host.PrivateData.DebugForegroundColor = "White"
		Write-Debug "Rebuild mode ON"
		if (Test-Path -LiteralPath $xml) {
			$old = __fromxml $xml
		} else {
			Set-Location $oldpath
			throw "Unable to find XML file. Please, run the command without '-Rebuild' switch."
		}
		$interm = New-Object PsFCIV.FCIV
		# use foreach-object instead of where-object to keep original types.
		$host.PrivateData.VerboseForegroundColor = $host.UI.RawUI.ForegroundColor
		Write-Verbose "Perform DB file cleanup from non-existent items."
		$old.FILE_ENTRY | ForEach-Object {
			if ((Test-Path -LiteralPath $_.name)) {
				if ($_.name -eq $xml) {
					$host.PrivateData.DebugForegroundColor = "Yellow"
					Write-Debug "File '$($_.name)' is DB file. Removed."
				} else {
					$interm.FILE_ENTRY.Add($_)
				}
			} else {
				$host.PrivateData.DebugForegroundColor = "Yellow"
				Write-Debug "File '$($_.name)' does not exist. Removed."
			}
		}
		$script:statcount.Del = $interm.Length
		$script:statcount.Total = $old.FILE_ENTRY.Count - $interm.Length
		dirx -Path .\* -Filter $Include -Exclude $Exclude $Recurse -Force | ForEach-Object {
			$host.PrivateData.VerboseForegroundColor = $host.UI.RawUI.ForegroundColor
			Write-Verbose "Perform file '$($_.FullName)' checking."
			$file = Get-Item -LiteralPath $_.FullName -Force
			if (__filelock $file) {return}
			$filename = $file.FullName -replace [regex]::Escape($($pwd.providerpath + "\"))
			$host.PrivateData.VerboseForegroundColor = "Green"
			if ($interm.FILE_ENTRY.Contains((New-Object PsFCIV.FCIVFILE_ENTRY $filename))) {
				Write-Verbose "File '$filename' already exist in XML database. Skipping."
				return
			} else {
				$new.FILE_ENTRY.Add((__makeobject $file))
				Write-Verbose "File '$filename' is added."
				__statcounter $filename New
			}
		}
		$interm.FILE_ENTRY.AddRange($new.FILE_ENTRY)
		__writexml $interm
		__stats
		return
	}
	
	# this part contains main routine
	$sum = __fromxml $xml
	<#
	check XML file format. If Size property of the first element is zero, then the file was generated by
	original FCIV.exe tool. In this case we transform existing XML to a new PsFCIV format by adding new
	properties. Each record is checked against hashes stored in the source XML file. If hash check fails,
	an item is removed from final XML.
	#>
	if ($sum.FILE_ENTRY.Count -gt 0 -and $sum.FILE_ENTRY[0].Size -eq 0) {
		# 
		if ($PSBoundParameters.ContainsKey("HashAlgorithm")) {$HashAlgorithm = $HashAlgorithm[0].ToUpper()} else {$HashAlgorithm = @()}
		$host.PrivateData.DebugForegroundColor = "White"
		Write-Debug "FCIV (compatibility) mode ON"
		if ($HashAlgorithm -and $HashAlgorithm -notcontains "sha1" -and $HashAlgorithm -notcontains "md5") {
			throw "Specified hash algorithm (or algorithms) is not supported. For native FCIV source, use MD5 and/or SHA1."
		}
		for ($index = 0; $index -lt $sum.FILE_ENTRY.Count; $index++) {
			$host.PrivateData.VerboseForegroundColor = $host.UI.RawUI.ForegroundColor
			Write-Verbose "Perform file '$($sum.FILE_ENTRY[$index].name)' checking."
			$filename = $sum.FILE_ENTRY[$index].name
			# check if the path is absolute and matches current path. If the path is absolute and does not belong to
			# current path -- skip this entry.
			if ($filename.Contains(":") -and $filename -notmatch [regex]::Escape($pwd.ProviderPath)) {return}
			# if source file name record contains absolute path, and belongs to the current pathe,
			# just strip base path. New XML format uses relative paths only.
			if ($filename.Contains(":")) {$filename = $filename -replace ([regex]::Escape($($pwd.ProviderPath + "\")))}
			# Test if the file exist. If the file does not exist, skip the current entry and process another record.
			if (!(Test-Path -LiteralPath $filename)) {
				$host.PrivateData.VerboseForegroundColor = "Yellow"
				Write-Verbose "File '$filename' not found. Skipping."
				__statcounter $filename Missed
				return
			}
			# get file item and test if it is not locked by another application
			$file = Get-Item -LiteralPath $filename -Force -ErrorAction SilentlyContinue
			if (__filelock $file) {return}
			# create new-style entry record that stores additional data: file length and last modification timestamp.
			$entry = __makeobject $file -NoHash
			$entry.name = $filename
			# process current hash entries and copy required hash values to a new entry object.
			"SHA1", "MD5" | ForEach-Object {$entry.$_ = $sum.FILE_ENTRY[$index].$_}
			$sum.FILE_ENTRY[$index] = $entry
			__checkfiles $newentry $file $Action
		}
		# we are done. Overwrite XML, display stats and exit.
		__writexml $sum
		# display statistics and exit right now.
		__stats
	}
	# if XML file exist, proccess and check all records. XML file will not be modified.
	if ($sum.FILE_ENTRY.Count -gt 0) {
		$host.PrivateData.DebugForegroundColor = "White"
		Write-Debug "Native PsFCIV mode ON"
		# this part is executed only when we want to process certain file. Wildcards are not allowed.
		if ($Include -ne "*") {
			$sum.FILE_ENTRY | Where-Object {$_.name -like $Include} | ForEach-Object {
				$host.PrivateData.VerboseForegroundColor = $host.UI.RawUI.ForegroundColor
				Write-Verbose "Perform file '$($_.name)' checking."
				$entry = $_
				# calculate the hash if the file exist.
				if (Test-Path -LiteralPath $entry.name) {
					# and check file integrity
					$file = Get-Item -LiteralPath $entry.name -Force -ErrorAction SilentlyContinue
					__checkfiles $entry $file $Action
				} else {
					# if there is no record for the file, skip it and display appropriate message
					$host.PrivateData.VerboseForegroundColor = "Yellow"
					Write-Verbose "File '$filename' not found. Skipping."
					__statcounter $entry.name Missed
				}
			}
		} else {
			$sum.FILE_ENTRY | ForEach-Object {
				<#
				to process files only in the current directory (without subfolders), we remove items
				that contain slashes from the process list and continue regular file checking.
				#>
				if (!$Recurse -and $_.name -match "\\") {return}
				$host.PrivateData.VerboseForegroundColor = $host.UI.RawUI.ForegroundColor
				Write-Verbose "Perform file '$($_.name)' checking."
				$entry = $_
				if (Test-Path -LiteralPath $entry.name) {
					$file = Get-Item -LiteralPath $entry.name -Force -ErrorAction SilentlyContinue
					__checkfiles $entry $file $Action
				} else {
					$host.PrivateData.VerboseForegroundColor = "Yellow"
					Write-Verbose "File '$($entry.name)' not found. Skipping."
					__statcounter $entry.name Missed
				}
			}
		}
	} else {
		# if there is no existing XML DB file, start from scratch and create a new one.
		$host.PrivateData.DebugForegroundColor = "White"
		Write-Debug "New XML mode ON"

		dirx -Path .\* -Filter $Include -Exclude $Exclude $Recurse -Force | ForEach-Object {
			$_
			# $host.PrivateData.VerboseForegroundColor = $Host.UI.RawUI.ForegroundColor
			# Write-Verbose "Perform file '$($_.fullName)' checking."
			# $file = Get-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
			# if (__filelock $file) {return}
			# $entry = __makeobject $file
			# $sum.FILE_ENTRY.Add($entry)
			# __statcounter $entry.name New
		}
		__writexml $sum
	}
	__stats
}
# SIG # Begin signature block
# MIIcgAYJKoZIhvcNAQcCoIIccTCCHG0CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCh54G+7BnjUc2T
# VlNgo0WdRcbYHLAtcSrMGdoBXdwbhqCCF4owggUTMIID+6ADAgECAhAJwnVp5a70
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
# DAYKKwYBBAGCNwIBFTAvBgkqhkiG9w0BCQQxIgQgpwLhyhhxKt5syg/Vuubf8G9n
# /9o6uAYWCKV4wLO1ObAwDQYJKoZIhvcNAQEBBQAEggEAJkOTNagKUta2jab51aMX
# vmo8YjbNiGokSoBJ0mX6Xb1UMD463wtyh6J7eQaYmhUgQYtlEqkIPs8+KJlm/PGM
# 9kbrXTZhBKvrkVrD0hTpTSQj7mLfutZrKj1TLQPZytKmvNvG0iMzggG8UpxM9ZIa
# 6+1eESakMulJDZEgHBLXrIotBdKY8K3Ay8GHDaL/jpEWlO2qJpPP2dtpNS3Gr5ht
# 8jKa8shYr7ZRPalpgsD3dpnsDvQ46uspomCUBm0My0oIwAw2bazImfVjpcC0jk5o
# VLycaNnYhSmRADvZdNxMofnColwfObnMsnGZoPHA6Pnb9WIukvG8Sm9moaYmuNc3
# d6GCAg8wggILBgkqhkiG9w0BCQYxggH8MIIB+AIBATB2MGIxCzAJBgNVBAYTAlVT
# MRUwEwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5j
# b20xITAfBgNVBAMTGERpZ2lDZXJ0IEFzc3VyZWQgSUQgQ0EtMQIQAwGaAjr/WLFr
# 1tXq5hfwZjAJBgUrDgMCGgUAoF0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAc
# BgkqhkiG9w0BCQUxDxcNMTgxMDIyMTYyNzI0WjAjBgkqhkiG9w0BCQQxFgQU4vDI
# Cl3NJKgicVVTfMyGjzMKME8wDQYJKoZIhvcNAQEBBQAEggEAYFyFzR8vY6NCJRn/
# u+6fdQQMwFXa4Pecf7bkR4h6/jTiloU3rU1Wv8cbaJ/St/Chhv6l6Z2FqB6iTL25
# Yj6GIeUWZhu1ZoDIVZ3jjyt6S6mHIc4PFHHlugL+pk9OHscCwpvafmIHPfdTvPvB
# tK5KwE5dn4S+zw6wwUP3UAzRhpHOAOUHBk6CHRe/s3QTtguirfIxSToI1C/1rqjZ
# yRqMaTXbjB4tcP3yiDT22oV/2ZS3zuxiP8tojkmnDsNFR632SZHi4np/NjQGR9GY
# oyoDMnqFOCDv0KWS+ywjEtrAtxmVRw/F7lmS/hS7NQRx/v7gN801aFTuMgr7uN/a
# 3z/mwA==
# SIG # End signature block
