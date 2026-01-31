/* AMX Mod X Plugin
 *
 * Stats Mod - Statistics Collection and Reporting
 *
 * Author: Your Name
 * Description: Collects and reports game statistics
 * Version: 1.0.0
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <sockets>

// Include our custom definitions
#include <stats_mod>

#define PLUGIN_NAME "Stats Mod"
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_AUTHOR "Sluicee"

#pragma dynamic 131072

// Global buffers to avoid stack overflow
new g_JsonBuffer[MAX_JSON_SIZE]
new g_PayloadBuffer[MAX_JSON_SIZE]
new g_RequestBuffer[MAX_REQUEST_SIZE]

// Configuration variables
new g_StatsEnabled = 1
new g_ApiUrl[MAX_URL_LENGTH]
new g_ServerUUID[MAX_UUID_LENGTH]
new Float:g_FpsInterval = 60.0
new Float:g_SessionInterval = 600.0
new g_KillsBatchSize = 10
new Float:g_KillsInterval = 30.0
new g_StatsDebug = 0

// Batch queues
new Array:g_UsersQueue
new Array:g_SessionsQueue
new Array:g_KillsQueue
new Array:g_FpsQueue
new Array:g_CountersQueue

// Session tracking
new g_PlayerSessions[33][SessionInfo]
new g_PlayerCounters[33][CounterInfo]
new g_PlayerConnected[33]
new g_PlayerFirstConnect[33]

// Rate limiting
new Float:g_LastSendTime = 0.0
new g_SendingInProgress = 0

// Timers
new g_FpsTimer = 0
new g_SessionTimer = 0
new g_KillsTimer = 0
new g_RetryTimer = 0

// Server info
new g_ServerInfo[ServerInfo]
new g_ServerInfoSent = 0

new const g_WeaponClassnames[][] = {
	"weapon_p228", "weapon_scout", "weapon_xm1014", "weapon_mac10", "weapon_aug", "weapon_elite",
	"weapon_fiveseven", "weapon_ump45", "weapon_sg550", "weapon_galil", "weapon_famas", "weapon_usp",
	"weapon_glock18", "weapon_awp", "weapon_mp5navy", "weapon_m249", "weapon_m3", "weapon_m4a1",
	"weapon_tmp", "weapon_g3sg1", "weapon_deagle", "weapon_sg552", "weapon_ak47", "weapon_p90"
}

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
	
	// Create data directory
	new dataDir[128]
	formatex(dataDir, charsmax(dataDir), "addons/amxmodx/data/stats_mod")
	if (!dir_exists(dataDir))
	{
		mkdir(dataDir)
	}
	
	DebugLogToFile("--- Plugin Initialization Started ---")
	server_print("[Stats Mod] plugin_init started. Logging to addons/amxmodx/data/stats_mod/debug.log")
	
	// Initialize arrays
	g_UsersQueue = ArrayCreate(UserInfo)
	g_SessionsQueue = ArrayCreate(SessionInfo)
	g_KillsQueue = ArrayCreate(KillInfo)
	g_FpsQueue = ArrayCreate(FPSInfo)
	g_CountersQueue = ArrayCreate(CounterInfo)
	
	// Load configuration
	LoadConfig()
	
	// Check if enabled
	if (!g_StatsEnabled)
	{
		DebugLogToFile("Plugin is DISABLED in config.")
		server_print("[Stats Mod] Plugin is DISABLED via config.")
		return
	}
	
	// Validate UUID
	if (!ValidateUUID(g_ServerUUID))
	{
		new msg[128]
		formatex(msg, charsmax(msg), "[Stats Mod] ERROR: Invalid/Missing server UUID: '%s'.", g_ServerUUID)
		DebugLogToFile(msg)
		server_print(msg)
		set_fail_state(msg)
		return
	}
	
	DebugLogToFile("Config loaded successfully. UUID: %s", g_ServerUUID)
	
	if (containi(g_ApiUrl, "https://") != -1)
	{
		server_print("[Stats Mod] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
		server_print("[Stats Mod] ERROR: HTTPS is NOT supported! Use http:// instead.")
		server_print("[Stats Mod] !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
		DebugLogToFile("CRITICAL: HTTPS detected in API URL. Sockets will fail.")
	}
	
	// Initialize server info
	GetServerInfo()
	
	// Register hooks
	RegisterHam(Ham_TakeDamage, "player", "OnPlayerTakeDamage")
	RegisterHam(Ham_Killed, "player", "OnPlayerKilled", 1)
	RegisterHam(Ham_Player_Jump, "player", "OnPlayerJump", 1)
	
	new modname[32]
	get_modname(modname, charsmax(modname))
	public TaskHeartbeat()
{
	// Removed for production
}
	if (equal(modname, "cstrike") || equal(modname, "czero"))
	{
		for (new i = 0; i < sizeof g_WeaponClassnames; i++)
		{
			RegisterHam(Ham_Weapon_PrimaryAttack, g_WeaponClassnames[i], "OnPrimaryAttack", 1)
		}
	}
	else if (equal(modname, "valve"))
	{
		RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_9mmhandgun", "OnPrimaryAttack", 1)
		RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_mp5", "OnPrimaryAttack", 1)
	}
	
	register_event("DeathMsg", "OnDeathMsg", "a")
	
	// Create queue directory
	new queuePath[128]
	formatex(queuePath, charsmax(queuePath), "%s", QUEUE_DIR)
	if (!dir_exists(queuePath))
	{
		mkdir(queuePath)
	}
	
	log_amx("[Stats Mod] Plugin initialized successfully.")
}

public plugin_precache()
{
	// No noise in production
}

public plugin_cfg()
{
	// Reload config on map change
	LoadConfig()
	
	// Send server info on startup
	if (g_StatsEnabled && !g_ServerInfoSent)
	{
		set_task(5.0, "SendServerInfo")
	}
	
	// Start timers
	if (g_StatsEnabled)
	{
		StartTimers()
	}
}

public plugin_end()
{
	// Send remaining data
	if (g_StatsEnabled)
	{
		FlushAllBatches()
	}
	
	// Cleanup arrays
	ArrayDestroy(g_UsersQueue)
	ArrayDestroy(g_SessionsQueue)
	ArrayDestroy(g_KillsQueue)
	ArrayDestroy(g_FpsQueue)
	ArrayDestroy(g_CountersQueue)
}

// Configuration loading
LoadConfig()
{
	new configPath[128]
	formatex(configPath, charsmax(configPath), "%s", CONFIG_FILE)
	
	server_print("[Stats Mod] Loading config from: %s", configPath)
	
	if (!file_exists(configPath))
	{
		// Try fallback to amxmodx/configs/
		formatex(configPath, charsmax(configPath), "addons/amxmodx/configs/stats_mod.cfg")
		server_print("[Stats Mod] Not found, trying: %s", configPath)
		
		if (!file_exists(configPath))
		{
			server_print("[Stats Mod] ERROR: Config file NOT FOUND! Plugin will not work.")
			log_amx("[Stats Mod] Config file not found")
			return
		}
	}
	
	g_StatsEnabled = GetConfigInt("stats_enabled", 1)
	GetConfigString("stats_api_url", g_ApiUrl, charsmax(g_ApiUrl), "")
	GetConfigString("stats_server_uuid", g_ServerUUID, charsmax(g_ServerUUID), "")
	g_FpsInterval = GetConfigFloat("stats_fps_interval", 60.0)
	g_SessionInterval = GetConfigFloat("stats_session_interval", 600.0)
	g_KillsBatchSize = GetConfigInt("stats_kills_batch_size", 10)
	g_KillsInterval = GetConfigFloat("stats_kills_interval", 30.0)
	g_StatsDebug = GetConfigInt("stats_debug", 0)
}

GetConfigInt(const key[], def)
{
	new configPath[128]
	formatex(configPath, charsmax(configPath), "%s", CONFIG_FILE)
	
	new line[128], keyValue[64], value[64]
	new file = fopen(configPath, "rt")
	
	if (!file)
		return def
	
	while (!feof(file))
	{
		fgets(file, line, charsmax(line))
		trim(line)
		
		// Skip comments and empty lines
		if (line[0] == ';' || line[0] == '/' || !line[0])
			continue
		
		parse(line, keyValue, charsmax(keyValue), value, charsmax(value))
		trim(keyValue)
		trim(value)
		
		if (equal(keyValue, key))
		{
			fclose(file)
			return str_to_num(value)
		}
	}
	
	fclose(file)
	return def
}

Float:GetConfigFloat(const key[], Float:def)
{
	new configPath[128]
	formatex(configPath, charsmax(configPath), "%s", CONFIG_FILE)
	
	new line[128], keyValue[64], value[64]
	new file = fopen(configPath, "rt")
	
	if (!file)
		return def
	
	while (!feof(file))
	{
		fgets(file, line, charsmax(line))
		trim(line)
		
		if (line[0] == ';' || line[0] == '/' || !line[0])
			continue
		
		parse(line, keyValue, charsmax(keyValue), value, charsmax(value))
		trim(keyValue)
		trim(value)
		
		if (equal(keyValue, key))
		{
			fclose(file)
			return str_to_float(value)
		}
	}
	
	fclose(file)
	return def
}

GetConfigString(const key[], output[], len, const def[])
{
	new configPath[128]
	formatex(configPath, charsmax(configPath), "%s", CONFIG_FILE)
	
	new line[128], keyValue[64], value[256]
	new file = fopen(configPath, "rt")
	
	if (!file)
	{
		copy(output, len, def)
		return
	}
	
	while (!feof(file))
	{
		fgets(file, line, charsmax(line))
		trim(line)
		
		if (line[0] == ';' || line[0] == '/' || !line[0])
			continue
		
		parse(line, keyValue, charsmax(keyValue), value, charsmax(value))
		trim(keyValue)
		trim(value)
		
		// Remove quotes if present
		new valLen = strlen(value)
		if (valLen >= 2 && value[0] == '"' && value[valLen - 1] == '"')
		{
			value[valLen - 1] = 0
			new temp[256]
			copy(temp, charsmax(temp), value[1])
			copy(value, charsmax(value), temp)
		}
		
		if (equal(keyValue, key))
		{
			fclose(file)
			copy(output, len, value)
			return
		}
	}
	
	fclose(file)
	copy(output, len, def)
}

// Server info collection
GetServerInfo()
{
	copy(g_ServerInfo[SI_UUID], charsmax(g_ServerInfo[SI_UUID]), g_ServerUUID)
	
	new serverName[64]
	get_cvar_string("hostname", serverName, charsmax(serverName))
	copy(g_ServerInfo[SI_NAME], charsmax(g_ServerInfo[SI_NAME]), serverName)
	
	GetServerAddress(g_ServerInfo[SI_ADDRESS], charsmax(g_ServerInfo[SI_ADDRESS]))
	
	g_ServerInfo[SI_MAX_PLAYERS] = get_maxplayers()
}

GetServerAddress(output[], len)
{
	new ip[32], port
	get_cvar_string("ip", ip, charsmax(ip))
	if (strlen(ip) == 0)
	{
		// Fallback: try to get from server info
		copy(ip, charsmax(ip), "0.0.0.0")
	}
	port = get_cvar_num("port")
	if (port == 0)
	{
		port = 27015 // Default GoldSource port
	}
	
	formatex(output, len, "%s:%d", ip, port)
}

// Timer management
StartTimers()
{
	// FPS timer
	if (g_FpsTimer)
		remove_task(g_FpsTimer)
	g_FpsTimer = set_task(g_FpsInterval, "TaskCollectFPS", _, _, _, "b")
	
	// Session update timer
	if (g_SessionTimer)
		remove_task(g_SessionTimer)
	g_SessionTimer = set_task(g_SessionInterval, "TaskUpdateSessions", _, _, _, "b")
	
	// Kills batch timer
	if (g_KillsTimer)
		remove_task(g_KillsTimer)
	g_KillsTimer = set_task(g_KillsInterval, "TaskFlushKills", _, _, _, "b")
	
	// Retry queue timer
	if (g_RetryTimer)
		remove_task(g_RetryTimer)
	g_RetryTimer = set_task(30.0, "TaskProcessRetryQueue", _, _, _, "b")
	
	// Counters timer
	set_task(60.0, "TaskFlushCounters", _, _, _, "b")
}

// Client connection hooks
public client_connect(id)
{
	if (!g_StatsEnabled || !IsValidPlayer(id))
		return
	
	g_PlayerConnected[id] = 0
	g_PlayerFirstConnect[id] = 0
	
	// Check if first connect
	new authid[MAX_STEAMID_LENGTH]
	GetSteamID(id, authid, charsmax(authid))
	
	if (strlen(authid) > 0 && equal(authid, "STEAM_", 6))
	{
		// Register new user
		new userInfo[UserInfo]
		copy(userInfo[UI_STEAMID], charsmax(userInfo[UI_STEAMID]), authid)
		
		new name[MAX_NAME_LENGTH]
		get_user_name(id, name, charsmax(name))
		copy(userInfo[UI_NAME], charsmax(userInfo[UI_NAME]), name)
		
		userInfo[UI_REGISTERED] = GetCurrentTimestamp()
		
		AddToBatch(BATCH_TYPE_USERS, userInfo, UserInfo)
		g_PlayerFirstConnect[id] = 1
	}
}

public client_putinserver(id)
{
	if (!g_StatsEnabled || !IsValidPlayer(id))
		return
	
	g_PlayerConnected[id] = 1
	
	// Initialize session
	new authid[MAX_STEAMID_LENGTH]
	GetSteamID(id, authid, charsmax(authid))
	
	if (strlen(authid) > 0)
	{
		copy(g_PlayerSessions[id][SE_STEAMID], charsmax(g_PlayerSessions[][SE_STEAMID]), authid)
		copy(g_PlayerSessions[id][SE_SERVER_UUID], charsmax(g_PlayerSessions[][SE_SERVER_UUID]), g_ServerUUID)
		
		new mapName[MAX_MAP_NAME]
		get_mapname(mapName, charsmax(mapName))
		copy(g_PlayerSessions[id][SE_MAP_NAME], charsmax(g_PlayerSessions[][SE_MAP_NAME]), mapName)
		
		g_PlayerSessions[id][SE_SESSION_START] = GetCurrentTimestamp()
		g_PlayerSessions[id][SE_SESSION_END] = 0
		g_PlayerSessions[id][SE_KILLS] = 0
		g_PlayerSessions[id][SE_DEATHS] = 0
		g_PlayerSessions[id][SE_HEADSHOTS] = 0
		
		// Reset counters
		copy(g_PlayerCounters[id][CI_STEAMID], charsmax(g_PlayerCounters[][CI_STEAMID]), authid)
		copy(g_PlayerCounters[id][CI_SERVER_UUID], charsmax(g_PlayerCounters[][CI_SERVER_UUID]), g_ServerUUID)
		g_PlayerCounters[id][CI_SHOTS] = 0
		g_PlayerCounters[id][CI_HITS] = 0
		g_PlayerCounters[id][CI_DAMAGE] = 0
		g_PlayerCounters[id][CI_JUMPS] = 0
	}
}

public client_disconnect(id)
{
	if (!g_StatsEnabled || !IsValidPlayer(id))
		return
	
	if (g_PlayerConnected[id])
	{
		// Finalize session
		g_PlayerSessions[id][SE_SESSION_END] = GetCurrentTimestamp()
		
		new sessionInfo[SessionInfo]
		copy(sessionInfo[SE_STEAMID], charsmax(sessionInfo[SE_STEAMID]), g_PlayerSessions[id][SE_STEAMID])
		copy(sessionInfo[SE_SERVER_UUID], charsmax(sessionInfo[SE_SERVER_UUID]), g_PlayerSessions[id][SE_SERVER_UUID])
		copy(sessionInfo[SE_MAP_NAME], charsmax(sessionInfo[SE_MAP_NAME]), g_PlayerSessions[id][SE_MAP_NAME])
		sessionInfo[SE_SESSION_START] = g_PlayerSessions[id][SE_SESSION_START]
		sessionInfo[SE_SESSION_END] = g_PlayerSessions[id][SE_SESSION_END]
		sessionInfo[SE_KILLS] = g_PlayerSessions[id][SE_KILLS]
		sessionInfo[SE_DEATHS] = g_PlayerSessions[id][SE_DEATHS]
		sessionInfo[SE_HEADSHOTS] = g_PlayerSessions[id][SE_HEADSHOTS]
		
		AddToBatch(BATCH_TYPE_SESSIONS, sessionInfo, SessionInfo)
	}
	
	g_PlayerConnected[id] = 0
}

// Kill tracking
public OnPlayerTakeDamage(victim, inflictor, attacker, Float:damage, damagebits)
{
	if (!g_StatsEnabled || !IsValidPlayer(attacker) || !IsValidPlayer(victim))
		return
	
	if (attacker == victim)
		return
		
	g_PlayerCounters[attacker][CI_HITS]++
	g_PlayerCounters[attacker][CI_DAMAGE] += floatround(damage)
}

public OnPrimaryAttack(weapon)
{
	new id = pev(weapon, pev_owner)
	if (IsValidPlayer(id))
	{
		g_PlayerCounters[id][CI_SHOTS]++
	}
}

public OnPlayerJump(id)
{
	if (IsValidPlayer(id))
	{
		g_PlayerCounters[id][CI_JUMPS]++
	}
}

public OnPlayerKilled(victim, attacker, shouldgib)
{
	// Handled in OnDeathMsg for better headshot detection
}

public OnDeathMsg()
{
	if (!g_StatsEnabled)
		return
	
	new victim = read_data(2)
	new attacker = read_data(1)
	new headshot = read_data(3) // 1 if headshot, 0 otherwise
	
	if (!IsValidPlayer(victim))
		return
	
	if (victim == attacker)
		return
	
	// Update session stats
	if (IsValidPlayer(attacker) && g_PlayerConnected[attacker])
	{
		g_PlayerSessions[attacker][SE_KILLS]++
		if (headshot)
		{
			g_PlayerSessions[attacker][SE_HEADSHOTS]++
		}
	}
	
	if (g_PlayerConnected[victim])
	{
		g_PlayerSessions[victim][SE_DEATHS]++
	}
	
	// Record kill event
	new killInfo[KillInfo]
	
	if (IsValidPlayer(attacker))
	{
		new attackerSteamID[MAX_STEAMID_LENGTH]
		GetSteamID(attacker, attackerSteamID, charsmax(attackerSteamID))
		copy(killInfo[KI_KILLER_STEAMID], charsmax(killInfo[KI_KILLER_STEAMID]), attackerSteamID)
		
		new weaponName[MAX_WEAPON_NAME]
		read_data(4, weaponName, charsmax(weaponName))
		copy(killInfo[KI_WEAPON], charsmax(killInfo[KI_WEAPON]), weaponName)
	}
	else
	{
		// Environmental kill
		killInfo[KI_KILLER_STEAMID][0] = 0
		killInfo[KI_WEAPON][0] = 0
	}
	
	new victimSteamID[MAX_STEAMID_LENGTH]
	GetSteamID(victim, victimSteamID, charsmax(victimSteamID))
	copy(killInfo[KI_VICTIM_STEAMID], charsmax(killInfo[KI_VICTIM_STEAMID]), victimSteamID)
	
	copy(killInfo[KI_SERVER_UUID], charsmax(killInfo[KI_SERVER_UUID]), g_ServerUUID)
	killInfo[KI_HEADSHOT] = headshot
	killInfo[KI_DATE] = GetCurrentTimestamp()
	
	AddToBatch(BATCH_TYPE_KILLS, killInfo, KillInfo)
	
	// Check if batch size reached
	if (ArraySize(g_KillsQueue) >= g_KillsBatchSize)
	{
		FlushBatch(BATCH_TYPE_KILLS)
	}
}

// FPS collection
public TaskCollectFPS()
{
	if (!g_StatsEnabled)
		return
	
	CollectFPSMetrics()
}

CollectFPSMetrics()
{
	new fpsInfo[FPSInfo]
	copy(fpsInfo[FI_SERVER_UUID], charsmax(fpsInfo[FI_SERVER_UUID]), g_ServerUUID)
	fpsInfo[FI_DATE] = GetCurrentTimestamp()
	
	// Get server FPS (approximation via engine)
	// Note: This is a simplified approach. For accurate FPS, consider using engine module
	new Float:fps = 100.0 // Default approximation
	new fpsCvar = get_cvar_pointer("sys_ticrate")
	if (fpsCvar)
	{
		fps = get_pcvar_float(fpsCvar)
		if (fps <= 0.0)
		{
			fps = 100.0 // Fallback
		}
	}
	fpsInfo[_:FI_FPS] = _:fps
	
	// Count online players
	fpsInfo[FI_PLAYERS_ONLINE] = 0
	for (new i = 1; i <= get_maxplayers(); i++)
	{
		if (g_PlayerConnected[i])
		{
			fpsInfo[FI_PLAYERS_ONLINE]++
		}
	}
	
	new mapName[MAX_MAP_NAME]
	get_mapname(mapName, charsmax(mapName))
	copy(fpsInfo[FI_MAP_NAME], charsmax(fpsInfo[FI_MAP_NAME]), mapName)
	
	AddToBatch(BATCH_TYPE_FPS, fpsInfo, FPSInfo)
	FlushBatch(BATCH_TYPE_FPS)
}

// Session updates
public TaskUpdateSessions()
{
	if (!g_StatsEnabled)
		return
	
	// Update active sessions
	for (new i = 1; i <= get_maxplayers(); i++)
	{
		if (g_PlayerConnected[i])
		{
			new sessionInfo[SessionInfo]
			copy(sessionInfo[SE_STEAMID], charsmax(sessionInfo[SE_STEAMID]), g_PlayerSessions[i][SE_STEAMID])
			copy(sessionInfo[SE_SERVER_UUID], charsmax(sessionInfo[SE_SERVER_UUID]), g_PlayerSessions[i][SE_SERVER_UUID])
			copy(sessionInfo[SE_MAP_NAME], charsmax(sessionInfo[SE_MAP_NAME]), g_PlayerSessions[i][SE_MAP_NAME])
			sessionInfo[SE_SESSION_START] = g_PlayerSessions[i][SE_SESSION_START]
			sessionInfo[SE_SESSION_END] = 0 // Still active
			sessionInfo[SE_KILLS] = g_PlayerSessions[i][SE_KILLS]
			sessionInfo[SE_DEATHS] = g_PlayerSessions[i][SE_DEATHS]
			sessionInfo[SE_HEADSHOTS] = g_PlayerSessions[i][SE_HEADSHOTS]
			
			AddToBatch(BATCH_TYPE_SESSIONS, sessionInfo, SessionInfo)
		}
	}
	
	FlushBatch(BATCH_TYPE_SESSIONS)
}

// Kills batching
public TaskFlushKills()
{
	if (!g_StatsEnabled)
		return
	
	if (ArraySize(g_KillsQueue) > 0)
	{
		FlushBatch(BATCH_TYPE_KILLS)
	}
}

public TaskFlushCounters()
{
	if (!g_StatsEnabled)
		return
		
	for (new i = 1; i <= get_maxplayers(); i++)
	{
		if (g_PlayerConnected[i])
		{
			new counterInfo[CounterInfo]
			for (new j = 0; j < CounterInfo; j++)
			{
				counterInfo[j] = g_PlayerCounters[i][j]
			}
			
			// Only push if there's something to report
			if (counterInfo[CI_SHOTS] > 0 || counterInfo[CI_JUMPS] > 0)
			{
				AddToBatch(BATCH_TYPE_COUNTERS, counterInfo, CounterInfo)
				
				// Reset after batching
				g_PlayerCounters[i][CI_SHOTS] = 0
				g_PlayerCounters[i][CI_HITS] = 0
				g_PlayerCounters[i][CI_DAMAGE] = 0
				g_PlayerCounters[i][CI_JUMPS] = 0
			}
		}
	}
	
	FlushBatch(BATCH_TYPE_COUNTERS)
}

// Server info sending
public SendServerInfo()
{
	if (!g_StatsEnabled || g_ServerInfoSent)
		return
	
	new serverInfo[ServerInfo]
	copy(serverInfo[SI_UUID], charsmax(serverInfo[SI_UUID]), g_ServerInfo[SI_UUID])
	copy(serverInfo[SI_NAME], charsmax(serverInfo[SI_NAME]), g_ServerInfo[SI_NAME])
	copy(serverInfo[SI_ADDRESS], charsmax(serverInfo[SI_ADDRESS]), g_ServerInfo[SI_ADDRESS])
	serverInfo[SI_MAX_PLAYERS] = g_ServerInfo[SI_MAX_PLAYERS]
	
	AddToBatch(BATCH_TYPE_SERVERS, serverInfo, ServerInfo)
	FlushBatch(BATCH_TYPE_SERVERS)
	
	g_ServerInfoSent = 1
}

// Batch management
AddToBatch(type, const data[], size)
{
	#pragma unused size
	if (!g_StatsEnabled)
		return
	
	switch (type)
	{
		case BATCH_TYPE_USERS:
		{
			ArrayPushArray(g_UsersQueue, data)
		}
		case BATCH_TYPE_SESSIONS:
		{
			ArrayPushArray(g_SessionsQueue, data)
		}
		case BATCH_TYPE_KILLS:
		{
			ArrayPushArray(g_KillsQueue, data)
		}
		case BATCH_TYPE_FPS:
		{
			ArrayPushArray(g_FpsQueue, data)
		}
		case BATCH_TYPE_SERVERS:
		{
			// Servers are sent immediately, no queue
		}
		case BATCH_TYPE_COUNTERS:
		{
			ArrayPushArray(g_CountersQueue, data)
		}
	}
}

FlushBatch(type)
{
	#pragma unused type
	if (!g_StatsEnabled || g_SendingInProgress)
		return
	
	// Check rate limiting
	new Float:currentTime = get_gametime()
	if (currentTime - g_LastSendTime < MIN_SEND_INTERVAL)
	{
		return
	}
	
	if (BuildBatchPayload(g_PayloadBuffer, MAX_JSON_SIZE))
	{
		g_SendingInProgress = 1
		SendStatisticsBatch(g_PayloadBuffer)
		g_LastSendTime = currentTime
	}
}

FlushAllBatches()
{
	if (ArraySize(g_UsersQueue) > 0 || ArraySize(g_SessionsQueue) > 0 || 
		ArraySize(g_KillsQueue) > 0 || ArraySize(g_FpsQueue) > 0)
	{
		FlushBatch(BATCH_TYPE_USERS)
	}
}

// JSON building
BuildBatchPayload(output[], maxlen)
{
	if (strlen(g_ApiUrl) == 0 || strlen(g_ServerUUID) == 0)
		return 0
	
	new pos = 0
	
	// Start JSON object
	copy(g_JsonBuffer, maxlen, "{")
	add(g_JsonBuffer, maxlen, "^"server_uuid^":^"")
	add(g_JsonBuffer, maxlen, g_ServerUUID)
	add(g_JsonBuffer, maxlen, "^"")
	pos = strlen(g_JsonBuffer)
	
	// Servers array
	if (g_ServerInfoSent)
	{
		add(g_JsonBuffer, maxlen, ",^"servers^":[")
		pos = strlen(g_JsonBuffer)
		pos += BuildServerJSON(g_JsonBuffer[pos], maxlen - pos, g_ServerInfo)
		add(g_JsonBuffer, maxlen, "]")
		pos = strlen(g_JsonBuffer)
	}
	
	// Users array
	new usersCount = ArraySize(g_UsersQueue)
	if (usersCount > 0)
	{
		add(g_JsonBuffer, maxlen, ",^"users^":[")
		pos = strlen(g_JsonBuffer)
		for (new i = 0; i < usersCount; i++)
		{
			if (i > 0) add(g_JsonBuffer, maxlen, ",")
			new userInfo[UserInfo]
			ArrayGetArray(g_UsersQueue, i, userInfo)
			pos = strlen(g_JsonBuffer)
			pos += BuildUserJSON(g_JsonBuffer[pos], maxlen - pos, userInfo)
		}
		add(g_JsonBuffer, maxlen, "]")
		ArrayClear(g_UsersQueue)
		pos = strlen(g_JsonBuffer)
	}
	
	// Sessions array
	new sessionsCount = ArraySize(g_SessionsQueue)
	if (sessionsCount > 0)
	{
		add(g_JsonBuffer, maxlen, ",^"sessions^":[")
		pos = strlen(g_JsonBuffer)
		for (new i = 0; i < sessionsCount; i++)
		{
			if (i > 0) add(g_JsonBuffer, maxlen, ",")
			new sessionInfo[SessionInfo]
			ArrayGetArray(g_SessionsQueue, i, sessionInfo)
			pos = strlen(g_JsonBuffer)
			pos += BuildSessionJSON(g_JsonBuffer[pos], maxlen - pos, sessionInfo)
		}
		add(g_JsonBuffer, maxlen, "]")
		ArrayClear(g_SessionsQueue)
		pos = strlen(g_JsonBuffer)
	}
	
	// Kills array
	new killsCount = ArraySize(g_KillsQueue)
	if (killsCount > 0)
	{
		add(g_JsonBuffer, maxlen, ",^"kills^":[")
		pos = strlen(g_JsonBuffer)
		for (new i = 0; i < killsCount; i++)
		{
			if (i > 0) add(g_JsonBuffer, maxlen, ",")
			new killInfo[KillInfo]
			ArrayGetArray(g_KillsQueue, i, killInfo)
			pos = strlen(g_JsonBuffer)
			pos += BuildKillJSON(g_JsonBuffer[pos], maxlen - pos, killInfo)
		}
		add(g_JsonBuffer, maxlen, "]")
		ArrayClear(g_KillsQueue)
		pos = strlen(g_JsonBuffer)
	}
	
	// FPS array
	new fpsCount = ArraySize(g_FpsQueue)
	if (fpsCount > 0)
	{
		add(g_JsonBuffer, maxlen, ",^"fps^":[")
		pos = strlen(g_JsonBuffer)
		for (new i = 0; i < fpsCount; i++)
		{
			if (i > 0) add(g_JsonBuffer, maxlen, ",")
			new fpsInfo[FPSInfo]
			ArrayGetArray(g_FpsQueue, i, fpsInfo)
			pos = strlen(g_JsonBuffer)
			pos += BuildFPSJSON(g_JsonBuffer[pos], maxlen - pos, fpsInfo)
		}
		add(g_JsonBuffer, maxlen, "]")
		ArrayClear(g_FpsQueue)
		pos = strlen(g_JsonBuffer)
	}
	
	// Counters array
	new countersCount = ArraySize(g_CountersQueue)
	if (countersCount > 0)
	{
		add(g_JsonBuffer, maxlen, ",^"counters^":[")
		pos = strlen(g_JsonBuffer)
		for (new i = 0; i < countersCount; i++)
		{
			if (i > 0) add(g_JsonBuffer, maxlen, ",")
			new counterInfo[CounterInfo]
			ArrayGetArray(g_CountersQueue, i, counterInfo)
			pos = strlen(g_JsonBuffer)
			pos += BuildCounterJSON(g_JsonBuffer[pos], maxlen - pos, counterInfo)
		}
		add(g_JsonBuffer, maxlen, "]")
		ArrayClear(g_CountersQueue)
		pos = strlen(g_JsonBuffer)
	}
	
	// Close JSON object
	add(g_JsonBuffer, maxlen, "}")
	pos = strlen(g_JsonBuffer)
	
	if (pos >= maxlen - 1)
		return 0
	
	copy(output, maxlen, g_JsonBuffer)
	return 1
}

BuildServerJSON(output[], maxlen, const serverInfo[ServerInfo])
{
	new escapedName[MAX_NAME_LENGTH * 2]
	EscapeJSONString(serverInfo[SI_NAME], escapedName, charsmax(escapedName))
	
	copy(output, maxlen, "{^"server_uuid^":^"")
	add(output, maxlen, serverInfo[SI_UUID])
	add(output, maxlen, "^",^"name^":^"")
	add(output, maxlen, escapedName)
	add(output, maxlen, "^",^"address^":^"")
	add(output, maxlen, serverInfo[SI_ADDRESS])
	new maxPlayersStr[16]
	num_to_str(serverInfo[SI_MAX_PLAYERS], maxPlayersStr, charsmax(maxPlayersStr))
	add(output, maxlen, "^",^"max_players^":")
	add(output, maxlen, maxPlayersStr)
	add(output, maxlen, "}")
	return strlen(output)
}

BuildUserJSON(output[], maxlen, const userInfo[UserInfo])
{
	new escapedName[MAX_NAME_LENGTH * 2]
	EscapeJSONString(userInfo[UI_NAME], escapedName, charsmax(escapedName))
	
	new escapedSteamID[MAX_STEAMID_LENGTH * 2]
	EscapeJSONString(userInfo[UI_STEAMID], escapedSteamID, charsmax(escapedSteamID))
	
	copy(output, maxlen, "{^"steam_id^":^"")
	add(output, maxlen, escapedSteamID)
	add(output, maxlen, "^",^"name^":^"")
	add(output, maxlen, escapedName)
	new registeredStr[32]
	formatex(registeredStr, charsmax(registeredStr), "%d000", userInfo[UI_REGISTERED])
	add(output, maxlen, "^",^"registered^":")
	add(output, maxlen, registeredStr)
	add(output, maxlen, "}")
	return strlen(output)
}

BuildSessionJSON(output[], maxlen, const sessionInfo[SessionInfo])
{
	new escapedSteamID[MAX_STEAMID_LENGTH * 2]
	EscapeJSONString(sessionInfo[SE_STEAMID], escapedSteamID, charsmax(escapedSteamID))
	
	new escapedMap[MAX_MAP_NAME * 2]
	EscapeJSONString(sessionInfo[SE_MAP_NAME], escapedMap, charsmax(escapedMap))
	
	copy(output, maxlen, "{^"steam_id^":^"")
	add(output, maxlen, escapedSteamID)
	add(output, maxlen, "^",^"server_uuid^":^"")
	add(output, maxlen, sessionInfo[SE_SERVER_UUID])
	add(output, maxlen, "^",^"map_name^":^"")
	add(output, maxlen, escapedMap)
	new tempStr[32]
	formatex(tempStr, charsmax(tempStr), "%d000", sessionInfo[SE_SESSION_START])
	add(output, maxlen, "^",^"session_start^":")
	add(output, maxlen, tempStr)
	formatex(tempStr, charsmax(tempStr), "%d000", sessionInfo[SE_SESSION_END])
	add(output, maxlen, ",^"session_end^":")
	add(output, maxlen, tempStr)
	num_to_str(sessionInfo[SE_KILLS], tempStr, charsmax(tempStr))
	add(output, maxlen, ",^"kills^":")
	add(output, maxlen, tempStr)
	num_to_str(sessionInfo[SE_DEATHS], tempStr, charsmax(tempStr))
	add(output, maxlen, ",^"deaths^":")
	add(output, maxlen, tempStr)
	num_to_str(sessionInfo[SE_HEADSHOTS], tempStr, charsmax(tempStr))
	add(output, maxlen, ",^"headshots^":")
	add(output, maxlen, tempStr)
	add(output, maxlen, "}")
	return strlen(output)
}

BuildKillJSON(output[], maxlen, const killInfo[KillInfo])
{
	new escapedKiller[MAX_STEAMID_LENGTH * 2]
	EscapeJSONString(killInfo[KI_KILLER_STEAMID], escapedKiller, charsmax(escapedKiller))
	
	new escapedVictim[MAX_STEAMID_LENGTH * 2]
	EscapeJSONString(killInfo[KI_VICTIM_STEAMID], escapedVictim, charsmax(escapedVictim))
	
	new escapedWeapon[MAX_WEAPON_NAME * 2]
	EscapeJSONString(killInfo[KI_WEAPON], escapedWeapon, charsmax(escapedWeapon))
	
	copy(output, maxlen, "{^"killer_steam_id^":")
	if (strlen(killInfo[KI_KILLER_STEAMID]) > 0)
	{
		add(output, maxlen, "^"")
		add(output, maxlen, escapedKiller)
		add(output, maxlen, "^"")
	}
	else
	{
		add(output, maxlen, "null")
	}
	add(output, maxlen, ",^"victim_steam_id^":^"")
	add(output, maxlen, escapedVictim)
	add(output, maxlen, "^",^"server_uuid^":^"")
	add(output, maxlen, killInfo[KI_SERVER_UUID])
	add(output, maxlen, "^",^"weapon^":^"")
	add(output, maxlen, escapedWeapon)
	add(output, maxlen, "^",^"headshot^":")
	add(output, maxlen, killInfo[KI_HEADSHOT] ? "true" : "false")
	new dateStr[32]
	formatex(dateStr, charsmax(dateStr), "%d000", killInfo[KI_DATE])
	add(output, maxlen, ",^"date^":")
	add(output, maxlen, dateStr)
	add(output, maxlen, "}")
	return strlen(output)
}

BuildFPSJSON(output[], maxlen, const fpsInfo[FPSInfo])
{
	new escapedMap[MAX_MAP_NAME * 2]
	EscapeJSONString(fpsInfo[FI_MAP_NAME], escapedMap, charsmax(escapedMap))
	
	copy(output, maxlen, "{^"server_uuid^":^"")
	add(output, maxlen, fpsInfo[FI_SERVER_UUID])
	new tempStr[32]
	formatex(tempStr, charsmax(tempStr), "%d000", fpsInfo[FI_DATE])
	add(output, maxlen, "^",^"date^":")
	add(output, maxlen, tempStr)
	new fpsStr[32]
	float_to_str(Float:fpsInfo[FI_FPS], fpsStr, charsmax(fpsStr))
	add(output, maxlen, ",^"fps^":")
	add(output, maxlen, fpsStr)
	num_to_str(fpsInfo[FI_PLAYERS_ONLINE], tempStr, charsmax(tempStr))
	add(output, maxlen, ",^"players_online^":")
	add(output, maxlen, tempStr)
	add(output, maxlen, ",^"map_name^":^"")
	add(output, maxlen, escapedMap)
	add(output, maxlen, "^"}")
	return strlen(output)
}

BuildCounterJSON(output[], maxlen, const counterInfo[CounterInfo])
{
	copy(output, maxlen, "{^"steam_id^":^"")
	add(output, maxlen, counterInfo[CI_STEAMID])
	add(output, maxlen, "^",^"server_uuid^":^"")
	add(output, maxlen, counterInfo[CI_SERVER_UUID])
	add(output, maxlen, "^",^"counters^":{")
	
	new temp[32]
	num_to_str(counterInfo[CI_SHOTS], temp, charsmax(temp))
	add(output, maxlen, "^"shots^":")
	add(output, maxlen, temp)
	
	num_to_str(counterInfo[CI_HITS], temp, charsmax(temp))
	add(output, maxlen, ",^"hits^":")
	add(output, maxlen, temp)
	
	num_to_str(counterInfo[CI_DAMAGE], temp, charsmax(temp))
	add(output, maxlen, ",^"damage^":")
	add(output, maxlen, temp)
	
	num_to_str(counterInfo[CI_JUMPS], temp, charsmax(temp))
	add(output, maxlen, ",^"jumps^":")
	add(output, maxlen, temp)
	
	add(output, maxlen, "}}")
	return strlen(output)
}

EscapeJSONString(const input[], output[], len)
{
	new pos = 0
	new inputLen = strlen(input)
	
	for (new i = 0; i < inputLen && pos < len - 1; i++)
	{
		if (input[i] == '"')
		{
			if (pos < len - 2)
			{
				output[pos++] = 92 // backslash
				output[pos++] = '"'
			}
		}
		else if (input[i] == 92) // backslash
		{
			if (pos < len - 2)
			{
				output[pos++] = 92 // backslash
				output[pos++] = 92 // backslash
			}
		}
		else if (input[i] == 10) // \n
		{
			if (pos < len - 2)
			{
				output[pos++] = 92 // backslash
				output[pos++] = 'n'
			}
		}
		else if (input[i] == 13) // \r
		{
			if (pos < len - 2)
			{
				output[pos++] = 92 // backslash
				output[pos++] = 'r'
			}
		}
		else if (input[i] == 9) // \t
		{
			if (pos < len - 2)
			{
				output[pos++] = 92 // backslash
				output[pos++] = 't'
			}
		}
		else
		{
			output[pos++] = input[i]
		}
	}
	
	output[pos] = 0
	return pos
}

// HTTP client
SendStatisticsBatch(const payload[])
{
	if (strlen(g_ApiUrl) == 0)
	{
		log_amx("[Stats Mod] API URL not configured")
		g_SendingInProgress = 0
		return
	}
	
	// Parse URL
	new host[128], path[256], port = 80
	new urlCopy[MAX_URL_LENGTH]
	copy(urlCopy, charsmax(urlCopy), g_ApiUrl)
	trim(urlCopy)
	
	DebugLogToFile("Parsing URL: %s", urlCopy)
	
	// Remove protocol
	new pos = strfind(urlCopy, "://")
	if (pos != -1)
	{
		if (containi(urlCopy, "https") != -1) port = 443
		
		new temp[MAX_URL_LENGTH]
		copy(temp, charsmax(temp), urlCopy[pos + 3])
		copy(urlCopy, charsmax(urlCopy), temp)
	}
	
	// Extract path (everything after first /)
	pos = strfind(urlCopy, "/")
	if (pos != -1)
	{
		copy(path, charsmax(path), urlCopy[pos])
		urlCopy[pos] = 0
		
		// If path is just "/", use default endpoint
		if (equal(path, "/"))
		{
			formatex(path, charsmax(path), "%s", API_ENDPOINT)
		}
	}
	else
	{
		formatex(path, charsmax(path), "%s", API_ENDPOINT)
	}
	
	// Extract port from remains of urlCopy (which is now just the host[:port])
	pos = strfind(urlCopy, ":")
	if (pos != -1)
	{
		new portStr[16]
		copy(portStr, charsmax(portStr), urlCopy[pos + 1])
		port = str_to_num(portStr)
		urlCopy[pos] = 0
	}
	
	// Copy remaining as host
	copy(host, charsmax(host), urlCopy)
	
	// Build HTTP request
	new reqPos = 0
	
	reqPos += formatex(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, "POST %s HTTP/1.0^r^n", path)
	reqPos += formatex(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, "Host: %s^r^n", host)
	reqPos += formatex(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, "User-Agent: AMXX-StatsMod/1.0^r^n")
	reqPos += formatex(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, "Content-Type: application/json^r^n")
	reqPos += formatex(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, "Content-Length: %d^r^n", strlen(payload))
	reqPos += formatex(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, "Connection: close^r^n")
	reqPos += formatex(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, "Accept: */*^r^n")
	reqPos += formatex(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, "^r^n")
	
	// Copy payload
	copy(g_RequestBuffer[reqPos], MAX_REQUEST_SIZE - reqPos, payload)
	
	if (g_StatsDebug >= 1)
	{
		DebugLogToFile("Sending request to %s:%d%s", host, port, path)
		// Log the first 500 characters of the request to see the headers
		new debugReq[512]
		copy(debugReq, charsmax(debugReq), g_RequestBuffer)
		DebugLogToFile("Full Request (truncated to 512):^n%s", debugReq)
	}
	
	// Open socket
	new timeout = floatround(HTTP_TIMEOUT)
	new socket = socket_open(host, port, SOCKET_TCP, timeout)
	if (socket == -1)
	{
		DebugLogToFile("CRITICAL: Failed to open socket to %s:%d", host, port)
		SaveToRetryQueue(payload)
		g_SendingInProgress = 0
		return
	}
	
	// Send request
	socket_send(socket, g_RequestBuffer, strlen(g_RequestBuffer))
	
	// Read response (simplified - read first 1024 bytes)
	new response[1024]
	new bytesReceived = socket_recv(socket, response, charsmax(response))
	
	socket_close(socket)
	
	if (bytesReceived > 0)
	{
		DebugLogToFile("Received %d bytes response", bytesReceived)
		ParseAPIResponse(response)
	}
	else
	{
		DebugLogToFile("ERROR: No response received from server (timeout or closed)")
		SaveToRetryQueue(payload)
	}
	
	g_SendingInProgress = 0
}

