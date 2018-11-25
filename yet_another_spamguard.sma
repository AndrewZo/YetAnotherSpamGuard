#include <amxmodx>
#include <amxmisc>
#include <regex>

#define PLUGIN			"Yet Another SpamGuard"
#define VERSION			"2.1"
#define AUTHOR			"AndrewZ/voed"

#define MAX_WLMESSAGES		128
#define MAX_WLNAMES			128
#define MAX_MESSAGES		128
#define MAX_NAMES			128
#define MAX_LONGMESSAGES	10
#define MAX_NAMECHANGES		4

#define WLMESSAGES_SIZE		190
#define WLNAMES_SIZE		32
#define MESSAGES_SIZE		190
#define NAMES_SIZE			32

#define MSGS_PREFIX			"YASG"

new g_szRegexPattern[] = "^^[\w\dа-яА-Я\-\'\<\>\{\}\[\]\(\)\*\.\\\?\$\|\/\,\:\;\~\`\@\#\!\&\=\^^\ \і\І\ї\Ї\є\Є\Ё\ё]+$"

new g_WHITELIST_MESSAGES[ MAX_WLMESSAGES ][ WLMESSAGES_SIZE ],
	g_WHITELIST_NAMES[ MAX_WLNAMES ][ WLNAMES_SIZE ],
	g_BLOCKED_MESSAGES[ MAX_MESSAGES ][ MESSAGES_SIZE ],
	g_BLOCKED_NAMES[ MAX_NAMES ][ NAMES_SIZE ]

new bool:g_bChatguardKeyUsed[ 33 ],
	bool:g_bNameguardKeyUsed[ 33 ]
	
new g_szUserSpamMessages[ 33 ][ MAX_LONGMESSAGES ][ 192 ], 
	g_szUserLongmessagesCount[ 33 ], 
	g_szUserNameguardMenuDisplayed[ 33 ],
	g_szUserNameguardNameChanges[ 33 ]

new g_pcvr_ImmunityFlag,
	g_pcvr_ChatguardMode, g_pcvr_ChatguardRepeatMode, g_pcvr_ChatguardRepeatLen,
	g_pcvr_NameguardMode, g_pcvr_NameguardName, g_pcvr_NameguardNamespam
	
new g_msg_SayText

new g_iMaxPlayers

new bool:g_bSetClientKeyValueBlock

new g_szConfigsDir[ 64 ]

public plugin_init()
{
	register_plugin( PLUGIN, VERSION, AUTHOR )
	
	register_logevent( "event_round_start", 2, "1=Round_Start" )
	
	register_forward( FM_SetClientKeyValue, "fwd_setclientkeyvalue" )
	
	register_clcmd( "say", "hook_say" )
	register_clcmd( "say_team", "hook_say" )
	
	g_msg_SayText = get_user_msgid( "SayText" )
	
	g_iMaxPlayers = get_maxplayers()
	
	g_pcvr_ImmunityFlag			= register_cvar( "yasg_immunity_flag", "a" )
	g_pcvr_ChatguardMode		= register_cvar( "yasg_chatguard_mode", "2" )
	g_pcvr_ChatguardRepeatMode	= register_cvar( "yasg_chatguard_repeat_mode", "2" )
	g_pcvr_ChatguardRepeatLen	= register_cvar( "yasg_chatguard_repeat_len", "13" )
	g_pcvr_NameguardMode		= register_cvar( "yasg_nameguard_mode", "2" )
	g_pcvr_NameguardName		= register_cvar( "yasg_nameguard_name", "[YASG] Player" )
	g_pcvr_NameguardNamespam	= register_cvar( "yasg_nameguard_namespam", "1" )
	
	register_cvar( "yasg_version", VERSION, FCVAR_SPONLY | FCVAR_SERVER )
	set_cvar_string( "yasg_version", VERSION )
	
	register_dictionary( "yet_another_spamguard.txt" )

	register_menu( "chatguard_menu", -1, "handler_chatguard_menu" )
	register_menu( "nameguard_menu", -1, "handler_nameguard_menu" )

	set_task( 1.0, "task_read_files" )
}

public plugin_cfg()
{
	get_configsdir( g_szConfigsDir, charsmax( g_szConfigsDir ) )
	server_cmd( "exec %s/yet_another_spamguard/yasg_config.cfg", g_szConfigsDir )
}

