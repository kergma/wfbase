package wf::Model::ppdb;

use strict;
use warnings;
use parent 'Catalyst::Model';
use DBI;
use Date::Format;
use Encode;
use Digest::MD5;
use POSIX ":sys_wait_h";
use Time::HiRes 'usleep';
use packetproc;
use db;



=head1 NAME

wf::Model::ppdb - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

my $dbh;
my $cc;

sub ACCEPT_CONTEXT
{
	my ($self,$c,@args)=@_;

	$cc=$c;
	return $self;
}

sub connect
{
	$dbh and return $dbh;
	$dbh=DBI->connect("dbi:Pg:dbname=mailproc;host=ppdb", 'mailproc', undef, {AutoCommit => 1,InactiveDestroy=>1});
	return $dbh;
}

sub sconnect
{
	my $sdbh=DBI->connect("dbi:Pg:dbname=mailproc;host=ppdb", 'stat', undef, {AutoCommit => 1});
	$sdbh->do("create function pg_temp.wfuser() returns uuid as \$\$select '${\($cc->user->{souid})}'::uuid\$\$ language sql");
	return $sdbh;
}

sub array_ref
{
	my ($self, $q, @values)=@_;
	$self->connect() or return undef;

	my $sth=$dbh->prepare($q);
	$sth->execute(@values);
	my @result=();
	while(my $r=$sth->fetchrow_hashref)
	{
		push @result,join('',values %$r) if keys(%$r)==1;
		push @result,$r if keys(%$r)>1;
	};
	return \@result;
}

sub cached_array_ref
{
	my ($self, $q, @values)=@_;
	$self->connect() or return undef;

	my $md5=Digest::MD5->new;
	$md5->add($q);
	$md5->add($_) foreach @values;
	my $qkey=$md5->hexdigest();

	my $result=$cc->cache->get("aref-".$qkey);
	unless ($result)
	{
		$result=array_ref($self,$q,@values);
		$cc->cache->set("aref-".$qkey,$result);
	};
	return $result;
}

sub read_row
{
	my ($self, $table, $id)=@_;
	$self->connect() or return undef;
	defined $cc or return undef;
	$table =~ /^[[:alnum:]_]+$/ or return undef;
	return {error=>'Действие не разрешено'} unless $dbh->selectrow_hashref("select * from data where v1=? and r='разрешение на чтение таблицы для роли' and v2 in (".join(', ',map ('?',@{$cc->user->{roles}})).")",undef,$table,@{$cc->user->{roles}});
	$id or undef $id;
	my $sth=$dbh->prepare("select * from ".$dbh->quote_identifier($table)." where id=?");
	$sth->execute($id);
	my $r=$sth->fetchrow_hashref();
	my %data=(header=>$sth->{NAME},data=>$r);
	$data{error}='Строка не найдена' unless $r;
	return \%data;

}

sub update_row
{
	my ($self, $table, $id, $set)=@_;
	$self->connect() or return undef;
	defined $cc or return undef;
	$table =~ /^[[:alnum:]_]+$/ or return undef;
	return {error=>'Действие не разрешено'} unless $dbh->selectrow_hashref("select * from data where v1=? and r='разрешение на ввод данных в таблицу для роли' and v2 in (".join(', ',map ('?',@{$cc->user->{roles}})).")",undef,$table,@{$cc->user->{roles}});
	return {error=>'Некорректный  идентификатор записи'} unless $id+0;
	my $rv=$dbh->do("update ".$dbh->quote_identifier($table)." set ".join(', ',map ("$_=?",keys %$set))." where id=?",undef,map($set->{$_},keys %$set),$id);
	return {rv=>$rv, error=>"Ошибка при сохранении изменений: $DBI::errstr"} unless $rv==1;
	return {rv=>$rv};

}

sub insert_row
{
	my ($self, $table, $pairs)=@_;
	$self->connect() or return undef;
	defined $cc or return undef;
	$table =~ /^[[:alnum:]_]+$/ or return undef;
	return {error=>'Действие не разрешено'} unless $dbh->selectrow_hashref("select * from data where v1=? and r='разрешение на ввод данных в таблицу для роли' and v2 in (".join(', ',map ('?',@{$cc->user->{roles}})).")",undef,$table,@{$cc->user->{roles}});
	
	my $r=$dbh->selectrow_hashref("select nextval('$table"."_id_seq') as id");
	$r=$dbh->selectrow_hashref("select uuid_generate_v1o() as id") unless $r;
	return {error=>'Ошибка при определении идентификатора новой записи'} unless $r;

	my $rv=$dbh->do("insert into ".$dbh->quote_identifier($table)." (id, ".join(', ', keys %$pairs).") values (?, ".join(', ',map ("?",values %$pairs)).")",undef,$r->{id},values %$pairs);

	return {error=>"Ошибка при добавлении записи: $DBI::errstr"} unless $rv==1;
	
	return {rv=>$rv,id=>$r->{id}};

}

