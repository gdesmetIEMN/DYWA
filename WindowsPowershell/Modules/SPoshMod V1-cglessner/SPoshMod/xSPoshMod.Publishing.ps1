function Write-More()
{
   write-host "more";
}

$SPoshModFunctions = @("Write-More")
Export-ModuleMember -Function $SPoshModFunctions -Variable InvalidClasses