#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <kento_rankme/rankme>
#include <store>
#include <multicolors>

#pragma tabsize 0
#pragma newdecls required

#define PLUGIN_AUTHOR "DiogoOnAir"
#define PLUGIN_VERSION "1.1"

Handle cookie_mm_type = INVALID_HANDLE;

ConVar cv_vipflags;
ConVar cv_creditsammount;
ConVar cv_pluginmode;

bool firstconnect[MAXPLAYERS +1] = true;

int prestigelevel[MAXPLAYERS + 1];
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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Store_GetClientCredits");
	MarkNativeAsOptional("Store_SetClientCredits");
}

public Plugin myinfo = 
{
	name = "Ranks for rankme | Prestige",
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
	
	//Events
	HookEvent("announce_phase_end", Event_AnnouncePhaseEnd);
	HookEvent("player_disconnect", Event_Disconnect, EventHookMode_Pre);
	HookEvent("player_spawn", Event_PlayerSpawn)
	
	RegClientCookie("cookie_mm_type", "Matchmaking Icon Type", CookieAccess_Public);
	
	//Convars
	cv_vipflags = CreateConVar("sm_ranksbyrankme_flags", "1", "1 - ADMIN FLAG RESERVATION / 2 - ADMIN FLAGG CUSTOM1 / 3 ADMIN FLAG RESRVATION AND CUSTOM1");
	cv_creditsammount = CreateConVar("sm_ranksbyrankme_credits", "1000", "Amount Of Credits To Give");
	cv_pluginmode = CreateConVar("sm_ranksbyrankme_mode", "1", "1 to give credits / 2 to give vip");
	
	//Database
	ConnectToDatabase();
	char Query[255];
	g_db.Format(Query, sizeof(Query), "CREATE TABLE IF NOT EXISTS `viptimer` (`steamid` VARCHAR(48) NOT NULL, `date` VARCHAR(15), `expirationdate` VARCHAR(15))");
	g_db.Query(Query_ErrorCheckCallBack, Query);
	
	//Translations
	LoadTranslations("ranksforrankme_phrases.txt");  
	
	//Ranks Function
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			CheckRanks(i);
		}
	}
	
}

//Events

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
  int client = GetClientOfUserId(GetEventInt(event, "userid")); 
  UpdateDayDatabase(client);
  CheckPlayerVip(client);
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

//Voids

