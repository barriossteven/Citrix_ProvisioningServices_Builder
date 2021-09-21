Param(
	[Parameter(Position=0,Mandatory=$true)][System.Int32]$Param_VMsToBuild,
	[Parameter(Position=1)][System.String]$Param_vCenter = "vCenter",
	[Parameter(Position=2)][System.String[]]$Param_Snapins = @(),
	[Parameter(Position=3)][System.String[]]$Param_Modules = @("C:\Program Files\Citrix\Provisioning Services Console\Citrix.PVS.SnapIn.dll","VMware.vimautomation.core"),
	[Parameter(Position=4)][System.String]$Param_PortGroupFilter = "PortGroupFilter",
	[Parameter(Position=5)][System.String]$Param_TemplateFilter = "TemplateFilter",
	[Parameter(Position=6)][System.String]$Param_DataStoreCluster = "DataStoreCluster",
	[Parameter(Position=7)][System.String[]]$Param_PVSServers = @("PVSServers"),       
	[Parameter(Position=8)][System.String]$Param_PVSTargetDevicePrefix = "PVSTargetDevicePrefix",
	[Parameter(Position=9)][System.Int32]$Param_PVSDeviceIndex = 1,
	[Parameter(Position=10)][System.String]$Param_PVSDeviceCollection = "PVSDeviceCollection",
	[Parameter(Position=11)][System.String]$Param_PVSSiteName = "PVSSiteName", 
	[Parameter(Position=12)][System.Int32]$Param_HostMaxCapacity = 40,
	[Parameter(Position=13)][System.Int32]$Param_PortGroupMaxCapacity = 220,
    [Parameter(Position=14)][System.String]$Param_HostCluster = "HostCluster",
    [Parameter(Position=15)][System.String[]]$Param_ExcludedHosts = @("ExcludedHosts")
)
$Var_Stopwatch =  [system.diagnostics.stopwatch]::StartNew()
Start-Transcript -Path $("$($PSScriptRoot)\transcript-"+$(Get-Date -format "yyyyMMddHHmmss")+"_"+$($env:Username)+".txt") 
Clear-Host
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Param_VMsToBuild VM build request submitted by $($env:UserName) on $($env:Computername)"
$Param_Snapins | % {
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Importing Snapin $_"
	Remove-PSSnapin $_ -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	Add-PSSnapin $_ -ErrorAction Stop -WarningAction SilentlyContinue
}
$Param_Modules | % {
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Importing Module $_"
	Remove-Module $_ -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
	Import-Module $_ -ErrorAction Stop -WarningAction SilentlyContinue
}
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Connecting to vCenter $Param_vCenter"
$Var_VCConn = Connect-VIServer -Server $Param_vCenter
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Retrieving PortGroup Info"
$Var_PortGroups = Get-VirtualPortGroup -Distributed | Where-Object {$_.Name -like $Param_PortGroupFilter} | Select Name, Key
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Retrieving VM Info"
$Var_VMs = Get-View -ViewType "VirtualMachine"
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Retrieving Template Info"
$Var_Templates = Get-Template | Where-Object {$_.Name -like $Param_TemplateFilter} | select -Unique
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Computing PortGroup Utilization"
$Var_PortGroups | % {
	$_ | Add-Member -MemberType NoteProperty -Name "TotalCount" -Value $([Math]::Ceiling(($Param_VMsToBuild+($Var_VMs.Count))/($Var_PortGroups.Count)))
	If(($_.TotalCount) -gt $Param_PortGroupMaxCapacity){
		$_.TotalCount = $Param_PortGroupMaxCapacity
	}
	$Var_PGName = $_.Key
	$_ | Add-Member -MemberType NoteProperty -Name "CurrentCount" -Value $(($Var_VMs.Network.Value | Where-Object {$_ -eq $Var_PGName}).Count)
	$Var_ToAdd = ($_.TotalCount) - ($_.CurrentCount)
	$_ | Add-Member -MemberType NoteProperty -Name "AvailCap" -Value $([Math]::Max(0,$Var_ToAdd))
} 
$Var_PortGroups = $Var_PortGroups | Sort-Object AvailCap -Descending 

Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Computing Esx Host Utilization"
$Var_HostCluster = Get-View -ViewType "ClusterComputeResource" | ?{$_.name -eq $Param_HostCluster}
$Var_HostCluster.UpdateViewData("host.name")
$Var_Hosts = Get-View -ViewType "HostSystem"
$Var_Hosts = $Var_Hosts | ?{($Var_HostCluster.LinkedView.Host.name) -contains $_.name}

