package wf::View::page;
use Moose;
use namespace::autoclean;

extends 'Catalyst::View::TT';

__PACKAGE__->config(
	TEMPLATE_EXTENSION => '.tt',
	render_die => 1,
	INCLUDE_PATH => [wf->path_to('root')],
	WRAPPER => 'page.tt',
	EVAL_PERL=>1,
	RECURSION=>1,
);

=head1 NAME

wf::View::page - TT View for wf

=head1 DESCRIPTION

TT View for wf.

=head1 SEE ALSO

L<wf>

=head1 AUTHOR

Pushkinsv

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
