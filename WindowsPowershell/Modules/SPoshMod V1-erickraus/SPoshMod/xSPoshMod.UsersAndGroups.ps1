##Gets all users (unique) that belong to a site that has a site collection or subsite Premium (Enterprie) feature enabled
function Get-SPUsersInEnterpriseSites()
{
    param($url=$(throw "You must specify the url to the web application"),$filename=$(throw "You must specify the filename to output xml"))
	#PremiumSite
	$feature1 = new-object System.Guid("8581a8a7-cf16-4770-ac54-260265ddb0b2")
	#PremiumSiteStapling
	$feature2 = new-object System.Guid("a573867a-37ca-49dc-86b0-7d033a7ed2c8")
	#PremiumWeb
	$feature3 = new-object System.Guid("0806d127-06e6-447a-980e-2e90b03101b8")
	#PremiumWebApplication
	$feature4 = new-object System.Guid("0ea1c3b6-6ac0-44aa-9f3f-05e8dbe6d70b")

	$userskeep = @{}

    $xmlTemplate = "<Users><User><Site/></User></Users>"
    $xml = new-object XML
    $xml.LoadXml($xmlTemplate)
    
	$webapp = Get-SPWebApplication($url)
	
    foreach($site in $webapp.Sites)
	{
		$premiumsitefeatures = ($site.Features | where-object {$_.DefinitionId -eq $feature1 -or $_.DefinitionId -eq $feature2 -or $_.DefinitionId -eq $feature3 -or $_.DefinitionId -eq $feature4})

		foreach($web in $site.AllWebs)
		{
            #not guaranteed user is in
			$webfeatures = $web.Features
			$premiumwebfeatures = ($webfeatures | where-object {$_.DefinitionId -eq $feature1 -or $_.DefinitionId -eq $feature2 -or $_.DefinitionId -eq $feature3 -or $_.DefinitionId -eq $feature4})

			if($premiumsitefeatures -ne $null -or $premiumwebfeatures -ne $null)
			{
				#enterprise somewhere
                foreach($userobj in $web.Users)
				{             
                    
                    $username = $userobj.LoginName
                    
                    $siteUrl = $web.Url
                        
					$found = $xml.FirstChild.SelectSingleNode("/Users/User[@UserName='$username']")
                    if($found.Attributes -ne $null)
                    {
                        #found
                        $root = $xml.FirstChild
                        $newSite = $root.FirstChild.FirstChild.Clone()
                        $newSite.Attributes.Append($xml.CreateAttribute("Url"))
                        $newSite.Url = $siteUrl
                        if($premiumsitefeatures -ne $null)
                        {
                            $newSite.Attributes.Append($xml.CreateAttribute("SiteEnabled"))
                            $newSite.SiteEnabled = "True"
                        }
                        if($premiumwebfeatures  -ne $null)
                        {
                            $newSite.Attributes.Append($xml.CreateAttribute("WebEnabled"))
                            $newSite.WebEnabled = "True"
                        }
                        $found.AppendChild($newSite)
                    }
                    else
                    {
                        #create new
                        $root = $xml.FirstChild
                        $newUser = $root.FirstChild.CloneNode($false)
                        $newUser.Attributes.Append($xml.CreateAttribute("UserName"))
                        $newUser.UserName = $username
                        
                        #found
                        $newSite = $root.FirstChild.FirstChild.Clone()
                        $newSite.Attributes.Append($xml.CreateAttribute("Url"))
                        $newSite.Url = $siteUrl
                        if($premiumsitefeatures -ne $null)
                        {
                            $newSite.Attributes.Append($xml.CreateAttribute("SiteEnabled"))
                            $newSite.SiteEnabled = "True"
                        }
                        if($premiumwebfeatures  -ne $null)
                        {
                            $newSite.Attributes.Append($xml.CreateAttribute("WebEnabled"))
                            $newSite.WebEnabled = "True"
                        }
                        $newUser.AppendChild($newSite)
                        
                        $xml.FirstChild.AppendChild($newUser)
                    }
				}
			}
		}
				
	}

    
    $xml.Save($filename)
}

$SPoshModFunctions = @("Get-SPUsersInEnterpriseSites")
Export-ModuleMember -Function $SPoshModFunctions -Variable InvalidClasses