package wfbase::Model::dbcon;
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

wfbase::Model::dbcon - Catalyst Model

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
	my $r=db::selectall_arrayref(qq/
select path[array_length(path,1)] as role,a.t role_t from er.tree_from(?,array[er.key('входит в состав полномочия'),-er.key('уполномочен на')]) t
left join authorities a on a.e1=t.path[array_length(t.path,1)] and a.r=any(er.keys('наименование%','полномочия'))
/,{Slice=>{}},$authinfo->{soid});
	$data{roles}=[map {$_->{role},$_->{role_t}} @$r];
	return \%data;
}

sub entity
{
	my ($self,$en,$domain)=@_;
	return db::selectrow_hashref(qq/select * from er.entities(coalesce(?,0::int8),null,null,?)/,undef,$en,$domain);
}

package db;

my $dbh;
my $conf;

for my $funame (qw/errstr do prepare quote selectrow_arrayref selectrow_hashref selectcol_arrayref selectall_arrayref selectall_hashref last_insert_id quote_identifier begin_work commit rollback/)
{
	no strict 'refs';
	*$funame=sub {
		db::connect() unless $dbh;
		my $rv=$dbh->$funame(@_);
		if ($dbh->errstr and !$dbh->ping)
		{
			print "db connection lost ",$dbh->errstr,"\n";
			undef $dbh;
			db::connect();
			print "reconnected\n";
			$rv=$dbh->$funame(@_);
		};

		#Catalyst::Exception->throw($DBI::errstr) if $DBI::errstr;
		return $rv;
	};
}

sub connect
{
	my $c=shift||$conf||$cc->config;
	$conf||=$c;
	$dbh||=DBI->connect(
		"dbi:".$c->{dbdriver}.":".join(';',map {({dbhost=>'host',dbport=>'port'}->{$_}||$_)."=".$c->{$_}} grep {$c->{$_}} qw/dbhost dbport dbname database/),
		$c->{dbusername},
		$c->{dbauth},
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
	return unless $dbh;
	return $dbh->{pg_pid};
}

sub h
{
	return $dbh;
}

sub clone
{
	return unless $dbh;
	$dbh=$dbh->clone;
	return $dbh;
}

sub selectval_scalar
{
	my $row=db::selectrow_arrayref(@_);
	return undef unless $row;
	return $row->[0];
}

1;
