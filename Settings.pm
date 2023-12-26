package Plugins::1001Albums::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.1001albums');

sub name { Slim::Web::HTTP::CSRF->protectName('PLUGIN_1001_ALBUMS_SHORT') }

sub page { 'plugins/1001Albums/settings.html' }

sub prefs {
	return ($prefs, qw(username));
}

1;