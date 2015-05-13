package wf::View::json;

use strict;
use base 'Catalyst::View::JSON';

use JSON;
use Encode;

sub encode_json
{
	my($self, $c, $data) = @_;
	decode("utf8",to_json($data,{utf8=>0}));
}

=head1 NAME

wf::View::json - Catalyst JSON View

=head1 SYNOPSIS

See L<wf>

=head1 DESCRIPTION

Catalyst JSON View.

=head1 AUTHOR

spu,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
