package wf::Model::udb;
use Moose;
use namespace::autoclean;

extends 'Catalyst::Model';

use DBI;

=head1 NAME

wf::Model::udb - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

Pushkinsv

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

package db;

my $dbh;

for my $funame (qw/do prepare selectrow_arrayref selectrow_hashref selectall_arrayref/)
{
	no strict 'refs';
	*$funame=sub {
		db::connect() unless $dbh;
		my $rv=$dbh->$funame(@_);
		Catalyst::Exception->throw($DBI::errstr) if $DBI::errstr;
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
		wf->config->{dbauth}
	);
	Catalyst::Exception->throw($DBI::errstr) unless $dbh;
}


sub selectval_scalar
{
	my $row=db::selectrow_arrayref(@_);
	return undef unless $row;
	return $row->[0];
}

1;
