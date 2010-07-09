package web::Model::stat;

use strict;
use warnings;
use parent 'Catalyst::Model';
use DBI;
use Encode;

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

sub query
{
	my ($self,$query)=@_;
	$self->connect() or return undef;

	my $start=time;
	my $sth=$dbh->prepare($query);
	$sth or return {error=>$dbh->errstr};
	$sth->execute() or return {error=>$dbh->errstr};
	my @rows;
	while (my $r=$sth->fetchrow_hashref)
	{
		push @rows, {map {encode("utf8",$_) => $r->{$_}} keys %$r};;
	}; 

	return {rows=>\@rows, error=>$dbh->errstr, header=>[map(encode("utf8",$_),@{$sth->{NAME}})],duration=>time-$start, retrieved=>time};
}

1;
