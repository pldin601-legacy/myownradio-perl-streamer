#!/usr/bin/perl

my @bitrate_array = ( 32, 64, 128, 256 );

sub http_request
{

	my $_REQUEST	= shift;
	my $_GET		= shift;
	my $_PATH		= shift;
	
	my $_SOCKET		= shift;
	my $_OUTPUT		= shift;

	my $bitrate 	= exists($bitrate_array[$_GET->{br}]) ? $bitrate_array[$_GET->{br}] : $bitrate_array[3];
	my $metadata	= int($_REQUEST->{"_headers"}->{"icy-metadata"});
	
	print "Stack size: ", threads->get_stack_size(), "\n";
	
	if($_PATH eq "/audio")
	{
		unless($_GET->{id} =~ m/^\d+$/)
		{
			print $_OUTPUT http_404();
			return;
		}
	
		my $share = new memory($_GET->{id}.":".$bitrate);
		
		unless($share->isMemoryActive())
		{
			printf "Client starts the streamer stream_id=%d, bitrate=%dkbps...\n", $_GET->{id}, $bitrate;
			async { create_stream($_GET->{id}, $bitrate); };
		}

		my $stream = new Stream($_GET->{id});
		unless($stream->available())
		{
			print $_OUTPUT http_404();
			return;
		}
		
		++ $shared_last_listener;
		
		my $listener_id = $server_unique_prefix . $shared_last_listener;
		my $time_of_start = time();
		
		print $_OUTPUT http_responce($metadata, "Stream " . $stream->getTitle());
	
		my $flow = new flow();
		
		$flow->setupIcy($metadata)->setOutput($_OUTPUT);
		
		if($metadata)
		{
			$flow->setInterval(Settings::settings()->{streaming}->{icy_metadata_interval})
				 ->setTitle("Stream " . $_GET->{id});
		}
		
		my $raw, $title = "";
		$stat_clients_total ++;
		my $iterations = 0;
		while(($raw = $share->readMemory()) && $_OUTPUT->connected())
		{
			if($share->getTitle() ne $title)
			{
				$title = $share->getTitle();
				$flow->setTitle($title);
			}
			$flow->write($raw);
			if($iterations % 10 == 0)
			{
				$shared_listeners{$listener_id} = encode_json({
					"stream_id" 	=> $_GET->{id}, 
					"client_ua" 	=> $_REQUEST->{"_headers"}->{"user-agent"},
					"client_ip" 	=> long2ip($_SOCKET->peeraddr()),
					"stream_br" 	=> $bitrate,
					"connected" 	=> time() - $time_of_start,
					"connected_at" 	=> $time_of_start
				});
			}
			$iterations ++;
			$stat_client_bytes += length($raw);
		}
		push @shared_gone, $listener_id;
		return;
	}
	
}

