<#
 .Notes
 NAME: Check-SCSMNotificationTemplateUsage.ps1
 AUTHOR: Stefan Johner
 Website: http://blog.jhnr.ch
 Twitter: http://twitter.com/JohnerStefan
 Version: 1.1
 CREATED: 15/07/2014
 LASTEDIT:
 14/08/2014 1.1
 Added support for Workflow Subscriptions
 15/07/2014 1.0
 Initial Release

 .Synopsis
 Checks for a given notification template if it is used in any notification subscription.

 .Description
 Retrieves all workflows and notification subscriptions that a given notification template is directly referenced to.

 .Parameter TemplateId
 Specify the GUID of the template you want to check usage for

 .Outputs
 DisplayName, Name and Id properties of the workflow or notification subscriptions which use the given template

 .Example
 .Check-SCSMNotificationTemplateUsage.ps1 -TemplateId "5120d091-efef-b47a-f942-6905250f577f"
 
 .Link
 http://github.com/sjohner/SCSM-ScriptRepository

#>

Param
(
    [Parameter(Mandatory=$true)]
    [String]$TemplateId
)

# Run the script and check for errors
try {

    # Load SMLets
    if(!(get-module smlets)){import-module smlets -Force -ErrorAction Stop}

    $NotificationSubscriptionPattern = '<WorkflowArrayParameter Name="TemplateIds" Type="string"><Item>' + $TemplateId + '</Item></WorkflowArrayParameter>'
    $WorkflowSubscriptionPattern = '<WorkflowArrayParameter Name="NotificationTemplates" Type="guid"><Item>' + $TemplateId + '</Item></WorkflowArrayParameter>'

    # Get Notification Template
    $TemplateObj = Get-SCSMObjectTemplate -Id $TemplateId

    if($TemplateObj) {

        Write-Host " "
        Write-Host "Validating..."
        Write-Host " "

        $Workflows = @()

        # Get Workflows which use the defined template in WriteAction
        Get-SCSMWorkflow.ps1 | ForEach-Object {
            $wf = $_
            $wf.WriteActionCollection | ForEach-Object {
                if ($_.Configuration.Contains($NotificationSubscriptionPattern) -or $_.Configuration.Contains($WorkflowSubscriptionPattern)) {
                    $Workflows += $wf
                }
            }
        }

        # Output results
        If($Workflows.Count -gt 0) {
            Write-Host "Template used by $($Workflows.Count) workflow(s) or notification subscription(s):" -ForegroundColor Green
            Write-Host " "
            $Workflows | ForEach-Object {
                $_ | Select-Object DisplayName,Name,Id
            }
        }
        Else {
            Write-Host "Template not used in any workflow or notification subscription!" -ForegroundColor Red
            $TemplateObj | Select-Object DisplayName,Name,Id
        }
    }
    Else {
        Write-Host " "
        Write-Host "Template with ID `"$($TemplateId)`" not found!" -ForegroundColor Red
        Write-Host " "
    }

# Remove SMLets
remove-module smlets -force
}

# Catch any errors
catch
{
# Return the error details
Throw $_.Exception
}
