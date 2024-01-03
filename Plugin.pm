package Plugins::1001Albums::Plugin;

use strict;

use Date::Parse qw(str2time);
use JSON::XS::VersionOneAndTwo;
use Text::Levenshtein;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use constant BASE_URL => 'https://1001albumsgenerator.com/';
use constant ALBUM_URL => 'https://1001albumsgenerator.com/api/v1/projects/';
use constant MAX_DISTANCE => 5;

my $log = Slim::Utils::Log->addLogCategory({
	'category'    => 'plugin.1001albums',
	'description' => 'PLUGIN_1001_ALBUMS',
});

my $prefs = preferences('plugin.1001albums');
$prefs->init({
	username => ''
});

my ($hasSpotty, $hasQobuz, $hasTIDAL);

sub initPlugin {
	my $class = shift;

	if (main::WEBUI) {
		require Plugins::1001Albums::Settings;
		Plugins::1001Albums::Settings->new();
	}

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => '1001Albums',
		menu   => 'radios',
		is_app => 1,
		weight => 1,
	);
}

sub postinitPlugin {
	my $class = shift;

	if ( Slim::Utils::PluginManager->isEnabled('Plugins::Spotty::Plugin') ) {
		$hasSpotty = 1;
	}

	if ( Slim::Utils::PluginManager->isEnabled('Plugins::Qobuz::Plugin') ) {
		$hasQobuz = 1;
	}

	if ( !$Plugins::LastMix::Plugin::NOMYSB && Slim::Utils::PluginManager->isEnabled('Slim::Plugin::WiMP::Plugin') ) {
		$hasTIDAL = 1;
	}

	if (!$hasSpotty && !$hasQobuz) {
		$log->error("This plugin requires a streaming service to work properly - unless you own all 1001 albums already.");
	}
}

sub handleFeed {
	my ($client, $cb) = @_;

	if (!$prefs->get('username')) {
		return $cb->([{
			name => cstring($client, 'PLUGIN_1001_ALBUMS_MISSING_USERNAME'),
			type => 'text'
		},{
			name => $client->string('PLUGIN_1001_ALBUMS_MORE_INFORMATION'),
			weblink => BASE_URL
		}]);
	}

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;

			my $albumData = eval { from_json($response->content) };

			$@ && $log->error($@);
			main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($albumData));

			my $items = [{
				items => $prefs->get('username')
					? [{ name => cstring($client, 'EMPTY') }]
					: [{ name => cstring($client, 'PLUGIN_1001_ALBUMS_MISSING_USERNAME') }]
			}];

			if ($albumData && ref $albumData && (my $currentAlbum = $albumData->{currentAlbum})) {
				my $item = getAlbumItem($client, $currentAlbum);

				if ($item) {
					$items = [$item];
				}

				push @$items, {
					name => $client->string('PLUGIN_1001_ALBUMS_REVIEWS'),
					image => 'plugins/1001Albums/html/albumreviews_MTL_icon_rate_review.png',
					weblink => $currentAlbum->{globalReviewsUrl}
				} if $currentAlbum->{globalReviewsUrl} && canWeblink($client);

				if ($albumData->{history}) {
					my $historyItems = [];

					foreach (@{$albumData->{history}}) {
						my $item = getAlbumItem($client, $_->{album}, str2time($_->{generatedAt}));
						unshift @$historyItems, $item if $item && $item->{url};
					}

					push @$items, {
						name  => cstring($client, 'PLUGIN_1001_ALBUMS_HISTORY'),
						image => 'plugins/1001Albums/html/history_MTL_icon_history.png',
						type  => 'outline',
						items => $historyItems
					} if scalar @$historyItems;
				}
			}

			push @$items, {
				name => $client->string('PLUGIN_1001_PROJECT_PAGE'),
				image => 'plugins/1001Albums/html/profile_MTL_icon_bar_chart.png',
				weblink => BASE_URL . $prefs->get('username'),
			} if canWeblink($client);

			push @$items, {
				name => $client->string('PLUGIN_1001_ALBUMS_ABOUT'),
				image => __PACKAGE__->_pluginDataFor('icon'),
				weblink => BASE_URL
			} if canWeblink($client);

			return $cb->({
				items => $items
			});
		},
		sub {
			my ($http, $error) = @_;

			$log->warn("Error: $error");
			$cb->();
		},
		{
			cache => 1,
			expires => '1h'
		},
	)->get(ALBUM_URL . $prefs->get('username'));
}

