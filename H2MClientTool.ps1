Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net

$ErrorActionPreference = "Stop"

function Is-H2M {
    param($h, $m, $g) 
    $h -match "H2M" -or "mp_broadcast","mp_crash","mp_crossfire","mp_shipment" -contains $m -or "war","dom","sab","koth" -contains $g
}


function Fetch-Servers {
    param($progressBar, $listView)
    try {
        $progressBar.Value = 0
        $progressBar.Maximum = 100
        $progressBar.Value = 10
        
        $selectedGame = $gameDropdown.SelectedItem
        $response = Invoke-WebRequest "https://master.iw4.zip/servers" -UseBasicParsing
        $progressBar.Value = 30
        
        Write-Host "Fetching servers for $selectedGame"
        Write-Host "Response content length: $($response.Content.Length)"
        
        $progressBar.Value = 50
        
        $script:servers = @()
        
        # Extract the content of the specific game's servers div
        $gameServersMatch = $response.Content | Select-String "(?s)<div class=`"game-server-panel.*?`" id=`"${selectedGame}_servers`">(.*?)</div>\s*(?:<div class=`"game-server-panel|$)" -AllMatches
        
        if ($null -ne $gameServersMatch -and $gameServersMatch.Matches.Count -gt 0) {
            $gameServers = $gameServersMatch.Matches[0].Groups[1].Value
            Write-Host "Found game servers div. Content length: $($gameServers.Length)"
            
            $serverRowsMatch = $gameServers | Select-String '(?s)<tr class="server-row".*?</tr>' -AllMatches
            
            if ($null -ne $serverRowsMatch -and $serverRowsMatch.Matches.Count -gt 0) {
                Write-Host "Found $($serverRowsMatch.Matches.Count) server rows for $selectedGame"
                foreach ($row in $serverRowsMatch.Matches) {
                    $serverDataMatch = $row.Value | Select-String '(?s)data-ip="([^"]+)".*?data-port="([^"]+)".*?data-hostname="([^"]+)".*?data-map="([^"]+)".*?data-clientnum="(\d+)".*?data-maxclientnum="(\d+)".*?data-gametype="([^"]+)"'
                    if ($null -ne $serverDataMatch -and $serverDataMatch.Matches.Count -gt 0) {
                        $match = $serverDataMatch.Matches[0]
                        $script:servers += [PSCustomObject]@{
                            IP = $match.Groups[1].Value
                            Port = [int]$match.Groups[2].Value
                            Hostname = [System.Net.WebUtility]::HtmlDecode($match.Groups[3].Value)
                            Map = $match.Groups[4].Value
                            CurrentPlayers = [int]$match.Groups[5].Value
                            MaxPlayers = [int]$match.Groups[6].Value
                            GameType = $match.Groups[7].Value
                            Ping = "N/A"
                        }
                    } else {
                        Write-Host "Failed to match server data in row: $($row.Value)"
                    }
                }
            } else {
                Write-Host "No server rows found for $selectedGame"
                Write-Host "Game servers div content: $gameServers"
            }
        } else {
            Write-Host "No content found for $selectedGame"
            Write-Host "Searching for: <div class=`"game-server-panel.*?`" id=`"${selectedGame}_servers`">"
            $allDivs = $response.Content | Select-String "(?s)<div class=`"game-server-panel.*?`" id=`"(\w+)_servers`">" -AllMatches
            if ($null -ne $allDivs -and $allDivs.Matches.Count -gt 0) {
                Write-Host "All game server divs found: $($allDivs.Matches | ForEach-Object { $_.Groups[1].Value })"
            } else {
                Write-Host "No game server divs found in the HTML content."
            }
        }
        
        $progressBar.Value = 80
        
        Update-ListView
        
        $progressBar.Value = 100
        Write-Host "Fetched $($script:servers.Count) servers for $selectedGame"
        
        if ($script:servers.Count -eq 0) {
            Write-Host "No servers found for $selectedGame. Try selecting a different game from the dropdown."
        }
        
        return $true
    } catch {
        $errorMessage = "Error fetching servers: $_`n`nStack Trace:`n$($_.ScriptStackTrace)"
        Write-Host $errorMessage
        [System.Windows.Forms.MessageBox]::Show($errorMessage, "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
}

function Update-ListView {
    $listView.BeginUpdate()
    $listView.Items.Clear()
    foreach ($server in $script:servers) {
        $item = New-Object System.Windows.Forms.ListViewItem($server.Hostname)
        $item.SubItems.Add($server.IP)
        $item.SubItems.Add($server.Port.ToString())
        $item.SubItems.Add($server.Map)
        $item.SubItems.Add($server.GameType)
        $item.SubItems.Add("$($server.CurrentPlayers)/$($server.MaxPlayers)")
        $item.SubItems.Add($server.Ping)
        $listView.Items.Add($item)
    }
    $listView.EndUpdate()
}

function Ping-Servers {
    param($progressBar, $listView)

    $totalServers = $script:servers.Count
    $progressBar.Maximum = $totalServers
    $progressBar.Value = 0

    $pingTasks = @{}

    foreach ($server in $script:servers) {
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $pingTasks[$server] = $ping.SendPingAsync($server.IP, 999)
        }
        catch {
            Write-Host "Error initiating ping for $($server.IP): $($_.Exception.Message)"
        }

        # Small delay to prevent overwhelming the network
        Start-Sleep -Milliseconds 1
    }

    foreach ($server in $script:servers) {
        try {
            if ($pingTasks.ContainsKey($server)) {
                $task = $pingTasks[$server]
                if ($task.Wait(1000)) {  # Wait up to 1 second for task completion
                    $reply = $task.Result
                    if ($reply.Status -eq 'Success') {
                        $server.Ping = $reply.RoundtripTime
                    } else {
                        $server.Ping = 999
                    }
                } else {
                    $server.Ping = 999
                }
            } else {
                $server.Ping = 999
            }
        }
        catch {
            $server.Ping = 999
            Write-Host "Error processing ping result for $($server.IP): $($_.Exception.Message)"
        }

        # Update ListView
        $item = $listView.Items[$script:servers.IndexOf($server)]
        $item.SubItems[6].Text = $server.Ping.ToString()

        # Update progress bar
        $progressBar.Value = [Math]::Min($progressBar.Value + 1, $totalServers)
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Save-Favorites {
    param($saveTop100Ping = $false, $saveTop100Players = $false)
    try {
        $favoritesDir = ".\players2"
        if (-not (Test-Path $favoritesDir)) {
            New-Item -ItemType Directory -Path $favoritesDir -Force | Out-Null
        }
        
        if ($saveTop100Ping -or $saveTop100Players) {
            if ($saveTop100Players) {
                $serversToSave = $script:servers | Where-Object { $_.CurrentPlayers -gt 0 } |
                                 Sort-Object { [int]$_.CurrentPlayers } -Descending |
                                 Select-Object -First 100
            }
            if ($saveTop100Ping) {
                $pingServers = $script:servers | Where-Object { $_.Ping -ne "N/A" -and $_.Ping -ne 999 } |
                               Sort-Object { [int]$_.Ping } |
                               Select-Object -First 100
                $serversToSave = if ($saveTop100Players) {
                    ($serversToSave + $pingServers | Sort-Object IP -Unique | Sort-Object { [int]$_.CurrentPlayers } -Descending | Select-Object -First 100)
                } else {
                    $pingServers
                }
            }
        } else {
            $serversToSave = $script:servers
        }
        
        $favoriteServers = $serversToSave | ForEach-Object { "`"$($_.IP):$($_.Port)`"" }
        $json = "[" + ($favoriteServers -join ", ") + "]"
        Set-Content "$favoritesDir\favourites.json" $json -NoNewline
        
        $message = if ($saveTop100Ping -or $saveTop100Players) { 
            "Saved top 100 servers to favourites.json based on selected criteria" 
        } else { 
            "Saved all servers to favourites.json" 
        }
        [System.Windows.Forms.MessageBox]::Show($message, "Success", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Error saving favorites: $_`n`nStack Trace:`n$($_.ScriptStackTrace)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Connect-To-Server {
    param($ip, $port)
    try {
        # Check if H2M-Mod is running
        $process = Get-Process "H2M-Mod" -ErrorAction SilentlyContinue
        if (-not $process) {
            throw "H2M-Mod is not running. Please start the game before connecting to a server."
        }

        # Activate the H2M-Mod window
        $wshell = New-Object -ComObject wscript.shell
        $wshell.AppActivate($process.MainWindowTitle)
        Start-Sleep -Milliseconds 1

        # Send backtick key, connect command, and Enter
        [System.Windows.Forms.SendKeys]::SendWait("``")
        Start-Sleep -Milliseconds 1
        [System.Windows.Forms.SendKeys]::SendWait("connect $ip`:$port{ENTER}")
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Error connecting to server: $_`n`nStack Trace:`n$($_.ScriptStackTrace)", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "Server Browser"
$form.Size = New-Object System.Drawing.Size(800, 600)

$listView = New-Object System.Windows.Forms.ListView
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.GridLines = $true
$listView.Location = New-Object System.Drawing.Point(10, 10)
$listView.Size = New-Object System.Drawing.Size(760, 480)

$listView.Columns.Clear()
$listView.Columns.Add("Hostname", 250) | Out-Null
$listView.Columns.Add("IP", 120) | Out-Null
$listView.Columns.Add("Port", 50) | Out-Null
$listView.Columns.Add("Map", 100) | Out-Null
$listView.Columns.Add("GameType", 80) | Out-Null
$listView.Columns.Add("Players", 60) | Out-Null
$listView.Columns.Add("Ping", 60) | Out-Null

# Add double-click event handler
$listView.Add_DoubleClick({
    $selectedItem = $listView.SelectedItems[0]
    if ($selectedItem) {
        $ip = $selectedItem.SubItems[1].Text
        $port = $selectedItem.SubItems[2].Text
        Connect-To-Server -ip $ip -port $port
    }
})

# Add sorting functionality
$listView.Add_ColumnClick({
    param($sender, $e)
    $column = $e.Column
    $currentSort = $script:currentSort

    if ($currentSort.Column -eq $column) {
        $currentSort.Descending = !$currentSort.Descending
    } else {
        $currentSort.Column = $column
        $currentSort.Descending = $false
    }

    $script:servers = switch ($column) {
        2 { # Port
            if ($currentSort.Descending) {
                $script:servers | Sort-Object {[int]$_.Port} -Descending
            } else {
                $script:servers | Sort-Object {[int]$_.Port}
            }
        }
        5 { # Players
            if ($currentSort.Descending) {
                $script:servers | Sort-Object {[int]$_.CurrentPlayers} -Descending
            } else {
                $script:servers | Sort-Object {[int]$_.CurrentPlayers}
            }
        }
        6 { # Ping
            if ($currentSort.Descending) {
                $script:servers | Sort-Object {[int]$_.Ping} -Descending
            } else {
                $script:servers | Sort-Object {[int]$_.Ping}
            }
        }
        default {
            if ($currentSort.Descending) {
                $script:servers | Sort-Object {$_.$($listView.Columns[$column].Text)} -Descending
            } else {
                $script:servers | Sort-Object {$_.$($listView.Columns[$column].Text)}
            }
        }
    }

    Update-ListView
})

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 500)
$progressBar.Size = New-Object System.Drawing.Size(760, 20)

$fetchButton = New-Object System.Windows.Forms.Button
$fetchButton.Location = New-Object System.Drawing.Point(10, 530)
$fetchButton.Size = New-Object System.Drawing.Size(100, 30)
$fetchButton.Text = "Fetch Servers"
$fetchButton.Add_Click({
    $fetchButton.Enabled = $false
    $pingButton.Enabled = $false
    $saveButton.Enabled = $false
    $gameDropdown.Enabled = $false
    
    $success = Fetch-Servers $progressBar $listView
    
    $fetchButton.Enabled = $true
    $pingButton.Enabled = $success
    $saveButton.Enabled = $success
    $gameDropdown.Enabled = $true
})

$pingButton = New-Object System.Windows.Forms.Button
$pingButton.Location = New-Object System.Drawing.Point(120, 530)
$pingButton.Size = New-Object System.Drawing.Size(100, 30)
$pingButton.Text = "Ping Servers"
$pingButton.Enabled = $false
$pingButton.Add_Click({
    $fetchButton.Enabled = $false
    $pingButton.Enabled = $false
    $saveButton.Enabled = $false
    
    Ping-Servers $progressBar $listView
    
    $fetchButton.Enabled = $true
    $pingButton.Enabled = $true
    $saveButton.Enabled = $true
})

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Location = New-Object System.Drawing.Point(230, 530)
$saveButton.Size = New-Object System.Drawing.Size(150, 30)
$saveButton.Text = "Save IPs"
$saveButton.Enabled = $false
$saveButton.Add_Click({
    Save-Favorites -saveTop100Ping $saveTop100CheckBox.Checked -saveTop100Players $saveTop100PlayersCheckBox.Checked
})


$saveTop100CheckBox = New-Object System.Windows.Forms.CheckBox
$saveTop100CheckBox.Location = New-Object System.Drawing.Point(390, 535)
$saveTop100CheckBox.Size = New-Object System.Drawing.Size(200, 20)
$saveTop100CheckBox.Text = "Save Top 100 Lowest Pings"

$saveTop100PlayersCheckBox = New-Object System.Windows.Forms.CheckBox
$saveTop100PlayersCheckBox.Location = New-Object System.Drawing.Point(390, 555)  # Adjust the Y coordinate as needed
$saveTop100PlayersCheckBox.Size = New-Object System.Drawing.Size(200, 20)
$saveTop100PlayersCheckBox.Text = "Save Top 100 Most Player Servers"
$form.Controls.Add($saveTop100PlayersCheckBox)

$form.Controls.Add($listView)
$form.Controls.Add($progressBar)
$form.Controls.Add($fetchButton)
$form.Controls.Add($pingButton)
$form.Controls.Add($saveButton)
$form.Controls.Add($saveTop100CheckBox)

$gameDropdown = New-Object System.Windows.Forms.ComboBox
$gameDropdown.Location = New-Object System.Drawing.Point(600, 530)
$gameDropdown.Size = New-Object System.Drawing.Size(100, 30)
$gameDropdown.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$games = @("COD", "H1", "H2M", "IW3", "IW4", "IW5", "IW6", "L4D2", "SHG1", "T4", "T5", "T6", "T7")
$gameDropdown.Items.Clear()
$gameDropdown.Items.AddRange($games)
$gameDropdown.SelectedIndex = $games.IndexOf("H2M")
$form.Controls.Add($gameDropdown)

$script:currentSort = @{
    Column = 0
    Descending = $false
}

$form.ShowDialog() | Out-Null