sub delete_row
{
	my ($self, $table, $id)=@_;
	$self->connect() or return undef;
	defined $cc or return undef;
	$table =~ /^[[:alnum:]_]+$/ or return undef;
	return {error=>'Действие не разрешено'} unless $dbh->selectrow_hashref("select * from data where v1=? and r='разрешение на удаление данных из таблицы для роли' and v2 in (".join(', ',map ('?',@{$cc->user->{roles}})).")",undef,$table,@{$cc->user->{roles}});

	return {error=>'Некорректный  идентификатор записи'} unless $id+0;

	my $rv=$dbh->do("delete from ".$dbh->quote_identifier($table)." where id=?",undef,$id);

	return {rv=>$rv,error=>"Ошибка при удалении записи: $DBI::errstr"} unless $rv==1;
	
	return {rv=>$rv};
}


sub get_otd_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	return cached_array_ref($self,"select otd from orders where otd ~ ? group by otd order by otd",$cc->user->{otd});
}
sub get_sp_list
{
	my ($self,$souid)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	my $r=cached_array_ref($self,"select v2 as sp, shortest(v1) as spname from data d where r='наименование структурного подразделения' and v2 in (select (items_of).item from (select items_of(v2) from data where r='принадлежит структурному подразделению' and v1=?) s union select v2 from data where r='принадлежит структурному подразделению' and v1=?) group by v2 order by 2",$souid,$souid);
	$_={$_->{sp}=>$_->{spname}} foreach @$r;
	return $r;
}
sub get_outersp_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	my $r=cached_array_ref($self,qq"
select v2 as sp, shortest(v1) as spname, 1 as ord from data d where r='наименование структурного подразделения' and v2 in ('a9b7079b-26de-49e3-8d16-9e141d644faf','d86e0ad4-4824-430b-9790-5e78e3a87cae') group by v2
union
select d.v2 as sp, shortest(d.v1) as spname, 2 as ord from (
select v2,items_of(v2) from data where lower(v1) like '%отделение%' and r='свойства структурного подразделения' 
) s 
join data d on d.r='наименование структурного подразделения' and d.v2 in (s.v2,(s.items_of).item)
group by d.v2
order by ord,2
");
	$_={$_->{sp}=>$_->{spname}} foreach @$r;
	return $r;
}

sub get_cd_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return cached_array_ref($self,"select cadastral_district from objects where cadastral_district is not null group by cadastral_district order by cadastral_district");
}

sub get_objsource_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return cached_array_ref($self,"select source from objects where source is not null group by source order by source");
}

sub get_rc_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return cached_array_ref($self,"select reg_code from packets where reg_code is not null group by reg_code order by reg_code");
}
sub get_pt_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return cached_array_ref($self,"select type from packets where type is not null group by type order by type");
}

sub get_field_list
{
	my ($self,$table)=@_;
	$self->connect() or return undef;
	my $sth=$dbh->prepare("select * from $table where false");
	$sth->execute();
	$sth->fetchrow_hashref();
	$sth->finish;
	return $sth->{NAME};
}

sub get_path_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return cached_array_ref($self,"select path from packets where path is not null group by path order by path");
}

sub get_event_list
{
	my ($self,$refto)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my $reftow="";
	$refto and $reftow="and refto=".$dbh->quote($refto);
	return cached_array_ref($self,"select event from log where event is not null $reftow and id>uuid_generate_v1o(now()-3*interval '1 month') group by event order by event");
}

sub get_who_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	return cached_array_ref($self,"select (select v1::uuid from sdata where r='ФИО сотрудника' and v2::uuid=l.who) as who from log l where who is not null group by who order by who");
}

sub get_coworkers_list
{
	my ($self,$souid)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	my $r=cached_array_ref($self,qq/
select comma(distinct fio_cw.v1) as fio, fio_cw.v2 as souid
from data dc
join data cw on cw.r='принадлежит структурному подразделению' and cw.v2=dc.v2
join data fio_cw on fio_cw.r='ФИО сотрудника' and fio_cw.v2=cw.v1
where dc.v1=? and dc.r='принадлежит структурному подразделению'
group by fio_cw.v2
order by 1
/,$souid);
	$_={$_->{souid}=>$_->{fio}} foreach @$r;
	return $r;
}

sub get_dispatchee_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	my $r=cached_array_ref($self,qq/
select v2 as uid, shortest(v1) as name from data where r in ('ФИО сотрудника', 'наименование структурного подразделения') group by v2,r order by r, name
/);
	$_={$_->{uid}=>$_->{name}} foreach @$r;
	return $r;
}


sub get_oper_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	return cached_array_ref($self,qq/
select d2.v1 as who
from data d1
join data d2 on d2.v2=d1.v2 and d2.r='ФИО сотрудника' 
where d1.v1 ~ 'оператор|проверяющий' and d1.r ='описание сотрудника'
order by who
/);
}

sub get_refto_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	return cached_array_ref($self,"select refto from log_old where refto is not null group by refto order by refto");
}

sub authinfo_password
{
	my ($self,$authinfo)=@_;
	$self->connect() or return undef;
	my $r=$dbh->selectrow_hashref("select * from data where v2=? and r like 'пароль%'",undef,$authinfo->{username});
	$r or return undef;
	return $r->{v1};
}

