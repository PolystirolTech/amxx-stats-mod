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
#define QUEUE_DIR "addons/amxmodx/data/stats_mod/queue"

// API endpoint
#define API_ENDPOINT "/api/v1/statistics/goldsource/batch"

// Batch types
#define BATCH_TYPE_SERVERS 0
#define BATCH_TYPE_USERS 1
#define BATCH_TYPE_SESSIONS 2
#define BATCH_TYPE_KILLS 3
#define BATCH_TYPE_FPS 4
#define BATCH_TYPE_COUNTERS 5

// Maximum values
#define MAX_STEAMID_LENGTH 32
#define MAX_NAME_LENGTH 64
#define MAX_MAP_NAME 32
#define MAX_WEAPON_NAME 32
#define MAX_UUID_LENGTH 36
#define MAX_URL_LENGTH 256
#define MAX_JSON_SIZE 8192
#define MAX_BATCH_SIZE 100
#define MAX_QUEUE_FILES 100

// Rate limiting
#define MIN_SEND_INTERVAL 5.0
#define HTTP_TIMEOUT 15.0

// Helper macros
#define IsValidPlayer(%1) (1 <= %1 <= 32)

// Data structures
enum _:ServerInfo {
	SI_UUID[MAX_UUID_LENGTH],
	SI_NAME[MAX_NAME_LENGTH],
	SI_ADDRESS[32],
	SI_MAX_PLAYERS
}

enum _:UserInfo {
	UI_STEAMID[MAX_STEAMID_LENGTH],
	UI_NAME[MAX_NAME_LENGTH],
	UI_REGISTERED
}

enum _:SessionInfo {
	SE_STEAMID[MAX_STEAMID_LENGTH],
	SE_SERVER_UUID[MAX_UUID_LENGTH],
	SE_MAP_NAME[MAX_MAP_NAME],
	SE_SESSION_START,
	SE_SESSION_END,
	SE_KILLS,
	SE_DEATHS,
	SE_HEADSHOTS
}

enum _:KillInfo {
	KI_KILLER_STEAMID[MAX_STEAMID_LENGTH],
	KI_VICTIM_STEAMID[MAX_STEAMID_LENGTH],
	KI_SERVER_UUID[MAX_UUID_LENGTH],
	KI_WEAPON[MAX_WEAPON_NAME],
	KI_HEADSHOT,
	KI_DATE
}

enum _:FPSInfo {
	FI_SERVER_UUID[MAX_UUID_LENGTH],
	FI_DATE,
	Float:FI_FPS,
	FI_PLAYERS_ONLINE,
	FI_MAP_NAME[MAX_MAP_NAME]
}

// Forward declarations
forward OnClientConnect(id);
forward OnClientPutInServer(id);
forward OnClientDisconnect(id);
forward OnPlayerKilled(victim, attacker, headshot);
forward CollectFPSMetrics();
forward SendServerInfo();
forward AddToBatch(type, const data[], size);
forward FlushBatch(type);
forward BuildBatchPayload(output[], maxlen);
forward SendStatisticsBatch(const payload[]);
forward ParseAPIResponse(const response[]);
forward HandleAPIError(const error[], const payload[]);
forward SaveToRetryQueue(const payload[]);
forward ProcessRetryQueue();
forward CleanOldQueueFiles();
forward GetSteamID(player, output[], len);
forward GetCurrentTimestamp();
forward GetServerAddress(output[], len);
forward ValidateUUID(const uuid[]);
forward EscapeJSONString(const input[], output[], len);
forward LoadConfig();
forward Float:GetConfigFloat(const key[], Float:def);
forward GetConfigString(const key[], output[], len, const def[]);
forward GetConfigInt(const key[], def);

