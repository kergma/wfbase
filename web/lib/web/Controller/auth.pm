package web::Controller::auth;

use strict;
use warnings;
use base 'Catalyst::Controller::FormBuilder';
use Data::Dumper;

=head1 NAME

web::Controller::auth - Catalyst Controller

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
	$form->method('post');

	my $body=$form->render();
        if ( $form->submitted ) {
            if ( $form->validate ) {
		if ($c->authenticate({username=>$form->field('username'),password=>$form->field('password')}))
		{
			$c->response->redirect($c->uri_for('/auth'));
			$c->response->redirect($c->flash->{redirect_after_login}) if defined $c->flash->{redirect_after_login};
			return;
		    $body.="authentication succeeded in default<br><pre>".Dumper($c);
		}
		else
		{
		    $body.="authentication failed in default<br>";
		}
            }
            else {
                $c->stash->{ERROR}          = "INVALID FORM";
                $c->stash->{invalid_fields} = [ grep { !$_->validate } $form->fields ];
            }
        }

    $c->response->body($body);
}
=head1 login
Форма входа в систему
=cut

sub logout :Local
{
	my ($self, $c) = @_;
	$c->logout;
	$c->response->redirect($c->uri_for($c->controller('auth')->action_for('index')));
}

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
