package wf::Model::udb;
use Moose;
use namespace::autoclean;

extends 'Catalyst::Model';

use DBI;
use Digest::MD5;
use Encode;
use Date::Format;

no warnings qw/uninitialized experimental/;

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


my $isuid='3019f26b-c6d5-41bb-9d1e-7311b675f46f'; # UDB
my $cc;

sub ACCEPT_CONTEXT
{
	my ($self,$c,@args)=@_;

	$cc=$c;
	return $self;
}

sub arrayref;
sub arrayref($)
{
	my ($v)=@_;
	return $v if ref $v eq 'ARRAY';
	return [$v];
}

sub authinfo_password
{
	my ($self,$authinfo)=@_;

	my $r=db::selectrow_hashref(qq{
select p.t as passw,a.e2 as soid from systems a
join systems n on n.r=er.key('имя входа') and n.e1=a.e1
join systems p on p.r=er.key('пароль ct') and p.e1=a.e1
where a.r=er.key('учётная запись сотрудника') and (n.t=? or a.e1=?)
},undef,$authinfo->{username},$authinfo->{uid});
	$r or return undef;
	$r->{passw}="***" if $authinfo->{uid} and !$authinfo->{username};
	$authinfo->{soid}=$r->{soid};
	$authinfo->{password}=$r->{passw};
	return $r->{passw};
}



sub authinfo_data
{
	my ($self,$authinfo)=@_;

	my %data=%$authinfo;
	$data{entity}=$self->entity($authinfo->{soid});
	$data{full_name}=$data{entity}->{names}->[0];
	my $r=$self->array_ref(qq/
select path[array_length(path,1)] as role,a.t role_t from er.tree_from(?,array[er.key('входит в состав полномочия'),-er.key('уполномочен на')]) t
left join authorities a on a.e1=t.path[array_length(t.path,1)] and a.r=any(er.keys('наименование%','полномочия'))
/,$authinfo->{soid})
;
	$data{roles}=[map {$_->{role},$_->{role_t}} @$r];
	return \%data;
}

sub search_records
{
	my ($self,$filter)=@_;

	my %where=('1=?',1);
	$where{'recid=?'}=$filter->{recid} if $filter->{recid};
	$where{'lower(defvalue)~lower(?)'}=$filter->{defvalue} if $filter->{defvalue};
	$where{'lower(defvalue)~lower(?)'}=~s/ +/\.\*/ if $filter->{defvalue};
	$where{sprintf("rectype in (%s)",join(',', map {'?'} @{arrayref $filter->{rectype}}))}=arrayref $filter->{rectype} if $filter->{rectype};
	$where{"exists (select 1 from data where (v1=recid or v2=recid) and (v1=? or v2=?))"}=[$filter->{related},$filter->{related}] if $filter->{related};
	my $limit=$filter->{limit}||0;
	$limit+0 or $limit="";
	$limit and $limit="limit $limit";
	return read_table($self,sprintf(qq/select * from recv where %s order by 2 $limit/,join(" and ",keys %where)),map(@{arrayref $_}, grep {$_ ne 'novalue'} values %where));
}

sub timestame_of_id
{
	my ($self,$id,$format)=@_;
	$format//='%Y-%m-%d %H:%M:%S';
	my $t=str2time(db::selectval_scalar('select timestame_of_id(?)',undef,$id));
	return time2str($t,$format);
}

sub entities
{
	my ($self, $f)=@_;
	return read_table($self,qq/select * from er.entities(?,?,?,?,?)/,$f->{en},$f->{name},$f->{type},$f->{domain},$f->{limit});
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
order by r,refdef
/,{Slice=>{}},$id,$id,$id,$id);

}

