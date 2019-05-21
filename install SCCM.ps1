<#
# Install SCCM (Current Branch) version 1902, 2019/4/23 Niall Brady, https://www.windows-noob.com
#
# This script:            Optionally extends the schema for SCCM, downloads pre-requisites, and then Installs SCCM (Current Branch) version 1802.
# Before running:         Make sure the $SCCMPath variable points to the location of the 1802 ISO (or extracted media). Edit the variables as necessary (lines 16-45). 
# Usage:                  Run this script on the ConfigMgr Primary Server as a user with local Administrative permissions on the server
#>
  If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole] “Administrator”))

    {
        Write-Warning “You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!”
        Break
    }

# below variables are customizable
$SourcePath = "C:\Source"
# where is the media mounted ?
$SCCMPath = "C:\Source\SCCM1902"
$PrerequisitesPath = "$SourcePath" + "\SCCMPrereqs"
$DestinationServer = "CM01.windowsnoob.lab.local"
# Installation specific variables
$Action="InstallPrimarySite"
# enter your product ID (25 chars) or use EVAL for the evaluation version, to change from EVAL to the full edition see https://www.niallbrady.com/2016/12/08/how-can-i-change-system-center-configuration-manager-from-an-eval-edition-to-a-licensed-edition/
$ProductID="EVAL"
$SiteCode="P01"
$Sitename="windows-noob.com Primary Site"
$SMSInstallDir="D:\SCCM"
$SDKServer=$DestinationServer
$RoleCommunicationProtocol="HTTPorHTTPS"
$ClientsUsePKICertificate="0"
$PrerequisiteComp="1"
$ManagementPoint=$DestinationServer
$ManagementPointProtocol="HTTP"
$DistributionPoint=$DestinationServer
$DistributionPointProtocol="HTTP"
$DistributionPointInstallIIS="0"
$AdminConsole="1"
$JoinCEIP="0"
$SQLServerName=$DestinationServer
$DatabaseName="CM_P01"
$SQLSSBPort="4022"
$CloudConnector="1"
$CloudConnectorServer=$DestinationServer
$UseProxy="0"
$ProxyName=""
$ProxyPort=""
$SysCenterId=""

# please don't edit below this line

write-host ""
write-host "Starting the installation of System Center Configuration Manager."
write-host ""
write-host "As part of this installation, you will be asked if want to extend the Active Directory Schema. If you answer Yes then you'll need to provide administrative credentials to extend the schema for SCCM, these credentials are only used for the schema extension. If you've already extended the schema previously then you do not need to do it again." -ForegroundColor Yellow
write-host "" -foregroundcolor white

# Check for SCCM source files
write-host "Looking for ConfigMgr media in '$SCCMPath'..." -nonewline
if (Test-Path "$SCCMPath\SMSSETUP"){
Write-Host "done!" -ForegroundColor Green
 } else {
write-host "Error" -ForegroundColor Red
write-host "Please extract the SCCM media to '$SCCMPath' and then try running this script again..."
break}

$answer = Read-Host "Extend the schema ?" 

while("yes","no","y","n" -notcontains $answer)
{
	$answer = Read-Host "Yes No"
}
if ($answer -eq "No" -or $answer -eq "n"){
write-host "skipping schema extension"
}
else
{   $Credential = $Host.ui.PromptForCredential("Need credentials", "Please enter suitable administrative credentials for extending the schema.", "", "NetBiosUserName")
    # extend the schema 
    write-host "about to extend the schema..." -nonewline
    $filepath = "$SCCMPath\SMSSETUP\bin\X64\extadsch.exe"

Try
    {Start-Process "$filepath" -Credential $Credential | Out-Null}
    catch
    {Write-Host "Sorry but there was an error extending the schema, are you sure the credentials were correct!" -ForegroundColor red
    break}
    Write-Host "done!" -ForegroundColor Green
    Start-Sleep 30
}

write-host "Checking for'$PrerequisitesPath' folder..." -nonewline

# Check for prerequisites download path folder, if not present create it
if (Test-Path "$PrerequisitesPath"){
 Write-Host "done!" -ForegroundColor Green
 #write-host "The folder '$PrerequisitesPath' already exists, therefore this script will not download the prerequisites."
 
 } else {
mkdir "$PrerequisitesPath" | out-null
Write-Host "done!" -ForegroundColor Green
# start the SCCM prerequisite downloader
write-host "Downloading SCCM version prerequisite files..." -nonewline
$filepath = "$SCCMPath\SMSSETUP\bin\X64\SETUPDL.exe"
# remove /NoUI if you want to see the download progress UI
$Parms = "/NoUI `"$PrerequisitesPath`""
$Prms = $Parms.Split(" ")

Try
{& "$filepath" $Prms | Out-Null}
catch
{Write-Host "error!" -ForegroundColor red
break}
Write-Host "done!" -ForegroundColor Green
}

# do not edit below this line

$conffile= @"
[Identification]
Action="$Action"

[SABranchOptions]
SAActive=1
CurrentBranch=1

[Options]
ProductID="$ProductID"
SiteCode="$SiteCode"
SiteName="$Sitename"
SMSInstallDir="$SMSInstallDir"
SDKServer="$SDKServer"
RoleCommunicationProtocol="$RoleCommunicationProtocol"
ClientsUsePKICertificate="$ClientsUsePKICertificate"
PrerequisiteComp="$PrerequisiteComp"
PrerequisitePath="$PrerequisitesPath"
ManagementPoint="$ManagementPoint"
ManagementPointProtocol="$ManagementPointProtocol"
DistributionPoint="$DistributionPoint"
DistributionPointProtocol="$DistributionPointProtocol"
DistributionPointInstallIIS="$DistributionPointInstallIIS"
AdminConsole="$AdminConsole"
JoinCEIP="$JoinCEIP"

[SQLConfigOptions]
SQLServerName="$SQLServerName"
DatabaseName="$DatabaseName"
SQLSSBPort="$SQLSSBPort"

[CloudConnectorOptions]
CloudConnector="$CloudConnector"
CloudConnectorServer="$CloudConnectorServer"
UseProxy="$UseProxy"
ProxyName="$ProxyName"
ProxyPort="$ProxyPort"

[SystemCenterOptions]
SysCenterId="$SysCenterId"

[HierarchyExpansionOption]
"@

# Check for Script Directory & file
if (Test-Path "$SourcePath"){
 write-host "The folder '$SourcePath' already exists, will not recreate it."
 } else {
mkdir "$SourcePath"
}
if (Test-Path "$SourcePath\ConfigMgrAutoSave.ini"){
 write-host "The file '$SourcePath\ConfigMgrAutoSave.ini' already exists, removing..."
 Remove-Item -Path "$SourcePath\ConfigMgrAutoSave.ini" -Force
 } else {

}
# Create file:
write-host "Creating '$SourcePath\ConfigMgrAutoSave.ini'..." -nonewline
New-Item -Path "$SourcePath\ConfigMgrAutoSave.ini" -ItemType File -Value $Conffile | Out-Null
Write-Host "done!" -ForegroundColor Green

# start the SCCM installer
write-host "installing SCCM (please wait)..." -nonewline
$filepath = "$SCCMPath\SMSSETUP\bin\X64\Setup.exe"
$Parms = "  /script $SourcePath\ConfigMgrAutoSave.ini"
$Prms = $Parms.Split(" ")
Try
{& "$filepath" $Prms | Out-Null}
catch
{Write-Host "error!" -ForegroundColor red
break}
Write-Host "done!" -ForegroundColor Green


# exit script
write-host "Exiting script, goodbye."

