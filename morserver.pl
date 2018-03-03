#!/usr/bin/perl

use threads('stack_size' => 1048576);
use threads::shared;
use IO::Socket::INET;
use Time::HiRes qw(time usleep sleep);
use JSON;
use FindBin qw($RealBin);
use IPC::Open3;
use Proc::Killfam;


use HTTP::Response;
use URI::URL;

use strict;
use warnings;

use constant true  => 1;
use constant false => 0;

use Data::Dumper;



require $RealBin . "/core/settings.pl";
require $RealBin . "/core/share.pm";
require $RealBin . "/core/redis.pm";
require $RealBin . "/core/database.pm";
require $RealBin . "/core/functions.pm";
require $RealBin . "/core/flow.pm";
require $RealBin . "/core/stream.pm";
require $RealBin . "/core/readfile.pm";
require $RealBin . "/core/connection.pm";



$| = 1;
$SIG{PIPE} = 'IGNORE';
$SIG{CHLD} = 'IGNORE';

our $shared_last_listener	: shared = 0;
our %shared_listeners		: shared;
our @shared_gone			: shared;

our $server_unique_prefix = unique_listener_id() . "_";

# Statistical data counters
our $stat_tracks_played		: shared = 0;
our $stat_server_bytes_in	: shared = 0;
our $stat_server_bytes_out	: shared = 0;
our $stat_client_bytes		: shared = 0;
our $stat_clients_total		: shared = 0;
our $stat_clients_5min		: shared = 0;
our $stat_jingle_streams	: shared = 0;
our $stat_jingle_plays		: shared = 0;
our $static_start_time		: shared = time();

my $max_header_size			= 4096;


my $listen = IO::Socket::INET->new(
	LocalPort => Settings::settings()->{streaming}->{listen_port}, 
	LocalAddr => Settings::settings()->{streaming}->{listen_host},
	ReuseAddr => 1, 
	Listen => 4096
) || die("Cant create socket!");

printf("Audio streamer is started listening on http://%s:%d/\n", 
	Settings::settings()->{streaming}->{listen_host}, 
	Settings::settings()->{streaming}->{listen_port});

threads->create('stats_control');

while (my $socket = $listen->accept) {
    async(\&handle_connection, $socket)->detach;
}

sub handle_connection {
	
    my $socket = shift;
    my $output = shift || $socket;
    my $exit = 0;
	
	my $header_string = "";
	
	RUN: while (<$socket>) {

		if(length($header_string) < $max_header_size)
		{
			$header_string .= $_;
		}
		else
		{
			http_large();
			last RUN;
		}
		
		print $_;
	
		if( m/^\r\n$/ )
		{
			my $r = HTTP::Response->parse( $header_string );
			my $uri = URI->new($r->{_rc});
			my $query = $uri->query_form;
			my $path = $uri->path;

			http_request($r, {$uri->query_form}, $uri->path, $socket, $output);
			
			$exit = 1;
		}
		
        if($exit)
		{
			last RUN;
		}
    }
	
	# Exit a thread
    threads->exit();
}


sub stats_control
{
	
	while(1)
	{
		sleep(10);
	
		while(my $l = shift @shared_gone)
		{
			delete $shared_listeners{$l};
			Database::query_update("CALL moveListenerToLog(?)", $l);
		}
		
		foreach my $key (keys %shared_listeners)
		{
			my $decoded = decode_json($shared_listeners{$key});
			Database::query_update("INSERT INTO `r_listener` SET `listener_id` = ?, `client_ip` = ?, `client_ua` = ?, `stream_id` = ?, `bitrate` = ?, `last_activity` = ?, `listening_time` = ?, `connected_at` = FROM_UNIXTIME(?) ON DUPLICATE KEY UPDATE `last_activity` = ?, `listening_time` = ?",  
				$key, $decoded->{client_ip}, $decoded->{client_ua}, $decoded->{stream_id}, $decoded->{stream_br}, time(), $decoded->{connected}, $decoded->{connected_at}, time(), $decoded->{connected}
			);
		}
		
		
			
	}
}


sub http_responce
{
	my $icy_enabled = shift;
	my $icy_title = shift;
	my $responce = "";
	
	$responce .= "HTTP/1.1 200 OK\r\n";
	$responce .= "Content-Type: audio/mpeg\r\n";
	$responce .= "Server: myownradio.biz audio server 1.1\r\n";
	
	if ($icy_enabled)
	{
		$responce .= "icy-metadata: 1\r\n";
		$responce .= "icy-name: " . $icy_title . "\r\n";
		$responce .= "icy-notice1: This stream requires Winamp\r\n";
		$responce .= "icy-notice2: My Own Radio Audio Server/FreeBSD v1.0\r\n";
		$responce .= "icy-metaint: 8192\r\n";
	}
	$responce .= "\r\n";
	return $responce;
}


sub http_404
{
	my $responce = "";
	$responce .= "HTTP/1.1 404 Not Found\r\n";
	$responce .= "Connection: keep-alive\r\n";
	$responce .= "Content-Type: text/html; charset=utf-8\r\n";
	$responce .= "Server: myownradiostreamer 1.0\r\n";
	$responce .= "\r\n";
	$responce .= "<html><body><h1>404 Not Found</h1></body></html>";
	return $responce;
}

sub http_large
{
	my $responce = "";
	$responce .= "HTTP/1.1 413 Entity Too Large\r\n";
	$responce .= "Connection: keep-alive\r\n";
	$responce .= "Content-Type: text/html; charset=utf-8\r\n";
	$responce .= "Server: myownradiostreamer 1.0\r\n";
	$responce .= "\r\n";
	$responce .= "<html><body><h1>413 Entity Too Large</h1></body></html>";
	return $responce;
}