sub authinfo_data
{
	my ($self,$authinfo)=@_;
	$self->connect() or return undef;
	my %data=%$authinfo;

	my $r=$dbh->selectrow_hashref(qq/
select lo_so.v2 as souid,lo_so.v1 as login,
(select v1 from data where r like 'пароль %' and v2=lo_so.v1) as password,
(select comma(v1) from data where r='ФИО сотрудника' and v2=lo_so.v2) as full_name,
(select comma(distinct lower(v1)) from data where r='свойства сотрудника' and v2 in (select container from containers_of(lo_so.v2) union select lo_so.v2)) as props,
(select comma(distinct lower(v1)) from data where r like 'описание %' and v2=lo_so.v2) as desc
from data lo_so
where lo_so.r='логин сотрудника' and lo_so.v1=?
/
,undef,$authinfo->{username});

	%data=(%data,%$r) if $r;
	push @{$data{roles}}, split / +/,$data{description};
	push @{$data{roles}}, split /,\s*/,$data{props};

	push @{$data{roles}}, $authinfo->{username};
	push @{$data{roles}}, 'отправляющий' if grep {/наблюдающий|оператор/} @{$data{roles}};

	$data{otd}='';

	my $roles="'norole'";
	$roles="'".join("', '",@{$data{roles}})."'" if $data{roles};
	my $otds=$dbh->selectcol_arrayref(qq/
select v1 from data where r='отделение сотрудника' and v2=?
union
select otd from orders group by otd having otd = ? 
union
select v1 from data where r='отделение сущности' and v2=?
/,undef, $data{souid},$data{username},$data{full_name});
	$otds and @$otds and $data{otd}=join("|",@$otds);

	my $sp=$dbh->selectall_arrayref(qq/
select so_sp.v2 as uid,comma(name_sp.v1) as name
from data so_sp
join data name_sp on name_sp.v2=so_sp.v2 and name_sp.r='наименование структурного подразделения'
where so_sp.r='принадлежит структурному подразделению' and so_sp.v1=?
group by so_sp.v2
/,{Slice=>{}}, $data{souid});
	$data{sp}=[map {$_->{uid}} @$sp];
	$data{spname}=[map {$_->{name}} @$sp];

	return \%data;
}

sub souid
{
	my ($self, $who)=@_;
	$self->connect() or return undef;
	return $who if $who=~/^[a-f0-9\-]{36}$/;

	my $whocache=$cc->cache->get("whosouidmap");
	return $whocache->{$who} if $whocache->{$who};
	my $sth=db::prepare("select distinct v2 as souid from data where r='ФИО сотрудника' and v1=?");
	$sth->execute($who);

	$whocache->{$who}=($sth->fetchrow_hashref()//{})->{souid};
	delete $whocache->{$who} if $sth->fetchrow_hashref();

	$cc->cache->set("whosouidmap") if $whocache->{$who};
	return $whocache->{$who};
}
sub sodata
{
	my ($self, $souid)=@_;
	$self->connect() or return undef;
	my $sodata=$cc->cache->get("sodata-$souid");
	unless ($sodata)
	{
		
		$sodata=db::selectrow_hashref(qq/
select fio_so.v2 as souid, fio_so.v1 as full_name, lo_so.v1 as login
from data fio_so
join data lo_so on lo_so.v2=fio_so.v2 and lo_so.r='логин сотрудника'
where fio_so.v2=? and fio_so.r='ФИО сотрудника'
/,undef,$souid);
		$cc->cache->set("sodata-$souid",$sodata);
	};
	return $sodata;
}

sub log_event
{
	my $self=shift;

	my %data=scalar(@_)==1?%{$_[0]}:(@_);
	my $event_id=packetproc::newid();
	my $rv=db::do("insert into log (id,event,who,note,refto, refid, cause) values (?,?,?,?,?,?,?)",undef,$event_id,$data{event},$data{who},$data{note},$data{refto},$data{refid},$data{cause});
	return $event_id if $rv;
}

sub read_order_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my $r=$dbh->selectrow_hashref(qq{
select o.*,
(select event from log where refto='orders' and refid=o.id order by id desc limit 1) as ostatus,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='orders' and refid=o.id order by id desc limit 1) as osdate,
(select event from log where refto='packets' and refid in (select id from packets where order_id=o.id) order by id desc limit 1) as pstatus,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid in (select id from packets where order_id=o.id) order by id desc limit 1) as psdate
from orders o where id=? and otd ~ ?
},undef,$id,$cc->user->{otd});
	return undef unless $r;
	my %data;
	$data{order}=$r;
	$r=$dbh->selectrow_hashref("select * from objects where id=?",undef,$r->{object_id});
	$data{object}=$r;

	my $sth=$dbh->prepare("select * from packets where order_id=? order by id desc");
	$sth->execute($id);
	my %packets=(elements=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$packets{elements}},$r;
	};
	$sth->finish;
	$data{packets}=\%packets;

	$sth=$dbh->prepare(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,coalesce((select v1 from sdata where r='ФИО сотрудника' and v2::uuid=l.who limit 1),who::text) as who,refto,refid,cause
from log l
where (refto='orders' and refid=?)
or (refto='packets' and refid in (select id from packets where order_id=?))
or (refto='objects' and refid=(select object_id from orders where id=?))
order by id desc/);
	$sth->execute($id,$id,$id);
	my %events=(elements=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$events{elements}},$r;
	};
	$sth->finish;
	$data{events}=\%events;
	return \%data;
}

