package wf::Model::dbcon;
use Moose;
use namespace::autoclean;
use utf8;

extends 'Catalyst::Model';

use DBI;
use Digest::MD5;
use Encode;
use Date::Format;

no warnings qw/uninitialized/;
no if ($] >= 5.018), 'warnings' => 'experimental';

=head1 NAME

wf::Model::dbcon - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

Pushkinsv

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;


my $cc;

sub ACCEPT_CONTEXT
{
	my ($self,$c,@args)=@_;

	$cc=$c;
	return $self;
}

sub arrayref;
sub arrayref($)
{
	my ($v)=@_;
	return $v if ref $v eq 'ARRAY';
	return [$v];
}

sub authinfo_password
{
	my ($self,$authinfo)=@_;

	my $r=db::selectrow_hashref(qq{
select p.t as passw,a.e2 as soid from systems a
join systems n on n.r=er.key('имя входа') and n.e1=a.e1
join systems p on p.r=er.key('пароль ct') and p.e1=a.e1
where a.r=er.key('учётная запись сотрудника') and (n.t=? or a.e1=?)
},undef,$authinfo->{username},$authinfo->{uid});
	$r or return undef;
	$r->{passw}="***" if $authinfo->{uid} and !$authinfo->{username};
	$authinfo->{soid}=$r->{soid};
	$authinfo->{password}=$r->{passw};
	return $r->{passw};
}



sub authinfo_data
{
	my ($self,$authinfo)=@_;

	my %data=%$authinfo;
	$data{entity}=$self->entity($authinfo->{soid});
	$data{full_name}=$data{entity}->{names}->[0];
	my $r=$self->array_ref(qq/
select path[array_length(path,1)] as role,a.t role_t from er.tree_from(?,array[er.key('входит в состав полномочия'),-er.key('уполномочен на')]) t
left join authorities a on a.e1=t.path[array_length(t.path,1)] and a.r=any(er.keys('наименование%','полномочия'))
/,$authinfo->{soid})
;
	$data{roles}=[map {$_->{role},$_->{role_t}} @$r];
	return \%data;
}

sub entity
{
	my ($self,$en,$domain)=@_;
	return db::selectrow_hashref(qq/select * from er.entities(coalesce(?,0::int8),null,null,?)/,undef,$en,$domain);
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
	$md5->add($q);
	$md5->add($_) foreach @values;
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

sub read_table
{
	my $self=shift;
	my $query=shift;
	my @values=@_;

	my $start=time;

	my $sth=db::prepare($query);
	$sth->execute(@values);

	my %result=(query=>$query,values=>[@values],header=>[map(encode("utf8",$_),@{$sth->{NAME}})],rows=>[]);

	while(my $r=$sth->fetchrow_hashref)
	{
		push @{$result{rows}}, {map {encode("utf8",$_) => $r->{$_}} keys %$r};;
	};
	$sth->finish;

	$result{duration}=time-$start;
	$result{retrievedf}=$result{retrieved}=time2str('%Y-%m-%d %H:%M:%S',time);

	return \%result;
}


package db;

my $dbh;

for my $funame (qw/errstr do prepare quote selectrow_arrayref selectrow_hashref selectcol_arrayref selectall_arrayref selectall_hashref last_insert_id quote_identifier/)
{
	no strict 'refs';
	*$funame=sub {
		db::connect() unless $dbh;
		my $rv=$dbh->$funame(@_);
		#Catalyst::Exception->throw($DBI::errstr) if $DBI::errstr;
		return $rv;
	};
}

sub connect
{
	$dbh||=DBI->connect(
		"dbi:Pg:".join(';',grep {$_} (
			wf->config->{dbhost}?"host=".wf->config->{dbhost}:undef,
			wf->config->{dbport}?"port=".wf->config->{dbport}:undef,
			wf->config->{dbname}?"dbname=".wf->config->{dbname}:undef,
		)),
		wf->config->{dbusername},
		wf->config->{dbauth},
		{InactiveDestroy=>1}
	);
	Catalyst::Exception->throw($DBI::errstr) unless $dbh;
}

sub disconnect
{
	$dbh->disconnect if $dbh;
	undef $dbh;
}

sub connected
{
	return $dbh;
}

sub pg_pid;
sub pg_pid()
{
	db::connect() unless $dbh;
	return $dbh->{pg_pid};
}

sub selectval_scalar
{
	my $row=db::selectrow_arrayref(@_);
	return undef unless $row;
	return $row->[0];
}

1;
