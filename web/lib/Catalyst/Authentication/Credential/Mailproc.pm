package Catalyst::Authentication::Credential::Mailproc;
use strict;
use warnings;
use base qw/Class::Accessor::Fast/;

use Catalyst::Exception;
use DBI;

BEGIN {
	__PACKAGE__->mk_accessors(qw/_config realm/);
}

sub new
{
    my ($class, $config, $app, $realm) = @_;
    
    my $self = { _config => $config };
    bless $self, $class;
    
    $self->realm($realm);
    
    return $self;
}

sub authenticate
{
	my ( $self, $c, $realm, $authinfo ) = @_;

	my $userfindauthinfo = {%{$authinfo}};
	delete($userfindauthinfo->{$self->_config->{'password_field'}});

	my $user_obj = $realm->find_user($userfindauthinfo, $c);

	if (ref($user_obj))
	{
		if ($self->check_password($user_obj, $authinfo)) {
			return $user_obj;
		}
	} else {
		$c->log->debug("Unable to locate user matching user info provided") if $c->debug;
		return;
	}
}

sub check_password
{
	my ( $self, $user, $authinfo ) = @_;
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
