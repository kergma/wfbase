package wf::Model::pki;
use Moose;
use namespace::autoclean;

use File::Slurp;
use File::Temp ':POSIX';
use Date::Parse;
use Date::Format;
use X500::DN;

no warnings 'uninitialized';

extends 'Catalyst::Model';

=head1 NAME

wf::Model::pki - Catalyst Model

=head1 DESCRIPTION

Catalyst Model.

=head1 AUTHOR

spu,,,

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

sub gen_pkey
{
	my $self=shift;
	my %h=@_>1?@_:(id=>shift);
	my $a=ref $h{id} eq 'HASH'?$h{id}:\%h;

	my $pp="";
	$pp="-pass pass:$a->{passphrase1} -des3" if $a->{passphrase1};
	my $out=`openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:1024 $pp 2>&1`;
	$out=~s/(.*?)(-+BEGIN)/$2/s and $a->{out}=$1;
	$a->{error}=$out if $out=~/error/si;
	$a->{content}=$out unless $a->{error};
	$a->{type}='key';
	return $a;

}

sub read_object
{
	my $self=shift;
	my %h=@_>1?@_:(record=>shift);
	my $a=ref $h{record} eq 'HASH'?$h{record}:\%h;
	eval{ $a->{id}||=db::selectval_scalar("select id from pki where record=? order by id desc limit 1",undef,$a->{record}) if $a->{record};  };
	eval{ $a->{content}=db::selectval_scalar("select content from pki where id=?",undef,$a->{id}) if $a->{id}; };
	eval{ $a->{record}=db::selectval_scalar("select record from pki where id=?",undef,$a->{id}) if $a->{id}; };
	return $a unless $a->{content};
	$a->{type}='crt' if $a->{content} =~ /CERTIFICATE---/s;
	$a->{type}='csr' if $a->{content} =~ /REQUEST---/s;
	$a->{type}='key' if $a->{content} =~ /PRIVATE KEY/s;
	$a->{encrypted}=1 if $a->{content} =~ /ENCRYPTED/s;

	$a->{cdump}=`echo '$a->{content}' |openssl req -text -nameopt RFC2253` if $a->{type} eq 'csr';
	$a->{cdump}=`echo '$a->{content}' |openssl x509 -text -nameopt RFC2253` if $a->{type} eq 'crt';
	
	if ($a->{cdump})
	{
		my $d=parse_cerdump($a->{cdump});
		@$a{keys %$d}=values %$d;
	};

	$a->{owner}=db::selectval_scalar("select v2 from data where r ~ '^(ключ|сертификат|запрос) .*PKI .*' and v1=? order by id limit 1",undef,$a->{record}),
	$a->{name}=db::selectval_scalar("select v1 from data where r like 'наименование %PKI' and v2=? order by id limit 1",undef,$a->{record}),

	$a->{pkey}=read_object($self,id=>db::selectval_scalar("select key from pki where id=?",undef,$a->{id}));

	return $a;
}

sub read_owner
{
       my $self=shift;
       my $record=shift;
       my ($d,$t)=$cc->model->recdef($record);
       return {
               id=>$t?$record:undef,
               name=>$d,
               type=>$t,
               pkey=>read_object($self,db::selectval_scalar("select v1 from data where r like 'ключ PKI %' and v2=? order by id limit 1",undef,$record)),
       };

}


sub store_pkey
{
	my $self=shift;
	my %h=@_>1?@_:(id=>shift);
	my $d=ref $h{id} eq 'HASH'?$h{id}:\%h;

	db::do("update data set v1=? where r = 'наименование ключа PKI' and v2=?",undef,$d->{name},$d->{id})>0
		or db::do("insert into data (v1,r,v2) values (?,'наименование ключа PKI',?)",undef,$d->{name},$d->{id});

	my $r=db::selectval_scalar("select r from data where r ~ '^(наименование|ФИО)' and v2=?",undef,$d->{owner});
	$r=~s/^(наименование|ФИО)/ключ PKI/;

	db::do("update data set v2=? where r =? and v1=?",undef,$d->{owner},$r,$d->{id})>0
		or db::do("insert into data (v1,r,v2) values (?,?,?)",undef,$d->{id},$r,$d->{owner});

	db::do("update pki set type=? where record=? and content=?",undef,$d->{type},$d->{id},$d->{content})>0
		or db::do("insert into pki (record,type,content) values (?,?,?)",undef,$d->{id},$d->{type},$d->{content});
		
	return $d;
}

