# We define our plugin class
package ForbiddenWords;

# We use strict Perl syntax for cleaner code
use strict;

# We use the SPADS plugin API module
use SpadsPluginApi;

# This is the first version of the plugin
my $pluginVersion='0.1';

# This plugin is compatible with any SPADS version which supports plugins
# (only SPADS versions >= 0.11 support plugins)
my $requiredSpadsVersion='0.11';

# We define one global setting "words" and one preset setting "immuneLevel".
# "words" has no type associated (no restriction on allowed values)
# "immuneLevel" must be an integer or an integer range
# (check %paramTypes hash in SpadsConf.pm for a complete list of allowed
# setting types)
my %globalPluginParams = ( words => [] );
my %presetPluginParams = ( immuneLevel => ['integer','integerRange'] );

# This is how SPADS gets our version number (mandatory callback)
sub getVersion { return $pluginVersion; }

# This is how SPADS determines if the plugin is compatible (mandatory callback)
sub getRequiredSpadsVersion { return $requiredSpadsVersion; }

# This is how SPADS finds what settings we need in our configuration file (mandatory callback for configurable plugins)
sub getParams { return [\%globalPluginParams,\%presetPluginParams]; }

# This is our constructor, called when the plugin is loaded by SPADS (mandatory callback)
sub new {

  # Constructors take the class name as first parameter
  my $class=shift;

  # We create a hash which will contain the plugin data
  my $self = {};

  # We instanciate this hash as an object of the given class
  bless($self,$class);

  # We call the API function "slog" to log a notice message (level 3) when the plugin is loaded
  slog("ForbiddenWords plugin loaded (version $pluginVersion)",3);

  # We set up a lobby command handler on SAIDBATTLE
  addLobbyCommandHandler({SAIDBATTLE => \&hLobbySaidBattle});

  # We return the instantiated plugin
  return $self;

}

# This callback is called each time we (re)connect to the lobby server
sub onLobbyConnected {

  # When we are disconnected from the lobby server, all lobby command
  # handlers are automatically removed, so we (re)set up our command
  # handler here.
  addLobbyCommandHandler({SAIDBATTLE => \&hLobbySaidBattle});

}

# This is the handler we set up on SAIDBATTLE lobby command.
# It is called each time a player says something in the battle lobby.
sub hLobbySaidBattle {

  # $command is the lobby command name (SAIDBATTLE)
  # $user is the name of the user who said something in the battle lobby
  # $message is the message said in the battle lobby
  my ($command,$user,$message)=@_;

  # First we check it's not a message from SPADS (so we don't kick ourself)
  my $p_spadsConf=getSpadsConf();
  return if($user eq $p_spadsConf->{lobbyLogin});

  # Then we check the user isn't a privileged user
  # (autohost access level >= immuneLevel)
  my $p_conf=getPluginConf();
  return if(getUserAccessLevel($user) >= $p_conf->{immuneLevel});

  # We put the forbidden words in a array
  my @forbiddenWords=split(/;/,$p_conf->{words});

  # We test each forbidden word
  foreach my $forbiddenWord (@forbiddenWords) {

    # If the message contains the forbidden word (case insensitive)
    if($message =~ /\b$forbiddenWord\b/i) {

      # Then we kick the user from the battle lobby
      sayBattle("Kicking $user from battle (watch your language!)");
      queueLobbyCommand(["KICKFROMBATTLE",$user]);

      # We quit the foreach loop (no need to test other forbidden word)
      last;

    }

  }
  
}

# This callback is called when the plugin is unloaded
sub onUnload {

  # We remove our lobby command handler when the plugin is unloaded
  removeLobbyCommandHandler(['SAIDBATTLE']);

}

1;
