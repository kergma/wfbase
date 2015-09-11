use strict;
use warnings;
use Test::More;


use Catalyst::Test 'wf';
use wf::Controller::ajapi;

ok( request('/ajapi')->is_success, 'Request should succeed' );
done_testing();