sub record_of
{
	my ($self,$id,$domain)=@_;
	return db::selectall_arrayref(qq/select * from er.record_of(?,?) order by value is null, key, name2, name1/,{Slice=>{}},$id,$domain);
}
sub record_of_requested
{
	my ($self,$id,$domain)=@_;
	return db::selectall_arrayref(qq/
with i as (
	select ?::int8 as id
),
r as (
	select (r).* from (select er.record_of(id) as r from i) s
),
c as (
	select c.* from changes c join r on r.table=c.table and r.row=c.row where not exists (select 1 from changes where "table"=c.table and "row"=c.row and request>c.request)
	union
	select c.* from changes c,i where (('e1',null,id)::er.row=any(data) or ('e2',null,id)::er.row=any(data))
),
x as (
	select
	(select e from er.entities(coalesce((select (u).value::int8 from unnest((c).data) as u where (u).column='e1' and isid((u).value)),-1)) e) as e1,
	(select k from er.keys k where id=(select (u).value::int8 from unnest((c).data) as u where (u).column='r')) as r,
	(select e from er.entities(coalesce((select (u).value::int8 from unnest((c).data) as u where (u).column='e2' and isid((u).value)),-1)) e) as e2,
	(select (u).value from unnest((c).data) as u where (u).column='t') as value,
	c
	from c
),
cx as (
	select (c).*,
	(e1).en as e1, (e1).names[1] as name1,
	(r).id as r, (r).key, (r).domain,
	(e2).en as e2, (e2).names[1] as name2,
	value
	from x
)
select coalesce(r."table",cx."table") as "table", coalesce(r.row,cx.row) as row, r.e1, r.name1, r.r, r.key, r.domain, r.e2, r.name2, r.value,
(select nullif(array_agg_md(array[array[d.column,d.type, d.value]]),'{}') from unnest(data) d) as data,
action,request,requester,resolve,resolver,resolution,note,
coalesce(cx.e1::text,(select (u).value from unnest(data) as u where (u).column='e1')) as c_e1, cx.name1 as c_name, cx.r as c_r, cx.key as c_key, cx.domain as c_domain, coalesce(cx.e2::text,(select (u).value from unnest(data) as u where (u).column='e2')) as c_e2, cx.name2 as c_name2, cx.value as c_value
from r full join cx on cx.table=r.table and cx.row=r.row
order by r.value is null, r.key, r.name2, r.name1
/,{Slice=>{}},$id);
;
}
sub request_update
{
	my ($self,$r,$value)=@_;
	my $d;
	$d=['t',undef,$value] if $r->{r}~~[2400924095923474560,2400924095940272256,2400924095940276352];
	$d=[['e1',undef,$cc->user->{entity}->{en}],['r',undef,$r->{r}],['e2',undef,$value]] if $r->{r}~~[2400924095923462272,2401518747775791232];
	db::do('delete from changes where "table"=? and "row"=? and request=?',undef,$r->{table},$r->{row},$r->{request});
	return db::selectall_arrayref(q/insert into changes ("table","row",action,request,requester,data) select ?::text,?::int,'update',coalesce(?::int8,generate_id()),?::int8,array_agg((e[1],e[2],e[3])::er.row) from unnest_md(?::text[][]) as e returning */,{Slice=>{}},$r->{table},$r->{row},undef,$cc->user->{entity}->{en},$d);
}
sub request_delete
{
	my ($self,$r)=@_;
	db::do('delete from changes where "table"=? and "row"=? and request=?',undef,$r->{table},$r->{row},$r->{request});
	return db::selectall_arrayref(q/insert into changes ("table","row",action,request,requester) select ?::text,?::int,'delete',coalesce(?::int8,generate_id()),?::int8 returning */,{Slice=>{}},$r->{table},$r->{row},undef,$cc->user->{entity}->{en});
}
sub request_insert
{
	my ($self,$key,$value)=@_;
	my $d;
	$d=[['e1',undef,$cc->user->{entity}->{en}],['r',undef,$key->[0]],['t',undef,$value]] if $key->[0]~~[2400924095923474560,2400924095940272256,2400924095940276352];
	$d=[['e1',undef,$cc->user->{entity}->{en}],['r',undef,$key->[0]],['e2',undef,$value]] if $key->[0]~~[2400924095923462272,2401518747775791232];
	return db::selectall_arrayref(q/insert into changes ("table",action,request,requester,data) select ?::text,'insert',coalesce(?::int8,generate_id()),?::int8,array_agg((e[1],e[2],e[3])::er.row) from unnest_md(?::text[][]) as e returning */,{Slice=>{}},$key->[3],undef,$cc->user->{entity}->{en},$d);
}
sub cancel_request
{
	my ($self,$r)=@_;
	db::do('delete from changes where "table"=? and coalesce("row",0)=coalesce(?,0) and request=?',undef,$r->{table},$r->{row},$r->{request});
}
sub test
{
	my ($self,$id,$domain)=@_;
	return db::selectall_arrayref(qq/select data from changes/);
}

