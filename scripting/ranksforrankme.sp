#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <kento_rankme/rankme>
#include <chat-processor>
#include <store>
#include <multicolors>

#pragma tabsize 0
#pragma newdecls required

#define PLUGIN_AUTHOR "DiogoOnAir"
#define PLUGIN_VERSION "2.0"



ConVar cv_creditsammount;
ConVar cv_pluginmode;
ConVar cv_modelsmenu;
ConVar cv_chattag;


int prestigelevel[MAXPLAYERS + 1];
bool chattag[MAXPLAYERS + 1];
int rank[MAXPLAYERS+1] = {0, ...};
int rankType[MAXPLAYERS+1] = {0, ...};
int oldrank[MAXPLAYERS+1] = {0, ...};

Database g_db;

char RankStrings[][] =
{
	"Unranked",
	"Silver I",
	"Silver II",
	"Silver III",
	"Silver IV",
	"Silver Elite",
	"Silver Elite Master",
	"Gold Nova I",
	"Gold Nova II",
	"Gold Nova III",
	"Gold Nova Master",
	"Master Guardian I",
	"Master Guardian II",
	"Master Guardian Elite",
	"Distinguished Master Guardian",
	"Legendary Eagle",
	"Legendary Eagle Master",
	"Supreme First Master Class",
	"Global Elite"
};

char g_configpath[PLATFORM_MAX_PATH];
char g_mconfigpath[PLATFORM_MAX_PATH];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Store_GetClientCredits");
	MarkNativeAsOptional("Store_SetClientCredits");
}

public Plugin myinfo = 
{
	name = "Ranks for rankme | Prestige | REMAKE",
	author = PLUGIN_AUTHOR,
	description = "Matchmaking Ranks based on Kento Rankme Points with prestige addon",
	version = PLUGIN_VERSION,
	url = "https://www.steamcommunity.com/id/diogo218dv"
};

public void OnPluginStart()
{
	//Commands
	RegConsoleCmd("sm_lvl", Menu_MM);
	RegConsoleCmd("sm_prestige", Cmd_prestige);
	RegConsoleCmd("sm_pmodels", Cmd_PrestigeModels);
	RegConsoleCmd("sm_chattag", Cmd_ChatTag);
	
	//Events
	HookEvent("announce_phase_end", Event_AnnouncePhaseEnd);
	HookEvent("player_disconnect", Event_Disconnect, EventHookMode_Pre);
	HookEvent("player_death", PlayerDeath);
	
	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say_team");
	
	RegClientCookie("cookie_mm_type", "Matchmaking Icon Type", CookieAccess_Public);
	
	//Convars
	cv_creditsammount = CreateConVar("sm_ranksbyrankme_credits", "1000", "Amount Of Credits To Give");
	cv_pluginmode = CreateConVar("sm_ranksbyrankme_mode", "1", "1 to give credits / 2 to custom bonus, NOT DEVELOPED YET");
	cv_modelsmenu = CreateConVar("sm_ranksbyrankme_modelsenabled", "1", "if models menu per prestige are enabled");
	cv_chattag = CreateConVar("sm_ranksbyrankme_chattag", "1", "if 0 chat tag will be disabled"); 
	
	//Database
	ConnectToDatabase();
	
	//Translations
	LoadTranslations("ranksforrankme_phrases.txt");  
	
	BuildPath(Path_SM, g_configpath, sizeof(g_configpath), "configs/ranksforrankme.txt");
	BuildPath(Path_SM, g_mconfigpath, sizeof(g_mconfigpath), "configs/prestigemodels.txt");
}

