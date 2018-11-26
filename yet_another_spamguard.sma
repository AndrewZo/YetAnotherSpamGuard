#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <regex>
#include <reapi>

#define PLUGIN "Yet Another SpamGuard"
#define VERSION "2.0"
#define AUTHOR "AndrewZ/voed"

#define MSGS_PREFIX "YASG"

#define MAX_LONGMESSAGES 10
#define MAX_NAMECHANGES 2
	
new Array:g_szWlMessages,
	Array:g_szWlNames,
	Array:g_szRestMessages,
	Array:g_szRestNames

new bool:g_bChatguardKeyUsed[ MAX_PLAYERS + 1 ],
	bool:g_bNameguardKeyUsed[ MAX_PLAYERS + 1 ]
	
new g_szUserSpamMessages[ MAX_PLAYERS + 1 ][ MAX_LONGMESSAGES ][ 192 ], 
	g_szUserLongmessagesCount[ MAX_PLAYERS + 1 ], 
	g_szUserNameguardMenuDisplayed[ MAX_PLAYERS + 1 ],
	g_szUserNameguardNameChanges[ MAX_PLAYERS + 1 ]

new g_pcvr_ImmunityFlag,
	g_pcvr_ChatguardMode, g_pcvr_ChatguardRepeatMode, g_pcvr_ChatguardRepeatLen,
	g_pcvr_NameguardMode, g_pcvr_NameguardName, g_pcvr_NameguardNamespam
	
new g_msg_SayText

new bool:g_bSetClientKeyValueBlock

new g_szConfigsDir[ 64 ]

public plugin_init()
{
	register_plugin( PLUGIN, VERSION, AUTHOR )
	
	set_pcvar_string( register_cvar( "yasg_version", VERSION, FCVAR_SPONLY | FCVAR_SERVER ), VERSION )

	g_pcvr_ImmunityFlag = register_cvar( "yasg_immunity_flag", "a" )
	g_pcvr_ChatguardMode = register_cvar( "yasg_chatguard_mode", "2" )
	g_pcvr_ChatguardRepeatMode = register_cvar( "yasg_chatguard_repeat_mode", "2" )
	g_pcvr_ChatguardRepeatLen = register_cvar( "yasg_chatguard_repeat_len", "13" )
	g_pcvr_NameguardMode = register_cvar( "yasg_nameguard_mode", "2" )
	g_pcvr_NameguardName = register_cvar( "yasg_nameguard_name", "[YASG] Player" )
	g_pcvr_NameguardNamespam = register_cvar( "yasg_nameguard_namespam", "1" )

	g_szWlMessages = ArrayCreate( 192, 1 ),
	g_szWlNames = ArrayCreate( 32, 1 ),
	g_szRestMessages = ArrayCreate( 192, 1 ),
	g_szRestNames = ArrayCreate( 32, 1 )
	
	register_logevent( "logevent_round_start", 2, "1=Round_Start" )
	
	register_forward( FM_SetClientKeyValue, "fwd_setclientkeyvalue" )
	
	register_clcmd( "say", "hook_say" )
	register_clcmd( "say_team", "hook_say" )
	
	g_msg_SayText = get_user_msgid( "SayText" )
	
	register_dictionary( "yet_another_spamguard.txt" )
}

public plugin_cfg()
{
	get_configsdir( g_szConfigsDir, charsmax( g_szConfigsDir ) )
	server_cmd( "exec %s/yet_another_spamguard/yasg_config.cfg", g_szConfigsDir )

	write_file_to_array( g_szWlMessages, "yasg_whitelist_messages" )
	write_file_to_array( g_szWlNames, "yasg_whitelist_names" )
	write_file_to_array( g_szRestMessages, "yasg_restricted_messages" )
	write_file_to_array( g_szRestNames, "yasg_restricted_names" )
}

public write_file_to_array( Array:Array, const szFile[] )
{
	new szTemp[ 192 ]
	formatex( szTemp, charsmax( szTemp ), "%s/yet_another_spamguard/%s.ini", g_szConfigsDir, szFile )
	
	new iFile = fopen( szTemp, "rt" )
	
	if( iFile )
	{
		while( !feof( iFile ) )
		{
			fgets( iFile, szTemp, charsmax( szTemp ) )
			trim( szTemp )
			ArrayPushString( Array, szTemp )
		}
	}
}



public logevent_round_start()
{
	server_print( "================================" )
	for( new i; i < ArraySize( g_szRestMessages ); i ++ )
	{
		new szTemp[ 64 ];ArrayGetString( g_szRestMessages, i, szTemp, charsmax( szTemp ) )
		
		server_print( szTemp )
		
	}
	server_print( "================================" )

	if( !get_pcvar_num( g_pcvr_NameguardMode ) && !get_pcvar_num( g_pcvr_NameguardNamespam ) )
		return

	arrayset( g_szUserNameguardNameChanges, 0, MAX_PLAYERS )
	
	for( new i = 1; i <= MAX_PLAYERS; i ++ )
	{
		g_szUserNameguardNameChanges[ i ] = 0
		
		if( !g_szUserNameguardMenuDisplayed[ i ] )
			continue
			
		if( task_exists( i ) )
			remove_task( i )
			
		set_task( 1.0, "nameguard_check", i )
	}
}

