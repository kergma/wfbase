package web::Controller::Root;

use strict;
use warnings;
use parent 'Catalyst::Controller';

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

=head1 NAME

web::Controller::Root - Root Controller for web

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=cut

=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    # Hello World
}

sub default :Path {
    my ( $self, $c ) = @_;
    $c->response->body( 'Page not found' );
    $c->response->status(404);
    
}

=head2 end

Attempt to render a view, if needed.

=cut 

sub end : ActionClass('RenderView') {}

=head2 auto
=cut
sub auto :Private
{
	my ($self, $c) = @_;
	srand();
	if ($c->controller eq $c->controller('auth'))
	{
		return 1;
	};

	if (!$c->user_exists)
	{
		$c->log->debug('***Root::auto User not found, forwarding to /login');
		$c->response->redirect($c->uri_for('/auth/login'));
		$c->flash->{redirect_after_login} = '' . $c->req->uri;
		return 0;
	};
    
	return 1;
}

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
