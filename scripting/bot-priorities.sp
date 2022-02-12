/*

List of priorities:
 - Killing Infected
 - Pick Up Items
 - Reviving Teammates
 - Picking up Incaps
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <bot-priorities>

#define PLUGIN_VERSION "1.0.6"

#define MAX_PRIORITES 256

#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3

#define TRACE_TOLERANCE 75.0

public Plugin myinfo = 
{
	name = "[L4D2] Bot Priorities", 
	author = "Keith The Corgi", 
	description = "Manages bot priorities based on distance and actions.", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/keiththecorgi"
};

ConVar convar_Timeout;

enum struct Priorities
{
	char name[MAX_NAME_LENGTH]; //Name of the Priority.
	bool status; //Whether this priority is enabled or disabled.
	int team; //0 = all, 1 = ignored, 2 = Survivors, 3 = Infected
	char entity[64]; //The entity at which is targeted specifically.
	char entity_flags[256]; //The required flags that must be on the entity.
	float trigger_distance;	//Minimum distance at which is required to trigger this priority.
	float required_distance; //The required distance for the bot to move towards the entity before the action takes place.
	float movement_delay; //The delay at which movement commands are sent to the bot.
	int classid; //The class ID used in conjunction with the entity to determine which survivor or infected to look for. Entity must be 'player' for this to be used.
	int slot; //The slot to switch the bot to when the required distance is met.
	char slot_entity[64]; //The required entity to have in that slot as a weapon or item.
	char buttons[256]; //The buttons to press whenever the bot is within the required distance.
	float button_delay; //The delay at which to press the buttons over and over again.
	char block_buttons[256]; //Buttons to block for bots when the priority is active and/or the required distance is met.
	char script[512]; //A VScript to execute whenever the bot is within the required distance.
	bool lookat; //Toggle on/off to look at the target manually whenever the bot is within the required distance.
	char release_event[64]; //The event called whenever the bot should have their current priority released.
	float release_seconds; //The time in seconds once the priority is found for the bot to forget about the priority automatically.
	bool ispinned; //Easy check whether or not the target is a survivor who has been pinned by an infected.
	bool haspinned; //Easy check whether or not the target is an infected and has a survivor pinned.
	float periodic_add; //The amount of periodic to add to the timer for this priority to be active.
	float periodic_required; //The required amount of periodic for this priority to become active.
	bool must_be_visible; //A basic check to see if the bot and the entity target are visible to each other.
	int is_hanging; //Checks whether the entity target is hanging or not.
	int is_incapped; //Checks whether the entity target is incapped or not.

	void Add(const char[] name, bool status, int team, const char[] entity, const char[] entity_flags, float trigger_distance, float required_distance, float movement_delay, int classid, int slot, const char[] slot_entity, const char[] buttons, float button_delay, const char[] block_buttons, const char[] script, bool lookat, const char[] release_event, float release_seconds, bool ispinned, bool haspinned, float periodic_add, float periodic_required, bool must_be_visible, int is_hanging, int is_incapped)
	{
		strcopy(this.name, sizeof(Priorities::name), name);
		this.status = status;
		this.team = team;
		strcopy(this.entity, sizeof(Priorities::entity), entity);
		strcopy(this.entity_flags, sizeof(Priorities::entity_flags), entity_flags);
		this.trigger_distance = trigger_distance;
		this.required_distance = required_distance;
		this.movement_delay = movement_delay;
		this.classid = classid;
		this.slot = slot;
		strcopy(this.slot_entity, sizeof(Priorities::slot_entity), slot_entity);
		strcopy(this.buttons, sizeof(Priorities::buttons), buttons);
		this.button_delay = button_delay;
		strcopy(this.block_buttons, sizeof(Priorities::block_buttons), block_buttons);
		strcopy(this.script, sizeof(Priorities::script), script);
		this.lookat = lookat;
		strcopy(this.release_event, sizeof(Priorities::release_event), release_event);
		this.release_seconds = release_seconds;
		this.ispinned = ispinned;
		this.haspinned = haspinned;
		this.periodic_add = periodic_add;
		this.periodic_required = periodic_required;
		this.must_be_visible = must_be_visible;
		this.is_hanging = is_hanging;
		this.is_incapped = is_incapped;
	}
}

Priorities g_Priorities[MAX_PRIORITES];
int g_TotalPriorities;

GlobalForward g_Fw_ConfigLoaded;
GlobalForward g_Fw_ConfigReloaded;
GlobalForward g_Fw_OnPrioFound;
GlobalForward g_Fw_OnPrioCleared;

enum struct Bot
{
	StringMap periodics;

	void Init()
	{
		delete this.periodics;
		this.periodics = new StringMap();
	}

	void AddP(int prio, float value)
	{
		float set = this.GetP(prio) + value;
		this.SetP(prio, set);
	}

	void SetP(int prio, float value)
	{
		char sPrio[32];
		IntToString(prio, sPrio, sizeof(sPrio));

		this.periodics.SetValue(sPrio, value);
	}

	void RemoveP(int prio, float value)
	{
		float set = this.GetP(prio) - value;
		this.SetP(prio, set);
	}

	float GetP(int prio)
	{
		char sPrio[32];
		IntToString(prio, sPrio, sizeof(sPrio));

		float value;
		this.periodics.GetValue(sPrio, value);

		return value;
	}

	void Clear()
	{
		this.periodics.Clear();
	}
}

Bot g_Bot[MAXPLAYERS + 1];

int g_CurrentPrio[MAXPLAYERS + 1] = {NO_PRIO, ...};
int g_CurrentTarget[MAXPLAYERS + 1] = {NO_TARGET, ...};
float g_MovementDelay[MAXPLAYERS + 1];
float g_CurrentPrioTime[MAXPLAYERS + 1] = {NO_TIME, ...};
float g_PrioTimeout[MAXPLAYERS + 1] = {NO_TIME, ...};
float g_DelayFire[MAXPLAYERS + 1] = {NO_TIME, ...};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("bot-priorities");

	CreateNative("BotPrio_GetPrio", Native_GetPrio);
	CreateNative("BotPrio_SetPrio", Native_SetPrio);
	CreateNative("BotPrio_ClearPrio", Native_ClearPrio);
	CreateNative("BotPrio_GetName", Native_GetName);

	g_Fw_ConfigLoaded = new GlobalForward("BotPrio_ConfigLoaded", ET_Ignore);
	g_Fw_ConfigReloaded = new GlobalForward("BotPrio_ConfigReloaded", ET_Ignore, Param_Cell);
	g_Fw_OnPrioFound = new GlobalForward("BotPrio_OnPrioFound", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_Fw_OnPrioCleared = new GlobalForward("BotPrio_OnPrioCleared", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

	return APLRes_Success;
}

public int Native_GetPrio(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index '%i' is invalid or not available.", client);
	
	if (!IsFakeClient(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index '%i' is not a bot.", client);
	
	return g_CurrentPrio[client];
}

public int Native_SetPrio(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index '%i' is invalid or not available.", client);
	
	if (!IsFakeClient(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index '%i' is not a bot.", client);
	
	int prio = GetNativeCell(2);
	int target = GetNativeCell(3);
	
	return SetPrio(client, prio, target);
}

public int Native_ClearPrio(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);

	if (client < 1 || client > MaxClients || !IsClientInGame(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index '%i' is invalid or not available.", client);
	
	if (!IsFakeClient(client))
		return ThrowNativeError(SP_ERROR_NATIVE, "Client index '%i' is not a bot.", client);
	
	return ClearPrio(client);
}

public int Native_GetName(Handle plugin, int numParams)
{
	int prio = GetNativeCell(1);

	if (prio < 1 || prio > g_TotalPriorities)
		return false;
	
	SetNativeString(2, g_Priorities[prio].name, GetNativeCell(3));
	
	return true;
}

public void OnPluginStart()
{
	CreateConVar("sm_botpriorities_version", PLUGIN_VERSION, "The current version of this plugin.");
	convar_Timeout = CreateConVar("sm_botpriorities_timeout", "2.0", "The maximum amount of time a priority can be active for before being timed out.", FCVAR_NOTIFY, true, 0.0);

	RegAdminCmd("sm_reloadprios", Command_ReloadPrio, ADMFLAG_ROOT, "Reload all bot priorities from the config.");
	RegAdminCmd("sm_prios", Command_Prios, ADMFLAG_ROOT, "List all available bot priorities and toggle them on or off.");

	HookEvent("ability_use", Event_Release);
	HookEvent("ammo_pickup", Event_Release);
	HookEvent("item_pickup", Event_Release);
	HookEvent("player_death", Event_Release);
	HookEvent("upgrade_pack_used", Event_Release);

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientConnected(i))
			OnClientConnected(i);
	
	ParsePriorities(-1);
}

public Action Command_ReloadPrio(int client, int args)
{
	ParsePriorities(client);
	return Plugin_Handled;
}

public Action Command_Prios(int client, int args)
{
	OpenPrioritiesMenu(client);
	return Plugin_Handled;
}

void OpenPrioritiesMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Priorities);
	menu.SetTitle("Bot Priorities: (%i/%i Active)", GetActivePriorities(), g_TotalPriorities);

	char sID[16]; char sDisplay[256];
	for (int i = 0; i < g_TotalPriorities; i++)
	{
		IntToString(i, sID, sizeof(sID));
		FormatEx(sDisplay, sizeof(sDisplay), "%s (%s)", g_Priorities[i].name, g_Priorities[i].status ? "ON" : "OFF");
		menu.AddItem(sID, sDisplay);
	}

	if (menu.ItemCount == 0)
		menu.AddItem("", " :: No Priorities Found", ITEMDRAW_DISABLED);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Priorities(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char sID[16];
			menu.GetItem(param2, sID, sizeof(sID));

			int index = StringToInt(sID);
			g_Priorities[index].status = !g_Priorities[index].status;

			char sStatus[16];
			IntToString(g_Priorities[index].status, sStatus, sizeof(sStatus));
			SetPriorityConfigValue(index, "status", sStatus);

			OpenPrioritiesMenu(param1);
		}

		case MenuAction_End:
			delete menu;
	}

	return 0;
}

void SetPriorityConfigValue(int index, const char[] key, const char[] value)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/bot-priorities.cfg");

	KeyValues kv = new KeyValues("bot-priorities");
	kv.ImportFromFile(sPath);
	kv.JumpToKey(g_Priorities[index].name);
	kv.SetString(key, value);
	kv.Rewind();
	kv.ExportToFile(sPath);
	delete kv;
}

int GetActivePriorities()
{
	int amount;

	for (int i = 0; i < g_TotalPriorities; i++)
		if (g_Priorities[i].status)
			amount++;
	
	return amount;
}

void ParsePriorities(int client = -1)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/bot-priorities.cfg");

	KeyValues kv = new KeyValues("bot-priorities");

	if (kv.ImportFromFile(sPath) && kv.GotoFirstSubKey(false))
	{
		g_TotalPriorities = 0;
		
		char name[MAX_NAME_LENGTH]; //Name of the Priority.
		bool status; //Whether this priority is enabled or disabled.
		int team; //0 = all, 1 = ignored, 2 = Survivors, 3 = Infected
		char entity[64]; //The entity at which is targeted specifically.
		char entity_flags[256]; //The required flags that must be on the entity.
		float trigger_distance;	//Minimum distance at which is required to trigger this priority.
		float required_distance; //The required distance for the bot to move towards the entity before the action takes place.
		float movement_delay; //The delay at which movement commands are sent to the bot.
		int classid; //The class ID used in conjunction with the entity to determine which survivor or infected to look for.
		int slot; //The slot to switch the bot to when the required distance is met.
		char slot_entity[64]; //The required entity to have in that slot as a weapon or item.
		char buttons[256]; //The buttons to press whenever the bot is within the required distance.
		float button_delay; //The delay at which to press the buttons over and over again.
		char block_buttons[256]; //Buttons to block for bots when the priority is active and/or the required distance is met.
		char script[512]; //A VScript to execute whenever the bot is within the required distance.
		bool lookat; //Toggle on/off to look at the target manually whenever the bot is within the required distance.
		char release_event[64]; //The event called whenever the bot should have their current priority released.
		float release_seconds; //The time in seconds once the priority is found for the bot to forget about the priority automatically.
		bool ispinned; //Easy check whether or not the target is a survivor who has been pinned by an infected.
		bool haspinned; //Easy check whether or not the target is an infected and has a survivor pinned.
		float periodic_add; //The amount of periodic to add to the timer for this priority to be active.
		float periodic_required; //The required amount of periodic for this priority to become active.
		bool must_be_visible; //A basic check to see if the bot and the entity target are visible to each other.
		int is_hanging; //Checks whether the entity target is hanging or not.
		int is_incapped; //Checks whether the entity target is incapped or not.

		do
		{
			kv.GetSectionName(name, sizeof(name));
			status = view_as<bool>(kv.GetNum("status", 1));
			team = kv.GetNum("team", -1);
			kv.GetString("entity", entity, sizeof(entity), "");
			kv.GetString("entity_flags", entity_flags, sizeof(entity_flags), "");
			trigger_distance = kv.GetFloat("trigger_distance", -1.0);
			required_distance = kv.GetFloat("required_distance", -1.0);
			movement_delay = kv.GetFloat("movement_delay", 1.0);
			classid = kv.GetNum("classid", -1);
			slot = kv.GetNum("slot", -1);
			kv.GetString("slot_entity", slot_entity, sizeof(slot_entity), "");
			kv.GetString("buttons", buttons, sizeof(buttons), "");
			button_delay = kv.GetFloat("button_delay", -1.0);
			kv.GetString("block_buttons", block_buttons, sizeof(block_buttons), "");
			kv.GetString("script", script, sizeof(script), "");
			lookat = view_as<bool>(kv.GetNum("lookat", 0));
			kv.GetString("release_event", release_event, sizeof(release_event), "");
			release_seconds = kv.GetFloat("release_seconds", -1.0);
			ispinned = view_as<bool>(kv.GetNum("ispinned", 0));
			haspinned = view_as<bool>(kv.GetNum("haspinned", 0));
			periodic_add = kv.GetFloat("periodic_add", -1.0);
			periodic_required = kv.GetFloat("periodic_required", -1.0);
			must_be_visible = view_as<bool>(kv.GetNum("must_be_visible", 0));
			is_hanging = kv.GetNum("is_hanging", -1);
			is_incapped = kv.GetNum("is_incapped", -1);

			g_Priorities[g_TotalPriorities++].Add(name, status, team, entity, entity_flags, trigger_distance, required_distance, movement_delay, classid, slot, slot_entity, buttons, button_delay, block_buttons, script, lookat, release_event, release_seconds, ispinned, haspinned, periodic_add, periodic_required, must_be_visible, is_hanging, is_incapped);
		}
		while (kv.GotoNextKey(false));
	}

	delete kv;
	LogMessage("%i bot priorities found.", g_TotalPriorities);

	if (client > -1)
	{
		ReplyToCommand(client, "Bot priorities reloaded, %i found total.", g_TotalPriorities);

		Call_StartForward(g_Fw_ConfigReloaded);
		Call_PushCell(client);
		Call_Finish();
	}
	else
	{
		Call_StartForward(g_Fw_ConfigLoaded);
		Call_Finish();
	}
}

public void OnClientConnected(int client)
{
	g_Bot[client].Init();
}

public void OnClientDisconnect_Post(int client)
{
	g_CurrentPrio[client] = NO_PRIO;
	g_CurrentTarget[client] = NO_TARGET;
	g_Bot[client].Clear();
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || !IsFakeClient(client))
		return Plugin_Continue;
	
	if (GetEntProp(client, Prop_Send, "m_isHangingFromLedge") || GetEntProp(client, Prop_Send, "m_isIncapacitated"))
		return Plugin_Continue;
	
	if (GetEntityMoveType(client) == MOVETYPE_LADDER)
		return Plugin_Continue;
	
	float origin[3];
	GetClientAbsOrigin(client, origin);

	int team = GetClientTeam(client);
	float time = GetGameTime();
	
	//If this bot has a priority already, don't assign a new one until they've finished this priority.
	if (g_CurrentPrio[client] != NO_PRIO)
	{
		int prio = g_CurrentPrio[client];
		int target = g_CurrentTarget[client];

		//Priority was turned off while the bot had the priority currently.
		if (!g_Priorities[prio].status)
		{
			ClearPrio(client);
			return Plugin_Continue;
		}

		//The player's team has changed or the prio's team has changed, clear prio if the new values don't match up.
		if (g_Priorities[prio].team != -1 && g_Priorities[prio].team != team)
		{
			ClearPrio(client);
			return Plugin_Continue;
		}

		//A target is involved with this priority and the entity is no longer alive.
		if (target != NO_TARGET && !IsValidEntity(target))
		{
			ClearPrio(client);
			return Plugin_Continue;
		}

		//The priority has lasted too long so we should time it out.
		if (g_PrioTimeout[client] != NO_TIME && g_PrioTimeout[client] <= time)
		{
			ClearPrio(client);
			return Plugin_Continue;
		}

		//The priority has been timed out manually by the plugin.
		if ((time - g_CurrentPrioTime[client]) > convar_Timeout.FloatValue)
		{
			ClearPrio(client);
			return Plugin_Continue;
		}

		float entorigin[3];
		if (IsValidEntity(target))
			GetEntPropVector(target, Prop_Send, "m_vecOrigin", entorigin);

		//If a required distance is set and we're not in the required distance, move the bot towards the target.
		if (g_Priorities[prio].required_distance > 0.0 && GetVectorDistance(origin, entorigin) > g_Priorities[prio].required_distance)
		{
			if (g_MovementDelay[client] > time)
				return Plugin_Continue;
			
			g_MovementDelay[client] = time + g_Priorities[prio].movement_delay;

			ExecuteScript(client, "CommandABot({cmd=1,pos=Vector(%f,%f,%f),bot=GetPlayerFromUserID(%i)})", entorigin[0], entorigin[1], entorigin[2], GetClientUserId(client));
			return Plugin_Continue;
		}

		if (g_Priorities[prio].slot != -1 && GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != GetPlayerWeaponSlot(client, g_Priorities[prio].slot))
		{
			int slotweapon = GetPlayerWeaponSlot(client, g_Priorities[prio].slot);

			if (IsValidEntity(slotweapon))
			{
				char class[32];
				GetEdictClassname(slotweapon, class, sizeof(class));

				//They switched items/weapons in this slot during the priority so clear the priority now.
				if (strlen(g_Priorities[prio].slot_entity) > 0 && !StrEqual(class, g_Priorities[prio].slot_entity, false))
				{
					ClearPrio(client);
					return Plugin_Continue;
				}

				FakeClientCommand(client, "use %s", class);
				SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
			}
		}

		if (g_Priorities[prio].lookat)
		{
			float EyePos[3];
			GetClientEyePosition(client, EyePos);

			float AimOnDeadSurvivor[3];
			MakeVectorFromPoints(EyePos, entorigin, AimOnDeadSurvivor);

			float AimAngles[3];
			GetVectorAngles(AimOnDeadSurvivor, AimAngles);

			TeleportEntity(client, NULL_VECTOR, AimAngles, NULL_VECTOR);
		}

		if (strlen(g_Priorities[prio].buttons) > 0)
		{
			if (g_Priorities[prio].button_delay == -1 || g_Priorities[prio].button_delay != -1 && g_DelayFire[client] <= time)
			{
				g_DelayFire[client] = time + g_Priorities[prio].button_delay;

				if (StrContains(g_Priorities[prio].buttons, "IN_ATTACK", false) != -1)
					buttons |= IN_ATTACK;
				
				if (StrContains(g_Priorities[prio].buttons, "IN_ATTACK2", false) != -1)
					buttons |= IN_ATTACK2;
				
				if (StrContains(g_Priorities[prio].buttons, "IN_USE", false) != -1)
					buttons |= IN_USE;
			}
		}

		if (strlen(g_Priorities[prio].block_buttons) > 0)
		{
			if (StrContains(g_Priorities[prio].block_buttons, "IN_ATTACK", false) != -1)
				buttons &= ~IN_ATTACK;
			
			if (StrContains(g_Priorities[prio].block_buttons, "IN_ATTACK2", false) != -1)
				buttons &= ~IN_ATTACK2;
			
			if (StrContains(g_Priorities[prio].block_buttons, "IN_USE", false) != -1)
				buttons &= ~IN_USE;
		}

		if (strlen(g_Priorities[prio].script) > 0)
			ExecuteScript(client, "%s", g_Priorities[prio].script);

		return Plugin_Continue;
	}

	float distance;
	float entorigin[3];

	//Sort through every priority per tick if this bot doesn't have a priority to find one if possible.
	for (int i = 0; i < g_TotalPriorities; i++)
	{
		//Priority is currently off, skip it from happening entirely.
		if (!g_Priorities[i].status)
			continue;
		
		//If a team is specified, must be on that team to be assigned this priority.
		if (g_Priorities[i].team != -1 && g_Priorities[i].team != team)
			continue;
		
		//Lets make sure the bot has the proper weapon in the proper slot if specified otherwise don't assign them this priority.
		if (g_Priorities[i].slot != -1 && strlen(g_Priorities[i].slot_entity) > 0)
		{
			int slotweapon = GetPlayerWeaponSlot(client, g_Priorities[i].slot);
			
			if (!IsValidEntity(slotweapon))
				continue;
			
			char class[64];
			GetEdictClassname(slotweapon, class, sizeof(class));

			if (!StrEqual(class, g_Priorities[i].slot_entity, false))
				continue;
		}

		//Adds delays for when this priority should be active.
		if (g_Priorities[i].periodic_required != -1.0)
		{
			g_Bot[client].AddP(i, g_Priorities[i].periodic_add);

			if (g_Bot[client].GetP(i) < g_Priorities[i].periodic_required)
				continue;
			
			g_Bot[client].SetP(i, 0.0);
		}

		if (strlen(g_Priorities[i].entity) > 0)
		{
			distance = g_Priorities[i].trigger_distance;
			
			int entity = -1; int flags;
			while ((entity = FindEntityByClassname(entity, g_Priorities[i].entity)) != -1)
			{
				if (strlen(g_Priorities[i].entity_flags) > 0)
				{
					flags = GetEntityFlags(entity);

					if (StrContains(g_Priorities[i].entity_flags, "FL_ONFIRE", false) != -1 && (flags & FL_ONFIRE) == FL_ONFIRE)
						continue;
				}

				//If the target is a player then we can check what their survivor ID or their infected ID is.
				//Also check if they should be pinned currently or are pinning themselves.
				if (StrEqual(g_Priorities[i].entity, "player", false))
				{
					if (client == entity)
						continue;
					
					if (team == GetClientTeam(entity))
						continue;
					
					if (GetClientTeam(entity) < TEAM_SURVIVORS)
						continue;
					
					if (!IsPlayerAlive(entity))
						continue;
					
					if (g_Priorities[i].is_hanging != -1 && GetEntProp(entity, Prop_Send, "m_isHangingFromLedge") != g_Priorities[i].is_hanging)
						continue;
					
					if (g_Priorities[i].is_incapped != -1 && GetEntProp(entity, Prop_Send, "m_isIncapacitated") != g_Priorities[i].is_incapped)
						continue;
					
					switch (GetClientTeam(entity))
					{
						case TEAM_SURVIVORS:
						{
							if (g_Priorities[i].classid != -1 && GetEntProp(entity, Prop_Send, "m_survivorCharacter") != g_Priorities[i].classid)
								continue;
							
							if (g_Priorities[i].ispinned && GetInfectedAttacker(entity) < 1)
								continue;
						}

						case TEAM_INFECTED:
						{
							if (g_Priorities[i].classid != -1 && GetEntProp(entity, Prop_Send, "m_zombieClass") != g_Priorities[i].classid)
								continue;
							
							if (g_Priorities[i].haspinned && GetSurvivorVictim(entity) < 1)
								continue;
						}
					}
				}

				GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entorigin);

				//A trigger distance is set, only target the nearest entity then with the distance in mind.
				if (distance > 0.0 && GetVectorDistance(origin, entorigin) > distance)
					continue;
				
				//Checks if there's no geometry or visible props between the bot and the target entity.
				if (g_Priorities[i].must_be_visible && !IsVisibleTo(client, entity))
					continue;
				
				//Sets the priority of the bot manually.
				SetPrio(client, i, entity);
			}
		}
		else
			SetPrio(client, i);
	}

	return Plugin_Continue;
}

public Action OnWeaponSwitch(int client, int weapon)
{
	return Plugin_Stop;
}

stock void ExecuteScript(int client, const char[] script, any ...)
{
	char vscript[PLATFORM_MAX_PATH];
	VFormat(vscript, sizeof(vscript), script, 3);
	
	int flags = GetCommandFlags("script");
	SetCommandFlags("script", flags ^ FCVAR_CHEAT);
	FakeClientCommand(client, "script %s", vscript);
	SetCommandFlags("script", flags | FCVAR_CHEAT);
}

public void Event_Release(Event event, const char[] name, bool dontBroadcast)
{
	int client;
	if (StrEqual(name, "player_death", false))
		client = GetClientOfUserId(event.GetInt("attacker"));
	else
		client = GetClientOfUserId(event.GetInt("userid"));
	
	int prio = g_CurrentPrio[client];

	if (prio == NO_PRIO)
		return;
	
	if (StrEqual(name, g_Priorities[prio].release_event, false))
		ClearPrio(client);
}

bool SetPrio(int client, int prio, int target = NO_TARGET)
{	
	//All checks passed, give them this priority and assign the target.
	g_CurrentPrio[client] = prio;
	g_CurrentTarget[client] = target;
	g_CurrentPrioTime[client] = GetGameTime();

	//Sets a timeout for this priority based on seconds of it being received.
	if (g_Priorities[prio].release_seconds != -1.0)
		g_PrioTimeout[client] = g_CurrentPrioTime[client] + g_Priorities[prio].release_seconds;
	
	Call_StartForward(g_Fw_OnPrioFound);
	Call_PushCell(client);
	Call_PushCell(prio);
	Call_PushCell(target);
	Call_Finish();

	//PrintToChatAll("%N has received the priority [%i] '%s' with the target index '%i'.", client, prio, g_Priorities[prio].name, target);
	
	return true;
}

bool ClearPrio(int client)
{
	//Bot already doesn't have a prio, no need to reset them.
	if (g_CurrentPrio[client] == NO_PRIO)
		return false;
	
	int prev = g_CurrentPrio[client];
	int prev2 = g_CurrentTarget[client];
	
	//Reset the data of the bot through cached variables.
	ClearData(client);

	Call_StartForward(g_Fw_OnPrioCleared);
	Call_PushCell(client);
	Call_PushCell(prev);
	Call_PushCell(prev2);
	Call_Finish();

	return true;
}

void ClearData(int client)
{
	g_CurrentPrio[client] = NO_PRIO;
	g_CurrentTarget[client] = NO_TARGET;
	g_MovementDelay[client] = 0.0;
	g_CurrentPrioTime[client] = NO_TIME;
	g_PrioTimeout[client] = NO_TIME;
	g_DelayFire[client] = NO_TIME;
	g_Bot[client].Clear();

	SDKUnhook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
}

stock int GetInfectedAttacker(int client)
{
	int attacker;

	/* Charger */
	attacker = GetEntPropEnt(client, Prop_Send, "m_pummelAttacker");
	if (attacker > 0)
		return attacker;

	attacker = GetEntPropEnt(client, Prop_Send, "m_carryAttacker");
	if (attacker > 0)
		return attacker;

	/* Hunter */
	attacker = GetEntPropEnt(client, Prop_Send, "m_pounceAttacker");
	if (attacker > 0)
		return attacker;

	/* Smoker */
	attacker = GetEntPropEnt(client, Prop_Send, "m_tongueOwner");
	if (attacker > 0)
		return attacker;

	/* Jockey */
	attacker = GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker");
	if (attacker > 0)
		return attacker;

	return -1;
}

