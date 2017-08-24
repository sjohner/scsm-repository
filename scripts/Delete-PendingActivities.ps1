<# 
 
.SYNOPSIS 
This script deletes all Activities with status "Pending"
 
.DESCRIPTION 
The script gets all Activities with status "Pending" and deletes them after promting the user. Be carefull when using this script!
 
.EXAMPLE 
.\Delete-PendingActivities.ps1 -ComputerName 'SM02' -Verbose 
 
.NOTES 
SMLets have to be available on the computer where the script is run.
 
.LINK 
https://blog.jhnr.ch 
 
#> 

[CmdletBinding()]

Param
(
    [Parameter(Mandatory=$false)]
    [String]$ComputerName = 'localhost'
)


#region Import modules
    
Write-Verbose "Loading SMLets module"

Try
{
    if (!(Get-Module SMLets))
    {
        Import-Module SMLets
    }
}
Catch
{
    Throw "Loading SMLets module failed"
}

#endregion

Try
{
    #region Get objects

    $EnumGuid = (Get-SCSMEnumeration -Name ActivityStatusEnum.Ready -ComputerName $ComputerName).Id

    $ActivityArray = @()
    $ActivityArray = Get-SCSMObject -Class (Get-SCSMClass -Name System.WorkItem.Activity$ -ComputerName $ComputerName) -Filter "Status -eq '$EnumGuid'" -ComputerName $ComputerName

    #endregion

    #region Prompt user to continue
    if($($ActivityArray.Count) -gt 0)
    {
        $ActivityArray
        
        $Title = "Found $($ActivityArray.Count) activite(s) with status 'Pending' to be deleted"
        $Prompt = 'Should I [A]bort or [C]ontinue?'
        $Abort = New-Object System.Management.Automation.Host.ChoiceDescription '&Abort','Aborts the operation'
        $Continue = New-Object System.Management.Automation.Host.ChoiceDescription '&Continue','Continues the operation'
        $Options = [System.Management.Automation.Host.ChoiceDescription[]] ($Abort,$Continue)
         
        $Choice = $Host.UI.PromptForChoice($Title,$Prompt,$Options,0)

        #endregion

        if($Choice -eq 1)
        {
            Write-Output "Deleting $($ActivityArray.Count) activitie(s). This could take some time..."
            Foreach($Activity in $ActivityArray)
            {
                Remove-SCSMObject -SMObject $Activity –Force  -ComputerName $ComputerName
                Write-Verbose "Deleted Activity $($Activity.DisplayName)"
            }
            Write-Output "*** Finished deleting $($ActivityArray.Count) activitie(s) ***"
        }
        else
        {
            Write-Warning "Operation aborted, no activities deleted"
        }
    }
    else
    {
        Write-Warning "No activities found with status 'Pending'"
    }
}

Catch
{
    Write-Error "$($_.Exception.Message)"
}

Finally
{
    # Remove SMLets module
    Write-Verbose "Removing SMLets module"
    
    if ((Get-Module SMLets))
    {
        Remove-Module SMLets
    }
}