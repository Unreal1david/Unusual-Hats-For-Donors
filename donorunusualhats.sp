#include <sourcemod>
#include <colors>
#include <tf2items>
#include <tf2_stocks>


public Plugin:myinfo = {
	name = "Unusual Hats",
	author = "Unreal1",
	description = "",
	version = "1.0",
	url = ""
};

new Handle:g_hDatabase = INVALID_HANDLE;

new Handle:g_hAvailableParticles = INVALID_HANDLE;
new Handle:g_hAvailableHats = INVALID_HANDLE;
new Handle:g_hClientsHatsParticles[MAXPLAYERS] = INVALID_HANDLE;
new Handle:g_hClientsCurrentlyEquippedHats[MAXPLAYERS] = INVALID_HANDLE;
new Float:g_fLastClientInventoryApplication[MAXPLAYERS] = 0.0;

public OnPluginStart() {
	RegAdminCmd("sm_unusualhats", OnCmdUnusual, ADMFLAG_CUSTOM4);
	
	g_hAvailableParticles = CreateArray();
	g_hAvailableHats = CreateArray();
	for(new i = 0; i < MAXPLAYERS; i++)
		g_hClientsHatsParticles[i] = CreateArray();
	for(new i = 0; i < MAXPLAYERS; i++)
		g_hClientsCurrentlyEquippedHats[i] = CreateArray();
	
	AutoExecConfig();
}

public OnMapStart() {
	if(g_hDatabase != INVALID_HANDLE)
		LoadDataFromDatabase();
}

public OnConfigsExecuted() {
	InitDatabase();
}

public OnClientPutInServer(client) {
	ClearClientSlot(client);

	new String:sQuery[255], String:sSteamID[32];
	GetClientAuthString(client, sSteamID, sizeof(sSteamID));
	Format(sQuery, sizeof(sQuery), "SELECT `hat`, `particle` FROM `unusualhats` WHERE `steamid` = '%s';", sSteamID);
	SQL_TQuery(g_hDatabase, OnDatabasePlayer, sQuery, client);
}

public ClearClientSlot(client) {
	if(g_hClientsCurrentlyEquippedHats[client] != INVALID_HANDLE) {
		// for(new i = 0; i < GetArraySize(g_hClientsCurrentlyEquippedHats[client]); i++)
		// 	CloseHandle(GetArrayCell(g_hClientsCurrentlyEquippedHats[client], i));
		ClearArray(g_hClientsCurrentlyEquippedHats[client]);
	}

	if(g_hClientsHatsParticles[client] != INVALID_HANDLE) {
		// for(new i = 0; i < GetArraySize(g_hClientsHatsParticles[client]); i++)
		// 	CloseHandle(GetArrayCell(g_hClientsHatsParticles[client], i));
		ClearArray(g_hClientsHatsParticles[client]);
	}
}

stock ClearDataArrays() {
	for(new i = 0; i < GetArraySize(g_hAvailableParticles); i++) {
		CloseHandle(GetArrayCell(g_hAvailableParticles, i));
	}
	ClearArray(g_hAvailableParticles);
	
	for(new i = 0; i < GetArraySize(g_hAvailableHats); i++) {
		CloseHandle(GetArrayCell(g_hAvailableHats, i));
	}
	ClearArray(g_hAvailableHats);
}

public LoadDataFromDatabase() {
	new String:sQuery[255];
	Format(sQuery, sizeof(sQuery), "SELECT `id`, `name`, `type` FROM `unusualhats_itemlist` ORDER BY `type` ASC, `id` ASC;");
	SQL_TQuery(g_hDatabase, OnLoadDataFromDatabaseDB, sQuery);
}

