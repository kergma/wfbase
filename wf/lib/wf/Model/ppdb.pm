package wf::Model::ppdb;

use strict;
use warnings;
no warnings 'uninitialized';
use parent 'Catalyst::Model';
use DBI;
use Date::Format;
use Encode;
use Digest::MD5;
use POSIX ":sys_wait_h";
use Time::HiRes 'usleep';
use packetproc;
use db;
use util;
no warnings 'uninitialized';



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

my $cc;

sub ACCEPT_CONTEXT
{
	my ($self,$c,@args)=@_;

	$cc=$c;
	return $self;
}

sub sconnect
{
	my $sdbh=DBI->connect("dbi:Pg:dbname=worker;host=ppdb", 'stat', undef, {AutoCommit => 1,pg_enable_utf8=>0});
	$sdbh->do("create function pg_temp.wfuser() returns uuid as \$\$select '${\($cc->user->{souid})}'::uuid\$\$ language sql");
	return $sdbh;
}

sub array_ref
{
	my ($self, $q, @values)=@_;

	my $opts={row=>'auto'};
	if (ref $q eq 'HASH')
	{
		%$opts=(%$opts,%$q);
		$q=shift @values;
	};

	my $sth=db::prepare($q);
	my $r=$sth->execute(@values);
	return undef unless $r;
	my $row=$opts->{row};
	$opts->{row}='hashref' if ($opts->{row}//'auto') eq 'auto' and scalar(@{$sth->{NAME}})>1;
	$opts->{row}='col' if ($opts->{row}//'auto') eq 'auto' and scalar(@{$sth->{NAME}})==1;
	my @result=();
	while(my $r=($opts->{row} eq 'hashref'?$sth->fetchrow_hashref:$sth->fetchrow_arrayref))
	{
		push @result,$r->[0] if $opts->{row} eq 'col';
		push @result,$r if $opts->{row} eq 'hashref';
		push @result,[@$r] if $opts->{row} eq 'arrayref';
		push @result,[@$r] if $opts->{row} eq 'enhash';
	}
	if ($opts->{row} eq 'enhash')
	{
		my $r={};
		$r->{$_->[0]}=$_ foreach @result;
		return $r;
	};
	return \@result;
}

sub cached_array_ref
{
	my ($self, $q, @values)=@_;
	my $opts={};
	if (ref $q eq 'HASH')
	{
		$opts=$q;
		$q=shift @values;
	};

	my $md5=Digest::MD5->new;
	$md5->add($opts->{cache_key}) if defined $opts->{cache_key};
	$md5->add($q);
	$md5->add($_) foreach @values;
	my $qkey=$md5->hexdigest();

	my $result=$cc->cache->get("aref-".$qkey);
	undef $result if $opts->{update};
	unless ($result)
	{
		$result=array_ref(@_);
		$cc->cache->set("aref-".$qkey,$result) if defined $result;
	};
	return $result;
}


sub read_row
{
	my ($self, $table, $id)=@_;
	defined $cc or return undef;
	$table =~ /^[[:alnum:]_]+$/ or return undef;
	return {error=>'Действие не разрешено'} unless db::selectrow_hashref("select * from data where v1=? and r='разрешение на чтение таблицы для роли' and v2 in (".join(', ',map ('?',@{$cc->user->{roles}})).")",undef,$table,@{$cc->user->{roles}});
	$id or undef $id;
	my $sth=db::prepare("select * from ".db::quote_identifier($table)." where id=?");
	$sth->execute($id);
	my $r=$sth->fetchrow_hashref();
	my %data=(header=>$sth->{NAME},data=>$r);
	$data{error}='Строка не найдена' unless $r;
	return \%data;

}

sub update_row
{
	my ($self, $table, $id, $set)=@_;
	defined $cc or return undef;
	$table =~ /^[[:alnum:]_]+$/ or return undef;
	return {error=>'Действие не разрешено'} unless db::selectrow_hashref("select * from data where v1=? and r='разрешение на ввод данных в таблицу для роли' and v2 in (".join(', ',map ('?',@{$cc->user->{roles}})).")",undef,$table,@{$cc->user->{roles}});
	return {error=>'Некорректный  идентификатор записи'} unless $id+0;
	my $rv=db::do("update ".db::quote_identifier($table)." set ".join(', ',map ("$_=?",keys %$set))." where id=?",undef,map($set->{$_},keys %$set),$id);
	return {rv=>$rv, error=>"Ошибка при сохранении изменений: $DBI::errstr"} unless $rv==1;
	return {rv=>$rv};

}

sub insert_row
{
	my ($self, $table, $pairs)=@_;
	defined $cc or return undef;
	$table =~ /^[[:alnum:]_]+$/ or return undef;
	return {error=>'Действие не разрешено'} unless db::selectrow_hashref("select * from data where v1=? and r='разрешение на ввод данных в таблицу для роли' and v2 in (".join(', ',map ('?',@{$cc->user->{roles}})).")",undef,$table,@{$cc->user->{roles}});
	
	my $r=db::selectrow_hashref("select nextval('$table"."_id_seq') as id");
	$r=db::selectrow_hashref("select uuid_generate_v1o() as id") unless $r;
	return {error=>'Ошибка при определении идентификатора новой записи'} unless $r;

	my $rv=db::do("insert into ".db::quote_identifier($table)." (id, ".join(', ', keys %$pairs).") values (?, ".join(', ',map ("?",values %$pairs)).")",undef,$r->{id},values %$pairs);

	return {error=>"Ошибка при добавлении записи: $DBI::errstr"} unless $rv==1;
	
	return {rv=>$rv,id=>$r->{id}};

}

sub delete_row
{
	my ($self, $table, $id)=@_;
	defined $cc or return undef;
	$table =~ /^[[:alnum:]_]+$/ or return undef;
	return {error=>'Действие не разрешено'} unless db::selectrow_hashref("select * from data where v1=? and r='разрешение на удаление данных из таблицы для роли' and v2 in (".join(', ',map ('?',@{$cc->user->{roles}})).")",undef,$table,@{$cc->user->{roles}});

	return {error=>'Некорректный  идентификатор записи'} unless $id+0;

	my $rv=db::do("delete from ".db::quote_identifier($table)." where id=?",undef,$id);

	return {rv=>$rv,error=>"Ошибка при удалении записи: $DBI::errstr"} unless $rv==1;
	
	return {rv=>$rv};
}


sub get_otd_list
{
	my ($self)=@_;
	defined $cc or return undef;
	return cached_array_ref($self,"select otd from orders where otd ~ ? group by otd order by otd",$cc->user->{otd});
}
sub get_org_list
{
	my ($self,$souid)=@_;
	return options_list($self,{cache_key=>$souid},qq[
select c.container as org, (select shortest(v1) from data where r='наименование структурного подразделения' and v2=c.container ) as org_name
from containers_of(?) c
join data o on o.r='принадлежит структурному подразделению' and o.v1=c.container and o.v2='61b45bd4-d36a-44d0-bcb0-0949a37c27b7' /* Организации */
order by 2
],$souid);
}
sub get_sp_list
{
	my ($self,$souid)=@_;
	return options_list($self,{cache_key=>$souid},qq/select distinct item,sp_name from items where souid=? and sp_name is not null order by 2/,$souid);
}
sub get_direct_sp_list
{
	my ($self,$souid)=@_;
	return options_list($self,{cache_key=>$souid},qq/
select distinct name_sp.v2 as item, name_sp.v1 as name
from data so_sp
join data name_sp on name_sp.r='наименование структурного подразделения' and name_sp.v2=so_sp.v2
where
so_sp.v1=? and so_sp.r='принадлежит структурному подразделению'
order by 2/,$souid);
}
sub get_outersp_list
{
	my ($self)=@_;
	defined $cc or return undef;
	my $r=cached_array_ref($self,qq"
select v2 as sp, shortest(v1) as spname, 1 as ord from data d where r='наименование структурного подразделения' and v2 in ('a9b7079b-26de-49e3-8d16-9e141d644faf','d86e0ad4-4824-430b-9790-5e78e3a87cae') group by v2
union
select d.v2 as sp, shortest(d.v1) as spname, 2 as ord from (
select v2,items_of(v2) from data where r='принадлежит структурному подразделению' and v2='7265a431-4510-4b19-bb56-0c1c31123283' 
) s 
join data d on d.r='наименование структурного подразделения' and d.v2 in (s.v2,(s.items_of).item)
group by d.v2
order by ord,2
");
	$_={$_->{sp}=>$_->{spname}} foreach @$r;
	return $r;
}

sub options_list
{
	my ($self, $q, @values)=@_;
	my $opts={row=>'arrayref'};
	if (ref $q eq 'HASH')
	{
		%$opts=(%$q,%$opts);
		$q=shift @values;
	};
	my $r=cached_array_ref($self,$opts,$q,@values);
	$_=scalar(@$_)==1?$_->[0]:{$_->[0]=>$_->[1]} foreach @$r;
	return $r;

}

sub get_cd_list
{
	my ($self)=@_;
	return cached_array_ref($self,"select cadastral_district from objects where cadastral_district is not null group by cadastral_district order by cadastral_district");
}

sub get_objsource_list
{
	my ($self)=@_;
	return cached_array_ref($self,"select source from objects where source is not null group by source order by source");
}

sub get_rc_list
{
	my ($self)=@_;
	return cached_array_ref($self,"select reg_code from packets where reg_code is not null group by reg_code order by reg_code");
}
sub get_pt_list
{
	my ($self)=@_;
	return cached_array_ref($self,"select type from packets where type is not null group by type order by type");
}

sub get_field_list
{
	my ($self,$table)=@_;
	my $sth=db::prepare("select * from $table where false");
	$sth->execute();
	$sth->fetchrow_hashref();
	$sth->finish;
	return $sth->{NAME};
}

sub get_path_list
{
	my ($self)=@_;
	return cached_array_ref($self,"select path from packets where path is not null group by path order by path");
}

sub get_event_list
{
	my ($self,$refto)=@_;
	defined $cc or return undef;
	my $event=db::selectval_scalar("select uuid_generate_v1o(now()-6*interval '1 month')");

	my $reftow="";
	$refto and $reftow="and refto=".db::quote($refto);
	return cached_array_ref($self,"select event from log where event is not null $reftow and id>? group by event order by event",$event);
}

sub get_who_list
{
	my ($self)=@_;
	defined $cc or return undef;
	return cached_array_ref($self,"select (select (earliest(d.*)).v1 from sdata d where r='ФИО сотрудника' and v2::uuid=l.who) as who from log l where who is not null group by who order by who");
}

sub get_coworkers_list
{
	my ($self,$souid)=@_;
	defined $cc or return undef;
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
	return cached_array_ref($self,"select distinct refto from log where refto is not null order by refto");
}

sub get_reqproc_splist
{
	my ($self,$souid)=@_;
	return options_list($self,{cache_key=>$souid},qq/
select d.v1 as spid, def.v1 as spdef
from
(select * from context_of('21c02bf5-9968-4eb8-9f27-ebd4d60acc8c',?)) c
join data d on d.v2=c.item and d.r='используется в структурном подразделении'
join data def on def.v2=d.v1 and def.r like 'наименование%'
order by 2
/,$souid);
};


sub authinfo_password
{
	my ($self,$authinfo)=@_;
	my $r=db::selectrow_hashref("select * from data where v2=? and r like 'пароль%'",undef,$authinfo->{username});
	$r=db::selectrow_hashref("select '***' as v1 from data where v2=? and r = 'ФИО сотрудника'",undef,$authinfo->{uid}) if $authinfo->{uid};
	undef $r if $authinfo->{uid} and $authinfo->{username};
	$r=db::selectrow_hashref("select '***' as v1 from data where v1=? and r = 'логин сотрудника'",undef,$authinfo->{username}) if $authinfo->{uid} eq 'a87df57e-8b4e-4825-a562-149e4bddb49c';
	$r or return undef;
	return $r->{v1};
}

sub authinfo_data
{
	my ($self,$authinfo)=@_;
	my %data=%$authinfo;

	my $r=db::selectrow_hashref(qq/
select lo_so.v2 as souid,lo_so.v1 as username,
(select v1 from data where r like 'пароль %' and v2=lo_so.v1) as password,
(select (latest(data.*)).v1 from data where r='ФИО сотрудника' and v2=lo_so.v2) as full_name,
(select comma(distinct lower(v1)) from data where r='свойства сотрудника' and v2 in (select container from containers_of(lo_so.v2) union select lo_so.v2)) as props,
(select comma(distinct lower(v1)) from data where r like 'описание %' and v2=lo_so.v2) as desc
from data lo_so
where lo_so.r='логин сотрудника' and (lo_so.v1=? or lo_so.v2=?)
/
,undef,$authinfo->{username},$authinfo->{uid});
	$r->{password}='***' if $authinfo->{uid};

	%data=(%data,%$r) if $r;
	push @{$data{roles}}, split / +/,$data{description};
	push @{$data{roles}}, split /,\s*/,$data{props};

	push @{$data{roles}}, $authinfo->{username};
	push @{$data{roles}}, 'отправляющий' if grep {/наблюдающий|оператор/} @{$data{roles}};

	push @{$data{roles}}, 'запрашивающий' if db::selectval_scalar("select 1 from context_of('21c02bf5-9968-4eb8-9f27-ebd4d60acc8c',?)",undef,$data{souid});
	push @{$data{roles}}, 'подписант' if scalar(@{get_signers($self,$data{souid})});

	$data{otd}='';

	my $roles="'norole'";
	$roles="'".join("', '",@{$data{roles}})."'" if $data{roles};
	my $otds=db::selectcol_arrayref(qq/
select v1 from data where r='отделение сотрудника' and v2=?
union
select otd from orders group by otd having otd = ? 
union
select v1 from data where r='отделение сущности' and v2=?
/,undef, $data{souid},$data{username},$data{full_name});
	$otds and @$otds and $data{otd}=join("|",@$otds);

	my $sp=db::selectall_arrayref(qq/
select so_sp.v2 as uid,comma(name_sp.v1) as name
from data so_sp
join data name_sp on name_sp.v2=so_sp.v2 and name_sp.r='наименование структурного подразделения'
where so_sp.r='принадлежит структурному подразделению' and so_sp.v1=?
group by so_sp.v2
/,{Slice=>{}}, $data{souid});
	$data{sp}=[map {$_->{uid}} @$sp];
	$data{spname}=[map {$_->{name}} @$sp];

	db::do("create or replace function pg_temp.wfuser() returns uuid as \$\$select '$data{souid}'::uuid\$\$ language sql");

	return \%data;
}

sub souid
{
	my ($self, $who)=@_;
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
	close_order($self,$data{refid}) if $data{event} eq 'закрыт' and $data{refto} eq 'orders';
	close_order($self,$data{refid},1) if $data{event} eq 'возобновлён' and $data{refto} eq 'orders';
	return $event_id if $rv;
}

sub close_order
{
	my ($self,$id,$reopen)=@_;
	my $closed=$reopen?'null':'current_timestamp';
	my $rv=db::do("update log set closed=$closed where refid in (select ?::uuid union select id from packets where order_id=?)",undef,$id,$id);
	return $rv;
}

sub read_order_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;

	my $r=db::selectrow_hashref(qq{
select o.*,
(select event from log where refto='orders' and refid=o.id order by id desc limit 1) as ostatus,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='orders' and refid=o.id order by id desc limit 1) as osdate,
(select event from log where refto='packets' and refid in (select id from packets where order_id=o.id) order by id desc limit 1) as pstatus,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid in (select id from packets where order_id=o.id) order by id desc limit 1) as psdate
from orders o where id=?
and (o.sp::text in (select item from items where souid=? and sp_name is not null)
or o.id in (select refid from log where refto='orders' and (who::text in (select item from items where souid=? and sp_name is not null)) or who=?))
},undef,$id,$cc->user->{souid},$cc->user->{souid},$cc->user->{souid});
	return {order=>{id=>$id}} unless $r;
	my %data;
	$data{order}=$r;
	$r=db::selectrow_hashref("select * from objects where id=?",undef,$r->{object_id});
	$data{object}=$r;

	my $sth=db::prepare("select * from packets where order_id=? order by id desc");
	$sth->execute($id);
	my %packets=(rows=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$packets{rows}},$r;
	};
	$sth->finish;
	$data{packets}=\%packets;

	$sth=db::prepare(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,coalesce((select shortest(v1) from sdata where r in ('ФИО сотрудника','наименование структурного подразделения') and v2::uuid=l.who),who::text) as who,refto,refid,cause
from log l
where (refto='orders' and refid=?)
or (refto='packets' and refid in (select id from packets where order_id=?))
or (refto='objects' and refid=(select object_id from orders where id=?))
order by id desc/);
	$sth->execute($id,$id,$id);
	my %events=(rows=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$events{rows}},$r;
	};
	$sth->finish;
	$data{events}=\%events;
	return \%data;
}

