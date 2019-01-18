#include <amxmodx>//
#include <amxmisc>
#include <reapi>

#define PLUGIN "Yet Another SpamGuard"
#define VERSION "2.0"
#define AUTHOR "AndrewZ/voed"

#define CHAT_PREFIX "YASG"

#define MAX_CS_SAYTEXT_LENGTH 192
#define MAX_LONG_MESSAGES 10
#define MAX_NAMECHANGES 2
	
new Array:g_apFreeMessages,
	Array:g_apFreeNames,
	Array:g_apRestMessages,
	Array:g_apRestNames,
	Array:g_apNames
	
new g_szUserSpamMessages[MAX_PLAYERS + 1][MAX_LONG_MESSAGES][MAX_CS_SAYTEXT_LENGTH], 
	g_szChatguardCount[MAX_PLAYERS + 1], 
	g_iNameguardChangeCount[MAX_PLAYERS + 1]

new g_pCvarImmunityFlag, g_pCvarChatguard, g_pCvarChatguardRepeat, g_pCvarChatguardRepeatLength,
	g_pCvarNameguard, g_pCvarNameguardNamespam
	
new bool:g_bNameguardMenuDisplayed[MAX_PLAYERS + 1],
	bool:g_bBlockSayText
	
new g_msg_SayText
new g_szConfigsDir[64]


public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	
	set_pcvar_string(register_cvar("yasg_version", VERSION, FCVAR_SPONLY | FCVAR_SERVER), VERSION)
	g_pCvarImmunityFlag = register_cvar("yasg_immunity_flag", "a")
	g_pCvarChatguard = register_cvar("yasg_chatguard", "2")
	g_pCvarChatguardRepeat = register_cvar("yasg_chatguard_repeat", "2")
	g_pCvarChatguardRepeatLength = register_cvar("yasg_chatguard_repeat_length", "13")
	g_pCvarNameguard = register_cvar("yasg_nameguard", "2")
	g_pCvarNameguardNamespam = register_cvar("yasg_nameguard_namespam", "1")
	
	register_concmd("yasg_chatguard_addcmd", "concmd_ChatguardAddCmd", ADMIN_RCON, "<command> - add specified command to check for restricted messages.")
	
	RegisterHookChain(RG_CSGameRules_RestartRound, "fwd_RestartRound_pre")
	RegisterHookChain(RG_CBasePlayer_SetClientUserInfoName, "fwd_SetClientUserInfoName_pre")
	
	g_msg_SayText = get_user_msgid("SayText")
	
	register_dictionary("yet_another_spamguard.txt")
}

public plugin_cfg()
{
	get_configsdir(g_szConfigsDir, charsmax(g_szConfigsDir))
	server_cmd("exec %s/yet_another_spamguard/yasg_config.cfg", g_szConfigsDir)

	g_apFreeMessages = ArrayWriteFromFile("yasg_free_messages", MAX_CS_SAYTEXT_LENGTH)
	g_apFreeNames = ArrayWriteFromFile("yasg_free_names", MAX_NAME_LENGTH)
	g_apRestMessages = ArrayWriteFromFile("yasg_restricted_messages", MAX_CS_SAYTEXT_LENGTH)
	g_apRestNames = ArrayWriteFromFile("yasg_restricted_names", MAX_NAME_LENGTH)
	//g_apNames = ArrayWriteFromFile("yasg_names", MAX_NAME_LENGTH)
}

public Array:ArrayWriteFromFile(const szFile[], const iLen)
{
	new Array:apRet = ArrayCreate(iLen, 1)

	new szTemp[MAX_CS_SAYTEXT_LENGTH]
	formatex(szTemp, charsmax(szTemp), "%s/yet_another_spamguard/%s.ini", g_szConfigsDir, szFile)
	
	new pFile = fopen(szTemp, "rt")
	
	if (pFile)
	{
		while(!feof(pFile))
		{
			fgets(pFile, szTemp, charsmax(szTemp))
			trim(szTemp)
			ArrayPushString(apRet, szTemp)
		}
	}
	
	fclose(pFile)
	
	return apRet
}


public fwd_RestartRound_pre() 
{
	if (!get_pcvar_num(g_pCvarNameguard) && !get_pcvar_num(g_pCvarNameguardNamespam))
		return HC_CONTINUE

	arrayset(g_iNameguardChangeCount, 0, MAX_PLAYERS + 1)
	
	for (new i = 1; i <= MAX_PLAYERS; i ++)
	{
		if (g_bNameguardMenuDisplayed[i])	
			fnNameguardCheck(i)
	}

	return HC_CONTINUE
}

