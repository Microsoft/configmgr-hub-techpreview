<#
.SYNOPSIS
    Gets the pending reboot status on a local computer.

.DESCRIPTION
    This function will query the registry on a local computer and determine if the
    system is pending a reboot, from Microsoft updates, Configuration Manager Client SDK, Pending Computer 
	Rename, Domain Join or Pending File Rename Operations. By default, the "Pending File Rename" condition does
	NOT trigger the script to return 'PendingReboot'.

	EXTRA STEPS:
	In SCCM console, add the following parameter validation for 'PendingFileNameIsCritical':
		Description: "By default, the "Pending File Rename" condition does NOT trigger the script to return $True for a pending reboot.  Set this to "True" to override this behavior."
		Minimum length: 4
		Maximum length: 5
		Regular expression: ^(?:(?:T|t)(?:R|r)(?:U|u)(?:E|e)|(?:F|f)(?:A|a)(?:L|l)(?:S|s)(?:E|e))$
		Customer error: "Parameter value must be either 'True' or 'False'"

.EXAMPLE
    PS C:\> Get-PendingReboot -Verbose
	
    Computer           : WKS01
    CBServicing        : False
    WindowsUpdate      : True
    CCMClient          : False
    PendComputerRename : False
    PendFileRename     : False
    PendFileRenVal     : 
	RebootPending      : True
	
	PendingReboot
	
    This example will query the local machine for pending reboot information.
	
.LINK
    Component-Based Servicing:
    http://technet.microsoft.com/en-us/library/cc756291(v=WS.10).aspx
	
    PendingFileRename/Auto Update:
    http://support.microsoft.com/kb/2723674
    http://technet.microsoft.com/en-us/library/cc960241.aspx
    http://blogs.msdn.com/b/hansr/archive/2006/02/17/patchreboot.aspx

    SCCM 2012/CCM_ClientSDK:
	http://msdn.microsoft.com/en-us/library/jj902723.aspx
	
#>
#Requires -Version 3.0
[CmdletBinding()]
param
(
	[parameter(Mandatory=$false)]
	[ValidateScript({
		$_ -eq $true.ToString() -or $_ -eq $false.ToString()
	})]
	[string] $PendingFileRenameIsCritical = "False"
)
Process
{
	$PendingFileRenameIsCritical = [System.Convert]::ToBoolean($PendingFileRenameIsCritical)
	Try
	{
	    ## Setting pending values to false to cut down on the number of else statements
	    $CompPendRen,$PendFileRename,$Pending,$SCCM = $false,$false,$false,$false
                        
	    ## Setting CBSRebootPend to null since not all versions of Windows has this value
	    $CBSRebootPend = $null
						
	    ## Querying WMI for build version
	    $WMI_OS = Get-WmiObject -Class Win32_OperatingSystem -Property BuildNumber, CSName -ErrorAction Stop

	    ## Making registry connection to the local/remote computer
	    $HKLM = [UInt32] "0x80000002"
	    $WMI_Reg = [WMIClass] "root\default:StdRegProv"
						
	    ## If Vista/2008 & Above query the CBS Reg Key
		If ([Int32]$WMI_OS.BuildNumber -ge 6001)
		{
		    $RegSubKeysCBS = $WMI_Reg.EnumKey($HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\")
		    $CBSRebootPend = $RegSubKeysCBS.sNames -contains "RebootPending"
	    }
							
	    ## Query WUAU from the registry
	    $RegWUAURebootReq = $WMI_Reg.EnumKey($HKLM,"SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\")
	    $WUAURebootReq = $RegWUAURebootReq.sNames -contains "RebootRequired"

	    ## Query PendingFileRenameOperations from the registry
	    $RegSubKeySM = $WMI_Reg.GetMultiStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\Session Manager\","PendingFileRenameOperations")
	    $RegValuePFRO = $RegSubKeySM.sValue

	    ## Query JoinDomain key from the registry - These keys are present if pending a reboot from a domain join operation
	    $Netlogon = $WMI_Reg.EnumKey($HKLM,"SYSTEM\CurrentControlSet\Services\Netlogon").sNames
	    $PendDomJoin = ($Netlogon -contains 'JoinDomain') -or ($Netlogon -contains 'AvoidSpnSet')

	    ## Query ComputerName and ActiveComputerName from the registry
	    $ActCompNm = $WMI_Reg.GetStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName\","ComputerName")
	    $CompNm = $WMI_Reg.GetStringValue($HKLM,"SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName\","ComputerName")

		If (($ActCompNm -ne $CompNm) -or $PendDomJoin)
		{
	        $CompPendRen = $true
	    }

	    ## If PendingFileRenameOperations has a value set $RegValuePFRO variable to $true
		If ($RegValuePFRO)
		{
		    $PendFileRename = $true
	    }

	    ## Determine SCCM 2012 Client Reboot Pending Status
	    ## To avoid nested 'if' statements and unneeded WMI calls to determine if the CCM_ClientUtilities class exist, setting EA = 0
	    $CCMClientSDK = $null
	    $CCMSplat = @{
	        NameSpace='ROOT\ccm\ClientSDK'
	        Class='CCM_ClientUtilities'
	        Name='DetermineIfRebootPending'
	        ErrorAction='Stop'
	    }
	    ## Try CCMClientSDK
		Try
		{
	        $CCMClientSDK = Invoke-WmiMethod @CCMSplat
		}
		Catch [System.UnauthorizedAccessException]
		{
	        $CcmStatus = Get-Service -Name CcmExec -ComputerName $ComputerName -ErrorAction SilentlyContinue
			If ($CcmStatus.Status -ne 'Running')
			{
	            Write-Warning "$ComputerName`: Error - CcmExec service is not running."
	            $CCMClientSDK = $null
	        }
		}
		Catch
		{
	        $CCMClientSDK = $null
	    }

		If ($CCMClientSDK)
		{
			If ($CCMClientSDK.ReturnValue -ne 0)
			{
		        Write-Warning "Error: DetermineIfRebootPending returned error code $($CCMClientSDK.ReturnValue)"          
		    }
			If ($CCMClientSDK.IsHardRebootPending -or $CCMClientSDK.RebootPending)
			{
		        $SCCM = $true
		    }
	    }
		Else
		{
	        $SCCM = $null
		}
		
		## Creating Custom PSObject and Select-Object Splat
	    $SelectSplat = @{
	        Property=(
	            'CBServicing',
	            'WindowsUpdate',
	            'CCMClientSDK',
	            'PendComputerRename',
	            'PendFileRename',
	            'PendFileRenVal',
	            'RebootPending'
	        )}
	    Write-Verbose $(New-Object -TypeName PSObject -Property @{
	        CBServicing=$CBSRebootPend
	        WindowsUpdate=$WUAURebootReq
	        CCMClientSDK=$SCCM
	        PendComputerRename=$CompPendRen
	        PendFileRename=$PendFileRename
	        PendFileRenVal=$RegValuePFRO
	        RebootPending=($CompPendRen -or $CBSRebootPend -or $WUAURebootReq -or $SCCM -or ($PendFileRename -and [System.Convert]::ToBoolean($PendingFileRenameIsCritical)))
	    } | Select-Object @SelectSplat | Out-String)

		if ($CBSRebootPend -or $WUAURebootReq -or $CompPendRen -or $SCCM -or ($PendFileRename -and [System.Convert]::ToBoolean($PendingFileRenameIsCritical)))
		{
			Write-Output "PendingReboot"
		}
		else
		{
			Write-Output "NoRebootNeeded"
		}
	}
	Catch
	{
	    return $("ERROR -- {0}" -f $_.Exception.Message)
	}
}