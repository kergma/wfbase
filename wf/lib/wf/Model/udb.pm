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

sub authinfo_password
{
	my ($self,$authinfo)=@_;

	my $r=db::selectrow_hashref(qq{
select pw_ac.v1 as passw
from data lo_ac
join data pw_ac on pw_ac.v2=lo_ac.v2 and pw_ac.r like 'пароль % учётной записи'
where lo_ac.r='имя входа учётной записи' and lo_ac.v1=?
},undef,$authinfo->{username});
	$r or return undef;
	return $r->{passw};
}



sub authinfo_data
{
	my ($self,$authinfo)=@_;

	my %data=%$authinfo;

	my $r=db::selectrow_hashref(qq/
select fio_so.v2 as souid, lo_ac.v1 as username, pw_ac.v1 as password,fio_so.v1 as fio,
(select join(', ', v1) from data where r='описание сотрудника' and v2=fio_so.v2) as description
from data fio_so 
join data ac_so on ac_so.r='учётная запись сотрудника' and ac_so.v2=fio_so.v2
join data lo_ac on lo_ac.r='имя входа учётной записи' and lo_ac.v2=ac_so.v1
join data pw_ac on pw_ac.r like 'пароль %' and pw_ac.v2=ac_so.v1
where fio_so.r='ФИО сотрудника' and lo_ac.v1=?
/,undef,$authinfo->{username});
	%data=(%data,%$r) if $r;

	push @{$data{roles}}, $authinfo->{username};
	push @{$data{roles}}, split /, */, $data{description};


	my $roles="'norole'";
	$roles="'".join("', '",@{$data{roles}})."'" if $data{roles};

	return \%data;
}

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
