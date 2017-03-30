
configuration ConfigS2D
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds,

        [Parameter(Mandatory)]
        [String]$ClusterName,

        [Parameter(Mandatory)]
        [String]$NFSName,

        [Parameter(Mandatory)]
        [String]$ShareName,

        [Parameter(Mandatory)]
        [String]$LBIPAddress,

        [Parameter(Mandatory)]
        [String]$vmNamePrefix,

        [Parameter(Mandatory)]
        [Int]$vmCount,

        [Parameter(Mandatory)]
        [Int]$vmDiskSize,

        [Parameter(Mandatory)]
        [String]$witnessStorageName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$witnessStorageKey,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30

    )

    Import-DscResource -ModuleName xComputerManagement, xNetworking, xFailOverCluster, xNFS
 
    [System.Collections.ArrayList]$Nodes=@()
    For ($count=0; $count -lt $vmCount; $count++) {
        $Nodes.Add($vmNamePrefix + $Count.ToString())
    }

    Node localhost
    {

        WindowsFeature FC
        {
            Name = "Failover-Clustering"
            Ensure = "Present"
        }

        WindowsFeature FCPS
        {
            Name = "RSAT-Clustering-PowerShell"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]FC"
        }

        WindowsFeature FCMgmt
        {
            Name = "RSAT-Clustering-Mgmt"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]FC"
        }

        WindowsFeature FS
        {
            Name = "FS-FileServer"
            Ensure = "Present"
        }

        WindowsFeature NFSService
        {
            Name = "FS-NFS-Service"
            Ensure = "Present"
        }        

        WindowsFeature NFSAdmin
        {
            Name = "RSAT-NFS-Admin"
            Ensure = "Present"
            DependsOn = "[WindowsFeature]NFSService"
        }

        xFirewall LBProbePortRule
        {
            Direction = "Inbound"
            Name = "Azure Load Balancer Customer Probe Port"
            DisplayName = "Azure Load Balancer Customer Probe Port (TCP-In)"
            Description = "Inbound TCP rule for Azure Load Balancer Customer Probe Port."
            DisplayGroup = "Azure"
            State = "Enabled"
            Access = "Allow"
            Protocol = "TCP"
            LocalPort = "59001" -as [String]
            Ensure = "Present"
        }

        Script DNSSuffix
        {
            SetScript = "Set-DnsClientGlobalSetting -SuffixSearchList $DomainName; Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\' -Name Domain -Value $DomainName; Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\' -Name 'NV Domain' -Value $DomainName"
            TestScript = "'$DomainName' -in (Get-DNSClientGlobalSetting).SuffixSearchList"
            GetScript = "@{Ensure = if (('$DomainName' -in (Get-DNSClientGlobalSetting).SuffixSearchList) {'Present'} else {'Absent'}}"
        }

        Script FirewallProfile
        {
            SetScript = 'Get-NetConnectionProfile | Where-Object NetworkCategory -eq "Public" | Set-NetConnectionProfile -NetworkCategory Private; $global:DSCMachineStatus = 1'
            TestScript = '(Get-NetConnectionProfile | Where-Object NetworkCategory -eq "Public").Count -eq 0'
            GetScript = '@{Ensure = if ((Get-NetConnectionProfile | Where-Object NetworkCategory -eq "Public").Count -eq 0) {"Present"} else {"Absent"}}'
            DependsOn = "[Script]DNSSuffix"
        }

        xCluster FailoverCluster
        {
            Name = $ClusterName
            Nodes = $Nodes
            PsDscRunAsCredential = $AdminCreds
	        DependsOn = @("[WindowsFeature]FCPS","[Script]FirewallProfile")
        }

        Script CloudWitness
        {
            SetScript = "Set-ClusterQuorum -CloudWitness -AccountName ${witnessStorageName} -AccessKey $($witnessStorageKey.GetNetworkCredential().Password)"
            TestScript = "(Get-ClusterQuorum).QuorumResource.Name -eq 'Cloud Witness'"
            GetScript = "@{Ensure = if ((Get-ClusterQuorum).QuorumResource.Name -eq 'Cloud Witness') {'Present'} else {'Absent'}}"
            DependsOn = "[xCluster]FailoverCluster"
        }

        Script IncreaseClusterTimeouts
        {
            SetScript = "(Get-Cluster).SameSubnetDelay = 2000; (Get-Cluster).SameSubnetThreshold = 15; (Get-Cluster).CrossSubnetDelay = 3000; (Get-Cluster).CrossSubnetThreshold = 15"
            TestScript = "(Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15"
            GetScript = "@{Ensure = if ((Get-Cluster).SameSubnetDelay -eq 2000 -and (Get-Cluster).SameSubnetThreshold -eq 15 -and (Get-Cluster).CrossSubnetDelay -eq 3000 -and (Get-Cluster).CrossSubnetThreshold -eq 15) {'Present'} else {'Absent'}}"
            DependsOn = "[Script]CloudWitness"
        }

        Script EnableS2D
        {
            SetScript = "Enable-ClusterS2D -Confirm:0; New-Volume -StoragePoolFriendlyName S2D* -FriendlyName ${NFSName}_vol0 -FileSystem NTFS -DriveLetter F -UseMaximumSize -ResiliencySettingName Mirror"
            TestScript = "(Get-Volume -DriveLetter F -ErrorAction SilentlyContinue).OperationalStatus -eq 'OK'"
            GetScript = "@{Ensure = if ((Get-Volume -DriveLetter F -ErrorAction SilentlyContinue).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}"
            DependsOn = "[Script]IncreaseClusterTimeouts"
        }

        xNFS EnableNFS
        {
            NFSName = $NFSName
            LBIPAddress = $LBIPAddress
            PsDscRunAsCredential = $AdminCreds
            DependsOn = @("[Script]EnableS2D","[xFirewall]LBProbePortRule")
        }

        Script CreateShare
        {
            SetScript = "New-Item -Path F:\${ShareName} -ItemType Directory; New-NfsShare -Name ${ShareName} -Path F:\${ShareName} -EnableUnmappedAccess $True -Authentication SYS -AllowRootAccess $True -Permission ReadWrite; NFSFILE /r m=777 F:\${ShareName}"
            TestScript = "(Get-NfsShare -Name ${ShareName} -ErrorAction SilentlyContinue).IsOnline -eq $True"
            GetScript = "@{Ensure = if ((Get-NfsShare -Name ${ShareName} -ErrorAction SilentlyContinue).IsOnline -eq $True) {'Present'} Else {'Absent'}}"
            DependsOn = "[xNFS]EnableNFS"
        }

        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $true
        }

    }

}
