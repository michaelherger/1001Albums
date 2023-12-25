package Plugins::1001Albums::Plugin;

use strict;
use JSON::XS::VersionOneAndTwo;

use base qw(Slim::Plugin::OPMLBased);

use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use constant ALBUM_URL => 'https://1001albumsgenerator.com/api/v1/projects/';

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.1001albums',
	'description'  => 'PLUGIN_1001_ALBUMS',
});

my $prefs = preferences('plugin.1001albums');
$prefs->init({
	history => [],
	username => ''
});

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(
		feed   => \&handleFeed,
		tag    => '1001Albums',
		menu   => 'radios',
		is_app => 1,
		weight => 1,
	);
}

sub handleFeed {
	my ($client, $cb) = @_;

	Slim::Networking::SimpleAsyncHTTP->new(
		sub {
			my $response = shift;

			my $albumData = eval { from_json($response->content) };
			$albumData->{timestamp} = time();

			my $history = $prefs->get('history');
			if (!$history->[-1] || $history->[-1]->{shareableUrl} ne $albumData->{shareableUrl}) {
				warn 'history';
				push @$history, $albumData;
			}

			$@ && $log->error($@);
			main::DEBUGLOG && $log->is_debug && $log->debug(Data::Dump::dump($albumData));

			if ($albumData && ref $albumData) {
				$albumData->{currentAlbum}->{image} = $albumData->{currentAlbum}->{images}->[0]->{url};

				my $item = dbAlbumItem($client, $albumData->{currentAlbum})
					|| spotifyAlbumItem($client, $albumData->{currentAlbum});


				$item->{line2} .= ' - ' . Slim::Utils::DateTime::shortDateF() if $item && $item->{url};

				return $cb->({
					items => [$item]
				});
			}

			$cb->();
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
			name          => $args->{name},
			line2         => $args->{artist},
			image         => $args->{image},
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

	return unless $args->{spotifyId};

	return Plugins::Spotty::OPML::_albumItem($client, {
		name    => $args->{name},
		artists => [{ name => $args->{artist}}],
		uri     => 'spotify:album:' . $args->{spotifyId},
		image   => $args->{images}->[0]->{url},
	});
}

1;
