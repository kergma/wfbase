package wf::Model::ppdb;

use strict;
use warnings;
no warnings 'uninitialized';
use parent 'Catalyst::Model';
use DBI;
use Date::Format;
use Digest::MD5;
use POSIX ":sys_wait_h";
use Time::HiRes 'usleep';
no warnings 'uninitialized';
use utf8;



=head1 NAME

wf::Model::ppdb - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

my $cc;

sub ACCEPT_CONTEXT
{
	my ($self,$c,@args)=@_;

	$cc=$c;
	return $self;
}

sub sconnect
{
	my $sdbh=DBI->connect("dbi:Pg:dbname=worker;host=ppdb", 'stat', undef, {AutoCommit => 1,pg_enable_utf8=>0});
	$sdbh->do("create function pg_temp.wfuser() returns uuid as \$\$select '${\($cc->user->{souid})}'::uuid\$\$ language sql");
	return $sdbh;
}

sub array_ref
{
	my ($self, $q, @values)=@_;

	my $opts={row=>'auto'};
	if (ref $q eq 'HASH')
	{
		%$opts=(%$opts,%$q);
		$q=shift @values;
	};

	my $sth;
	if ($opts->{use_safe_connection})
	{
		my $sdbh=$self->sconnect() or return undef;
		$sth=$sdbh->prepare($q);
	}
	else
	{
		$sth=db::prepare($q);
	};
	my $r=$sth->execute(@values);
	return undef unless $r;
	my $row=$opts->{row};
	$opts->{row}='hashref' if ($opts->{row}//'auto') eq 'auto' and scalar(@{$sth->{NAME}})>1;
	$opts->{row}='col' if ($opts->{row}//'auto') eq 'auto' and scalar(@{$sth->{NAME}})==1;
	my @result=();
	while(my $r=($opts->{row} eq 'hashref'?$sth->fetchrow_hashref:$sth->fetchrow_arrayref))
	{
		push @result,$r->[0] if $opts->{row} eq 'col';
		push @result,$r if $opts->{row} eq 'hashref';
		push @result,[@$r] if $opts->{row} eq 'arrayref';
		push @result,[@$r] if $opts->{row} eq 'enhash';
	}
	if ($opts->{row} eq 'enhash')
	{
		my $r={};
		$r->{$_->[0]}=$_ foreach @result;
		return $r;
	};
	return \@result;
}

sub cached_array_ref
{
	my ($self, $q, @values)=@_;
	my $opts={};
	if (ref $q eq 'HASH')
	{
		$opts=$q;
		$q=shift @values;
	};

	my $md5=Digest::MD5->new;
	$md5->add($opts->{cache_key}) if defined $opts->{cache_key};
	use Encode qw(encode_utf8);
	$md5->add(encode_utf8($q));
	$md5->add(encode_utf8($_)) foreach @values;
	my $qkey=$md5->hexdigest();

	my $result=$cc->cache->get("aref-".$qkey);
	undef $result if $opts->{update};
	unless ($result)
	{
		$result=array_ref(@_);
		$cc->cache->set("aref-".$qkey,$result) if defined $result;
	};
	return $result;
}


sub options_list
{
	my ($self, $q, @values)=@_;
	my $opts={row=>'arrayref'};
	if (ref $q eq 'HASH')
	{
		%$opts=(%$q,%$opts);
		$q=shift @values;
	};
	my $r=cached_array_ref($self,$opts,$q,@values);
	$_=scalar(@$_)==1?$_->[0]:{$_->[0]=>$_->[1]} foreach @$r;
	return $r;

}

sub query
{
	my $self=shift;
	my $query=shift;
	my $params=shift;
	$params={} unless defined $params;
	$params->{need_db}=0;
	my @values=@_;

	my $cache=$cc->cache;

	return defer($self,sub {
		my $running=pop;
		my $sdbh=$self->sconnect() or return undef;
		$running->{pg_pid}=$sdbh->{pg_pid};
		$cache->set("rkey-$running->{rkey}",$running,0);
		my $d=$cache->get("defr-$running->{deferral}");
		$d->{query}=$query;
		$cache->set("defr-$running->{deferral}",$d,0);

		my $result={};
		my $sth;
		eval {$sth=$sdbh->prepare($query);};
		if ($sth and $sth->execute(@_))
		{
			my @rows;
			while (my $r=$sth->fetchrow_hashref)
			{
				push @rows, {map {$_ => $r->{$_}} keys %$r};;
			}; 

			$result={ARRAY=>\@rows,header=>[@{$sth->{NAME}}],error=>$@?$@:$sdbh->errstr};
		};
		$result={%$result,(query=>$query,error=>$@?$@:$sdbh->errstr)};
		$sth->finish();
		$sdbh->disconnect();
		return $result;
	},$params,@values);
}

sub cancel_query
{
	my ($self,$r)=@_;
	$r=deferred($self,$r) if ref \$r eq 'SCALAR';
	return unless $r->{running};

	my $sdbh=$self->sconnect() or return undef;
	my $re=$sdbh->selectrow_hashref("select cancel_query(?)",undef,$r->{running}->{pg_pid});
	$re=db::selectrow_hashref("select cancel_query(?)",undef,$r->{running}->{pg_pid}) unless $re;
	$sdbh->disconnect;
	unless ($re)
	{
		kill 9, $r->{running}->{pid};
		$r->{error}='Выполнение запроса прервано';
		$cc->cache->remove("rkey-$r->{rkey}");
		$cc->cache->set("defr-$r->{deferral}",$r);
	};
	return $re;

}

sub defer
{
	my $self=shift;
	my $proc=shift;
	my $params=shift;

	my @values=@_;

	my $cache=$cc->cache;

	my $md5=Digest::MD5->new;
	$md5->add($proc);
	use Encode qw(encode_utf8);
	$md5->add($_,encode_utf8($params->{$_})) foreach sort keys %$params;
	$md5->add(encode_utf8($_)) foreach @values;
	my $rkey=$md5->hexdigest();

	my $running=$cache->get("rkey-$rkey");
	if (defined $running)
	{
		return {deferral=>$running->{deferral}};
	};

	my $deferral=Digest::MD5::md5_hex(rand());
	my $start=time;

	$SIG{CHLD} = 'IGNORE';
	my $child=fork();

	unless (defined $child)
	{
		return {error=>'cannot fork'};
	};
	$running={rkey=>$rkey,deferral=>$deferral,pid=>$child||$$,start=>$start};
	if ($child)
	{
		$cache->set("rkey-$rkey",$running,0);
		$cache->set("defr-$deferral",{rkey=>$rkey,deferral=>$deferral,params=>$params,user=>$cc->user->{souid},action=>$cc->req->{action}},0);
		while ((time-$start)<($params->{defer_threshold}||5) and (my $c=waitpid($child,WNOHANG))>=0) {usleep(100)};
		return {deferral=>$deferral};
	};
	if ($params->{need_db}//1)
	{
		undef $db::dbh;
		db::connect();
		$running->{pg_pid}=db::pg_pid;
	};
	
	$cache->set("rkey-$rkey",$running,0);

	my @r=&$proc(@values,$running);
	my $result=shift @r if scalar(@r)==1;
	$result=\@r unless defined $result;

	$result={'ARRAY'=>$result} if ref $result eq 'ARRAY';
	$result={'SCALAR'=>$result} unless ref $result;
	$result->{rkey}=$rkey;
	
	$result={%$result,(values=>[@values],duration=>time-$start,completed=>time,completedf=>time2str('%Y-%m-%d %H:%M:%S',time),deferral=>$deferral,params=>$params,user=>$cc->user->{souid},action=>$cc->req->{action})};
	$cache->remove("rkey-$rkey");
	if (scalar(@{$result->{ARRAY}//[]})*scalar(@{$result->{header}//[]})>30 or !$cache->set("defr-$deferral",$result))
	{
		$cc->cache("big")->set("array-$deferral",$result->{ARRAY});
		delete $result->{ARRAY};
		$cache->set("defr-$deferral",$result);
	};
	db::disconnect if $params->{need_db}//1;

	exit 0; # PSGI

}


sub deferred
{
	my ($self,$deferral,$onlyheader)=@_;
	my $cache=$cc->cache;
	($deferral,$onlyheader)=(defer(@_)->{deferral},undef) if ref $deferral eq 'CODE';
	my $result=$cache->get("defr-$deferral");

	return {error=>'Неправильный или устаревший отложенный идентификатор',deferral=>$deferral} unless $result;
	$result->{running}=$cache->get("rkey-$result->{rkey}");
	$result->{running}->{duration}=time-$result->{running}->{start} if defined $result->{running};
	unless ($cache->set("defr-$deferral",$result,defined $result->{running}?0:undef))
	{
		$cc->cache("big")->set("array-$deferral",$result->{ARRAY});
		my $a=$result->{ARRAY};
		undef $result->{ARRAY};
		$cache->set("defr-$deferral",$result);
		$result->{ARRAY}=$a;
	};
	unless ($result->{ARRAY} or $onlyheader)
	{
		$result->{ARRAY}=$cc->cache("big")->get("array-$deferral");
		$cc->cache("big")->set("array-$deferral",$result->{ARRAY});
		$result->{big}=1;
	};
	$result->{rows}=$result->{ARRAY} if $result->{query};
	return $result;
}


1;
