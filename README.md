# Create a Storage Spaces Direct (S2D) Network File System (NFS) Cluster with Windows Server 2016 on an existing VNET
This template will create a Storage Spaces Direct (S2D) Network File System (NFS) cluster using Windows Server 2016 in an existing VNET with existing DNS servers configured.  This cluster will be deployed as a workgroup-mode cluster, and as such, an Active Directory domain is not required.

This template creates the following resources by default:

+   A Standard Storage Account for a Cloud Witness
+	A Windows Server 2016 cluster for storage nodes, provisioned for Storage Spaces Direct (S2D) and the NFS File Server role
+   Managed Disk resources for each virtual disk attached to the VM cluster nodes
+	One Availability Set for the cluster nodes

Click the button below to deploy from the portal:

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Frobotechredmond%2F301-nfs-storage-spaces-direct-md%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>
<a href="http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Frobotechredmond%2F301-nfs-storage-spaces-direct-md%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://armviz.io/visualizebutton.png"/>
</a>

## Notes

+	The default settings for storage are to deploy using **premium storage**, which is **strongly** recommended for S2D performance.  When using Premium Storage, be sure to select a VM size (DS-series, GS-series) that supports Premium Storage.

+   The default settings deploy 2 data disks per storage node, but can be increased to up to 32 data disks per node.  When increasing # of data disks, be sure to select a VM size that can support the # of data disks you specify.

+ 	The default settings for compute require that you have at least 2 cores of free quota to deploy.

+ 	The images used to create this deployment are
	+ 	Windows Server 2016 Datacenter Edition - Latest Image

+	To successfully deploy this template, be sure that the subnet to which the storage nodes are being deployed already exists on the specified Azure virtual network.

+   To successfully deploy this template, DNS servers should also be configured for the Azure VNET for resolving  hostnames in the DNS domain in which this cluster is deployed.  Host (A) records should exist in the DNS zone for this domain for each cluster node and the NFS file server role name.

## Deploying Sample Templates

You can deploy these samples directly through the Azure Portal or by using the scripts supplied in the root of the repo.

To deploy the sammple using the Azure Portal, click the **Deploy to Azure** button found above.

To deploy the sample via the command line (using [Azure PowerShell or the Azure CLI](https://azure.microsoft.com/en-us/downloads/)) you can use the scripts.

Simple execute the script and pass in the folder name of the sample you want to deploy.  For example:

```PowerShell
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus' -ArtifactsStagingDirectory '[foldername]'
```
```bash
azure-group-deploy.sh -a [foldername] -l eastus -u
```
If the sample has artifacts that need to be "staged" for deployment (Configuration Scripts, Nested Templates, DSC Packages) then set the upload switch on the command.
You can optionally specify a storage account to use, if so the storage account must already exist within the subscription.  If you don't want to specify a storage account
one will be created by the script or reused if it already exists (think of this as "temp" storage for AzureRM).

```PowerShell
.\Deploy-AzureResourceGroup.ps1 -ResourceGroupLocation 'eastus' -ArtifactsStagingDirectory '301-storage-spaces-direct' -UploadArtifacts 
```
```bash
azure-group-deploy.sh -a '301-storage-spaces-direct' -l eastus -u
```

Tags: ``nfs, cluster, ha, storage spaces, storage spaces direct, S2D, windows server 2016, ws2016``