sub create_stream 
{

	my $stream_id	= shift;
	my $bitrate 	= shift;

	# Create instance of stream
	my $stream = new Stream($stream_id);

	# Return error if stream not exists
	return 404 unless($stream->available());
	
	# Create instance of memory buffer
	my $memory = new memory($stream_id.":".$bitrate);
	
	# Init memory buffer
	$memory->initMemory($stream_id, $bitrate);

	# Creating master input handle
	my ($MASTER, $master_handle) = createMasterHandle("MP3", $bitrate, $memory);
	
	# First track flag
	my $first_track = 1;
	my $track_counter = 0;
	
	# Infinity loop
	SESSION: while($memory->lastTouched() < 30) 
	{
		# Play jingle if needed
		#
		#if($track_counter ++ % 3 == 0)
		#{
		#	my $jingle = parametralCommand(Settings::settings()->{streaming}->{stream_command}, { 
		#		INFILE => Settings::settings()->{content}->{content_folder} . "/../jingle.wav", 
		#		BITRATE => $bitrate, 
		#		START => 0, 
		#		FILTER => ""}
		#	);
		#	runCommand($jingle, $memory->setTitle("Advertisement"), $stream_id, $MASTER, 1);
		#} 
			
		# Getting current playing track
		my $track = $stream->getPlayingTrack($first_track ? int(Settings::settings()->{server}->{stream_buffer}) * 1000 : 0);
		my $manual = 0;
		if($track)
		{
			# Path to current playing track
			my $pathname_lores = $stream->generatePath(Settings::settings()->{content}->{content_folder}, $track);
			my $pathname_original = $stream->generatePathOriginal(Settings::settings()->{content}->{content_folder}, $track);
			my $checktime = time() * 1000 + $track->{duration} - $track->{cursor};
			
			my $pathname;
			if(-e $pathname_original)
			{
				$pathname = $pathname_original;
			}
			elsif(-e $pathname_lores)
			{
				$pathname = $pathname_lores;
			}
			else
			{
				$pathname = "";
			}

			# Play current track
			my $ss = $track->{cursor} / 1000;
			my $filter = ($ss > 1) ? "-af afade=t=in:ss=0:st=0:d=0.5" : "";
			my $duration = ($track->{duration} - $track->{cursor}) / 1000;
			my $ending = $track->{duration} / 1000 - $ss;
			
			# Unsynchronized track ending repeat prevention
			if($ending < 2 && $first_track == 0)
			{
				printf "STREAM %d: Too early... Sleeping for %0.3f seconds\n", $stream_id, $ending;
				sleep($ending);
				next SESSION;
			}
			
			printf "STREAM %d: Now playing %s from %0.3f second (before end %0.3f)\n", $stream_id, $track->{artist} . " - " . $track->{title}, $ss, $ending;
			
			unless(length($pathname) == 0)
			{
				my $sw = (((int($track->{t_order}) - 1) % 4 == 0) && ($ss <= 2)) ? Settings::settings()->{streaming}->{stream_jingled_command} : Settings::settings()->{streaming}->{stream_command};
				my $command = parametralCommand($sw, { 
					INFILE => $pathname, 
					BITRATE => $bitrate, 
					START => $ss, 
					FILTER => ""
				});
				writeCurrentTitle($stream_id.":".$bitrate, $track->{unique_id}, $track->{artist} . " - " . $track->{title}, time() * 1000 - $track->{cursor}, $track->{duration}, $track->{tid});
				$manual = runCommand($command, $memory->setTitle($track->{artist} . " - " . $track->{title}), $stream_id, $MASTER, 0);
				$stat_tracks_played ++;
			}
			else
			{
				my $command = parametralCommand(Settings::settings()->{streaming}->{limnoise_command}, { 
					BITRATE => $bitrate, 
					DURATION => $duration
				});
				writeCurrentTitle($stream_id.":".$bitrate, $track->{unique_id}, $track->{artist} . " - " . $track->{title} . " (file not found)", time() * 1000 - $track->{cursor}, $track->{duration}, $track->{tid});
				$manual = runCommand($command, $memory->setTitle("Track not found"), $stream_id, $MASTER, 0);
			}
			
			if($manual == 1)
			{
				# Play sound effect
				print("Sound effect...\n");
				my $command = parametralCommand(Settings::settings()->{streaming}->{stream_command}, { 
					INFILE => Settings::settings()->{content}->{content_folder} . "/../dialup.wav", 
					BITRATE => $bitrate, 
					START => 0, 
					FILTER => ""
				});
				runCommand($command, $memory, $stream_id, $MASTER, 1);
			}
		}
		else
		{
			# Play silence if nothing playing
			my $command = parametralCommand(Settings::settings()->{streaming}->{infnoise_command}, {
				BITRATE => $bitrate 
			});
			writeCurrentTitle($stream_id.":".$bitrate, "", "Stream switched off", 0, 0, 0);
			runCommand($command, $memory->setTitle("Stream switched off"), $stream_id, $MASTER);
		}
		$first_track = 0;
	}

    $master_handle->kill('SIGUSR1')->join();
}

sub parametralCommand
{
	my $command		= shift;
	my $params		= shift;

	my $quoted;

	foreach my $key (keys %{$params})
	{
		$quoted	= esc_chars($params->{$key});
		$key2 = uc($key);
		$command =~ s/<$key2>/$quoted/g;
	}
	
	return $command;
	
}

sub createMasterHandle
{
	my $format 	= shift;
	my $bitrate = shift;
	my $output  = shift;
	my $command = parametralCommand(Settings::settings()->{streaming}->{stream_master}, { 
		BITRATE => $bitrate,
		CHANNELS => ($bitrate >= 64) ? 2 : 1
	});
		
	my $pid = open3(\*SOURCE, \*FILE, \*SECOND_ERR, $command);
	
	SOURCE->autoflush();
	FILE->autoflush();
	close SECOND_ERR;
	
	$| = 1;
	
	my $handle = async 
	{
		$SIG{USR1} = sub { 
			while(!killfam(9, $pid))
			{
				sleep(1);
			}
		};
		
		my ($data, $n);
		while ((($n = read (FILE, $data, 1024)) != 0))
		{
			$output->writeMemory($data);
			$stat_server_bytes_out += $data;
		}
		close SOURCE, FILE, SECOND_ERR;
		$output->stopMemory();
		print "Stream encoder shutdown...\n";
		threads->exit();
	};
	
	return (SOURCE, $handle);
}

sub runCommand
{
	my $command		= shift;
	my $output		= shift;
	my $stream_id	= shift;
	my $MASTER		= shift;
	my $forced		= shift;

	$| = 1;
	
	my $pid = open3(\*FIRST_IN, \*FILE, \*FIRST_ERR, $command);

	close FIRST_ERR;
	close FIRST_IN;
		
	binmode FILE;
	
	my ($data, $n);
	my $mtime = streamSubscribe::read($stream_id);

	my $subtime = time();
	my $manual = 0;
	while ((($n = read FILE, $data, 4096) != 0) && ($output->lastTouched() < 30))
	{
		print $MASTER $data;
		if(!$forced && (time() - $subtime >= 0.25))
		{
			$subtime = time();
			unless($mtime == streamSubscribe::read($stream_id))
			{
				$manual = 1;
				last;
			}
		}
		$stat_server_bytes_in += length($data);
	}
	kill -9, $pid;
	close FILE;
	return $manual;
}

sub esc_chars {
	my $chars = shift;
	$chars =~ s/([;<>\*\|`&\$!#\(\)\[\]\{\}:"])/\\$1/g;
	return $chars;
}

1;