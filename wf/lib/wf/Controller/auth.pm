package wf::Controller::auth;

use strict;
use warnings;
use base 'Catalyst::Controller::FormBuilder';
use Data::Dumper;

no warnings 'uninitialized';

__PACKAGE__->config( 'Controller::FormBuilder' => {form_path => File::Spec->catfile( wf->path_to('root'))});

=head1 NAME

wf::Controller::auth - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut


=head2 index 

=cut

sub index :Path :Args(0)
{
	my ( $self, $c ) = @_;

	$c->response->body("user exists '".$c->user_exists()."' user '".$c->user."'<br>".Dumper($c->user));
}

=head1 login
Форма входа в систему
=cut

sub login :Local :Form
{
	my ( $self, $c ) = @_;
	my $form=$self->formbuilder;

	$form->field(name => 'username', label=>'Имя входа');
	$form->field(name => 'password', label=>'Пароль', type=>'password');
	$form->submit('Вход');
	$form->method('post');

	my $body=$form->render();
	if ( $form->submitted ) {
		if ( $form->validate ) {
			if ($c->authenticate({username=>$form->field('username'),password=>$form->field('password')}))
			{
				$c->response->redirect('/');
				$c->response->redirect($c->flash->{redirect_after_login}) if defined $c->flash->{redirect_after_login};
				return;
				$body.="authentication succeeded in default<br><pre>".Dumper($c);
			}
			else
			{
				$body.="Неправильно введено имя входа или пароль<br>Попробуйте еще раз<br>Регистр букв учитывается и в имени и в пароле";
			}
		}
		else {
			$c->stash->{ERROR}          = "INVALID FORM";
			$c->stash->{invalid_fields} = [ grep { !$_->validate } $form->fields ];
		}
	}
	if ($c->request->{env}->{HTTP_X_VERIFIED} eq 'SUCCESS')
	{
		my $uid;
		$uid=$1 if $c->request->{env}->{HTTP_X_CLIENT_S_DN} =~ /UID=([a-f0-9\-]{36})/i;
		my $user;
		$user=$c->model->authinfo_data({uid=>$uid}) if $uid;
		$body.=qq\<p>Продолжить как <a href="/">$user->{username}</a></p>\ if $user;
	};

	$c->response->body($body);
}
=head1 login
Форма входа в систему
=cut

sub logout :Local
{
	my ($self, $c) = @_;
	$c->logout;
	$c->response->redirect('/auth/login');
}

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
