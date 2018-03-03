package memory;

use Time::HiRes qw(time usleep sleep);
use JSON;

use strict;
use warnings;

my %memory_stream_data		:shared;
my %memory_stream_cursor	:shared;
my %memory_stream_touched	:shared;
my %memory_stream_active	:shared;
my %memory_stream_title		:shared;
my %memory_stream_buffer	:shared;

my $key = "";
my $cursor = 0;
my $marker = 0;
my $stream_buffer = 0;

sub new
{
	my $this 		= shift;
	   $key 		= shift || "";
	   $cursor		= 0;
	   $marker		= 0;
	my $self		= { name => "Memory", version => "1.0" };
	bless $self;
	return $self;
}

sub initMemory
{
	my $this		= shift;
	my $stream_id	= shift;
	my $bitrate		= shift;
	
	$memory_stream_buffer{$key} = $bitrate * int(Settings::settings()->{server}->{stream_buffer}) / 8 * 1000;
	$memory_stream_data{$key} = "0;";
	$memory_stream_cursor{$key} = 0;
	$memory_stream_touched{$key} = time();
	$memory_stream_active{$key} = 1;
	$memory_stream_title{$key} = "";
	
	return $this;
}

sub stopMemory
{
	my $this		= shift;
	my $stream_id	= shift;

	$memory_stream_active{$key} = 0;

	return $this;
}



sub isMemoryActive
{
	my $this		= shift;
	return 0 unless($memory_stream_active{$key});
	return $memory_stream_active{$key};
}

sub writeMemory
{
	my $this = shift;
	my $input = shift;
	
	my ($pos, $data) = split("\;", $memory_stream_data{$key}, 2);
	
	my $new_size = length($data) + length($input);

	if( $new_size > $memory_stream_buffer{$key} )
	{
		my $trimsize = $new_size - $memory_stream_buffer{$key};
		$data = substr($data, $trimsize);
	}
	
	$data	.= $input;
	$pos	+= length($input);

	$memory_stream_data{$key} = join(";", ($pos, $data));
	$memory_stream_cursor{$key} ++;
	
	if($memory_stream_cursor{$key} % 10 == 0)
	{
		#printf "WRITE: key=%s, id=%s, length=%d, cursor=%d\n", $memory_stream_cursor{$key}, $key, length($input), $pos;
	}
	
	return $this;
}

sub readMemory
{
	my $this = shift;
	my $start = time();
	
	PROC: while(time() - $start < 60) {
	
		unless($this->isMemoryActive())
		{
			sleep(0.25);
			next PROC;
		}
	
		$memory_stream_touched{$key} = time();
		
		my $i = $memory_stream_cursor{$key} - $marker;
		
		$i = 1 if($i < 0);
		
		if(exists($memory_stream_cursor{$key}) && $i > 0)
		{
			my ($pos, $data) = split("\;", $memory_stream_data{$key}, 2);
			
			my $delta = $pos - $cursor;

			if ($delta <= 0)
			{
				usleep(100000);
				next PROC;
			}
			
			my $raw;
			
			if($delta < length($data))
			{
				$raw = substr($data, length($data) - $delta);
			}
			else
			{
				$raw = $data;
			}
			$cursor = $pos;
			$marker += $i;
			return $raw;
		}

		sleep(0.1);
	}
	
	return undef;
}

sub lastTouched
{
	my $this = shift;
	return time() - $memory_stream_touched{$key};
}

sub setTitle
{
	my $this 	= shift;
	my $title 	= shift;
	$memory_stream_title{$key} = $title;
	return $this;
}

sub getTitle
{
	my $this 	= shift;
	my $title 	= shift;
	return exists($memory_stream_title{$key}) ? $memory_stream_title{$key} : "";
}

1;