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
	$dbh=DBI->connect("dbi:Pg:dbname=mailproc;host=localhost", undef, undef, {AutoCommit => 1});
	return $dbh;
}

sub array_ref
{
	my ($self, $q, @params)=@_;
	$self->connect() or return undef;

	my $sth=$dbh->prepare($q);
	$sth->execute(@params);
	my @result=();
	while(my $r=$sth->fetchrow_arrayref)
	{
		push @result,$r->[0];
	};
	return \@result;
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
	my $rv=$dbh->do("insert into ".$dbh->quote_identifier($table)." (".join(', ', keys %$pairs).") values (".join(', ',map ("?",values %$pairs)).")",undef,values %$pairs);

	return {error=>"Ошибка при добавлении записи: $DBI::errstr"} unless $rv==1;
	
	my $r=$dbh->selectrow_hashref("select currval('$table"."_id_seq') as id");

	return {error=>'Ошибка при определении идентификатора новой записи'} unless $r;

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
	return array_ref($self,"select otd from orders where otd ~ ? group by otd order by otd",$cc->user->{otd});
}

sub get_cd_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return array_ref($self,"select cadastral_district from objects where cadastral_district is not null group by cadastral_district order by cadastral_district");
}

sub get_objsource_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return array_ref($self,"select source from objects where source is not null group by source order by source");
}

sub get_rc_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return array_ref($self,"select reg_code from packets where reg_code is not null group by reg_code order by reg_code");
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
	return array_ref($self,"select path from packets where path is not null group by path order by path");
}

sub get_event_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	my $result=$cc->cache->get("wholist");
	unless ($result)
	{
		$result=array_ref($self,"select event from log where event is not null group by event order by event");
		$cc->cache->set("wholist",$result);
	};
	return $result;
}

sub get_who_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	my $result=$cc->cache->get("wholist");
	unless ($result)
	{
		$result=array_ref($self,"select who from log where who is not null group by who order by who");
		$cc->cache->set("wholist",$result);
	};
	return $result;
}

sub get_refto_list
{
	my ($self)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	return array_ref($self,"select refto from log where refto is not null group by refto order by refto");
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

	my $r=$dbh->selectrow_hashref("select d1.v1 as password, d2.v2 as full_name from data d1 join data d2 on d1.r like 'пароль%' and d2.r like '%сущности' and d2.v1=d1.v2 where d1.v2=?",undef,$authinfo->{username});

	%data=(%data,%$r) if $r;

	my $sth=$dbh->prepare(qq/
select d3.v1 as description
from data d1
join data d2 on d2.v1=d1.v2 and d2.r like '%сущности'
join data d3 on d3.v2=d2.v2 and d3.r like 'описание сущности'
where d1.v2=? and d1.r like 'пароль%'
/
);
	$sth->execute($authinfo->{username}); 
	while (my $r=$sth->fetchrow_hashref)
	{
		push @{$data{roles}}, split / /,$r->{description};
	};
	$sth->finish();

	$data{otd}='x';

	my $roles="'norole'";
	$roles="'".join("', '",@{$data{roles}})."'" if $data{roles};
	my $otds=$dbh->selectcol_arrayref(qq/
select v1 from data where r='отделение сотрудника' and v2=?
union
select v1 from data where r='отделение роли' and v2 in ($roles)
union
select otd from orders group by otd having otd = ? 
union
select v1 from data where r='отделение сущности' and v2=?
/,undef, $data{full_name},$data{username},$data{full_name});
	$otds and @$otds and $data{otd}=join("|",@$otds);

	return \%data;
}

sub read_orders
{
	my ($self,$authinfo)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	return 'read_orders';
}

