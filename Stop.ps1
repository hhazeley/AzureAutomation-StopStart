
Param(
   $AutomationRG = "My1StRG",
   $AutomationAcct = "StopStart",
   $StopType = "Auto"
)


$connectionName = "AzureRunAsConnection"
try
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection=Get-AutomationConnection -Name $connectionName         

    "Logging in to Azure..."
    Add-AzureRmAccount `
        -ServicePrincipal `
        -TenantId $servicePrincipalConnection.TenantId `
        -ApplicationId $servicePrincipalConnection.ApplicationId `
        -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch {
    if (!$servicePrincipalConnection)
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    } else{
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}

function Get-AzureRmVMStatus {
  [CmdletBinding()]
  param (
    #The name of a resouce group in your subscription
    [Parameter(Mandatory=$true)]
    [string]
    $ResourceGroupName
    ,
    #VM name filter
    [Parameter()]
    [string]
    $Name = '*'
  )
  Get-AzureRmVM -ResourceGroupName $ResourceGroupName | ? {$_.Tags.Keys -eq "Stop" -and $_.Tags.Values -eq "$StopType"} |
    Get-AzureRmVM -Status |
    Select-Object -Property Name, Statuses, ResourceGroupName |
    Where-Object {$_.Name -like $Name} |
    ForEach-Object {
      $VMName = $_.Name
      $ResourceGroupName = $_.ResourceGroupName
      $_.Statuses |
        Where-Object {$_.Code -like 'PowerState/*'} |
        ForEach-Object {
          New-Object -TypeName psobject -Property @{
            Name   = $VMName
            ResourceGroupName = $ResourceGroupName
            Status = $_.DisplayStatus
          }
        }
      }
}

$subs = Get-AzureRmSubscription -WarningAction SilentlyContinue

$subs | % {Select-AzureRmSubscription -SubscriptionId $_.SubscriptionId
$VMs = Get-AzureRmResourceGroup | % {Get-AzureRmVMStatus $_.ResourceGroupName}

$ASVMs = $VMs | ? {$_.Status -ne "VM deallocated"}

Foreach ($ASVM in $ASVMs)
 {
     $params = @{"Name"=$ASVM.name;"ResourceGroupName"=$ASVM.ResourceGroupName}
     $msg = "Stopping VM "
     $msg += $ASVM.name
     $msg += " on resouregroup "
     $msg += $ASVM.ResourceGroupName
     $msg += "......"
     Write-Output " " 
     Write-Output $msg
     Write-Output " "
     Start-AzureRmAutomationRunbook	-AutomationAccountName $AutomationAcct -Name "StopVM" -Parameters $params -ResourceGroupName $AutomationRG
     }
}