<#
 .Notes
 NAME: Get-SCSMReviewActivities.ps1
 AUTHOR: Stefan Johner
 Website: http://blog.jhnr.ch
 Twitter: http://twitter.com/JohnerStefan
 Version: 1.1
 CREATED: 20/07/2015
 LASTEDIT:
 20/07/2015 1.0
 Initial Release
 
 .Synopsis
 This script gets all Review Activities for a given work item.
 
 .Description
 When run on a Service Manager Management Server, the script will get all Review Activities which are related to a given work item.
 You can easily alter the function to get other activity types by just changing ReviewActivityClass variable to a class of your needs.
 The script has to be run on a Service Manager Management server and SMLets cmdlets have to be available.
 
 .Parameter WorkItemId
 Specify the Id of the work item you want to find Review Activities for
 
 .Outputs
 Review Activities which are related to the given work item
 
 .Example
 ./Get-SCSMReviewActivities -WorkItem "SR12345"

 .Link
 http://github.com/sjohner/SCSM-ScriptRepository
 
#>

[cmdletbinding()]
Param(
	[Parameter(Mandatory=$True)][string]$WorkItemId
)

try {

	#Import SMLets module
	import-module smlets
	
	#Get necessary classes and relationships
	$ReviewActivityClass = Get-SCSMClass -Name ^System.WorkItem.Activity.ReviewActivity$
	$WorkItemRelatesToWorkItemRelClass = Get-SCSMRelationshipClass -Name ^System.WorkItemRelatesToWorkItem$
	$WorkItemContainsActivityRelClass = Get-SCSMRelationshipClass -Name ^System.WorkItemContainsActivity$
	$WorkItemClass = Get-SCSMClass -Name ^System.Workitem$
	
	#Define ArrayList to store Review Activities. We need to use ArrayList instead of System.Array to be able to add and remove elements.
	#The MSDN page for the ISFixedSize Property helps to explain this. Note that it supports the modification of existing elements,
	#but not the addition or removal of others.
	[System.Collections.ArrayList]$ReviewActivities = @()
	
	#Recursively get all Review Activities for specific WorkItem
	Function getReviewActivities {  
		Param 
			(
			[Parameter(Mandatory=$true)]$WorkItem
			) 
	
		#Get all activities contained in the given WorkItem
		$ContainedActivities =  @()	
		$ContainedActivities += Get-SCSMRelatedObject -Relationship $WorkItemContainsActivityRelClass -SMObject $WorkItem
		
		#Check if an activity is a Review Activity and add it to the ArrayList
		foreach ($Activity in $ContainedActivities)
		{
			if($Activity.ClassName -eq $ReviewActivityClass.Name)
			{
				$Index = $ReviewActivities.Add($Activity)
			}
			#If not Review Activity, recursively call getReviewActivities to get RAs in nested Activities
			else
			{
				getReviewActivities -WorkItem $Activity
			}
		}
	}
	
	#Get WorkItem object
	$WorkItemObj = Get-SCSMObject -Class $WorkItemClass -Filter "Id -eq $($WorkItemId)"
	
	#Find related Review Activities
	getReviewActivities -WorkItem $WorkItemObj
	
	#Remove SMLets
	Remove-Module smlets -force
	
	#Output RAs
	$ReviewActivities
}
catch {
	#Throw error
    Throw "@   
    $error[0]
    @"  
}
