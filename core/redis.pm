package streamSubscribe;

use Redis;

sub read
{
	my $stream_id 	= shift;
	my $redis 		= new Redis( server => '127.0.0.1:6379', debug => 0 );
	
	my $mtime = $redis->exists(sprintf("myownradio.biz:state_changed:stream_%d", $stream_id)) ? $redis->get(sprintf("myownradio.biz:state_changed:stream_%d", $stream_id)) : 0;
	undef $redis;
	return $mtime;
}

1;