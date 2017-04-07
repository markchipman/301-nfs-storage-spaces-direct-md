#
# xSOFS: DSC resource to configure a Scale-out File Server Cluster Resource. 
#

function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $NFSName,

        [parameter(Mandatory)]
        [string] $ShareName,

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
        [string] $ShareName,

        [parameter(Mandatory)]
        [string] $LBIPAddress

    )
 
    # Add NFS Server role to Cluster
    
    $Disks = Get-ClusterResource -ErrorAction SilentlyContinue | Where-Object Name -like "*${NFSName}_*"

    Add-ClusterFileServerRole -Storage $Disks.Name -Name $NFSName -StaticAddress $LBIPAddress -ErrorAction Stop -Verbose

    # Make sure NFS Server role is active on this node

    Move-ClusterGroup -Name $NFSName -Node $env:COMPUTERNAME -ErrorAction Stop -Verbose

    # Update IP Address Resource for NFS Group with Azure Load Balancer IP Address

    $ClusterNetworkName = "Cluster Network 1"
    $IPResourceName = "IP Address ${LBIPAddress}"
    $ProbePort = "59001"

    Get-ClusterResource $IPResourceName | 
    Set-ClusterParameter -Verbose -Multiple @{
        "Address"="$LBIPAddress";
        "ProbePort"="$ProbePort";
        "SubnetMask"="255.255.255.255";
        "Network"="$ClusterNetworkName";
        "OverrideAddressMatch"=1;
        "EnableDhcp"=0
        }

    # Stop and Start Cluster Group so that IP Resource change takes effect
    
    Stop-ClusterGroup -Name $NFSName -ErrorAction SilentlyContinue -Verbose

    Start-ClusterGroup -Name $NFSName -ErrorAction Stop -Verbose

    Start-Sleep -Seconds 60

    # Create NFS shared folder and set initial permissions

    [system.io.directory]::CreateDirectory("F:\${ShareName}")
    
    New-NfsShare -Name "${ShareName}" -Path "F:\${ShareName}" -EnableUnmappedAccess $True -Authentication SYS -AllowRootAccess $True -Permission ReadWrite -Verbose
    
    Start-Process -FilePath "${env:SystemRoot}\System32\nfsfile.exe" -ArgumentList "/r m=777 F:\${ShareName}" -Wait

    # Enable Auto-failback of Cluster Groups

    (Get-ClusterGroup) | Foreach-Object {$_.AutoFailbackType = 1}

    # Set NFS Lease and Grace duration

    Set-NfsServerConfiguration -LeasePeriodSec 10 -GracePeriodSec 20

    # Restart NFS Service on each Cluster Node to make new Lease and Grace durations effective

    Set-Item wsman:\localhost\Client\TrustedHosts -Value "<local>" -Force

    Get-ClusterNode -Cluster . | Foreach-Object { Invoke-Command -ComputerName $_.Name -ScriptBlock { Restart-Service -Name NfsService } }

    Set-Item wsman:\localhost\Client\TrustedHosts -Value "" -Force

}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $NFSName,

        [parameter(Mandatory)]
        [string] $ShareName,
        
        [parameter(Mandatory)]
        [string] $LBIPAddress

    )

    $retvalue = (Get-ClusterGroup -Name ${NFSName} -ErrorAction SilentlyContinue).State -eq 'Online'
 
    $retvalue
    
}

Export-ModuleMember -Function *-TargetResource