sub read_order_data
{
	my ($self,$id)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my $r=$dbh->selectrow_hashref(qq{
select o.*,
(select to_char(date,'yyyy-mm-dd') from log where order_id=o.id and event='принят' order by id desc limit 1) as accepted,
(select to_char(date,'yyyy-mm-dd') from log where order_id=o.id and event='оплата' order by id desc limit 1) as paid
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
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,who,refto,refid,file
from log
where order_id=?
or packet_id in (select id from packets where order_id=?)
or object_id=(select object_id from orders where id=?)
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

	my $r=$dbh->selectrow_hashref("select * from objects where id=? and otd ~ ?",undef,$id,$cc->user->{otd});
	return undef unless $r;

	my %data;
	$data{object}=$r;

	my %orders;
	my $sth=$dbh->prepare(qq{
select o.*,
(select to_char(date,'yyyy-mm-dd') from log where event='принят' and order_id=o.id order by id desc limit 1) as accepted,
(select to_char(date,'yyyy-mm-dd') from log where event='оплата' and order_id=o.id order by id desc limit 1) as paid
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
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,who,refto,refid,file
from log
where order_id in (select id from orders where object_id=?)
or packet_id in (select id from packets where order_id in (select id from orders where object_id=?))
or object_id=?
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
(select who from log where packet_id=p.id order by id desc limit 1) as who,
(select event || ' '|| to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id order by id limit 1) as accepted,
(select event || ' '|| to_char(date,'yyyy-mm-dd hh24:mi') from log where refto='packets' and refid=p.id order by id desc limit 1) as status,
(select file from log where refto='packets' and refid=p.id and file is not null order by id desc limit 1) as current
from packets p where id=?}
,undef,$id);
	return undef unless $packet;
	$data{packet}=$packet;

	my $order=$dbh->selectrow_hashref("select * from orders where id=?",undef,$packet->{order_id});
	$data{order}=$order;

	my $object=$dbh->selectrow_hashref("select * from objects where id=?",undef,$order->{object_id});
	$data{object}=$object;

	my $sth=$dbh->prepare(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,who,refto,refid,file
from log
where packet_id = ?
or order_id=?
or packet_id in (select id from packets where order_id = ?)
or object_id=?
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

sub read_table
{
	my $self=shift;
	my $query=shift;
	my @values=@_;

	$self->connect() or return undef;

	my $start=time;

	my $sth=$dbh->prepare($query);
	$sth->execute(@values);

	my %result=(query=>$query,values=>[@values],header=>[@{$sth->{NAME}}],rows=>[]);

	while(my $r=$sth->fetchrow_hashref)
	{
		push @{$result{rows}},$r;
	};
	$sth->finish;

	$result{duration}=time-$start;

	return \%result;
}

sub search_orders
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;
	my $start=time;

	my @where;
	push @where, "o.otd ~ ".$dbh->quote($cc->user->{otd});
	push @where, "o.otd = ".$dbh->quote($filter->{otd}) if $filter->{otd};
	push @where, "year = ".$dbh->quote($filter->{year}) if $filter->{year};
	push @where, "ordno = ".$dbh->quote($filter->{ordno}) if $filter->{ordno};
	push @where, "objno = ".$dbh->quote($filter->{objno}) if $filter->{objno};
	push @where, sprintf "exists (select 1 from log where order_id=o.id and date=%s and event='принят')",$dbh->quote($filter->{accepted}) if $filter->{accepted};
	push @where, sprintf "exists (select 1 from log where order_id=o.id and date=%s and event='оплата')",$dbh->quote($filter->{paid}) if $filter->{paid};
	push @where, sprintf "exists (select 1 from objects where id=o.object_id and lower(address) ~ lower(%s))",$dbh->quote($filter->{address}) if $filter->{address};
	push @where, sprintf "exists (select 1 from objects where id=o.object_id and lower(invent_number) ~ lower(%s))",$dbh->quote($filter->{invent_number}) if $filter->{invent_number};

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=read_table($self,sprintf(qq{
select 
o.id,o.otd,o.year,o.ordno,o.objno,
(select to_char(date,'yyyy-mm-dd') from log where order_id=o.id and event='принят' order by id desc limit 1) as accepted,
(select to_char(date,'yyyy-mm-dd') from log where order_id=o.id and event='оплата' order by id desc limit 1) as paid,
(select address from objects where id=o.object_id) as address,
(select invent_number from objects where id=o.object_id) as invent_number
from orders o
where %s order by id desc %s},join(" and ",@where),$limit));
	
	return $result;

}

sub search_objects
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %where;
	$where{"1=?"}=1;
	$where{"o.cadastral_district = ?"}=$filter->{cadastral_district} if $filter->{cadastral_district};
	$where{"lower(o.address) ~ lower(?)"}=$filter->{address} if $filter->{address};
	$where{"lower(o.name) ~ lower(?)"}=$filter->{name} if $filter->{name};
	$where{"lower(o.invent_number) ~ lower(?)"}=$filter->{invent_number} if $filter->{invent_number};
	$where{"lower(o.cadastral_number) ~ lower(?)"}=$filter->{cadastral_number} if $filter->{cadastral_number};
	$where{"o.source = ?"}=$filter->{source} if $filter->{source};

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=read_table($self,qq{
select 
id, cadastral_district, address, name, invent_number, cadastral_number, source
from objects o
where }
.join (" and ",keys %where)." order by id desc $limit",map($where{$_},keys %where)
);
	
	return $result;

}

sub search_packets
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %where;
	$where{"o.otd ~ ?"}=$cc->user->{otd};
	$where{"o.otd = ?"}=$filter->{otd} if $filter->{otd};
	$where{"p.reg_code = ?"}=$filter->{reg_code} if $filter->{reg_code};
	$where{"lower(p.guid) ~ lower(?)"}=$filter->{guid} if $filter->{guid};
	$where{"p.actno ~ ?"}=$filter->{actno} if $filter->{actno};
	$where{"p.reqno ~ ?"}=$filter->{reqno} if $filter->{reqno};

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=read_table($self,qq{
select
p.id, o.otd, reg_code, guid, path, actno, reqno 
from packets p left join orders o on o.id=p.order_id
where }
.join (" and ",keys %where)." order by p.id desc $limit",map($where{$_},keys %where)
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
	push @where, "l.date > ".$dbh->quote($filter->{from}) if $filter->{from};
	push @where, "l.date <= ".$dbh->quote($filter->{to}) if $filter->{to};
	push @where, "l.event = ".$dbh->quote($filter->{event}) if $filter->{event};
	push @where, "l.who = ".$dbh->quote($filter->{who}) if $filter->{who};
	push @where, sprintf "lower(l.note) ~ lower(%s)", $dbh->quote($filter->{note}) if $filter->{note};
	push @where, "l.refto = ".$dbh->quote($filter->{refto}) if $filter->{refto};
	push @where, "l.refid = ".$dbh->quote($filter->{refid}) if $filter->{refid};
	push @where, sprintf "lower(obj.address) ~ lower(%s)", $dbh->quote($filter->{address}) if $filter->{address};
	push @where, sprintf "lower(obj.invent_number) ~ lower(%s)", $dbh->quote($filter->{invent_number}) if $filter->{invent_number};
	scalar @where or push @where,'true';

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=read_table($self,qq{
select
l.id, to_char(date,'yyyy-mm-dd hh24:mi') as date,event,who,note,refto,refid,o.otd,obj.invent_number,obj.address,l.file
from log l
join orders o on o.id=coalesce((select l.refid where l.refto='orders'), (select order_id from packets where id=l.refid and l.refto='packets'),(select id from orders where object_id=l.refid and l.refto='objects'))
left join objects obj on obj.id=o.object_id
where l.id in
(
select l.id
from log l
join orders o on o.id=coalesce((select l.refid where l.refto='orders'), (select order_id from packets where id=l.refid and l.refto='packets'),(select id from orders where object_id=l.refid and l.refto='objects'))
left join objects obj on obj.id=o.object_id
where
}.join (" and ",@where).qq{
order by l.id desc $limit
)
order by l.id desc
});
	
	return $result;

}
1;
