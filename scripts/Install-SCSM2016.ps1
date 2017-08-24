<#
 
.SYNOPSIS
This script installs Service Manager 2016 and necessary prerequisites.
 
.DESCRIPTION
All necessary prerequisites will be downloaded to the specified working folder and installed. If there is no internet connection
available, files can be placed in the prereq folder to avoid downloading.
 
.EXAMPLE
./Install-SCSM2016.ps1 -WorkingFolder "C:\Install" -InstallType "PrimaryServer" -Verbose

.NOTES
The script needs to be run as administrator. Working folder has to exist. Sxs and SCSM 2016 source has to be present in specified working folder or an alternate folder path. If prerequisite files are already available
they need to be placed in a prereq folder within the specified working folder or an alternate folder path.

    Directory: C:\Install\prereq


Mode                LastWriteTime     Length Name                                                                                                                        
----                -------------     ------ ----                                                                                                                        
-a---        21.07.2016     12:03    2284376 ReportViewer.exe                                                                                                            
-a---        14.12.2016     09:35    5140480 sqlncli.msi                                                                                                                 
-a---        14.12.2016     10:45    4300800 SQL_AS_AMO.msi
 
.LINK
https://blog.jhnr.ch
 
#>

[cmdletbinding()]
Param(
    [Parameter(Mandatory=$True)][string]$WorkingFolder,
    [Parameter(Mandatory=$True)][ValidateSet('PrimaryServer','AdditionalServer')][string]$InstallType,
    [Parameter(Mandatory=$False)][string]$SourcePath = "$WorkingFolder\source",
    [Parameter(Mandatory=$False)][string]$PrereqPath = "$WorkingFolder\prereq",
    [Parameter(Mandatory=$False)][string]$SxsPath = "$WorkingFolder\sxs"
)

$ErrorActionPreference = "Stop"

#Service Manager installation details, change these according to your needs
$Owner = "Owner"
$Organization = "Organization"
$ProductKey = "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX" #[25-character product key]
$MgName = "SM_Test"
$AdminGroup = "Test\Test Group" #[Domain\Account Name]
$ServiceAccount = "TEST\svc\BlaBla123$" #[Domain\Account Name\Password]
$WorkflowAccount = "TEST\svc\BlaBla123$" #[Domain\Account Name\Password]
$SqlInstance = "localhost,1433" #[Instance FQDN,Port]
$SqlDatabase = "ServiceManager" #Default name "ServiceManager"
$DatabaseSize = "2000" #Default size 2000MB
$DatabaseDataFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\DATA" #Default path "C:\Program Files\Microsoft SQL Server\[Server Version]\[Instance Name]\DATA"
$DatabaseLogFilePath = "C:\Program Files\Microsoft SQL Server\MSSQL13.MSSQLSERVER\MSSQL\Log" #Default path "C:\Program Files\Microsoft SQL Server\[Server Version]\[Instance Name]\Log"
$InstallPath = "C:\Program Files\Microsoft System Center\Service Manager" #Default path "C:\Program Files\Microsoft System Center\Service Manager"


