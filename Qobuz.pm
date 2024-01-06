package Plugins::1001Albums::Qobuz;

use strict;

use Text::Levenshtein;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::Qobuz::Plugin;
use Plugins::Qobuz::API;

my $log = logger('plugin.1001albums');

use constant MAX_DISTANCE => 5;

# Some tracks I didn't find on Qobuz, but they might be available in other regions.
# Return a truthy value which would cause the plugin to use text search anyway.
my $spotify2QobuzMap = 	{
	"0cGaQUOlAm0smFXWUB8KIL" => "-1",
	"0w8692CEApsMHme5SwpOjw" => "-1",
	"111J9nxmdhyHSLNHeAL1jO" => "-1",
	"3KzwlFAMKB3eVsCP2NyDwN" => "-1",
	"4A10zgDO51IMdrLVfUnhh8" => "-1",
	"4CgweKiwA0yckiVbG6eUJI" => "-1",
	"4dgAnIHFpnFdSBqpRZheHq" => "-1",
	"4gn6f5jaOO75s0oF7ozqGG" => "-1",
	"4VcKXOCUzcrxltYt0Jyqfk" => "-1",
	"4WznTvC9d1Oino7gLS8XHq" => "-1",
	"4x2er6NU84V8bOjj1KE5Hh" => "-1",
	"5pgaVcKREhdQ3OI7ZvP9tv" => "-1",
	"5wnhqlZzXIq8aO9awQO2ND" => "-1",
	"5yvjiLsbi25u0PjdpqQM2S" => "-1",
	"61YthmX9Hi1gyqVl0MGEy2" => "-1",
	"63Eji2cNg0vH9sYqxg5iHI" => "-1",
	"6hHhe2mLkUJFPpXYu83YBK" => "-1",
	"6QDLJorX8HQ2ogxZUCvtd1" => "-1",
};

sub getId { $spotify2QobuzMap->{$_[1]} }

sub getAlbum {
	my ($client, $cb, $params, $args) = @_;

	my $albumId = $args->{album_id};

	return searchAlbum($client, $cb, $params, $args) if $albumId == -1;

	Plugins::Qobuz::API->getAlbum(sub {
		my $album = shift;

		if ($album) {
			main::INFOLOG && $log->is_info && $log->info("Found Qobuz track by ID: $albumId");
			return Plugins::Qobuz::Plugin::QobuzGetTracks($client, $cb, $params, $args);
		}

		return searchAlbum($client, $cb, $params, $args);
	}, $albumId);
}

sub searchAlbum {
	my ($client, $cb, $params, $args) = @_;

	my $albumName = lc($args->{album_title});
	my $artist = lc($args->{album_artist});

	main::INFOLOG && $log->is_info && $log->info("Did not find Qobuz track by ID, try text search instead: $albumName - $artist");

	Plugins::Qobuz::API->search(sub {
		my $searchResult = shift;

		if (!$searchResult || !$searchResult->{albums}->{items}) {
			# TODO do something
			$cb->({ items => [{ name => cstring($client, 'EMPTY') }] });
			return;
		}

		my $candidate;

		for my $weak (0, 1) {
			for my $album ( @{$searchResult->{albums}->{items} || []} ) {
				if (main::DEBUGLOG && $log->is_debug) {
					$log->debug(Data::Dump::dump({
						artist => $album->{artist}->{name},
						album => $album->{title},
					}));
				}

				# Elvis Costello has enough albums on that list to deserve some special treatment...
				$artist =~ s/(Elvis Costello) & The Attractions/$1/i if $weak;

				next if !$album->{artist} || !$album->{title};
				next if !$weak && lc($album->{artist}->{name}) ne $artist;
				next if $weak && $album->{artist}->{name} !~ /\b\Q$artist\E\b/i && Text::Levenshtein::distance(lc($album->{artist}->{name}), $artist) > MAX_DISTANCE;

				if ( lc($album->{title}) eq $albumName || ($weak && (
						$album->{title} =~ /\b\Q$albumName\E\b/i
						|| $albumName =~ /\b\Q$album->{title}\E\b/i
						|| Text::Levenshtein::distance(lc($album->{title}), $albumName) <= MAX_DISTANCE)
				)) {
					$candidate = $album;
					last;
				}
			}

			last if $candidate;
		}

		if ($candidate) {
			return Plugins::Qobuz::Plugin::QobuzGetTracks($client, $cb, $params, {
				album_id => $candidate->{id}
			});
		}

		# TODO do something useful...
		$cb->({ items => [{ name => cstring($client, 'EMPTY') }] });
	}, $albumName, 'albums', {
		limit => 10
	});
}

1;