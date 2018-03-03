#!/usr/bin/perl

package flow;

use Time::HiRes qw(usleep nanosleep);
use POSIX qw(ceil);

use constant true  => 1;
use constant false => 0;

use strict;

my $meta_interval   = 8192,
my $meta_enabled    = false,
my $meta_buffer     = "",
my $meta_title      = "No metadata",
my $meta_new        = true,
my $target			= undef;

sub new
{
	my $class		= shift;

	my $self		= { name => "Flow", version => "1.0" };
	
	bless $self;
	return $self;
}

sub setupIcy
{
	my $this = shift;
	my $icy = shift;
	$meta_enabled = $icy ? true : false;
	return $this;
}

sub setBitrate
{
	my $this = shift;
	return $this;
}

sub setInterval
{
	my $this = shift;
	$meta_interval = shift;
	return $this;
}

sub setTitle
{
	my $this = shift;
	$meta_title = shift;
	$meta_new = true;
	return $this;
}

sub setOutput
{
	my $this = shift;
	$target  = shift;
	return $this;
}

sub writeTag
{
	if($meta_new == true)
	{
		my $meta_pack = "";
		my $title = sprintf("StreamTitle='%s';", $meta_title);
		my $title_length = ceil(length($title) / 16);
		$meta_pack .= pack("C", $title_length);
		$meta_pack .= $title . " " x (($title_length * 16) - length($title));
		$meta_new = true;
		return $meta_pack;
	}
	else
	{
		return pack("C", 0);
	}
	return shift;
}

sub write
{
	my $this = shift;
	my $data = shift;

	$meta_buffer .= $data;
	
	if(length($meta_buffer) >= $meta_interval)
	{
		my @splits = split_string($meta_buffer, $meta_interval);
		
		foreach my $split (@splits)
		{
			if(length($split) == $meta_interval)
			{
				print $target $split;
				print $target writeTag() if($meta_enabled == true);
			}
			else
			{
				$meta_buffer = $split;
			}
		}

	}
	return $this;
}

sub split_string
{
	my $data = shift;
	my $size = shift;
	my @arr = [];
	for my $i (0..int(length($data) / $size))
	{
		push @arr, substr($data, $i * $size, $size);
	}
	return @arr;
}

1;