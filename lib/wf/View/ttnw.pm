package wf::View::ttnw;

use strict;
use base 'Catalyst::View::TT';

__PACKAGE__->config(
	TEMPLATE_EXTENSION => '.tt',
	INCLUDE_PATH => ["$wfbase::base/root","$wfbase::home/root"],
	EVAL_PERL=>1,
	RECURSION=>1,
	POST_CHOMP=>1,
	TRIM=>1,
	ENCODING => 'utf-8',
);

=head1 NAME

wf::View::ttnw - TT without wrapper View for wf 

=head1 DESCRIPTION

TT View for wf. 

=head1 AUTHOR

=head1 SEE ALSO

L<wf>

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