sub read_object_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my $r=$dbh->selectrow_hashref("select * from objects o where id=? and (exists (select 1 from orders where object_id=o.id and otd ~ ?) or not exists (select 1 from orders where object_id=o.id))",undef,$id,$cc->user->{otd});
	return undef unless $r;

	my %data;
	$data{object}=$r;

	my %orders;
	my $sth=$dbh->prepare(qq{
select o.*,
(select to_char(date,'yyyy-mm-dd') from log_old where event='принят' and refto='orders' and refid=o.id order by id desc limit 1) as accepted,
(select to_char(date,'yyyy-mm-dd') from log_old where event='оплачен' and refto='orders' and refid=o.id order by id desc limit 1) as paid
from orders o where object_id=? order by id desc
});
	$sth->execute($id);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$orders{elements}},$r;
	};
	$sth->finish;
	$data{orders}=\%orders;

	my %packets=(elements=>[]);
	$sth=$dbh->prepare("select * from packets where order_id in (select id from orders where object_id=?) order by id desc");
	$sth->execute($id);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$packets{elements}},$r;
	};
	$sth->finish;
	$data{packets}=\%packets;

	$sth=$dbh->prepare(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,who,refto,refid,file,
(select id from timeline t where t.basename=l.file order by id desc limit 1) as message
from log_old l
where (refto='orders' and refid in (select id from orders where object_id=?))
or (refto='packets' and refid in (select id from packets where order_id in (select id from orders where object_id=?)))
or (refto='objects' and refid=?)
order by id desc/);
	$sth->execute($id,$id,$id);
	my %events=(elements=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$events{elements}},$r;
	};
	$sth->finish;
	$data{events}=\%events;
	return \%data;
}

sub read_packet_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %data;
	my $packet=$dbh->selectrow_hashref(qq{
select p.*,
(select coalesce(d.v1,who::text) from log l left join data d on d.r='ФИО сотрудника' and v2::uuid=l.who where refto='packets' and refid=p.id order by l.id desc limit 1) as who,
(select event || ' '|| to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id order by id limit 1) as accepted,
(select event from log where refto='packets' and refid=p.id order by id desc limit 1) as status,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id order by id desc limit 1) as status_date
from packets p where id=?}
,undef,$id);
	return undef unless $packet;
	$data{packet}=$packet;

	my $order=$dbh->selectrow_hashref("select * from orders where id=?",undef,$packet->{order_id});
	$data{order}=$order;

	my $object=$dbh->selectrow_hashref("select * from objects where id=?",undef,$order->{object_id});
	$data{object}=$object;

	my $sth=$dbh->prepare(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,coalesce((select v1 from sdata where r='ФИО сотрудника' and v2::uuid=l.who limit 1),who::text) as who,refto,refid,cause
from log l
where (refto='packets' and refid = ?)
or (refto='orders' and refid=?)
or (refto='packets' and refid in (select id from packets where order_id = ?))
or (refto='objects' and refid=?)
order by id desc/);
	$sth->execute($packet->{id},$order->{id},$order->{id},$object->{id});
	my %events=(elements=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$events{elements}},$r;
	};
	$sth->finish;
	$data{events}=\%events;
	return \%data;
}

sub read_event_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %data;
	my $event=$dbh->selectrow_hashref(qq{
select id,date,event,coalesce((select v1 from sdata where r='ФИО сотрудника' and v2::uuid=l.who limit 1),who::text) as who,note,refto,refid,cause from log l where id=?}
,undef,$id);
	return undef unless $event;
	$data{event}=$event;

	my $order=$dbh->selectrow_hashref("select * from orders where id=(select coalesce((select refid where refto='orders'),(select order_id from packets where id=refid and refto='packets')) from log where id=?)",undef,$event->{id});
	$data{order}=$order;


	my $packet=$dbh->selectrow_hashref("select * from packets where id=(select refid from log where refto='packets' and id=?)",undef,$event->{id});
	$data{packet}=$packet;

	my $object=$dbh->selectrow_hashref("select * from objects where id=(select coalesce((select l.refid where l.refto='objects'),(select object_id from orders where id=l.refid and l.refto='orders'),(select o.object_id from orders o join packets p on p.order_id=o.id where p.id=l.refid and l.refto='packets')) from log l where id=?)",undef,$id);
	$data{object}=$object;

	my $orders=$data{orders}->{elements}=db::selectall_arrayref(qq{select * from orders o where id in (select refid from log where refto='orders' and id=?) or object_id in (select refid from log where refto='objects' and id=?) order by id desc},{Slice=>{}},$id,$id);
	my $packets=$data{packets}->{elements}=db::selectall_arrayref("select * from packets where order_id in (select refid from log where refto='orders' and id=? union select id from orders where object_id=(select refid from log where refto='objects' and id=?)) order by id desc",{Slice=>{}},$id,$id);

	push @$orders,{id=>undef};
	push @$packets,{id=>undef};

	my $sth=$dbh->prepare(sprintf(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,coalesce((select v1 from sdata where r='ФИО сотрудника' and v2::uuid=l.who limit 1),who::text) as who,refto,refid, cause
from log l
where id=?
or (refto=? and refid=?)
or (refto='orders' and refid in (%s))
or (refto='packets' and refid in (%s))
or (refto='objects' and refid=?)
order by id desc/,join(',',map {'?'} @$orders),join(',',map {'?'} @$packets)));
	$sth->execute($event->{id},$event->{refto},$event->{refid},map ($_->{id},@$orders),map ($_->{id}, @$packets),$object->{id});
	my %events=(elements=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$events{elements}},$r;
	};
	$sth->finish;
	$data{events}=\%events;

	@$orders=grep {$_->{id}} @$orders;
	@$packets=grep {$_->{id}} @$packets;
	return \%data;
}