sub read_object_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;

	my $r=db::selectrow_hashref("select * from objects j where id=? and (exists (select 1 from orders where object_id=j.id and sp::text in (select item from items where souid=? and sp_name is not null)) or not exists (select 1 from orders where object_id=j.id))",undef,$id,$cc->user->{souid});
	return undef unless $r;

	my %data;
	$data{object}=$r;

	my %orders;
	my $sth=db::prepare(qq{
select o.*,
(select to_char(date,'yyyy-mm-dd') from log where event='принят' and refto='orders' and refid=o.id order by id desc limit 1) as accepted,
(select to_char(date,'yyyy-mm-dd') from log where event='оплачен' and refto='orders' and refid=o.id order by id desc limit 1) as paid
from orders o where object_id=? order by id desc
});
	$sth->execute($id);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$orders{rows}},$r;
	};
	$sth->finish;
	$data{orders}=\%orders;

	my %packets=(rows=>[]);
	$sth=db::prepare("select * from packets where order_id in (select id from orders where object_id=?) order by id desc");
	$sth->execute($id);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$packets{rows}},$r;
	};
	$sth->finish;
	$data{packets}=\%packets;

	$sth=db::prepare(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,coalesce((select shortest(v1) from sdata where r in ('ФИО сотрудника','наименование структурного подразделения') and v2::uuid=l.who),who::text) as who, who as whoid, refto,refid,cause
from log l
where (refto='orders' and refid in (select id from orders where object_id=?))
or (refto='packets' and refid in (select id from packets where order_id in (select id from orders where object_id=?)))
or (refto='objects' and refid=?)
order by id desc/);
	$sth->execute($id,$id,$id);
	my %events=(rows=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$events{rows}},$r;
	};
	$sth->finish;
	$data{events}=\%events;
	return \%data;
}

