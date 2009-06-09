package Catalyst::Authentication::Store::Mailproc;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;

use Catalyst::Authentication::User::Hash;
use Catalyst::Exception;
use DBI;

BEGIN
{
	__PACKAGE__->mk_accessors(qw/_config/);
}

sub new
{
	my ( $class, $config, $app, $realm ) = @_;
	bless { _config => $config }, $class;
}

sub for_session
{
	my ( $self, $c, $user ) = @_;
	return $user;
}

sub from_session
{
	my ( $self, $c, $user ) = @_;
	return $user;
}

use Data::Dumper;
sub find_user
{
	my ( $self, $authinfo, $c ) = @_;
	$c->log->debug(Dumper($authinfo));

	my $dbh=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", undef, undef, {AutoCommit => 1}) or return 'Error connecting database' ;
	my $sth=$dbh->prepare("select * from data where v2='$authinfo->{username}' and r like 'пароль%'");
	$sth->execute(); 
	my $r=$sth->fetchrow_hashref;
	$sth->finish();
	$r and $authinfo->{password}=$r->{v1};

	$sth=$dbh->prepare("select d2.v2 as full_name from data d1 join data d2 on d2.r like '%сотрудника' and d2.v1=d1.v2 where d1.v2='$authinfo->{username}'");
	$sth->execute(); 
	$r=$sth->fetchrow_hashref;
	$sth->finish();
	$r and $authinfo->{full_name}=$r->{full_name};

	$sth=$dbh->prepare(qq/
select d3.v1 as description
from data d1
join data d2 on d2.v1=d1.v2 
join data d3 on d3.v2=d2.v2 and d3.r like 'описание%'
where d1.v2='$authinfo->{username}' and d1.r like 'пароль%'
/
);
	$sth->execute(); 
	while (my $r=$sth->fetchrow_hashref)
	{
		push @{$authinfo->{roles}}, split / /,$r->{description};
	};
	$sth->finish();

	$sth=$dbh->prepare("select * from data where r like '%отделения' and v2='$authinfo->{username}'");
	$sth->execute(); 
	$r=$sth->fetchrow_hashref;
	$sth->finish();
	$r and push @{$authinfo->{roles}},'отделение';

	$dbh->disconnect;
	$c->log->debug(Dumper($authinfo));
	return bless $authinfo, 'Catalyst::Authentication::User::Hash';
}

sub user_supports
{
    my $self = shift;
    Catalyst::Authentication::User::Hash->supports(@_);
}

1;
