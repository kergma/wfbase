package wf::Controller::ajapi;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

wf::Controller::ajapi - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path :Args
{
	my ( $self, $c , @a) = @_;

	$c->stash->{args}=[@a];
	$c->forward('View::json');
}



=encoding utf8

=head1 AUTHOR

spu,,,

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
