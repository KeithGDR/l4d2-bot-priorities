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
#include <bot-priorities>

#define PLUGIN_VERSION "1.0.2"

#define MAX_PRIORITES 256

#define NO_PRIO -1
#define NO_TARGET -1

#define TEAM_SURVIVORS 2
#define TEAM_INFECTED 3

public Plugin myinfo = 
{
	name = "[L4D2] Bot Priorities", 
	author = "Keith The Corgi", 
	description = "Manages bot priorities based on distance and actions.", 
	version = PLUGIN_VERSION, 
	url = "https://github.com/keiththecorgi"
};

enum struct Priorities
{
	char name[MAX_NAME_LENGTH]; //Name of the Priority.
	bool status; //Whether this priority is enabled or disabled.
	int team; //0 = all, 1 = ignored, 2 = Survivors, 3 = Infected
	char entity[64]; //The entity at which is targeted specifically.
	float trigger_distance;	//Minimum distance at which is required to trigger this priority.
	float required_distance; //The required distance for the bot to move towards the entity before the action takes place.
	int classid; //The class ID used in conjunction with the entity to determine which survivor or infected to look for. Entity must be 'player' for this to be used.
	int slot; //The slot to switch the bot to when the required distance is met.
	char buttons[256]; //The buttons to press whenever the bot is within the required distance.
	char script[512]; //A VScript to execute whenever the bot is within the required distance.

	void Add(const char[] name, bool status, int team, const char[] entity, float trigger_distance, float required_distance, int classid, int slot, const char[] buttons, const char[] script)
	{
		strcopy(this.name, sizeof(Priorities::name), name);
		this.status = status;
		this.team = team;
		strcopy(this.entity, sizeof(Priorities::entity), entity);
		this.trigger_distance = trigger_distance;
		this.required_distance = required_distance;
		this.classid = classid;
		this.slot = slot;
		strcopy(this.buttons, sizeof(Priorities::buttons), buttons);
		strcopy(this.script, sizeof(Priorities::script), script);
	}
}

Priorities g_Priorities[MAX_PRIORITES];
int g_TotalPriorities;

GlobalForward g_Fw_ConfigLoaded;
GlobalForward g_Fw_ConfigReloaded;

int g_CurrentPrio[MAXPLAYERS + 1] = {NO_PRIO, ...};
int g_CurrentTarget[MAXPLAYERS + 1] = {NO_TARGET, ...};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("bot-priorities");

	CreateNative("BotPrio_GetPrio", Native_GetPrio);

	g_Fw_ConfigLoaded = new GlobalForward("BotPrio_ConfigLoaded", ET_Ignore);
	g_Fw_ConfigReloaded = new GlobalForward("BotPrio_ConfigReloaded", ET_Ignore, Param_Cell);

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

public void OnPluginStart()
{
	CreateConVar("sm_botpriorities_version", PLUGIN_VERSION, "The current version of this plugin.");

	RegAdminCmd("sm_reloadprios", Command_ReloadPrio, ADMFLAG_ROOT, "Reload all bot priorities from the config.");
	RegAdminCmd("sm_prios", Command_Prios, ADMFLAG_ROOT, "List all available bot priorities and toggle them on or off.");
	
	ParsePriorities(-1);

	RegConsoleCmd("sm_c", Command_C);
}