sub read_packet_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;

	my %data;
	my $packet=db::selectrow_hashref(qq{
select p.*,
(select coalesce(d.v1,who::text) from log l left join data d on d.r='ФИО сотрудника' and v2::uuid=l.who where refto='packets' and refid=p.id order by l.id desc limit 1) as who,
(select event || ' '|| to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id order by id limit 1) as accepted,
(select event from log where refto='packets' and refid=p.id order by id desc limit 1) as status,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id order by id desc limit 1) as status_date
from packets p where id=?}
,undef,$id);
	return undef unless $packet;
	$data{packet}=$packet;

	my $order=db::selectrow_hashref("select * from orders where id=?",undef,$packet->{order_id});
	$data{order}=$order;

	my $object=db::selectrow_hashref("select * from objects where id=?",undef,$order->{object_id});
	$data{object}=$object;

	my $sth=db::prepare(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,coalesce((select shortest(v1) from sdata where r in ('ФИО сотрудника','наименование структурного подразделения') and v2::uuid=l.who),who::text) as who, who as whoid, refto,refid,cause
from log l
where (refto='packets' and refid = ?)
or (refto='orders' and refid=?)
or (refto='packets' and refid in (select id from packets where order_id = ?))
or (refto='objects' and refid=?)
order by id desc/);
	$sth->execute($packet->{id},$order->{id},$order->{id},$object->{id});
	my %events=(rows=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$events{rows}},$r;
	};
	$sth->finish;
	$data{events}=\%events;
	return \%data;
}

sub read_event_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;

	my %data;
	my $event=db::selectrow_hashref(qq{
select id,date,event,coalesce((select v1 from sdata where r='ФИО сотрудника' and v2::uuid=l.who limit 1),who::text) as who,note,refto,refid,cause from log l where id=?}
,undef,$id);
	return undef unless $event;
	$data{event}=$event;

	my $order=db::selectrow_hashref("select * from orders where id=(select coalesce((select refid where refto='orders'),(select order_id from packets where id=refid and refto='packets')) from log where id=?)",undef,$event->{id});
	$data{order}=$order;


	my $packet=db::selectrow_hashref("select * from packets where id=(select refid from log where refto='packets' and id=?)",undef,$event->{id});
	$data{packet}=$packet;

	my $object=db::selectrow_hashref("select * from objects where id=(select coalesce((select l.refid where l.refto='objects'),(select object_id from orders where id=l.refid and l.refto='orders'),(select o.object_id from orders o join packets p on p.order_id=o.id where p.id=l.refid and l.refto='packets')) from log l where id=?)",undef,$id);
	$data{object}=$object;

	my $orders=$data{orders}->{rows}=db::selectall_arrayref(qq{select * from orders o where id in (select refid from log where refto='orders' and id=?) or object_id in (select refid from log where refto='objects' and id=?) order by id desc},{Slice=>{}},$id,$id);
	my $packets=$data{packets}->{rows}=db::selectall_arrayref("select * from packets where order_id in (select refid from log where refto='orders' and id=? union select id from orders where object_id=(select refid from log where refto='objects' and id=?)) order by id desc",{Slice=>{}},$id,$id);

	push @$orders,{id=>undef};
	push @$packets,{id=>undef};

	my $sth=db::prepare(sprintf(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,coalesce((select shortest(v1) from sdata where r in ('ФИО сотрудника','наименование структурного подразделения') and v2::uuid=l.who),who::text) as who,refto,refid, cause
from log l
where id=?
or (refto=? and refid=?)
or (refto='orders' and refid in (%s))
or (refto='packets' and refid in (%s))
or (refto='objects' and refid=?)
order by id desc/,join(',',map {'?'} @$orders),join(',',map {'?'} @$packets)));
	$sth->execute($event->{id},$event->{refto},$event->{refid},map ($_->{id},@$orders),map ($_->{id}, @$packets),$object->{id});
	my %events=(rows=>[]);
	while (my $r=$sth->fetchrow_hashref())
	{
		push @{$events{rows}},$r;
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
	$result{completedf}=time2str('%Y-%m-%d %H:%M:%S',time);

	return \%result;
}

sub search_objects
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;

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
	my $start=time;

	my %where;
	$where{qq/(o.sp::text in (select item from items where souid=? and sp_name is not null)
or o.id in (select refid from log where refto='orders' and (who::text in (select item from items where souid=? and sp_name is not null)) or who=?))
/}=[$cc->user->{souid},$cc->user->{souid},$cc->user->{souid}];

	$where{"o.id=?"}=$filter->{order_id} if $filter->{order_id};
	$where{"o.sp=?"}=$filter->{sp} if $filter->{sp};
	$where{"o.year=?"}=$filter->{year} if $filter->{year};
	$where{"o.ordno=?"}=$filter->{ordspec} if $filter->{ordspec};
	if ($filter->{ordspec} =~ /^(\d{4})(\d{2})(\d{6})\d{6}$/)
	{
		my ($spcode,$year,$ordno6)=($1,$2+2000,$3);
		my $spcodes=cached_array_ref($self,{row=>'enhash'},"select distinct v1 as code, v2 as sp from data where r='код структурного подразделения'");
		$where{"/**/o.sp=?"}=$spcodes->{$spcode}->[1];
		$where{"/**/o.year=?"}=$year;
		$where{"o.ordno=?"}="00$ordno6";
	};
	$where{"o.objno=?"}=$filter->{objno} if $filter->{objno};
	$where{"exists (select 1 from log l where id>=o.id and refto='orders' and refid=o.id and who in (select v2::uuid from sdata where r in ('ФИО сотрудника','наименование структурного подразделения') and lower(v1)~lower(?)))"}=$filter->{who} if $filter->{who};
	$where{"exists (select 1 from log l where refto='orders' and refid=o.id and not exists (select 1 from log where refto=l.refto and refid=l.refid and id>l.id) and event=?)"}=$filter->{status} if $filter->{status};
	$where{"exists (select 1 from objects where id=o.object_id and lower(address) ~ lower(?))"}=$filter->{address} if $filter->{address};
	
	$where{"not exists (select 1 from packets where order_id=o.id)"}='novalue' if $filter->{ready} eq 'нет данных';
	$where{"(select event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='данные' order by l.id desc limit 1)='загружен'"}='novalue' if $filter->{ready} eq 'распределение';
	$where{"(select event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='данные' order by l.id desc limit 1)='назначен'"}='novalue' if $filter->{ready} eq 'проверка';
	$where{"exists (select 1 from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='данные' and l.event='отклонён' and lower(coalesce(l.note,'замечания'))~'замечания' and not exists (select 1 from packets where type=p.type and id>l.id and order_id=p.order_id))"}='novalue' if $filter->{ready} eq 'замечания';
	$where{"(select event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='данные' order by l.id desc limit 1)='принят' and coalesce((select l.event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type in ('техплан','межевой') order by l.id desc limit 1),'')<>'принят'"}='novalue' if $filter->{ready} eq 'обработка';
	$where{"(select l.event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='техплан' order by l.id desc limit 1)='принят'"}='novalue' if $filter->{ready} eq 'техплан';
	$where{"(select l.event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='межевой' order by l.id desc limit 1)='принят'"}='novalue' if $filter->{ready} eq 'межевой';

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=query($self,sprintf(qq\
select 
o.id as order_id,
(select shortest(v1) from sdata where r='наименование структурного подразделения' and v2=o.sp::text) as spname,
year,
(select v1 from sdata where r='код структурного подразделения' and v2=o.sp::text order by id limit 1)||year-2000||substr(o.ordno,3,6)||'000000' as ordno,
(select event from log where refto='orders' and refid=o.id order by id desc limit 1) as status,
(case when not exists (select 1 from packets where order_id=o.id) then 'нет данных' when (select event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='данные' order by l.id desc limit 1)='загружен' then 'распределение' when (select event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='данные' order by l.id desc limit 1)='назначен' then 'проверка' when exists (select 1 from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='данные' and l.event='отклонён' and lower(coalesce(l.note,'замечания'))~'замечания' and not exists (select 1 from packets where type=p.type and id>l.id and order_id=p.order_id)) then 'замечания' when (select event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='данные' order by l.id desc limit 1)='принят' and coalesce((select l.event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type in ('техплан','межевой') order by l.id desc limit 1),'')<>'принят' then 'обработка' when (select l.event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='техплан' order by l.id desc limit 1)='принят' then 'техплан' when (select l.event from packets p join log l on l.refto='packets' and l.refid=p.id where p.order_id=o.id and p.type='межевой' order by l.id desc limit 1)='принят' then 'межевой' else null end) as ready,
(select coalesce((select (latest(d.*)).v1 from sdata d where r='ФИО сотрудника' and v2=l.who::text),(select shortest(v1) from sdata where r='наименование структурного подразделения' and v2=l.who::text),who::text) from log l join packets p on l.refid in (p.id, o.id) where p.order_id=o.id and l.who is not null order by l.id desc limit 1) as who,
(select to_char(date,'yyyy-mm-dd hh24:mi:ss') from log l join packets p on l.refid in (p.id, o.id) where p.order_id=o.id order by l.id desc limit 1) as touched,
(select address from objects where id=o.object_id) as address
from (
select *
from orders o
where
%s
order by o.id desc %s
) o
\,join(" and ",keys %where),$limit),$filter,map(@{arrayref $_},grep {$_ ne 'novalue'} values %where));
	
	return $result;

}

