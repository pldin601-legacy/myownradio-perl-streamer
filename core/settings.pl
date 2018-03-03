package Settings;

use Config::Tiny;
use FindBin qw($RealBin);

my $cached_settings = undef;

sub settings
{
	$cached_settings = ini_parse( $RealBin . "/../application/config.ini" ) if($cached_settings == undef);
	return $cached_settings;
}

sub ini_parse
{
	my $path = shift;
	my %settings = {};
	my $current_section = "default";
	
	$settings->{default} = {};
	
	open INI, "<", $path || return undef;
	while(<INI>)
	{
		#chomp;
		s/(\r|\n)//ig;
		
		if(m/^\[(.+)\]/)
		{
			$current_section = $1;
			$settings->{$current_section} = {};
		}
		elsif(m/^(\w+)\[\s*\]\s*\=[\s\"]+(.*)\"/)
		{
			unless(exists($settings->{$current_section}->{$1}))
			{
				$settings->{$current_section}->{$1} = ();
			}
			push(@{$settings->{$current_section}->{$1}}, $2);
		}
		elsif(m/^(\w+)\s*\=[\s\"]+(.*)\"/)
		{
			$settings->{$current_section}->{$1} = $2;
		}
		elsif(m/^(\w+)\[\s*\]\s*\=\s+(.*)\s*/)
		{
			unless(exists($settings->{$current_section}->{$1}))
			{
				$settings->{$current_section}->{$1} = ();
			}
			push(@{$settings->{$current_section}->{$1}}, $2);
		}
		elsif(m/^(\w+)\s*\=\s+(.*)\s*/)
		{
			$settings->{$current_section}->{$1} = $2;
		}
		
	}
	close INI;
	return $settings;
}

1;