public Action Command_C(int client, int args)
{
	int entity = GetClientAimTarget(client, true);

	if (entity < 1)
	{
		PrintToChat(client, "not found");
		return Plugin_Handled;
	}

	char class[32];
	GetEntityClassname(entity, class, sizeof(class));
	PrintToChat(client, class);

	return Plugin_Handled;
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
		float trigger_distance;	//Minimum distance at which is required to trigger this priority.
		float required_distance; //The required distance for the bot to move towards the entity before the action takes place.
		int classid; //The class ID used in conjunction with the entity to determine which survivor or infected to look for.
		int slot; //The slot to switch the bot to when the required distance is met.
		char buttons[256]; //The buttons to press whenever the bot is within the required distance.
		char script[512]; //A VScript to execute whenever the bot is within the required distance.

		do
		{
			kv.GetSectionName(name, sizeof(name));
			status = view_as<bool>(kv.GetNum("status", 1));
			team = kv.GetNum("team", -1);
			kv.GetString("entity", entity, sizeof(entity), "");
			trigger_distance = kv.GetFloat("trigger_distance", -1.0);
			required_distance = kv.GetFloat("required_distance", -1.0);
			classid = kv.GetNum("classid", -1);
			slot = kv.GetNum("slot", -1);
			kv.GetString("buttons", buttons, sizeof(buttons), "");
			kv.GetString("script", script, sizeof(script), "");

			g_Priorities[g_TotalPriorities++].Add(name, status, team, entity, trigger_distance, required_distance, classid, slot, buttons, script);
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

public void OnClientDisconnect_Post(int client)
{
	g_CurrentPrio[client] = NO_PRIO;
	g_CurrentTarget[client] = NO_TARGET;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || !IsFakeClient(client))
		return Plugin_Continue;
	
	float origin[3];
	GetClientAbsOrigin(client, origin);
	
	//If this bot has a priority already, don't assign a new one until they've finished this priority.
	if (g_CurrentPrio[client] != NO_PRIO)
	{
		int prio = g_CurrentPrio[client];
		int target = g_CurrentTarget[client];

		//Priority was turned off while the bot had the priority currently.
		if (!g_Priorities[prio].status)
		{
			g_CurrentPrio[client] = NO_PRIO;
			g_CurrentTarget[client] = NO_TARGET;
			return Plugin_Continue;
		}

		float entorigin[3];
		GetEntPropVector(target, Prop_Send, "m_vecorigin", entorigin);

		//If a required distance is set and we're not in the required distance, move the bot towards the target.
		if (g_Priorities[prio].required_distance > 0.0 && GetVectorDistance(origin, entorigin) > g_Priorities[prio].required_distance)
		{
			ExecuteScript(client, "CommandABot({cmd=1,pos=Vector(%f,%f,%f),bot=GetPlayerFromUserID(%i)})", entorigin[0], entorigin[1], entorigin[2], GetClientUserId(client));
			return Plugin_Continue;
		}

		if (g_Priorities[prio].slot != -1 && GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon") != GetPlayerWeaponSlot(client, g_Priorities[prio].slot))
		{
			int slotweapon = GetPlayerWeaponSlot(client, g_Priorities[prio].slot);

			char class[32];
			GetEdictClassname(slotweapon, class, sizeof(class));

			FakeClientCommand(client, "use %s", class);
		}

		if (strlen(g_Priorities[prio].buttons) > 0)
		{
			if (StrContains(g_Priorities[prio].buttons, "IN_ATTACK", false) != -1)
				buttons |= IN_ATTACK;
			
			if (StrContains(g_Priorities[prio].buttons, "IN_ATTACK2", false) != -1)
				buttons |= IN_ATTACK2;
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
		
		//TODO: Make it so this is optional.
		if (strlen(g_Priorities[i].entity) == 0)
			continue;
		
		distance = g_Priorities[i].trigger_distance;
		
		int entity = -1;
		while ((entity = FindEntityByClassname(entity, g_Priorities[i].entity)) != -1)
		{
			//If the target is a player then we can check what their survivor ID or their infected ID is.
			if (StrEqual(g_Priorities[i].entity, "player", false))
			{
				switch (GetClientTeam(entity))
				{
					case TEAM_SURVIVORS:
					{
						if (GetEntProp(entity, Prop_Send, "m_survivorCharacter") != g_Priorities[i].classid)
							continue;
					}

					case TEAM_INFECTED:
					{
						if (GetEntProp(entity, Prop_Send, "m_zombieClass") != g_Priorities[i].classid)
							continue;
					}
				}

				continue;
			}

			GetEntPropVector(entity, Prop_Send, "m_vecorigin", entorigin);

			//A trigger distance is set, only target the nearest entity then with the distance in mind.
			if (distance > 0.0 && GetVectorDistance(origin, entorigin) > distance)
				continue;
			
			//All checks passed, give them this priority and assign the target.
			g_CurrentPrio[client] = i;
			g_CurrentTarget[client] = entity;
		}
	}

	return Plugin_Continue;
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