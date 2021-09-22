# Citrix_ProvisioningServices_Builder

## .SYNOPSIS

Citrix Provisioning Services has a built-in wizard to automate the create of virtual machines to be latered used for non-persistent VDI. However, the wizard does not allow proper load-balanced of resources on hypervisor hosts, network subnets, and storage components. 

New-PVSBuild will let you prep and build virtual machines and automatically import in to Citrix Provisining Services for non-persistent VDI usage. 

## .DESCRIPTION

The built-in streamed-vm wizard and xendesktop wizard in Citrix Provisioning Services is a very simple tool used to to build non-persistent VDI. However, given constraints in our environment and desire to properly load-balance infrastructure resources, this tool was created to have better resource distribution when creating virtual machines.

This utility will connect to the targetted VMWare vCenter and Citrix PVS Site. Based on the desire VM template in vCenter, the utility will build however machines are requested. Upon building, the utility will properly place the virtual machine on the best available hypervisor host and storage datastore. Additionally, if multiple subnets are available for use, the utility will properly allocate a network adapter and set the proper vlan information. 

This utility allows for full resource load-balancing ensuring one area is not overly stressed. 

## .ACCOMPLISHMENTS/WHAT I LEARNED

Was able to circumvent the limitations of a built-in product and custom tailoring the process to my needs. There is no need to sacrifice design quality because of the established interfaces. Given the proper SDKs and modules, the same process can be enhanced and tailored to one's needs. 

## .AREAS OF IMPROVEMENT

Given the dynamics of Citrix PVS administration and volatility of OS images/OUs, the AD machine account creation process and vDisk assignments were omitted from this process. Once the VMs are built and imported into PVS, they are placed in a 'staging' collection where you can create the machine account in your desired OU and assign the vdisk. 

If circumstances change and OU/vdisk assignments were to settle down, both of these processes can easily be added to this utility further maximizing efficiency.

## .NOTES
Script was created using Powershell 5.1. 

PowerCLI, and Citrix Broker SDK are required.






