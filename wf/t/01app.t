use strict;
use warnings;
use Test::More tests => 2;

BEGIN { use_ok 'Catalyst::Test', 'wf' }

ok( request('/')->is_success, 'Request should succeed' );
