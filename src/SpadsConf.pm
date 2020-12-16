# Object-oriented Perl module handling SPADS configuration files
#
# Copyright (C) 2008-2020  Yann Riou <yaribzh@gmail.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

package SpadsConf;

use strict;

use Digest::MD5 'md5_base64';
use FileHandle;
use Fcntl qw':DEFAULT :flock';
use File::Basename;
use File::Copy;
use File::Spec;
use FindBin;
use List::Util 'first';
use Storable qw'nstore retrieve dclone';
use Time::HiRes;

use SimpleLog;

sub any (&@) { my $c = shift; return defined first {&$c} @_; }
sub all (&@) { my $c = shift; return ! defined first {! &$c} @_; }
sub none (&@) { my $c = shift; return ! defined first {&$c} @_; }
sub notall (&@) { my $c = shift; return defined first {! &$c} @_; }

# Internal data ###############################################################

my $moduleVersion='0.12.5';
my $win=$^O eq 'MSWin32';
my $macOs=$^O eq 'darwin';
my $spadsDir=$FindBin::Bin;
my $unitsyncLibName;
if($win) {
  $unitsyncLibName='unitsync.dll';
}elsif($macOs) {
  $unitsyncLibName='libunitsync.dylib';
}else{
  $unitsyncLibName='libunitsync.so';
}

my %globalParameters = (lobbyLogin => ['login'],
                        lobbyPassword => ['password'],
                        lobbyHost => ['hostname'],
                        lobbyPort => ['port'],
                        lobbyReconnectDelay => ['integer'],
                        localLanIp => ['ipAddr','star','null'],
                        lobbyFollowRedirect => ['bool'],
                        autoHostPort => ['port'],
                        forceHostIp => ['ipAddr','null'],
                        springConfig => ['readableFile','null'],
                        springServer => ['absoluteExecutableFile','null'],
                        springServerType => ['springServerType','null'],
                        autoUpdateRelease => ['autoUpdateType','null'],
                        autoUpdateDelay => ['integer'],
                        autoRestartForUpdate => ['autoRestartType'],
                        etcDir => ['notNull'],
                        varDir => ['notNull'],
                        instanceDir => [],
                        logDir => ['notNull'],
                        pluginsDir => ['notNull'],
                        autoManagedSpringVersion => ['autoManagedSpringVersionType','null'],
                        autoManagedSpringDir => ['notNull'],
                        unitsyncDir => ['unitsyncDirType','null'],
                        springDataDir => ['absoluteReadableDirs'],
                        autoReloadArchivesMinDelay => ['integer'],
                        sendRecordPeriod => ['integer'],
                        maxBytesSent => ['integer'],
                        maxLowPrioBytesSent => ['integer'],
                        maxChatMessageLength => ['integer'],
                        maxAutoHostMsgLength => ['integer'],
                        msgFloodAutoKick => ['integerCouple'],
                        statusFloodAutoKick => ['integerCouple'],
                        kickFloodAutoBan => ['integerTriplet'],
                        cmdFloodAutoIgnore => ['integerTriplet'],
                        floodImmuneLevel => ['integer'],
                        maxSpecsImmuneLevel => ['integer'],
                        autoLockClients => ['integer','null'],
                        defaultPreset => ['notNull'],
                        restoreDefaultPresetDelay => ['integer'],
                        masterChannel => ['channel','null'],
                        broadcastChannels => ['channelList','null'],
                        opOnMasterChannel => ['bool'],
                        voteTime => ['integer'],
                        minVoteParticipation => ['integer','integerCouple'],
                        reCallVoteDelay => ['integer'],
                        promoteDelay => ['integer'],
                        botsRank => ['integer'],
                        autoSaveBoxes => ['bool2'],
                        autoLearnMaps => ['bool'],
                        lobbyInterfaceLogLevel => ['integer'],
                        autoHostInterfaceLogLevel => ['integer'],
                        updaterLogLevel => ['integer'],
                        spadsLogLevel => ['integer'],
                        simpleEventLogLevel => ['integer'],
                        logChanChat => ['bool'],
                        logChanJoinLeave => ['bool'],
                        logBattleChat => ['bool'],
                        logBattleJoinLeave => ['bool'],
                        logGameChat => ['bool'],
                        logGameJoinLeave => ['bool'],
                        logGameServerMsg => ['bool'],
                        logPvChat => ['bool'],
                        alertLevel => ['integer'],
                        alertDelay => ['integer'],
                        alertDuration => ['integer'],
                        promoteMsg => [],
                        promoteChannels => ['channelList','null'],
                        springieEmulation => ['onOffWarnType'],
                        colorSensitivity => ['integer'],
                        dataDumpDelay => ['integer'],
                        allowSettingsShortcut => ['bool'],
                        kickBanDuration => ['kickBanDurationType'],
                        privacyTrustLevel => ['integer'],
                        userDataRetention => ['dataRetention'],
                        useWin32Process => ['useWin32ProcessType'],
                        autoLoadPlugins => [],
                        eventModel => ['eventModelType'],
                        maxChildProcesses => ['integer']);

my %spadsSectionParameters = (description => ['notNull'],
                              commandsFile => ['notNull'],
                              mapList => ['ident'],
                              banList => ['ident','null'],
                              preset => ['notNull'],
                              hostingPreset => ['ident'],
                              battlePreset => ['ident'],
                              map => [],
                              rotationType => ['rotationType'],
                              rotationEndGame => ['rotationMode'],
                              rotationEmpty => ['rotationMode'],
                              rotationManual => ['manualRotationMode'],
                              rotationDelay => ['integer','integerRange'],
                              midGameSpecLevel => ['integer','integerRange'],
                              autoAddBotNb => ['integer','integerRange'],
                              maxBots => ['integer','integerRange','null'],
                              maxLocalBots => ['integer','integerRange','null'],
                              maxRemoteBots => ['integer','integerRange','null'],
                              localBots => ['botList','null'],
                              allowedLocalAIs => [],
                              maxSpecs => ['integer','integerRange','null'],
                              speedControl => ['bool2'],
                              welcomeMsg => [],
                              welcomeMsgInGame => [],
                              mapLink => [],
                              advertDelay => ['integer','integerRange'],
                              advertMsg => [],
                              ghostMapLink => [],
                              autoSetVoteMode => ['bool'],
                              voteMode => ['voteMode'],
                              votePvMsgDelay => ['integer','integerRange'],
                              voteRingDelay => ['integer','integerRange'],
                              minRingDelay => ['integer','integerRange'],
                              handleSuggestions => ['bool'],
                              ircColors => ['bool'],
                              spoofProtection => ['onOffWarnType'],
                              rankMode => ['rankMode'],
                              skillMode => ['skillMode'],
                              shareId => ['password','null'],
                              autoCallvote => ['bool'],
                              autoLoadMapPreset => ['bool'],
                              hideMapPresets => ['bool'],
                              balanceMode => ['balanceModeType'],
                              clanMode => ['clanModeType'],
                              nbPlayerById => ['nonNullInteger','nonNullIntegerRange'],
                              teamSize => ['nonNullInteger','nonNullIntegerRange'],
                              minTeamSize => ['integer','integerRange'],
                              nbTeams => ['nonNullInteger','nonNullIntegerRange'],
                              extraBox => ['integer','integerRange'],
                              idShareMode => ['idShareModeType'],
                              minPlayers => ['nonNullInteger','nonNullIntegerRange'],
                              endGameCommand => [],
                              endGameCommandEnv => ['null','varAssignments'],
                              endGameCommandMsg => ['null','exitMessages'],
                              endGameAwards => ['bool2'],
                              autoLock => ['autoParamType'],
                              autoSpecExtraPlayers => ['bool'],
                              autoBalance => ['autoParamType'],
                              autoFixColors => ['autoParamType'],
                              autoBlockBalance => ['bool'],
                              autoBlockColors => ['bool'],
                              autoStart => ['autoParamType'],
                              autoStop => ['autoStopType'],
                              autoLockRunningBattle => ['bool'],
                              forwardLobbyToGame => ['bool'],
                              noSpecChat => ['bool'],
                              noSpecDraw => ['bool'],
                              unlockSpecDelay => ['integerCouple'],
                              freeSettings => ['settingList'],
                              allowModOptionsValues => ['bool'],
                              allowMapOptionsValues => ['bool'],
                              allowGhostMaps =>['bool']);

my %hostingParameters = (description => ['notNull'],
                         battleName => ['notNull'],
                         modName => ['notNull'],
                         port => ['port'],
                         natType => ['integer','integerRange'],
                         password => ['password'],
                         maxPlayers => ['maxPlayersType'],
                         minRank => ['integer','integerRange']);

my %battleParameters = (description => ['notNull'],
                        startpostype => ['integer','integerRange'],
                        resetoptions => ['bool'],
                        disabledunits => ['disabledUnitList','null']);

my %paramTypes = (login => '[\w\[\]]{2,20}',
                  password => '[^\s]+',
                  hostname => '\w[\w\-\.]*',
                  port => sub { return ($_[0] =~ /^\d+$/ && $_[0] < 65536) },
                  integer => '\d+',
                  nonNullInteger => '[1-9]\d*',
                  ipAddr => '\d+\.\d+\.\d+\.\d+',
                  star => '\*',
                  null => '',
                  absoluteExecutableFile => sub { return (-f $_[0] && -x $_[0] && isAbsolutePath($_[0])) },
                  unitsyncDirType => sub { return (-f "$_[0]/$unitsyncLibName" && -r "$_[0]/$unitsyncLibName") },
                  autoUpdateType => '(stable|testing|unstable|contrib)',
                  autoManagedSpringVersionType => sub { return $_[0] =~ /^(stable|testing|unstable|maintenance)(?:;\d*(?:;(on|off|whenEmpty|whenOnlySpec))?)?$/ || $_[0] =~ /^\d+(?:\.\d+){1,3}(?:-\d+-g[0-9a-f]+)?$/},
                  autoRestartType => '(on|off|whenEmpty|whenOnlySpec)',
                  absoluteReadableDirs => sub { return $_[0] ne '' && (all {-d $_ && -x $_ && -r $_ && isAbsolutePath($_)} split($win?';':':',$_[0])) },
                  integerCouple => '\d+;\d+',
                  integerTriplet => '\d+;\d+;\d+',
                  bool => '[01]',
                  bool2 => '[012]',
                  ident => '[\w\.\-]+',
                  channel => '[\w\[\]\ ]+',
                  channelList => '([\w\[\]\ ]+(;[\w\[\]\ ]+)*)?',
                  disabledUnitList => '(\-\*|\-\w+|\w+)(;(\-\*|\-\w+|\w+))*',
                  notNull => '.+',
                  readableFile => sub { return (-f $_[0] && -r $_[0]) },
                  rotationType => '(map(;[\w\.\-]+)?|preset)',
                  rotationMode => '(off|random|order)',
                  manualRotationMode => '(random|order)',
                  maxPlayersType => sub { return (($_[0] =~ /^\d+$/ && $_[0] < 252) || ($_[0] =~ /^(\d+)\-(\d+)$/ && $1 < $2 && $2 < 252)) },
                  integerRange => '\d+\-\d+',
                  kickBanDurationType => '\d+g?',
                  nonNullIntegerRange => '[1-9]\d*\-\d+',
                  float => '\d+(\.\d*)?',
                  floatRange => '\d+\.\d+\-\d+\.\d+',
                  balanceModeType => '(clan;random|clan;skill|skill|random)',
                  clanModeType => '(tag(\(\d*\))?(;pref(\(\d*\))?)?|pref(\(\d*\))?(;tag(\(\d*\))?)?)',
                  idShareModeType => '(all|auto|manual|clan|off)',
                  deathMode => '(killall|com|comcontrol)',
                  autoParamType => '(on|off|advanced)',
                  autoStopType => '(gameOver(\(\d+\))?|noOpponent(\(\d+\))?|onlySpec(\(\d+\))?|off)',
                  onOffWarnType => '(on|off|warn)',
                  voteMode => '(normal|away)',
                  rankMode => '(account|ip|[0-7])',
                  skillMode => '(rank|TrueSkill)',
                  varAssignments => '\w+=[^;]*(;\w+=[^;]*)*',
                  exitMessages => '(\(\d+(-\d+)?(,\d+(-\d+)?)*\))?[^\|]+(\|(\(\d+(-\d+)?(,\d+(-\d+)?)*\))?[^\|]+)*',
                  dataRetention => '(-1|\d+);(-1|\d+);(-1|\d+)',
                  useWin32ProcessType => sub { return (($win && $_[0] =~ /^[01]$/) || $_[0] eq '0') },
                  springServerType => '(dedicated|headless)',
                  settingList => sub {
                                   my @sets=split(/;/,$_[0]);
                                   foreach my $set (@sets) {
                                     $set=$1 if($set =~ /^([^\(]+)\([^\)]+\)$/);
                                     return 0 unless(exists($spadsSectionParameters{$set}));
                                   }
                                   return 1;
                                 },
                  botList => '[\w\[\]]{2,20} \w+(#[\da-fA-F]{6})? [^ \;][^\;]*(;[\w\[\]]{2,20} \w+(#[\da-fA-F]{6})? [^ \;][^\;]*)*',
                  db => '[^\/]+\/[^\@]+\@(?i:dbi)\:\w+\:\w.*',
                  eventModelType => '(auto|internal|AnyEvent)');

my @banListsFields=(['accountId','name','country','cpu','lobbyClient','rank','access','bot','level','ip','skill','skillUncert'],['banType','startDate','endDate','remainingGames','reason']);
my @preferencesListsFields=(['accountId'],['autoSetVoteMode','voteMode','votePvMsgDelay','voteRingDelay','minRingDelay','handleSuggestions','password','rankMode','skillMode','shareId','spoofProtection','ircColors','clan']);
my @usersFields=(['accountId','name','country','cpu','rank','access','bot','auth'],['level']);
my @levelsFields=(['level'],['description']);
my @commandsFields=(['source','status','gameState'],['directLevel','voteLevel']);
my @mapBoxesFields=(['mapName','nbTeams'],['boxes']);
my @mapHashesFields=(['springMajorVersion','mapName'],['mapHash']);
my @userDataFieldsOld=(['accountId'],['country','cpu','lobbyClient','rank','timestamp','ips','names']);
my @userDataFields=(['accountId'],['country','lobbyClient','rank','timestamp','ips','names']);
my @springLobbyCertificatesFields=(['lobbyHost'],['certHashes']);

my %shareableData = ( savedBoxes => { type => 'fastTable',
                                      fields => \@mapBoxesFields },
                      bans => { type => 'table',
                                fields => \@banListsFields },
                      trustedLobbyCertificates => { type => 'binary' } );

# Constructor #################################################################