$Var_Hosts = $Var_Hosts | % {
	$Var_Obj = $_
	$Var_HostObj = New-Object -TypeName PSObject
	$Var_HostObj | Add-Member -MemberType NoteProperty -Name "Name" -Value $($Var_Obj.Name)
	$Var_HostObj | Add-Member -MemberType NoteProperty -Name "CurrentCount" -Value $($Var_Obj.Vm.Count)
	$Var_HostObj | Add-Member -MemberType NoteProperty -Name "TotalCount" -Value $([Math]::Ceiling(($Param_VMsToBuild+($Var_VMs.Count))/($Var_Hosts.Count)))
	If(($Var_HostObj.TotalCount) -gt $Param_HostMaxCapacity){
		$Var_HostObj.TotalCount = $Param_HostMaxCapacity
	}
	$Var_ToAdd = ($Var_HostObj.TotalCount) - ($Var_HostObj.CurrentCount)
	$Var_HostObj | Add-Member -MemberType NoteProperty -Name "AvailCap" -Value $([Math]::Max(0,$Var_ToAdd))
	$Var_HostObj
} | Sort-Object AvailCap -Descending 

$Var_Hosts = $Var_Hosts | ?{$Param_ExcludedHosts -notcontains $_.name}

Set-PvsConnection -Server $($Param_PVSServers|Get-Random)
$Var_Devices = Get-PvsDeviceInfo 
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Commencing VM build process"
$Var_PVSTargetDevices = @()
1..$Param_VMsToBuild | % {
	Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ********************** Building VM $_ of $Param_VMsToBuild **********************"	

    
    $Var_DatastoreCluster = Get-View -ViewType StoragePod | ?{$_.name -eq $Param_DataStoreCluster} 
    $Var_DatastoreCluster.UpdateViewData("childentity.*")
    $Var_DataStore = $Var_DatastoreCluster.LinkedView.ChildEntity.summary | Sort-Object freespace -Descending | select -First 1 name
    
	$Var_PG = $Var_PortGroups[0].Name
	$Var_PortGroups[0].AvailCap = $Var_PortGroups[0].AvailCap - 1
	$Var_PortGroups = $Var_PortGroups | Sort-Object AvailCap -Descending 	
	$Var_EsxHost = $Var_Hosts[0].Name
	$Var_Hosts[0].AvailCap = $Var_Hosts[0].AvailCap - 1
	$Var_Hosts = $Var_Hosts | Sort-Object AvailCap -Descending 	
	$Var_HostName = $null
	Do{
		$Var_CheckHostName = ($Param_PVSTargetDevicePrefix + ($Param_PVSDeviceIndex + 2000))
		If($($Var_Devices.name) -notcontains $Var_CheckHostName){
			$Var_HostName = $Var_CheckHostName
		}
		$Param_PVSDeviceIndex = $Param_PVSDeviceIndex + 1
	} Until ($Var_HostName -ne $null)	
	If(($Var_EsxHost) -and ($Var_PG) -and ($Var_HostName)){
		Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Building VM $Var_HostName on host $Var_EsxHost connected to VLAN $Var_PG on Datastore $($var_datastore.name)"
		$Var_VMNetworkAdapter = New-VM -Name $Var_HostName.ToUpper() -Template $Var_Templates -VMHost $Var_EsxHost -Datastore $var_datastore.name -Location "Citrix" | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $Var_PG -Confirm:$false
		If($Var_VMNetworkAdapter){
			Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Importing VM $Var_HostName into PVS Device Collection $Param_PVSDeviceCollection in site $Param_PVSSiteName"
			Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Target device MAC is $($Var_VMNetworkAdapter.MacAddress)"
			$Var_PVSTargetDevices += New-PvsDevice -SiteName $Param_PVSSiteName -CollectionName $Param_PVSDeviceCollection -DeviceName $($Var_HostName.ToUpper()) -DeviceMac $($Var_VMNetworkAdapter.MacAddress -replace ":", "-")
		}
	}		
}
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ********************** Build process complete **********************"
$Var_Stopwatch.Stop()
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') Total execution time: $([Math]::Round($Var_Stopwatch.Elapsed.TotalSeconds,0)) seconds"
Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') VMs built: $($Var_PVSTargetDevices.Name)"
Stop-Transcript | Out-Null
Read-Host "Press any key to exit..."