ParseAPIResponse(const response[])
{
	DebugLogToFile("Full API Response:^n%s", response)
	
	// Check for success (200/201)
	if (containi(response, "HTTP/1.1 200") != -1 || containi(response, "HTTP/1.1 201") != -1)
	{
		return
	}
	
	if (containi(response, "HTTP/1.1 301") != -1 || containi(response, "HTTP/1.1 302") != -1)
	{
		DebugLogToFile("WARNING: API returned a REDIRECT. HLDS Sockets cannot follow redirects. Use the final URL in config (check if it should be https but we use http).")
	}
	
	// Error - save to retry queue
	log_amx("[Stats Mod] API error: Check debug.log for details")
}

// Retry queue
SaveToRetryQueue(const payload[])
{
	new queuePath[128]
	formatex(queuePath, charsmax(queuePath), "%s", QUEUE_DIR)
	
	if (!dir_exists(queuePath))
	{
		mkdir(queuePath)
	}
	
	// Create filename with timestamp
	new filename[128]
	new timestamp = GetCurrentTimestamp()
	formatex(filename, charsmax(filename), "%s/batch_%d.json", queuePath, timestamp)
	
	// Save payload to file
	new file = fopen(filename, "wt")
	if (file)
	{
		fputs(file, payload)
		fclose(file)
		log_amx("[Stats Mod] Saved failed batch to queue: %s", filename)
	}
}

