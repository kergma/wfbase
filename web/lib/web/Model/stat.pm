package web::Model::stat;

use strict;
use warnings;
use parent 'Catalyst::Model';
use DBI;

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

my $dbh;

sub connect
{
	$dbh and return $dbh;
	my $tmp=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", undef, undef, {AutoCommit => 1});
	my $r=$tmp->selectrow_hashref("select v1 as password, v2 as username from data where r='пароль пользователя БД' and v2='stat'");
	$tmp->disconnect;
	$dbh=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", $r->{username}, $r->{password}, {AutoCommit => 1});
	return $dbh;
}

sub test
{
	my ($self)=@_;
	$self->connect() or return undef;
	return $dbh->selectrow_hashref("select * from sdata limit 1");
}

1;