sub search_packets
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;

	my %where;

	$where{qq/(o.sp::text in (select item from items where souid=? and sp_name is not null)
or o.id in (select refid from log where  refto='orders' and who::text in (select item from items where souid=? and (sp_name is not null or item=souid)))
or p.id in (select refid from log where refto='packets' and who::text in (select item from items where souid=? and (sp_name is not null or item=souid)))
)
/}=[$cc->user->{souid},$cc->user->{souid},$cc->user->{souid}];

	$where{"p.id = ?"}=$filter->{packet_id} if $filter->{packet_id};
	$where{"o.id = ?"}=$filter->{ordspec} if $filter->{ordspec};
	$where{"o.sp = ?"}=$filter->{sp} if $filter->{sp};
	$where{qq\(o.id in (select refid from log where refto='orders' and  who::text in (select v2 from sdata where r in ('ФИО сотрудника','наименование структурного подразделения') and lower(v1)~lower(?)))
or p.id in (select refid from log where refto='packets' and who::text in (select v2 from sdata where r in ('ФИО сотрудника','наименование структурного подразделения') and lower(v1)~lower(?))))
\}=[$filter->{who},$filter->{who}] if $filter->{who};
	$where{"p.type = ?"}=$filter->{type} if $filter->{type};
	$where{"exists (select 1 from files fi where fi.id=p.container and lower(fi.name)~lower(?))"}=$filter->{file} if $filter->{file};
	$where{"exists (select 1 from log l where refto='packets' and refid=p.id and event=? and not exists (select 1 from log where refto=l.refto and refid=l.refid and id>l.id))"}=$filter->{status} if $filter->{status};

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=query($self,sprintf(qq{
select
s.*, event as status, to_char(date,'yyyy-mm-dd hh24:mi') status_date, l.id as status_event,
(select name from files where id=s.container) as container_name,
(select shortest(v1) from sdata where r='наименование структурного подразделения' and v2=s.sp::text) as spname
from (
select p.id as packet_id, o.sp, type, container
from packets p
left join orders o on o.id=p.order_id
where 
%s
order by p.id desc %s
) s
left join log l on l.refto='packets' and l.refid=s.packet_id and not exists (select 1 from log where refto='packets' and refid=l.refid and id>l.id)
;
--select * from pg_temp.vi;
},join(" and ",keys %where),$limit),$filter,map(@{arrayref $_},grep {$_ ne 'novalue'} values %where));
	
	return $result;

}

sub search_events
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;

	my @where;
	push @where, "o.otd ~ ".db::quote($cc->user->{otd}) if $cc->user->{otd};
	push @where, "o.otd = ".db::quote($filter->{otd}) if $filter->{otd};
	push @where, "l.id = ".db::quote($filter->{event_id}) if $filter->{event_id};
	push @where, "l.date > ".db::quote($filter->{from}) if $filter->{from};
	push @where, "l.date <= ".db::quote($filter->{to}) if $filter->{to};
	push @where, "l.event = ".db::quote($filter->{event}) if $filter->{event};
	push @where, "l.who  in (select v2::uuid from sdata where r='ФИО сотрудника' and v1=".db::quote($filter->{who}).")" if $filter->{who};
	push @where, sprintf "lower(l.note) ~ lower(%s)", db::quote($filter->{note}) if $filter->{note};
	push @where, "l.refto = ".db::quote($filter->{refto}) if $filter->{refto};
	push @where, "l.refid = ".db::quote($filter->{refid}) if $filter->{refid};
	push @where, sprintf "lower(obj.address) ~ lower(%s)", db::quote($filter->{address}) if $filter->{address};
	push @where, sprintf "lower(obj.invent_number) ~ lower(%s)", db::quote($filter->{invent_number}) if $filter->{invent_number};
	scalar @where or push @where,'true';

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=query($self,qq{
select
l.id, to_char(date,'yyyy-mm-dd hh24:mi') as date,event,coalesce((select v1 from sdata where r='ФИО сотрудника' and v2::uuid=l.who limit 1),who::text) as who,note,refto,refid,o.otd,obj.invent_number,obj.address,obj.name,l.cause
from log l
left join orders o on o.id>present() and o.id=coalesce((select l.refid where l.refto='orders'), (select order_id from packets where id=l.refid and l.refto='packets'),(select '00000000000000000000000000000000'::uuid where l.refto='objects'))
left join objects obj on obj.id=o.object_id or (obj.id=l.refid and l.refto='objects')
where l.id>present() and l.id in
(
select l.id
from log l
left join orders o on o.id>present() and o.id=coalesce((select l.refid where l.refto='orders'), (select order_id from packets where id=l.refid and l.refto='packets'),(select '00000000000000000000000000000000'::uuid where l.refto='objects'))
left join objects obj on obj.id=o.object_id or (obj.id=l.refid and l.refto='objects')
where l.id>present() and l.refid>present() and
}.join (" and ",@where).qq{
order by l.id desc $limit
)
order by l.id desc
},$filter);
	
	return $result;

}

sub read_run_status
{
	my ($self,$id)=@_;
	defined $cc or return undef;

	my %data;
	#$data{running}{rows}=read_table($self,"select * from run where completed is null and started is not null order by id desc");
	$data{running}=read_table($self,qq/
select r.id, r.id as run_id, r.task_id, t.value as task_name, to_char(r.started,'yyyy-mm-dd hh24:mi:ss') as started, now()-started as last
from run r 
join syslog t on t.id=r.task_id and t.key_id='1e110f2f-aea6-5921-b330-33e52e05cc17' --задача
where completed is null and started is not null
order by r.id
/
);
	$data{running}{rows}=[] unless defined $data{running}{rows};

	$data{scheduled}=read_table($self,qq/
select r.id, r.id as run_id, r.task_id, t.value as task_name, to_char(r.at,'yyyy-mm-dd hh24:mi:ss') as at, at-now() as in
from run r 
join syslog t on t.id=r.task_id and t.key_id='1e110f2f-aea6-5921-b330-33e52e05cc17' --задача
where completed is null and started is null
order by r.id desc
/
);
	$data{scheduled}{rows}=[] unless defined $data{scheduled}{rows};

	$data{completed}=read_table($self,qq/
select r.id, r.id as run_id, r.task_id, t.value as task_name, to_char(r.started,'yyyy-mm-dd hh24:mi:ss') as started, to_char(r.completed,'yyyy-mm-dd hh24:mi:ss') as completed, now()-completed as last
from run r 
join syslog t on t.id=r.task_id and t.key_id='1e110f2f-aea6-5921-b330-33e52e05cc17' --задача
where completed is not null and completed>=date_trunc('day',now())
order by r.id desc
/
);
	$data{completed}{rows}=[] unless defined $data{completed}{rows};
	return \%data;
}