sub new {
  my ($objectOrClass,$confFile,$sLog,$p_macros,$p_previousInstance) = @_;
  $p_previousInstance//=0;
  my $class = ref($objectOrClass) || $objectOrClass;

  my $p_conf = loadSettingsFile($sLog,$confFile,\%globalParameters,\%spadsSectionParameters,$p_macros,undef,'set');
  if(! checkSpadsConfig($sLog,$p_conf)) {
    $sLog->log('Unable to load main configuration parameters',1);
    return 0;
  }

  $sLog=SimpleLog->new(logFiles => [$p_conf->{''}{logDir}.'/spads.log',''],
                       logLevels => [$p_conf->{''}{spadsLogLevel},3],
                       useANSICodes => [0,-t STDOUT ? 1 : 0],
                       useTimestamps => [1,-t STDOUT ? 0 : 1],
                       prefix => '[SPADS] ');

  my $p_hConf =  loadSettingsFile($sLog,$p_conf->{''}{etcDir}.'/hostingPresets.conf',{},\%hostingParameters,$p_macros,undef,'hSet');
  if(! checkHConfig($sLog,$p_conf,$p_hConf)) {
    $sLog->log('Unable to load hosting presets',1);
    return 0;
  }

  my $p_bConf =  loadSettingsFile($sLog,$p_conf->{''}{etcDir}.'/battlePresets.conf',{},\%battleParameters,$p_macros,1);
  if(! checkBConfig($sLog,$p_conf,$p_bConf)) {
    $sLog->log('Unable to load battle presets',1);
    return 0;
  }
  my $p_banLists=loadTableFile($sLog,$p_conf->{''}{etcDir}.'/banLists.conf',\@banListsFields,$p_macros);
  my $p_mapLists=loadSimpleTableFile($sLog,$p_conf->{''}{etcDir}.'/mapLists.conf',$p_macros);
  if(!checkConfigLists($sLog,$p_conf,$p_banLists,$p_mapLists)) {
    $sLog->log('Unable to load banLists or mapLists configuration files',1);
    return 0;
  }

  my $defaultPreset=$p_conf->{''}{defaultPreset};
  my $commandsFile=$p_conf->{$defaultPreset}{commandsFile}[0];
  my $p_users=loadTableFile($sLog,$p_conf->{''}{etcDir}.'/users.conf',\@usersFields,$p_macros);
  my $p_levels=loadTableFile($sLog,$p_conf->{''}{etcDir}.'/levels.conf',\@levelsFields,$p_macros);
  my $p_commands=loadTableFile($sLog,$p_conf->{''}{etcDir}."/$commandsFile",\@commandsFields,$p_macros,1);
  my $p_help=loadSimpleTableFile($sLog,"$spadsDir/help.dat",$p_macros,1);
  my $p_helpSettings=loadHelpSettingsFile($sLog,"$spadsDir/helpSettings.dat",$p_macros,1);

  my %sharedDataTs=map {$_ => 0} (keys %shareableData);
  if(exists $p_macros->{sharedData}) {
    foreach my $sharedData (split(',',$p_macros->{sharedData})) {
      if(exists $sharedDataTs{$sharedData}) {
        $sharedDataTs{$sharedData}=-1;
      }else{
        $sLog->log("Ignoring request to share invalid data \"$sharedData\"",2);
      }
    }
  }

  my $p_bans;
  if($sharedDataTs{bans}) {
    $p_bans=initSharedData($sLog,$p_conf,\%sharedDataTs,'bans');
  }else{
    my $bansFile=$p_conf->{''}{instanceDir}.'/bans.dat';
    touch($bansFile) unless(-f $bansFile);
    $p_bans=loadTableFile($sLog,$bansFile,\@banListsFields,{});
  }

  if(! checkNonEmptyHash($p_users,$p_levels,$p_commands,$p_help,$p_helpSettings,$p_bans)) {
    $sLog->log('Unable to load commands, help and permission system',1);
    return 0;
  }

  touch($p_conf->{''}{instanceDir}.'/preferences.dat') unless(-f $p_conf->{''}{instanceDir}.'/preferences.dat');
  my $p_preferences=loadFastTableFile($sLog,$p_conf->{''}{instanceDir}.'/preferences.dat',\@preferencesListsFields,{});
  if(! %{$p_preferences}) {
    $sLog->log('Unable to load preferences',1);
    return 0;
  }else{
    $p_preferences=preparePreferences($sLog,$p_preferences->{''});
  }

  my $p_mapBoxes=loadFastTableFile($sLog,$p_conf->{''}{etcDir}.'/mapBoxes.conf',\@mapBoxesFields,$p_macros);
  if(! %{$p_mapBoxes}) {
    $sLog->log('Unable to load map boxes',1);
    return 0;
  }

  my $p_savedBoxes;
  if($sharedDataTs{savedBoxes}) {
    $p_savedBoxes=initSharedData($sLog,$p_conf,\%sharedDataTs,'savedBoxes');
  }else{
    my $savedBoxesFile=$p_conf->{''}{instanceDir}.'/savedBoxes.dat';
    touch($savedBoxesFile) unless(-f $savedBoxesFile);
    $p_savedBoxes=loadFastTableFile($sLog,$savedBoxesFile,\@mapBoxesFields,{});
  }
  if(! %{$p_savedBoxes}) {
    $sLog->log('Unable to load saved map boxes',1);
    return 0;
  }

  touch($p_conf->{''}{instanceDir}.'/mapHashes.dat') unless(-f $p_conf->{''}{instanceDir}.'/mapHashes.dat');
  my $p_mapHashes=loadFastTableFile($sLog,$p_conf->{''}{instanceDir}.'/mapHashes.dat',\@mapHashesFields,{});
  if(! %{$p_mapHashes}) {
    $sLog->log('Unable to load map hashes',1);
    return 0;
  }

  my $p_springLobbyCertificates={''=>{}};
  if(-f "$spadsDir/springLobbyCertificates.dat") {
    $p_springLobbyCertificates=loadFastTableFile($sLog,"$spadsDir/springLobbyCertificates.dat",\@springLobbyCertificatesFields,{});
    if(! %{$p_springLobbyCertificates}) {
      $sLog->log('Unable to load official Spring lobby certificates',1);
      return 0;
    }
  }

  touch($p_conf->{''}{instanceDir}.'/userData.dat') unless(-f $p_conf->{''}{instanceDir}.'/userData.dat');
  my $p_userData=loadFastTableFile($sLog,$p_conf->{''}{instanceDir}.'/userData.dat',\@userDataFieldsOld,{});
  if(! %{$p_userData}) {
    my $savExtension=1;
    while(-f $p_conf->{''}{instanceDir}."/userData.dat.sav$savExtension" && $savExtension < 100) {
      ++$savExtension;
    }
    move($p_conf->{''}{instanceDir}.'/userData.dat',$p_conf->{''}{instanceDir}."/userData.dat.sav$savExtension");
    touch($p_conf->{''}{instanceDir}.'/userData.dat');
    $sLog->log("Unable to load user data, user data file reinitialized (old file renamed to \"userData.dat.sav.$savExtension\")",2);
    $p_userData=loadFastTableFile($sLog,$p_conf->{''}{instanceDir}.'/userData.dat',\@userDataFieldsOld,{});
    if(! %{$p_userData}) {
      $sLog->log('Unable to load user data after file reinitialization, giving up!',1);
      return 0;
    }
  }
  my ($p_accountData,$p_ipIds,$p_nameIds)=buildUserDataCaches($p_userData->{''});

  my $p_mapInfoCache={};
  if(-f $p_conf->{''}{instanceDir}.'/mapInfoCache.dat') {
    $p_mapInfoCache=retrieve($p_conf->{''}{instanceDir}.'/mapInfoCache.dat');
    if(! defined $p_mapInfoCache) {
      $sLog->log('Unable to load map info cache',1);
      return 0;
    }
  }

  my $p_trustedLobbyCertificates={};
  if($sharedDataTs{trustedLobbyCertificates}) {
    $p_trustedLobbyCertificates=initSharedData($sLog,$p_conf,\%sharedDataTs,'trustedLobbyCertificates');
  }else{
    my $trustedLobbyCertificatesFile=$p_conf->{''}{instanceDir}.'/trustedLobbyCertificates.dat';
    if(-f $trustedLobbyCertificatesFile) {
      $p_trustedLobbyCertificates=retrieve($trustedLobbyCertificatesFile);
    }
  }
  if(! defined $p_trustedLobbyCertificates) {
    $sLog->log('Unable to load trusted lobby certificates',1);
    return 0;
  }

  my $self = {
    presets => $p_conf,
    hPresets => $p_hConf,
    bPresets => $p_bConf,
    banLists => $p_banLists,
    mapLists => $p_mapLists,
    commands => $p_commands,
    levels => $p_levels,
    mapBoxes => $p_mapBoxes->{''},
    savedBoxes => $p_savedBoxes->{''},
    mapHashes => $p_mapHashes->{''},
    users => $p_users->{''},
    help => $p_help,
    helpSettings => $p_helpSettings,
    log => $sLog,
    conf => $p_conf->{''},
    values => {},
    hSettings => {},
    hValues => {},
    bSettings => {},
    bValues => {},
    bans => $p_bans->{''},
    preferences => $p_preferences,
    accountData => $p_accountData,
    ipIds => $p_ipIds,
    nameIds => $p_nameIds,
    mapInfo => $p_mapInfoCache,
    maps => {},
    orderedMaps => [],
    ghostMaps => {},
    orderedGhostMaps => [],
    macros => $p_macros,
    pluginsConf => {},
    springLobbyCertificates => $p_springLobbyCertificates->{''},
    trustedLobbyCertificates => $p_trustedLobbyCertificates,
    sharedDataTs => \%sharedDataTs
  };

  bless ($self, $class);

  $self->removeExpiredBans();

  if($self->{conf}{autoLoadPlugins} ne '') {
    my @pluginNames=split(/;/,$self->{conf}{autoLoadPlugins});
    foreach my $pluginName (@pluginNames) {
      if(! $self->loadPluginConf($pluginName)) {
        $self->{log}->log("Unable to load configuration for plugin \"$pluginName\"",1);
        return 0;
      }
    }
  }

  $self->applyPreset($self->{conf}{defaultPreset},1);

  if($p_previousInstance) {
    $self->{conf}=$p_previousInstance->{conf};
    $self->{hSettings}=$p_previousInstance->{hSettings};
    $self->{bSettings}=$p_previousInstance->{bSettings};
    $self->{maps}=$p_previousInstance->{maps};
    $self->{orderedMaps}=$p_previousInstance->{orderedMaps};
    $self->{ghostMaps}=$p_previousInstance->{ghostMaps};
    $self->{orderedGhostMaps}=$p_previousInstance->{orderedGhostMaps};
    foreach my $pluginName (keys %{$p_previousInstance->{pluginsConf}}) {
      $self->{pluginsConf}{$pluginName}=$p_previousInstance->{pluginsConf}{$pluginName} unless(exists $self->{pluginsConf}{$pluginName});
      $self->{pluginsConf}{$pluginName}{conf}=$p_previousInstance->{pluginsConf}{$pluginName}{conf};
    }
  }

  return $self;
}


# Accessor ####################################################################

sub getVersion {
  return $moduleVersion;
}

# Internal functions ##########################################################

sub _acquireLock {
  my ($file,$lockType)=@_;
  if(open(my $lockFh,'>',$file.'.lock')) {
    if(flock($lockFh, $lockType)) {
      return $lockFh;
    }else{
      close($lockFh);
      return undef;
    }
  }else{
    return undef;
  }
}

sub isAbsolutePath {
  my $fileName=shift;
  my $fileSpecRes=File::Spec->file_name_is_absolute($fileName);
  return $fileSpecRes == 2 if($win);
  return $fileSpecRes;
}

sub touch {
  my $file=shift;
  open(TMP,">$file");
  close(TMP);
}

sub aindex (\@$;$) {
  my ($aref, $val, $pos) = @_;
  for ($pos ||= 0; $pos < @$aref; $pos++) {
    return $pos if $aref->[$pos] eq $val;
  }
  return -1;
}

sub checkValue {
  my ($value,$p_types)=@_;
  return 1 unless(@{$p_types});
  foreach my $type (@{$p_types}) {
    my $checkFunction=$paramTypes{$type};
    if(ref($checkFunction)) {
      return 1 if(&{$checkFunction}($value));
    }else{
      return 1 if($value =~ /^$checkFunction$/);
    }
  }
  return 0;
}

sub checkNonEmptyHash {
  foreach my $p_hash (@_) {
    return 0 unless(%{$p_hash});
  }
  return 1;
}

sub roExists {
  my ($r_hash,$r_keys)=@_;
  for my $i (0..$#{$r_keys}) {
    return 0 unless(exists $r_hash->{$r_keys->[$i]});
    $r_hash=$r_hash->{$r_keys->[$i]};
  }
  return 1;
}

sub ipToInt {
  my $ip=shift;
  my $int=0;
  $int=$1*(256**3)+$2*(256**2)+$3*256+$4 if ($ip =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/);
  return $int;
}