public Action Cmd_ChatTag(int client, int args)
{
	if(chattag[client])
	{
		char g_Query[512];
		char steamid[512];
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		FormatEx(g_Query, 512, "UPDATE prestige_playerdb SET tag = 'NO' WHERE steamid = '%s'", steamid);
		SQL_TQuery(g_db, T_Generic, g_Query);
		chattag[client] = false;
		CPrintToChat(client, "%t", "DisableTag");
    }
    else
    {
    	char g_Query[512];
		char steamid[512];
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		FormatEx(g_Query, 512, "UPDATE prestige_playerdb SET tag = 'YES' WHERE steamid = '%s'", steamid);
		SQL_TQuery(g_db, T_Generic, g_Query);
    	chattag[client] = true;
    	CPrintToChat(client, "%t", "EnableTag");
    }
}

public Action Cmd_PrestigeModels(int client, int args)
{
	if(cv_modelsmenu.IntValue == 0)
	{
		return Plugin_Handled;
    }
    
    char Name[32], Id[32];
	Menu menu = new Menu(ModelsMenus);
	menu.SetTitle("Select Skin");
	Handle kv = CreateKeyValues("PrestigeModels");
	FileToKeyValues(kv, g_mconfigpath);
	KvGotoFirstSubKey(kv, false);
	do 
	{
		int g_level = KvGetNum(kv, "Prestige", 0);
		KvGetString(kv, "Name", Name, sizeof(Name));
		KvGetString(kv, "Id", Id, sizeof(Id));
		if(prestigelevel[client] >= g_level)
		{
			menu.AddItem(Id, Name);
		}
	}
	while(KvGotoNextKey(kv, false));
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
	SetMenuExitButton(menu, true);
	CloseHandle(kv);
	return Plugin_Continue;
}

public int ModelsMenus(Handle menu, MenuAction action, int client, int param2) {

	char Name[32], Model[128], Arms[128], Id[32];
	Handle kv = CreateKeyValues("PrestigeModels");
	FileToKeyValues(kv, g_mconfigpath);

	switch (action) {

		case MenuAction_Select: {

			char item[64];
			GetMenuItem(menu, param2, item, sizeof(item));
			KvGotoFirstSubKey(kv, false);

			do {

				KvGetString(kv, "Id", Id, sizeof(Id));
				
				if (StrEqual(item, Id)) 
				{
					KvGetString(kv, "Name", Name, sizeof(Name));
					KvGetString(kv, "Model", Model, sizeof(Model));
					KvGetString(kv, "Arms", Arms, sizeof(Arms));
					
					if(!IsModelPrecached(Model))
					{
						PrecacheModel(Model);
					}
						
					if(!StrEqual(Model, "", false))
					{
						SetEntityModel(client, Model);
							
						PrintToChat(client, " \x10[PlayerSkin] \x01%T", "SelectedSkin", client, Name);
							
						if(!StrEqual(Arms, "", false))
						{
								SetEntPropString(client, Prop_Send, "m_szArmsModel", Arms);
						}
					}
				} 
				else 
				{
					KvGotoNextKey(kv, false);
				}

			} while (!StrEqual(item, Id));
		}
		case MenuAction_End: {

			CloseHandle(kv);
			CloseHandle(menu);
		}
	}
}

public Action CP_OnChatMessage(int& client, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool& processcolors, bool& removecolors)
{
	if(cv_chattag.IntValue == 1 && chattag[client])
	{
		if(prestigelevel[client] == 1)
		{
			Format(name, MAXLENGTH_NAME, "{lightgreen}[PRESTIGE 1]{default}%s", name);
			return Plugin_Changed;
	    }
	    else if(prestigelevel[client] == 2)
		{
			Format(name, MAXLENGTH_NAME, "{lime}[PRESTIGE 2]{default}%s", name);
			return Plugin_Changed;
	    }
	    else if(prestigelevel[client] == 3)
		{
			Format(name, MAXLENGTH_NAME, "{green}[PRESTIGE 3]{default}%s", name);
			return Plugin_Changed;
	    }
	    else if(prestigelevel[client] == 4)
		{
			Format(name, MAXLENGTH_NAME, "{yellow}[PRESTIGE 4]{default}%s", name);
			return Plugin_Changed;
	    }
	    else if(prestigelevel[client] == 5)
		{
			Format(name, MAXLENGTH_NAME, "{gold}[PRESTIGE 5]{default}%s", name);
			return Plugin_Changed;
	    }
    }

	return Plugin_Continue;
}