sub store_cert
{
	my $self=shift;
	my %h=@_>1?@_:(id=>shift);
	my $d=ref $h{id} eq 'HASH'?$h{id}:\%h;

	my $defr=$d->{type} eq 'csr'?'запроса сертификата PKI':'сертификата PKI';
	db::do("update data set v1=? where r = 'наименование $defr' and v2=?",undef,$d->{name},$d->{record})>0
		or db::do("insert into data (v1,r,v2) values (?,'наименование $defr',?)",undef,$d->{name},$d->{record});

	$defr=$d->{type} eq 'csr'?'запрос сертификата PKI':'сертификат PKI';
	my $r=db::selectval_scalar("select r from data where r ~ '^(наименование|ФИО)' and v2=?",undef,$d->{owner});
	$r=~s/^(наименование|ФИО)/$defr/;

	db::do("update data set v2=? where r =? and v1=?",undef,$d->{owner},$r,$d->{record})>0
		or db::do("insert into data (v1,r,v2) values (?,?,?)",undef,$d->{record},$r,$d->{owner});

	db::do("update pki set type=?, key=?, signet=? where record=? and content=?",undef,$d->{type},$d->{pkey}->{id},$d->{signet}->{id},$d->{record},$d->{content})>0
		or db::do("insert into pki (record,type,content,key,signet) values (?,?,?,?,?)",undef,$d->{record},$d->{type},$d->{content},$d->{pkey}->{id},$d->{signet}->{id});
}

sub create_request
{
	my $self=shift;
	my %h=@_>1?@_:(record=>shift);
	my $a=ref $h{record} eq 'HASH'?$h{record}:\%h;
	
	my $keyfile=tmpnam();
	write_file($keyfile,$a->{pkey}->{content});
	$a->{error}="Ошибка записи файла ключа $keyfile" and return $a unless -f $keyfile;


	my $cmd="openssl req -new -subj '$a->{subj}' -utf8 -key $keyfile -passin pass:$a->{passphrase}";
	my $out=`$cmd 2>&1`;
	unlink $keyfile;

	$a->{error}={error=>'не удалость создать запрос сертификата',pre=>$out,display=>{order=>[qw/error pre/]}} if $out =~ /error/mi;
	return $a if $a->{error};

	$a->{type}='csr';
	$a->{success}=$a->{content}=$out unless $a->{error};

	store_cert($self,$a);
		
	return $a;
}

sub create_cert
{
	my $self=shift;
	my %h=@_>1?@_:(record=>shift);
	my $a=ref $h{record} eq 'HASH'?$h{record}:\%h;
	
	my $req=$a->{req}->{content};

	my $keyfile=tmpnam();
	write_file($keyfile,$a->{signet}->{pkey}->{content});
	$a->{error}="Ошибка записи файла ключа $keyfile" and return $a unless -f $keyfile;

	my $cafile=tmpnam();
	write_file($cafile,$a->{signet}->{content});
	$a->{error}="Ошибка записи файла сертификата $cafile" and unlink $keyfile and return $a unless -f $cafile;

	my $out;
	if ($a->{req}->{id} eq $a->{signet}->{id})
	{
		my $cmd="echo '$req' | openssl x509 -req -days $a->{days} -signkey $keyfile -passin pass:$a->{passphrase}";
		$out=`$cmd 2>&1`;
	};
	unless ($out)
	{
		my $serial=time();
		my $cmd="echo '$req' | openssl x509 -days $a->{days} -req -CA $cafile -CAkey $keyfile -passin pass:$a->{passphrase} -set_serial $serial";
		$out=`$cmd 2>&1`;
	};
	unlink $keyfile, $cafile;

	$a->{error}={error=>'не удалость создать сертификат',pre=>$out,display=>{order=>[qw/error pre/]}} if $out =~ /error/mi;
	return $a if $a->{error};

	$a->{type}='crt';
	$a->{success}=$a->{content}=$out unless $a->{error};
	$a->{content}=~s/.*(-----BEGIN)/$1/ms;
	$a->{pkey}=$a->{req}->{pkey};

	store_cert($self,$a);
		
	return $a;
}

sub parse_cerdump
{
	my $dump=shift;
	my $data={};
	$dump=~/Not Before: (.*)$/m and $data->{notBefore}=str2time($1);
	$dump=~/Not After : (.*)$/m and $data->{notAfter}=str2time($1);
	$dump=~/Subject: (.*)$/m and $data->{subject}=X500::DN->ParseRFC2253($1);
	$dump=~/Issuer: (.*)$/m and $data->{issuer}=X500::DN->ParseRFC2253($1);
	$data->{sh}={map {$_->getAttributeTypes()=>$_->getAttributeValue($_->getAttributeTypes())} @{$data->{subject}}} if $data->{subject};
	$data->{ih}={map {$_->getAttributeTypes()=>$_->getAttributeValue($_->getAttributeTypes())} @{$data->{issuer}}} if $data->{issuer};
	return $data;
}

1;
