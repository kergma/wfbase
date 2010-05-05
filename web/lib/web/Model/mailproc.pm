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
	return array_ref($self,"select otd from orders where otd is not null group by otd order by otd");
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

sub get_path_list
{
	my ($self)=@_;
	$self->connect() or return undef;
	return array_ref($self,"select path from packets where path is not null group by path order by path");
}

sub test
{
	my ($self,$c)=@_;
	use Data::Dumper;

	return Dumper($cc);
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
/,undef, $data{full_name},$data{username});
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
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,who,order_id,packet_id,object_id
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
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,who,packet_id,order_id,object_id
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
(select event || ' '|| to_char(date,'yyyy-mm-dd hh24:mi') from log where packet_id=p.id order by id desc limit 1) as accepted,
(select event || ' '|| to_char(date,'yyyy-mm-dd hh24:mi') from log where packet_id=p.id order by id desc limit 1) as status
from packets p where id=?}
,undef,$id);
	return undef unless $packet;
	$data{packet}=$packet;

	my $order=$dbh->selectrow_hashref("select * from orders where id=?",undef,$packet->{order_id});
	$data{order}=$order;

	my $object=$dbh->selectrow_hashref("select * from objects where id=?",undef,$order->{object_id});
	$data{object}=$object;

	my $sth=$dbh->prepare(qq/
select id,to_char(date,'yyyy-mm-dd hh24:mi') as date,event,note,who,packet_id,order_id,object_id
from log
where order_id = ?
or packet_id in (select id from packets where order_id = ?)
or object_id=?
order by id desc/);
	$sth->execute($order->{id},$order->{id},$object->{id});
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

	use Data::Dumper;
	$cc->log->debug(Dumper($query).Dumper(\@values));

	$self->connect() or return undef;

	my $sth=$dbh->prepare($query);
	$sth->execute(@values);

	my %result=(query=>$query,values=>[@values],header=>[@{$sth->{NAME}}],rows=>[]);

	while(my $r=$sth->fetchrow_arrayref)
	{
		my @a=@$r;
		push @{$result{rows}},\@a;
	};
	$sth->finish;

	return \%result;
}

sub search_orders
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %where;
	$where{"o.otd ~ ?"}=$cc->user->{otd};
	$where{"o.otd = ?"}=$filter->{otd} if $filter->{otd};
	$where{"year = ?"}=$filter->{year} if $filter->{year};
	$where{"ordno = ?"}=$filter->{ordno} if $filter->{ordno};
	$where{"objno = ?"}=$filter->{objno} if $filter->{objno};
	$where{"exists (select 1 from log where order_id=o.id and date=? and event='принят')"}=$filter->{accepted} if $filter->{accepted};
	$where{"exists (select 1 from log where order_id=o.id and date=? and event='оплата')"}=$filter->{paid} if $filter->{paid};
	$where{"exists (select 1 from objects where id=o.object_id and lower(address) ~ lower(?))"}=$filter->{address} if $filter->{address};
	$where{"exists (select 1 from objects where id=o.object_id and lower(invent_number) ~ lower(?))"}=$filter->{invent_number} if $filter->{invent_number};

	$limit+0 or undef $limit;
	$limit and $limit="limit $limit";

	my $result=read_table($self,qq{
select 
o.id,o.otd,o.year,o.ordno,o.objno,
(select to_char(date,'yyyy-mm-dd') from log where order_id=o.id and event='принят' order by id desc limit 1) as accepted,
(select to_char(date,'yyyy-mm-dd') from log where order_id=o.id and event='оплата' order by id desc limit 1) as paid,
(select address from objects where id=o.object_id) as address,
(select invent_number from objects where id=o.object_id) as invent_number
from orders o
where }
.join (" and ",keys %where)." order by id desc $limit",map($where{$_},keys %where)
);
	
	$result->{header}=['Заказ','Отделение','Год','Номер','Объект','Принят','Оплачен','Адрес','Инв. номер'];
	return $result;

}

sub search_objects
{
	my ($self,$filter,$limit)=@_;
	defined $cc or return undef;
	$self->connect() or return undef;

	my %where;
	$where{"o.otd ~ ?"}=$cc->user->{otd};
	$where{"o.otd = ?"}=$filter->{otd} if $filter->{otd};
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
id, otd, cadastral_district, address, name, invent_number, cadastral_number, source
from objects o
where }
.join (" and ",keys %where)." order by id desc $limit",map($where{$_},keys %where)
);
	
	$result->{header}=['Объект','Отделение','Кадастровый р-н','Адрес','Наименование','Инв. номер','Кадастровый номер','Источник'];
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
	
	$result->{header}=['Пакет','Отделение','Код','ГУИД 1С','Направление','Номер акта','Номер заявления'];
	return $result;

}

1;