public OnLoadDataFromDatabaseDB(Handle:owner, Handle:hndl, const String:error[], any:data) {
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
		//aa, something very wrong happened
		return;
	if(SQL_GetRowCount(hndl) > 0) {
		ClearDataArrays();
		new iHats = 0, iParticles = 0;
		while(SQL_FetchRow(hndl)) {
			new iItemID, String:sItemName[255], String:sItemType[255];
			iItemID = SQL_FetchInt(hndl, 0);
			SQL_FetchString(hndl, 1, sItemName, sizeof(sItemName));
			SQL_FetchString(hndl, 2, sItemType, sizeof(sItemType));

			new Handle:hPack = CreateDataPack();
			WritePackCell(hPack, iItemID);
			WritePackString(hPack, sItemName);
			ResetPack(hPack);

			if(strcmp(sItemType, "hat") == 0) {
				PushArrayCell(g_hAvailableHats, hPack);
				iHats++
			}
			else if(strcmp(sItemType, "particle") == 0) {
				PushArrayCell(g_hAvailableParticles, hPack);
				iParticles++;
			}
		}
		PrintToServer("[UH] Successfully loaded %d particles and %d hats", iParticles, iHats);
	}
}

public InitDatabase() {
	if(g_hDatabase != INVALID_HANDLE) {
		LoadDataFromDatabase();
		return;
	}
	SQL_TConnect(OnDatabaseConnect, "default");
}

public OnDatabaseConnect(Handle:owner, Handle:hndl, const String:error[], any:data){
	if(hndl == INVALID_HANDLE)
		SetFailState("[UNUSUALHATS] Unable to connect to the database with error %s", error);
	else {
		g_hDatabase = hndl;
		new String:sQuery[255];
		Format(sQuery, sizeof(sQuery), "CREATE TABLE IF NOT EXISTS `unusualhats` (`steamid` VARCHAR(32) NOT NULL, `hat` INT NOT NULL, `particle` INT NOT NULL, PRIMARY KEY (`steamid`, `hat`));");
		SQL_TQuery(g_hDatabase, OnDatabaseConnectReply, sQuery);
		LoadDataFromDatabase();
	}
}

public OnDatabaseConnectReply(Handle:database, Handle:hndl, String:error[], any:client) {
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
		//aa, something very wrong happened
		return;
	else {
		new String:sQuery[255], String:steamID[32];
		for (new i = 1; i <= MaxClients; i++)
			if (IsClientConnected(i) && !IsFakeClient(i)) {
				GetClientAuthString(i, steamID, sizeof(steamID));
				Format(sQuery, sizeof(sQuery), "SELECT `hat`, `particle` FROM `unusualhats` WHERE `steamid` = '%s';", steamID);
				SQL_TQuery(g_hDatabase, OnDatabasePlayer, sQuery, i);
			}
	}
}

public OnDatabasePlayer(Handle:database, Handle:hndl, String:error[], any:client) {
	if(hndl == INVALID_HANDLE || strlen(error) > 0)
		//aa, something very wrong happened
		return;
	else {
		if(SQL_GetRowCount(hndl) > 0)
			while(SQL_FetchRow(hndl)) {
				new iHatId, iParticleId;
				iHatId = SQL_FetchInt(hndl, 0);
				iParticleId = SQL_FetchInt(hndl, 1);

				if(FindHatInArray(g_hAvailableHats, iHatId) == -1)
					continue;
				if(FindHatInArray(g_hAvailableParticles, iParticleId) == -1)
					continue;

				new Handle:hPack = CreateDataPack();
				WritePackCell(hPack, iHatId);
				WritePackCell(hPack, iParticleId);
				ResetPack(hPack);
				PushArrayCell(g_hClientsHatsParticles[client], hPack);
			}
	}
}

