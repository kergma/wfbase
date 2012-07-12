package wf::Model::udb;
use Moose;
use namespace::autoclean;

extends 'Catalyst::Model';

use DBI;
use Digest::MD5;
use Encode;
use Date::Format;

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


my $cc;

sub ACCEPT_CONTEXT
{
	my ($self,$c,@args)=@_;

	$cc=$c;
	return $self;
}

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

sub search_records
{
	my ($self,$filter)=@_;

	my %where=('1=?',1);
	$where{'recid=?'}=$filter->{recid} if $filter->{recid};
	$where{'lower(defvalue)~lower(?)'}=$filter->{defvalue} if $filter->{defvalue};
	$where{'lower(defvalue)~lower(?)'}=~s/ +/\.\*/ if $filter->{defvalue};
	$where{'rectype=?'}=$filter->{rectype} if $filter->{rectype};
	my $limit=$filter->{limit}||0;
	$limit+0 or $limit="";
	$limit and $limit="limit $limit";
	return read_table($self,sprintf(qq/select * from recv where %s order by 2 $limit/,join(" and ",keys %where)),values %where);
}
sub read_record
{
	my ($self,$id)=@_;
	return db::selectall_arrayref(qq/
select s.*,
(select comma(distinct defvalue) from recv where recid<>? and (recid=s.v1 or recid=s.v2)) as refdef,
(select comma(distinct rectype) from recv where recid<>? and (recid=s.v1 or recid=s.v2)) as reftype 
from
(select id,v1,r,null as v2 from data where v2=? union select id,null as v1,r,v2 from data where v1=?) s
/,{Slice=>{}},$id,$id,$id,$id);

}
sub rectypes
{
	my ($self)=@_;
	return cached_array_ref($self,qq/select distinct rectype from recv where rectype is not null order by 1/);
}
sub read_row
{
	my ($self,$id)=@_;
	return db::selectrow_hashref(qq/
select s.*,
(select comma(distinct defvalue) from recv where recid=s.v1) as def1,
(select comma(distinct rectype) from recv where recid=s.v1) as rt1,
(select comma(distinct defvalue) from recv where recid=s.v2) as def2,
(select comma(distinct rectype) from recv where recid=s.v2) as rt2
from data s where id=?
/,undef,$id);

}

sub datarow
{
	my ($self,$id)=@_;
	return db::selectrow_hashref(qq/select * from data where id=?/,undef,$id);
}
sub recdef
{
	my ($self,$recid)=@_;
	my $r=db::selectrow_arrayref(qq/select defvalue,rectype from recv where recid=?/,undef,$recid);
	return (undef,undef) unless $r;
	return @$r;
}

sub update_row
{
	my ($selft,$id,$v1,$r,$v2)=@_;
	return db::do("update data set v1=?,r=?,v2=? where id=?",undef,$v1,$r,$v2,$id);
}
sub delete_row
{
	my ($selft,$id)=@_;
	return db::do("delete from data where id=?",undef,$id);
}


sub relations
{
	my ($self)=@_;
	return cached_array_ref($self,qq/select distinct r from data order by 1/);
}

sub init_schema
{
	db::do(qq/
create or replace view recv as
select distinct
rec.v2 as recid,
def.v1 as defvalue,
case when def.r ='наименование списка' then 'Список' when def.r ='наименование ИС' then 'Информационная система' when def.r='наименование структурного подразделения' then 'Структурное подразделение' when def.r='ФИО сотрудника' then 'Сотрудник' when def.r like '%учётной записи%' then 'Учётная запись' else null end as rectype
from  data rec
left join data def on def.v2=rec.v2 and (def.r like 'наименование %' or def.r like 'ФИО %' or def.r like 'имя входа учётной записи')
/);
}

sub cached_array_ref
{
	my ($self, $q, @values)=@_;

	my $md5=Digest::MD5->new;
	$md5->add($q);
	$md5->add($_) foreach @values;
	my $qkey=$md5->hexdigest();

	my $result=$cc->cache->get("aref-".$qkey);
	unless ($result)
	{
		$result=db::selectall_arrayref($q,{Slice=>{}},@values);
		@$result=map {values %$_} @$result if keys(%{$result->[0]})==1;
		$cc->cache->set("aref-".$qkey,$result);
	};
	return $result;
}

sub read_table
{
	my $self=shift;
	my $query=shift;
	my @values=@_;

	my $start=time;

	my $sth=db::prepare($query);
	$sth->execute(@values);

	my %result=(query=>$query,values=>[@values],header=>[map(encode("utf8",$_),@{$sth->{NAME}})],rows=>[]);

	while(my $r=$sth->fetchrow_hashref)
	{
		push @{$result{rows}}, {map {encode("utf8",$_) => $r->{$_}} keys %$r};;
	};
	$sth->finish;

	$result{duration}=time-$start;
	$result{retrievedf}=$result{retrieved}=time2str('%Y-%m-%d %H:%M:%S',time);

	return \%result;
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

sub errstr
{
	return $DBI::errstr;
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
	wf::Model::udb::init_schema();
}


sub selectval_scalar
{
	my $row=db::selectrow_arrayref(@_);
	return undef unless $row;
	return $row->[0];
}

1;
