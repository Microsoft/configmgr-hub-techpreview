
# Find last time system was turned on
$os = Get-WmiObject -Class win32_operatingsystem
$startTime = $os.ConvertToDateTime($os.LastBootUpTime)

# Find out when first GP cycle after last boot completed

#Get-EventLog -LogName System  -After $bootupTime | Where 


$booted = (Get-WinEvent -FilterHashTable @{ LogName = "System"; StartTime = $startTime; ID = 6005 }).TimeCreated



return $booted-$startTime
#Get-WinEvent -LogName 'Microsoft-Windows-Winlogon/Operational' | select 