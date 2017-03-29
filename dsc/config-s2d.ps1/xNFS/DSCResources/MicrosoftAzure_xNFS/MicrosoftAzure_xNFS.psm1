﻿#
# xSOFS: DSC resource to configure a Scale-out File Server Cluster Resource. 
#

function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $NFSName,

        [parameter(Mandatory)]
        [string] $LBIPAddress

    )
  
    $retvalue = @{Ensure = if ((Get-ClusterGroup -Name ${NFSName} -ErrorAction SilentlyContinue).State -eq 'Online') {'Present'} Else {'Absent'}}

    $retvalue
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $NFSName,

        [parameter(Mandatory)]
        [string] $LBIPAddress

    )
 
    $Disks = Get-ClusterResource | Where-Object Name -like "*${NFSName}_*"

    Add-ClusterFileServerRole -Storage $Disks.Name -Name $NFSName -StaticAddress $LBIPAddress

    Move-ClusterGroup -Name $NFSName -Node $env:COMPUTERNAME 

    $ClusterNetworkName = "Cluster Network 1"
    $IPResourceName = "IP Address ${LBIPAddress}"
    $ProbePort = "59001"

    Get-ClusterResource $IPResourceName | 
    Set-ClusterParameter `
    -Multiple @{
        "Address"="$LBIPAddress";
        "ProbePort"="$ProbePort";
        "SubnetMask"="255.255.255.255";
        "Network"="$ClusterNetworkName";
        "OverrideAddressMatch"=1;
        "EnableDhcp"=0
        }

    Stop-ClusterGroup -Name $NFSName

    Start-ClusterGroup -Name $NFSName

}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $NFSName,

        [parameter(Mandatory)]
        [string] $LBIPAddress,

    )

    $retvalue = (Get-ClusterGroup -Name ${NFSName} -ErrorAction SilentlyContinue).State -eq 'Online'
 
    $retvalue
    
}

Export-ModuleMember -Function *-TargetResource