public task_read_files()
{
	new szTemp[ 128 ], i, iFile
	
	i = 0
	formatex( szTemp, charsmax( szTemp ), "%s/yet_another_spamguard/yasg_whitelist_messages.ini", g_szConfigsDir )
	iFile = fopen( szTemp, "rt" )
	
	if( iFile )
	{
		while( !feof( iFile ) )
		{
			fgets( iFile, g_WHITELIST_MESSAGES[ i ++ ], WLMESSAGES_SIZE - 1 )
		}
	}
	
	i = 0
	formatex( szTemp, charsmax( szTemp ), "%s/yet_another_spamguard/yasg_whitelist_names.ini", g_szConfigsDir )
	iFile = fopen( szTemp, "rt" )
	if( iFile )
	{
		while( !feof( iFile ) )
		{
			fgets( iFile, g_WHITELIST_NAMES[ i ++ ], WLNAMES_SIZE - 1 )
		}
	}
	
	i = 0
	formatex( szTemp, charsmax( szTemp ), "%s/yet_another_spamguard/yasg_messages.ini", g_szConfigsDir )
	iFile = fopen( szTemp, "rt" )
	if( iFile )
	{
		while( !feof( iFile ) )
		{
			fgets( iFile, g_BLOCKED_MESSAGES[ i ++ ], MESSAGES_SIZE - 1 )
		}
	}
	
	i = 0
	formatex( szTemp, charsmax( szTemp ), "%s/yet_another_spamguard/yasg_names.ini", g_szConfigsDir )
	iFile = fopen( szTemp, "rt" )
	if( iFile )
	{
		while( !feof( iFile ) )
		{
			fgets( iFile, g_BLOCKED_NAMES[ i ++ ], NAMES_SIZE - 1 )
		}
	}
}

public event_round_start()
{
	if( !get_pcvar_num( g_pcvr_NameguardMode ) && !get_pcvar_num( g_pcvr_NameguardNamespam ) )
		return
	
	new i
	
	for( i = 1; i <= g_iMaxPlayers; i ++ )
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
		
	if( get_pcvar_num( g_pcvr_NameguardNamespam ) && I_can_do_something( id ) )
	{	
		g_szUserNameguardNameChanges[ id ] ++
		
		if( g_szUserNameguardNameChanges[ id ] > MAX_NAMECHANGES )
			kick_user( id, "YASG_KICK_NAMEGUARD_NAMESPAM" )
	}
	
	return FMRES_IGNORED
}

public client_putinserver( id )
{
	g_bNameguardKeyUsed[ id ] 		 	= false
	g_bChatguardKeyUsed[ id ] 		 	= false
	g_szUserLongmessagesCount[ id ] 		= 0
	g_szUserNameguardMenuDisplayed[ id ]	= 0
	g_szUserNameguardNameChanges[ id ]		= 0
	
	if( get_pcvar_num( g_pcvr_NameguardMode ) )
	{
		if( task_exists( id ) )
			remove_task( id )
			
		set_task( 3.0, "nameguard_check", id )
	}
}

