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

sub find_user
{
	my ( $self, $authinfo, $c ) = @_;

	my $dbh=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", undef, undef, {AutoCommit => 1}) or return 'Error connecting database' ;
	my $sth=$dbh->prepare("select * from data where v2=? and r like 'пароль%'");
	$sth->execute($authinfo->{username}); 
	my $r=$sth->fetchrow_hashref;
	$sth->finish();
	$r and $authinfo->{password}=$r->{v1};

	$sth=$dbh->prepare("select d2.v2 as full_name from data d1 join data d2 on d1.r like 'пароль%' and d2.r like '%сущности' and d2.v1=d1.v2 where d1.v2=?");
	$sth->execute($authinfo->{username}); 
	$r=$sth->fetchrow_hashref;
	$sth->finish();
	$r and $authinfo->{full_name}=$r->{full_name};

	$sth=$dbh->prepare(qq/
select d3.v1 as description
from data d1
join data d2 on d2.v1=d1.v2 and d2.r like '%сущности'
join data d3 on d3.v2=d2.v2 and d3.r like 'описание сущности'
where d1.v2=? and d1.r like 'пароль%'
/
);
	$sth->execute($authinfo->{username}); 
	while (my $r=$sth->fetchrow_hashref)
	{
		push @{$authinfo->{roles}}, split / /,$r->{description};
	};
	$sth->finish();

	$dbh->disconnect;
	return bless $authinfo, 'Catalyst::Authentication::User::Hash';
}

sub user_supports
{
    my $self = shift;
    Catalyst::Authentication::User::Hash->supports(@_);
}

1;