sub query
{
	my $self=shift;
	my $query=shift;
	my $params=shift;
	$params={} unless defined $params;
	$params->{need_db}=0;
	my @values=@_;

	my $cache=$cc->cache;

	return defer($self,sub {
		my $running=pop;
		my $sdbh=$self->sconnect() or return undef;
		$running->{pg_pid}=$sdbh->{pg_pid};
		$cache->set("rkey-$running->{rkey}",$running,0);
		my $d=$cache->get("defr-$running->{deferral}");
		$d->{query}=$query;
		$cache->set("defr-$running->{deferral}",$d,0);

		my $result={};
		my $sth;
		eval {$sth=$sdbh->prepare($query);};
		if ($sth and $sth->execute(@_))
		{
			my @rows;
			while (my $r=$sth->fetchrow_hashref)
			{
				push @rows, {map {encode("utf8",$_) => $r->{$_}} keys %$r};;
			}; 

			$result={ARRAY=>\@rows,header=>[map(encode("utf8",$_),@{$sth->{NAME}})],error=>$@?$@:$sdbh->errstr};
		};
		$result={%$result,(query=>$query,error=>$@?$@:$sdbh->errstr)};
		$sth->finish();
		$sdbh->disconnect();
		return $result;
	},$params,@values);
}

sub cancel_query
{
	my ($self,$r)=@_;
	$r=deferred($self,$r) if ref \$r eq 'SCALAR';
	return unless $r->{running};

	my $sdbh=$self->sconnect() or return undef;
	my $re=$sdbh->selectrow_hashref("select cancel_query(?)",undef,$r->{running}->{pg_pid});
	$re=db::selectrow_hashref("select cancel_query(?)",undef,$r->{running}->{pg_pid}) unless $re;
	$sdbh->disconnect;
	unless ($re)
	{
		kill 9, $r->{running}->{pid};
		$r->{error}='Выполнение запроса прервано';
		$cc->cache->remove("rkey-$r->{rkey}");
		$cc->cache->set("defr-$r->{deferral}",$r);
	};
	return $re;

}

sub defer
{
	my $self=shift;
	my $proc=shift;
	my $params=shift;

	my @values=@_;

	my $cache=$cc->cache;

	my $md5=Digest::MD5->new;
	$md5->add($proc);
	$md5->add($_,$params->{$_}) foreach sort keys %$params;
	$md5->add($_) foreach @values;
	my $rkey=$md5->hexdigest();

	my $running=$cache->get("rkey-$rkey");
	if (defined $running)
	{
		return {deferral=>$running->{deferral}};
	};

	my $deferral=Digest::MD5::md5_hex(rand());
	my $start=time;

	$SIG{CHLD} = 'IGNORE';
	my $child=fork();

	unless (defined $child)
	{
		return {error=>'cannot fork'};
	};
	$running={rkey=>$rkey,deferral=>$deferral,pid=>$child||$$,start=>$start};
	if ($child)
	{
		$cache->set("rkey-$rkey",$running,0);
		$cache->set("defr-$deferral",{rkey=>$rkey,deferral=>$deferral,params=>$params,user=>$cc->user->{souid},action=>$cc->req->{action}},0);
		while ((time-$start)<($params->{defer_threshold}||5) and (my $c=waitpid($child,WNOHANG))>=0) {usleep(100)};
		return {deferral=>$deferral};
	};
	if ($params->{need_db}//1)
	{
		undef $db::dbh;
		db::connect();
		$running->{pg_pid}=db::pg_pid;
	};
	
	$cache->set("rkey-$rkey",$running,0);

	my @r=&$proc(@values,$running);
	my $result=shift @r if scalar(@r)==1;
	$result=\@r unless defined $result;

	$result={'ARRAY'=>$result} if ref $result eq 'ARRAY';
	$result={'SCALAR'=>$result} unless ref $result;
	$result->{rkey}=$rkey;
	
	$result={%$result,(values=>[@values],duration=>time-$start,completed=>time,completedf=>time2str('%Y-%m-%d %H:%M:%S',time),deferral=>$deferral,params=>$params,user=>$cc->user->{souid},action=>$cc->req->{action})};
	$cache->remove("rkey-$rkey");
	if (scalar(@{$result->{ARRAY}//[]})*scalar(@{$result->{header}//[]})>30 or !$cache->set("defr-$deferral",$result))
	{
		$cc->cache("big")->set("array-$deferral",$result->{ARRAY});
		delete $result->{ARRAY};
		$cache->set("defr-$deferral",$result);
	};
	db::disconnect if $params->{need_db}//1;

	exit 0; # PSGI

}


sub deferred
{
	my ($self,$deferral,$onlyheader)=@_;
	my $cache=$cc->cache;
	($deferral,$onlyheader)=(defer(@_)->{deferral},undef) if ref $deferral eq 'CODE';
	my $result=$cache->get("defr-$deferral");

	return {error=>'Неправильный или устаревший отложенный идентификатор',deferral=>$deferral} unless $result;
	$result->{running}=$cache->get("rkey-$result->{rkey}");
	$result->{running}->{duration}=time-$result->{running}->{start} if defined $result->{running};
	unless ($cache->set("defr-$deferral",$result,defined $result->{running}?0:undef))
	{
		$cc->cache("big")->set("array-$deferral",$result->{ARRAY});
		my $a=$result->{ARRAY};
		undef $result->{ARRAY};
		$cache->set("defr-$deferral",$result);
		$result->{ARRAY}=$a;
	};
	unless ($result->{ARRAY} or $onlyheader)
	{
		$result->{ARRAY}=$cc->cache("big")->get("array-$deferral");
		$cc->cache("big")->set("array-$deferral",$result->{ARRAY});
		$result->{big}=1;
	};
	$result->{rows}=$result->{ARRAY} if $result->{query};
	return $result;
}

sub set_packet_path
{
	my $self=shift;
	my $packet_id=shift;
	my $path=shift;


	my $rv=db::do("update packets set path=? where id=?",undef,$path,$packet_id);
	packetproc::log(sprintf("packet update error\n%s",db::errstr)) unless $rv;

	return $rv;
}

sub get_who_email
{
	my ($self,$who)=@_;
	my $r=db::selectrow_hashref("select v1 as email from data where r='email сущности' and substring(v2,E'^\\\\S+')=?",undef,$who);
	return $r->{email} if $r;
}

sub identify_order
{
	my $self=shift;
	my %h=@_>1?@_:(id=>shift);
	my $a=ref $h{id} eq 'HASH'?$h{id}:\%h;

	unless ($a->{objno})
	{
		$a->{error}='Не указан номер объекта в заказе';
		return $a ;
	};
	$a->{ordspec}=~/^(\d{4})(\d\d)(\d{6})0{6}$/ or $a->{error}='Некорректный номер заказа';
	return $a if $a->{error};
	my ($spcode,$year,$ordno6)=($1,substr([localtime()]->[5]+1900,0,2).$2,$3);

	$a->{year}=$year;
	$a->{spdata}=db::selectrow_hashref("select v1 as code, v2 as uid, (select shortest(v1) from data where r='наименование структурного подразделения' and v2=d.v2) as name from data d where r='код структурного подразделения' and v1=?",undef,$spcode);

	$a->{order}=db::selectrow_hashref(qq/
select * from orders o where substr(ordno,3,6)=? and sp=? and year=? and objno=?
and (o.sp::text in (select item from items where souid=? and sp_name is not null)
or o.id in (select refid from log where refto='orders' and (who::text in (select item from items where souid=? and sp_name is not null)) or who=?))
/,undef,$ordno6,$a->{spdata}->{uid},$year,$a->{objno},$cc->user->{souid},$cc->user->{souid},$cc->user->{souid});

	$a->{order_data}=undef;
	$a->{order_data}=read_order_data($self,$a->{order}->{id}) if $a->{order};

	$a->{permission}=1 if $a->{order};
	$a->{permission}=db::selectval_scalar(qq/
select 1 from items i1
join items i2 on i2.container=i1.item
where i1.souid=? and i2.container=?
/,undef,$cc->user->{souid},$a->{spdata}->{uid}) unless $a->{permission};
	$a->{error}="Доступ запрещен к отделению  с кодом $spcode" and return $a unless $a->{permission};
	return $a;

}

sub create_order
{
	my $self=shift;
	my %h=@_>1?@_:(id=>shift);
	my $a=ref $h{id} eq 'HASH'?$h{id}:\%h;
	$a->{order_id}=packetproc::newid();
	$a->{object}=db::selectrow_hashref("select * from objects where id=?",undef,$a->{object_id});
	unless ($a->{object})
	{
		$a->{object}={id=>packetproc::newid(),address=>$a->{address},source=>'wf'};
		my $rv=db::do("insert into objects (id, address, source) values (?,?,?)",undef,$a->{object}->{id},$a->{object}->{address},$a->{object}->{source});
		unless ($rv)
		{
			$a->{error}=db::errstr;
			return $a;
		};
	};
	if ($a->{ordspec} and $a->{ordspec}!~/^\d{4}(\d{2})(\d{6})000000$/)
	{
		$a->{error}='некорректная спецификация заказа 1с-регистратор';
		return $a;
	};
	$a->{year}=$1&&($1+2000);
	$a->{ordno}=$2&&"00$2";
	undef $a->{objno} unless $a->{objno};
	my $rv=db::do("insert into orders (id,org,sp,year,ordno,objno,object_id) values (?,?,?,?,?,?,?)",undef,$a->{order_id},$a->{org},$a->{sp},$a->{year},$a->{ordno},$a->{objno},$a->{object}->{id});
	$a->{error}=db::errstr unless $rv;
	return $a;

}


sub read_reqdata
{
	my $self=shift;
	my $id=shift;
	my $r=db::selectrow_hashref(qq\
select p.id as packet_id,p.order_id,o.object_id,j.address,j.cadastral_number,
(select value from packet_data where id=p.id and key_id='1e265362-1d99-d881-8a54-d317a67454ff') as reqtype,
(select value from packet_data where id=p.id and key_id='1e265282-e637-c6c1-9555-8312c307bb5d') as customer,
(select value from packet_data where id=p.id and key_id='1e265220-7516-b761-838a-db3fd92bfa89') as reqno,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id and event='принят' order by id desc limit 1) as accepted,
(select note from log where refto='packets' and refid=p.id and event='отклонён' order by id desc limit 1) as rejected,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id and event='зарегистрирован' order by id desc limit 1) as reqd,
(select value from packet_data where id=p.id and key_id='1e26524c-6fd1-f0e1-b776-b3d0eb2e4ac6') as paidno,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id and event='оплачен' order by id desc limit 1) as paid,
(select value from packet_data where id=p.id and key_id='1e265289-0f14-6de1-99af-cf099e10bd98') as amount,
(select p2.id from packet_data r2 join packets p2 on p2.id>present() and p2.id=r2.id and r2.key_id=r.key_id where r2.id>present() and r2.value=r.value and p2.type='сведения') as return
from packets p
join orders o on o.id=p.order_id
join objects j on j.id=o.object_id
left join packet_data r on r.id>present() and r.id=p.id and r.key_id='1e265220-7516-b761-838a-db3fd92bfa89'
where p.id=?
and o.sp::text in ( select d.v1 from (select * from context_of('21c02bf5-9968-4eb8-9f27-ebd4d60acc8c',?)) c join data d on d.v2=c.item and d.r='используется в структурном подразделении')
\,undef,$id,$cc->user->{souid});
	return $r;
}

sub reqproc_lists
{
	my $self=shift;
	my %h=@_>1?@_:(id=>shift);
	my $a=ref $h{id} eq 'HASH'?$h{id}:\%h;
	my $r={
		processing=>read_table($self,q/
select
j.address,r.value as reqno,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id and event='принят' order by id desc limit 1) as accepted,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id and event='зарегистрирован' order by id desc limit 1) as reqd,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id and event='оплачен' order by id desc limit 1) as paid,
p.id as packet_id, o.id as order_id, j.id as object_id
from packets p
join orders o on o.id=p.order_id
join objects j on j.id=o.object_id
left join packet_data r on r.id>present() and r.id=p.id and r.key_id='1e265220-7516-b761-838a-db3fd92bfa89'
where p.type='запрос'
and not exists (select 1 from packet_data r2 join packets p2 on p2.id>present() and p2.id=r2.id and r2.key_id=r.key_id where r2.id>present() and r2.value=r.value and p2.type='сведения')
and not exists (select 1 from log where id>present() and refto='packets' and refid=p.id and event='отклонён')
and p.id>present() and o.id>present()
and o.sp::text in ( select d.v1 from (select * from context_of('21c02bf5-9968-4eb8-9f27-ebd4d60acc8c',?)) c join data d on d.v2=c.item and d.r='используется в структурном подразделении')
order by p.id
/,$cc->user->{souid}),
		completed=>read_table($self,q/
select
j.address,r.value as reqno,
(select to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id and event='отклонён' order by id desc limit 1) as rejected,
(select max(p2.id) from packet_data r2 join packets p2 on p2.id>present() and p2.id=r2.id and r2.key_id=r.key_id where r2.id>present() and r2.value=r.value and p2.type='сведения') as return,
p.id as packet_id, o.id as order_id, j.id as object_id
from packets p
join orders o on o.id=p.order_id
join objects j on j.id=o.object_id
left join packet_data r on r.id>present() and r.id=p.id and r.key_id='1e265220-7516-b761-838a-db3fd92bfa89'
where p.type='запрос'
and ( exists (select 1 from packet_data r2 join packets p2 on p2.id>present() and p2.id=r2.id and r2.key_id=r.key_id where r2.id>present() and r2.value=r.value and p2.type='сведения')
or exists (select 1 from log where id>present() and refto='packets' and refid=p.id and event='отклонён')
)
and p.id>present() and o.id>present()
and p.id>uuid_generate_v1o(current_date-30)
and o.sp::text in ( select d.v1 from (select * from context_of('21c02bf5-9968-4eb8-9f27-ebd4d60acc8c',?)) c join data d on d.v2=c.item and d.r='используется в структурном подразделении')
order by p.id desc
limit 100
/,$cc->user->{souid}),
	};
	return $r;

}