sub findMatchingData {
  my ($p_data,$p_filters,$normalSearch)=@_;
  $normalSearch//=1;
  my %data=%{$p_data};
  my @filters=@{$p_filters};
  my @matchingData;
  for my $i (0..$#filters) {
    my @filterData=@{$filters[$i]};
    my %filter=%{$filterData[0]};
    my $matched=1;
    foreach my $field (keys %data) {
      next if($data{$field} eq '');
      if(! (exists $filter{$field} && defined $filter{$field} && $filter{$field} ne '')) {
        next if($normalSearch);
        $matched=0;
        last;
      }
      my @filterFieldValues=split(',',$filter{$field});
      my $matchedField=0;
      my $fieldData=$data{$field};
      $fieldData=$1 if($field eq 'accountId' && $fieldData =~ /^([^\(]+)\(/);
      foreach my $filterFieldValue (@filterFieldValues) {
        if($field eq 'accountId' && $filterFieldValue =~ /^([^\(]+)(\(.*)$/) {
          my ($filterAccountId,$filterUserName)=($1,$2);
          if($fieldData =~ /^\(/) {
            $filterFieldValue=$filterUserName;
          }else{
            $filterFieldValue=$filterAccountId;
          }
        }
        if($normalSearch && $fieldData =~ /^-?\d+(?:\.\d+)?$/ && $filterFieldValue =~ /^(-?\d+(?:\.\d+)?)-(-?\d+(?:\.\d+)?)$/) {
          if($1 <= $fieldData && $fieldData <= $2) {
            $matchedField=1;
            last;
          }
        }elsif($normalSearch && $fieldData =~ /^-?\d+(?:\.\d+)?$/ && $filterFieldValue =~ /^[<>]=?-?\d+(?:\.\d+)?$/) {
          if(eval "$fieldData$filterFieldValue") {
            $matchedField=1;
            last;
          }
        }elsif($normalSearch && $fieldData =~ /^\d+\.\d+\.\d+\.\d+$/ && $filterFieldValue =~ /^(\d+\.\d+\.\d+\.\d+)\-(\d+\.\d+\.\d+\.\d+)$/) {
          my ($startIp,$endIp)=(ipToInt($1),ipToInt($2));
          my $ip=ipToInt($fieldData);
          if($startIp <= $ip && $ip <= $endIp) {
            $matchedField=1;
            last;
          }
        }elsif($normalSearch && $filterFieldValue =~ /^~(.*)$/ && $fieldData =~ /^$1$/) {
          $matchedField=1;
          last;
        }elsif($fieldData eq $filterFieldValue) {
          $matchedField=1;
          last;
        }elsif($field eq 'status' && $fieldData eq 'playing' && $filterFieldValue eq 'player') {
          $matchedField=1;
          last;
        }
      }
      $matched=$matchedField;
      last unless($matched);
    }
    push(@matchingData,$filters[$i][1]) if($matched);
  }
  return \@matchingData;
}

sub mergeMapArrays {
  my ($p_orderedMaps,$p_orderedGhostMaps)=@_;

  my $maxIndex=-1;
  $maxIndex=$#{$p_orderedMaps} if(defined $p_orderedMaps);
  $maxIndex=$#{$p_orderedGhostMaps} if(defined $p_orderedGhostMaps && $#{$p_orderedGhostMaps} > $maxIndex);

  my @array;
  for my $i (0..$maxIndex) {
    push(@array,@{$p_orderedMaps->[$i]}) if(defined $p_orderedMaps && defined $p_orderedMaps->[$i]);
    push(@array,@{$p_orderedGhostMaps->[$i]}) if(defined $p_orderedGhostMaps && defined $p_orderedGhostMaps->[$i]);
  }

  return \@array;
}

# Internal functions - Configuration ##########################################

sub preProcessConfFile {
  my ($sLog,$p_content,$file,$p_macros,$p_alreadyLoaded)=@_;
  $p_alreadyLoaded->{$file}=1;
  my $fh=new FileHandle($file,'r');
  if(! defined $fh) {
    $sLog->log("Unable to read configuration file ($file: $!)",1);
    return 0;
  }
  while(local $_ = <$fh>) {
    foreach my $macroName (keys %{$p_macros}) {
      s/\%$macroName\%/$p_macros->{$macroName}/g;
    }
    if(/^\{(.*)\}$/) {
      my $subConfFile=$1;
      if(($win && $subConfFile !~ /^[a-zA-Z]\:/) || (! $win && $subConfFile !~ /^\//)) {
        my $etcPath=dirname($file);
        $subConfFile=$etcPath.'/'.$subConfFile;
      }
      if(exists $p_alreadyLoaded->{$subConfFile}) {
        $fh->close();
        $sLog->log("Recursive include of $subConfFile (from $file)",1);
        return 0;
      }
      if(! preProcessConfFile($sLog,$p_content,$subConfFile,$p_macros,$p_alreadyLoaded)) {
        $fh->close();
        return 0;
      }
    }else{
      push(@{$p_content},$_);
    }
  }
  $fh->close();
  delete $p_alreadyLoaded->{$file};
  return 1;
}

sub loadSettingsFile {
  my ($sLog,$cFile,$p_globalParams,$p_sectionParams,$p_macros,$caseInsensitiveNoCheck,$overwriteMacrosPrefix)=@_;

  $caseInsensitiveNoCheck//=0;
  my $currentSection='';
  my %newConf=('' => {});

  my @confData;
  return {} unless(preProcessConfFile($sLog,\@confData,$cFile,$p_macros,{}));

  my @invalidGlobalParams;
  my @invalidSectionParams;
  while(local $_ = shift(@confData)) {
    next if(/^\s*(\#.*)?$/);
    if(/^\s*\[([^\]]+)\]\s*$/) {
      $currentSection=$1;
      $newConf{$currentSection}={} unless(exists $newConf{$currentSection});
      next;
    }elsif(/^([^:]+):\s*((?:.*[^\s])?)\s*$/) {
      my ($param,$value)=($1,$2);
      $param=lc($param) if($caseInsensitiveNoCheck);
      $value=$p_macros->{"$overwriteMacrosPrefix:$param"} if(defined $overwriteMacrosPrefix && exists $p_macros->{"$overwriteMacrosPrefix:$param"});
      if($currentSection) {
        if(! exists $p_sectionParams->{$param}) {
          if(!$caseInsensitiveNoCheck) {
            $sLog->log("Ignoring invalid section parameter ($param)",2);
            next;
          }
        }
        my @values=split(/\|/,$value);
        $values[0]//='';
        if(exists $p_sectionParams->{$param}) {
          foreach my $v (@values) {
            if(! checkValue($v,$p_sectionParams->{$param})) {
              push(@invalidSectionParams,$param);
              last;
            }
          }
        }
        if(exists $newConf{$currentSection}{$param}) {
          $sLog->log("Duplicate parameter definitions in configuration file \"$cFile\" (section \"$currentSection\", parameter \"$param\")",2);
        }
        $newConf{$currentSection}{$param}=\@values;
      }else{
        if(! exists $p_globalParams->{$param}) {
          $sLog->log("Ignoring invalid global parameter ($param)",2);
          next;
        }
        push(@invalidGlobalParams,$param) unless(checkValue($value,$p_globalParams->{$param}));
        if(exists $newConf{''}{$param}) {
          $sLog->log("Duplicate parameter definitions in configuration file \"$cFile\" (parameter \"$param\")",2);
        }
        $newConf{''}{$param}=$value;
      }
      next;
    }else{
      chomp($_);
      $sLog->log("Ignoring invalid configuration line in file \"$cFile\" ($_)",2);
      next;
    }
  }

  if(@invalidGlobalParams) {
    $sLog->log("Configuration file \"$cFile\" contains inconsistent values for following global parameter(s): ".join(',',@invalidGlobalParams),1);
    return {};
  }

  if(@invalidSectionParams) {
    $sLog->log("Configuration file \"$cFile\" contains inconsistent values for following section parameter(s): ".join(',',@invalidSectionParams),1);
    return {};
  }

  my %inheritedSections;
  foreach my $section (keys %newConf) {
    next unless($section =~ /^(.+)<(.+)>$/);
    my ($sectionName,$inheritedSectionsString)=($1,$2);
    if(exists $newConf{$sectionName}) {
      $sLog->log("Configuration file \"$cFile\" contains multiple inconsistent preset inheritances for preset \"$sectionName\"",1);
      return {};
    }
    my @inheritedSectionsList=split(',',$inheritedSectionsString);
    $inheritedSections{$sectionName}=\@inheritedSectionsList;
    $newConf{$sectionName}=delete $newConf{$section};
  }

  foreach my $section (keys %inheritedSections) {
    my $r_inherits=flattenSectionInheritance(\%inheritedSections,$section);
    shift(@{$r_inherits});
    my @invalidInheritedSections;
    foreach my $inheritedSection (@{$r_inherits}) {
      if(! exists $newConf{$inheritedSection}) {
        push(@invalidInheritedSections,$inheritedSection);
        next;
      }
      foreach my $param (keys %{$newConf{$inheritedSection}}) {
        $newConf{$section}{$param}//=$newConf{$inheritedSection}{$param};
      }
    }
    if(@invalidInheritedSections) {
     $sLog->log("Configuration file \"$cFile\" contains invalid inheritance for preset \"$section\": ".(join(', ',@invalidInheritedSections)),1);
     return {};
    }
  }

  
  return \%newConf;
}

sub flattenSectionInheritance {
  my ($r_inheritances,$section,$r_alreadyInherited)=@_;
  $r_alreadyInherited//={};
  return [] if(exists $r_alreadyInherited->{$section});
  my @flattenedInheritance=($section);
  $r_alreadyInherited->{$section}=1;
  if(exists $r_inheritances->{$section}) {
    map {my $r_subInherits=flattenSectionInheritance($r_inheritances,$_,$r_alreadyInherited); push(@flattenedInheritance,@{$r_subInherits})} @{$r_inheritances->{$section}};
  }
  return \@flattenedInheritance;
}

sub loadTableFile {
  my ($sLog,$cFile,$p_fieldsArrays,$p_macros,$caseInsensitive)=@_;
  $caseInsensitive//=0;

  my @confData;
  return {} unless(preProcessConfFile($sLog,\@confData,$cFile,$p_macros,{}));

  my @pattern;
  my $section='';
  my %newConf=('' => []);

  while(local $_ = shift(@confData)) {
    my $line=$_;
    chomp($line);
    if(/^\s*\#\?\s*([^\s]+)\s*$/) {
      my $patternString=$1;
      my @subPatternStrings=split(/\|/,$patternString);
      @pattern=();
      for my $i (0..$#subPatternStrings) {
        my @splitSubPattern=split(/\:/,$subPatternStrings[$i]);
        $pattern[$i]=\@splitSubPattern;
      }
      if($#pattern != $#{$p_fieldsArrays}) {
        $sLog->log("Invalid pattern \"$line\" in configuration file \"$cFile\" (number of fields invalid)",1);
        return {};
      }
      for my $index (0..$#pattern) {
        my @fields=@{$pattern[$index]};
        foreach my $field (@fields) {
          if(none {$field eq $_} @{$p_fieldsArrays->[$index]}) {
            $sLog->log("Invalid pattern \"$line\" in configuration file \"$cFile\" (invalid field: \"$field\")",1);
            return {};
          }
        }
      }
      next;
    }
    next if(/^\s*(\#.*)?$/);
    if(/^\s*\[([^\]]+)\]\s*$/) {
      $section=$1;
      $section=lc($section) if($caseInsensitive);
      if(exists $newConf{$section}) {
        $sLog->log("Duplicate section definitions in configuration file \"$cFile\" ($section)",2);
      }else{
        $newConf{$section}=[];
      }
      next;
    }
    if(! @pattern) {
      $sLog->log("No pattern defined for data \"$line\" in configuration file \"$cFile\"",1);
      return {};
    }
    my $p_data=parseTableLine($sLog,\@pattern,$line);
    if(@{$p_data}) {
      push(@{$newConf{$section}},$p_data);
    }else{
      $sLog->log("Invalid configuration line in file \"$cFile\" ($line)",1);
      return {};
    }
  }

  return \%newConf;

}

sub parseTableLine {
  my ($sLog,$p_pattern,$line,$iter)=@_;
  $iter//=0;
  my $p_subPattern=$p_pattern->[$iter];
  my $subPatSize=$#{$p_subPattern};
  my %hashData;
  for my $index (0..($subPatSize-1)) {
    if($line =~ /^([^:]*):(.*)$/) {
      $hashData{$p_subPattern->[$index]}=$1;
      $line=$2;
    }else{
      $sLog->log("Unable to parse fields in following configuration data \"$line\"",1);
      return [];
    }
  }
  if($line =~ /^([^\|]*)\|(.*)$/) {
    $hashData{$p_subPattern->[$subPatSize]}=$1;
    $line=$2;
  }else{
    $hashData{$p_subPattern->[$subPatSize]}=$line;
    $line='';
  }
  my @data=(\%hashData);
  if($iter < $#{$p_pattern}) {
    my $p_data=parseTableLine($sLog,$p_pattern,$line,++$iter);
    return [] unless(@{$p_data});
    push(@data,@{$p_data});
  }
  return \@data;
}

sub loadSimpleTableFile {
  my ($sLog,$cFile,$p_macros,$caseInsensitive)=@_;
  $caseInsensitive//=0;

  my @confData;
  return {} unless(preProcessConfFile($sLog,\@confData,$cFile,$p_macros,{}));

  my $section='';
  my %newConf=('' => []);

  while(local $_ = shift(@confData)) {
    my $line=$_;
    next if(/^\s*(\#.*)?$/);
    if(/^\s*\[([^\]]+)\]\s*$/) {
      $section=$1;
      $section=lc($section) if($caseInsensitive);
      $newConf{$section}=[] unless(exists $newConf{$section});
      next;
    }
    chomp($line);
    if($section) {
      push(@{$newConf{$section}},$line);
    }else{
      $sLog->log("Invalid configuration file \"$cFile\" (missing section declaration)",1);
      return {};
    }
  }

  return \%newConf;
}

sub loadFastTableFile {
  my ($sLog,$cFile,$p_fieldsArrays,$p_macros)=@_;
  my @confData;

  return {} unless(preProcessConfFile($sLog,\@confData,$cFile,$p_macros,{}));

  my @pattern;
  my %newConf;

  while(local $_ = shift(@confData)) {
    my $line=$_;
    chomp($line);
    if(/^\s*\#\?\s*([^\s]+)\s*$/) {
      my $patternString=$1;
      my @subPatternStrings=split(/\|/,$patternString);
      @pattern=();
      for my $i (0..$#subPatternStrings) {
        my @splitSubPattern=split(/\:/,$subPatternStrings[$i]);
        $pattern[$i]=\@splitSubPattern;
      }
      if($#pattern != $#{$p_fieldsArrays}) {
        $sLog->log("Invalid pattern \"$line\" in configuration file \"$cFile\" (number of fields invalid)",1);
        return {};
      }
      for my $index (0..$#pattern) {
        my @fields=@{$pattern[$index]};
        foreach my $field (@fields) {
          if(none {$field eq $_} @{$p_fieldsArrays->[$index]}) {
            $sLog->log("Invalid pattern \"$line\" in configuration file \"$cFile\" (invalid field: \"$field\")",1);
            return {};
          }
        }
      }
      next;
    }
    next if(/^\s*(?:\#.*)?$/);
    my @subDataStrings=split(/\|/,$line,-1);
    if($#subDataStrings != $#pattern) {
      $sLog->log("Invalid number of fields in file \"$cFile\" ($line)",1);
      return {};
    }
    my $p_nextKeyData=\%newConf;
    for my $index (0..$#pattern) {
      my @fields=split(/\:/,$subDataStrings[$index],-1);
      if($#fields != $#{$pattern[$index]}) {
        $sLog->log("Invalid number of subfields in file \"$cFile\" ($line)",1);
        return {};
      }
      if($index == 0) {
        foreach my $keyVal (@fields) {
          $keyVal =~ s/\t<COLON>/:/g;
          $keyVal =~ s/\t<PIPE>/\|/g;
          $p_nextKeyData->{$keyVal}={} unless(exists $p_nextKeyData->{$keyVal});
          $p_nextKeyData=$p_nextKeyData->{$keyVal};
        }
      }else{
        $sLog->log("Duplicate entry in file \"$cFile\" ($line)",2) if(%{$p_nextKeyData});
        foreach my $fieldIndex (0..$#{$pattern[$index]}) {
          my $dataVal=$fields[$fieldIndex];
          $dataVal =~ s/\t<COLON>/:/g;
          $dataVal =~ s/\t<PIPE>/\|/g;
          $p_nextKeyData->{$pattern[$index][$fieldIndex]}=$dataVal;
        }
      }
    }
  }
  return {'' => \%newConf};
}

sub loadHelpSettingsFile {
  my ($sLog,$cFile,$p_macros)=@_;
  my $p_helpSettingsRaw=loadSimpleTableFile($sLog,$cFile,$p_macros);
  return {} unless(%{$p_helpSettingsRaw});
  my %helpSettings=();
  foreach my $setting (keys %{$p_helpSettingsRaw}) {
    next if($setting eq '');
    if($setting =~ /^(\w+):(\w+)$/) {
      my ($type,$name,$nameLc)=(lc($1),$2,lc($2));
      $helpSettings{$type}={} unless(exists $helpSettings{$type});
      if(exists $helpSettings{$type}{$nameLc}) {
        $sLog->log("Duplicate \"$type:$nameLc\" setting definition in help file \"$cFile\"",2);
      }else{
        $helpSettings{$type}{$nameLc}={};
      }
      $helpSettings{$type}{$nameLc}{name}=$name;
      my @content;
      my $index=0;
      $content[$index]=[];
      foreach my $helpLine (@{$p_helpSettingsRaw->{$setting}}) {
        if($helpLine eq '-') {
          $index++;
          $content[$index]=[];
          next;
        }
        push(@{$content[$index]},$helpLine);
      }
      $helpSettings{$type}{$nameLc}{explicitName}=$content[0];
      $helpSettings{$type}{$nameLc}{description}=$content[1];
      $helpSettings{$type}{$nameLc}{format}=$content[2];
      $helpSettings{$type}{$nameLc}{default}=$content[3];
    }else{
      $sLog->log("Invalid help section \"$setting\" in file \"$cFile\"",1);
      return {};
    }
  }
  return \%helpSettings;
}

sub loadPluginConf {
  my ($self,$pluginName)=@_;
  if(! exists $self->{pluginsConf}{$pluginName}) {
    unshift(@INC,$self->{conf}{pluginsDir}) unless(any {$self->{conf}{pluginsDir} eq $_} @INC);
    eval "use $pluginName";
    if($@) {
      $self->{log}->log("Unable to load plugin module \"$pluginName\": $@",1);
      return 0;
    }
    my $hasConf;
    eval "\$hasConf=$pluginName->can('getParams')";
    return 1 unless($hasConf);
  }
  my $p_pluginParams;
  eval "\$p_pluginParams=$pluginName->getParams()";
  if($@) {
    $self->{log}->log("Unable to get parameters for plugin \"$pluginName\": $@",1);
    return 0;
  }
  my ($p_globalParams,$p_presetParams)=@{$p_pluginParams};
  $p_globalParams//={};
  $p_presetParams//={};
  return 1 unless(%{$p_globalParams} || %{$p_presetParams});
  my $p_pluginPresets = loadSettingsFile($self->{log},"$self->{conf}{etcDir}/$pluginName.conf",$p_globalParams,$p_presetParams,$self->{macros});
  if(%{$p_presetParams} && ! exists $p_pluginPresets->{$self->{conf}{defaultPreset}} && exists $p_pluginPresets->{'_DEFAULT_'}) {
    $p_pluginPresets->{$self->{conf}{defaultPreset}}=$p_pluginPresets->{'_DEFAULT_'};
  }
  return 0 unless($self->checkPluginConfig($pluginName,$p_pluginPresets,$p_globalParams,$p_presetParams));
  my ($p_commands,$p_help)=({},{});
  if(exists $p_pluginPresets->{''}{commandsFile}) {
    my $commandsFile=$p_pluginPresets->{''}{commandsFile};
    $p_commands=loadTableFile($self->{log},$self->{conf}{etcDir}."/$commandsFile",\@commandsFields,$self->{macros},1);
    if(! exists $p_pluginPresets->{''}{helpFile}) {
      $self->{log}->log("A commands file without associated help file is defined for plugin $pluginName",1);
      return 0;
    }
    my $helpFile=$p_pluginPresets->{''}{helpFile};
    $p_help=loadSimpleTableFile($self->{log},$self->{conf}{pluginsDir}."/$helpFile",$self->{macros},1);
    if(! checkNonEmptyHash($p_commands,$p_help)) {
      $self->{log}->log("Unable to load commands, help and permission system for plugin $pluginName",1);
      return 0;
    }
  }
  $self->{log}->log("Reloading configuration of plugin $pluginName",4) if(exists $self->{pluginsConf}{$pluginName});
  $self->{pluginsConf}{$pluginName}={ presets => $p_pluginPresets,
                                      commands => $p_commands,
                                      help => $p_help,
                                      conf => $p_pluginPresets->{''},
                                      values => {} };
  return 1;
}

sub checkPluginConfig {
  my ($self,$pluginName,$p_conf,$p_globalParams,$p_presetParams)=@_;
  my $sLog=$self->{log};

  return 0 unless(defined $p_conf && %{$p_conf});

  my @missingParams;
  foreach my $requiredGlobalParam (keys %{$p_globalParams}) {
    if(! exists $p_conf->{''}{$requiredGlobalParam}) {
      push(@missingParams,$requiredGlobalParam);
    }
  }
  if(@missingParams) {
    my $mParams=join(',',@missingParams);
    $sLog->log("Incomplete plugin configuration for $pluginName (missing global parameters: $mParams)",1);
    return 0;
  }

  if(%{$p_presetParams}) {
    my $defaultPreset=$self->{conf}{defaultPreset};
    if(! exists $p_conf->{$defaultPreset}) {
      $sLog->log("Invalid plugin configuration for $pluginName: default preset \"$defaultPreset\" does not exist",1);
      return 0;
    }
    foreach my $requiredSectionParam (keys %{$p_presetParams}) {
      push(@missingParams,$requiredSectionParam) unless(exists $p_conf->{$defaultPreset}{$requiredSectionParam});
    }
    if(@missingParams) {
      my $mParams=join(',',@missingParams);
      $sLog->log("Incomplete plugin configuration for $pluginName (missing parameter(s) in default preset: $mParams)",1);
      return 0;
    }
  }

  return 1;
}

sub checkSpadsConfig {
  my ($sLog,$p_conf)=@_;

  return 0 unless(%{$p_conf});

  my @missingParams;
  foreach my $requiredGlobalParam (keys %globalParameters) {
    if(! exists $p_conf->{''}{$requiredGlobalParam}) {
      push(@missingParams,$requiredGlobalParam);
    }
  }
  if(@missingParams) {
    my $mParams=join(',',@missingParams);
    $sLog->log("Incomplete SPADS configuration (missing global parameters: $mParams)",1);
    return 0;
  }
  my $defaultPreset=$p_conf->{''}{defaultPreset};
  if(! exists $p_conf->{$defaultPreset}) {
    $sLog->log("Invalid SPADS configuration: default preset \"$defaultPreset\" does not exist",1);
    return 0;
  }
  foreach my $requiredSectionParam (keys %spadsSectionParameters) {
    if(! exists $p_conf->{$defaultPreset}{$requiredSectionParam}) {
      push(@missingParams,$requiredSectionParam);
    }
  }
  if(@missingParams) {
    my $mParams=join(',',@missingParams);
    $sLog->log("Incomplete SPADS configuration (missing parameter(s) in default preset: $mParams)",1);
    return 0;
  }
  foreach my $preset (keys %{$p_conf}) {
    next if($preset eq '');
    if(exists $p_conf->{$preset}{preset} && $p_conf->{$preset}{preset}[0] ne $preset) {
      $sLog->log("The default value of parameter \"preset\" ($p_conf->{$preset}{preset}[0]) must be the name of the preset ($preset)",1);
      return 0;
    }
  }

  my @relDirParams=(['etcDir'],
                    ['varDir'],
                    ['instanceDir','varDir'],
                    ['logDir','instanceDir'],
                    ['pluginsDir','varDir'],
                    ['autoManagedSpringDir','varDir']);
  foreach my $r_relDirParam (@relDirParams) {
    my ($paramName,$baseParam)=@{$r_relDirParam};
    my $baseDir = defined $baseParam ? $p_conf->{''}{$baseParam} : $spadsDir;
    my $realValue=$p_conf->{''}{$paramName};
    my $fixedValue = isAbsolutePath($realValue) ? $realValue : File::Spec->catdir($baseDir,$realValue);
    my $errorMsg;
    if(! -d $fixedValue) {
      $errorMsg='not a directory';
    }elsif(! -x $fixedValue) {
      $errorMsg='not a traversable directory';
    }elsif(! -r $fixedValue) {
      $errorMsg='not a readable directory';
    }elsif((none {$paramName eq $_} (qw'etcDir pluginsDir')) && ! -w $fixedValue) {
      $errorMsg='not a writable directory';
    }
    if($errorMsg) {
      $sLog->log("Invalid value \"$realValue\" for $paramName global setting: $errorMsg",1);
      return 0;
    }
    $p_conf->{''}{$paramName}=$fixedValue;
  }

  { # special checks for autoManagedSpringVersion setting
    my $springIsAutomanaged=$p_conf->{''}{autoManagedSpringVersion} ne '';
    if($springIsAutomanaged && $macOs) {
      $sLog->log('Spring version auto-management isn\'t available on macOS, the "autoManagedSpringVersion" setting must be empty',1);
      return 0;
    }
    my @badParams;
    foreach my $dependantParam (qw'unitsyncDir springServer') {
      push(@badParams,$dependantParam) if(($p_conf->{''}{$dependantParam} ne '') == $springIsAutomanaged);
    }
    if(@badParams) {
      my $badParamsString=join('" and "',@badParams);
      $sLog->log("The \"$badParamsString\" setting".($#badParams>0?'s':'').' must '.($springIsAutomanaged?'not ':'').'be defined when Spring version auto-management is '.($springIsAutomanaged?'enabled':'disabled'),1);
      return 0;
    }
    if($springIsAutomanaged && $p_conf->{''}{springServerType} eq '') {
      $sLog->log('The "springServerType" setting must be defined when Spring version auto-management is enabled',1);
      return 0;
    }
  }

  return 1;
}

sub checkHConfig {
  my ($sLog,$p_conf,$p_hConf)=@_;

  return 0 unless(%{$p_conf});

  my $defaultPreset=$p_conf->{''}{defaultPreset};
  my $defaultHPreset=$p_conf->{$defaultPreset}{hostingPreset}[0];
  if(! exists $p_hConf->{$defaultHPreset}) {
    $sLog->log("Invalid hosting settings configuration: default hosting preset \"$defaultHPreset\" does not exist",1);
    return 0;
  }
  my @missingParams;
  foreach my $requiredParam (keys %hostingParameters) {
    if(! exists $p_hConf->{$defaultHPreset}{$requiredParam}) {
      push(@missingParams,$requiredParam);
    }
  }
  if(@missingParams) {
    my $mParams=join(',',@missingParams);
    $sLog->log("Incomplete hosting settings configuration (missing parameter(s) in default hosting preset: $mParams)",1);
    return 0;
  }

  return 1;
}

sub checkBConfig {
  my ($sLog,$p_conf,$p_bConf)=@_;

  return 0 unless(%{$p_conf});

  my $defaultPreset=$p_conf->{''}{defaultPreset};
  my $defaultBPreset=$p_conf->{$defaultPreset}{battlePreset}[0];
  if(! exists $p_bConf->{$defaultBPreset}) {
    $sLog->log("Invalid battle settings configuration: default battle preset \"$defaultBPreset\" does not exist",1);
    return 0;
  }
  my @missingParams;
  foreach my $requiredParam (keys %battleParameters) {
    if(! exists $p_bConf->{$defaultBPreset}{$requiredParam}) {
      push(@missingParams,$requiredParam);
    }
  }
  if(@missingParams) {
    my $mParams=join(',',@missingParams);
    $sLog->log("Incomplete battle settings configuration (missing parameter(s) in default preset: $mParams)",1);
    return 0;
  }

  return 1;
}

sub checkConfigLists {
  my ($sLog,$p_conf,$p_banLists,$p_mapLists)=@_;

  my $defaultPreset=$p_conf->{''}{defaultPreset};
  my $banList=$p_conf->{$defaultPreset}{banList}[0];
  my $mapList=$p_conf->{$defaultPreset}{mapList}[0];

  if(! exists $p_banLists->{$banList}) {
    $sLog->log("Invalid banList configuration: default banList \"$banList\" does not exist",1);
    return 0;
  }

  if(! exists $p_mapLists->{$mapList}) {
    $sLog->log("Invalid mapList configuration: default mapList \"$mapList\" does not exist",1);
    return 0;
  }

  return 1;
}

sub pruneExpiredBans {
  my $self=shift;
  my $nbPrunedBans=0;
  my $p_banLists=$self->{banLists};
  foreach my $section (keys %{$p_banLists}) {
    my @filters=@{$p_banLists->{$section}};
    my @newFilters=();
    for my $i (0..$#filters) {
      if(exists $filters[$i][1]{endDate} && defined $filters[$i][1]{endDate} && $filters[$i][1]{endDate} ne '' && $filters[$i][1]{endDate} < time) {
        $nbPrunedBans++;
      }else{
        push(@newFilters,$filters[$i]);
      }
    }
    $p_banLists->{$section}=\@newFilters;
  }
  return $nbPrunedBans;
}

# Internal functions - Dynamic data ###########################################

sub dumpFastTable {
  my ($self,$p_data,$file,$p_fields)=@_;

  if(! open(TABLEFILE,">$file")) {
    $self->{log}->log("Unable to write to file \"$file\"",1);
    return 0;
  }

  print TABLEFILE <<EOH;
# Warning, this file is updated automatically by SPADS.
# Any modifications performed on this file while SPADS is running will be automatically erased.
  
EOH

  my $templateLine=join(':',@{$p_fields->[0]}).'|'.join(':',@{$p_fields->[1]});
  print TABLEFILE "#?$templateLine\n";

  my $p_rows=$self->printFastTable($p_data,$p_fields,1);
  foreach my $line (@{$p_rows}) {
    print TABLEFILE "$line\n";
  }
  close TABLEFILE;

  $self->{log}->log("File \"$file\" dumped",4);

  return 1;
}

sub printFastTable {
  my ($self,$p_data,$p_fields,$isFirst)=@_;
  $isFirst//=0;
  my @indexFields=@{$p_fields->[0]};
  my @dataFields=@{$p_fields->[1]};
  if(@indexFields) {
    my @result;
    shift @indexFields;
    foreach my $k (sort keys %{$p_data}) {
      my $p_subResults=$self->printFastTable($p_data->{$k},[\@indexFields,\@dataFields]);
      my $sep=':';
      $sep='' if($isFirst);
      $k =~ s/:/\t<COLON>/g;
      $k =~ s/\|/\t<PIPE>/g;
      my @keyResults=map {"$sep$k".$_} @{$p_subResults};
      push(@result,@keyResults);
    }
    return \@result;
  }else{
    my @dataFieldsValues=map {$p_data->{$_}} @dataFields;
    for my $i (0..$#dataFieldsValues) {
      $dataFieldsValues[$i]//='';
      $dataFieldsValues[$i] =~ s/:/\t<COLON>/g;
      $dataFieldsValues[$i] =~ s/\|/\t<PIPE>/g;
    }
    my $result=join(':',@dataFieldsValues);
    return ["|$result"];
  }
}

sub initSharedData {
  my ($sLog,$p_conf,$r_sharedDataTs,$sharedData)=@_;
  my $dataStorageType=$shareableData{$sharedData}{type};
  my $isCustomStorageType = $dataStorageType ne 'binary';
  my $r_data;
  $r_data={} if($isCustomStorageType);
  my ($privateFile,$sharedFile)=map {$p_conf->{''}{$_}."/$sharedData.dat"} (qw'instanceDir varDir');
  if(-f $sharedFile) {
    $sLog->log("Loading shared $sharedData data from shared file",5);
    if(my $lock=_acquireLock($sharedFile,LOCK_SH)) {
      $r_data=loadShareableData($sLog,$sharedFile,$sharedData);
      $r_sharedDataTs->{$sharedData}=(Time::HiRes::stat($sharedFile))[9];
      close($lock);
    }else{
      $sLog->log("Failed to acquire lock on shared file to load $sharedData data",1);
    }
  }elsif(-f $privateFile) {
    $sLog->log("Initializing shared $sharedData data from private file",3);
    if(my $lock=_acquireLock($sharedFile,LOCK_EX)) {
      if(-f $sharedFile) {
        $sLog->log("A shared file has appeared meanwhile for shared $sharedData data, loading data directly from shared file instead",3);
        $r_data=loadShareableData($sLog,$sharedFile,$sharedData);
        $r_sharedDataTs->{$sharedData}=(Time::HiRes::stat($sharedFile))[9];
      }else{
        $r_data=loadShareableData($sLog,$privateFile,$sharedData);
        if(($isCustomStorageType && %{$r_data})
           || (! $isCustomStorageType && defined $r_data)) {
          if(copy($privateFile,$sharedFile)) {
            $r_sharedDataTs->{$sharedData}=(Time::HiRes::stat($sharedFile))[9];
          }else{
            $sLog->log("Failed to initialize shared $sharedData data from private file: $!",2);
          }
        }else{
          $sLog->log("Failed to load private $sharedData data to initialize shared data",1);
        }
      }
      close($lock);
    }else{
      $sLog->log("Failed to acquire lock on shared file to load $sharedData data",1);
    }
  }elsif($isCustomStorageType) {
    $sLog->log("Initializing empty shared $sharedData data",3);
    if(my $lock=_acquireLock($sharedFile,LOCK_EX)) {
      if(-f $sharedFile) {
        $sLog->log("A shared file has appeared meanwhile for shared $sharedData data, loading data from shared file instead",3);
      }else{
        touch($sharedFile);
      }
      $r_data=loadShareableData($sLog,$sharedFile,$sharedData);
      $r_sharedDataTs->{$sharedData}=(Time::HiRes::stat($sharedFile))[9];
      close($lock);
    }else{
      $sLog->log("Failed to acquire lock on shared file to load $sharedData data",1);
    }
  }else{
    $r_data={};
    $sLog->log("No $sharedData data found",5);
  }
  return $r_data;
}

sub loadShareableData {
  my ($sLog,$file,$sharedData)=@_;
  my ($dataStorageType,$r_fields)=@{$shareableData{$sharedData}}{qw'type fields'};
  if($dataStorageType eq 'fastTable') {
    return loadFastTableFile($sLog,$file,$r_fields,{});
  }elsif($dataStorageType eq 'table') {
    return loadTableFile($sLog,$file,$r_fields,{});
  }elsif($dataStorageType eq 'binary') {
    return retrieve($file);
  }else{
    $sLog->log("Unable to load data \"$sharedData\" (not a shareable data)",0);
    return undef;
  }
}

sub refreshAndLockSharedDataForUpdate {
  my ($self,$sharedData)=@_;
  my $sharedFile="$self->{conf}{varDir}/$sharedData.dat";
  if(my $lock = _acquireLock($sharedFile,LOCK_EX)) {
    if(-f $sharedFile && (Time::HiRes::stat($sharedFile))[9] > $self->{sharedDataTs}{$sharedData}) {
      $self->{log}->log("Shared file \"$sharedData.dat\" has been modified, refreshing data before update",5);
      my $r_refreshedData;
      my $r_loadedData=loadShareableData($self->{log},$sharedFile,$sharedData);
      if($shareableData{$sharedData}{type} eq 'binary') {
        $r_refreshedData = defined $r_loadedData ? {'' => $r_loadedData} : {};
      }else{
        $r_refreshedData=$r_loadedData;
      }
      if(! %{$r_refreshedData}) {
        $self->{log}->log("Unable to update $sharedData data (failed to refresh data from shared file before update)",1);
        close($lock);
        return undef;
      }
      $self->{$sharedData}=$r_refreshedData->{''};
      $self->{sharedDataTs}{$sharedData}=(Time::HiRes::stat($sharedFile))[9];
    }
    return $lock;
  }else{
    $self->{log}->log("Unable to update $sharedData data (failed to acquire lock on shared file)",1);
    return undef;
  }
}

sub updateAndUnlockSharedData {
  my ($self,$sharedData,$lock)=@_;
  my $sharedFile="$self->{conf}{varDir}/$sharedData.dat";
  my $res;
  if($shareableData{$sharedData}{type} eq 'fastTable') {
    $res=$self->dumpFastTable($self->{$sharedData},$sharedFile,$shareableData{$sharedData}{fields});
  }elsif($shareableData{$sharedData}{type} eq 'table') {
    $res=$self->dumpTable($self->{$sharedData},$sharedFile,$shareableData{$sharedData}{fields});
  }elsif($shareableData{$sharedData}{type} eq 'binary') {
    $res=nstore($self->{$sharedData},$sharedFile);
  }else{
    $self->{log}->log("Unable to update shared data \"$sharedData\", unknown data",0);
    $res=0;
  }
  $self->{sharedDataTs}{$sharedData}=(Time::HiRes::stat($sharedFile))[9] if($res);
  close($lock);
  return $res;
}

# Internal functions - Dynamic data - Preferences #############################

sub preparePreferences {
  my ($sLog,$p_prefs)=@_;
  my %newPrefs;
  foreach my $key (keys %{$p_prefs}) {
    if($key =~ /^(.+)\((.+)\)$/) {
      my ($accountId,$name)=($1,$2);
      my $newKey=$key;
      $newKey=$accountId if($accountId =~ /^\d+$/ && $accountId != 0);
      $newPrefs{$newKey}=$p_prefs->{$key};
      $newPrefs{$newKey}{name}=$name;
    }else{
      $sLog->log("Ignoring invalid preference key \"$key\"",2);
    }
  }
  return \%newPrefs;
}

sub getPrunedRawPreferences {
  my $self=shift;
  my %newPrefs;
  foreach my $key (keys %{$self->{preferences}}) {
    my $keepPrefs=0;
    foreach my $p (keys %{$self->{preferences}{$key}}) {
      next if($p eq 'name' || ($self->{conf}{autoSetVoteMode} && $p eq 'voteMode') || $self->{preferences}{$key}{$p} eq '');
      $keepPrefs=1;
      last;
    }
    next unless($keepPrefs);
    my $newKey=$key;
    $newKey.="($self->{preferences}{$key}{name})" if($key !~ /\)$/);
    $newPrefs{$newKey}={};
    foreach my $p (keys %{$self->{preferences}{$key}}) {
      next if($p eq 'name');
      $newPrefs{$newKey}{$p}=$self->{preferences}{$key}{$p};
    }
  }
  return \%newPrefs;
}

# Internal functions - Dynamic data - User data ###############################

sub buildUserDataCaches {
  my $p_userData=shift;
  my (%accountData,%ipIds,%nameIds);
  foreach my $id (keys %{$p_userData}) {
    $accountData{$id}={};
    $accountData{$id}{country}=$p_userData->{$id}{country};
    $accountData{$id}{lobbyClient}=$p_userData->{$id}{lobbyClient}//'';
    $accountData{$id}{timestamp}=$p_userData->{$id}{timestamp};
    $accountData{$id}{rank}=$p_userData->{$id}{rank};
    $accountData{$id}{ips}={};
    my @idIps=split(' ',$p_userData->{$id}{ips});
    if(@idIps) {
      foreach my $idIp (@idIps) {
        if($idIp =~ /^(\d+(?:\.\d+){3});(\d+)$/) {
          my ($ip,$ts)=($1,$2);
          $accountData{$id}{ips}{$ip}=$ts;
          $ipIds{$ip}={} unless(exists $ipIds{$ip});
          $ipIds{$ip}{$id}=$ts;
        }
      }
    }
    $accountData{$id}{names}={};
    my @idNames=split(' ',$p_userData->{$id}{names});
    if(@idNames) {
      foreach my $idName (@idNames) {
        if($idName =~ /^([\w\[\]]+);(\d+)$/) {
          my ($name,$ts)=($1,$2);
          $accountData{$id}{names}{$name}=$ts;
          $nameIds{$name}={} unless(exists $nameIds{$name});
          $nameIds{$name}{$id}=$ts;
        }
      }
    }
  }
  return (\%accountData,\%ipIds,\%nameIds);
}

sub flushUserDataCache {
  my $self=shift;
  my %userData;
  my $p_accountData=$self->{accountData};
  $self->{ipIds}={};
  $self->{nameIds}={};
  my ($userDataRetentionPeriod,$userIpRetention,$userNameRetention)=(-1,-1,-1);
  $userDataRetentionPeriod=$1 if($self->{conf}{userDataRetention} =~ /^(\d+);/);
  $userIpRetention=$1 if($self->{conf}{userDataRetention} =~ /;(\d+);/);
  $userNameRetention=$1 if($self->{conf}{userDataRetention} =~ /;(\d+)$/);
  foreach my $id (keys %{$p_accountData}) {
    my $ts=$p_accountData->{$id}{timestamp};
    if($userDataRetentionPeriod != -1 && time-$ts > $userDataRetentionPeriod * 86400) {
      delete $p_accountData->{$id};
      next;
    }
    $userData{$id}{country}=$p_accountData->{$id}{country};
    $userData{$id}{lobbyClient}=$p_accountData->{$id}{lobbyClient};
    $userData{$id}{timestamp}=$ts;
    $userData{$id}{rank}=$p_accountData->{$id}{rank};
    my @ipData;
    my @sortedUserIps=sort {$p_accountData->{$id}{ips}{$b} <=> $p_accountData->{$id}{ips}{$a}} (keys %{$p_accountData->{$id}{ips}});
    foreach my $ip (@sortedUserIps) {
      my $ipTs=$p_accountData->{$id}{ips}{$ip};
      if(($userIpRetention != -1 && $#ipData + 1 >= $userIpRetention) || ($userDataRetentionPeriod != -1 && time-$ipTs > $userDataRetentionPeriod * 86400)) {
        delete $p_accountData->{$id}{ips}{$ip};
      }else{
        push(@ipData,"$ip;$ipTs");
        $self->{ipIds}{$ip}={} unless(exists $self->{ipIds}{$ip});
        $self->{ipIds}{$ip}{$id}=$ipTs;
      }
    }
    if(@ipData) {
      $userData{$id}{ips}=join(' ',@ipData);
    }else{
      $userData{$id}{ips}='';
    }
    my @nameData;
    my @sortedUserNames=sort {$p_accountData->{$id}{names}{$b} <=> $p_accountData->{$id}{names}{$a}} (keys %{$p_accountData->{$id}{names}});
    foreach my $name (@sortedUserNames) {
      my $nameTs=$p_accountData->{$id}{names}{$name};
      if(($userNameRetention != -1 && $#nameData + 1 > $userNameRetention) || ($userDataRetentionPeriod != -1 && time-$nameTs > $userDataRetentionPeriod * 86400)) {
        delete $p_accountData->{$id}{names}{$name};
      }else{
        push(@nameData,"$name;$nameTs");
        $self->{nameIds}{$name}={} unless(exists $self->{nameIds}{$name});
        $self->{nameIds}{$name}{$id}=$nameTs;
      }
    }
    if(@nameData) {
      $userData{$id}{names}=join(' ',@nameData);
    }else{
      $userData{$id}{names}='';
    }
  }
  return \%userData;
}

# Internal functions - Dynamic data - Bans ####################################

sub removeMatchingData {
  my ($p_data,$p_filters)=@_;
  my %data=%{$p_data};
  my @filters=@{$p_filters};
  my @newFilters;
  for my $i (0..$#filters) {
    my @filterData=@{$filters[$i]};
    my %filter=%{$filterData[0]};
    my $matched=1;
    foreach my $field (keys %data) {
      next if($data{$field} eq '');
      if(! (exists $filter{$field} && defined $filter{$field} && $filter{$field} ne '')) {
        $matched=0;
        last;
      }
      my @filterFieldValues=split(',',$filter{$field});
      my $matchedField=0;
      my $fieldData=$data{$field};
      $fieldData=$1 if($field eq 'accountId' && $fieldData =~ /^([^\(]+)\(/);
      foreach my $filterFieldValue (@filterFieldValues) {
        if($field eq 'accountId' && $filterFieldValue =~ /^([^\(]+)(\(.*)$/) {
          my ($filterAccountId,$filterUserName)=($1,$2);
          if($fieldData =~ /^\(/) {
            $filterFieldValue=$filterUserName;
          }else{
            $filterFieldValue=$filterAccountId;
          }
        }
        if($fieldData eq $filterFieldValue) {
          $matchedField=1;
          last;
        }
      }
      $matched=$matchedField;
      last unless($matched);
    }
    push(@newFilters,$filters[$i]) unless($matched);
  }
  return \@newFilters;
}

sub removeExpiredBans {
  my $self=shift;
  if($self->{sharedDataTs}{bans}) {
    $self->removeSharedExpiredBans();
  }else{
    $self->removePrivateExpiredBans();
  }
}

sub removeSharedExpiredBans {
  my $self=shift;
  my @bans=@{$self->{bans}};
  my $hasExpiredBans=0;
  for my $i (0..$#bans) {
    if(exists $bans[$i][1]{endDate} && defined $bans[$i][1]{endDate} && $bans[$i][1]{endDate} ne '' && $bans[$i][1]{endDate} < time) {
      $hasExpiredBans=1;
      last;
    }
  }
  return unless($hasExpiredBans);
  my $lock=$self->refreshAndLockSharedDataForUpdate('bans')
      or return;
  my $nbRemovedBans=0;
  @bans=@{$self->{bans}};
  my @newBans=();
  for my $i (0..$#bans) {
    if(exists $bans[$i][1]{endDate} && defined $bans[$i][1]{endDate} && $bans[$i][1]{endDate} ne '' && $bans[$i][1]{endDate} < time) {
      $nbRemovedBans++;
    }else{
      push(@newBans,$bans[$i]);
    }
  }
  if($nbRemovedBans) {
    $self->{bans}=\@newBans;
    $self->updateAndUnlockSharedData('bans',$lock);
    $self->{log}->log("$nbRemovedBans expired ban(s) removed from shared file \"bans.dat\"",3);
  }else{
    close($lock);
  }
}

sub removePrivateExpiredBans {
  my $self=shift;
  my $nbRemovedBans=0;
  my @bans=@{$self->{bans}};
  my @newBans=();
  for my $i (0..$#bans) {
    if(exists $bans[$i][1]{endDate} && defined $bans[$i][1]{endDate} && $bans[$i][1]{endDate} ne '' && $bans[$i][1]{endDate} < time) {
      $nbRemovedBans++;
    }else{
      push(@newBans,$bans[$i]);
    }
  }
  if($nbRemovedBans) {
    $self->{bans}=\@newBans;
    $self->dumpTable($self->{bans},$self->{conf}{instanceDir}.'/bans.dat',\@banListsFields);
    $self->{log}->log("$nbRemovedBans expired ban(s) removed from file \"bans.dat\"",3);
  }
}

sub dumpTable {
  my ($self,$p_data,$file,$p_fields)=@_;

  if(! open(TABLEFILE,">$file")) {
    $self->{log}->log("Unable to write to file \"$file\"",1);
    return 0;
  }

  print TABLEFILE <<EOH;
# Warning, this file is updated automatically by SPADS.
# Any modifications performed on this file while SPADS is running will be automatically erased.
  
EOH

  my $templateLine=join(':',@{$p_fields->[0]}).'|'.join(':',@{$p_fields->[1]});
  print TABLEFILE "#?$templateLine\n";

  for my $row (0..$#{$p_data}) {
    my $p_rowData=$p_data->[$row];
    my $invalidData='';
    foreach my $p_rowEntry (@{$p_rowData}) {
      foreach my $field (keys %{$p_rowEntry}) {
        if($p_rowEntry->{$field} =~ /[\:\|]/) {
          $invalidData="invalid value \"$p_rowEntry->{$field}\" for field \"$field\"";
          last;
        }
      }
      last if($invalidData);
    }
    if($invalidData) {
      $self->{log}->log("Skipping entry during dump table ($invalidData)",2);
      next;
    }
    my $line='';
    foreach my $fieldNb (0..$#{$p_fields->[0]}) {
      my $field=$p_fields->[0][$fieldNb];
      $line.=':' if($fieldNb);
      $line.=$p_rowData->[0]{$field} if(exists $p_rowData->[0]{$field} && defined $p_rowData->[0]{$field});
    }
    $line.='|';
    foreach my $fieldNb (0..$#{$p_fields->[1]}) {
      my $field=$p_fields->[1][$fieldNb];
      $line.=':' if($fieldNb);
      $line.=$p_rowData->[1]{$field} if(exists $p_rowData->[1]{$field} && defined $p_rowData->[1]{$field});
    }
    print TABLEFILE "$line\n";
  }
    
  close(TABLEFILE);

  $self->{log}->log("File \"$file\" dumped",4);

  return 1;
}

sub flattenBan {
  my $data=shift;
  return '__UNDEF__' unless(defined $data);
  return $data if(ref($data) eq '');
  if(ref($data) eq 'HASH') {
    my @resArray;
    foreach my $k (sort keys %{$data}) {
      push(@resArray,"$k\->".flattenBan($data->{$k})) if(defined $data->{$k} && (ref($data->{$k}) ne '' || $data->{$k} ne ''));
    }
    return '{'.join(',',@resArray).'}';
  }
  if(ref($data) eq 'ARRAY') {
    my @resArray;
    for my $i (0..$#{$data}) {
      push(@resArray,"$i:".flattenBan($data->[$i]));
    }
    return '['.join(',',@resArray).']';
  }
  return $data;
}

sub banIsDuplicate {
  my ($self,$r_banFilters,$r_banParams)=@_;
  for my $i (0..$#{$self->{bans}}) {
    return 1 if(areSameBans($r_banFilters,$self->{bans}[$i][0],0) && areSameBans($r_banParams,$self->{bans}[$i][1],1));
  }
  return 0;
}

sub areSameBans {
  my ($r_ban1,$r_ban2,$banPart)=@_;
  foreach my $field (@{$banListsFields[$banPart]}) {
    my @definedStatus = map {exists $_->{$field} && defined $_->{$field} && $_->{$field} ne '' ? 1 : 0} ($r_ban1,$r_ban2);
    return 0 unless($definedStatus[0] == $definedStatus[1]);
    next unless($definedStatus[0]);
    if($field eq 'startDate') {
      my $currentTime=time;
      next if($r_ban1->{startDate} <= $currentTime && $r_ban2->{startDate} <= $currentTime);
    }
    return 0 unless($r_ban1->{$field} eq $r_ban2->{$field});
  }
  return 1;
}

# Internal functions - Dynamic data - Map hashes ##############################

sub getMapHashes {
  my ($self,$springMajorVersion)=@_;
  return $self->{mapHashes}{$springMajorVersion} if(exists $self->{mapHashes}{$springMajorVersion});
  return {};
}

# Business functions ##########################################################

# Business functions - Configuration ##########################################

sub applyPreset {
  my ($self,$preset,$commandsAlreadyLoaded)=@_;
  $commandsAlreadyLoaded//=0;
  my %settings=%{$self->{presets}{$preset}};
  foreach my $param (keys %settings) {
    $self->{conf}{$param}=$settings{$param}[0];
    $self->{values}{$param}=$settings{$param};
  }
  $self->{conf}{preset}=$preset;
  if(! $commandsAlreadyLoaded) {
    my $p_commands=loadTableFile($self->{log},$self->{conf}{etcDir}.'/'.$self->{conf}{commandsFile},\@commandsFields,$self->{macros},1);
    if(%{$p_commands}) {
      $self->{commands}=$p_commands;
    }else{
      $self->{log}->log("Unable to load commands file \"$self->{conf}{commandsFile}\"",1);
    }
  }
  $self->applyHPreset($self->{conf}{hostingPreset});
  $self->applyBPreset($self->{conf}{battlePreset});
  foreach my $pluginName (keys %{$self->{pluginsConf}}) {
    $self->applyPluginPreset($pluginName,$preset);
  }
}

sub applyPluginPreset {
  my ($self,$pluginName,$preset)=@_;
  return unless(exists $self->{pluginsConf}{$pluginName} && exists $self->{pluginsConf}{$pluginName}{presets}{$preset});
  my %settings=%{$self->{pluginsConf}{$pluginName}{presets}{$preset}};
  foreach my $param (keys %settings) {
    $self->{pluginsConf}{$pluginName}{conf}{$param}=$settings{$param}[0];
    $self->{pluginsConf}{$pluginName}{values}{$param}=$settings{$param};
  }
}

sub applyHPreset {
  my ($self,$preset)=@_;
  my %settings=%{$self->{hPresets}{$preset}};
  foreach my $param (keys %settings) {
    $self->{hSettings}{$param}=$settings{$param}[0];
    $self->{hValues}{$param}=$settings{$param};
  }
  $self->{conf}{hostingPreset}=$preset;
}

sub applyBPreset {
  my ($self,$preset)=@_;
  my %settings=%{$self->{bPresets}{$preset}};
  if(exists $settings{resetoptions} && $settings{resetoptions}[0]) {
    foreach my $bSetKey (keys %{$self->{bSettings}}) {
      delete $self->{bSettings}{$bSetKey} unless(exists $battleParameters{$bSetKey});
    }
    foreach my $bValKey (keys %{$self->{bValues}}) {
      delete $self->{bValues}{$bValKey} unless(exists $battleParameters{$bValKey});
    }
  }
  foreach my $param (keys %settings) {
    if($param eq 'disabledunits') {
      my @currentDisUnits=();
      if(exists $self->{bSettings}{disabledunits} && $self->{bSettings}{disabledunits}) {
        @currentDisUnits=split(/;/,$self->{bSettings}{disabledunits});
      }
      my @newDisUnits=split(/;/,$settings{disabledunits}[0]);
      foreach my $newDisUnit (@newDisUnits) {
        if($newDisUnit eq '-*') {
          @currentDisUnits=();
        }elsif($newDisUnit =~ /^\-(.*)$/) {
          my $removedUnitIndex=aindex(@currentDisUnits,$1);
          splice(@currentDisUnits,$removedUnitIndex,1) if($removedUnitIndex != -1);
        }else{
          push(@currentDisUnits,$newDisUnit) unless(aindex(@currentDisUnits,$newDisUnit) != -1);
        }
      }
      $self->{bSettings}{disabledunits}=join(';',@currentDisUnits);
    }else{
      $self->{bSettings}{$param}=$settings{$param}[0];
      $self->{bValues}{$param}=$settings{$param};
    }
  }
  $self->{conf}{battlePreset}=$preset;
}

sub applyMapList {
  my ($self,$p_availableMaps,$springMajorVersion)=@_;
  my $p_mapFilters=$self->{mapLists}{$self->{conf}{mapList}};
  $self->{maps}={};
  $self->{orderedMaps}=[];
  $self->{ghostMaps}={};
  $self->{orderedGhostMaps}=[];
  my %alreadyTestedMaps;
  for my $i (0..$#{$p_availableMaps}) {
    $alreadyTestedMaps{$p_availableMaps->[$i]{name}}=1;
    for my $j (0..$#{$p_mapFilters}) {
      my $mapFilter=$p_mapFilters->[$j];
      if($mapFilter =~ /^!(.*)$/) {
        my $realMapFilter=$1;
        last if($p_availableMaps->[$i]{name} =~ /^$realMapFilter$/);
      }elsif($p_availableMaps->[$i]{name} =~ /^$mapFilter$/) {
        $self->{maps}{$i}=$p_availableMaps->[$i]{name};
        $self->{orderedMaps}[$j]//=[];
        push(@{$self->{orderedMaps}[$j]},$p_availableMaps->[$i]{name});
        last;
      }
    }
  }
  my $p_availableGhostMaps=$self->getMapHashes($springMajorVersion);
  foreach my $ghostMapName (keys %{$p_availableGhostMaps}) {
    next if(exists $alreadyTestedMaps{$ghostMapName});
    for my $j (0..$#{$p_mapFilters}) {
      my $mapFilter=$p_mapFilters->[$j];
      if($mapFilter =~ /^!(.*)$/) {
        my $realMapFilter=$1;
        last if($realMapFilter eq '_GHOSTMAPS_' || $ghostMapName =~ /^$realMapFilter$/);
      }elsif($mapFilter eq '_GHOSTMAPS_' || $ghostMapName =~ /^$mapFilter$/) {
        $self->{ghostMaps}{$ghostMapName}=$p_availableGhostMaps->{$ghostMapName};
        $self->{orderedGhostMaps}[$j]//=[];
        push(@{$self->{orderedGhostMaps}[$j]},$ghostMapName);
        last;
      }
    }
  }
}

sub applySubMapList {
  my ($self,$mapList)=@_;
  $mapList//='';

  my $p_orderedMaps;
  if($self->{conf}{allowGhostMaps}) {
    $p_orderedMaps=mergeMapArrays($self->{orderedMaps},$self->{orderedGhostMaps});
  }else{
    $p_orderedMaps=mergeMapArrays($self->{orderedMaps});
  }
  return $p_orderedMaps unless($mapList && exists $self->{mapLists}{$mapList});

  my @filteredMaps;
  my $p_mapFilters=$self->{mapLists}{$mapList};
  foreach my $mapName (@{$p_orderedMaps}) {
    for my $i (0..$#{$p_mapFilters}) {
      my $mapFilter=$p_mapFilters->[$i];
      if($mapFilter =~ /^!(.*)$/) {
        my $realMapFilter=$1;
        last if($mapName =~ /^$realMapFilter$/);
      }elsif($mapName =~ /^$mapFilter$/) {
        $filteredMaps[$i]//=[];
        push(@{$filteredMaps[$i]},$mapName);
        last;
      }
    }
  }

  $p_orderedMaps=mergeMapArrays(\@filteredMaps);
  return $p_orderedMaps;
}

sub getFullCommandsHelp {
  my $self=shift;
  my $p_fullHelp=loadSimpleTableFile($self->{log},"$spadsDir/help.dat",$self->{macros});
  return $p_fullHelp;
}

sub getUserAccessLevel {
  my ($self,$name,$p_user,$authenticated)=@_;
  my $p_userData={name => $name,
                  accountId => $p_user->{accountId},
                  country => $p_user->{country},
                  rank => $p_user->{status}{rank},
                  access => $p_user->{status}{access},
                  bot => $p_user->{status}{bot},
                  auth => $authenticated};
  my $p_levels=findMatchingData($p_userData,$self->{users});
  if(@{$p_levels}) {
    return $p_levels->[0]{level};
  }else{
    return 0;
  }
}

sub getLevelDescription {
  my ($self,$level)=@_;
  my $p_descriptions=findMatchingData({level => $level},$self->{levels}{''});
  if(@{$p_descriptions}) {
    return $p_descriptions->[0]{description};
  }else{
    return 'Unknown level';
  }
}

sub getCommandLevels {
  my ($self,$command,$source,$status,$gameState)=@_;
  if(exists $self->{commands}{$command}) {
    my $p_rights=findMatchingData({source => $source, status => $status, gameState => $gameState},$self->{commands}{$command});
    return dclone($p_rights->[0]) if(@{$p_rights});
  }else{
    foreach my $pluginName (keys %{$self->{pluginsConf}}) {
      if(exists $self->{pluginsConf}{$pluginName}{commands}{$command}) {
        my $p_rights=findMatchingData({source => $source, status => $status, gameState => $gameState},$self->{pluginsConf}{$pluginName}{commands}{$command});
        return dclone($p_rights->[0]) if(@{$p_rights});
      }
    }
  }
  return {};
}

sub getHelpForLevel {
  my ($self,$level)=@_;
  my @direct=();
  my @vote=();
  foreach my $command (sort keys %{$self->{commands}}) {
    if(! exists $self->{help}{$command}) {
      $self->{log}->log("Missing help for command \"$command\"",2) unless($command =~ /^#/);
      next;
    }
    my $p_filters=$self->{commands}{$command};
    my $foundDirect=0;
    my $foundVote=0;
    foreach my $p_filter (@{$p_filters}) {
      if(exists $p_filter->[1]{directLevel}
         && defined $p_filter->[1]{directLevel}
         && $p_filter->[1]{directLevel} ne ''
         && $level >= $p_filter->[1]{directLevel}) {
        $foundDirect=1;
      }
      if(exists $p_filter->[1]{voteLevel}
         && defined $p_filter->[1]{voteLevel}
         && $p_filter->[1]{voteLevel} ne ''
         && $level >= $p_filter->[1]{voteLevel}) {
        $foundVote=1;
      }
      last if($foundDirect);
    }
    if($foundDirect) {
      push(@direct,$self->{help}{$command}[0]);
    }elsif($foundVote) {
      push(@vote,$self->{help}{$command}[0]);
    }
  }
  foreach my $pluginName (keys %{$self->{pluginsConf}}) {
    my $p_pluginCommands=$self->{pluginsConf}{$pluginName}{commands};
    foreach my $command (sort keys %{$p_pluginCommands}) {
      if(! exists $self->{pluginsConf}{$pluginName}{help}{$command}) {
        $self->{log}->log("Missing help for command \"$command\" of plugin $pluginName",2);
        next;
      }
      my $p_filters=$p_pluginCommands->{$command};
      my $foundDirect=0;
      my $foundVote=0;
      foreach my $p_filter (@{$p_filters}) {
        if(exists $p_filter->[1]{directLevel}
           && defined $p_filter->[1]{directLevel}
           && $p_filter->[1]{directLevel} ne ''
           && $level >= $p_filter->[1]{directLevel}) {
          $foundDirect=1;
        }
        if(exists $p_filter->[1]{voteLevel}
           && defined $p_filter->[1]{voteLevel}
           && $p_filter->[1]{voteLevel} ne ''
           && $level >= $p_filter->[1]{voteLevel}) {
          $foundVote=1;
        }
        last if($foundDirect);
      }
      if($foundDirect) {
        push(@direct,$self->{pluginsConf}{$pluginName}{help}{$command}[0]);
      }elsif($foundVote) {
        push(@vote,$self->{pluginsConf}{$pluginName}{help}{$command}[0]);
      }
    }
  }
  return {direct => \@direct, vote => \@vote};
}

# Business functions - Dynamic data ###########################################

sub dumpDynamicData {
  my $self=shift;
  my $startDumpTs=time;
  my $p_prunedPrefs=$self->getPrunedRawPreferences();
  $self->dumpFastTable($p_prunedPrefs,$self->{conf}{instanceDir}.'/preferences.dat',\@preferencesListsFields);
  $self->dumpFastTable($self->{mapHashes},$self->{conf}{instanceDir}.'/mapHashes.dat',\@mapHashesFields);
  my $p_userData=flushUserDataCache($self);
  $self->dumpFastTable($p_userData,$self->{conf}{instanceDir}.'/userData.dat',\@userDataFields);
  my $dumpDuration=time-$startDumpTs;
  $self->{log}->log("Dynamic data dump process took $dumpDuration seconds",2) if($dumpDuration > 15);
}

sub refreshSharedData {
  my $self=shift;
  foreach my $sharedData (keys %shareableData) {
    my $sharedFile="$self->{conf}{varDir}/$sharedData.dat";
    next unless($self->{sharedDataTs}{$sharedData} && -f $sharedFile && (Time::HiRes::stat($sharedFile))[9] > $self->{sharedDataTs}{$sharedData});
    $self->{log}->log("Shared file \"$sharedData.dat\" has been modified, refreshing data",5);
    if(my $lock = _acquireLock($sharedFile,LOCK_SH)) {
      my $r_refreshedData;
      my $r_loadedData=loadShareableData($self->{log},$sharedFile,$sharedData);
      if($shareableData{$sharedData}{type} eq 'binary') {
        $r_refreshedData = defined $r_loadedData ? {'' => $r_loadedData} : {};
      }else{
        $r_refreshedData=$r_loadedData;
      }
      if(! %{$r_refreshedData}) {
        $self->{log}->log("Unable to refresh $sharedData data (failed to read data from shared file)",1);
      }else{
        $self->{$sharedData}=$r_refreshedData->{''};
        $self->{sharedDataTs}{$sharedData}=(Time::HiRes::stat($sharedFile))[9];
      }
      close($lock);
    }else{
      $self->{log}->log("Unable to refresh $sharedData data (failed to acquire lock on shared file)",1);
    }
  }
}

# Business functions - Dynamic data - Map info cache ##########################

sub getUncachedMaps {
  my ($self,$p_maps)=@_;
  my $p_uncachedMaps=[];
  foreach my $map (@{$p_maps}) {
    push(@{$p_uncachedMaps},$map) unless(exists $self->{mapInfo}{$map});
  }
  return $p_uncachedMaps;
}

sub getCachedMapInfo {
  my ($self,$map)=@_;
  return $self->{mapInfo}{$map} if(exists $self->{mapInfo}{$map});
  return undef;
}

sub cacheMapsInfo {
  my ($self,$p_mapsInfo)=@_;
  foreach my $map (keys %{$p_mapsInfo}) {
    $self->{mapInfo}{$map}=$p_mapsInfo->{$map};
  }
  $self->{log}->log('Unable to store map info cache',1) unless(nstore($self->{mapInfo},$self->{conf}{instanceDir}.'/mapInfoCache.dat'));
}

# Business functions - Dynamic data - Map boxes ###############################

sub existSavedMapBoxes {
  my ($self,$map,$nbTeams)=@_;
  return (exists $self->{savedBoxes}{$map} && exists $self->{savedBoxes}{$map}{$nbTeams});
}

sub getSavedBoxesMaps {
  my $self=shift;
  my @savedBoxesMaps=keys %{$self->{savedBoxes}};
  return \@savedBoxesMaps;
}

sub getMapBoxes {
  my ($self,$map,$nbTeams,$extraBox)=@_;
  my $p_boxes;
  if($extraBox) {
    my $tmpNbTeams=($nbTeams+$extraBox)."(-$extraBox)";
    if(exists $self->{mapBoxes}{$map} && exists $self->{mapBoxes}{$map}{$tmpNbTeams}) {
      $p_boxes=$self->{mapBoxes}{$map}{$tmpNbTeams}{boxes};
    }elsif(exists $self->{savedBoxes}{$map} && exists $self->{savedBoxes}{$map}{$tmpNbTeams}) {
      $p_boxes=$self->{savedBoxes}{$map}{$tmpNbTeams}{boxes};
    }
  }
  if(! defined $p_boxes) {
    if(exists $self->{mapBoxes}{$map} && exists $self->{mapBoxes}{$map}{$nbTeams}) {
      $p_boxes=$self->{mapBoxes}{$map}{$nbTeams}{boxes};
    }elsif(exists $self->{savedBoxes}{$map} && exists $self->{savedBoxes}{$map}{$nbTeams}) {
      $p_boxes=$self->{savedBoxes}{$map}{$nbTeams}{boxes};
    }
  }
  if(defined $p_boxes) {
    my @boxes=split(';',$p_boxes);
    return \@boxes;
  }
  return [];
}

sub saveMapBoxes {
  my ($self,$map,$p_startRects,$extraBox)=@_;
  return undef unless(%{$p_startRects});
  my @ids=sort (keys %{$p_startRects});
  my $nbTeams=$#ids+1;
  $nbTeams.="(-$extraBox)" if($extraBox);
  my $boxId=$ids[0];
  my $boxesString="$p_startRects->{$boxId}{left} $p_startRects->{$boxId}{top} $p_startRects->{$boxId}{right} $p_startRects->{$boxId}{bottom}";
  for my $boxIndex (1..$#ids) {
    $boxId=$ids[$boxIndex];
    $boxesString.=";$p_startRects->{$boxId}{left} $p_startRects->{$boxId}{top} $p_startRects->{$boxId}{right} $p_startRects->{$boxId}{bottom}";
  }
  return 2 if($self->existSavedMapBoxes($map,$nbTeams) && $self->{savedBoxes}{$map}{$nbTeams}{boxes} eq $boxesString);
  my $lock;
  if($self->{sharedDataTs}{savedBoxes}) {
    $lock=$self->refreshAndLockSharedDataForUpdate('savedBoxes')
        or return 0;
  }
  $self->{savedBoxes}{$map}={} unless(exists $self->{savedBoxes}{$map});
  $self->{savedBoxes}{$map}{$nbTeams}={} unless(exists $self->{savedBoxes}{$map}{$nbTeams});
  $self->{savedBoxes}{$map}{$nbTeams}{boxes}=$boxesString;
  if($lock) {
    $self->updateAndUnlockSharedData('savedBoxes',$lock);
    $self->{log}->log("Shared file \"savedBoxes.dat\" updated for \"$map\" (nbTeams=$nbTeams)",3);
  }else{
    $self->dumpFastTable($self->{savedBoxes},$self->{conf}{instanceDir}.'/savedBoxes.dat',\@mapBoxesFields);
    $self->{log}->log("File \"savedBoxes.dat\" updated for \"$map\" (nbTeams=$nbTeams)",3);
  }
  return 1;
}

# Business functions - Dynamic data - Map hashes ##############################

sub getMapHash {
  my ($self,$map,$springMajorVersion)=@_;
  if(exists $self->{mapHashes}{$springMajorVersion} && exists $self->{mapHashes}{$springMajorVersion}{$map}) {
    return $self->{mapHashes}{$springMajorVersion}{$map}{mapHash};
  }
  return 0;
}

sub saveMapHash {
  my ($self,$map,$springMajorVersion,$hash)=@_;
  $self->{mapHashes}{$springMajorVersion}={} unless(exists $self->{mapHashes}{$springMajorVersion});
  $self->{mapHashes}{$springMajorVersion}{$map}={} unless(exists $self->{mapHashes}{$springMajorVersion}{$map});
  $self->{mapHashes}{$springMajorVersion}{$map}{mapHash}=$hash;
  $self->{log}->log("Hash saved for map \"$map\" (springMajorVersion=$springMajorVersion)",5);
  return 1;
}

# Business functions - Dynamic data - Trusted certificate hashes ##############################

sub isTrustedCertificateHash {
  my ($self,$lobbyHost,$certHash)=@_;
  $lobbyHost=lc($lobbyHost);
  $certHash=lc($certHash);
  if(exists $self->{springLobbyCertificates}{$lobbyHost}) {
    my @trustedLobbyCertificates=split(/,/,$self->{springLobbyCertificates}{$lobbyHost}{certHashes});
    return 1 if(any {$certHash eq $_} @trustedLobbyCertificates);
  }
  return 1 if(roExists($self->{trustedLobbyCertificates},[$lobbyHost,$certHash]));
  return 0;
}

sub addTrustedCertificateHash {
  my ($self,$p_trustedCert)=@_;
  my ($lobbyHost,$certHash)=(lc($p_trustedCert->{lobbyHost}),lc($p_trustedCert->{certHash}));
  if($self->isTrustedCertificateHash($lobbyHost,$certHash)) {
    $self->{log}->log("Ignoring addition of trusted certificate hash: certificate is already trusted! ($lobbyHost:$certHash)",2);
    return 0;
  }
  my $lock;
  if($self->{sharedDataTs}{trustedLobbyCertificates}) {
    $lock=$self->refreshAndLockSharedDataForUpdate('trustedLobbyCertificates')
        or return 0;
  }
  $self->{trustedLobbyCertificates}{$lobbyHost}{$certHash}=1;
  my $res;
  if($lock) {
    $res=$self->updateAndUnlockSharedData('trustedLobbyCertificates',$lock);
  }else{
    $res=nstore($self->{trustedLobbyCertificates},$self->{conf}{instanceDir}.'/trustedLobbyCertificates.dat');
  }
  $self->{log}->log('Unable to store trusted lobby certificates',1) unless($res);
  return 1;
}

sub removeTrustedCertificateHash {
  my ($self,$p_trustedCert)=@_;
  my ($lobbyHost,$certHash)=(lc($p_trustedCert->{lobbyHost}),lc($p_trustedCert->{certHash}));
  if(! roExists($self->{trustedLobbyCertificates},[$lobbyHost,$certHash])) {
    my $reason='this certificate is already not trusted';
    $reason='this certificate is an official Spring lobby certificate' if($self->isTrustedCertificateHash($lobbyHost,$certHash));
    $self->{log}->log("Ignoring removal of trusted certificate hash: $reason! ($lobbyHost:$certHash)",2);
    return 0;
  }
  my $lock;
  if($self->{sharedDataTs}{trustedLobbyCertificates}) {
    $lock=$self->refreshAndLockSharedDataForUpdate('trustedLobbyCertificates')
        or return 0;
  }
  delete $self->{trustedLobbyCertificates}{$lobbyHost}{$certHash};
  delete $self->{trustedLobbyCertificates}{$lobbyHost} unless(%{$self->{trustedLobbyCertificates}{$lobbyHost}});
  my $res;
  if($lock) {
    $res=$self->updateAndUnlockSharedData('trustedLobbyCertificates',$lock);
  }else{
    $res=nstore($self->{trustedLobbyCertificates},$self->{conf}{instanceDir}.'/trustedLobbyCertificates.dat');
  }
  $self->{log}->log('Unable to store trusted lobby certificates',1) unless($res);
  return 1;
}

sub getTrustedCertificateHashes {
  my $self=shift;
  my %trustedCerts;
  foreach my $host (keys %{$self->{springLobbyCertificates}}) {
    my @trustedLobbyCertificates=split(/,/,$self->{springLobbyCertificates}{$host}{certHashes});
    foreach my $hash (@trustedLobbyCertificates) {
      $trustedCerts{$host}{$hash}=1;
    }
  }
  foreach my $host (keys %{$self->{trustedLobbyCertificates}}) {
    foreach my $hash (keys %{$self->{trustedLobbyCertificates}{$host}}) {
      $trustedCerts{$host}{$hash}=0;
    }
  }
  return \%trustedCerts;
}

# Business functions - Dynamic data - User data ###############################

sub getNbAccounts {
  my $self=shift;
  my $nbAccounts=keys %{$self->{accountData}};
  return $nbAccounts;
}

sub getNbNames {
  my $self=shift;
  my $nbNames=keys %{$self->{nameIds}};
  return $nbNames;
}

sub getNbIps {
  my $self=shift;
  my $nbIps=keys %{$self->{ipIds}};
  return $nbIps;
}

sub isStoredAccount {
  my ($self,$aId)=@_;
  return (exists $self->{accountData}{$aId});
}

sub isStoredUser {
  my ($self,$name)=@_;
  return (exists $self->{nameIds}{$name});
}

sub isStoredIp {
  my ($self,$ip)=@_;
  return (exists $self->{ipIds}{$ip});
}

sub getAccountNamesTs {
  my ($self,$id)=@_;
  return $self->{accountData}{$id}{names};
}

sub getAccountIpsTs {
  my ($self,$id)=@_;
  return $self->{accountData}{$id}{ips};
}

sub getAccountMainData {
  my ($self,$id)=@_;
  return $self->{accountData}{$id};
}

sub getUserIds {
  my ($self,$user)=@_;
  my @ids=keys %{$self->{nameIds}{$user}};
  return \@ids;
}

sub getIpIdsTs {
  my ($self,$ip)=@_;
  return $self->{ipIds}{$ip};
}

sub getAccountIps {
  my ($self,$id,$p_ignoredIps)=@_;
  $p_ignoredIps//={};
  my @ips;
  if(exists $self->{accountData}{$id}) {
    my %ipHash=%{$self->{accountData}{$id}{ips}};
    @ips=sort {$ipHash{$b} <=> $ipHash{$a}} (keys %ipHash);
  }
  my @filteredIps;
  foreach my $ip (@ips) {
    push(@filteredIps,$ip) unless(exists $p_ignoredIps->{$ip});
  }
  return \@filteredIps;
}

sub getLatestAccountIp {
  my ($self,$id)=@_;
  my $latestIdIp='';
  if(exists $self->{accountData}{$id}) {
    my $latestTimestamp=0;
    foreach my $ip (keys %{$self->{accountData}{$id}{ips}}) {
      if($self->{accountData}{$id}{ips}{$ip} > $latestTimestamp) {
        $latestIdIp=$ip;
        $latestTimestamp=$self->{accountData}{$id}{ips}{$ip};
      }
    }
  }
  return $latestIdIp;
}

sub getLatestUserAccountId {
  my ($self,$name)=@_;
  my $latestUserAccountId='';
  if(exists $self->{nameIds}{$name}) {
    my $latestTimestamp=0;
    foreach my $id (keys %{$self->{nameIds}{$name}}) {
      if($self->{nameIds}{$name}{$id} > $latestTimestamp) {
        $latestUserAccountId=$id;
        $latestTimestamp=$self->{nameIds}{$name}{$id};
      }
    }
  }
  return $latestUserAccountId;
}

sub getLatestIpAccountId {
  my ($self,$ip)=@_;
  my $latestIpAccountId='';
  if(exists $self->{ipIds}{$ip}) {
    my $latestTimestamp=0;
    foreach my $id (keys %{$self->{ipIds}{$ip}}) {
      if($self->{ipIds}{$ip}{$id} > $latestTimestamp) {
        $latestIpAccountId=$id;
        $latestTimestamp=$self->{ipIds}{$ip}{$id};
      }
    }
  }
  return $latestIpAccountId;
}

sub getIpAccounts {
  my ($self,$ip)=@_;
  my %accounts;
  if(exists $self->{ipIds}{$ip}) {
    foreach my $i (keys %{$self->{ipIds}{$ip}}) {
      $accounts{$i}=$self->{accountData}{$i}{rank};
    }
  }
  return \%accounts;
}

sub searchUserIds {
  my ($self,$search)=@_;
  my $nbMatchingId=0;
  my %matchingIds;
  foreach my $name (sort keys %{$self->{nameIds}}) {
    if(index(lc($name),lc($search)) > -1) {
      my %nameIds=%{$self->{nameIds}{$name}};
      foreach my $id (keys %nameIds) {
        if(exists $matchingIds{$id}) {
          $matchingIds{$id}{timestamp}=$nameIds{$id} unless($matchingIds{$id}{timestamp} > $nameIds{$id});
          $matchingIds{$id}{names}{$name}=$nameIds{$id};
        }else{
          ++$nbMatchingId;
          $matchingIds{$id}={timestamp => $nameIds{$id},
                             names => {$name => $nameIds{$id}}};
        }
      }
    }
  }
  return (\%matchingIds,$nbMatchingId);
}

sub searchIpIds {
  my ($self,$search)=@_;
  my $filter=$search;
  $filter=~s/\./\\\./g;
  $filter=~s/\*/\.\*/g;
  my $nbMatchingId=0;
  my %matchingIds;
  foreach my $ip (sort keys %{$self->{ipIds}}) {
    if($ip =~ /^$filter$/) {
      my %ipIds=%{$self->{ipIds}{$ip}};
      foreach my $id (keys %ipIds) {
        if(exists $matchingIds{$id}) {
          $matchingIds{$id}{timestamp}=$ipIds{$id} unless($matchingIds{$id}{timestamp} > $ipIds{$id});
          $matchingIds{$id}{ips}{$ip}=$ipIds{$id};
        }else{
          ++$nbMatchingId;
          $matchingIds{$id}={timestamp => $ipIds{$id},
                             ips => {$ip => $ipIds{$id}}};
        }
      }
    }
  }
  return (\%matchingIds,$nbMatchingId);
}

sub getSmurfs {
  my ($self,$id)=@_;
  my $latestAccountIp=$self->getLatestAccountIp($id);
  return [] unless($latestAccountIp);
  my $p_smurfs1=$self->getIpAccounts($latestAccountIp);
  my @smurfs1=sort {$p_smurfs1->{$b} <=> $p_smurfs1->{$a}} (keys %{$p_smurfs1});
  my @smurfs=(\@smurfs1);
  my @ips=([$latestAccountIp]);
  my ($p_processedAccounts,$p_processedIps,$p_newIps)=({$id => 1},{},$self->getAccountIps($id));
  while(@{$p_newIps}) {
    push(@ips,$p_newIps);
    my %newAccounts;
    foreach my $newIp (@{$p_newIps}) {
      next if(exists $p_processedIps->{$newIp});
      my $p_ipNewAccounts=$self->getIpAccounts($newIp);
      foreach my $newAccount (keys %{$p_ipNewAccounts}) {
        $newAccounts{$newAccount}=$p_ipNewAccounts->{$newAccount} unless(exists $p_processedAccounts->{$newAccount});
      }
      $p_processedIps->{$newIp}=1;
    }
    my @newSmurfs;
    $p_newIps=[];
    foreach my $newAccount (sort {$newAccounts{$b} <=> $newAccounts{$a}} (keys %newAccounts)) {
      push(@newSmurfs,$newAccount) unless(exists $p_smurfs1->{$newAccount});
      my $p_accountIps=$self->getAccountIps($newAccount,$p_processedIps);
      push(@{$p_newIps},@{$p_accountIps});
      $p_processedAccounts->{$newAccount}=1;
    }
    push(@smurfs,\@newSmurfs);
  }
  return (\@smurfs,\@ips);
}

sub learnUserData {
  my ($self,$user,$country,$id,$lobbyClient)=@_;
  if(! exists $self->{accountData}{$id}) {
    $self->{accountData}{$id}={country => $country,
                               lobbyClient => $lobbyClient,
                               rank => 0,
                               timestamp => time,
                               ips => {},
                               names => {$user => time}};
  }else{
    my $userNameRetention=-1;
    $userNameRetention=$1 if($self->{conf}{userDataRetention} =~ /;(\d+)$/);
    $self->{accountData}{$id}{country}=$country;
    $self->{accountData}{$id}{lobbyClient}=$lobbyClient;
    $self->{accountData}{$id}{timestamp}=time;
    my $isNewName=0;
    $isNewName=1 unless(exists $self->{accountData}{$id}{names}{$user});
    $self->{accountData}{$id}{names}{$user}=time;
    if($isNewName && $userNameRetention > -1) {
      my $p_accountNames=$self->{accountData}{$id}{names};
      my @accountNames=sort {$p_accountNames->{$a} <=> $p_accountNames->{$b}} (keys %{$p_accountNames});
      delete $self->{accountData}{$id}{names}{$accountNames[0]} if($#accountNames > $userNameRetention);
    }
  }
  $self->{nameIds}{$user}={} unless($self->isStoredUser($user));
  $self->{nameIds}{$user}{$id}=time;
}

sub learnAccountIp {
  my ($self,$id,$ip,$userIpRetention,$bot)=@_;
  $self->{accountData}{$id}{ips}={} if($bot);
  my $isNewIp=0;
  $isNewIp=1 unless(exists $self->{accountData}{$id}{ips}{$ip});
  $self->{accountData}{$id}{ips}{$ip}=time;
  $self->{ipIds}{$ip}={} unless(exists $self->{ipIds}{$ip});
  $self->{ipIds}{$ip}{$id}=time;
  if($isNewIp && $userIpRetention > 0) {
    my $p_accountIps=$self->{accountData}{$id}{ips};
    my @accountIps=sort {$p_accountIps->{$a} <=> $p_accountIps->{$b}} (keys %{$p_accountIps});
    delete $self->{accountData}{$id}{ips}{$accountIps[0]} if($#accountIps + 1 > $userIpRetention);
  }
}

sub learnAccountRank {
  my ($self,$id,$rank,$bot)=@_;
  if($self->{accountData}{$id}{rank} eq '' || $rank > $self->{accountData}{$id}{rank}) {
    if($bot) {
      $self->{accountData}{$id}{rank}=-$rank;
    }else{
      $self->{accountData}{$id}{rank}=$rank;
    }
  }
}

# Business functions - Dynamic data - Bans ####################################

sub getDynamicBans {
  my $self=shift;
  return $self->{bans};
}

sub getBanHash {
  my ($self,$p_ban)=@_;
  return substr(md5_base64(flattenBan($p_ban)),0,5);
}

sub removeBanByHash {
  my ($self,$hash,$checkOnly)=@_;
  foreach my $banIndex (0..$#{$self->{bans}}) {
    if($self->getBanHash($self->{bans}[$banIndex]) eq $hash) {
      my $res=1;
      if($checkOnly) {
        return $res;
      }elsif($self->{sharedDataTs}{bans}) {
        $res=$self->removeBanByHashShared($hash);
      }else{
        $res=splice(@{$self->{bans}},$banIndex,1);
        $self->dumpTable($self->{bans},$self->{conf}{instanceDir}.'/bans.dat',\@banListsFields);
      }
      return $res;
    }
  }
  return 0;
}

sub removeBanByHashShared {
  my ($self,$hash)=@_;
  my $lock=$self->refreshAndLockSharedDataForUpdate('bans')
      or return 0;
  foreach my $banIndex (0..$#{$self->{bans}}) {
    if($self->getBanHash($self->{bans}[$banIndex]) eq $hash) {
      my $res=splice(@{$self->{bans}},$banIndex,1);
      $self->updateAndUnlockSharedData('bans',$lock);
      return $res;
    }
  }
  close($lock);
  return 0;
}

sub banExists {
  my ($self,$p_filters)=@_;

  my $nbPrunedBans = $self->pruneExpiredBans();
  $self->{log}->log("$nbPrunedBans bans have expired in file \"banLists.cfg\"",3) if($nbPrunedBans);

  $self->removeExpiredBans();

  my $p_bans=findMatchingData($p_filters,$self->{bans},0);
  if(@{$p_bans}) {
    return 1;
  }else{
    return 0;
  }
}

sub getUserBan {
  my ($self,$name,$p_user,$authenticated,$ip,$skill,$skillUncert)=@_;
  $skill//='_UNKNOWN_';
  $skillUncert//='_UNKNOWN_';
  if(! defined $ip) {
    my $id=$p_user->{accountId};
    $id.="($name)" unless($id);
    $ip=$self->getLatestAccountIp($id);
  }
  $ip=$p_user->{ip} if($ip eq '' && exists $p_user->{ip} && defined $p_user->{ip});
  $ip='_UNKNOWN_' if($ip eq '');
  my $p_userData={name => $name,
                  accountId => $p_user->{accountId},
                  country => $p_user->{country},
                  lobbyClient => $p_user->{lobbyClient},
                  rank => $p_user->{status}{rank},
                  access => $p_user->{status}{access},
                  bot => $p_user->{status}{bot},
                  level => $self->getUserAccessLevel($name,$p_user,$authenticated),
                  ip => $ip,
                  skill => $skill,
                  skillUncert => $skillUncert};
  my $nbPrunedBans = $self->pruneExpiredBans();
  $self->{log}->log("$nbPrunedBans bans have expired in file \"banLists.cfg\"",3) if($nbPrunedBans);

  $self->removeExpiredBans();

  my $p_effectiveBan={banType => 3};
  my @allBans=();

  my $p_bans=findMatchingData($p_userData,$self->{banLists}{''});
  push(@allBans,$p_bans->[0]) if(@{$p_bans});

  my $p_bansAuto=findMatchingData($p_userData,$self->{bans});
  push(@allBans,@{$p_bansAuto});

  my $p_bansSpecific=[];
  $p_bansSpecific=findMatchingData($p_userData,$self->{banLists}{$self->{conf}{banList}}) if($self->{conf}{banList});
  push(@allBans,$p_bansSpecific->[0]) if(@{$p_bansSpecific});

  foreach my $p_ban (@allBans) {
    $p_effectiveBan=$p_ban if($p_ban->{banType} < $p_effectiveBan->{banType})
  }

  return $p_effectiveBan;
}

sub banUser {
  my ($self,$p_user,$p_ban)=@_;
  return 2 if($self->banIsDuplicate($p_user,$p_ban));
  my $lock;
  if($self->{sharedDataTs}{bans}) {
    $lock=$self->refreshAndLockSharedDataForUpdate('bans')
        or return 0;
    if($self->banIsDuplicate($p_user,$p_ban)) {
      close($lock);
      return 2;
    }
  }
  push(@{$self->{bans}},[$p_user,$p_ban]);
  if($lock) {
    $self->updateAndUnlockSharedData('bans',$lock);
  }else{
    $self->dumpTable($self->{bans},$self->{conf}{instanceDir}.'/bans.dat',\@banListsFields);
  }
  return 1;
}

sub unban {
  my ($self,$p_filters)=@_;
  my $lock;
  if($self->{sharedDataTs}{bans}) {
    $lock=$self->refreshAndLockSharedDataForUpdate('bans')
        or return;
  }
  $self->{bans}=removeMatchingData($p_filters,$self->{bans});
  if($lock) {
    $self->updateAndUnlockSharedData('bans',$lock);
  }else{
    $self->dumpTable($self->{bans},$self->{conf}{instanceDir}.'/bans.dat',\@banListsFields);
  }
}

sub decreaseGameBasedBans {
  my $self=shift;
  if($self->{sharedDataTs}{bans}) {
    $self->decreaseSharedGameBasedBans();
  }else{
    $self->decreasePrivateGameBasedBans();
  }
}

sub decreaseSharedGameBasedBans {
  my $self=shift;
  my $hasModifiedBans=0;
  foreach my $p_ban (@{$self->{bans}}) {
    if(exists $p_ban->[1]{remainingGames} && defined $p_ban->[1]{remainingGames} && $p_ban->[1]{remainingGames} ne '') {
      $hasModifiedBans=1;
      last;
    }
  }
  return unless($hasModifiedBans);
  my $lock=$self->refreshAndLockSharedDataForUpdate('bans')
      or return;
  my ($nbRemovedBans,$nbModifiedBans)=(0,0);
  my @newBans;
  foreach my $p_ban (@{$self->{bans}}) {
    if(exists $p_ban->[1]{remainingGames} && defined $p_ban->[1]{remainingGames} && $p_ban->[1]{remainingGames} ne '') {
      if($p_ban->[1]{remainingGames} < 2) {
        $nbRemovedBans++;
        next;
      }
      $nbModifiedBans++;
      $p_ban->[1]{remainingGames}--;
    }
    push(@newBans,$p_ban);
  }
  if($nbRemovedBans || $nbModifiedBans) {
    $self->{bans}=\@newBans;
    $self->updateAndUnlockSharedData('bans',$lock);
    $self->{log}->log("$nbRemovedBans expired ban(s) removed from shared file \"bans.dat\"",3) if($nbRemovedBans);
  }else{
    close($lock);
  }
}

sub decreasePrivateGameBasedBans {
  my $self=shift;
  my ($nbRemovedBans,$nbModifiedBans)=(0,0);
  my @newBans;
  foreach my $p_ban (@{$self->{bans}}) {
    if(exists $p_ban->[1]{remainingGames} && defined $p_ban->[1]{remainingGames} && $p_ban->[1]{remainingGames} ne '') {
      if($p_ban->[1]{remainingGames} < 2) {
        $nbRemovedBans++;
        next;
      }
      $nbModifiedBans++;
      $p_ban->[1]{remainingGames}--;
    }
    push(@newBans,$p_ban);
  }
  if($nbRemovedBans || $nbModifiedBans) {
    $self->{bans}=\@newBans;
    $self->{log}->log("$nbRemovedBans expired ban(s) removed from file \"bans.dat\"",3) if($nbRemovedBans);
    $self->dumpTable($self->{bans},$self->{conf}{instanceDir}.'/bans.dat',\@banListsFields);
  }
}

# Business functions - Dynamic data - Preferences #############################

sub checkUserPref {
  my ($self,$prefName,$prefValue)=@_;
  $prefName=lc($prefName);
  my $invalidValue=0;
  $invalidValue=1 if($prefValue =~ /[\:\|]/);
  foreach my $pref (@{$preferencesListsFields[1]}) {
    if($prefName eq lc($pref)) {
      if($invalidValue || ($prefValue ne '' && exists $spadsSectionParameters{$pref} && (! checkValue($prefValue,$spadsSectionParameters{$pref})))) {
        return ("invalid value \"$prefValue\" for preference $pref",$pref);
      }else{
        return ('',$pref);
      }
    }
  }
  return("invalid preference \"$prefName\"");
}

sub getAccountPrefs {
  my ($self,$aId)=@_;
  my %prefs;
  foreach my $pref (@{$preferencesListsFields[1]}) {
    $prefs{$pref}='';
  }
  return \%prefs unless(exists $self->{preferences}{$aId});
  foreach my $pref (keys %{$self->{preferences}{$aId}}) {
    next if($pref eq 'name');
    $prefs{$pref}=$self->{preferences}{$aId}{$pref};
  }
  return \%prefs;
}

sub getUserPrefs {
  my ($self,$aId,$name)=@_;
  my %prefs;
  foreach my $pref (@{$preferencesListsFields[1]}) {
    $prefs{$pref}='';
  }
  my $key=$aId || "?($name)";
  if(! exists $self->{preferences}{$key}) {
    if(exists $self->{preferences}{"?($name)"}) {
      $self->{preferences}{$key}=delete $self->{preferences}{"?($name)"};
    }else{
      return \%prefs;
    }
  }
  $self->{preferences}{$key}{name}=$name;
  foreach my $pref (keys %{$self->{preferences}{$key}}) {
    next if($pref eq 'name');
    $prefs{$pref}=$self->{preferences}{$key}{$pref};
  }
  return \%prefs;
}

sub setUserPref {
  my ($self,$aId,$name,$prefName,$prefValue)=@_;
  my $key=$aId || "?($name)";
  if(! exists $self->{preferences}{$key}) {
    if(exists $self->{preferences}{"?($name)"}) {
      $self->{preferences}{$key}=delete $self->{preferences}{"?($name)"};
    }else{
      $self->{preferences}{$key}={};
      foreach my $pref (@{$preferencesListsFields[1]}) {
        $self->{preferences}{$key}{$pref}='';
      }
    }
  }
  $self->{preferences}{$key}{name}=$name;
  $self->{preferences}{$key}{$prefName}=$prefValue;
}

1;
