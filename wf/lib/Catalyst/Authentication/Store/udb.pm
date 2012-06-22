package Catalyst::Authentication::Store::udb;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;

use Catalyst::Authentication::User::Hash;
use Catalyst::Exception;

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

	my $model=$c->model('udb');

	my $p=$model->authinfo_password($authinfo) or return undef;

	$authinfo->{password}=$p;

	my $data=$model->authinfo_data($authinfo);
	%$authinfo=(%$authinfo,%$data);

	return bless $authinfo, 'Catalyst::Authentication::User::Hash';
}

sub user_supports       
{
	my $self = shift;
	Catalyst::Authentication::User::Hash->supports(@_);
}

1;

