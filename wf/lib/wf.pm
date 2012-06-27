package wf;

use strict;
use warnings;

use Catalyst::Runtime '5.70';

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a Config::General file in the
#                 application's home directory
# Static::Simple: will serve static files from the application's root 
#                 directory

use parent qw/Catalyst/;
use Catalyst qw/
                ConfigLoader
                Static::Simple
		Authentication
		Authorization::Roles
		Session
		Session::Store::FastMmap
		Session::State::Cookie
		Cache
		/;
my $rev='';
'$Rev$' =~ /(\d+)/ and $rev=$1;

our $VERSION = "2.$rev";

use Cwd 'abs_path';
use lib abs_path($0)=~'/dev/'?"/home/worker/dev/lib":"/home/worker/lib";
use FindBin;
use lib "$FindBin::Bin/../../lib";
# Configure the application. 
#
# Note that settings in wf.conf (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

__PACKAGE__->config( name => 'wf', default_view => 'TT' );

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
				class => 'pp'
			}
			
		}
	}
};

__PACKAGE__->config->{"Plugin::Cache"} =
{
	backend =>
	{
		class => "Cache::FastMmap",
		expire_time => 300,
		enable_stats => 1,
		page_size => '1024k'
	},
};

# Start the application
__PACKAGE__->setup();


=head1 NAME

wf - Catalyst based application

=head1 SYNOPSIS

    script/wf_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<wf::Controller::Root>, L<Catalyst>

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;