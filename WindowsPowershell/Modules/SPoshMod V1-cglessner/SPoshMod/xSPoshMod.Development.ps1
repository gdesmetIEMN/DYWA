function Copy-SPControls()
{
    ##two parameters needed 
    ##    $prjSrc  - Path to the source Web Application folder User Controls
    ##    $prjDest - Path to the SharePoint Feature project for User Controls

    param($prjSrc=$(throw "You must pass the path to the source project and folder where User Controls are developed/tested"), $prjDest=$(throw "You must pass the path to the destination project where User Controls are included in a feature"))
    trap [Exception] {  continue;}


    ##$userControlsSrc = $prjSrc;
    ##if($userControlsSrc.EndsWith("\") -eq $false) {$userControlsSrc = $userControlsSrc + "\";}
    ##$userControlsSrc = $userControlsSrc + "FairIsaac";

    $userControlsDest = $prjDest;
    if($userControlsDest.EndsWith("\") -eq $false) {$userControlsDest = $userControlsDest + "\";}
    $userControlsDest = $userControlsDest + "TEMPLATE\CONTROLTEMPLATES";

    COPY $prjSrc $userControlsDest -RECURSE -FORCE
}
function Make-SPSolution()
{
    param($solutionProject=$(throw "You must pass the project directory of the DDF file"))
    ##$solutionProject = "e:\projects\customers\<project folder>"
    
    trap [Exception] {  continue;}
    
    cd $solutionProject\SOLUTION
    
    makecab /F $solutionProject\SOLUTION\SOLUTION.ddf
}
function Add-SPSolution()
{
    param($filename=$(throw "You must pass the filename path of the solution"))
    ##$filename = "e:\projects\customers\<project folder>\SOLUTION\PACKAGE\SharePoint.wsp"
    
    trap [Exception] {  continue;}

    stsadm -o addsolution -filename $filename
}
function Get-Solutions()
{
    stsadm -o enumsolutions
}
function Get-SPSolution()
{
    param($name=$(throw "You must pass the name of the solution"))
    ##$name = SharePoint.wsp
    
    $solutions = get-solutions
    $solutionsXML = [xml]$solutions
    
    $solutionsNode = [System.Xml.XmlNode]$solutionsXML
    $solutionsNode.SelectSingleNode("Solutions/Solution[File='$name']")
}
function Deploy-SPSolution()
{
    param($name=$(throw "You must pass the name of the solution"),$url=$(throw "You must pass the url to the site for deployment"),[switch]$allowgacdeployment)
    ##$name = SharePoint.wsp
    
    if($allowgacdeployment -eq $true)
    {
        stsadm -o deploysolution -name $name -url $url -force -immediate -allowgacdeployment
    }
    else
    {
        stsadm -o deploysolution -name $name -url $url -force -immediate
    }
}
function Retract-SPSolution()
{
    param($name=$(throw "You must pass the name of the solution to retract"),$url="",[switch]$allcontenturls)
    ##$name = SharePoint.wsp
    
    if($allcontenturls -eq $true)
    {
        stsadm -o retractsolution -name $name -allcontenturls -immediate
    }
    else
    {
        if($url -eq "")
        {
            throw "You must pass the url if -allcontenturls is set to false"
        }
        else
        {
            stsadm -o retractsolution -name $name -url $url -immediate
        }
    }
}
function Delete-SPSolution()
{
    param($name=$(throw "You must pass the name of the solution to delete"))
    ##$name = SharePoint.wsp
    
    stsadm -o deletesolution -name $name
}
function test()
{
    param($p)
    
    write-host $p
}

$SPoshModFunctions = @("Copy-SPControls","Make-SPSolution","Add-SPSolution","Get-SPSolutions","Get-SPSolution","Deploy-SPSolution","Retract-SPSolution","Delete-SPSolution","test")
Export-ModuleMember -Function $SPoshModFunctions -Variable InvalidClasses