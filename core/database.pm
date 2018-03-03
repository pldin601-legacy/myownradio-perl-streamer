#!/usr/bin/perl

package Database;

use DBI;
use strict;
use Time::HiRes qw(time);

my $query_counter = 0;

sub static_connect
{
	my $dbi = sprintf("dbi:mysql:database=%s;socket=/tmp/mysql.sock", 
		Settings::settings()->{database}->{db_database});
			
	my $dbh = DBI->connect( $dbi, 
		Settings::settings()->{database}->{db_login}, 
		Settings::settings()->{database}->{db_password} ) || return undef;
		
	   $dbh->do("SET NAMES 'utf8'");
	   
	return $dbh;
}

sub query_update
{
	my $query_string = shift;
	
	my $start = time();
	my $dbh = static_connect();
	
	return undef unless $dbh;
	
	my $sth = $dbh->do($query_string, undef, @_);
	my $delta = time() - $start;

	printf ("DEBUG: MYSQL(%d): %s (%0.4f)\n", $query_counter, $dbh->{Statement}, $delta) if (Settings::settings()->{streaming}->{debug} eq "yes");
	
	   $dbh->disconnect();
	
	$query_counter ++;
	
	return $sth;
}

sub query
{

	my $query_string = shift;
	
	my $start = time();
	my $dbh = static_connect();

	return undef unless $dbh;
	
	my $sth = $dbh->prepare($query_string);

	   $sth->execute(@_);

	my $delta = time() - $start;
	printf ("DEBUG: MYSQL(%d): %s (%0.4f)\n", $query_counter, $dbh->{Statement}, $delta) if (Settings::settings()->{streaming}->{debug} eq "yes");
	   
	my $results = $sth->fetchall_arrayref({});
	
	   $sth->finish();
	   $dbh->disconnect();
	
	$query_counter ++;
	
	return $results;
}

sub query_single_col
{

	my $query_string = shift;
	
	my $start = time();
	my $dbh = static_connect();

	return undef unless $dbh;
		
	my $sth = $dbh->prepare($query_string);

	$sth->execute(@_);

	my $delta = time() - $start;
	printf ("DEBUG: MYSQL(%d): %s (%0.4f)\n", $query_counter, $dbh->{Statement}, $delta) if (Settings::settings()->{streaming}->{debug} eq "yes");
	
	my @results = $sth->fetchall_arrayref();
	
	$sth->finish();
	$dbh->disconnect();
	
	$query_counter ++;
	
	return $results[0][0][0];
}

sub query_single_row
{

	my $query_string = shift;
	
	my $start = time();

	my $dbh = static_connect();

	return undef unless $dbh;
		
	my $sth = $dbh->prepare($query_string);

	   $sth->execute(@_);

	my $delta = time() - $start;
	printf ("DEBUG: MYSQL(%d): %s (%0.4f)\n", $query_counter, $dbh->{Statement}, $delta) if (Settings::settings()->{streaming}->{debug} eq "yes");
	   
	my @results = $sth->fetchall_arrayref({});
	
	   $sth->finish();
	   $dbh->disconnect();
	
	$query_counter ++;
	
	return $results[0][0];
}

sub queries
{
	return $query_counter;
}

1;