#if defined _stats_mod_included
	#endinput
#endif
#define _stats_mod_included

// Plugin version constants
#define STATS_MOD_VERSION_MAJOR 1
#define STATS_MOD_VERSION_MINOR 0
#define STATS_MOD_VERSION_PATCH 0

// Plugin configuration paths
#define CONFIG_FILE "addons/amxmodx/configs/stats_mod.cfg"

// Statistics event types (for future use)
#define STAT_EVENT_KILL 1
#define STAT_EVENT_DEATH 2
#define STAT_EVENT_ROUND_START 3
#define STAT_EVENT_ROUND_END 4
#define STAT_EVENT_MATCH_START 5
#define STAT_EVENT_MATCH_END 6

// Helper macros
#define IsValidPlayer(%1) (1 <= %1 <= 32)

// Forward declarations for future functions
// TODO: Add function declarations here

