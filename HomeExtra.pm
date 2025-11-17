package Plugins::1001Albums::HomeExtra;

use strict;

use base qw(Plugins::MaterialSkin::HomeExtraBase);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.1001albums');

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed => \&handleFeed,
		tag  => '1001AlbumsHome',
		extra => {
			title => 'PLUGIN_1001_ALBUMS',
			icon  => Plugins::1001Albums::Plugin->_pluginDataFor('icon'),
			needsPlayer => 1,
		}
	);
}

sub handleFeed {
	my ($client, $cb, $args) = @_;

	$args->{params}->{menu} = 'home_heroes';

	Plugins::1001Albums::Plugin::handleFeed($client, $cb, $args);
}

1;