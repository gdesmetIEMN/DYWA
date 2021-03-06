function Get-Farm()
{
    [Microsoft.SharePoint.Administration.SPFarm]::Local
}
function Get-WebApplication()
{
    param($url=$(throw "You must specify the url to the web application"))
    return [Microsoft.SharePoint.Administration.SPWebApplication]::Lookup($url);
}

$SPoshModFunctions = @("Get-Farm","Get-WebApplication")
Export-ModuleMember -Function $SPoshModFunctions -Variable InvalidClasses