package wfbase::Controller::auth;
use Moose;
use namespace::autoclean;
use utf8;

BEGIN {extends 'Catalyst::Controller::FormBuilder'; }

=head1 NAME

wfbase::Controller::auth - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index

=cut

sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->response->body('Matched wfbase::Controller::auth in auth.');
}

sub login :Local :Form
{
	my ( $self, $c ) = @_;
	my $form=$self->formbuilder;

	$form->field(name => 'username', label=>$c->config->{auth_strings}->{username_prompt}||'Имя входа');
	$form->field(name => 'password', label=>$c->config->{auth_strings}->{password_prompt}||'Пароль', type=>'password');
	$form->submit($c->config->{auth_strings}->{login_button}||'Вход');
	$form->method('post');
	$form->action('');

	my $env=$c->request->{env};
	my $body=$form->render();
	my $error="";
	if ( $form->submitted ) {
		if ($c->authenticate($c->req->parameters))
		{
			if ($c->check_any_user_role($c->config->{login_role}))
			{
				$c->response->redirect($env->{HTTP_X_SITE_ROOT}.'/');
				$c->response->redirect($c->flash->{redirect_after_login}) if defined $c->flash->{redirect_after_login};
				return;
			};
		}
		else
		{
			$error.=$c->config->{auth_strings}->{error}||"Неправильно введено имя входа или пароль<br>Попробуйте еще раз<br>Регистр букв учитывается и в имени и в пароле";
		};
	};
	if ($env->{HTTP_X_VERIFIED} eq 'SUCCESS')
	{
		my $uid;
		$uid=$1 if $env->{HTTP_X_CLIENT_S_DN} =~ /UID=([a-f0-9\-]{36})/i;
		my $user;
		$user=$c->model->authinfo_data({uid=>$uid}) if $uid;
		$body.=qq\<p>Продолжить как <a href="/">$user->{username}</a></p>\ if $user;
	};
	if ($c->user_exists and !$c->check_any_user_role($c->config->{login_role}))
	{
		$error.=sprintf $c->config->{auth_strings}->{forbidden}||"нет разрешения на вход для сотрудника %s",$c->user->{full_name}||$c->user->{username};
		$c->logout;
	};

	$body.=$c->stash->{error}=$error;
	$c->forward('wfbase::View::json') and return 1 if $env->{HTTP_ACCEPT}=~'application/json';
	$c->response->body($body);
}

sub logout :Local
{
	my ($self, $c) = @_;
	$c->logout;
	$c->response->redirect($c->request->{env}->{HTTP_X_SITE_ROOT}.'/auth/login');
}

=head1 AUTHOR

Pushkinsv

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

#__PACKAGE__->meta->make_immutable;

1;
