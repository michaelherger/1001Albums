package Plugins::1001Albums::Plugin;

use strict;

use Date::Parse qw(str2time);
use JSON::XS::VersionOneAndTwo;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Schema;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(cstring);

use constant BASE_URL => 'https://1001albumsgenerator.com/';
use constant ALBUM_URL => BASE_URL . 'api/v1/projects/';
use constant DONATION_URL => BASE_URL . 'info/info#donations';

my $log = Slim::Utils::Log->addLogCategory({
	'category'    => 'plugin.1001albums',
	'description' => 'PLUGIN_1001_ALBUMS',
});

my $prefs = preferences('plugin.1001albums');
$prefs->init({
	username => ''
});

my ($hasDeezer, $hasSpotty, $hasQobuz, $hasTIDAL, $hasYT);
my @albumFetchers = (\&dbAlbumItem);

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

	if ( $hasQobuz = Slim::Utils::PluginManager->isEnabled('Plugins::Qobuz::Plugin') ) {
		main::INFOLOG && $log->is_info && $log->info("Qobuz plugin is enabled");
		require Plugins::1001Albums::Qobuz;
		push @albumFetchers, \&qobuzAlbumItem;
	}

	if ( $hasTIDAL = Slim::Utils::PluginManager->isEnabled('Plugins::TIDAL::Plugin') ) {
		main::INFOLOG && $log->is_info && $log->info("TIDAL plugin is enabled");
		push @albumFetchers, \&tidalAlbumItem;
	}

	if ( $hasDeezer = Slim::Utils::PluginManager->isEnabled('Plugins::Deezer::Plugin') ) {
		main::INFOLOG && $log->is_info && $log->info("Deezer plugin is enabled");
		require Plugins::1001Albums::Deezer;
		push @albumFetchers, \&deezerAlbumItem;
	}

	if ( $hasSpotty = Slim::Utils::PluginManager->isEnabled('Plugins::Spotty::Plugin') ) {
		main::INFOLOG && $log->is_info && $log->info("Spotty plugin is enabled");
		push @albumFetchers, \&spotifyAlbumItem;
	}

	if ( $hasYT = Slim::Utils::PluginManager->isEnabled('Plugins::YouTube::Plugin') ) {
		main::INFOLOG && $log->is_info && $log->info("YouTube plugin is enabled");
		push @albumFetchers, \&ytAlbumItem;
	}

	if (@albumFetchers == 1) {
		$log->error("This plugin requires a streaming service to work properly - unless you own all 1001 albums already.");
	}

	if ( Slim::Utils::PluginManager->isEnabled('Plugins::MaterialSkin::Plugin') && Plugins::MaterialSkin::Plugin->can('registerHomeExtra') ) {
		eval {
			require Plugins::1001Albums::HomeExtra;
		};
		$log->error("Could not load 1001 Albums Home Extra: $@") if $@;
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

			if (main::DEBUGLOG && $log->is_debug) {
				$log->debug(Data::Dump::dump($albumData));
			}
			elsif (main::INFOLOG && $log->is_info) {
				my $limitedAlbumData = Storable::dclone($albumData);
				$limitedAlbumData->{history} = ['...'];
				$log->info(Data::Dump::dump($limitedAlbumData));
			}

			my $items = [];

			if (!$prefs->get('username')) {
				push @$items, [{ name => cstring($client, 'PLUGIN_1001_ALBUMS_MISSING_USERNAME') }]
			}

			if ($albumData && ref $albumData && !$albumData->{paused} && (my $currentAlbum = $albumData->{currentAlbum})) {
				push @$items, getAlbumItem($client, $currentAlbum);

				push @$items, {
					name => $client->string('PLUGIN_1001_ALBUMS_REVIEWS'),
					image => 'plugins/1001Albums/html/albumreviews_MTL_icon_rate_review.png',
					weblink => $currentAlbum->{globalReviewsUrl}
				} if $currentAlbum->{globalReviewsUrl} && canWeblink($client);

				if ($albumData->{history}) {
					my $historyItems = [];
					my $ratedItems = [[], [], [], [], [], []]; # 0-5 stars

					foreach (@{$albumData->{history}}) {
						my $item = getAlbumItem($client, $_->{album}, str2time($_->{generatedAt}));
						next unless $item && $item->{url};

						unshift @$historyItems, $item;
						unshift @{$ratedItems->[$_->{rating} || 0]}, $item;
					}

					push @$items, {
						name  => cstring($client, 'PLUGIN_1001_ALBUMS_HISTORY'),
						image => 'plugins/1001Albums/html/history_MTL_icon_history.png',
						type  => 'outline',
						items => $historyItems
					} if scalar @$historyItems;

					for (my $i = 5; $i >= 0; $i--) {
						my $starItems = $ratedItems->[$i];
						next unless scalar @$starItems;

						push @$items, {
							name  => cstring($client, "PLUGIN_1001_ALBUMS_${i}_STARS"),
							image => "plugins/1001Albums/html/${i}star_svg.png",
							type  => 'outline',
							items => $starItems
						};
					}
				}
			}

			if ($albumData && $albumData->{paused}) {
				push @$items, {
					name => $client->string('PLUGIN_1001_PROJECT_PAUSED'),
					image => 'plugins/1001Albums/html/profile_MTL_icon_bar_chart.png',
					weblink => BASE_URL . $prefs->get('username'),
				};
			}
			elsif (canWeblink($client)) {
				push @$items, {
					name => $client->string('PLUGIN_1001_PROJECT_PAGE'),
					image => 'plugins/1001Albums/html/profile_MTL_icon_bar_chart.png',
					weblink => BASE_URL . $prefs->get('username'),
				};
			}

			push @$items, {
				name => $client->string('PLUGIN_1001_ALBUMS_DONATE'),
				image => 'plugins/1001Albums/html/donate_MTL_icon_volunteer_activism.png',
				weblink => DONATION_URL
			},{
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

			if ($error =~ /429 too many/i) {
				return $cb->([{
					name => cstring($client, 'PLUGIN_1001_ALBUMS_429'),
					type => 'text'
				}]);
			}

			$cb->([{ name => cstring($client, 'EMPTY') }]);
		},
		{
			cache => 1,
			expires => 15 * 60
		},
	)->get(ALBUM_URL . $prefs->get('username'));
}

