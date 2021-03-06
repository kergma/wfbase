package wfbase::View::page;
use Moose;
use namespace::autoclean;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
	TEMPLATE_EXTENSION => '.tt',
	render_die => 1,
	INCLUDE_PATH => $wfbase::roots,
	WRAPPER => 'page.tt',
	EVAL_PERL=>1,
	RECURSION=>1,
	POST_CHOMP=>1,
	TRIM=>1,
	ENCODING => 'utf-8',
);

=head1 NAME

wfbase::View::page - TT View for wfbase

=head1 DESCRIPTION

TT View for wfbase.

=head1 SEE ALSO

L<wfbase>

=head1 AUTHOR

Pushkinsv

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