public hook_say( id )
{
	static iCvarChatguardMode, iCvarChatguardRepeatMode
	
	iCvarChatguardMode = get_pcvar_num( g_pcvr_ChatguardMode )
	iCvarChatguardRepeatMode = get_pcvar_num( g_pcvr_ChatguardRepeatMode )
	
	if( ( iCvarChatguardMode || iCvarChatguardRepeatMode ) && I_can_do_something( id ) )
	{
		new szInput[ 192 ]
		read_args( szInput, charsmax( szInput ) )
		remove_quotes( szInput )

		if( iCvarChatguardMode )
		{
			static i
			
			for( i = 0; i < sizeof( g_WHITELIST_MESSAGES ); i ++ )
			{
				if( containi( szInput, g_WHITELIST_MESSAGES[ i ] ) != -1 )
					return PLUGIN_CONTINUE
			}
			
			for( i = 0; i < sizeof( g_BLOCKED_MESSAGES ); i ++ )
			{
				if( containi( szInput, g_BLOCKED_MESSAGES[ i ] ) != -1 )
				{
					switch( iCvarChatguardMode )
					{
						case 1: return PLUGIN_HANDLED
						case 2:
						{
							if( !is_user_steam( id ) )
								chatguard_punish_menu( id, szInput )

							return PLUGIN_HANDLED
						}
					}
				}
			}
		}

		if( iCvarChatguardRepeatMode )
		{
			if( strlen( szInput ) > get_pcvar_num( g_pcvr_ChatguardRepeatLen ) )
			{
				static i
				
				for( i = 0; i < MAX_LONGMESSAGES; i ++ )
				{
					if( equal( g_szUserSpamMessages[ id ][ i ], szInput ) )
					{
						if( iCvarChatguardRepeatMode == 2 )
						{
							new szFile[ 256 ], szLog[ 256 ], szName[ 32 ], szAuthID[ 35 ], szIP[ 23 ], iDate[ 3 ] 
							
							get_user_name( id, szName, charsmax( szName ) )
							get_user_authid( id, szAuthID, charsmax( szAuthID ) )
							get_user_ip( id, szIP, charsmax( szIP ), 1 )
							date( iDate[ 0 ], iDate[ 1 ], iDate[ 2 ] )
							
							format( szLog, charsmax( szLog ), "%s: %s (AuthID:[%s], IP:[%s])", szName, szInput , szAuthID, szIP )
							format( szFile, charsmax( szFile ), "%s/yet_another_spamguard/logs/LONGMESSAGES%d%d%d.txt", g_szConfigsDir, iDate[ 0 ], iDate[ 1 ], iDate[ 2 ] )
							
							log_to_file( szFile, szLog )
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
	}
	
	return PLUGIN_CONTINUE
}


public chatguard_punish_menu( id, szInput[] )
{
	new szMenu[ 512 ], iLen, iKeys, szText[ 34 ]
	iKeys = MENU_KEY_1 + MENU_KEY_2
	
	formatex( szText, charsmax( szText ), "%s", szInput )

	iLen = formatex( szMenu, charsmax( szMenu ), "\y%s v%s", PLUGIN, VERSION )
	
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n^n\y(\d^"%s..^"\y)", szText )
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n\y%L", id, "YASG_CHATGUARD_DETECTED" )
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n%L", id, "YASG_CHATGUARD_DETECTED2" )

	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n^n\w1. %L", id, "YASG_CHATGUARD_YES" )
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n2. %L", id, "YASG_CHATGUARD_NO" )

	if( !g_bChatguardKeyUsed[ id ] )
	{
		iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n3. %L", id, "YASG_CHATGUARD_KEY" )
		iKeys += MENU_KEY_3
	}

	show_menu( id, iKeys, szMenu, _, "chatguard_menu" )
}

public handler_chatguard_menu( id, iKey )
{
	iKey ++

	switch( iKey )
	{
		case 1: reset_defaults_keys( id )
		case 2: client_cmd( id, "disconnect" )
		case 3:
		{
			g_bChatguardKeyUsed[ id ] = true

			yasg_print_color( id, "%L", id, "YASG_CHATGUARD_RULES" )
		}
	}
}


public show_nameguard_menu( id, szName[] )
{
	new szMenu[ 512 ], iLen, iKeys
	
	iKeys = MENU_KEY_1 + MENU_KEY_2
	
	iLen = formatex( szMenu, charsmax( szMenu ), "\y%s v%s", PLUGIN, VERSION )
	
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n^n\y(\d^"%s^"\y)", szName )
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n\y%L", id, "YASG_NAMEGUARD_DETECTED" )
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n^n^n%L", id, "YASG_NAMEGUARD_DETECTED2" )

	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n^n\w1. %L", id, "YASG_NAMEGUARD_YES" )
	iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n2. %L", id, "YASG_NAMEGUARD_NO" )
	
	if( !g_bNameguardKeyUsed[ id ] )
	{
		iLen += formatex( szMenu[ iLen ], charsmax( szMenu ) - iLen, "^n3. %L", id, "YASG_NAMEGUARD_KEY" )
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
			yasg_print_color( id, "%L", id, "YASG_NAMEGUARD_RULES" )
		}
	}
}

public nameguard_check( id )
{
	if( !I_can_do_something( id ) || !is_user_connected( id ) )
		return
	
	new szName[ 32 ]
	get_user_info( id, "szName", szName, charsmax( szName ) )
	
	if( valid_name( szName ) )
		return

	switch( get_pcvar_num( g_pcvr_NameguardMode ) )
	{
		case 1: kick_user( id, "YASG_KICK_NAMEGUARD" )
		case 2:
		{
			if( g_bNameguardKeyUsed[ id ] )
				kick_user( id, "YASG_KICK_NAMEGUARD" )
			
			else
			{
				if( g_szUserNameguardMenuDisplayed[ id ] < 2 )
					show_nameguard_menu( id, szName )
				
				else kick_user( id, "YASG_KICK_NAMEGUARD" )
			}
		}
		
		case 3: change_name( id )
	}
}

public change_name( id )
{
	if( !is_user_connected( id ) )
			return
	
	new szCvarName[ 32 ]
	
	get_pcvar_string( g_pcvr_NameguardName, szCvarName, charsmax( szCvarName ) ) 
	set_msg_block( g_msg_SayText, BLOCK_ONCE )
	g_bSetClientKeyValueBlock = true
	set_user_info( id, "name", szCvarName )

	yasg_print_color( id, "%L", id, "YASG_NAMEGUARD_NAMECHANGED", szCvarName )
}

public kick_user( id, sMLReason[] )
{
	if( !is_user_connected( id ) )
			return
	
	server_cmd( "kick #%d ^"[YASG] %L^"", get_user_userid( id ), id, sMLReason )
}

public reset_defaults_keys( id )
{
	client_cmd( id, "unbindall" )
	client_cmd( id, "bind ^"TAB^" ^"+showscores^"" )
	client_cmd( id, "bind ^"ENTER^" ^"+attack^"" )
	client_cmd( id, "bind ^"ESCAPE^" ^"escape^"" )
	client_cmd( id, "bind ^"SPACE^" ^"+jump^"" )
	client_cmd( id, "bind ^"'^" ^"+moveup^"" )
	client_cmd( id, "bind ^"+^" ^"sizeup^"" )
	client_cmd( id, "bind ^",^" ^"buyammo1^"" )
	client_cmd( id, "bind ^"-^" ^"sizedown^"" )
	client_cmd( id, "bind ^".^" ^"buyammo2^"" )
	client_cmd( id, "bind ^"/^" ^"+movedown^"" )
	client_cmd( id, "bind ^"0^" ^"slot10^"" )
	client_cmd( id, "bind ^"1^" ^"slot1^"" )
	client_cmd( id, "bind ^"2^" ^"slot2^"" )
	client_cmd( id, "bind ^"3^" ^"slot3^"" )
	client_cmd( id, "bind ^"4^" ^"slot4^"" )
	client_cmd( id, "bind ^"5^" ^"slot5^"" )
	client_cmd( id, "bind ^"6^" ^"slot6^"" )
	client_cmd( id, "bind ^"7^" ^"slot7^"" )
	client_cmd( id, "bind ^"8^" ^"slot8^"" )
	client_cmd( id, "bind ^"9^" ^"slot9^"" )
	client_cmd( id, "bind ^";^" ^"+mlook^"" )
	client_cmd( id, "bind ^"=^" ^"sizeup^"" )
	client_cmd( id, "bind ^"a^" ^"+moveleft^"" )
	client_cmd( id, "bind ^"b^" ^"buy^"" )
	client_cmd( id, "bind ^"c^" ^"radio3^"" )
	client_cmd( id, "bind ^"d^" ^"+moveright^"" )
	client_cmd( id, "bind ^"e^" ^"+use^"" )
	client_cmd( id, "bind ^"f^" ^"impulse 100^"" )
	client_cmd( id, "bind ^"g^" ^"drop^"" )
	client_cmd( id, "bind ^"h^" ^"+commandmenu^"" )
	client_cmd( id, "bind ^"i^" ^"showbriefing^"" )
	client_cmd( id, "bind ^"j^" ^"cheer^"" )
	client_cmd( id, "bind ^"k^" ^"+voicerecord^"" )
	client_cmd( id, "bind ^"m^" ^"chooseteam^"" )
	client_cmd( id, "bind ^"n^" ^"nightvision^"" )
	client_cmd( id, "bind ^"o^" ^"buyequip^"" )
	client_cmd( id, "bind ^"q^" ^"lastinv^"" )
	client_cmd( id, "bind ^"r^" ^"+reload^"" )
	client_cmd( id, "bind ^"s^" ^"+back^"" )
	client_cmd( id, "bind ^"t^" ^"impulse 201^"" )
	client_cmd( id, "bind ^"u^" ^"messagemode2^"" )
	client_cmd( id, "bind ^"w^" ^"+forward^"" )
	client_cmd( id, "bind ^"x^" ^"radio2^"" )
	client_cmd( id, "bind ^"y^" ^"messagemode^"" )
	client_cmd( id, "bind ^"z^" ^"radio1^"" )
	client_cmd( id, "bind ^"[^" ^"invprev^"" )
	client_cmd( id, "bind ^"]^" ^"invnext^"" )
	client_cmd( id, "bind ^"`^" ^"toggleconsole^"" )
	client_cmd( id, "bind ^"~^" ^"toggleconsole^"" )
	client_cmd( id, "bind ^"UPARROW^" ^"+forward^"" )
	client_cmd( id, "bind ^"DOWNARROW^" ^"+back^"" )
	client_cmd( id, "bind ^"LEFTARROW^" ^"+left^"" )
	client_cmd( id, "bind ^"RIGHTARROW^" ^"+right^"" )
	client_cmd( id, "bind ^"ALT^" ^"+strafe^"" )
	client_cmd( id, "bind ^"CTRL^" ^"+duck^"" )
	client_cmd( id, "bind ^"SHIFT^" ^"+speed^"" )
	client_cmd( id, "bind ^"F1^" ^"autobuy^"" )
	client_cmd( id, "bind ^"F2^" ^"rebuy^"" )
	client_cmd( id, "bind ^"F5^" ^"snapshot^"" )
	client_cmd( id, "bind ^"F6^" ^"save quick^"" )
	client_cmd( id, "bind ^"F7^" ^"load quick^"" )
	client_cmd( id, "bind ^"F10^" ^"quit prompt^"" )
	client_cmd( id, "bind ^"INS^" ^"+klook^"" )
	client_cmd( id, "bind ^"PGDN^" ^"+lookdown^"" )
	client_cmd( id, "bind ^"PGUP^" ^"+lookup^"" )
	client_cmd( id, "bind ^"END^" ^"centerview^"" )
	client_cmd( id, "bind ^"MWHEELDOWN^" ^"invnext^"" )
	client_cmd( id, "bind ^"MWHEELUP^" ^"invprev^"" )
	client_cmd( id, "bind ^"MOUSE1^" ^"+attack^"" )
	client_cmd( id, "bind ^"MOUSE2^" ^"+attack2^"" )
	client_cmd( id, "bind ^"PAUSE^" ^"pause^"" )
}

stock bool:valid_name( const szInput[] )
{	
	static i, szName[ 32 ], iRet, szError[ 128 ], Regex:iRegexHandle
	
	formatex( szName, charsmax( szName ), "%s", szInput )

	for( i = 0; i < sizeof( g_WHITELIST_NAMES ); i ++ )
	{
		if( containi( szName, g_WHITELIST_NAMES[ i ] ) != -1 )
			return true
	}
	
	for( i = 0; i < sizeof( g_BLOCKED_NAMES ); i ++ )
	{
		if( containi( szName, g_BLOCKED_NAMES[ i ] ) != -1 )
			return false
	}
	
	iRegexHandle = regex_compile_ex( g_szRegexPattern, PCRE_UTF8, szError, charsmax( szError ), iRet )

	if( iRegexHandle != REGEX_PATTERN_FAIL )
	{
		switch( regex_match_c( szName, iRegexHandle, iRet ) )
		{
			case REGEX_MATCH_FAIL: log_to_file( "[YASG] REGEX MATCH FAILED FOR %s", szName )
			case REGEX_NO_MATCH: return false
		}
		
		regex_free( iRegexHandle )
	}
	
	return true
}


stock bool:I_can_do_something( id )
{
	if( is_user_bot( id ) )
		return false
	
	if( is_user_hltv( id ) ) 
		return false
	
	new szError[ 23 ]
	
	get_pcvar_string( g_pcvr_ImmunityFlag, szError, charsmax( szError ) )
	
	if( get_user_flags( id ) & read_flags( szError ) )
		return false
	
	return true
}

stock bool:is_user_steam( id ) // Sh0oter
{
	new iCvarPointer
	
	if( iCvarPointer || ( iCvarPointer = get_cvar_pointer( "dp_r_id_provider" ) ) )
	{
		server_cmd( "dp_clientinfo %d", id )
		server_exec()
		return ( get_pcvar_num( iCvarPointer ) == 2 ) ? true : false
	}
	
	return false
}


stock yasg_print_color( id, szInput[], any:... )
{
	new szMessage[ 192 ]
   
	vformat( szMessage, charsmax( szMessage ), szInput, 3 )
	format( szMessage, charsmax( szMessage ), "%s %s", MSGS_PREFIX, szMessage )
  
	client_print_color( id, print_team_default, szMessage )

	return 0
}