#Split account information for further use
$ServiceAccountDomain = $ServiceAccount.Split('\')[0]
$ServiceAccountUsername = $ServiceAccount.Split('\')[1]
$WorkflowAccountDomain = $WorkflowAccount.Split('\')[0]
$WorkflowAccountUsername = $WorkflowAccount.Split('\')[1]


#Check for Active Directory module and install it if necessary. Module is used to check if specified accounts are present in the environment
if (Get-Module -ListAvailable -Name 'ActiveDirectory') {
    Write-Verbose "Active Directory module installed"
} else {
    Write-Verbose "Active Directory module not found, installing it right away"
    $Process = Install-WindowsFeature RSAT-AD-PowerShell
}


#Check for admin credentials
Write-Verbose "Checking for admin credentials"
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator'))
{
    Write-Error -Message "You do not have Administrator rights to run this script" -Category ResourceUnavailable -RecommendedAction "Please re-run this script as an Administrator"
}


#Check if specified accounts are present
Write-Verbose "Checking if specified Service Manager service account exists in Active Directory"
if (Get-ADUser $ServiceAccountUsername) {
    Write-Verbose "Service Manager Service account '$ServiceAccountDomain\$ServiceAccountUsername' present"
} else {
    Write-Error -Message "Specified Service Manager service account '$ServiceAccountDomain\$ServiceAccountUsername' was not found" -RecommendedAction "Check if account name is correct for your Service Manager service account"
}

Write-Verbose "Checking if specified Service Manager workflow account exists in Active Directory"
if (Get-ADUser $WorkflowAccountUsername) {
    Write-Verbose "Service Manager workflow account '$WorkflowAccountDomain\$WorkflowAccountUsername' present"
} else {
    Write-Error -Message "Specified Service Manager workflow account '$WorkflowAccountDomain\$WorkflowAccountUsername' was not found" -RecommendedAction "Check if account name is correct for your Service Manager workflow account"
}


#Check if specified Service Account is member of local Administrators group
#Borrowed from https://www.hanselman.com/blog/HowToDetermineIfAUserIsALocalAdministratorWithPowerShell.aspx
Write-Verbose "Checking local admin permissions for Service Account $ServiceAccountDomain\$ServiceAccountUsername"
if (([bool](([Security.Principal.WindowsIdentity]$ServiceAccountUsername).groups | Where-Object {$_.value -eq 'S-1-5-32-544'})) -eq $false)
{
    Write-Error -Message "Specified Service Account is not member of local Administrators group" -RecommendedAction "Add specified Service Account to local Administrators group"
} else {
    Write-Verbose -Message "Service Account $ServiceAccountDomain\$ServiceAccountUsername has local admin permissions"
}


#Check SQL connection
#Borrowed from http://www.sqlhammer.com/powershell-sql-connection-test/
Write-Verbose "Checking connection to SQL Server $SqlInstance"
$SqlConnString = "Data Source=$SqlInstance;Integrated Security=true;Initial Catalog=master;Connect Timeout=3;"
try
{
    $SqlConn = new-object ("Data.SqlClient.SqlConnection") $SqlConnString
    $SqlConn.Open()
}
catch
{
    Write-Error "Can not connect to SQL server $SqlInstance"
}

if ($SqlConn.State -eq 'Open')
{
    $SqlConn.Close();
    Write-Verbose "Successfully connected to SQL Server $SqlInstance"
}


#Install .Net Framework 3.5
Write-Verbose ".Net Framework 3.5"

if ((Test-Path -path "$SxsPath"))
{
    Write-Verbose "Installer files found"

	$Process = Install-WindowsFeature Net-Framework-Core -Source "$SxsPath"
}
else {
	Write-Error -Message "Error: .Net Framework 3.5 installation sources were not found in defined working folder" -Category InvalidArgument -RecommendedAction "Copy sxs directory which holds .Net 3.5 install sources to the defined working folder"
}


#Create prerequisites folder if not existing
if (!(Test-Path -path "$PrereqPath"))
{
	$PrereqFolder = New-Item "$PrereqPath" -type directory
}

#Prerequisite installer files
$ReportViewer = "$PrereqPath\ReportViewer.exe"
$SqlAmo = "$PrereqPath\SQL_AS_AMO.msi"
$SqlNc = "$PrereqPath\sqlncli.msi"
 
#Create Web Client
$WebClient = New-Object Net.WebClient


#Install Prerequisites

#Install Report Viewer 2008 (KB971119)
Write-Verbose "Report Viewer 2008 (KB971119)"

if (!(Test-Path -path $ReportViewer))
{
    Write-Verbose "Source not found, starting download..."
    
    #Get Report Viewer 2008 (KB971119)
    $RPTurl = 'http://download.microsoft.com/download/0/4/F/04F99ADD-9E02-4C40-838E-76A95BCEFB8B/ReportViewer.exe'
    $WebClient.DownloadFile($RPTurl, $ReportViewer)
    Write-Verbose "Download succeeded"
}

if ((Test-Path -path $ReportViewer))
{
    Write-Verbose "Installation started..."

	$Process = Start-Process -FilePath $ReportViewer -ArgumentList '/q /norestart' -Wait -PassThru

	if ($Process.ExitCode -eq 0) {
		Write-Verbose "Installation succeeded" 
	}
	else {
        Write-Error -Message "Error: Installation of Report Viewer 2008 (KB971119) failed." -Category NotSpecified
	}	
}
else {
    Write-Error -Message "Error: Installation source for Report Viewer 2008 (KB971119) not found." -Category ObjectNotFound -RecommendedAction "Check if download of Report Viewer source was successfull"
}


#Install SQL 2012 Native Client
Write-Verbose "SQL 2012 Native Client"

if (!(Test-Path -path $SqlNc))
{
    Write-Verbose "Source not found, starting download..."
    
    #Get SQL 2012 Native Client
    $RPTurl = 'http://go.microsoft.com/fwlink/?LinkID=239648&clcid=0x409'
    $WebClient.DownloadFile($RPTurl, $SqlNc)
    Write-Verbose "Download succeeded"
}

if ((Test-Path -path $SqlNc))
{
    Write-Verbose "Installation started..."

	$Process = Start-Process -FilePath $SqlNc -ArgumentList '/q /norestart IACCEPTSQLNCLILICENSETERMS=YES' -Wait -PassThru

	if ($Process.ExitCode -eq 0) {
		Write-Verbose "Installation succeeded"  
	}
	else {
		Write-Error -Message "Error: Installation of SQL 2012 Native Client failed." -Category NotSpecified
	}	
}
else {
    Write-Error -Message "Error: Installation source for SQL 2012 Native Client not found." -Category ObjectNotFound -RecommendedAction "Check if download of SQL 2012 Native Client source was successfull"
}


#Install SQL 2014 Analysis Management Objects
Write-Verbose "SQL 2014 Analysis Management Objects"

if (!(Test-Path -path $SqlAmo))
{
    Write-Verbose "Source not found, starting download..."
    
    #Get SQL 2014 Analysis Management Objects
    $RPTurl = 'https://download.microsoft.com/download/1/3/0/13089488-91FC-4E22-AD68-5BE58BD5C014/ENU/x64/SQL_AS_AMO.msi'
    $WebClient.DownloadFile($RPTurl, $SqlAmo)
    Write-Verbose "Download succeeded"
}

if ((Test-Path -path $SqlAmo))
{	
    Write-Verbose "Installation started..."

	$Process = Start-Process -FilePath $SqlAmo -ArgumentList '/q /norestart' -Wait -PassThru

	if ($Process.ExitCode -eq 0) {
		Write-Verbose "Installation succeeded" 
	}
	else {
		Write-Error -Message "Error: Installation of SQL 2014 Analysis Management Objects failed." -Category NotSpecified
	}	
}
else {
    Write-Error -Message "Error: Installation source for SQL 2014 Analysis Management Objects not found." -Category ObjectNotFound -RecommendedAction "Check if download of SQL 2014 Analysis Management Objects source was successfull"
}

Write-Verbose "Finished Installing Prerequisites"




#Install Service Manager 2016
Write-Verbose "Service Manager 2016"

#Prepare argument list depending on whether a primary or additional management server is going to be installed
if ($InstallType -eq 'PrimaryServer') {
$ArgumentList = @"
    /Install:Server /AcceptEula:"YES" /RegisteredOwner:"$Owner" /RegisteredOrganization:"$Organization" /ProductKey:"$ProductKey" /Installpath:"$InstallPath" /CreateNewDatabase /SqlServerInstance:"$SqlInstance" /DatabaseSize:"$DatabaseSize" /DatabaseDataFilePath:"$DatabaseDataFilePath" /DatabaseLogFilePath:"$DatabaseLogFilePath" /ManagementGroupName:"$MgName" /AdminRoleGroup:"$AdminGroup" /ServiceRunUnderAccount:"$ServiceAccount" /WorkflowAccount:"$WorkflowAccount" /CustomerExperienceImprovementProgram:"NO" /EnableErrorReporting:"NO" /Silent
"@
} 
if ($InstallType -eq 'AdditionalServer') {
$ArgumentList = @"
    /Install:Server /AcceptEula:"YES" /RegisteredOwner:"$Owner" /RegisteredOrganization:"$Organization" /ProductKey:"$ProductKey" /Installpath:"$InstallPath" /UseExistingDatabase:"$SqlInstance`:$SqlDatabase" /ManagementGroupName:"$MgName" /AdminRoleGroup:"$AdminGroup" /ServiceRunUnderAccount:"$ServiceAccount" /CustomerExperienceImprovementProgram:"NO" /EnableErrorReporting:"NO" /Silent
"@
}

#Check for Service Manager source folders
if (!(Test-Path -path "$SourcePath\Setup.exe"))
{
	Write-Error -Message "Error: Service Manager installation sources were not found in defined source path" -Category InvalidArgument -RecommendedAction "Copy SCSM 2016 directory which holds Setup.exe to the defined working folder"
}
else 
{
    Write-Verbose "Installer files found"
    Write-Verbose "Installation started..."

    $Process = Start-Process -FilePath "$SourcePath\Setup.exe" -ArgumentList $ArgumentList -Wait -PassThru

    if ($Process.ExitCode -eq 0) {
		Write-Verbose "Installation succeeded" 
	}
	else {
        Write-Error -Message "Error: Installation of Service Manager 2016 failed. See install log file for detailed information." -Category NotSpecified
	}	
}


#Add DAL registry settings
Write-Verbose "Adding DAL registry settings"
$Path = "HKLM:SOFTWARE\Microsoft\System Center\2010\Common\DAL\"

#Create new values if path exists
if(Test-Path $Path) {
    $itemProperty = New-ItemProperty -Path $Path -Name "DALInitiateClearPool" -Value 1 -PropertyType "DWord"
    Write-Verbose "DWord value DALInitiateClearPool added successfully"

    $itemProperty = New-ItemProperty -Path $Path -Name "DALInitiateClearPoolSeconds" -Value 60 -PropertyType "DWord"
    Write-Verbose "DWord value DALInitiateClearPoolSeconds added successfully"
}
else {
    Write-Error -Message "Registry key does not exist" -Category ResourceUnavailable -RecommendedAction "Check if registry key $Path exists on this computer"
}


#Restart Computer after installation
$Title = "Restart Computer"
$Message = "Do you want to restart the computer now?"

$Yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Immediately restarts the computer."
$No = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Does not restart the computer."

$Options = [System.Management.Automation.Host.ChoiceDescription[]]($Yes, $No)
$Result = $host.ui.PromptForChoice($Title, $Message, $Options, 0) 

switch ($Result)
{
    0 { Restart-Computer }
    1 { "You selected not to restart the computer. Please restart manually after installing Service Manager Management Server." }
}