sub update_req
{
	my $self=shift;
	my $p=shift;
	my $r=shift;
	$r=read_reqdata($self,$p->{id}) unless $r;

	foreach (qw/reqtype customer reqno paidno amount/)
	{
		packetproc::store_keydata($p->{$_},$_,$p->{id},"packet_data","reqproc") if $p->{$_} ne $r->{$_};
	};
	
	log_event($self,event=>'принят',date=>$p->{accepted},who=>$cc->user->{souid},refto=>'packets',refid=>$p->{id}) if $p->{accepted} and !$r->{accepted};
	db::do("update log set date=?,who=? where refto='packets' and refid=? and event='принят'",undef,$p->{accepted},$cc->user->{souid},$p->{id}) if $p->{accepted} and $r->{accepted} and $p->{accepted} ne $r->{accepted};

	log_event($self,event=>'отклонён',note=>$p->{rejected},who=>$cc->user->{souid},refto=>'packets',refid=>$p->{id}) if $p->{rejected} and !$r->{rejected};
	db::do("update log set note=?,who=? where refto='packets' and refid=? and event='отклонён'",undef,$p->{rejected},$cc->user->{souid},$p->{id}) if $p->{rejected} and $r->{rejected} and $p->{rejected} ne $r->{rejected};

	log_event($self,event=>'зарегистрирован',date=>$p->{reqd},who=>$cc->user->{souid},refto=>'packets',refid=>$p->{id}) if $p->{reqd} and !$r->{reqd};
	db::do("update log set date=?,who=? where refto='packets' and refid=? and event='зарегистрирован'",undef,$p->{reqd},$cc->user->{souid},$p->{id}) if $p->{reqd} and $r->{reqd} and $p->{reqd} ne $r->{reqd};

	log_event($self,event=>'оплачен',date=>$p->{reqd},who=>$cc->user->{souid},refto=>'packets',refid=>$p->{id}) if $p->{paid} and !$r->{paid};
	db::do("update log set date=?,who=? where refto='packets' and refid=? and event='оплачен'",undef,$p->{paid},$cc->user->{souid},$p->{id}) if $p->{paid} and $r->{paid} and $p->{paid} ne $r->{paid};
	return $p;
}

sub present
{
	my $self=shift;;
	my $format=shift||'%Y-%m-%d';
	my $present=$cc->cache->get("present");
	unless ($present)
	{
		$present={time=>str2time(db::selectval_scalar('select timestamp_from_uuid1o(present())')),uuid=>db::selectval_scalar('select present()')};
		$cc->cache->set("present",$present);
	};
	return $present->{uuid} if $format eq 'uuid';
	return time2str($format,$present->{time});
}

