package Plugins::1001Albums::Deezer;

use strict;

use Text::Levenshtein;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::Deezer::Plugin;
use Plugins::Deezer::API::Async;

my $log = logger('plugin.1001albums');

use constant MAX_DISTANCE => 5;

# Some albums we didn't find on Deezer, but they might be available in other regions.
# Return a truthy value which would cause the plugin to use text search anyway.
my $spotify2DeezerMap = 	{
	'0cGaQUOlAm0smFXWUB8KIL' => -1,
	'0ETFjACtuP2ADo6LFhL6HN' => 12047952,
	'63k57x0qOkUWEMR0dkMivh' => 6237061,
};

sub getId {
	# return 12047952;
	return -1;
	$spotify2DeezerMap->{$_[1]} }

sub getAlbum {
	my ($client, $cb, $params, $args) = @_;

	my $albumName = lc($args->{album_title});
	my $artist = lc($args->{album_artist});

	main::INFOLOG && $log->is_info && $log->info("Did not find Deezer album by ID, try text search instead: \"$args->{album_title}\" by $args->{album_artist}");

	Plugins::Deezer::Plugin::getAPIHandler($client)->search(sub {
		my $searchResult = shift;

		if (!$searchResult || ref $searchResult ne 'ARRAY') {
			# TODO do something
			$cb->({ items => [{ name => cstring($client, 'EMPTY') }] });
			return;
		}

		my $candidate;

		for my $weak (0, 1) {
			for my $album ( @$searchResult ) {
				if (main::DEBUGLOG && $log->is_debug) {
					$log->debug(Data::Dump::dump({
						artist => $album->{artist}->{name},
						album => $album->{title},
					}));
				}

				# Elvis Costello has enough albums on that list to deserve some special treatment...
				$artist =~ s/(elvis costello) & The Attractions/$1/i if $weak;

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
			return Plugins::Deezer::Plugin::getAlbum($client, $cb, $params, {
				id => $candidate->{id},
				title => $candidate->{title},
			});
		}

		# TODO do something useful...
		$cb->({ items => [{ name => cstring($client, 'EMPTY') }] });
	},{
		type => 'album',
		search => $albumName,
		limit => 10
	});
}

1;