sub read_table
{
	my $self=shift;
	my $query=shift;
	my @values=@_;

	$self->connect() or return undef;

	my $start=time;

	my $sth=$dbh->prepare($query);
	$sth->execute(@values);

	my %result=(query=>$query,values=>[@values],header=>[map(encode("utf8",$_),@{$sth->{NAME}})],rows=>[]);

	while(my $r=$sth->fetchrow_hashref)
	{
		push @{$result{elements}}, {map {encode("utf8",$_) => $r->{$_}} keys %$r};;
	};
	$sth->finish;

	$result{duration}=time-$start;
	$result{retrieved}=time2str('%Y-%m-%d %H:%M:%S',time);

	return \%result;
}

sub search_objects
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %where;
	$where{"1=?"}=1;
	$where{"exists (select 1 from orders where object_id=o.id and otd ~ ?)"}=$cc->user->{otd} if $cc->user->{otd}; 
	$where{"o.id = ?"}=$filter->{object_id} if $filter->{object_id};
	$where{"o.cadastral_district = ?"}=$filter->{cadastral_district} if $filter->{cadastral_district};
	$where{"lower(o.address) ~ lower(?)"}=$filter->{address} if $filter->{address};
	$where{"lower(o.name) ~ lower(?)"}=$filter->{name} if $filter->{name};
	$where{"lower(o.invent_number) ~ lower(?)"}=$filter->{invent_number} if $filter->{invent_number};
	$where{"lower(o.cadastral_number) ~ lower(?)"}=$filter->{cadastral_number} if $filter->{cadastral_number};
	$where{"o.source = ?"}=$filter->{source} if $filter->{source};

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=query($self,qq{
select 
id, cadastral_district, address, name, invent_number, cadastral_number, source
from objects o
where }
.join (" and ",keys %where)." order by id desc $limit",$filter,map($where{$_},keys %where)
);
	
	return $result;

}

sub search_orders
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	my $start=time;

	my %where;
	$where{"coalesce(o.otd,'') ~ ?"}=$cc->user->{otd};
	$where{"o.id=?"}=$filter->{order_id} if $filter->{order_id};
	$where{"o.otd=?"}=$filter->{otd} if $filter->{otd};
	$where{"exists (select 1 from log l left join packets p on l.refto='packets' and p.id=l.refid join orders o2 on o2.id=p.order_id or (l.refto='orders' and o2.id=l.refid) where who=? and o2.id=o.id)"}=$filter->{who} if $filter->{who}=~/^[a-f0-9\-]{36}$/;
	$where{"exists (select 1 from log l left join packets p on l.refto='packets' and p.id=l.refid join orders o2 on o2.id=p.order_id or (l.refto='orders' and o2.id=l.refid) where who in (select v2::uuid from sdata where r='ФИО сотрудника' and lower(v1)~lower(?)) and o2.id=o.id)"}=$filter->{who} if $filter->{who} and $filter->{who}!~/^[a-f0-9\-]{36}$/;;
	$where{"o.year=?"}=$filter->{year} if $filter->{year};
	$where{"o.ordno=?"}=$filter->{ordno} if $filter->{ordno};
	$where{"o.objno=?"}=$filter->{objno} if $filter->{objno};
	$where{"exists (select 1 from log l where refto='orders' and refid=o.id and not exists (select 1 from log where refto=l.refto and refid=l.refid and id>l.id) and event=?)"}=$filter->{ostatus} if $filter->{ostatus};
	$where{"exists (select 1 from log l join packets p on p.id=l.refid and l.refto='packets' where p.order_id=o.id and not exists (select 1 from log where refto=l.refto and refid=l.refid and id>l.id) and l.event=?)"}=$filter->{pstatus} if $filter->{pstatus};
	$where{"exists (select 1 from objects where id=o.object_id and lower(address) ~ lower(?))"}=$filter->{address} if $filter->{address};

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=query($self,sprintf(qq{
select o.*,
j.address,
j.invent_number,
(
select comma(distinct substring(who from E'^\\\\S+')) as who from (
select (select v1 from sdata where v2::uuid=who and r='ФИО сотрудника' limit 1) as who from log where refto='orders' and refid=o.id
union  
select (select v1 from sdata where v2::uuid=who and r='ФИО сотрудника' limit 1) as who from log where refto='packets' and refid in (select id from packets where order_id=o.id) 
) s
) as whos
from (
select
o.*,
(select (id,event)::record from log l where refto='orders' and refid=o.id and not exists (select 1 from log where refto=l.refto and refid=l.refid and id<l.id)) as oevent,
(
select array_agg((l.id,l.event)::record) as a from log l where refto='packets' and refid in (select id from packets where order_id=o.id) and not exists (select 1 from log where refto=l.refto and refid=l.refid and id>l.id)
) as pevents
from (
select * from orders o
where
%s
order by o.id desc %s
) o
) o
left join objects j on j.id=o.object_id
},join(" and ",keys %where),$limit),$filter,map($where{$_},keys %where));
	
	return $result;

}

