package Catalyst::Authentication::Realm::MailprocData;
use strict;
use warnings;
use Catalyst::Exception;
use base qw/Catalyst::Authentication::Realm/;
use DBI;

sub new
{
	my ($class, $realmname, $config, $app) = @_;
	return $class->SUPER::new($realmname, $config, $app);
}

sub authenticate
{
	my ( $self, $c, $authinfo ) = @_;
	my $dbh=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", undef, undef, {AutoCommit => 1}) or return 'Error connecting database' ;
	my $sth=$dbh->prepare("select * from data where v2='$authinfo->{username}' and r like 'пароль%' and v1='$authinfo->{password}'");
	$sth->execute(); 
	my $r=$sth->fetchrow_hashref;
	$sth->finish();
	$dbh->disconnect;
	$r and return 1;
	return 0;
} 

1;
