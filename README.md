# AMXX Stats Mod

Statistics collection and reporting plugin for AMX Mod X that sends game statistics to external API.

## Description

This plugin collects game statistics from GoldSource servers and sends them to an external API endpoint via HTTP POST requests. It tracks player sessions, kills, deaths, headshots, server performance metrics, and more.

## Features

- **Player Statistics**: Tracks kills, deaths, headshots per session
- **Session Management**: Monitors player connections and disconnections
- **Server Metrics**: Collects FPS, player count, and map information
- **Batch Processing**: Groups events for efficient API communication
- **Error Handling**: Retry queue for failed requests with file-based persistence
- **Rate Limiting**: Prevents API overload with configurable intervals
- **Real-time Updates**: Sends statistics at configurable intervals

## Installation

1. Compile the plugin:
   ```bash
   amxxpc -iinclude src/stats_mod.sma -o compiled/stats_mod.amxx
   ```

2. Copy the compiled `.amxx` file to your server's `addons/amxmodx/plugins/` directory

3. Add the plugin to `addons/amxmodx/configs/plugins.ini`:
   ```
   stats_mod.amxx
   ```

4. Copy `config/stats_mod.cfg` to `addons/amxmodx/configs/`

5. Configure the plugin (see Configuration section below)

6. Restart your server or use `amx_reloadplugins` command

## Configuration

Edit `addons/amxmodx/configs/stats_mod.cfg` to configure the plugin:

### Required Settings

- **`stats_api_url`**: Base URL of your API server (e.g., `https://api.example.com`)
  - Must include protocol (`http://` or `https://`)
  
- **`stats_server_uuid`**: Server UUID (36 characters, UUID v4 format)
  - Must match UUID from `game_servers` table in your database
  - Format: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
  - Example: `550e8400-e29b-41d4-a716-446655440000`

### Optional Settings

- **`stats_enabled`**: Enable/disable plugin (default: `1`)
- **`stats_fps_interval`**: FPS metrics collection interval in seconds (default: `60`, recommended: 30-60)
- **`stats_session_interval`**: Session update interval in seconds (default: `600`, recommended: 300-600)
- **`stats_kills_batch_size`**: Number of kills to accumulate before sending (default: `10`)
- **`stats_kills_interval`**: Maximum time to wait before sending kills batch in seconds (default: `30`, recommended: 10-30)
- **`stats_retry_delay`**: Minimum delay before retrying failed requests in seconds (default: `10`, recommended: 5+)

### Example Configuration

```
stats_enabled 1
stats_api_url "https://api.example.com"
stats_server_uuid "550e8400-e29b-41d4-a716-446655440000"
stats_fps_interval 60
stats_session_interval 600
stats_kills_batch_size 10
stats_kills_interval 30
stats_retry_delay 10
```

## API Integration

The plugin sends POST requests to `/api/v1/statistics/goldsource/batch` endpoint with JSON payloads containing:

- **servers**: Server information (sent on startup)
- **users**: New player registrations (first connect)
- **sessions**: Player session data (start/end times, stats)
- **kills**: Kill events (killer, victim, weapon, headshot)
- **fps**: Server performance metrics (FPS, player count, map)
- **counters**: Custom counters (for future use)

### Batch Frequency

- **FPS metrics**: Every 30-60 seconds (configurable)
- **Sessions**: On disconnect or every 5-10 minutes for active players
- **Kills**: Batched every 10-30 seconds or when batch size reached
- **Server info**: Only on startup or configuration change
- **Users**: On first player connection

### Error Handling

Failed requests are automatically saved to `addons/amxmodx/data/stats_mod/queue/` directory and retried periodically. The plugin respects rate limiting (minimum 5 seconds between requests).

## Build Instructions

### Quick Build

**Windows:**
```bash
build.bat
```

The script will automatically search for the compiler in:
- Environment variable `AMXXPC_PATH`
- System PATH
- Standard installation paths (`C:\Program Files\AMX Mod X\scripting\`)
- Common server locations

**Linux/Mac:**
```bash
chmod +x build.sh
./build.sh
```

### Setting Up Compiler Path

If the compiler is not found automatically, you have several options:

**Option 1: Set Environment Variable (Recommended)**
```bash
setx AMXXPC_PATH "C:\Program Files\AMX Mod X\scripting\amxxpc.exe"
```
Then restart your terminal and run `build.bat`

**Option 2: Add to PATH**
Add the directory containing `amxxpc.exe` to your system PATH environment variable.

**Option 3: Use build-config.bat**
Copy `build-config.example.bat` to `build-config.bat` and set your compiler path there.

**Option 4: Manual Build**
If you know the path to compiler:
```bash
"C:\Program Files\AMX Mod X\scripting\amxxpc.exe" -iinclude src/stats_mod.sma -ocompiled/stats_mod.amxx
```

### Requirements

- AMX Mod X compiler (`amxxpc.exe`)
- Download from: https://www.amxmodx.org/downloads.php

### Build Output

After successful compilation, the plugin file will be located at:
```
compiled/stats_mod.amxx
```

### Dependencies

- AMX Mod X 1.8.1 or higher
- Required modules:
  - `amxmodx` (core)
  - `fakemeta` (for game events)
  - `hamsandwich` (for player hooks)
  - `sockets` (for HTTP requests)

## Project Structure

```
amxx-stats-mod/
├── src/
│   └── stats_mod.sma          # Main plugin source
├── include/
│   └── stats_mod.inc          # Include file with definitions
├── config/
│   └── stats_mod.cfg          # Configuration file
└── README.md                  # This file
```

## Data Collection

The plugin collects the following statistics:

- **Player Sessions**: Start/end times, map, kills, deaths, headshots
- **Kill Events**: Killer, victim, weapon, headshot status, timestamp
- **Server Metrics**: FPS, online player count, current map
- **User Registration**: SteamID, name, first connection timestamp
- **Server Information**: UUID, name, address, max players

## Troubleshooting

### Plugin not sending data

1. Check that `stats_enabled` is set to `1`
2. Verify `stats_api_url` and `stats_server_uuid` are configured correctly
3. Check server logs for error messages
4. Ensure the API server is accessible from your game server

### UUID validation errors

- Ensure UUID is exactly 36 characters
- Format must be: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`
- UUID must exist in your database `game_servers` table

### Network errors

- Failed requests are saved to queue directory
- Check `addons/amxmodx/data/stats_mod/queue/` for queued batches
- Plugin will automatically retry failed requests

## Version

Current version: 1.0.0

## License

[Add your license here]

## Author

[Add your name/contact information here]

