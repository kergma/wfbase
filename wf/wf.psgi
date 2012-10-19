use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use wf;

*STDOUT=*STDERR;
my $app = wf->apply_default_middlewares(wf->psgi_app);
$app;

