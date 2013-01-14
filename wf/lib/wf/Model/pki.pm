package wf::Model::pki;
use Moose;
use namespace::autoclean;

use File::Slurp;

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

my $pkidir="$ENV{HOME}/pki";
mkdir $pkidir unless -d $pkidir;

my $cc;

sub ACCEPT_CONTEXT
{
	my ($self,$c,@args)=@_;

	$cc=$c;
	return $self;
}


sub read_pkey
{
	my ($self,%a)=@_;

	$a{basename}="$a{id}.key" unless $a{file};
	$a{file}="$pkidir/$a{basename}" unless $a{file};
	$a{content}=read_file($a{file}) unless $a{content};
	$a{decrypted_content}=`echo '$a{content}' | openssl pkey -passin pass:$a{passphrase} 2>&1`;
	$a{error}=$a{decrypted_content} and delete $a{decrypted_content} if $a{decrypted_content}=~/error/i;
	$a{passphrase_protected}=1 if $a{error}=~/bad password|bad decrypt/i;
	$a{passphrase_protected}=1 if !$a{error} and $a{passphrase};
	my $pkd=$cc->model->read_pkey($a{id});
	@a{keys %$pkd}=values %$pkd;
	
	return \%a;
}

1;