sub rectypes
{
	my ($self)=@_;
	return cached_array_ref($self,q/select distinct regexp_replace(rectype,'^.*PKI$','Объект PKI') from recv where rectype is not null order by 1/);
}
sub types
{
	my ($self)=@_;
	return cached_array_ref($self,q/select distinct type from er.typing where domain=coalesce(null,domain) order by 1/);
}
sub domains
{
	my ($self)=@_;
	return cached_array_ref($self,q/select distinct domain from er.keys order by 1/);
}
sub row
{
	my ($self,$table, $row)=@_;
	return db::selectall_arrayref(qq\
select (r).*, (e).*, (k).* from (
select r,case when "column" like 'e%' and value is not null then (select er.entities(value::int8) as e) end as e,
case when "column" ='r' and value is not null then (select k from er.keys k where id=value::int8) end as k
from er.row(?,?) as r
) s
\,{Slice=>{}},$table,$row);
}

sub row_update
{
	my ($self, $old, $new)=@_;
	my $table=(grep {$_->{column} eq 'table'} @$old)[0]->{value};
	my $row=(grep {$_->{column} eq 'row'} @$old)[0]->{value};
	delete $new->{row};
	undef $_ foreach grep {!$_} values %$new;

	return db::selectall_arrayref(qq/select * from er.chrow(?,?,?,?)/,{Slice=>{}},$table,$row,[keys %$new],[values %$new]);
}

