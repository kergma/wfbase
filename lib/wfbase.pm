package wfbase;
use Moose;
use namespace::autoclean;

use Catalyst::Runtime 5.80;

# Set flags and add plugins for the application.
#
# Note that ORDERING IS IMPORTANT here as plugins are initialized in order,
# therefore you almost certainly want to keep ConfigLoader at the head of the
# list if you're using it.
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
	ConfigLoader
	Static::Simple
	Authentication
	Authorization::Roles
	Session
	Session::Store::FastMmap
	Session::State::Cookie
	Cache
	+wfbase::Plugin::sloc
/;

extends 'Catalyst';

use FindBin;
use File::Basename;
our $home=$FindBin::Bin;
our $base=Catalyst::Utils::home('wfbase');

our $VERSION=[];
use Cwd;
my $wd=cwd();
foreach my $d ($home, $base)
{
	chdir $d;
	use Encode 'decode_utf8';
	my $gitlog=decode_utf8(`git log -1 --date=short`);
	my $v={};
	($v->{commit},$v->{date},$v->{msg})=($1,$2,$3) if $gitlog =~ /commit (.{7}).*Date:\s+(.{10}).*[\r\n]\s*(.*?)[\r\n]/ms;
	push @$VERSION,$v;
};
chdir $wd;

use File::Find;
our $roots;
find({wanted=>sub{return unless -d $File::Find::name and basename($File::Find::name) eq 'root';push @$roots, $File::Find::name; }},$wfbase::home);

push @$VERSION, {commit=>[sort {$b->{date} cmp $a->{date}} @$VERSION]->[0]->{date}};

use DDP filters=>{ 'CGI::FormBuilder' => sub {"{CGI::FormBuilder skipped}"} };

# Configure the application.
#
# Note that settings in wfbase.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with an external configuration file acting as an override for
# local deployment.

__PACKAGE__->config(
	# Disable deprecated behavior needed by old applications
	disable_component_resolution_regex_fallback => 1,
	enable_catalyst_header => 1, # Send X-Catalyst header
	default_view => 'page',
	base_home => $base,
	home => $home,
	root => "$home/root",
);

__PACKAGE__->config->{'Plugin::ConfigLoader'} = {
		driver => {'General' => { -UTF8 => 1 } },
};

__PACKAGE__->config(
	'Plugin::Static::Simple' => { dirs=>['s'],include_path => $roots },
);

__PACKAGE__->config->{'Plugin::Authentication'} =
{
	use_session => 1,
	realms =>
	{
		default =>
		{
			credential =>
			{
				class => 'Password',
				password_field=>'password',
				password_type=>'clear'
			},
			store =>
			{
				class => 'dbcon'
			}

		}
	}
};

__PACKAGE__->config->{"Plugin::Session"} =
{
	unlink_on_exit=>0
};

# Start the application
#__PACKAGE__->setup();


=head1 NAME

wfbase - Catalyst based application

=head1 SYNOPSIS

    script/wf_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<wfbase::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Pushkinsv

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
