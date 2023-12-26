package Plugins::1001Albums::Plugin;

use strict;

use Date::Parse qw(str2time);
use JSON::XS::VersionOneAndTwo;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use constant ALBUM_URL => 'https://1001albumsgenerator.com/api/v1/projects/';
use constant INFO_URL => 'https://1001albumsgenerator.com/info/info';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.1001albums',
	'description'  => 'PLUGIN_1001_ALBUMS',
});

my $prefs = preferences('plugin.1001albums');
$prefs->init({
	username => ''
});

my $hasSpotty;

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

	# if user has the Don't Stop The Music plugin enabled, register ourselves
	if ( Slim::Utils::PluginManager->isEnabled('Plugins::Spotty::Plugin') ) {
		$hasSpotty = 1;
	}

	if (!$hasSpotty) {
		$log->error("This plugin requires Spotify to work properly.");
	}
}

sub handleFeed {
	my ($client, $cb) = @_;

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
					image => __PACKAGE__->_pluginDataFor('icon'),
					weblink => $currentAlbum->{globalReviewsUrl}
				} if $currentAlbum->{globalReviewsUrl} && canWeblink($client);

				if ($albumData->{history}) {
					my $historyItems = [];

					foreach (@{$albumData->{history}}) {
						my $item = getAlbumItem($client, $_->{album}, str2time($_->{generatedAt}));
						push @$historyItems, $item if $item && $item->{url};
					}

					push @$items, {
						name  => cstring($client, 'PLUGIN_1001_ALBUMS_HISTORY'),
						image => 'plugins/1001Albums/html/history.png',
						type  => 'outline',
						items => $historyItems
					} if scalar @$historyItems;
				}
			}

			push @$items, {
				name => $client->string('PLUGIN_1001_ALBUMS_ABOUT'),
				image => __PACKAGE__->_pluginDataFor('icon'),
				weblink => INFO_URL
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
		|| spotifyAlbumItem($client, $album);

	if ($item && $item->{url}) {
		$item->{line2} .= ' - ' . Slim::Utils::DateTime::shortDateF($timestamp);
		$item->{name}  .= ' - ' . Slim::Utils::DateTime::shortDateF($timestamp);
	}

	return $item;
}

sub dbAlbumItem {
	my ($client, $args) = @_;

	my $album = Slim::Schema->first('Album', {
		title => $args->{name},
		'contributor.name' => $args->{artist}
	},{
		prefetch => 'contributor'
	});

	if ($album) {
		return {
			name          => $args->{name} . ' ' . cstring($client, 'BY') . ' ' . $args->{artist},
			line1         => $args->{name},
			line2         => $args->{artist},
			image         => $args->{images}->[0]->{url},
			type          => 'playlist',
			playlist      => \&Slim::Menu::BrowseLibrary::_tracks,
			url           => \&Slim::Menu::BrowseLibrary::_tracks,
			passthrough   => [ { searchTags => ["album_id:" . $album->id], library_id => -1 } ],
			favorites_url => $album->extid || sprintf('db:album.title=%s&contributor.name=%s', URI::Escape::uri_escape_utf8($album->name), URI::Escape::uri_escape_utf8($args->{artist})),
		};
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

# Keep in sync with Qobuz plugin
my $WEBLINK_SUPPORTED_UA_RE = qr/\b(?:iPeng|SqueezePad|OrangeSqueeze|OpenSqueeze|Squeezer|Squeeze-Control)\b/i;
my $WEBBROWSER_UA_RE = qr/\b(?:FireFox|Chrome|Safari)\b/i;

sub canWeblink {
	my ($client) = @_;
	return $client && (!$client->controllerUA || ($client->controllerUA =~ $WEBLINK_SUPPORTED_UA_RE || $client->controllerUA =~ $WEBBROWSER_UA_RE));
}


1;