sub orders_being_processed
{

	my $self=shift;
	my $operator=shift;
	my $filter=shift;
	
	my $inner=qq\
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from log l
join packets p on p.id=l.refid and l.refto='packets'
left join orders o on (o.id=l.refid and l.refto='orders') or o.id=p.order_id
where l.who=?
and l.closed is null
and (l.event='принят' or (l.event='назначен' and not exists (select 1 from log where refto=l.refto and refid=l.refid and id>l.id)))
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
\;

	my @a;
	my $r;
	$r=db::selectall_arrayref(qq/
select o.id as order_id,o.ordno, o.objno,o.year,j.id as object_id, j.address, sp,
(select shortest(v1) from data where r='наименование структурного подразделения' and v2=o.sp::text) as spname,
(select v1 from data where r='код структурного подразделения' and v2=o.sp::text) as spcode
from (
$inner
order by event_id desc
) o 
join objects j on j.id=o.object_id
/, {Slice=>{}},$filter||$operator);
	return {error=>$DBI::errstr} unless $r;
	push @a, @$r;

	foreach my $o (@a)
	{
		my $r=order_data($self,$o);
		return $r if $r->{error};
		my $p=$o->{packets}[0];
		$o->{group}='к принятию' if $p->{type} eq 'данные' and $p->{status}->{event} eq 'назначен' and ($filter ne $operator or $p->{status}->{who} eq $operator);
		$o->{group}='к получению' if $p->{type} =~ /техплан|межевой/ and $p->{status}->{event} eq 'принят';
		$o->{group}='к закрытию' if $o->{group} eq 'к получению' and (db::selectval_scalar("select 1 from data where r='принадлежит структурному подразделению' and v1=? and v2=?",undef,$p->{status}->{who},$o->{sp}) or db::selectval_scalar("select who from packets p join log l on l.refto='packets' and l.refid=p.id where who is not null and p.order_id=? order by l.id limit 1",undef,$o->{order_id}) eq $p->{status}->{who});
		$o->{group}='к получению' if $p->{type} eq 'сведения' and $p->{status}->{event} eq 'загружен';
		$o->{group}='замечания' if $p->{type} eq 'данные' and $p->{status}->{event} eq 'отклонён';

		$_->{file}=storage::tree_of($_->{container},\@{$_->{filelist}}) foreach $o->{group}?($o->{packets}->[0]):@{$o->{packets}};
	};
	my %group_ordering=('к принятию'=>1,''=>2,'замечания'=>3,'к получению'=>4,'к закрытию'=>5);
	@a=sort {$group_ordering{$a->{group}} <=> $group_ordering{$b->{group}} or $b->{packets}[0]->{status}->{event_id} cmp $a->{packets}[0]->{status}->{event_id}} @a;

	return { ARRAY=>\@a, };
}

sub orders_being_conducted
{

	my $self=shift;
	my $operator=shift;
	my $filter=shift;

	my $inner=qq\
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from log l
join packets p on p.id=l.refid and l.refto='packets'
left join orders o on (o.id=l.refid and l.refto='orders') or o.id=p.order_id
where l.who=?
and l.closed is null
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
union
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from log l
join orders o on o.id=l.refid and l.refto='orders'
where l.who=?
and l.closed is null
and not exists (select 1 from packets where order_id=o.id)
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
\;

	$inner=qq\
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from orders o
join log l on l.refto='orders' and l.refid=o.id
where o.sp=?
and l.closed is null
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
union
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from log l
join orders o on o.id=l.refid and l.refto='orders'
where o.sp=?
and l.closed is null
and not exists (select 1 from packets where order_id=o.id)
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
\ if $filter ne $operator;

	$inner=qq\
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from orders o
join log l on l.refto='orders' and l.refid=o.id
where o.sp in (select distinct v2::uuid from data where r='принадлежит структурному подразделению' and v1=?)
and l.closed is null
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
union
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from log l
join orders o on o.id=l.refid and l.refto='orders'
where o.sp in (select distinct v2::uuid from data where r='принадлежит структурному подразделению' and v1=?)
and l.closed is null
and not exists (select 1 from packets where order_id=o.id)
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
\ unless $filter;

	my @a;
	my $r;
	$r=db::selectall_arrayref(qq/
select 'accepted' as rtype, o.id as order_id,o.ordno, o.objno,o.year,j.id as object_id, j.address, sp,
(select shortest(v1) from data where r='наименование структурного подразделения' and v2=o.sp::text) as spname,
(select v1 from data where r='код структурного подразделения' and v2=o.sp::text) as spcode
from (
$inner
order by event_id desc
) o 
join objects j on j.id=o.object_id
/, {Slice=>{}},$filter||$operator,$filter||$operator);
	return {error=>$DBI::errstr} unless $r;
	push @a, @$r;

	foreach my $o (@a)
	{
		my $r=order_data($self,$o);
		return $r if $r->{error};
		my $p=$o->{packets}[0];
		$o->{group}='к принятию' if $p->{type} eq 'сведения' and $p->{status}->{event} eq 'загружен';
		$o->{group}='замечания' if $p->{type} eq 'данные' and $p->{status}->{event} eq 'отклонён';
		$o->{group}='к принятию' if $p->{type} eq 'данные' and $p->{status}->{event} =~ /назначен|загружен/ and $p->{status}->{note} =~ /на подпись/;
		$o->{group}='к получению' if $p->{type} =~ /техплан|межевой/ and $p->{status}->{event} eq 'принят';
		$o->{group}='к закрытию' if $o->{group} eq 'к получению' and (db::selectval_scalar("select 1 from data where r='принадлежит структурному подразделению' and v1=? and v2=?",undef,$p->{status}->{who},$o->{sp}) or db::selectval_scalar("select who from packets p join log l on l.closed is null and l.refto='packets' and l.refid=p.id where who is not null and p.order_id=? order by l.id limit 1",undef,$o->{order_id}) eq $p->{status}->{who});
		$o->{group}='к получению' if $p->{type} eq 'сведения' and $p->{status}->{event} eq 'загружен';

		$_->{file}=storage::tree_of($_->{container},\@{$_->{filelist}}) foreach $o->{group}?($o->{packets}->[0]):@{$o->{packets}};
	};
	my %group_ordering=('замечания'=>1,'к принятию'=>2,'к получению'=>3,''=>4,'к закрытию'=>5);
	@a=sort {$group_ordering{$a->{group}} <=> $group_ordering{$b->{group}} or $b->{packets}[0]->{status}->{event_id} cmp $a->{packets}[0]->{status}->{event_id}} @a;

	return { ARRAY=>\@a, };
}

sub order_data
{
	my ($self,$o)=@_;
	$o->{packets}=db::selectall_arrayref("select * from packets p where order_id=? order by p.id desc",{Slice=>{}},$o->{order_id});
	return {error=>$DBI::errstr} unless $o->{packets};

	foreach (@{$o->{packets}})
	{
		$_->{status}=db::selectrow_hashref(qq/
select l.id as event_id, event,note,to_char(date,'yyyy-mm-dd hh24:mi') as datef, who, coalesce(d.v1,l.who::text) as fio
from log l 
left join data d on d.r='ФИО сотрудника' and v2=l.who::text
where closed is null and refto='packets' and refid=? order by l.id desc, d.id desc limit 1
/,undef,$_->{id});
		return {error=>$DBI::errstr} unless defined $_->{status};
	};
	@{$o->{packets}}=sort {$b->{status}->{event_id} cmp $a->{status}->{event_id}} @{$o->{packets}};
	unless (scalar @{$o->{packets}})
	{
		$o->{status}=db::selectrow_hashref(qq/
select l.id as event_id, event,note,to_char(date,'yyyy-mm-dd hh24:mi') as datef, who, coalesce(d.v1,l.who::text) as fio
from log l 
left join data d on d.r='ФИО сотрудника' and v2=l.who::text
where closed is null and refto='orders' and refid=? order by l.id desc, d.id desc limit 1
/,undef,$o->{order_id});
		return {error=>$DBI::errstr} unless defined $o->{status};

	};
	return $o;
}


sub read_packet_info
{
	my ($self,$packet_id)=@_;
	return db::selectrow_hashref("select id as packet_id,* from packets where id=?",undef,$packet_id);
}
sub read_order_info
{
	my ($self,$order_id)=@_;
	return db::selectrow_hashref(qq/select o.id as order_id,*,
(select shortest(v1) from data where r='наименование структурного подразделения' and v2=o.sp::text) as spname,
(select v1 from data where r='код структурного подразделения' and v2=o.sp::text) as spcode,
(select event from log where refto='orders' and refid=o.id order by id desc limit 1) as status
from orders o join objects j on j.id=o.object_id where o.id=?/,undef,$order_id);
}

sub last_notified
{
	my ($self,$souid)=@_;
	return db::selectval_scalar("select v1 from data where r='последнее оповещение сотрудника' and v2=?",undef,$souid);
}

sub set_notified
{
	my ($self,$souid,$notification)=@_;
	$notification->{date}=str2time($notification->{date}) if ref $notification eq 'HASH' and $notification->{date}!~/^\d+$/;
	$notification="$notification->{date} $notification->{md5}" if ref $notification eq 'HASH';
	return {error=>'Ошибка в данных'} unless $notification=~/^\d+\s+[a-f0-9\-]+$/;

	return {success=>1} if db::do("update data set v1=? where r='последнее оповещение сотрудника' and v2=?",undef,$notification,$souid)>0;
	return {success=>1} if db::do("insert into data (v1,r,v2) values (?,'последнее оповещение сотрудника',?)",undef,$notification,$souid)>0;
	return {error=>db::errstr};

}

