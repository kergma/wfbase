package wf::Controller::Root;

use strict;
use warnings;
use parent 'Catalyst::Controller';

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config->{namespace} = '';

=head1 NAME

wf::Controller::Root - Root Controller for wf

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

sub begin :Private
{
	my ($self, $c) = @_;
	$c->stash->{template}='swalker.tt' unless -f wf->path_to('root')."/".$c->request->{action}.".tt";
}

sub end : ActionClass('RenderView')
{
	my ($self, $c) = @_;
	$c->{stash}->{stash}=$c->{stash};
	if ($c->stash->{formbuilder})
	{
		$c->{stash}->{FormBuilder}->fieldsubs(1);
		$c->{stash}->{formbuilder}->{display}={order=>[keys %{$c->{stash}->{FormBuilder}->{tmplvar}}]} unless defined $c->{stash}->{formbuilder}->{display};
		$c->{stash}->{formbuilder}->{form}=$c->{stash}->{FormBuilder} unless defined $c->{stash}->{formbuilder}->{form};
	};
	eval {
		use Data::Dumper;
		$Data::Dumper::Sortkeys=sub {
			my ($hash) = @_;
			return [grep {!/FormBuilder/} keys %$hash];
		};
		undef $Data::Dumper::Sortkeys if defined $c->{stash}->{fulldump} && $c->{stash}->{fulldump};

		$c->{stash}->{dump}=Dumper($c->stash);
	} if $c->check_any_user_role('разработчик');
}

=head2 auto
=cut
sub auto :Private
{
	my ($self, $c) = @_;
	srand();
	$c->stash->{version}=$wf::VERSION;
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
