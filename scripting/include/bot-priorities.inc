#if defined _Bot_Priorities_included
#endinput
#endif
#define _Bot_Priorities_included

#define NO_PRIO -1
#define NO_TARGET -1
#define NO_TIME -1.0

/**
	The current priority the bot has been assigned based on their current situation.

	client = Index of the bot.

	return = Priority ID
	error: Invalid Client Index / Client Is Not A Bot
**/
native int BotPrio_GetPrio(int client);

/**
	Manually set the current priority for the bot and whether or not it has a target associated with it.

	client = Index of the bot.
	prio = Index of the priority.
	target = Index of the target associated if this priority requires one.

	return = True if successful, false otherwise.
	error: Invalid Client Index / Client Is Not A Bot
**/
native int BotPrio_SetPrio(int client, int prio, int target = NO_TARGET);

/**
	Clears the current priority for the bot if it's assigned one currently.

	client = Index of the bot.

	return = True if one was found and cleared, false otherwise.
	error: Invalid Client Index / Client Is Not A Bot
**/
native bool BotPrio_ClearPrio(int client);

/**
	Retrieves the name of a certain priority based on index.

	prio = Index of the priority.
	buffer = String buffer to store the data in.
	size = Size of the string buffer.

	return = True if a valid priority was found and a name was provided, false otherwise.
**/
native bool BotPrio_GetName(int prio, char[] buffer, int size);

/**
	Called whenever the priorities configuration file is loaded for the first time.
**/
forward void BotPrio_ConfigLoaded();

/**
	Called whenever the priorities configuration file is reloaded by console or a client.
**/
forward void BotPrio_ConfigReloaded(int client);

/**
	Called whenever a bot has found a priority.

	client = Client Index of the bot.
	prio = Priority Index.
	target = Target Index if applicable.
**/
forward void BotPrio_OnPrioFound(int client, int prio, int target);

/**
	Called whenever a bot has their current priority cleared.

	client = Client Index of the bot.
	prio = Priority Index.
	target = Target Index if applicable.
**/
forward void BotPrio_OnPrioCleared(int client, int prio, int target);

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
	MarkNativeAsOptional("BotPrio_GetPrio");
	MarkNativeAsOptional("BotPrio_SetPrio");
	MarkNativeAsOptional("BotPrio_ClearPrio");
	MarkNativeAsOptional("BotPrio_GetName");
}
#endif
