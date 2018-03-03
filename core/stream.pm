#!/usr/bin/perl

package Stream;

use strict;
use warnings;

use Time::HiRes qw(time);

use constant true  => 1;
use constant false => 0;

use Data::Dumper;
use JSON;

my $stream_id = undef;

sub new
{
	my $class        = shift;
	$stream_id	     = shift;
	my $self         = { name => "Stream", version => "1.0" };
	bless $self;
	return $self;
}

sub getTitle
{
	my $this = shift;
	return Database::query_single_col("SELECT `name` FROM `r_streams` WHERE `sid` = ? LIMIT 1", $stream_id);
}

sub available
{
	my $this = shift;
	my $stream_data = Database::query_single_row("SELECT * FROM `r_streams` WHERE `sid` = ? LIMIT 1", $stream_id);
	
	unless($stream_data)
	{
		printf ("DEBUG: Stream %d unavailable\n", $stream_id) if (Settings::settings()->{streaming}->{debug} eq "yes");
		return false; 
	} 
	
	return true;
}

sub getPlayingTrack
{
	my $this = shift;
	my $preload = shift || 0;
	my $start = time();
	
	my $stream_info = Database::query_single_row("SELECT * FROM `r_streams` WHERE `sid` = ?", $stream_id);
	
	return false if $stream_info->{status} != 1;
	
	# Current stream tracklist
	# my $stream_tracks = Database::query("SELECT a.*, b.`unique_id`, b.`t_order`, b.`time_offset` FROM `r_tracks` a, `r_link` b WHERE a.`tid` = b.`track_id` AND b.`stream_id` = ? AND a.`lores` = 1 ORDER BY b.`t_order`", $stream_id);
	my $stream_static_duration = Database::query_single_col("SELECT `tracks_duration` FROM `r_static_stream_vars` WHERE `stream_id` = ?", $stream_id);

	return false if $stream_static_duration == 0;

	# Current position
	my $stream_position = (time() * 1000 - $stream_info->{started} + $stream_info->{started_from} - $preload) % $stream_static_duration;

	# Fast next track query
	my $i = Database::query_single_row("SELECT a.*, b.`unique_id`, b.`t_order`, b.`time_offset` FROM `r_tracks` a, `r_link` b WHERE b.`time_offset` <= ? AND b.`time_offset` + a.`duration` >= ? AND a.`tid` = b.`track_id` AND b.`stream_id` = ? AND a.`lores` = 1 ORDER BY b.`t_order`", $stream_position, $stream_position, $stream_id);
	
	unless($i) { return false; }
	
	my $time = time() * 1000;
	$i->{cursor} = $stream_position - $i->{time_offset};
	$i->{must_start} = $time - $i->{cursor};
	$i->{must_end} = $i->{must_start} + $i->{duration};
	return $i;
	
}

sub generatePath 
{
	my $this = shift;
	my $root = shift;
	my $track = shift;
	return sprintf("%s/ui_%d/lores_%03d.mp3", $root, $track->{'uid'}, $track->{'tid'});
}

sub generatePathOriginal 
{
	my $this = shift;
	my $root = shift;
	my $track = shift;
	return sprintf("%s/ui_%d/a_%04d_original.%s", $root, $track->{'uid'}, $track->{'tid'}, $track->{'ext'});
}

1;