sub search_packets
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %where;
	$where{"1=?"}='1';
	$where{"p.id = ?"}=$filter->{packet_id} if $filter->{packet_id};
	$where{"o.id = ?"}=$filter->{ordspec} if $filter->{ordspec};
	$where{"o.sp = ?"}=$filter->{sp} if $filter->{sp};
	$where{"p.type = ?"}=$filter->{type} if $filter->{type};
	$where{"exists (select 1 from log l where id>=least(o.id, p.id) and refid in (p.id,o.id) and who::text in (select v2 from sdata where r in ('ФИО сотрудника','наименование структурного подразделения') and lower(v1)~lower(?)))"}=$filter->{who} if $filter->{who};
	$where{"exists (select 1 from files fi where fi.id=p.container and lower(fi.name)~lower(?))"}=$filter->{file} if $filter->{file};
	$where{"exists (select 1 from log l where refto='packets' and refid=p.id and event=? and not exists (select 1 from log where refto=l.refto and refid=l.refid and id>l.id))"}=$filter->{status} if $filter->{status};

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $w=join (" and ",keys %where);
	my $result=query($self,qq{
create table pg_temp.vi as select ?::uuid as id;
insert into pg_temp.vi select d.v2::uuid from pg_temp.vi join sdata d on d.r='принадлежит структурному подразделению' and d.v1=vi.id::text;
insert into pg_temp.vi select (s.items_of).item::uuid from (select items_of(id::text) from pg_temp.vi) s join sdata d on d.r='наименование структурного подразделения' and d.v2=(s.items_of).item;
select
s.*, event as status, to_char(date,'yyyy-mm-dd hh24:mi') status_date, l.id as status_event,
(select name from files where id=s.container) as container_name,
(select v1 from sdata where r='наименование структурного подразделения' and v2=s.sp::text order by length(v1) limit 1) as spname
from (
select p.id as packet_id, o.sp, type, container
from packets p
left join orders o on o.id=p.order_id
where 
(
o.sp in (select id from pg_temp.vi) 
or p.id in (select refid from log l join vi on l.who=vi.id and refto='packets')
or o.id in (select refid from log l join vi on l.who=vi.id and refto='orders')
) and 
$w
order by p.id desc
$limit
) s
left join log l on l.refto='packets' and l.refid=s.packet_id and not exists (select 1 from log where refto='packets' and refid=l.refid and id>l.id)
;
--select * from pg_temp.vi;
},$filter,$cc->user->{souid},map($where{$_},keys %where)
);
	
	return $result;

}

sub search_events
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my @where;
	push @where, "o.otd ~ ".$dbh->quote($cc->user->{otd}) if $cc->user->{otd};
	push @where, "o.otd = ".$dbh->quote($filter->{otd}) if $filter->{otd};
	push @where, "l.id = ".$dbh->quote($filter->{event_id}) if $filter->{event_id};
	push @where, "l.date > ".$dbh->quote($filter->{from}) if $filter->{from};
	push @where, "l.date <= ".$dbh->quote($filter->{to}) if $filter->{to};
	push @where, "l.event = ".$dbh->quote($filter->{event}) if $filter->{event};
	push @where, "l.who  in (select v2::uuid from sdata where r='ФИО сотрудника' and v1=".$dbh->quote($filter->{who}).")" if $filter->{who};
	push @where, sprintf "lower(l.note) ~ lower(%s)", $dbh->quote($filter->{note}) if $filter->{note};
	push @where, "l.refto = ".$dbh->quote($filter->{refto}) if $filter->{refto};
	push @where, "l.refid = ".$dbh->quote($filter->{refid}) if $filter->{refid};
	push @where, sprintf "lower(obj.address) ~ lower(%s)", $dbh->quote($filter->{address}) if $filter->{address};
	push @where, sprintf "lower(obj.invent_number) ~ lower(%s)", $dbh->quote($filter->{invent_number}) if $filter->{invent_number};
	scalar @where or push @where,'true';

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=query($self,qq{
select
l.id, to_char(date,'yyyy-mm-dd hh24:mi') as date,event,coalesce((select v1 from sdata where r='ФИО сотрудника' and v2::uuid=l.who limit 1),who::text) as who,note,refto,refid,o.otd,obj.invent_number,obj.address,obj.name,l.cause
from log l
left join orders o on o.id=coalesce((select l.refid where l.refto='orders'), (select order_id from packets where id=l.refid and l.refto='packets'),(select '00000000000000000000000000000000'::uuid where l.refto='objects'))
left join objects obj on obj.id=o.object_id or (obj.id=l.refid and l.refto='objects')
where l.id in
(
select l.id
from log l
left join orders o on o.id=coalesce((select l.refid where l.refto='orders'), (select order_id from packets where id=l.refid and l.refto='packets'),(select '00000000000000000000000000000000'::uuid where l.refto='objects'))
left join objects obj on obj.id=o.object_id or (obj.id=l.refid and l.refto='objects')
where
}.join (" and ",@where).qq{
order by l.id desc $limit
)
order by l.id desc
},$filter);
	
	return $result;

}