public fwd_SetClientUserInfoName_pre(const id, szInfoBuffer[], szNewName[])
{
	if (!get_pcvar_num(g_pCvarNameguard))
		return HC_CONTINUE

	if (g_bBlockSayText)
	{
		set_msg_block(g_msg_SayText, BLOCK_ONCE)
		g_bBlockSayText = false
	}
	else
	{	
		if (!bIsUser(id))
			return HC_CONTINUE

		fnNameguardCheck(id)

		if (get_pcvar_num(g_pCvarNameguardNamespam))
		{	
			g_iNameguardChangeCount[id] ++
			
			if (g_iNameguardChangeCount[id] > MAX_NAMECHANGES)
				fnKickUser(id, "YASG_KICK_NAMEGUARD_NAMESPAM") // Обнаружен спам сменой ника.

			else 
				fnPrintColor(id, "%L", id, "YASG_NAMEGUARD_NAMESPAM_WARN", MAX_NAMECHANGES) // Предупреждение: На сервере запрещено менять ник чаще %d раз(а) за раунд.
		}
	}

	return HC_CONTINUE
}

public concmd_ChatguardAddCmd(const id, const iAccess, const pCmd)
{
	if (!cmd_access(id, iAccess, pCmd, 1))
		return PLUGIN_HANDLED
	
	new szCommand[32]
	read_args(szCommand, charsmax(szCommand))
	remove_quotes(szCommand)
	
	register_clcmd(szCommand, "fnChatguardCheck")

	return PLUGIN_CONTINUE
}

public client_putinserver(id)
{
	g_bNameguardMenuDisplayed[id] = false
	g_szChatguardCount[id] = 0
	g_iNameguardChangeCount[id] = 0
	
	if(get_pcvar_num(g_pCvarNameguard))
		fnNameguardCheck(id)
}

public fnChatguardCheck(const id)
{
	new szInput[MAX_CS_SAYTEXT_LENGTH], iLen

	read_args(szInput, charsmax(szInput))
	remove_quotes(szInput)
	iLen = strlen(szInput)
	
	if (!iLen || !bIsUser(id))
		return PLUGIN_CONTINUE
		
	new iCvarChatguard, i

	iCvarChatguard = get_pcvar_num(g_pCvarChatguard)
	
	if (iCvarChatguard)
	{
		new szTemp[MAX_CS_SAYTEXT_LENGTH], iSize
		iSize = ArraySize(g_apFreeMessages)
		
		if (iSize)
		{
			for (i = 0; i < iSize; i ++)
			{
				ArrayGetString(g_apFreeMessages, i, szTemp, charsmax(szTemp))

				if (containi(szInput, szTemp) != -1)
					return PLUGIN_CONTINUE
			}
		}
		
		for (i = 0; i < ArraySize(g_apRestMessages); i ++)
		{
			ArrayGetString(g_apRestMessages, i, szTemp, charsmax(szTemp))

			if (containi(szInput, szTemp) != -1)
			{
				if (strlen(szInput) > MAX_CS_SAYTEXT_LENGTH / 2)
					szInput[MAX_CS_SAYTEXT_LENGTH / 2] = '^0'
				
				switch (iCvarChatguard)
				{
					case 1:
					{
						fnPrintColor(id, "%L", id, "YASG_CHATGUARD_WARN") // Ваше сообщение было заблокировано, поскольку содержит недопустимые слова:
						fnPrintColor(id, "^"%s...^"", szInput) // %message%
						// add sound
					}
					case 2: fnKickUser(id, "YASG_CHATGUARD_KICK") // Обнаружены запрещенные слова в сообщении.
				}

				return PLUGIN_HANDLED
			}
		}
	}

	new iCvarChatguardRepeat = get_pcvar_num(g_pCvarChatguardRepeat) // need rework

	if (iCvarChatguardRepeat && iLen > get_pcvar_num(g_pCvarChatguardRepeatLength))
	{
		for (i = 0; i < MAX_LONG_MESSAGES; i ++)
		{
			if (equali(g_szUserSpamMessages[id][i], szInput))
			{
				if (iCvarChatguardRepeat == 2)
				{
					new iDate[3], szLog[256]
					date(iDate[0], iDate[1], iDate[2]) // y/m/d
					formatex(szLog, charsmax(szLog), "YASG_MSG_%d%02d%02d.log",  iDate[0], iDate[1], iDate[2]) 

					log_to_file(szLog, "%N | MESSAGE: %s", id, szInput)
				}
				
				return PLUGIN_HANDLED
			}
		}
		
		if (g_szChatguardCount[id] == MAX_LONG_MESSAGES - 1)
			g_szChatguardCount[id] = 0
		
		g_szChatguardCount[id] ++
		
		g_szUserSpamMessages[id][g_szChatguardCount[id]] = szInput
	}
	
	return PLUGIN_CONTINUE
}

