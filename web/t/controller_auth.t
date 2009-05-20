use strict;
use warnings;
use Test::More tests => 3;

BEGIN { use_ok 'Catalyst::Test', 'web' }
BEGIN { use_ok 'web::Controller::auth' }

ok( request('/auth')->is_success, 'Request should succeed' );