public Action SetSkinById(int client, char[] item)
{
	char Name[32], Model[128], Arms[128], Id[32];
	Handle kv = CreateKeyValues("PrestigeModels");
	FileToKeyValues(kv, g_mconfigpath);
	KvGotoFirstSubKey(kv, false);

	do {

		KvGetString(kv, "Id", Id, sizeof(Id));
				
		if (StrEqual(item, Id)) 
		{
			KvGetString(kv, "Name", Name, sizeof(Name))
			KvGetString(kv, "Model", Model, sizeof(Model));
			KvGetString(kv, "Arms", Arms, sizeof(Arms));
			int g_level = KvGetNum(kv, "Prestige", 0);
			if(prestigelevel[client] < g_level)
		 	{
		 		char g_Query[512];
		 		char steamid[512];
				GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
				FormatEx(g_Query, 512, "UPDATE prestige_playerdb SET model = 'def' WHERE steamid = '%s'", steamid);
				SQL_TQuery(g_db, T_Generic, g_Query);
		 		return Plugin_Handled;
		    }
					
			if(!IsModelPrecached(Model))
			{
				PrecacheModel(Model);
			}
						
			if(!StrEqual(Model, "", false))
			{
				SetEntityModel(client, Model);
							
				PrintToChat(client, " \x10[PlayerSkin] \x01%T", "SelectedSkin", client, Name);
							
				if(!StrEqual(Arms, "", false))
				{
						SetEntPropString(client, Prop_Send, "m_szArmsModel", Arms);
				}
			}
		} 
		else 
		{
			KvGotoNextKey(kv, false);
		}

	} while (!StrEqual(item, Id));
	
	return Plugin_Continue;
}

public void T_Generic(Handle owner, Handle results, const char[] error, any data)
{
    if(owner == null || results == null)
    {
        LogError("T_Generic returned error: %s", error);
        return;
    }
}


public bool CheckCommands(char[] cmd, char[] needlevel, int iMaxLengh)
{
	char prestige[12];
	
	KeyValues Commands = CreateKeyValues("Commands");
	
	FileToKeyValues(Commands, g_configpath);
	
	KvGetString(Commands, cmd, prestige, sizeof(prestige), "null");
	
	if (StrEqual(prestige, "null", true))
	{
		CloseHandle(Commands);
		
		return false;
	}
	
	CloseHandle(Commands);
	
	strcopy(needlevel, iMaxLengh, prestige);
	
	return true;
}

// --------------- LISTENERS --------------- //
public Action Command_Say(int client, char[] sCommand, int iArgs)
{
	bool bIsItBlocked;
	char sFirstArg[128], sCheckArg[128], needlevel[8];
	
	GetCmdArg(1, sFirstArg, sizeof(sFirstArg));
	
	strcopy(sCheckArg, sizeof(sCheckArg), sFirstArg);
	
	if (ReplaceString(sCheckArg, sizeof(sCheckArg), "!", "sm_") || ReplaceString(sCheckArg, sizeof(sCheckArg), "/", "sm_"))
	{
		bIsItBlocked = CheckCommands(sCheckArg, needlevel, sizeof(needlevel));
	} else {
		return Plugin_Continue;
	}
	
	if (bIsItBlocked)
	{
		int level = StringToInt(needlevel);
		if(prestigelevel[client] < level)
		{
			AddCommandListener(Check, sCheckArg);
			CPrintToChat(client, "%t", "YouNeedPrestige", level);
			return Plugin_Handled;
	    }
		return Plugin_Continue;
	} else {
		return Plugin_Continue;
	}
}