public Action:OnCmdUnusual(client, args) {
	if(GetArraySize(g_hAvailableParticles) == 0 || GetArraySize(g_hAvailableHats) == 0) {
		ReplyToCommand(client, "There are no available particles, sorry");
		return Plugin_Handled;
	}
	
	new Handle:hMenu = CreateMenu(OnCmdUnusualMenu);
	SetMenuExitButton(hMenu, true);
	SetMenuExitBackButton(hMenu, bool:true);
	SetMenuTitle(hMenu, "Select a hat you want attach an unusual to \n---------------------");
	new iItemsCount = 0;
	for(new i = 0; i < GetArraySize(g_hClientsCurrentlyEquippedHats[client]); i++) {
		new iIndex = FindHatInArray(g_hAvailableHats, GetArrayCell(g_hClientsCurrentlyEquippedHats[client], i));
		if(iIndex != -1) {
			new String:sItem[255], String:sHatName[255], Handle:hPack;
			hPack = GetArrayCell(g_hAvailableHats, iIndex);
			ReadPackCell(hPack);
			ReadPackString(hPack, sHatName, sizeof(sHatName));
			ResetPack(hPack);
			Format(sItem, sizeof(sItem), "%d", iIndex);
			AddMenuItem(hMenu, sItem, sHatName);
			iItemsCount++;
		}
	}
	if(iItemsCount > 0)
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	else {
		CPrintToChat(client, "{green}There are not available particles for your hat, sorry");
		CloseHandle(hMenu);
	}
	
	return Plugin_Handled;
}

public OnCmdUnusualMenu(Handle:menu, MenuAction:action, client, item) {
	
	if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
	FakeClientCommand(client, "sm_donor");
	
	if(action == MenuAction_Select) {
		new String:sItem[255], iIndex;
		GetMenuItem(menu, item, sItem, sizeof(sItem));
		iIndex = StringToInt(sItem);

		new Handle:hPack = GetArrayCell(g_hAvailableHats, iIndex);
		ReadPackCell(hPack);
		new String:sHatName[255];
		ReadPackString(hPack, sHatName, sizeof(sHatName));
		ResetPack(hPack);

		new Handle:hMenu = CreateMenu(OnCmdUnusualMenuParticleMenu);
		SetMenuExitButton(hMenu, true);
		SetMenuExitBackButton(hMenu, bool:true);
		SetMenuTitle(hMenu, "Select an unusual to attach to %s \n---------------------", sHatName);
		Format(sItem, sizeof(sItem), "%d|-1", iIndex);
		AddMenuItem(hMenu, sItem, "Disable");
		for(new i = 0; i < GetArraySize(g_hAvailableParticles); i++) {
			hPack = GetArrayCell(g_hAvailableParticles, i);
			new String:sParticleName[255];
			ReadPackCell(hPack);
			ReadPackString(hPack, sParticleName, sizeof(sParticleName));
			ResetPack(hPack);
			Format(sItem, sizeof(sItem), "%d|%d", iIndex, i);
			AddMenuItem(hMenu, sItem, sParticleName);
		}
		DisplayMenu(hMenu, client, MENU_TIME_FOREVER);
	}
	else if(action == MenuAction_End)
		CloseHandle(menu);
}

public OnCmdUnusualMenuParticleMenu(Handle:menu, MenuAction:action, client, item) {
	
	if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
	FakeClientCommand(client, "sm_unusualhats");
	
	if(action == MenuAction_Select) {
		new String:sItem[255];
		GetMenuItem(menu, item, sItem, sizeof(sItem));
		new String:sHatId[255], String:sParticleId[255];
		new iSplitIndex = SplitString(sItem, "|", sHatId, sizeof(sHatId));
		strcopy(sParticleId, sizeof(sParticleId), sItem[iSplitIndex]);
		new iHatId = StringToInt(sHatId), iParticleId = StringToInt(sParticleId);

		new Handle:hPack = GetArrayCell(g_hAvailableHats, iHatId);
		new iHatIndex = ReadPackCell(hPack);
		ResetPack(hPack);

		new iHatArrayIndex = FindHatInArray(g_hClientsHatsParticles[client], iHatIndex);
		if(iParticleId != -1) {
			hPack = GetArrayCell(g_hAvailableParticles, iParticleId);
			new iParticleIndex = ReadPackCell(hPack);
			ResetPack(hPack);
			hPack = CreateDataPack();
			WritePackCell(hPack, iHatIndex);
			WritePackCell(hPack, iParticleIndex);
			ResetPack(hPack);
			if(iHatArrayIndex != -1) 
				SetArrayCell(g_hClientsHatsParticles[client], iHatArrayIndex, hPack);
			else
				PushArrayCell(g_hClientsHatsParticles[client], hPack);
			SaveClientHatParticle(client, iHatIndex, iParticleIndex);
		} else if(iHatArrayIndex != -1) {
			RemoveFromArray(g_hClientsHatsParticles[client], iHatArrayIndex);
			SaveClientHatParticle(client, iHatIndex, -1);
		}

		CPrintToChat(client, "{green}Please switch your class to a different one and go back to the current one");
		FakeClientCommand(client, "sm_unusualhats");
	}
	else if(action == MenuAction_End)
		CloseHandle(menu);
}