sub dispatch_queue
{
	my ($self,$filter)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my @where;
	push @where, "p.reg_code='raw'" if $filter->{type} eq 'Исходные';
	push @where, "p.reg_code<>'raw'" if $filter->{type} eq 'XML';
	
	push @where, "l.event in ('филиал','проверка')" if $filter->{event} eq 'Проверка';
	push @where, "(l.event='ввод' or (l.event='проверен' and p.reg_code='raw'))" if $filter->{event} eq 'Ввод';
	push @where, "(l.event in ('филиал','проверка','ввод') or (l.event='проверен' and p.reg_code='raw'))" if $filter->{event} eq 'Все' or !defined($filter->{event});

	push @where, "(l.event='филиал' or (l.event='проверен' and p.reg_code='raw'))" if $filter->{state} eq 'В ожидании';
	push @where, "(l.event in ('проверка','ввод'))" if $filter->{state} eq 'Обрабатываются';

	push @where, 'not exists (select 1 from log_old where id>l.id and refto=l.refto and refid=l.refid)';

	scalar @where or push @where,'true';

	my $result=query($self,qq{
select o.id as order_id, o.kpeta, p.path, p.id as packet_id, p.reg_code,
o.otd, 
coalesce((select max(d.v1) from sdata d where d.v2=o.otd and d.r ='приоритет отделения' union select max(d.v1) from sdata d where d.v2=p.path and d.r ='приоритет направления' order by 1 desc limit 1),'0') as priority,
j.id as object_id,j.address,j.invent_number,
l.event,l.who,to_char(l.date,'yyyy-mm-dd hh24:mi') as date
from log_old l 
join packets p on p.id=l.refid and l.refto='packets'
join orders o on o.id=p.order_id
left join objects j on j.id=o.object_id
where 
}.join (" and ",@where).qq{
order by o.kpeta, p.id
},$filter);
	
	return $result;

}

