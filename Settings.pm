package Plugins::1001Albums::Settings;

use strict;
use base qw(Slim::Web::Settings);
use JSON::XS::VersionOneAndTwo;

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.1001albums');
my $log = Slim::Utils::Log::logger('plugin.1001albums');

sub name { Slim::Web::HTTP::CSRF->protectName('PLUGIN_1001_ALBUMS_SHORT') }

sub page { 'plugins/1001Albums/settings.html' }

sub prefs {
	return ($prefs, qw(username));
}

sub handler {
	my ($class, $client, $params, $callback, @args) = @_;

	if ($params->{saveSettings} && $params->{pref_username}) {
		my $cb = sub {
			my ($response, $error) = @_;

			my $profile = eval { from_json($response->content) } unless $error;

			if ($error || $@ || !$profile) {
				delete $params->{saveSettings};
				$error ||= $@ || 'profile not found';
				$log->error("Failed profile validation: $error");
				$params->{validation_error} = Slim::Utils::Strings::string('PLUGIN_1001_ALBUMS_FAILED_VALIDATION', $error);
			}

			main::DEBUGLOG && $log->is_debug && $profile && $log->debug(Data::Dump::dump($profile));

			return $callback->( $client, $params, $class->SUPER::handler($client, $params), @args );
		};

		Slim::Networking::SimpleAsyncHTTP->new($cb, $cb, {
			cache => 0,
		})->get(Plugins::1001Albums::Plugin::ALBUM_URL . URI::Escape::uri_escape_utf8($params->{pref_username}));

		return;
	}

	$params->{infolink} = Plugins::1001Albums::Plugin::BASE_URL;

	return $class->SUPER::handler($client, $params);
}

1;