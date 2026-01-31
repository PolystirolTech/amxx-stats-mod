# AMXX Stats Mod

Statistics collection and reporting plugin for AMX Mod X.

## Description

This plugin collects game statistics and reports them to external systems. The plugin is currently in early development with basic structure in place.

## Installation

1. Compile the plugin:
   ```
   amxxpc src/stats_mod.sma -o compiled/stats_mod.amxx
   ```

2. Copy the compiled `.amxx` file to your server's `addons/amxmodx/plugins/` directory

3. Add the plugin to `addons/amxmodx/configs/plugins.ini`:
   ```
   stats_mod.amxx
   ```

4. Copy `config/stats_mod.cfg` to `addons/amxmodx/configs/`

5. Restart your server or use `amx_reloadplugins` command

## Configuration

Edit `addons/amxmodx/configs/stats_mod.cfg` to configure the plugin settings.

## Build Instructions

To compile the plugin, you need AMX Mod X compiler (`amxxpc`):

```bash
amxxpc src/stats_mod.sma -o compiled/stats_mod.amxx
```

Make sure the `include/` directory is in your compiler's include path, or use:

```bash
amxxpc -iinclude src/stats_mod.sma -o compiled/stats_mod.amxx
```

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

## Future Features

- Real-time statistics collection (kills, deaths, rounds, etc.)
- HTTP API integration for statistics reporting
- Database support for statistics storage
- Web dashboard for statistics visualization
- Match statistics tracking
- Player performance metrics

## Version

Current version: 1.0.0

## License

[Add your license here]

## Author

[Add your name/contact information here]

