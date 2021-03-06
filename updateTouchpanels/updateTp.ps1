Param (
        [Parameter(ValueFromPipeline=$true)]
        [string]$Csv = ".\tp.csv",
        [string]$output = ".\touchpanelUpdate_log"
    )

Import-Module PSFTP

. .\Get-Telnet.ps1
. .\Log.ps1

#CONSTANTS
$Port = "41795"
$fliptop = ".\firmware\ft600_1.500.0013.puf"
$fliptop_img = "ft.vtz"
$teclite = ".\firmware\tpmc-4sm_11.92.113.001.puf"
$teclite_img = "lite.vtz"
$hd = ".\firmware\tsxxx0_series_1.012.0017.002.puf"
$hd_img = "hd.vtz"
$fliptopPath = "$($pwd)\vtz\$($fliptop_img)"
$teclitePath = "$($pwd)\vtz\$($teclite_img)"
$hdPath = "$($pwd)\vtz\$($hd_img)"

$username = "anonymous"
$password = $username | ConvertTo-SecureString -AsPlainText -Force
$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $username, $password

#Variables
$Hnames = @()
$Ip = @()
$fw = ""

Import-Csv $Csv -Delimiter "," | `
    ForEach-Object { 
        $Hnames += $_.Host;
        $Ip += $_.IP;
    }

$Now = Get-Date -Format "yyyy-MM-ddTHH:mm:ss"

$output = "$($output)_$($Now).txt"

New-Item $output -ItemType file -force

$Ip | Foreach {
    $cmds = @()
    $InnerIP = $_

    Log -File $output -Message "Updating $($InnerIP)"
    
    $Where = [array]::IndexOf($Ip, $InnerIP )
    $H = $Hnames[$Where]

    Log -File $output -Message "$($H)"

    $IPTablePath_preEdit = "c:\repos\av-systems-automation\updateTouchpanels\" + $H + "_IPTable.csv"
    $IPTablePath = "c:\repos\av-systems-automation\updateTouchpanels\" + $H + "_IPTable.csv"
    
    $firmwareUpdatePath = "c:\repos\av-systems-automation\updateTouchpanels\" + $H + "_FW.csv"
    New-Item $IPTablePath -ItemType file -force
    
    #Get IPTable
    $IPTableEntry_Type = @();
    $IPTableEntry_Address = @();
    $IPTableEntry_IPID = @();
    Get-Telnet -RemoteHost "$InnerIP" -Commands "iptable" -OutputPath $IPTablePath_preEdit

    Log -File $output -Message "Obtained IPTable for $($InnerIP)"

    ##Determine firmware by output of iptable
    
    Set-FTPConnection -Credentials $cred -Server $InnerIP -Session TPSession -UsePassive 
    $Session = Get-FTPConnection -Session TPSession 

    $c = Get-Content $IPTablePath -Encoding byte -TotalCount 20
    [System.Text.Encoding]::Unicode.GetString($c)
    $c = [char[]](Get-Content $IPTablePath -Encoding byte -TotalCount 20)
    $c_edited = @()
    $c_edited += $c[2]
    $c_edited += $c[4]
    $tpType = -join $c_edited
    if ($tpType -match 'FT')
    {
        Add-FTPItem -Session $Session -Path "/FIRMWARE/" -LocalPath $fliptop
        $deviceType = "flip";
    }
    elseif ($tpType -match 'TS')
    {
        Add-FTPItem -Session $Session -Path "/FIRMWARE/" -LocalPath $hd
        $deviceType = "HD";
    }
    elseif ($tpType -match 'TP')
    {
        Add-FTPItem -Session $Session -Path "/FIRMWARE/" -LocalPath $teclite 
        $deviceType = "lite";
    }
    else {
        exit
    }
    Log -File $output -Message "Device Type: $($deviceType)"

    New-Item $IPTablePath -ItemType file -force
    Get-Content $IPTablePath_preEdit | Where-Object {($_ -notmatch 'IP Table') -and ($_ -notmatch '-')} | Set-Content $IPTablePath
    
    ##Update Firmware
    #Wait for Touchpanel to come back
    do {
        Write-Host "waiting..."
        sleep 3      
    } until(Test-NetConnection $InnerIP -Port $Port | ? { $_.TcpTestSucceeded } )

    New-Item $firmwareUpdatePath -ItemType file -force
    Get-Telnet -RemoteHost "$InnerIP" -Port "$Port" -OutputPath "$firmwareUpdatePath" -Commands "puf"
    
    Log -File $output -Message "Updated firmware"
    #Initialize
    do {
        Write-Host "waiting..."
        sleep 3      
    } until(Test-NetConnection $InnerIP -Port $Port | ? { $_.TcpTestSucceeded } )
    Log -File $output -Message "Initializing $($InnerIP)"
    Get-Telnet -RemoteHost "$InnerIP" -Port "$Port" -OutputPath "$firmwareUpdatePath" -Commands "initialize","y"
    Log -File $output -Message "Initialized."
    #betacleanup
    do {
        Write-Host "waiting..."
        sleep 3      
    } until(Test-NetConnection $InnerIP -Port $Port | ? { $_.TcpTestSucceeded } )
    Log -File $output -Message "Running betacleanup..."
    Get-Telnet -RemoteHost "$InnerIP" -Port "$Port" -OutputPath "$firmwareUpdatePath" -Commands "betacleanup","y"
    Log -File $output -Message "Betacleanup complete"

    ############
    #Load project
    do {
        Write-Host "waiting..."
        sleep 3      
    } until(Test-NetConnection $InnerIP -Port $Port | ? { $_.TcpTestSucceeded } )

    $projName = ""
    Log -File $output -Message "Uploading project..."
    if ($tpType -match 'FT')
    {
        Add-FTPItem -LocalPath "$($fliptopPath)" -Overwrite -Session $Session
        $projName = $fliptop_img
    }
    elseif ($tpType -match 'TS')
    {
        Add-FTPItem -LocalPath "$($hdPath)" -Overwrite -Session $Session
        $projName = $hd_img
    }
    elseif ($tpType -match 'TP')
    {
        Add-FTPItem -LocalPath "$($teclitePath)" -Overwrite -Session $Session
        $projName = $teclite_img
    }

    #Project Load
    do {
        Write-Host "waiting..."
        sleep 3      
    } until(Test-NetConnection $InnerIP -Port $Port | ? { $_.TcpTestSucceeded } )
    
    Log -File $output -Message "Loading project..."

    if ($tpType -notmatch 'TS'){
        Get-Telnet -RemoteHost "$InnerIP" -Port "$Port" -OutputPath "$firmwareUpdatePath" -Commands "cd \FTP","MOVEFILE $($projName) \ROMDISK\User\Display","reboot"
    }
    else
    {
        Get-Telnet -RemoteHost "$InnerIP" -Port "$Port" -OutputPath "$firmwareUpdatePath" -Commands "cd \FTP","MOVEFILE $($projName) \ROMDISK\user\Display","reboot"
    }
    
    do {
        Write-Host "waiting..."
        sleep 3      
    } until(Test-NetConnection $InnerIP -Port $Port | ? { $_.TcpTestSucceeded } )
    Sleep 60
    Get-Telnet -RemoteHost "$InnerIP" -Port "$Port" -OutputPath "$firmwareUpdatePath" -Commands "projectload"

    do {
        Write-Host "waiting..."
        sleep 3      
    } until(Test-NetConnection $InnerIP -Port $Port | ? { $_.TcpTestSucceeded } )
    
    Log -File $output -Message "Reloading IPTable for $($InnerIP)"

    #Parse IPTable
    Import-Csv $IPTablePath -Delimiter " " | `
    ForEach-Object { 
        $IPTableEntry_IPID += $_.CIP_ID
        $IPTableEntry_Type += $_.Type
        $IPTableEntry_Address += $_."IP Address/SiteName"
    }
    $IPTableEntry_IPID | Foreach {
        $IPTable_Where = [array]::IndexOf($IPTableEntry_IPID, $_ )
        $T = $IPTableEntry_Type[$IPTable_Where]
        $A = $IPTableEntry_Address[$IPTableEntry_Address]
        $IPTableOutput = ".\IPTableOutput.txt"

        if ($T -eq "Gway")
        {
            Get-Telnet -RemoteHost "$InnerIP" -Port "$Port" -OutputPath "$IPTableOutput" -Commands "ADDMaster $_ $A"
        }
        else
        {
            Get-Telnet -RemoteHost "$InnerIP" -Port "$Port" -OutputPath "$IPTableOutput" -Commands "ADDSlave $_ $A"            
        }
    }
}