sub storages
{
	my ($self,$domain)=@_;
	return db::selectall_arrayref(qq/select * from er.storages order by ?=any(domains) desc,"table"/,{Slice=>{}},$domain);
}
sub recdef
{
	my ($self,$recid)=@_;
	my $r=db::selectrow_arrayref(qq/select defvalue,rectype from recv where recid=?/,undef,$recid);
	return (undef,undef) unless $r;
	return @$r;
}
sub entity
{
	my ($self,$en,$domain)=@_;
	return db::selectrow_hashref(qq/select * from er.entities(coalesce(?,0::int8),null,null,?)/,undef,$en,$domain);
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

	my $sth;
	if ($opts->{use_safe_connection})
	{
		my $sdbh=$self->sconnect() or return undef;
		$sth=$sdbh->prepare($q);
	}
	else
	{
		$sth=db::prepare($q);
	};
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

sub generate_id()
{
	my $self=shift;
	return db::selectval_scalar("select generate_id()");
}

sub keys()
{
	my ($self, $q)=@_;
	return cached_array_ref($self,{row=>'enhash'},"select * from er.keys");
}

sub membership()
{
	my ($self, $en)=@_;
	my $r=$self->cached_array_ref(q/
with z as (
select path[2: array_length(path,1)],path[array_length(path,1)] as id,shortest(s.t) as name from er.tree_from(?,er.keys('принадлежит%'),true,null,1) t
left join subjects s on s.e1=t.path[array_length(t.path,1)] and s.r=any(er.keys('наименование%','субъекты'))
group by path
)
select not exists (select 1 from z z2 where path[1: array_length(path,1)-1]=z.path) as leaf, * from z order by array_reverse(path)
/,$en);
	my $i={map {$_->{path}->[-1]=>$_->{name}} @$r};
	@$r=map {@{$_->{path}}=reverse @{$_->{path}};$_->{name}=$i->{$_->{path}->[-1]};$_->{names}=[map {$i->{$_}} @{$_->{path}}];$_} grep {$_->{leaf}} @$r;
	return {list=>$r};
}

sub authorization()
{
	my ($self, $en)=@_;
	my $r=$self->cached_array_ref(q/
select path[2: array_length(path,1)] as path,a.t as name from er.tree_from(?,array[er.key('входит в состав полномочия'),-er.key('уполномочен на')],null,null,1) t
left join authorities a on a.e1=t.path[array_length(t.path,1)] and a.r=any(er.keys('наименование%','полномочия'))
order by path
/,$en);
	return {list=>$r};
}

sub contact_info()
{
	my ($self, $en)=@_;
	return $self->cached_array_ref(q/
with m as (
select path[2: array_length(path,1)],path[array_length(path,1)] as id,shortest(s.t) as name from er.tree_from(?,er.keys('принадлежит%'),true) t
left join subjects s on s.e1=t.path[array_length(t.path,1)] and s.r=any(er.keys('наименование%','субъекты'))
group by path
)
select (array_agg_uniq(key))[1] as k, t, array_agg_uniq(m.id) as subjects, array_agg_uniq(m.name) as names
from m
join subjects p on p.r in (er.key('телефон'), er.key('email')) and p.e1=m.id
join er.keys k on k.id=p.r
group by t
order by max(m.path)
/,$en);
}

sub content()
{
	my ($self, $en)=@_;
	my $r=$self->cached_array_ref(q/
select path[2: array_length(path,1)] as path,shortest(s.t) as name from er.tree_from(?,er.keys('принадлежит%'),null,1,1) t
left join subjects s on s.e1=t.path[array_length(t.path,1)] and s.r=any(er.keys('наименование%','субъекты')||er.keys('полное имя%'))
group by path
order by path
/,$en);
	return {list=>$r};
}


package db;

my $dbh;

for my $funame (qw/errstr do prepare quote selectrow_arrayref selectrow_hashref selectcol_arrayref selectall_arrayref selectall_hashref last_insert_id quote_identifier/)
{
	no strict 'refs';
	*$funame=sub {
		db::connect() unless $dbh;
		my $rv=$dbh->$funame(@_);
		#Catalyst::Exception->throw($DBI::errstr) if $DBI::errstr;
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
		wf->config->{dbauth},
		{InactiveDestroy=>1,pg_enable_utf8=>0}
	);
	Catalyst::Exception->throw($DBI::errstr) unless $dbh;
}

sub disconnect
{
	$dbh->disconnect if $dbh;
	undef $dbh;
}

sub connected
{
	return $dbh;
}

sub pg_pid;
sub pg_pid()
{
	db::connect() unless $dbh;
	return $dbh->{pg_pid};
}

sub selectval_scalar
{
	my $row=db::selectrow_arrayref(@_);
	return undef unless $row;
	return $row->[0];
}

sub setv1
{
	my ($v1,$r,$v2)=@_;
	
	db::do("update data set v1=? where r =? and v2=?",undef,$v1,$r,$v2)>0
		or db::do("insert into data (v1,r,v2) values (?,?,?)",undef,$v1,$r,$v2);
}

sub setv2
{
	my ($v1,$r,$v2)=@_;
	
	db::do("update data set v2=? where r =? and v1=?",undef,$v2,$r,$v1)>0
		or db::do("insert into data (v1,r,v2) values (?,?,?)",undef,$v1,$r,$v2);
}
1;