public SaveClientHatParticle(client, hat, particle) {
	new String:sSteamID[32], String:sQuery[255];
	GetClientAuthString(client, sSteamID, sizeof(sSteamID));
	if(particle != -1)
		Format(sQuery, sizeof(sQuery), "REPLACE INTO `unusualhats` (`steamid`, `hat`, `particle`) VALUES ('%s', '%d', '%d');", sSteamID, hat, particle);
	else
		Format(sQuery, sizeof(sQuery), "DELETE FROM `unusualhats` WHERE `steamid` = '%s' AND `hat` = '%d';", sSteamID, hat);
	SQL_TQuery(g_hDatabase, NullDBCallback, sQuery, client);
}

public NullDBCallback(Handle:database, Handle:hndl, String:error[], any:client) {
	return;
}

stock FindHatInArray(Handle:hArray, iDefIndex) {
	for(new i = 0; i < GetArraySize(hArray); i++) {
		new Handle:hPack = GetArrayCell(hArray, i);
		new iID = ReadPackCell(hPack);
		ResetPack(hPack);
		if(iID == iDefIndex)
			return i;
	}
	return -1;
}

stock AddHatToClientsList(client, iDefIndex) {
	new i = FindValueInArray(g_hClientsCurrentlyEquippedHats[client], iDefIndex);
	if(i != -1)
		return;
	PushArrayCell(g_hClientsCurrentlyEquippedHats[client], iDefIndex);
}

stock ClearClientsHatsList(client) {
	ClearArray(g_hClientsCurrentlyEquippedHats[client]);
}

public Action:TF2Items_OnGiveNamedItem(client, String:classname[], iItemDefinitionIndex, &Handle:hItem) {
	if(strcmp(classname, "tf_wearable") == 0) {
		if(GetGameTime() - g_fLastClientInventoryApplication[client] > 0.1)
			ClearClientsHatsList(client);
		g_fLastClientInventoryApplication[client] = GetGameTime();
		AddHatToClientsList(client, iItemDefinitionIndex);
		new iHatIndex = FindHatInArray(g_hClientsHatsParticles[client], iItemDefinitionIndex);
		if(iHatIndex != -1) {
			if(hItem == INVALID_HANDLE)
				hItem = TF2Items_CreateItem(OVERRIDE_ATTRIBUTES | PRESERVE_ATTRIBUTES);
			else
				TF2Items_SetFlags(hItem, TF2Items_GetFlags(hItem) | OVERRIDE_ATTRIBUTES | PRESERVE_ATTRIBUTES);
			new iNumAttrs = TF2Items_GetNumAttributes(hItem);

			new Handle:hPack = GetArrayCell(g_hClientsHatsParticles[client], iHatIndex);
			ReadPackCell(hPack);
			new iParticleIndex = ReadPackCell(hPack);
			ResetPack(hPack);

			new iParticleAttrIndex = -1;
			for(new i = 0; i < iNumAttrs; i++)
				if(TF2Items_GetAttributeId(hItem, i) == 134) {
					iParticleAttrIndex = i;
					break;
				}
			if(iParticleAttrIndex == -1) {
				iParticleAttrIndex = iNumAttrs;
				TF2Items_SetNumAttributes(hItem, iNumAttrs + 1);
			}
			TF2Items_SetAttribute(hItem, iParticleAttrIndex, 134, float(iParticleIndex));
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}