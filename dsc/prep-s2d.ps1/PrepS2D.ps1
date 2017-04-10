#
# CopyrightMicrosoft Corporation. All rights reserved."
#

configuration PrepS2D
{
    param
    (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$AdminCreds,

        [Int]$RetryCount=20,
        [Int]$RetryIntervalSec=30
    )

    Import-DscResource -ModuleName xComputerManagement, xNetworking

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
        }

        WindowsFeature FCMgmt
        {
            Name = "RSAT-Clustering-Mgmt"
            Ensure = "Present"
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
        
        Script WindowsUpdate
        {
            SetScript = "Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AUOptions -Value 4 -Type DWord; Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name ScheduledInstallTime -Value 3 -Type DWord; Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AlwaysAutoRebootAtScheduledTime -Value 1 -Type DWord; Set-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AlwaysAutoRebootAtScheduledTimeMinutes -Value 15 -Type DWord"
            TestScript = "(Get-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AUOptions -ErrorAction SilentlyContinue).AUOptions -eq 4"
            GetScript = "@{Ensure = if ((Get-ItemProperty -Path HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\AU -Name AUOptions -ErrorAction SilentlyContinue).AUOptions -eq 4) {'Present'} else {'Absent'}}"
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

        Script EnableSSH
        {
            SetScript = 'Invoke-Expression ((New-Object System.Net.WebClient).DownloadString("https://chocolatey.org/install.ps1")); choco install openssh -params "/SSHServerFeature /KeyBasedAuthenticationFeature" -y; $global:DSCMachineStatus = 1'
            TestScript = "(Get-Service -Name sshd -ErrorAction SilentlyContinue).Status -eq 'Running'"
            GetScript = "@{Ensure = if ((Get-Service -Name sshd -ErrorAction SilentlyContinue).Status -eq 'Running') {'Present'} Else {'Absent'}}"
            PsDscRunAsCredential = $AdminCreds
            DependsOn = "[Script]FirewallProfile"
        }

        LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $True
        }

    }
}
