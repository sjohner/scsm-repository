<#
 .Notes
 NAME: Update-SCSMEnumList.ps1
 AUTHOR: Stefan Johner
 Website: http://blog.jhnr.ch
 Twitter: http://twitter.com/JohnerStefan
 Version: 1.1
 CREATED: 11/04/2015
 LASTEDIT:
 11/04/2015 1.0
 Initial Release

 .Synopsis
 This script updates Service Manager enums based on a MySQL query.

 .Description
 The script establishes a connection to a MySQL database and updates a defined enumeration list according to the defined MySQL query
 The user which runs the script needs to be part of the "Author" role to update enum lists. Also the script needs to be executed on a
 Service Manager management server where MySQL Connector/Net ADO.NET driver and SMLets are installed (see http://dev.mysql.com/downloads/connector/net/)
 Do not forget to update credentials for SQL connection string.

 .Example
 .\Update-SCSMEnumList.ps1 -Verbose

 .Link
 http://github.com/sjohner/SCSM-ScriptRepository

#>

[cmdletbinding()]

# Setup the script to stop on error
$ErrorActionPreference = "Stop"

#Define MySQL query to get job titles
$MySqlQuery = "select title from jobtitles where deleted = 0"

#Define MySQL credentials and connection string
$MySQLUserName = 'mysqluser'
$MySQLPassword = 'p@ssword'
$MySQLDatabase = 'databasename'
$MySQLHost = 'mysql.scsmlab.com'
$ConnectionString = "server=" + $MySQLHost + "; port=3306; uid=" + $MySQLUserName + "; pwd=" + $MySQLPassword + "; database="+$MySQLDatabase

try
{
    #Used to invoke MySQL query
    Function Invoke-MySQL {
        Param
            (
            [Parameter(Mandatory = $true,ParameterSetName = '',ValueFromPipeline = $true)][string]$Query
            )

        #Load assembly. MySQL Connector/Net ADO.NET driver has to be installed http://dev.mysql.com/downloads/connector/net/
        [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")

        #Create new connection by using previousely defined connection string
        $Connection = New-Object MySql.Data.MySqlClient.MySqlConnection
        $Connection.ConnectionString = $ConnectionString
        $Connection.Open()

        #Excute query and close connection
        $Command = New-Object MySql.Data.MySqlClient.MySqlCommand($Query, $Connection)
        $DataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($Command)
        $DataSet = New-Object System.Data.DataSet
        $RecordCount = $dataAdapter.Fill($dataSet, "data")
        $Connection.Close()

        #Return query results
        Return $DataSet.Tables[0]
    }

    #Get Job Titles from Tippps MySQL database
    $Result = Invoke-MySQL -Query $MySqlQuery
    Write-Verbose "Retreived data from MySQL database ($($Result.Rows.Count) rows)"

    #Import SMLets
    Import-Module smlets

    #Get Management Pack to save enumerations and appropriate parent enum
    $EnumManagementPack = Get-SCSMManagementPack -Name ^tph.listelements.library$
    $ParentEnum = Get-SCSMEnumeration -Name ^tphenumemploymentstatus$

    #Get child enumsn using Get-SCSMChildEnumeration which is much faster
    #PS C:\> (Measure-Command {Get-SCSMChildEnumeration -Enumeration $ParentEnum}).TotalMilliseconds
    #1,3816
    #PS C:\> (Measure-Command {(Get-SCSMEnumeration | where {$_.Parent -match $($ParentEnum.Id)})}).TotalMilliseconds
    #242,5261
    $ChildEnums = Get-SCSMChildEnumeration -Enumeration $ParentEnum

    #Add new titles to enum list if not already in enum list
    Foreach($Title in $Result.Title) {
        if($($ChildEnums.DisplayName) -notcontains $Title) {

            #Get highest ordinal value using Measure-Object. Seems to be much faster than sorting an getting last objects ordinal value
            #PS C:\> (Measure-Command {($ChildEnums | Measure-Object -Property Ordinal -Maximum).Maximum}).TotalMilliseconds
            #0,892
            #PS C:\> (Measure-Command {($ChildEnums | Sort-Object Ordinal | select -Last 1).Ordinal}).TotalMilliseconds
            #4,0093
            $Ordinal = (($ChildEnums | Measure-Object -Property Ordinal -Maximum).Maximum) + 1

            #Create child enum internal name (convert to lower case and remove spaces)
            $ChildEnumName = "$($ParentEnum.Name)$Title".ToLower() -replace '\s',''

            #Add new child enum as last element in list (increment hightest ordinal)
            Add-SCSMEnumeration -Parent $ParentEnum -Name $ChildEnumName -DisplayName $Title -Ordinal $Ordinal -ManagementPack $EnumManagementPack
            Write-Verbose "Added $Title to Enum List"
        }
    }

    #Remove obsolete titles from enum list if not anymore in database
    Foreach($ChildEnum in $ChildEnums) {
        if($($Result.Title) -notcontains $($ChildEnum.DisplayName)) {
            Remove-SCSMEnumeration -Enumeration $ChildEnum
            Write-Verbose "Removed $($ChildEnum.DisplayName) from Enum List"
        }
    }

    # Remove smlets
    Remove-module smlets -force
}

catch {

    Throw "@

    $error[0]

    @"

}