public fwd_setclientkeyvalue( id, const sInfobuffer[], const sKey[], const sValue[] )
{
	if( g_bSetClientKeyValueBlock )
	{
		g_bSetClientKeyValueBlock = false
		return FMRES_IGNORED
	}
		
	if( !is_user_connected( id ) )
		return FMRES_IGNORED
		
	if( !equal( sKey, "name" ) )
		return FMRES_IGNORED
	
	if( get_pcvar_num( g_pcvr_NameguardMode ) )
	{
		if( task_exists( id ) )
			remove_task( id )
			
		set_task( 1.0, "nameguard_check", id )
	}
		
	if( get_pcvar_num( g_pcvr_NameguardNamespam ) && is_user_user( id ) )
	{	
		g_szUserNameguardNameChanges[ id ] ++
		
		if( g_szUserNameguardNameChanges[ id ] > MAX_NAMECHANGES )
			kick_user( id, "YASG_KICK_NAMEGUARD_NAMESPAM" ) // Кикнут за спам сменой ника.
	}
	
	return FMRES_IGNORED
}

public client_putinserver( id )
{
	g_bNameguardKeyUsed[ id ] = false
	g_bChatguardKeyUsed[ id ] = false
	g_szUserLongmessagesCount[ id ] = 0
	g_szUserNameguardMenuDisplayed[ id ] = 0
	g_szUserNameguardNameChanges[ id ] = 0
	
	if( get_pcvar_num( g_pcvr_NameguardMode ) )
	{
		if( task_exists( id ) )
			remove_task( id )
			
		set_task( 3.0, "nameguard_check", id )
	}
}

public hook_say( id )
{
	new i_pCvrCGMode = get_pcvar_num( g_pcvr_ChatguardMode )
	new i_pCvrCGRepeatMode = get_pcvar_num( g_pcvr_ChatguardRepeatMode )
	
	if( ( i_pCvrCGMode || i_pCvrCGRepeatMode ) && is_user_user( id ) )
	{
		new szInput[ 192 ]
		read_args( szInput, charsmax( szInput ) )
		remove_quotes( szInput )

		if( i_pCvrCGMode )
		{
			new i, szTemp[ 192 ]
			
			for( i = 0; i < ArraySize( g_szRestMessages ); i ++ )
			{
				ArrayGetString( g_szRestMessages, i, szTemp, charsmax( szTemp ) )

				if( containi( szInput, szTemp ) != -1 )
				{
					for( i = 0; i < ArraySize( g_szWlMessages ); i ++ )
					{
						ArrayGetString( g_szWlMessages, i, szTemp, charsmax( szTemp ) )

						if( containi( szInput, szTemp ) != -1 )
							return PLUGIN_CONTINUE
					}
				}
					
				switch( i_pCvrCGMode )
				{
					case 1:
					{
						yasg_print_color( id, "%L", id, "YASG_CHATGUARD_WARN" ) // Ваше сообщение было заблокировано, поскольку содержит недопустимые слова:
						yasg_print_color( id, "^"%s^"", szInput[ 64 ] ) // %message%
					}
					case 2:  kick_user( id, "YASG_CHATGUARD_KICK" )
				}

				return PLUGIN_HANDLED
			}
		}

		if( i_pCvrCGRepeatMode && strlen( szInput ) > get_pcvar_num( g_pcvr_ChatguardRepeatLen ) )
		{
			for( new i = 0; i < MAX_LONGMESSAGES; i ++ )
			{
				if( equali( g_szUserSpamMessages[ id ][ i ], szInput ) )
				{
					if( i_pCvrCGRepeatMode == 2 )
					{
						new y, m, d, szTemp[ 32 ]
						date( y, m, d )
						formatex( szTemp, charsmax( szTemp ), "YASG_MSG_%d%02d%02d.log", y, m, d ) 

						log_to_file( szTemp, "%N | MESSAGE: %s", id, szInput )
					}
					
					return PLUGIN_HANDLED
				}
			}
			
			if( g_szUserLongmessagesCount[ id ] == MAX_LONGMESSAGES - 1 )
				g_szUserLongmessagesCount[ id ] = 0
			
			g_szUserLongmessagesCount[ id ] ++
			
			g_szUserSpamMessages[ id ][ g_szUserLongmessagesCount[ id ] ] = szInput
		}
	}
	
	return PLUGIN_CONTINUE
}

