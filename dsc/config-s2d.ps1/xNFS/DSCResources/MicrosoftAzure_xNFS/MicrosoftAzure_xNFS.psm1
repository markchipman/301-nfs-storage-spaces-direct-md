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
        [string] $LBIPAddress,

        [parameter(Mandatory)]
        [PSCredential] $AdminCreds
    )
  
    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $AdminCreds
        $retvalue = @{Ensure = if ((Get-ClusterGroup -Name ${NFSName} -ErrorAction SilentlyContinue).State -eq 'Online') {'Present'} Else {'Absent'}}
    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }

    $retvalue
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $NFSName,

        [parameter(Mandatory)]
        [string] $LBIPAddress,

        [parameter(Mandatory)]
        [PSCredential] $AdminCreds
    )
 
    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $AdminCreds

        $Disks = Get-ClusterResource | ? Name -like "*${NFSName}_*"

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
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }

}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [string] $NFSName,

        [parameter(Mandatory)]
        [string] $LBIPAddress,

        [parameter(Mandatory)]
        [PSCredential] $AdminCreds
    )

    try
    {
        ($oldToken, $context, $newToken) = ImpersonateAs -cred $AdminCreds
        $retvalue = (Get-ClusterGroup -Name ${NFSName} -ErrorAction SilentlyContinue).State -eq 'Online'
    }
    finally
    {
        if ($context)
        {
            $context.Undo()
            $context.Dispose()
            CloseUserToken($newToken)
        }
    }

    $retvalue
    
}

function Get-ImpersonateLib
{
    if ($script:ImpersonateLib)
    {
        return $script:ImpersonateLib
    }

    $sig = @'
[DllImport("advapi32.dll", SetLastError = true)]
public static extern bool LogonUser(string lpszUsername, string lpszDomain, string lpszPassword, int dwLogonType, int dwLogonProvider, ref IntPtr phToken);

[DllImport("kernel32.dll")]
public static extern Boolean CloseHandle(IntPtr hObject);
'@
   $script:ImpersonateLib = Add-Type -PassThru -Namespace 'Lib.Impersonation' -Name ImpersonationLib -MemberDefinition $sig

   return $script:ImpersonateLib
}

function ImpersonateAs([PSCredential] $cred)
{
    [IntPtr] $userToken = [Security.Principal.WindowsIdentity]::GetCurrent().Token
    $userToken
    $ImpersonateLib = Get-ImpersonateLib

    $bLogin = $ImpersonateLib::LogonUser($cred.GetNetworkCredential().UserName, $cred.GetNetworkCredential().Domain, $cred.GetNetworkCredential().Password, 
    9, 0, [ref]$userToken)

    if ($bLogin)
    {
        $Identity = New-Object Security.Principal.WindowsIdentity $userToken
        $context = $Identity.Impersonate()
    }
    else
    {
        throw "Can't log on as user '$($cred.GetNetworkCredential().UserName)'."
    }
    $context, $userToken
}

function CloseUserToken([IntPtr] $token)
{
    $ImpersonateLib = Get-ImpersonateLib

    $bLogin = $ImpersonateLib::CloseHandle($token)
    if (!$bLogin)
    {
        throw "Can't close token."
    }
}

Export-ModuleMember -Function *-TargetResource
