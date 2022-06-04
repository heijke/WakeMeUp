# Include WPF
Add-Type -AssemblyName PresentationFramework

# Variables
$DstPort = 9
$NICDevices = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} 
$IfID = $NICDevices.ifIndex
$LANDevices = Get-NetNeighbor -AddressFamily IPv4 -State Reachable -ifIndex $IfID
[Byte[]]$SyncStream = (,0xFF * 6)
[Byte[]]$EthType = (0x08, 0x42)

$DebugPreference = "Continue"

# BEGIN XAML WPF Window definition
# Generated with the help of https://app.poshgui.com/
$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Wake on LAN Magic packet sender" Width="500" Height="400" ResizeMode="CanMinimize">
<Grid>
<Grid HorizontalAlignment="Left" VerticalAlignment="Top" Width="450" Height="375" Margin="25,25,0,0">
<Label HorizontalAlignment="Left" VerticalAlignment="Top" Content="Wake on LAN Magic packet sender" Margin="10,10,0,0" Name="WOLLabel"/>
<Label HorizontalAlignment="Left" VerticalAlignment="Top" Content="From Device MAC" Margin="10,45,0,0" Name="FromMACLabel"/>
<ComboBox HorizontalAlignment="Left" VerticalAlignment="Top" Width="117" Margin="125,45,0,0" Height="25" Name="FromMAC"/>
<Label HorizontalAlignment="Left" VerticalAlignment="Top" Content="To Device MAC" Margin="10,85,0,0" Name="ToMACLabel"/>
<ComboBox HorizontalAlignment="Left" VerticalAlignment="Top" Width="117" Margin="125,85,0,0" Height="25" Name="ToMAC"/>
<Label HorizontalAlignment="Left" VerticalAlignment="Top" Content="To Device IP" Margin="10,125,0,0" Name="ToIPLabel"/>
<Label HorizontalAlignment="Left" VerticalAlignment="Top" Content="xx.xx.xx.xx" Margin="125,125,0,0" Name="ToIP"/>
<TextBlock HorizontalAlignment="Left" VerticalAlignment="Top" TextWrapping="Wrap" Margin="10,170,0,0" Width="350" Name="Desc">This script enables you to send a Magic packet to a device on the same network, provided the destination device supports being woken up.<LineBreak/>It is also worth considering, that perhaps, the destination device, would rather just sleep.</TextBlock>
<Image HorizontalAlignment="Left" Height="100" VerticalAlignment="Top" Width="100" Margin="15,237,0,0"/>
<Button Content="WAKE UP!" HorizontalAlignment="Left" VerticalAlignment="Top" Width="90" Margin="350,275,0,0" Opacity="0.9500000000000001" Background="#a99af3" BorderBrush="#9687e0" OpacityMask="#c953ce" Name="Button"/>
</Grid>
</Grid>
</Window>
"@

# END XAML WPF Window definition

# BEGIN Functions

# Assembless the magic packet in the correct format 
# (Destination MAC + Source MAC + Ethernet type header 
# + Synchronization stream of 0xFF * 6 + Destination MAC * 16)
function AssembleRawBytes {
    Param(
        [Byte[]]$Dst,
        [Byte[]]$Src
    )
    [Byte[]]$MagicPacket = $Dst
    $MagicPacket += $Src
    $MagicPacket += $EthType
    $MagicPacket += $SyncStream
    $MagicPacket += ($Dst * 16)
    return $MagicPacket
}

# Sends the Assembled byte array over raw socket
# Sadly, is not recognized by Wireshark as WoL packet
# Since still, somehow some header info is added...
function SendMagicRaw {
    Param(
        [Byte[]]$Buffer
    )
    $Destination = New-Object Net.IPEndpoint([Net.IPAddress]::Broadcast, $DstPort)
    $Socket = New-object System.Net.Sockets.Socket([Net.Sockets.AddressFamily]::InterNetwork,[Net.Sockets.SocketType]::Raw,[Net.Sockets.ProtocolType]::Raw)
    $Socket.SetSocketOption( "Socket", "Broadcast", 1 )
    $Socket.SetSocketOption( "Socket", "Debug", 1 )
    #$Socket.SetSocketOption( "Socket", "DontRoute", 1 )
    #$Socket.SetSocketOption( "IP", "HeaderIncluded", $true )
    #$Socket.Connect("255.255.255.255", $DstPort)
    try{
    for($i = 0; $i -lt 50; $i++){
    $Socket.SendTo($Buffer, $Destination)
    }
        $MsgBox = [Windows.MessageBox]::Show("Magic Packet was sent to the destination of $($ToMAC.SelectedValue)", "Magic Packet sent", "OK")    
    } catch [System.Management.Automation.MethodInvocationException] {
        $MsgBox = [Windows.MessageBox]::Show("I did not think this project through.`nSocket permissions on Windows do not allow me to send raw bytes through socket...`nSorry :(.", "Magic Packet NOT sent", "OK")    
    }  finally {
        $Socket.Close()
    }
    Write-Debug "Contents of sent buffer: $Buffer"
}

# Just for testing...
#function SendMagicUDP {
#    Param(
#        [Byte[]]$Buffer
#    )
#    $Destination = New-Object Net.IPEndpoint([Net.IPAddress]::Broadcast, $DstPort)
#    $UDPSocket = New-object System.Net.Sockets.UdpClient
#    $UDPSocket.Connect($Destination)
#    for($i = 0; $i -lt 50; $i++){
#    $UDPSocket.Send($Buffer, $Buffer.Length)
#    }
#    $UDPSocket.Close()
#}

# END Functions
 
# BEGIN Window display

# Display the window as defined by the xaml
try{$Window = [Windows.Markup.XamlReader]::Parse($Xaml)}
catch{throw}

[xml]$xml = $Xaml

# Make all the properties of GUI visible and reachable from script
try {$xml.SelectNodes("//*[@Name]") | ForEach-Object {Set-Variable -Name $_.Name -Value $Window.FindName($_.Name) -ErrorAction Stop}}
catch{throw}

# BEGIN Logic

# Add devices MACs to ComboBox dropdown
$NICDevices.MacAddress | ForEach-Object {[void] $FromMAC.Items.Add($_)}

$LANDevices.LinkLayerAddress | ForEach-Object {[void] $ToMAC.Items.Add($_)}

# On ComboBox dropdown selection change, update relevant values
$FromMAC.Add_SelectionChanged{ $IfID = $NICDevices[$FromMAC.SelectedIndex].ifIndex
                               # Format the given MAC addresses
                               $Script:SrcMAC = $($FromMAC.SelectedValue -split "-" | ForEach-Object {[Byte]"0x$_"})
}

$ToMAC.Add_SelectionChanged{ $ToIp.Content = $LANDevices[$ToMAC.SelectedIndex].IPAddress
                             # Format the given MAC addresses
                             $Script:DstMAC = $($ToMAC.SelectedValue -split "-" | ForEach-Object {[System.Convert]::ToByte($_, 16)})
}

$Button.Add_Click{
SendMagicRaw -Buffer (AssembleRawBytes -Dst $DstMAC -Src $SrcMAC)
# Just for testing...
#SendMagicUDP -Buffer (AssembleRawBytes)
}
# END Logic

[void]$Window.Dispatcher.InvokeAsync{$Window.ShowDialog()}.Wait()

# END Window display
