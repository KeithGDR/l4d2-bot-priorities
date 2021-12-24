#if defined _Bot_Priorities_included
#endinput
#endif
#define _Bot_Priorities_included

/**
	The current priority the bot has been assigned based on their current situation.

	client = Index of the bot.

	return = Priority ID
	error: Invalid Client Index / Client Is Not A Bot
**/
native int BotPrio_GetPrio(int client);

/**
	Called whenever the priorities configuration file is loaded for the first time.
**/
forward void BotPrio_ConfigLoaded();

/**
	Called whenever the priorities configuration file is reloaded by console or a client.
**/
forward void BotPrio_ConfigReloaded(int client);

public SharedPlugin __pl_Bot_Priorities = 
{
	name = "bot-priorities",
	file = "bot-priorities.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_Bot_Priorities_SetNTVOptional()
{
	
}
#endif
