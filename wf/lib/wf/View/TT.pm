package web::View::TT;

use strict;
use base 'Catalyst::View::TT';

__PACKAGE__->config(
	TEMPLATE_EXTENSION => '.tt',
	INCLUDE_PATH => [web->path_to('root')],
	WRAPPER => 'wrapper.tt'
);

=head1 NAME

web::View::TT - TT View for web

=head1 DESCRIPTION

TT View for web. 

=head1 AUTHOR

=head1 SEE ALSO

L<web>

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