stock int GetSurvivorVictim(int client)
{
    int victim;

    /* Charger */
    victim = GetEntPropEnt(client, Prop_Send, "m_pummelVictim");
    if (victim > 0)
        return victim;

    victim = GetEntPropEnt(client, Prop_Send, "m_carryVictim");
    if (victim > 0)
        return victim;

    /* Hunter */
    victim = GetEntPropEnt(client, Prop_Send, "m_pounceVictim");
    if (victim > 0)
        return victim;

    /* Smoker */
    victim = GetEntPropEnt(client, Prop_Send, "m_tongueVictim");
    if (victim > 0)
        return victim;

    /* Jockey */
    victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
    if (victim > 0)
        return victim;

    return -1;
}

public void OnMapEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		ClearData(i);
}

bool IsVisibleTo(int client, int entity)
{
	float vOrigin[3];
	GetClientEyePosition(client,vOrigin);

	float vEnt[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vEnt);

	float vLookAt[3];
	MakeVectorFromPoints(vOrigin, vEnt, vLookAt);

	float vAngles[3];
	GetVectorAngles(vLookAt, vAngles);

	Handle trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, TraceFilter);

	bool isVisible;
	if (TR_DidHit(trace))
	{
		float vStart[3];
		TR_GetEndPosition(vStart, trace);
		
		if ((GetVectorDistance(vOrigin, vStart, false) + TRACE_TOLERANCE) >= GetVectorDistance(vOrigin, vEnt))
			isVisible = true;
	}
	else
		isVisible = true;

	delete trace;
	return isVisible;
}

public bool TraceFilter(int entity, int contentsMask)
{
	if (entity <= MaxClients || !IsValidEntity(entity))
		return false;
	
	char class[128];
	GetEdictClassname(entity, class, sizeof(class));
	
	return !StrEqual(class, "prop_physics", false);
}

stock bool IsClientIdle(int client)
{
	if (GetClientTeam(client) != 1)
		return false;

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientConnected(i) && IsClientInGame(i))
			if ((GetClientTeam(i) == TEAM_SURVIVORS) && IsPlayerAlive(i))
				if (IsFakeClient(i))
					if (GetClientOfUserId(GetEntProp(i, Prop_Send, "m_humanSpectatorUserID")) == client)
						return true;

	return false;
}