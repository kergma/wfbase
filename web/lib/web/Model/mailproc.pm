package web::Model::mailproc;

use strict;
use warnings;
use parent 'Catalyst::Model';
use DBI;



=head1 NAME

web::Model::mailproc - Catalyst Model

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
	$dbh=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", undef, undef, {AutoCommit => 1});
	return $dbh;
}

sub array_ref
{
	my ($self, $q)=@_;
	$self->connect() or return undef;

	my $sth=$dbh->prepare($q);
	$sth->execute();
	my @result=();
	while(my $r=$sth->fetchrow_arrayref)
	{
		push @result,$r->[0];
	};
	return \@result;
}

sub get_otd_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return array_ref($self,"select oti from orders where oti is not null group by oti order by oti");
}

1;