public show_nameguard_menu( id, szName[] )
{
	new szMenu[ 512 ], iLen, iKeys
	
	iKeys = MENU_KEY_1 + MENU_KEY_2
	
	iLen = formatex( szMenu, charsmax( szMenu ), "\y%s v%s", PLUGIN, VERSION )
	
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n^n\y(\d^"%s^"\y)", szName )
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n\y%L", id, "YASG_NAMEGUARD_DETECTED" ) // Ваш ник содержит запрещенные слова.
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n^n^n%L", id, "YASG_NAMEGUARD_DETECTED2" ) // Сменить ник?

	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n^n\w1. %L", id, "YASG_NAMEGUARD_YES" ) // Да
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n2. %L", id, "YASG_NAMEGUARD_NO" ) // Нет, покинуть сервер
	
	if( !g_bNameguardKeyUsed[ id ] )
	{
		iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n3. %L", id, "YASG_NAMEGUARD_KEY" ) // Нет, сменю ник сам
		iKeys += MENU_KEY_3
	}
	
	show_menu( id, iKeys, szMenu, _, "nameguard_menu" )
	
	g_szUserNameguardMenuDisplayed[ id ] ++
}

public handler_nameguard_menu( id, iKey )
{
	iKey ++

	switch( iKey )
	{
		case 1: change_name( id )
		case 2: client_cmd( id, "disconnect" )
		case 3:
		{
			g_bNameguardKeyUsed[ id ] = true
			yasg_print_color( id, "%L", id, "YASG_NAMEGUARD_RULES" ) // Необходимо сменить ник до следующей проверки!
		}
	}
}

public nameguard_check( id )
{
	if( !is_user_user( id ) )
		return
	
	new szName[ 32 ]
	get_user_info( id, "name", szName, charsmax( szName ) )
	
	if( is_name_safe( szName ) )
		return

	switch( get_pcvar_num( g_pcvr_NameguardMode ) )
	{
		case 1: kick_user( id, "YASG_KICK_NAMEGUARD" ) // Кикнут за запрещенные слова в нике.
		case 2:
		{
			if( g_bNameguardKeyUsed[ id ] )
				kick_user( id, "YASG_KICK_NAMEGUARD" ) // Кикнут за запрещенные слова в нике.
			
			else
			{
				if( g_szUserNameguardMenuDisplayed[ id ] < 2 )
					show_nameguard_menu( id, szName )
				
				else kick_user( id, "YASG_KICK_NAMEGUARD" ) // Кикнут за запрещенные слова в нике.
			}
		}
		
		case 3: change_name( id )
	}
}

public change_name( id )
{
	if( !is_user_connected( id ) )
			return
	
	new sz_pCvrNGName[ 32 ]
	
	get_pcvar_string( g_pcvr_NameguardName, sz_pCvrNGName, charsmax( sz_pCvrNGName ) ) 
	set_msg_block( g_msg_SayText, BLOCK_ONCE )
	g_bSetClientKeyValueBlock = true
	set_user_info( id, "name", sz_pCvrNGName )

	yasg_print_color( id, "%L", id, "YASG_NAMEGUARD_NAMECHANGED", sz_pCvrNGName ) // Ваш ник изменен на ^"%s^", переименуйте себя.
}

public kick_user( id, szMLReason[] )
{
	if( !is_user_connected( id ) )
			return
	
	server_cmd( "kick #%d ^"[%s] %L^"", get_user_userid( id ), MSGS_PREFIX, id, szMLReason )
}

public bool:is_name_safe( const szName[] )
{	
	new i, szTemp[ 32 ]

	client_print( 0, print_chat, "ArraySize RestNames is:%d", ArraySize( g_szRestNames ) )

	for( i = 0; i < ArraySize( g_szWlNames ); i ++ )
	{
		ArrayGetString( g_szWlNames, i, szTemp, charsmax( szTemp ) )

		if( containi( szName, szTemp ) != -1 )
			return true
	}
	
	for( i = 0; i < ArraySize( g_szRestNames ); i ++ )
	{
		ArrayGetString( g_szRestNames, i, szTemp, charsmax( szTemp ) )

		if( containi( szName, szTemp ) != -1 )
			return false
	}
	
	return true
}


public bool:is_user_user( id )
{
	if( is_user_bot( id ) || is_user_hltv( id ) || !!is_user_connected( id ) ) 
		return false
	
	new szFlags[ 24 ]
	get_pcvar_string( g_pcvr_ImmunityFlag, szFlags, charsmax( szFlags ) )
	
	if( get_user_flags( id ) & read_flags( szFlags ) )
		return false
	
	return true
}

stock yasg_print_color( id, szInput[], any:... )
{
	new szMessage[ 192 ]
   
	vformat( szMessage, charsmax( szMessage ), szInput, 3 )
	format( szMessage, charsmax( szMessage ), "^1[^4%s^1] %s", MSGS_PREFIX, szMessage )

	replace_all( szMessage, charsmax( szMessage ), "!g", "^4" ) // Green Color
	replace_all( szMessage, charsmax( szMessage ), "!n", "^1" ) // Default Color
	replace_all( szMessage, charsmax( szMessage ), "!t", "^3" ) // Team Color
  
	client_print_color( id, print_team_default, szMessage )
}