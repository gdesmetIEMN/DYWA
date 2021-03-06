function Get-Site()
{
   param($url=$(throw "You must pass the url to the site"))
   new-object Microsoft.SharePoint.SPSite($url)
}
function Get-Web()
{
   param($url=$(throw "You must pass the url to the web"))
   $site = get-site $url
   $site.OpenWeb()
}

$SPoshModFunctions = @("Get-Site","Get-Web")
Export-ModuleMember -Function $SPoshModFunctions -Variable InvalidClasses