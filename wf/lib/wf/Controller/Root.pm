package wf::Controller::Root;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=head1 NAME

wf::Controller::Root - Root Controller for wf

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 index

The root page (/)

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

}

=head2 default

Standard 404 error page

=cut

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
	$c->stash->{template}='default.tt' unless -f wf->path_to('root')."/".$c->request->{action}.".tt";
}

sub end : ActionClass('RenderView')
{
	my ($self, $c) = @_;
	$c->{stash}->{form}//=$c->controller->formbuilder if ref($c->action)=~ /FormBuilder/;
	use Data::Dumper;
	$c->{stash}->{data}->{dump}=Dumper($c->stash->{data});
}

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
		$c->response->redirect('/auth/login');
		$c->flash->{redirect_after_login} = '/' . $c->req->path;
		return 0;
	};
    
	return 1;
}

=head1 AUTHOR

Pushkinsv

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
