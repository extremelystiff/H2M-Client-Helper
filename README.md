# H2M-Server-Launcher
The H2M Server Browser is a tool designed to enhance the multiplayer experience for players of the H2M mod for Call of Duty: Modern Warfare Remastered.

## Features

Fetches server data from the H2M master server
Displays server information including hostname, IP, port, map, game type, player count, and ping
Allows sorting servers by various criteria
Ping servers to check latency
Double-click a server to connect directly in-game
Save favorite servers based on ping or player count
Supports other games in addition to H2M

### Installation

Ensure you have PowerShell installed on your Windows system
Download the H2MServerBrowser.ps1 script
Place the script in a convenient location

#### Usage

Right-click the H2MServerBrowser.ps1 script and select "Run with PowerShell"
The H2M Server Browser window will appear
Select your desired game from the dropdown (defaults to H2M)
Click "Fetch Servers" to retrieve the server list
Optionally, click "Ping Servers" to check server latencies
Double-click a server to connect to it in-game

Ensure H2M is running before attempting to connect


Check the "Save Top 100" boxes and click "Save IPs" to save your favorite servers

Favorites are saved to favourites.json in the players2 subfolder