sub getAlbumItem {
	my ($client, $album, $timestamp) = @_;

	my $item = dbAlbumItem($client, $album)
		|| spotifyAlbumItem($client, $album)
		|| tidalAlbumItem($client, $album)
		|| qobuzAlbumItem($client, $album);

	if ($item && $item->{url}) {
		$item->{line2} .= ' - ' . Slim::Utils::DateTime::shortDateF($timestamp);
		$item->{name}  .= ' - ' . Slim::Utils::DateTime::shortDateF($timestamp);
	}

	return $item;
}

sub _baseAlbumItem {
	my ($client, $args) = @_;

	return {
		name  => $args->{name} . ' ' . cstring($client, 'BY') . ' ' . $args->{artist},
		line1 => $args->{name},
		line2 => $args->{artist},
		image => $args->{images}->[0]->{url},
		type  => 'playlist',
	}
}

sub dbAlbumItem {
	my ($client, $args) = @_;

	my $album = Slim::Schema->rs('Album')->search({
		title => { like => $args->{name} },
		'contributor.name' => { like => $args->{artist} },
	},{
		prefetch => 'contributor'
	})->first();

	if ($album) {
		my $item = _baseAlbumItem($client, $args);
		$item->{url} = $item->{playlist} = \&Slim::Menu::BrowseLibrary::_tracks;
		$item->{passthrough} = [ { searchTags => ["album_id:" . $album->id], library_id => -1 } ],
		$item->{favorites_url} = $album->extid || sprintf('db:album.title=%s&contributor.name=%s', URI::Escape::uri_escape_utf8($album->name), URI::Escape::uri_escape_utf8($args->{artist})),

		return $item;
	}
}

sub spotifyAlbumItem {
	my ($client, $args) = @_;

	return unless $hasSpotty && $args->{spotifyId};

	return Plugins::Spotty::OPML::_albumItem($client, {
		name    => $args->{name},
		artists => [{ name => $args->{artist}}],
		uri     => 'spotify:album:' . $args->{spotifyId},
		image   => $args->{images}->[0]->{url},
	});
}

sub tidalAlbumItem {
	my ($client, $args) = @_;

	return unless $hasTIDAL && $client && ( $client->isAppEnabled('WiMP') || $client->isAppEnabled('WiMPDK') );

	my $item = _baseAlbumItem($client, $args);
	$item->{url} = $item->{playlist} = 'https://tidal.com/browse/album/' . $args->{tidalId};

	return $item;
}

sub qobuzAlbumItem {
	my ($client, $args) = @_;

	return unless $hasQobuz && $args->{qobuzId};

	my $item = _baseAlbumItem($client, $args);
	$item->{url} = $item->{playlist} = \&Plugins::Qobuz::Plugin::QobuzGetTracks;
	$item->{passthrough} = [{
		album_id => $args->{qobuzId},
		album_title => $args->{name},
	}];

	return $item;
}

# Keep in sync with Qobuz plugin
my $WEBLINK_SUPPORTED_UA_RE = qr/\b(?:iPeng|SqueezePad|OrangeSqueeze|OpenSqueeze|Squeezer|Squeeze-Control)\b/i;
my $WEBBROWSER_UA_RE = qr/\b(?:FireFox|Chrome|Safari)\b/i;

sub canWeblink {
	my ($client) = @_;
	return $client && (!$client->controllerUA || ($client->controllerUA =~ $WEBLINK_SUPPORTED_UA_RE || $client->controllerUA =~ $WEBBROWSER_UA_RE));
}


1;