public fnNameguardCheck(const id) // rework
{
	new iCvarNameguard = get_pcvar_num(g_pCvarNameguard)

	if (!iCvarNameguard || !bIsUser(id) || bIsNameSafe(id))
		return

	switch (get_pcvar_num(g_pCvarNameguard))
	{
		case 1: fnKickUser(id, "YASH_NAMEGUARD_KICK") // Ник содержит запрещенные слова
		case 2:
		{
			if(g_bNameguardMenuDisplayed[id])
				fnKickUser(id, "YASH_NAMEGUARD_KICK") // Ник содержит запрещенные слова
			
			else fnNameguardMenu(id)
		}
		
		case 3: fnChangeName(id)
	}
}

public fnChangeName(const id) // rework
{
	if (!bIsUser(id))
			return
	
	new szNewName[32]
	ArrayGetString(g_apNames, random_num(0, ArraySize(g_apNames)), szNewName, charsmax(szNewName))

	g_bBlockSayText = true
	set_entvar(id, var_netname, szNewName)

	fnPrintColor(id, "%L", id, "YASG_NAMEGUARD_CHANGED", szNewName) // Ваш ник изменен на ^"%s^".
}

public fnKickUser(const id, const szReasonML[])
{
	if (!is_user_connected(id))
			return
	
	server_cmd("kick #%d ^"[%s] %L^"", get_user_userid(id), CHAT_PREFIX, id, szReasonML)
}

public bool:bIsNameSafe(const id)
{	
	new szName[MAX_NAME_LENGTH], szTemp[MAX_NAME_LENGTH], i, iSize
	
	iSize = ArraySize(g_apFreeNames)
	get_entvar(id, var_netname, szName, charsmax(szName))

	if (iSize)
	{
		for (i = 0; i < iSize; i ++)
		{
			ArrayGetString(g_apFreeNames, i, szTemp, charsmax(szTemp))

			if(containi(szName, szTemp) != -1)
				return true
		}
	}

	for (i = 0; i < ArraySize(g_apRestNames); i ++)
	{
		ArrayGetString(g_apRestNames, i, szTemp, charsmax(szTemp))

		if (containi(szName, szTemp) != -1)
			return false
	}
	
	return true
}

public fnNameguardMenu(const id)
{
	static pMenu
	
	if (pMenu)
		menu_display(id, pMenu, 0)
	
	else
	{
		new szTemp[128]
		
		formatex(szTemp, charsmax(szTemp), "%L", id, "YASG_NAMEGUARD_TITLE")
		pMenu = menu_create(szTemp, "hNameguardMenu")
		
		formatex(szTemp, charsmax(szTemp), "%L", id, "YASG_NAMEGUARD_YES")
		menu_additem(pMenu, szTemp, szTemp, ADMIN_ALL)
		
		formatex(szTemp, charsmax(szTemp), "%L", id, "YASG_NAMEGUARD_NO")
		menu_additem(pMenu, szTemp, szTemp, ADMIN_ALL)
		
		formatex(szTemp, charsmax(szTemp), "%L", id, "YASG_NAMEGUARD_SELF")
		menu_additem(pMenu, szTemp, szTemp, ADMIN_ALL)
		
		menu_setprop(pMenu, MPROP_NUMBER_COLOR, "\w")
		
		menu_setprop(pMenu, MPROP_EXIT, MEXIT_NEVER)
		
		menu_display(id, pMenu, 0)
	}

	fnPrintColor(id, "%L", id, "YASH_NAMEGUARD_WARN1") // Ваш ник содержит запрещенные слова, необходимо сменить его до следующей проверки.
	g_bNameguardMenuDisplayed[id] = true
}

public hNameguardMenu(const id, const pMenu, const iItem)
{
	switch (iItem)
	{
		case 1: fnChangeName(id)
		case 2: fnKickUser(id, "YASH_NAMEGUARD_KICK") // Ник содержит запрещенные слова
		case 3: fnPrintColor(id, "%L", id, "YASH_NAMEGUARD_WARN2") // Необходимо сменить ник до следующей проверки.
	}
	
	return PLUGIN_HANDLED
}

public bool:bIsUser(const id)
{
	if (is_user_bot(id) || is_user_hltv(id) || !is_user_connected(id)) 
		return false
	
	new szFlags[24]
	get_pcvar_string(g_pCvarImmunityFlag, szFlags, charsmax(szFlags))
	
	if (get_user_flags(id) & read_flags(szFlags))
		return false
	
	return true
}

stock fnPrintColor(const id, const szInput[], any:...)
{
	new szMessage[MAX_CS_SAYTEXT_LENGTH]
   
	vformat(szMessage, charsmax(szMessage), szInput, 3)
	format(szMessage, charsmax(szMessage), "^1[^4%s^1] %s", CHAT_PREFIX, szMessage)

	replace_all(szMessage, charsmax(szMessage), "!g", "^4") // Green Color
	replace_all(szMessage, charsmax(szMessage), "!n", "^1") // Default Color
	replace_all(szMessage, charsmax(szMessage), "!t", "^3") // Team Color
  
	client_print_color(id, print_team_default, szMessage)
}