sub read_news
{
	use LWP::Simple;
	my ($self,$user)=@_;

	my $news_href = "http://trac.sfo.rosinv.ru/wiki/Новости";
	my $notified=last_notified($self,$user);
	my $notified_md5;
	($notified,$notified_md5)=($1,$2) if $notified=~/^(\d+) (.*)$/;

	my $newsdata = $cc->cache->get("newsdata-".$user);
	unless ($newsdata)
	{
		my $content = encode("utf8",get("http://trac/wiki/Новости"));
		#my $content = get($news_href); #"http://trac/wiki/Новости");
	 	return unless defined $content;

		# Вырезаем всё кроме новостей
		$content =~ s'^.*<div id="wikipage">''s;
		$content =~ s'</div>.*$''s;

		# Перебираем новости и формируем список
		while ($content =~ s|<h3.*?id="(.+?)">(.+?)</h3>.*?<p>(.+?)</p>||s)
		{
			my $d={text => $3, status => 'info', date => $2, timestamp=>str2time($2),href => "$news_href#$1"};
			last if $notified>$d->{timestamp};
			s/\s+$// and s/^\s+// foreach values %$d;
			$d->{md5}=Digest::MD5::md5_hex($d->{text});
			last if $d->{md5} eq $notified_md5;
			unshift @$newsdata, $d;
		};

		$cc->cache->set("newsdata-".$user,$newsdata);
	};
	return $newsdata;
}

sub log_activity
{
	my ($self,$user)=@_;
	my $active=$cc->cache->get("last-active-$user");
	return if $active;
	$cc->cache->set("last-active-$user",time());
	return if db::do("update data set v1=current_timestamp where r='последняя активность сотрудника' and v2=?",undef,$user)>0;
	db::do("insert into data (v1,r,v2) values (current_timestamp,'последняя активность сотрудника',?)",undef,$user)>0;
}

sub orders_being_dispatched
{

	my $self=shift;
	my $operator=shift;
	my $filter=shift;


	my $inner=qq\
select distinct o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,(select max(id) from log where closed is null and refid in (o.id,p.id)) as event_id
from packets p
left join orders o on o.id=p.order_id
where
p.type in( 'данные','техплан','межевой')
and exists (select 1 from log l where closed is null and refto='packets' and refid=p.id and event='загружен' and lower(coalesce(note,'')) !~ 'на подпись' and not exists (select 1 from log where closed is null and refto=l.refto and refid=l.refid and id>l.id))
and (
o.sp::text in (select item from items where souid=? and sp_name is not null)
or o.id in (select refid from log where closed is null and refto='orders' and who::text in (select item from items where souid='$operator' and (sp_name is not null or item=souid)))
or p.id in (select refid from log where closed is null and refto='packets' and who::text in (select item from items where souid='$operator' and (sp_name is not null or item=souid)))
)
union
select distinct o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,(select max(id) from log where closed is null and refid in (o.id,p.id)) as event_id
from packets p
join orders o on o.id=p.order_id
where
p.type='данные'
and exists ( select 1 from log l join data d on d.r='наименование структурного подразделения' and d.v2::uuid=l.who and d.v2 in (select v2 from data where l.closed is null and r='принадлежит структурному подразделению' and v1='$operator') where refto='packets' and refid=p.id and event='назначен' and not exists (select 1 from log where closed is null and refto=l.refto and refid=l.refid and id>l.id))
\;

	my $coworkers=get_coworkers_list($self,$operator);

	$inner=qq\
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from orders o
join log l on l.refto='orders' and l.refid=o.id
where o.sp=?
and l.closed is null
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
\ if $filter ne $operator;

	$inner=qq\
select o.id,o.sp,o.ordno,o.year,o.objno,o.object_id,max(l.id) as event_id
from log l
join packets p on p.id=l.refid and l.refto='packets'
left join orders o on (o.id=l.refid and l.refto='orders') or o.id=p.order_id
where l.who=?
and l.closed is null
and (l.event='принят' or (l.event='назначен' and not exists (select 1 from log where closed is null and refto=l.refto and refid=l.refid and id>l.id)))
group by o.id,o.sp,o.ordno,o.year,o.objno,o.object_id
\ if $filter ne $operator and grep {(keys %$_)[0] eq $filter} @$coworkers;

	my @a;
	my $r;
	$r=db::selectall_arrayref(qq/
select 'accepted' as rtype, o.id as order_id,o.ordno, o.objno,o.year,j.id as object_id, j.address, sp,
(select shortest(v1) from data where r='наименование структурного подразделения' and v2=o.sp::text) as spname,
(select v1 from data where r='код структурного подразделения' and v2=o.sp::text) as spcode
from (
$inner
order by event_id desc
) o 
join objects j on j.id=o.object_id
/, {Slice=>{}},$filter||$operator);
	return {error=>$DBI::errstr} unless $r;
	push @a, @$r;

	foreach my $o (@a)
	{
		my $r=order_data($self,$o);
		return $r if $r->{error};
		my $p=$o->{packets}[0];
		$o->{group}='к принятию' if $p->{type} =~ /техплан|межевой/ and $p->{status}->{event} eq 'загружен';
		$o->{group}='замечания' if $p->{type} eq 'данные' and $p->{status}->{event} eq 'отклонён';
		$o->{group}='к принятию' if $p->{type} eq 'данные' and $p->{status}->{event} =~ /назначен|загружен/ and $p->{status}->{note} =~ /на подпись/;
		$o->{group}='к получению' if $p->{type} =~ /техплан|межевой/ and $p->{status}->{event} eq 'принят';
		$o->{group}='к закрытию' if $o->{group} eq 'к получению' and (db::selectval_scalar("select 1 from data where r='принадлежит структурному подразделению' and v1=? and v2=?",undef,$p->{status}->{who},$o->{sp}) or db::selectval_scalar("select who from packets p join log l on l.refto='packets' and l.refid=p.id where l.closed is null and who is not null and p.order_id=? order by l.id limit 1",undef,$o->{order_id}) eq $p->{status}->{who});
		$o->{group}='к получению' if $p->{type} eq 'сведения' and $p->{status}->{event} eq 'загружен';

		$_->{file}=storage::tree_of($_->{container},\@{$_->{filelist}}) foreach $o->{group}?($o->{packets}->[0]):@{$o->{packets}};
	};
	my %group_ordering=('к принятию'=>1,''=>2,'замечания'=>3,'к получению'=>4,'к закрытию'=>5);
	@a=sort {$group_ordering{$a->{group}} <=> $group_ordering{$b->{group}} or $b->{packets}[0]->{status}->{event_id} cmp $a->{packets}[0]->{status}->{event_id}} @a;

	return { ARRAY=>\@a, };
}

sub autoassign
{
	my ($self,$souid,$autoassign)=@_;

	my $r=shift cached_array_ref($self,"select * from data where r='автоматическое назначение пакетов оператору' and v2=?",$souid);
	return $r->{v1} ne 'отключено' unless defined $autoassign;

	db::do("update data set v1='отключено' where id=?",undef,$r->{id}) if !$autoassign and $r->{v1} ne 'отключено'; 
	db::do("delete from data where id=?",undef,$r->{id}) if $r->{id} and $autoassign;
	my $rv=db::do("insert into data (v1,r,v2) values (?,?,?)",undef,'отключено','автоматическое назначение пакетов оператору',$souid) if !$autoassign and !$r->{id};
	$r=cached_array_ref($self,{update=>1},"select * from data where r='автоматическое назначение пакетов оператору' and v2=?",$souid);
	return $autoassign;
}

sub move_packet
{
	my ($self, $packet_id, $order_id)=@_;
	db::do("update packets set order_id=? where id=?",undef,$order_id||undef,$packet_id);
	db::do("update log set closed=current_timestamp where refto='packets' and refid=? and closed is null",undef,$packet_id) unless $order_id;
	db::do("update log set closed=(select closed from log where refto='orders' and refid=? order by id desc limit 1) where refto='packets' and refid=?",undef,$order_id,$packet_id) if $order_id;
}

sub order_address
{
	my ($self, $order_id)=@_;
	return db::selectval_scalar("select address from objects j join orders o on o.object_id=j.id where o.id=?",undef,$order_id);

}
sub order_closed
{
	my ($self, $order_id)=@_;
	return db::selectval_scalar("select 1 where not exists (select 1 from log where closed is null and refto='orders' and refid=?)",undef,$order_id)//0;

}

sub get_signers
{
	my ($self, $signant)=@_;
	return options_list($self,{cache_key=>$signant},"select d.v2,(latest(d.*)).v1 from data s join data d on d.r='ФИО сотрудника' and d.v2=s.v2 where s.r='оператор ЭЦП' and s.v1=? group by d.v2 order by 2",$signant);
}

1;