sub getAlbumItem {
	my ($client, $album, $timestamp) = @_;

	my $item;

	for my $fetcher (@albumFetchers) {
		$item = $fetcher->($client, $album);
		last if $item;
	}

	if ($item && $item->{url}) {
		$item->{line2} .= ' - ' . Slim::Utils::DateTime::shortDateF($timestamp);
		$item->{name}  .= ' - ' . Slim::Utils::DateTime::shortDateF($timestamp);
	}

	main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($item));

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

	my $dbh = Slim::Schema->dbh;
	my $sth = $dbh->prepare_cached(q(
		SELECT albums.id AS id, albums.title AS title, contributors.name AS name, albums.extid AS extid
		FROM albums
			JOIN contributors ON contributors.id = albums.contributor
		WHERE contributors.namesearch = ? AND albums.titlesearch = ?
		LIMIT 1
	));

	$sth->execute(Slim::Utils::Text::ignoreCase($args->{artist}), Slim::Utils::Text::ignoreCase($args->{name}));

	my $albumHash = $sth->fetchrow_hashref || {};
	$sth->finish;

	if ($albumHash->{id}) {
		my $item = _baseAlbumItem($client, $args);
		$item->{url} = $item->{playlist} = \&Slim::Menu::BrowseLibrary::_tracks;
		$item->{passthrough} = [ { searchTags => ["album_id:" . $albumHash->{id}], library_id => -1 } ],
		$item->{favorites_url} = $albumHash->{extid} || sprintf('db:album.title=%s&contributor.name=%s', URI::Escape::uri_escape_utf8($albumHash->{title}), URI::Escape::uri_escape_utf8($albumHash->{name})),

		return $item;
	}
}

sub deezerAlbumItem {
	my ($client, $args) = @_;

	return unless $hasDeezer;

	my $id = $args->{deezerId} || Plugins::1001Albums::Deezer->getId($args->{spotifyId}) || return;

	my $item = _baseAlbumItem($client, $args);

	if ($id ne '-1') {
		$item->{url} = $item->{playlist} = "deezer://album:$id";
		return $item;
	}

	$item->{url} = $item->{playlist} = \&Plugins::1001Albums::Deezer::getAlbum;
	$item->{passthrough} = [{
		album_id => $id,
		album_title => $args->{name},
		album_artist => $args->{artist},
	}];

	return $item;
}

sub spotifyAlbumItem {
	my ($client, $args) = @_;

	return unless $hasSpotty && $args->{spotifyId};

	my $item = _baseAlbumItem($client, $args);
	$item->{url} = $item->{playlist} = 'spotify:album:' . $args->{spotifyId};

	return $item;
}

sub ytAlbumItem {
	my ($client, $args) = @_;

	return unless $hasYT && $args->{youtubeMusicId};

	my $item = _baseAlbumItem($client, $args);

	$args->{youtubeMusicId} =~ s/[&?].*//;	# Everything up to & to handle 1234asbcXYZ&feature=share or perhaps ?something
	$item->{url} = $item->{playlist} = 'https://music.youtube.com/playlist?list=' . $args->{youtubeMusicId};

	return $item;
}

sub tidalAlbumItem {
	my ($client, $args) = @_;

	return unless $hasTIDAL && $client && $args->{tidalId};

	my $item = _baseAlbumItem($client, $args);
	$item->{url} = $item->{playlist} = 'https://tidal.com/browse/album/' . $args->{tidalId};

	return $item;
}

sub qobuzAlbumItem {
	my ($client, $args) = @_;

	return unless $hasQobuz;

	my $id = $args->{qobuzId} || Plugins::1001Albums::Qobuz->getId($args->{spotifyId}) || return;

	my $item = _baseAlbumItem($client, $args);

	if ($id ne '-1') {
		$item->{url} = $item->{playlist} = "qobuz:album:$id";
		return $item;
	}

	$item->{url} = $item->{playlist} = \&Plugins::1001Albums::Qobuz::getAlbum;
	$item->{passthrough} = [{
		album_id => $id,
		album_title => $args->{name},
		album_artist => $args->{artist},
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
