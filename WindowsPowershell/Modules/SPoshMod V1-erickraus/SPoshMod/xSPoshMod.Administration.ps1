function Get-SPFarm()
{
    [Microsoft.SharePoint.Administration.SPFarm]::Local
}
function Get-SPWebApplication()
{
    param($url=$(throw "You must specify the url to the web application"))
    return [Microsoft.SharePoint.Administration.SPWebApplication]::Lookup($url);
}
function Get-SPEvents()
{
	param($limit=20)
	
	Get-EventLog -LogName Application -Source '*sharepoint*' -newest $limit
}

$SPoshModFunctions = @("Get-SPFarm","Get-SPWebApplication","Get-SPEvents")
Export-ModuleMember -Function $SPoshModFunctions -Variable InvalidClasses