public TaskProcessRetryQueue()
{
	if (!g_StatsEnabled || g_SendingInProgress)
		return
	
	// Check rate limiting
	new Float:currentTime = get_gametime()
	if (currentTime - g_LastSendTime < MIN_SEND_INTERVAL)
		return
	
	ProcessRetryQueue()
}

ProcessRetryQueue()
{
	new queuePath[128]
	formatex(queuePath, charsmax(queuePath), "%s", QUEUE_DIR)
	
	if (!dir_exists(queuePath))
		return
	
	new dir = open_dir(queuePath, "", 0)
	if (!dir)
		return
	
	new filename[128], filepath[256]
	new fileCount = 0
	
	while (next_file(dir, filename, charsmax(filename)) && fileCount < 5)
	{
		if (containi(filename, ".json") == -1)
			continue
		
		formatex(filepath, charsmax(filepath), "%s/%s", queuePath, filename)
		
		new file = fopen(filepath, "rt")
		if (!file)
			continue
		
		new payload[MAX_JSON_SIZE]
		new len = 0
		new line[256]
		while (!feof(file) && len < charsmax(payload) - 1)
		{
			fgets(file, line, charsmax(line))
			new lineLen = strlen(line)
			if (len + lineLen < charsmax(payload) - 1)
			{
				copy(payload[len], charsmax(payload) - len, line)
				len += lineLen
			}
		}
		fclose(file)
		
		if (len > 0)
		{
			payload[len] = 0
			trim(payload)
			
			// Try to send
			g_SendingInProgress = 1
			SendStatisticsBatch(payload)
			g_LastSendTime = get_gametime()
			
			// If still in progress after timeout, keep file
			// Otherwise delete it (successful send)
			set_task(2.0, "DeleteQueueFile", _, filepath, strlen(filepath))
			
			fileCount++
		}
	}
	
	close_dir(dir)
}

