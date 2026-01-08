package Plugins::1001Albums::HomeExtra;

use strict;

use base qw(Plugins::MaterialSkin::HomeExtraBase);

use constant UPDATE_INTERVAL => 7200;

use Slim::Utils::Log;
use Slim::Utils::Prefs;

my $prefs = preferences('plugin.1001albums');
my $log = logger('plugin.1001albums');

__PACKAGE__->initPlugin();

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed => \&Plugins::1001Albums::Plugin::handleFeed,
		tag  => '1001AlbumsHome',
		extra => {
			title => 'PLUGIN_1001_ALBUMS',
			icon  => Plugins::1001Albums::Plugin->_pluginDataFor('icon'),
			needsPlayer => 1,
		}
	);

	if (Plugins::MaterialSkin::Plugin->can('signalHomeExtraUpdate')) {
		Slim::Utils::Timers::setTimer(undef, time() + UPDATE_INTERVAL, \&requestHomeExtrasUpdate);
	}
}

sub requestHomeExtrasUpdate{
	main::INFOLOG && $log->is_info && $log->info("Tell MaterialSkin to update the Home Extras");
	Slim::Utils::Timers::killTimers(undef, \&requestHomeExtrasUpdate);
	Plugins::MaterialSkin::Plugin::signalHomeExtraUpdate();
	Slim::Utils::Timers::setTimer(undef, time() + UPDATE_INTERVAL, \&requestHomeExtrasUpdate);
}

1;