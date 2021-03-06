function Get-SPSite()
{
   param($url=$(throw "You must pass the url to the site"))
   new-object Microsoft.SharePoint.SPSite($url)
}
function Get-SPWeb()
{
   param($url=$(throw "You must pass the url to the web"))
   $site = Get-SPSite $url
   $site.OpenWeb()
}

$SPoshModFunctions = @("Get-SPSite","Get-SPWeb")
Export-ModuleMember -Function $SPoshModFunctions -Variable InvalidClasses