public DeleteQueueFile(filepath[])
{
	if (file_exists(filepath))
	{
		delete_file(filepath)
	}
}

// Utility functions
GetSteamID(player, output[], len)
{
	if (!IsValidPlayer(player))
	{
		output[0] = 0
		return
	}
	
	get_user_authid(player, output, len)
}

GetCurrentTimestamp()
{
	return get_systime()
}

DebugLogToFile(const msg[], any:...)
{
	new buffer[512]
	vformat(buffer, charsmax(buffer), msg, 2)
	
	new dataDir[128]
	formatex(dataDir, charsmax(dataDir), "addons/amxmodx/data/stats_mod")
	if (!dir_exists(dataDir)) mkdir(dataDir)
	
	new path[256]
	formatex(path, charsmax(path), "%s/debug.log", dataDir)
	log_to_file(path, buffer)
}

ValidateUUID(const uuid[])
{
	// Check UUID v4 format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (36 chars)
	if (strlen(uuid) != 36)
		return 0
	
	// Check format
	for (new i = 0; i < 36; i++)
	{
		if (i == 8 || i == 13 || i == 18 || i == 23)
		{
			if (uuid[i] != '-')
				return 0
		}
		else
		{
			if (!((uuid[i] >= '0' && uuid[i] <= '9') || 
				(uuid[i] >= 'a' && uuid[i] <= 'f') || 
				(uuid[i] >= 'A' && uuid[i] <= 'F')))
				return 0
		}
	}
	
	return 1
}


