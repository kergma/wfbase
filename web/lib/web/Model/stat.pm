package web::Model::stat;

use strict;
use warnings;
use parent 'Catalyst::Model';
use DBI;
use Encode;
use Digest::MD5;
use POSIX ":sys_wait_h";
use Time::HiRes 'usleep';

=head1 NAME

web::Model::stat - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

my $cc;

#sub reaper
#{
#	#while ((my $child = waitpid(-1,WNOHANG)) > 0) {print "$$ reaped $child\n";undef $pid};
#	1 while (my $child = waitpid(-1,WNOHANG)) > 0;
#	$SIG{CHLD}=\&reaper;
#}

sub ACCEPT_CONTEXT
{
	my ($self,$c,@args)=@_;

	$cc=$c;
	return $self;
}

sub connect
{
	my $tmp=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", undef, undef, {AutoCommit => 1});
	my $r=$tmp->selectrow_hashref("select v1 as password, v2 as username from data where r='пароль пользователя БД' and v2='stat'");
	$tmp->disconnect;
	my $dbh=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", $r->{username}, $r->{password}, {AutoCommit => 1});
	return $dbh;
}

sub query
{
	my ($self,$query)=@_;

	my $cache=$cc->cache;

	my $qkey=Digest::MD5::md5_hex($query);
	my $querying=$cache->get($qkey);
	if (defined $querying)
	{
		return {retrieval=>$querying->{retrieval}};
	};

	my $retrieval=Digest::MD5::md5_hex(rand());
	my $start=time;

	my $child=fork();

	unless (defined $child)
	{
		return {error=>'cannot fork'};
	};
	if ($child)
	{
		#$SIG{CHLD}=\&reaper;
		$querying={qkey=>$qkey,retrieval=>$retrieval,pid=>$child,start=>$start};
		$cache->set($qkey,$querying);
		$cache->set($retrieval,{qkey=>$qkey,retrieval=>$retrieval,query=>$query,querying=>$querying});
		while ((time-$start)<5 and (my $c=waitpid($child,WNOHANG))>=0) {usleep(100)};
		return {retrieval=>$retrieval};
	};
	
	my $dbh=$self->connect() or return undef;

	my $sth=$dbh->prepare($query);
	my $result={};
	if ($sth and $sth->execute())
	{
		my @rows;
		while (my $r=$sth->fetchrow_hashref)
		{
			push @rows, {map {encode("utf8",$_) => $r->{$_}} keys %$r};;
		}; 

		$result={rows=>\@rows,header=>[map(encode("utf8",$_),@{$sth->{NAME}})]};
	}
	$result={%$result,(query=>$query,duration=>time-$start,retrieved=>time,retrieval=>$retrieval,error=>$dbh->errstr)};
	$cache->remove($qkey);
	$cache->set($retrieval,$result);
	$dbh->disconnect();

	CORE::exit(0);

}

sub result
{
	my ($self,$retrieval,$start,$count)=@_;
	my $cache=$cc->cache;
	my $result=$cache->get($retrieval);
	return {error=>'Неправильный или устаревший идентификатор извлечения'} unless $result;
	$result->{querying}->{duration}=time-$result->{querying}->{start} if defined $result->{querying};
	$cache->set($retrieval,$result);
	return $result;
}

1;