//Events
public Action Check(int client, const char[] sCommand, int iArgc)
{
	char needlevel[8];
	char command[200];
	Format(command, sizeof(command), "%s", sCommand);
	CheckCommands(command, needlevel, sizeof(needlevel));
	int abc = StringToInt(needlevel);
	if(prestigelevel[client] < abc)
	{
		return Plugin_Stop;
	}
	return Plugin_Continue;
}


public Action Event_Disconnect(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(client)
	{
		rank[client] = 0;
	}
}

public Action Event_AnnouncePhaseEnd(Handle event, const char[] name, bool dontBroadcast)
{
	Handle hBuffer = StartMessageAll("ServerRankRevealAll");
	if (hBuffer == INVALID_HANDLE)
	{
		PrintToServer("ServerRankRevealAll = INVALID_HANDLE");
	}
	else
	{
		EndMessage();
	}
	return Plugin_Continue;
}

//Commands

public Action Menu_MM(int client, int args)
{
		Menu menu = new Menu(Menu_Handler);
		menu.SetTitle("Prestige Menu: ");
		menu.AddItem("1", "Prestige Level");
		menu.ExitButton = true;
		menu.Display(client, 20);
}

public int Menu_Handler(Menu menu, MenuAction action, int client, int choice)
{
	if(action == MenuAction_Select)
	{
		switch(choice)
		{
			case 0: CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeLevel", prestigelevel[client]);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

public Action Cmd_prestige(int client, int args)
{
	if(rank[client] == 18)
	{
	  rank[client] = 1;
	  if(prestigelevel[client] == 1)
	  {
	  	ClientCommand(client, "sm_resetmyrank");
	  	prestigelevel[client] = 2;
	  	GivePrize(client);
	  }
	  else if(prestigelevel[client] == 2)
	  {
	  	ClientCommand(client, "sm_resetmyrank");
	  	prestigelevel[client] = 3;
	  	GivePrize(client);
	  }
	  else if(prestigelevel[client] == 3)
	  {
	  	ClientCommand(client, "sm_resetmyrank");
	  	prestigelevel[client] = 4;
	  	GivePrize(client);
	  }
	  else if(prestigelevel[client] == 4)
	  {
	  	ClientCommand(client, "sm_resetmyrank");
	  	prestigelevel[client] = 5;
	  	GivePrize(client);
	  }
	  else if(prestigelevel[client] == 5)
	  {
	  	GivePrize(client);
	  }
    }
    else 
    {
    	CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeNotGlobal");
    }
}

public Action PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if(GameRules_GetProp("m_bWarmupPeriod") == 1)
		return Plugin_Handled;

	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	CheckRanks(victim);
	CheckRanks(attacker);
 	return Plugin_Continue;
}

//Voids

public void OnClientPutInServer(int client)
{
	prestigelevel[client] = 1;
	CreateTimer(3.0, setitm, client);
	
	char gB_Query[512];
	char steamid[512];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	SQL_UnlockDatabase(g_db);
	FormatEx(gB_Query, 512, "SELECT model,tag FROM prestige_playerdb WHERE steamid='%s';", steamid);
	g_db.Query(SQL_CallBack2, gB_Query, GetClientUserId(client), DBPrio_Normal);
}

public Action setitm(Handle timerm,int client)
{
	CheckRanks(client);
}

public void SQL_CallBack2(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientOfUserId(data);
	if (!results.FetchRow())
	{
		char gB_Query[512];
		char steamid[512];
		GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
		FormatEx(gB_Query, 512, "INSERT INTO prestige_playerdb(steamid,model,tag) VALUES('%s','def','YES');", steamid);
		SQL_TQuery(g_db, T_Generic, gB_Query);
		chattag[client] = true;
		return;
	}
	else
	{
		char model[128];
		char tag[12];
		results.FetchString(0, model, sizeof(model));
		results.FetchString(1, tag, sizeof(tag));
		
		if(StrEqual(tag, "YES") && cv_chattag.IntValue == 1)
		{
			chattag[client] = true;
	    }
	    else
	    {
	    	chattag[client] = false;
	    }
		
		if(!StrEqual(model, "def"))
		{
			SetSkinById(client, model);
	    }
	}
}

public void OnMapStart()
{
	int iIndex = FindEntityByClassname(MaxClients+1, "cs_player_manager");
	if (iIndex == -1) {
		SetFailState("Unable to find cs_player_manager entity");
	}
	
	SDKHook(iIndex, SDKHook_ThinkPost, Hook_OnThinkPost);
}


public void Hook_OnThinkPost(int iEnt)
{
	static int iRankOffset = -1;
	static int iRankOffsetType = -1;
	if (iRankOffset == -1)
	{
		iRankOffset = FindSendPropInfo("CCSPlayerResource", "m_iCompetitiveRanking");
	}
	if(iRankOffsetType == -1)
	{
		iRankOffsetType = FindSendPropInfo("CCSPlayerResource", "m_iCompetitiveRankType");
	}
	
	int iRank[MAXPLAYERS+1];
	int iRankType[MAXPLAYERS + 1];
	GetEntDataArray(iEnt, iRankOffset, iRank, MaxClients+1);
	for (int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			iRank[i] = rank[i];
			iRankType[i] = rankType[i];
			SetEntDataArray(iEnt, iRankOffset, iRank, MaxClients+1);
			SetEntDataArray(iEnt, iRankOffsetType, iRankType, MAXPLAYERS+1, 1);
		}
	}
}

public void CheckRanks(int client)
{
	int points = RankMe_GetPoints(client);
  if(prestigelevel[client] == 1)
  {  
	// Silver I
	if(points >= 0 && points < 1010)
	{
		rank[client] = 1;
	}
	// Silver II
	else if(points >= 1010 && points < 1020)
	{
		rank[client] = 2;
	}
	// Silver III
	else if(points >= 1020 && points < 1030)
	{
		rank[client] = 3;
	}
	// Silver IV
	else if(points >= 1030 && points < 1040)
	{
		rank[client] = 4;
	}
	// Silver Elite
	else if(points >= 1040 && points < 1050)
	{
		rank[client] = 5;
	}
	// Silver Elite Master
	else if(points >= 1050 && points < 1060)
	{
		rank[client] = 6;
	}
	// Gold Nova I
	else if(points >= 1070 && points < 1070)
	{
		rank[client] = 7;
	}
	// Gold Nova II
	else if(points >= 1090 && points < 1080)
	{
		rank[client] = 8;
	}
	// Gold Nova III
	else if(points >= 1110 && points < 1090)
	{
		rank[client] = 9;
	}
	// Gold Nova IV
	else if(points >= 1130 && points < 1100)
	{
		rank[client] = 10;
	}
	// Master Guardian I
	else if(points >= 1170 && points < 1110)
	{
		rank[client] = 11;
	}
	// Master Guardian II
	else if(points >= 1210 && points < 1120)
	{
		rank[client] = 12;
	}
	// Master Guardian Elite
	else if(points >= 1250 && points < 1130)
	{
		rank[client] = 13;
	}
	// Distinguished Master Guardian
	else if(points >= 1290 && points < 1140)
	{
		rank[client] = 14;
	}
	// Legendary Eagle
	else if(points >= 1350 && points < 1150)
	{
		rank[client] = 15;
	}
	// Legendary Eagle Master
	else if(points >= 1410 && points < 1160)
	{
		rank[client] = 16;
	}
	// Supreme Master First Class
	else if(points >= 1470 && points < 1170)
	{
		rank[client] = 17;
	}
	// Global Elite
	else if(points >= 1180)
	{
		rank[client] = 18;
	}
	
	if(rank[client] > oldrank[client])
	{
		CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeRankUp", RankStrings[rank[client]]);
	}
	
	oldrank[client] = rank[client];
  }
  else if(prestigelevel[client] == 2)
  {  
	if(points >= 0 && points < 1020)
	{
		rank[client] = 1;
	}
	// Silver II
	else if(points >= 1020 && points < 1040)
	{
		rank[client] = 2;
	}
	// Silver III
	else if(points >= 1040 && points < 1060)
	{
		rank[client] = 3;
	}
	// Silver IV
	else if(points >= 1060 && points < 1080)
	{
		rank[client] = 4;
	}
	// Silver Elite
	else if(points >= 1080 && points < 1100)
	{
		rank[client] = 5;
	}
	// Silver Elite Master
	else if(points >= 1100 && points < 1120)
	{
		rank[client] = 6;
	}
	// Gold Nova I
	else if(points >= 1120 && points < 1140)
	{
		rank[client] = 7;
	}
	// Gold Nova II
	else if(points >= 1140 && points < 1160)
	{
		rank[client] = 8;
	}
	// Gold Nova III
	else if(points >= 1160 && points < 1180)
	{
		rank[client] = 9;
	}
	// Gold Nova IV
	else if(points >= 1180 && points < 1200)
	{
		rank[client] = 10;
	}
	// Master Guardian I
	else if(points >= 1200 && points < 1220)
	{
		rank[client] = 11;
	}
	// Master Guardian II
	else if(points >= 1220 && points < 1240)
	{
		rank[client] = 12;
	}
	// Master Guardian Elite
	else if(points >= 1240 && points < 1260)
	{
		rank[client] = 13;
	}
	// Distinguished Master Guardian
	else if(points >= 1260 && points < 1280)
	{
		rank[client] = 14;
	}
	// Legendary Eagle
	else if(points >= 1280 && points < 1300)
	{
		rank[client] = 15;
	}
	// Legendary Eagle Master
	else if(points >= 1300 && points < 1320)
	{
		rank[client] = 16;
	}
	// Supreme Master First Class
	else if(points >= 1320 && points < 1340)
	{
		rank[client] = 17;
	}
	// Global Elite
	else if(points >= 1340)
	{
		rank[client] = 18;
	}
	
	if(rank[client] > oldrank[client])
	{
		CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeRankUp", RankStrings[rank[client]]);
	}
	
	oldrank[client] = rank[client];
  }
  else if(prestigelevel[client] == 3)
  {  
	if(points >= 0 && points < 1030)
	{
		rank[client] = 1;
	}
	// Silver II
	else if(points >= 1030 && points < 1060)
	{
		rank[client] = 2;
	}
	// Silver III
	else if(points >= 1060 && points < 1090)
	{
		rank[client] = 3;
	}
	// Silver IV
	else if(points >= 1090 && points < 1120)
	{
		rank[client] = 4;
	}
	// Silver Elite
	else if(points >= 1120 && points < 1150)
	{
		rank[client] = 5;
	}
	// Silver Elite Master
	else if(points >= 1150 && points < 1180)
	{
		rank[client] = 6;
	}
	// Gold Nova I
	else if(points >= 1180 && points < 1210)
	{
		rank[client] = 7;
	}
	// Gold Nova II
	else if(points >= 1210 && points < 1240)
	{
		rank[client] = 8;
	}
	// Gold Nova III
	else if(points >= 1240 && points < 1270)
	{
		rank[client] = 9;
	}
	// Gold Nova IV
	else if(points >= 1270 && points < 1300)
	{
		rank[client] = 10;
	}
	// Master Guardian I
	else if(points >= 1300 && points < 1330)
	{
		rank[client] = 11;
	}
	// Master Guardian II
	else if(points >= 1330 && points < 1360)
	{
		rank[client] = 12;
	}
	// Master Guardian Elite
	else if(points >= 1360 && points < 1390)
	{
		rank[client] = 13;
	}
	// Distinguished Master Guardian
	else if(points >= 1390 && points < 1420)
	{
		rank[client] = 14;
	}
	// Legendary Eagle
	else if(points >= 1420 && points < 1450)
	{
		rank[client] = 15;
	}
	// Legendary Eagle Master
	else if(points >= 1450 && points < 1480)
	{
		rank[client] = 16;
	}
	// Supreme Master First Class
	else if(points >= 1480 && points < 1510)
	{
		rank[client] = 17;
	}
	// Global Elite
	else if(points >= 1510)
	{
		rank[client] = 18;
	}
	
	if(rank[client] > oldrank[client])
	{
		CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeRankUp", RankStrings[rank[client]]);
	}
	
	oldrank[client] = rank[client];
  }
  else if(prestigelevel[client] == 4)
  {  
	if(points >= 0 && points < 1040)
	{
		rank[client] = 1;
	}
	// Silver II
	else if(points >= 1040 && points < 1080)
	{
		rank[client] = 2;
	}
	// Silver III
	else if(points >= 1080 && points < 1120)
	{
		rank[client] = 3;
	}
	// Silver IV
	else if(points >= 1120 && points < 1160)
	{
		rank[client] = 4;
	}
	// Silver Elite
	else if(points >= 1160 && points < 1200)
	{
		rank[client] = 5;
	}
	// Silver Elite Master
	else if(points >= 1200 && points < 1240)
	{
		rank[client] = 6;
	}
	// Gold Nova I
	else if(points >= 1240 && points < 1280)
	{
		rank[client] = 7;
	}
	// Gold Nova II
	else if(points >= 1280 && points < 1320)
	{
		rank[client] = 8;
	}
	// Gold Nova III
	else if(points >= 1320 && points < 1360)
	{
		rank[client] = 9;
	}
	// Gold Nova IV
	else if(points >= 1360 && points < 1400)
	{
		rank[client] = 10;
	}
	// Master Guardian I
	else if(points >= 1400 && points < 1440)
	{
		rank[client] = 11;
	}
	// Master Guardian II
	else if(points >= 1440 && points < 1480)
	{
		rank[client] = 12;
	}
	// Master Guardian Elite
	else if(points >= 1480 && points < 1520)
	{
		rank[client] = 13;
	}
	// Distinguished Master Guardian
	else if(points >= 1520 && points < 1560)
	{
		rank[client] = 14;
	}
	// Legendary Eagle
	else if(points >= 1560 && points < 1600)
	{
		rank[client] = 15;
	}
	// Legendary Eagle Master
	else if(points >= 1600 && points < 1640)
	{
		rank[client] = 16;
	}
	// Supreme Master First Class
	else if(points >= 1640 && points < 1680)
	{
		rank[client] = 17;
	}
	// Global Elite
	else if(points >= 1680)
	{
		rank[client] = 18;
	}
	
	if(rank[client] > oldrank[client])
	{
		CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeRankUp", RankStrings[rank[client]]);
	}
	
	oldrank[client] = rank[client];
  }
  else if(prestigelevel[client] == 5)
  {  
	if(points >= 0 && points < 1050)
	{
		rank[client] = 1;
	}
	// Silver II
	else if(points >= 1050 && points < 1100)
	{
		rank[client] = 2;
	}
	// Silver III
	else if(points >= 1100 && points < 1150)
	{
		rank[client] = 3;
	}
	// Silver IV
	else if(points >= 1150 && points < 1200)
	{
		rank[client] = 4;
	}
	// Silver Elite
	else if(points >= 1200 && points < 1250)
	{
		rank[client] = 5;
	}
	// Silver Elite Master
	else if(points >= 1250 && points < 1300)
	{
		rank[client] = 6;
	}
	// Gold Nova I
	else if(points >= 1300 && points < 1350)
	{
		rank[client] = 7;
	}
	// Gold Nova II
	else if(points >= 1350 && points < 1400)
	{
		rank[client] = 8;
	}
	// Gold Nova III
	else if(points >= 1400 && points < 1450)
	{
		rank[client] = 9;
	}
	// Gold Nova IV
	else if(points >= 1450 && points < 1500)
	{
		rank[client] = 10;
	}
	// Master Guardian I
	else if(points >= 1500 && points < 1550)
	{
		rank[client] = 11;
	}
	// Master Guardian II
	else if(points >= 1550 && points < 1600)
	{
		rank[client] = 12;
	}
	// Master Guardian Elite
	else if(points >= 1600 && points < 1650)
	{
		rank[client] = 13;
	}
	// Distinguished Master Guardian
	else if(points >= 1650 && points < 1700)
	{
		rank[client] = 14;
	}
	// Legendary Eagle
	else if(points >= 1700 && points < 1750)
	{
		rank[client] = 15;
	}
	// Legendary Eagle Master
	else if(points >= 1750 && points < 1800)
	{
		rank[client] = 16;
	}
	// Supreme Master First Class
	else if(points >= 1800 && points < 1850)
	{
		rank[client] = 17;
	}
	// Global Elite
	else if(points >= 1850)
	{
		rank[client] = 18;
	}
	
	if(rank[client] > oldrank[client])
	{
		CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeRankUp", RankStrings[rank[client]]);
	}
	
	oldrank[client] = rank[client];
  }
}

//Database

void ConnectToDatabase()
{
	if (g_db != null)
	{
		delete g_db;
	}

	char g_Error[255];
	if (SQL_CheckConfig("ranksbyrankme"))
	{
		g_db = SQL_Connect("ranksbyrankme", true, g_Error, 255);

		if (g_db == null)
		{
			SetFailState("[Ranks] Error on start. Reason: %s", g_Error);
		}
	}
	else
	{
		SetFailState("[Ranks] Cant find `ranksbyrankme` on database.cfg");
	}
	
	char g_Query[512];
	Format(g_Query, sizeof(g_Query), "CREATE TABLE IF NOT EXISTS `prestige_playerdb` (`steamid` VARCHAR(48) NOT NULL, `model` VARCHAR(128) NOT NULL, `tag` VARCHAR(12) NOT NULL, PRIMARY KEY (`steamid`)) ");
	g_db.Query(Query_ErrorCheckCallBack, g_Query, DBPrio_Normal);
}

public void CallbackConnect(Database db, char[] error, any data)
{
	if(db == null)
		LogError("Can't connect to server. Error: %s", error);
		
	g_db = db;
}

public void Query_ErrorCheckCallBack(Database db, Handle hndl, const char[] error, any data)
{  
    if(hndl == INVALID_HANDLE) 
    { 
        SetFailState("Query failed! %s", error); 
        LogError("Did not connect to database!"); 
    } 
} 

// Some Actions

public Action GivePrize(int client)
{
    if(GetConVarInt(cv_pluginmode) == 1)
    {
    	Store_SetClientCredits(client, Store_GetClientCredits(client) + GetConVarInt(cv_creditsammount));
    	CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeLevelUpAndPrizeCredits", GetConVarInt(cv_creditsammount));
    }
    else if(GetConVarInt(cv_pluginmode) == 2)
    {
    	//Nothing Yet
    }
    return Plugin_Continue; 
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (buttons & IN_SCORE && !(GetEntProp(client, Prop_Data, "m_nOldButtons") & IN_SCORE)) {
		Handle hBuffer = StartMessageOne("ServerRankRevealAll", client);
		if (hBuffer == INVALID_HANDLE)
		{
			PrintToChat(client, "INVALID_HANDLE");
		}
		else
		{
			EndMessage();
		}
	}
	return Plugin_Continue;
}

//some stocks

stock bool IsValidClient(int client)
{
	if(client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client))
	{
		return true;
	}
	
	return false;
}


