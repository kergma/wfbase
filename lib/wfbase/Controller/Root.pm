package wfbase::Controller::Root;
use Moose;
use namespace::autoclean;
use utf8;
no warnings 'uninitialized';

BEGIN { extends 'Catalyst::Controller' }

#
# Sets the actions in this controller to be registered with no prefix
# so they function identically to actions created in MyApp.pm
#
__PACKAGE__->config(namespace => '');

=head1 NAME

wfbase::Controller::Root - Root Controller for wfbase

=head1 DESCRIPTION

[enter your description here]

=head1 METHODS

=head2 index

The root page (/)

=cut

sub index :Path :Args(0)
{
	my ( $self, $c ) = @_;
	return $c->forward($c->config->{root_forward}) if $c->config->{root_forward};
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
	if (!$c->sessionid and $c->req->{parameters}->{sessionid})
	{
		$c->_sessionid($c->req->{parameters}->{sessionid});
		$c->_load_session();
	};
}

sub end : ActionClass('RenderView')
{
	my ($self, $c) = @_;
	$c->stash->{template}='swalker.tt' unless defined $c->stash->{template} or -f $c->path_to('root')."/".$c->action->{reverse}.".tt";
	$c->stash->{stash}=$c->stash;
	if ($c->stash->{formbuilder})
	{
		$c->stash->{FormBuilder}->fieldsubs(1);
		$c->stash->{formbuilder}->{display}={order=>[keys %{$c->stash->{FormBuilder}->{tmplvar}}]} unless defined $c->stash->{formbuilder}->{display};
		$c->stash->{formbuilder}->{form}=$c->stash->{FormBuilder} unless defined $c->stash->{formbuilder}->{form};
	};
	$c->stash->{dump}=DDP::np($c->stash) if $c->check_any_user_role('Разработчик','developer');
	if (defined $c->stash->{snippet} && $c->stash->{snippet})
	{
		$c->forward($c->view('snippet'));
		delete $c->stash->{$_} foreach grep {$_ ne $c->stash->{snippet}} grep {defined $c->stash->{$c->stash->{snippet}}} keys %{$c->stash};
	};
	$c->response->headers->header('Access-Control-Allow-Origin'=>'*');
}

sub auto :Private
{
	my ($self, $c) = @_;
	srand();
	$c->stash->{version}=$wfbase::VERSION;
	$c->stash->{systitle}=$c->config->{systitle};
	if ($c->controller eq $c->controller('auth'))
	{
		return 1;
	};
	return 1 if $c->{request}->{action} eq 'pki';
	
	my $env=$c->request->{env};
	if (!$c->user_exists and $env->{HTTP_X_VERIFIED} eq 'SUCCESS')
	{
		my $uid;
		$uid=$1 if $env->{HTTP_X_CLIENT_S_DN} =~ /UID=([a-f0-9\-]{36})/i;
		$c->authenticate({uid=>$uid,password=>'***'}) if $uid;
	};

	if (!$c->user_exists and $c->controller eq $c->controller('ajapi'))
	{
		$c->stash->{error}='not authenticated';
		$c->forward('wfbase::View::json');
		return 0;
	};
	return 1 if grep {my $l=$_; grep {$l eq $_} @{$c->config->{public_pages}}} ($c->action->{reverse},$c->request->{env}->{PATH_INFO});

	$c->model('dbcon'); # make dbcon accept context
	eval{$c->model->update_user($c)};
	if (!$c->user_exists)
	{
		$c->response->redirect($env->{HTTP_X_SITE_ROOT}.'/auth/login');
		$c->flash->{redirect_after_login} = $env->{HTTP_X_SITE_ROOT}.'/' . $c->req->path;
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