public void OnClientPutInServer(int client)
{
	if(firstconnect[client] == true)
	{
		firstconnect[client] =  false;
		prestigelevel[client] = 1;
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

public void OnClientPostAdminCheck(int client)
{
	if(IsValidClient(client))
	{
		if(AreClientCookiesCached(client))
		{
			char cookie_buffer[52];
			GetClientCookie(client, cookie_mm_type, cookie_buffer, sizeof(cookie_buffer));	
			rankType[client] = StringToInt(cookie_buffer);
		}
		else
		{
			SetClientCookie(client, cookie_mm_type, "0");
		}
		CheckRanks(client);
	}
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
			CheckRanks(i);
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
	if(SQL_CheckConfig("ranksbyrankme"))
		Database.Connect(CallbackConnect, "ranksbyrankme");
	else
		Database.Connect(CallbackConnect, "default");
}

public void CallbackConnect(Database db, char[] error, any data)
{
	if(db == null)
		LogError("Can't connect to server. Error: %s", error);
		
	g_db = db;
}

public void Query_CallBack(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
			LogError("Query failed! %s", error);
    }
	if(results.RowCount == 1)
	{
		char date[512];
		char expirationdate[512];
		int dateint,expirationdateint,dateintequal;
			
		while(results.FetchRow())
		{
			results.FetchString(0, date, sizeof(date));
			results.FetchString(1, expirationdate, sizeof(expirationdate));
				
			dateint = StringToInt(date);
			expirationdateint = StringToInt(expirationdate);
			dateintequal = ((expirationdateint - dateint)/60/60/24);
				
            if (dateintequal <= 0)
			{
				    char Query[255];
				    char steamid[32];
				    int client = GetClientOfUserId(data);
				    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
				    
				    if(GetConVarInt(cv_vipflags) == 1)
                    {
                    	RemoveUserFlags(client, Admin_Reservation);
                    }
                    else if(GetConVarInt(cv_vipflags) == 2)
                    {
                    	RemoveUserFlags(client, Admin_Custom1);
                    }   
                    else if(GetConVarInt(cv_vipflags) == 3)
                    {
                    	RemoveUserFlags(client, Admin_Custom1);
                    	RemoveUserFlags(client, Admin_Reservation);
                    }                      
					g_db.Format(Query, sizeof(Query), "UPDATE `viptimer` SET date = ' ', expirationdate = '' WHERE steamid = '%s';", steamid);
					g_db.Query(Query_ErrorCheckCallBack, Query);
			}
		}
	}
	else
	{
		LogError("RanksForRankme - No results ound or more than 1 row!"); 
	}
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
    	int day, month, year, endday, endmonth, endyear;
    	int dayinmonth[13] = {0, 31, 28, 30, 31, 30, 31, 30, 31, 30, 31, 30, 31};
    	char Query[255];
    	char steamid[32];
	    char sday[10]; 
	    char smonth[10]; 
	    char syear[10]; 
	    
	    GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	    
	    FormatTime(sday, sizeof(sday), "%d"); // Obtain day 
	    FormatTime(smonth, sizeof(smonth), "%m"); // Obtain month 
	    FormatTime(syear, sizeof(syear), "%Y"); // Obtain year 
	
	    day = StringToInt(sday); 
	    month = StringToInt(smonth); 
	    year = StringToInt(syear); 
	
	    endday = day + 1;
	    endmonth = month;
	    endyear = year;
	    
	    if (endday > dayinmonth[month]) 
		{
			endday = endday - dayinmonth[month];
			endmonth = endmonth + 1;
		}
		
		if (endmonth == 13) 
		{
			endyear = endyear + 1;
			endmonth = 1;
		}
		
	   	if(prestigelevel[client] == 1)
	   	{
	   	  	g_db.Format(Query, sizeof(Query), "INSERT INTO viptimer (steamid, expirationdate) VALUES ('%s', '%i-%i-%i')", endyear, endmonth, endday, steamid);
			g_db.Query(Query_ErrorCheckCallBack, Query);
	   	}
	   	else if(prestigelevel[client] > 1)
	   	{
	   		g_db.Format(Query, sizeof(Query), "UPDATE `viptimer` SET date = ' ', expirationdate = '%i-%i-%i' WHERE steamid = '%s'", endyear, endmonth, endday, steamid);
			g_db.Query(Query_ErrorCheckCallBack, Query);
	    }
		
    	CPrintToChat(client, "{yellow}[Prestige] {default}%T", "PrestigeLevelUpAndPrizeVip");
    	if(GetConVarInt(cv_vipflags) == 1)
        {
    	   AddUserFlags(client, Admin_Reservation);
        }
        if(GetConVarInt(cv_vipflags) == 2)
        {
    	   AddUserFlags(client, Admin_Custom1);
        }
        if(GetConVarInt(cv_vipflags) == 3)
        {
           AddUserFlags(client, Admin_Reservation);
    	   AddUserFlags(client, Admin_Custom1);
        }
    }
    return false; 
}

public Action UpdateDayDatabase(int client)
{
	int day, month, year
	char sday[10]; 
	char smonth[10]; 
	char syear[10]; 
	
	FormatTime(sday, sizeof(sday), "%d"); // Obtain day 
	FormatTime(smonth, sizeof(smonth), "%m"); // Obtain month 
	FormatTime(syear, sizeof(syear), "%Y"); // Obtain year 
	
	day = StringToInt(sday); 
	month = StringToInt(smonth); 
	year = StringToInt(syear); 
	
	char Query[255];
	char steamid[32];
	
	if (GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid)))
	{
		
		g_db.Format(Query, sizeof(Query), "UPDATE `autovip` SET date = '%i-%i-%i' WHERE steamid = '%s'", year, month, day, steamid);
		g_db.Query(Query_ErrorCheckCallBack, Query);
	}
	
}

public Action CheckPlayerVip(int client)
{
	char Query[255];
	char steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	
	g_db.Format(Query, sizeof(Query), "SELECT UNIX_TIMESTAMP(`date`), UNIX_TIMESTAMP(`expirationdate`) FROM `viptimer` WHERE steamid = '%s'", steamid);	
	g_db.Query(Query_CallBack, Query, GetClientUserId(client));
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


