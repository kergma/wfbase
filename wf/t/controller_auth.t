use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'wf' }
BEGIN { use_ok 'wf::Controller::auth' }

ok( request('/auth')->is_success, 'Request should succeed' );