sub read_run_status
{
	my ($self,$id)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %data;
	#$data{running}{elements}=read_table($self,"select * from run where completed is null and started is not null order by id desc");
	$data{running}=read_table($self,qq/
select r.id, r.id as run_id, r.task_id, t.value as task_name, to_char(r.started,'yyyy-mm-dd hh24:mi:ss') as started, now()-started as last
from run r 
join syslog t on t.id=r.task_id and t.key_id='1e110f2f-aea6-5921-b330-33e52e05cc17' --задача
where completed is null and started is not null
order by r.id
/
);
	$data{running}{elements}=[] unless defined $data{running}{elements};

	$data{scheduled}=read_table($self,qq/
select r.id, r.id as run_id, r.task_id, t.value as task_name, to_char(r.at,'yyyy-mm-dd hh24:mi:ss') as at, at-now() as in
from run r 
join syslog t on t.id=r.task_id and t.key_id='1e110f2f-aea6-5921-b330-33e52e05cc17' --задача
where completed is null and started is null
order by r.id desc
/
);
	$data{scheduled}{elements}=[] unless defined $data{scheduled}{elements};

	$data{completed}=read_table($self,qq/
select r.id, r.id as run_id, r.task_id, t.value as task_name, to_char(r.started,'yyyy-mm-dd hh24:mi:ss') as started, to_char(r.completed,'yyyy-mm-dd hh24:mi:ss') as completed, now()-completed as last
from run r 
join syslog t on t.id=r.task_id and t.key_id='1e110f2f-aea6-5921-b330-33e52e05cc17' --задача
where completed is not null and completed>=date_trunc('day',now())
order by r.id desc
/
);
	$data{completed}{elements}=[] unless defined $data{completed}{elements};
	return \%data;
}
sub query
{
	my $self=shift;
	my $query=shift;
	my $params=shift;
	my @values=@_;

	my $cache=$cc->cache;

	my $md5=Digest::MD5->new;
	$md5->add($query);
	$md5->add($_) foreach @values;
	my $qkey=$md5->hexdigest();
	my $querying=$cache->get("qkey-$qkey");
	if (defined $querying)
	{
		return {retrieval=>$querying->{retrieval}};
	};

	my $retrieval=Digest::MD5::md5_hex(rand());
	my $start=time;

	$SIG{CHLD} = 'IGNORE';
	my $child=fork();

	unless (defined $child)
	{
		return {error=>'cannot fork'};
	};
	$querying={qkey=>$qkey,retrieval=>$retrieval,pid=>$child||$$,start=>$start};
	if ($child)
	{
		$cache->set("qkey-$qkey",$querying,0);
		$cache->set("retr-$retrieval",{qkey=>$qkey,retrieval=>$retrieval,query=>$query,params=>$params,user=>$cc->user->{souid},action=>$cc->req->{action}},0);
		while ((time-$start)<5 and (my $c=waitpid($child,WNOHANG))>=0) {usleep(100)};
		return {retrieval=>$retrieval};
	};
	
	my $sdbh=$self->sconnect() or return undef;
	$querying->{pg_pid}=$sdbh->{pg_pid};
	$cache->set("qkey-$qkey",$querying,0);

	my $result={qkey=>$qkey};
	my $sth;
	eval {$sth=$sdbh->prepare($query);};
	if ($sth and $sth->execute(@values))
	{
		my @rows;
		while (my $r=$sth->fetchrow_hashref)
		{
			push @rows, {map {encode("utf8",$_) => $r->{$_}} keys %$r};;
		}; 

		$result={qkey=>$qkey,rows=>\@rows,header=>[map(encode("utf8",$_),@{$sth->{NAME}})]};
	};
	$result={%$result,(query=>$query,values=>[@values],duration=>time-$start,retrieved=>time,retrievedf=>time2str('%Y-%m-%d %H:%M:%S',time),retrieval=>$retrieval,error=>$@?$@:$sdbh->errstr,params=>$params,user=>$cc->user->{souid},action=>$cc->req->{action})};
	$cache->remove("qkey-$qkey");
	if (scalar(@{$result->{rows}//[]})*scalar(@{$result->{header}//[]})>30 or !$cache->set("retr-$retrieval",$result))
	{
		$cc->cache("big")->set("rows-$retrieval",$result->{rows});
		delete $result->{rows};
		$cache->set("retr-$retrieval",$result);
	};
	$sdbh->disconnect();

	exit 0; # PSGI
	#CORE::exit(0); # Apache mod_perl
	#return {retrieval=>$retrieval}; # fast_cgi

}

sub result
{
	my ($self,$retrieval,$onlyheader)=@_;
	my $cache=$cc->cache;
	my $result=$cache->get("retr-$retrieval");
	return {error=>'Неправильный или устаревший идентификатор извлечения'} unless $result;
	$result->{querying}=$cache->get("qkey-$result->{qkey}");
	$result->{querying}->{duration}=time-$result->{querying}->{start} if defined $result->{querying};
	$cache->set("retr-$retrieval",$result,defined $result->{querying}?0:undef);
	unless ($result->{rows} or $onlyheader)
	{
		$result->{rows}=$cc->cache("big")->get("rows-$retrieval");
		$cc->cache("big")->set("rows-$retrieval",$result->{rows});
	};
	return $result;
}

sub cancel_query
{
	my ($self,$r)=@_;
	$r=result($self,$r) if ref \$r eq 'SCALAR';
	return unless $r->{querying};

	my $sdbh=$self->sconnect() or return undef;
	$sdbh->do("select cancel_query(?)",undef,$r->{querying}->{pg_pid});
	$sdbh->disconnect;

}

sub log_packet
{
	my $self=shift;
	my $data=shift;
	my $last_event=shift;

	foreach (values %$data) {undef $_ unless $_;};
	my $query=sprintf "insert into log_old (event,who,note,file,message_id,refto,refid) values (%s,%s,%s,%s,%s,'packets',%s)",$dbh->quote($data->{event}),$dbh->quote($data->{who}),$dbh->quote($data->{note}),$dbh->quote($data->{file}),$dbh->quote($data->{message_id}),$dbh->quote($data->{packet_id});
		
	my $rv=$dbh->do($query);
	packetproc::log(sprintf("log_old insert error\n%s\n%s",$query,$dbh->errstr)) if $rv!=1;

	return $rv;
}

sub set_packet_path
{
	my $self=shift;
	my $packet_id=shift;
	my $path=shift;


	my $rv=$dbh->do("update packets set path=? where id=?",undef,$path,$packet_id);
	packetproc::log(sprintf("packet update error\n%s",$dbh->errstr)) unless $rv;

	return $rv;
}

sub get_who_email
{
	my ($self,$who)=@_;
	my $r=$dbh->selectrow_hashref("select v1 as email from data where r='email сущности' and substring(v2,E'^\\\\S+')=?",undef,$who);
	return $r->{email} if $r;
}

1;
